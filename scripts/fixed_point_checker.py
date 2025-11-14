#!/usr/bin/env python3
"""
Fixed-Point Arithmetic Checker for Verilog

This script analyzes fixed-point arithmetic comments in Verilog files
and checks for correctness (no overflow, correct types).

Usage:
    python fixed_point_checker.py <verilog_file>

The script looks for comments in the format:
    // Type result = expression

Where Type is like U8F0, S12F11, etc., and expression contains
fixed-point arithmetic operations.

Supported operations:
- Addition/Subtraction: +
- Multiplication: *
- Right shift: >>>
- Concatenation: {{width, value}}
- Type casting: $signed()
- Functions: abs()
- Array indexing: var[index]
- Literals: 12'sd1024, 24'h1000000, etc.
"""

import re
import sys
import traceback
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
from lark import Lark, Transformer, Token, v_args
from lark.exceptions import VisitError


@dataclass
class FixedPointType:
    """Represents a fixed-point type: signed/unsigned, total bits, fractional bits"""
    signed: bool
    total_bits: int
    frac_bits: int

    @property
    def int_bits(self) -> int:
        """Integer bits (including sign bit for signed types)"""
        return self.total_bits - self.frac_bits

    def __str__(self):
        sign = 'S' if self.signed else 'U'
        return f"{sign}{self.total_bits}F{self.frac_bits}"

    def __repr__(self):
        return self.__str__()

    def __eq__(self, other):
        if not isinstance(other, FixedPointType):
            return False
        return self.signed == other.signed and self.total_bits == other.total_bits and self.frac_bits == other.frac_bits


class NumberType(FixedPointType):
    """Represents a number literal with its value"""
    def __init__(self, value: str, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.value = value


# Lark grammar for fixed-point expressions
EXPRESSION_GRAMMAR = r"""
start: expr

expr: term (add_op term)*

term: factor (mul_op factor)*

factor: atom (shift_op atom)*

atom: number
    | ident
    | type_annotated_expr
    | paren_expr
    | concatenation
    | abs_expr
    | signed_expr
    | array_access
    | bit_negate
    | TYPE

type_annotated_expr: TYPE ident
                   | TYPE array_access
                   | TYPE number

number: VERILOG_LITERAL | DECIMAL_NUMBER
ident: IDENT
paren_expr: "(" expr ")"
concatenation: replication | "{" expr ("," expr)* "}"
replication: "{" expr "{" expr "}" "}"
abs_expr: ABS "(" expr ")"
signed_expr: SIGNED "(" expr ")"
array_access: IDENT "[" expr "]" | IDENT "[" expr ":" expr "]"
bit_negate: "~" expr

add_op: ADD | SUBTRACT
mul_op: MULTIPLY | DIVIDE
shift_op: SHL | SHR | SHRS

TYPE.10: /[US]\d+F\d+/
IDENT: /[a-zA-Z_][a-zA-Z0-9_]*/
VERILOG_LITERAL: /\d+'(b|d|h|sd)\w+/
DECIMAL_NUMBER: /\d+(\.\d+)?/
ABS.20: "abs"
SIGNED.20: "$signed" | "signed"
ADD: "+"
SUBTRACT: "-"
MULTIPLY: "*"
DIVIDE: "/"
SHL: "<<"
SHR: ">>"
SHRS: ">>>"

%import common.WS
%ignore WS
"""
class TypeTransformer(Transformer):
    """Transformer that evaluates types from the parse tree"""

    def __init__(self, checker):
        self.checker = checker
        self.ops = None
        self.annotation_issues = []

    @v_args(inline=True)
    def start(self, expr):
        type_, text = expr
        assert isinstance(type_, FixedPointType), f"start: expr should be (FixedPointType, str), got {type(expr)}"
        return type_, text

    @v_args(inline=True)
    def expr(self, *args):
        if len(args) == 1:
            type_, text = args[0]
            assert isinstance(type_, FixedPointType), f"expr: arg should be FixedPointType, got {type(type_)}"
            return type_, text
        elif len(args) % 2 == 1:
            result_type, result_text = args[0]
            for i in range(1, len(args), 2):
                op = args[i]
                right_type, right_text = args[i+1]
                if op == '+' or op == '-':
                    result_type = self.ops.add_types(result_type, right_type, op)
                    result_text = f"({result_text} {op} {right_text})"
                else:
                    raise ValueError(f"Unknown expr op: {op}")
            return result_type, result_text
        raise ValueError(f"Invalid expr args: {args}")

    @v_args(inline=True)
    def term(self, *args):
        if len(args) == 1:
            type_, text = args[0]
            assert isinstance(type_, FixedPointType), f"term: arg should be FixedPointType, got {type(type_)}"
            return type_, text
        elif len(args) % 2 == 1:
            result_type, result_text = args[0]
            for i in range(1, len(args), 2):
                op = args[i]
                right_type, right_text = args[i+1]
                if op == '*':
                    result_type = self.ops.multiply_types(result_type, right_type)
                    result_text = f"({result_text} {op} {right_text})"
                elif op == '/':
                    result_type = self.ops.divide_types(result_type, right_type)
                    result_text = f"({result_text} {op} {right_text})"
                else:
                    raise ValueError(f"Unknown term op: {op}")
            return result_type, result_text
        raise ValueError(f"Invalid term args: {args}")

    @v_args(inline=True)
    def factor(self, *args):
        # args = atom1, shift_op1, atom2, shift_op2, ...
        atoms = []
        ops = []
        i = 0
        while i < len(args):
            if i % 2 == 0:
                # atom
                atom_type, atom_text = args[i]
                assert isinstance(atom_type, FixedPointType), f"factor: atom should be FixedPointType, got {type(atom_type)}"
                atoms.append((atom_type, atom_text))
            else:
                # shift_op
                op = args[i]
                if isinstance(op, str):
                    ops.append(op)
                else:
                    assert hasattr(op, 'value'), f"factor: shift_op should be str or Token, got {type(op)}"
                    ops.append(op.value)
            i += 1

        # Now combine atoms with ops
        result_type, result_text = atoms[0]
        for op, (atom_type, atom_text) in zip(ops, atoms[1:]):
            if isinstance(atom_type, NumberType) and atom_type.value == 0:
                self.annotation_issues.append(f"Shift by 0 is redundant: {op} 0")
            if op == '<<':
                result_type = self.ops.shift_left_types(result_type, atom_type)
                result_text = f"({result_text} {op} {atom_text})"
            elif op == '>>':
                result_type = self.ops.shift_right_unsigned_types(result_type, atom_type)
                result_text = f"({result_text} {op} {atom_text})"
            elif op == '>>>':
                result_type = self.ops.shift_right_signed_types(result_type, atom_type)
                result_text = f"({result_text} {op} {atom_text})"
            else:
                raise ValueError(f"Unknown shift op: {op}")
        return result_type, result_text

    @v_args(inline=True)
    def atom(self, alternative):
        type_, text = alternative
        assert isinstance(type_, FixedPointType), f"atom: alternative should be FixedPointType, got {type(type_)}"
        return type_, text

    @v_args(inline=True)
    def type_annotated_expr(self, type_arg, expr):
        # type_arg can be either a Token (from TYPE) or a tuple (type, text) from processed TYPE
        if isinstance(type_arg, tuple):
            # Already processed TYPE token
            declared_type, type_text = type_arg
        else:
            # Raw TYPE token
            assert hasattr(type_arg, 'value'), f"type_annotated_expr: type_arg should be Token or tuple, got {type(type_arg)}"
            declared_type = self.checker.parse_type(type_arg.value)
            type_text = type_arg.value

        sub_type, sub_text = expr
        assert isinstance(sub_type, FixedPointType), f"type_annotated_expr: sub_type should be FixedPointType, got {type(sub_type)}"

        if isinstance(sub_type, FixedPointType):
            # For annotated literals (numbers), use the declared type
            # For annotated identifiers/arrays, check consistency
            if isinstance(sub_type, NumberType):
                # This is likely an inferred integer literal, override with declared
                return declared_type, f"{type_text} {sub_text}"
            else:
                # Check if declared matches computed
                if declared_type != sub_type:
                    self.annotation_issues.append(f"Type annotation mismatch for '{sub_text}': declared {declared_type}, computed {sub_type}")
                return sub_type, f"{type_text} {sub_text}"
        else:
            raise ValueError(f"Type annotation expr is {type(sub_type)}, not FixedPointType")

    @v_args(inline=True)
    def number(self, token):
        if isinstance(token, tuple):
            # Already processed by NUMBER method
            return token
        else:
            assert hasattr(token, 'value'), f"number: token should be Token or tuple, got {type(token)}"
            # Handle Verilog literals and decimal numbers
            expr = token.value
            # Handle Verilog literals and decimal numbers
            if '.' in expr:
                try:
                    value = float(expr)
                    return NumberType(value, False, None, None), expr
                except:
                    raise ValueError(f"Invalid decimal number: {expr}")
            else:
                num_match = re.match(r'(\d+)(?:\'(d|sd|h|b)(\w+))?', expr)
                if num_match:
                    size_str, format_type, value = num_match.groups()
                    size = int(size_str)
                    if format_type == 'h':
                        value = int(value, 16)
                    elif format_type == 'd':
                        value = int(value, 10)
                    elif format_type == 'b':
                        value = int(value, 2)
                    elif format_type == 'sd':
                        value = int(value, 10)
                        if value > (1 << (size - 1)) - 1:
                            value -= (1 << size)
                    else:
                        value = int(size_str, 10)
                    if format_type:
                        if format_type == 'sd':
                            return NumberType(value, True, size, 0), expr
                        else:
                            return NumberType(value, False, size, 0), expr
                    else:
                        return NumberType(value, False, 32, 0), expr

                raise ValueError(f"Unsupported number format: {expr}")

    @v_args(inline=True)
    def ident(self, token):
        if isinstance(token, tuple):
            ident_type, ident_text = token
            name = ident_text.strip()
            if name in self.checker.known_types:
                return self.checker.known_types[name], name
            raise FixedPointError(f"Unknown identifier: {name}")
        else:
            assert hasattr(token, 'value'), f"ident: token should be Token or tuple, got {type(token)}"
            name = token.value.strip()
            if name in self.checker.known_types:
                return self.checker.known_types[name], name
            raise FixedPointError(f"Unknown identifier: {name}")

    @v_args(inline=True)
    def paren_expr(self, expr):
        type_, text = expr
        assert isinstance(type_, FixedPointType), f"paren_expr: expr should be FixedPointType, got {type(type_)}"
        return type_, f"({text})"

    @v_args(inline=True)
    def abs_expr(self, abs_token, expr):
        if isinstance(abs_token, tuple):
            abs_type, abs_text = abs_token
        else:
            assert hasattr(abs_token, 'value'), f"abs_expr: abs_token should be Token or tuple, got {type(abs_token)}"
            abs_text = abs_token.value
        if self.ops.verilog:
            self.annotation_issues.append(f"'abs' is not standard Verilog.")
        type_, text = expr
        assert isinstance(type_, FixedPointType), f"abs_expr: expr should be FixedPointType, got {type(type_)}"
        return FixedPointType(False, type_.total_bits, type_.frac_bits), f"abs({text})"

    @v_args(inline=True)
    def signed_expr(self, signed_token, expr):
        if isinstance(signed_token, tuple):
            signed_type, signed_text = signed_token
        else:
            assert hasattr(signed_token, 'value'), f"signed_expr: signed_token should be Token or tuple, got {type(signed_token)}"
            signed_text = signed_token.value
        if signed_text == 'signed':
            self.annotation_issues.append(f"Use of 'signed' without $ is not standard Verilog.")
        type_, text = expr
        assert isinstance(type_, FixedPointType), f"signed_expr: expr should be FixedPointType, got {type(type_)}"
        return FixedPointType(True, type_.total_bits, type_.frac_bits), f"$signed({text})"

    @v_args(inline=True)
    def array_access(self, *args):
        if len(args) == 2:
            # Array access: IDENT "[" expr "]"
            ident_token, index_expr = args
            ident_name = ident_token.value if hasattr(ident_token, 'value') else ident_token[1]
            index_type, index_text = index_expr
            type_ = self._handle_array_access(ident_name, index_type)
            return type_, f"{ident_name}[{index_text}]"
        elif len(args) == 3:
            # Bit slice: IDENT "[" expr ":" expr "]"
            ident_token, start_expr, end_expr = args
            ident_name = ident_token.value if hasattr(ident_token, 'value') else ident_token[1]
            start_type, start_text = start_expr
            end_type, end_text = end_expr
            type_ = self._handle_bit_slice(ident_name, start_type, end_type)
            return type_, f"{ident_name}[{start_text}:{end_text}]"
        else:
            raise ValueError(f"Unexpected number of args for array_access: {len(args)}")

    def _handle_array_access(self, array_name: str, index_expr) -> FixedPointType:
        """Handle array access like arr[idx] - returns the element type of the array"""
        if array_name in self.checker.known_types:
            # For arrays, the type is the same as the base type
            # (assuming 1D arrays for now)
            return self.checker.known_types[array_name]
        else:
            raise ValueError(f"Unknown array: {array_name}")

    def _handle_bit_slice(self, array_name: str, start_type, end_type) -> FixedPointType:
        """Handle bit slice like arr[msb:lsb] - returns the sliced type"""
        if array_name not in self.checker.known_types:
            raise ValueError(f"Unknown array: {array_name}")

        base_type = self.checker.known_types[array_name]

        # Calculate width from start and end
        if isinstance(start_type, NumberType) and isinstance(end_type, NumberType):
            start_val = int(start_type.value)
            end_val = int(end_type.value)
            width = start_val - end_val + 1
            if width <= 0:
                raise ValueError(f"Invalid bit slice width: {width} for {array_name}[{start_val}:{end_val}]")
        else:
            # If not constants, can't determine width, assume same as base or issue warning
            self.annotation_issues.append(f"Bit slice with non-constant indices: {array_name}[{start_type}:{end_type}]")
            width = base_type.total_bits  # fallback

        return FixedPointType(base_type.signed, width, base_type.frac_bits)

    @v_args(inline=True)
    def concatenation(self, *args):
        # args = expr1, comma, expr2, comma, expr3, ..., rbrace
        # Extract the exprs as (type, text) tuples
        exprs = []
        texts = []
        i = 0
        while i < len(args) - 1:  # -1 for rbrace
            if isinstance(args[i], tuple):
                type_, text = args[i]
                exprs.append(type_)
                texts.append(text)
            else:
                # Handle non-tuple args if any, but shouldn't happen
                exprs.append(args[i])
                texts.append(str(args[i]))
            i += 1
            if i < len(args) - 1:
                # Skip comma - now it's a tuple too
                if isinstance(args[i], tuple):
                    comma_type, comma_text = args[i]
                else:
                    assert hasattr(args[i], 'value'), f"concatenation: comma {i} should be Token or tuple, got {type(args[i])}"
                i += 1  # skip comma

        # Compute the type
        total_width = 0
        last_signed = False
        last_frac = 0
        for arg in exprs:
            if isinstance(arg, FixedPointType):
                total_width += arg.total_bits
                last_signed = arg.signed
                last_frac = arg.frac_bits
            else:
                # Try to parse as number
                arg_str = str(arg)
                if "'d" in arg_str:
                    total_width += int(arg_str.split("'d")[0])
                elif "'b" in arg_str:
                    total_width += int(arg_str.split("'b")[0])
                elif arg_str.isdigit():
                    total_width += int(arg_str)
                else:
                    total_width += 32  # fallback

        return FixedPointType(last_signed, total_width, last_frac), f"{{{', '.join(texts)}}}"

    @v_args(inline=True)
    def bit_negate(self, e):
        type_, text = e
        assert isinstance(type_, FixedPointType), f"bit_negate: expr should be FixedPointType, got {type(type_)}"
        return type_, f"~{text}"

    @v_args(inline=True)
    def replication(self, count_expr, value_expr):
        # Replication {count{value}}
        count_type, count_text = count_expr
        value_type, value_text = value_expr

        # For replication, the result type has width = count * value_width
        # Signedness and fractional bits from the value
        if isinstance(count_type, NumberType) and isinstance(value_type, FixedPointType):
            count_value = count_type.value
            result_width = count_value * value_type.total_bits
            return FixedPointType(value_type.signed, result_width, value_type.frac_bits), "{" + count_text + "{" + value_text + "}}"
        else:
            # Fallback: assume width is large
            return FixedPointType(value_type.signed if isinstance(value_type, FixedPointType) else False, 32, 0), "{" + count_text + "{" + value_text + "}}"

    @v_args(inline=True)
    def add_op(self, token):
        if isinstance(token, tuple):
            op_type, op_text = token
            return op_text
        else:
            assert hasattr(token, 'value'), f"add_op: token should be Token or tuple, got {type(token)}"
            return token.value

    @v_args(inline=True)
    def mul_op(self, token):
        if isinstance(token, tuple):
            op_type, op_text = token
            return op_text
        else:
            assert hasattr(token, 'value'), f"mul_op: token should be Token or tuple, got {type(token)}"
            return token.value

    @v_args(inline=True)
    def shift_op(self, token):
        if isinstance(token, tuple):
            op_type, op_text = token
            return op_text
        else:
            assert hasattr(token, 'value'), f"shift_op: token should be Token or tuple, got {type(token)}"
            return token.value

    @v_args(inline=True)
    def TYPE(self, token):
        if isinstance(token, tuple):
            type_type, type_text = token
            type_ = self.checker.parse_type(type_text)
            return type_, type_text
        else:
            assert hasattr(token, 'value'), f"TYPE: token should be Token or tuple, got {type(token)}"
            type_ = self.checker.parse_type(token.value)
            return type_, token.value

    @v_args(inline=True)
    def NUMBER(self, token):
        if isinstance(token, tuple):
            num_type, num_text = token
            return num_type, num_text
        else:
            assert hasattr(token, 'value'), f"NUMBER: token should be Token or tuple, got {type(token)}"
            expr = token.value
            # Handle Verilog literals and decimal numbers
            if '.' in expr:
                try:
                    value = float(expr)
                    return NumberType(value, False, None, None), expr
                except:
                    raise ValueError(f"Invalid decimal number: {expr}")
            else:
                num_match = re.match(r'(\d+)(?:\'(d|sd|h)(\w+))?', expr)
                if num_match:
                    size_str, format_type, value = num_match.groups()
                    size = int(size_str)
                    if format_type == 'h':
                        value = int(value, 16)
                    elif format_type == 'd':
                        value = int(value, 10)
                    elif format_type == '2':
                        value = int(value, 2)
                    elif format_type == 'sd':
                        value = int(value, 10)
                        if value > (1 << (size - 1)) - 1:
                            value -= (1 << size)
                    else:
                        value = int(size_str, 10)
                    if format_type:
                        if format_type == 'sd':
                            return NumberType(value, True, size, 0), expr
                        else:
                            return NumberType(value, False, size, 0), expr
                    else:
                        return NumberType(value, False, 32, 0), expr

                raise ValueError(f"Unsupported number format: {expr}")

    @v_args(inline=True)
    def IDENT(self, token):
        if isinstance(token, tuple):
            ident_type, ident_text = token
            # Look up the identifier in known types
            if ident_text in self.checker.known_types:
                return self.checker.known_types[ident_text], ident_text
            else:
                raise FixedPointError(f"Unknown identifier: {ident_text}")
        else:
            assert hasattr(token, 'value'), f"IDENT: token should be Token or tuple, got {type(token)}"
            # Look up the identifier in known types
            if token.value in self.checker.known_types:
                return self.checker.known_types[token.value], token.value
            else:
                raise FixedPointError(f"Unknown identifier: {token.value}")

    def __default__(self, data, children, meta):
        assert False, f"Missing method for rule {data} with children {children}"

class FixedPointOps:
    def __init__(self, verilog, transformer):
        self.verilog = verilog
        self.transformer = transformer

    def add_types(self, left: FixedPointType, right: FixedPointType, op: str) -> FixedPointType:
        """Add or subtract two fixed-point types"""
        if left.frac_bits != 0 and right.frac_bits != 0 and abs(left.frac_bits - right.frac_bits) > 1:
            self.transformer.annotation_issues.append(f"Fractional bits do not match for {op}: {left.frac_bits} vs {right.frac_bits}")

        if self.verilog:
            result_bits = max(left.total_bits, right.total_bits)
            result_signed = left.signed and right.signed
        else:
            if left.frac_bits != 0 and right.frac_bits != 0:
                result_bits = max(left.total_bits, right.total_bits)
            else:
                result_bits = left.total_bits if left.frac_bits else right.total_bits
            result_signed = left.signed or right.signed
        return FixedPointType(result_signed, result_bits, left.frac_bits)

    def multiply_types(self, left: FixedPointType, right: FixedPointType) -> FixedPointType:
        """Multiply two fixed-point types"""
        if self.verilog:
            result_bits = max(left.total_bits, right.total_bits)
            result_signed = left.signed and right.signed
        else:
            if left.frac_bits != 0 and right.frac_bits != 0:
                result_bits = left.total_bits + right.total_bits
            else:
                result_bits = left.total_bits if left.frac_bits else right.total_bits
            result_signed = left.signed or right.signed
        if left.frac_bits != 0 and right.frac_bits != 0:
            result_frac_bits = left.frac_bits + right.frac_bits
        else:
            result_frac_bits = left.frac_bits if left.frac_bits else right.frac_bits
        return FixedPointType(result_signed, result_bits, result_frac_bits)

    def divide_types(self, left: FixedPointType, right: FixedPointType) -> FixedPointType:
        """Divide two fixed-point types"""
        if self.verilog:
            result_bits = max(left.total_bits, right.total_bits)
            result_signed = left.signed and right.signed
        else:
            if left.frac_bits != 0 and right.frac_bits != 0:
                result_bits = max(left.total_bits, right.total_bits)
            else:
                result_bits = left.total_bits if left.frac_bits else right.total_bits
            result_signed = left.signed or right.signed
        if left.frac_bits != 0 and right.frac_bits != 0:
            result_frac_bits = left.frac_bits - right.frac_bits
        else:
            result_frac_bits = left.frac_bits if left.frac_bits else right.frac_bits
        return FixedPointType(result_signed, result_bits, result_frac_bits)

    def shift_left_types(self, left, right):
        assert isinstance(right, NumberType), "Shift amount must be a number"
        if right.value == 0:
            self.transformer.annotation_issues.append("Shift by 0 is redundant")
        if left.frac_bits == 0:
            result_frac_bits = 0
        else:
            result_frac_bits = left.frac_bits + right.value
        return FixedPointType(left.signed, left.total_bits + right.value, result_frac_bits)

    def shift_right_signed_types(self, left, right):
        assert isinstance(right, NumberType), "Shift amount must be a number"
        if not left.signed:
            self.transformer.annotation_issues.append("Signed right shift on unsigned type")
        if right.value == 0:
            self.transformer.annotation_issues.append("Shift by 0 is redundant")
        if left.frac_bits == 0:
            result_frac_bits = 0
        else:
            result_frac_bits = left.frac_bits - right.value
        return FixedPointType(left.signed, left.total_bits - right.value, result_frac_bits)

    def shift_right_unsigned_types(self, left, right):
        assert isinstance(right, NumberType), "Shift amount must be a number"
        if left.signed:
            self.transformer.annotation_issues.append("unsigned right shift on signed type")
        if right.value == 0:
            self.transformer.annotation_issues.append("Shift by 0 is redundant")
        if left.frac_bits == 0:
            result_frac_bits = 0
        else:
            result_frac_bits = left.frac_bits - right.value
        return FixedPointType(left.signed, left.total_bits - right.value, result_frac_bits)

class FixedPointError(ValueError):
    pass

class FixedPointChecker:
    """Checks fixed-point arithmetic expressions"""

    def __init__(self):
        # Common Verilog identifiers and their types (can be extended)
        self.known_types = {
            # Common constants
            'PITCH_REF_C2': FixedPointType(False, 7, 0),  # localparam [6:0] PITCH_REF_C2 = 7'd24;
            # These will be extended by parsing register declarations
        }
        self.known_registers = set()

    def parse_reg_declaration(self, line: str) -> Optional[Tuple[str, Optional[FixedPointType]]]:
        """Parse a register declaration line like: reg [23:0] note_offset_8x [0:7];  // U24F24
        or: reg signed [7:0] s8_sample;    // S8F7"""
        # Match pattern: reg [signed] [range] name [array]; // comment
        match = re.match(r'^\s*reg\s+(signed\s+)?\[(\d+):(\d+)\]\s+(\w+)(\s*\[.*\])?\s*;(\s*//(.*))?', line.strip())
        if not match:
            return None

        signed_str, msb, lsb, name, array_part, comment_part, comment_text = match.groups()

        # Calculate bit width
        total_bits = int(msb) - int(lsb) + 1
        signed = signed_str is not None

        fp_type = None
        if comment_text:
            # Find the type anywhere in the comment
            type_match = re.search(r'([SU]\d+F\d+)', comment_text)
            if type_match:
                type_str = type_match.group(1)
                type_match2 = re.match(r'([SU])(\d+)F(\d+)', type_str)
                if type_match2:
                    sign_char, declared_total, frac = type_match2.groups()

                    # Verify the bit width matches
                    if int(declared_total) != total_bits:
                        print(f"Warning: Bit width mismatch for {name}: reg [{msb}:{lsb}] vs {type_str}")

                    fp_type = FixedPointType(sign_char == 'S', total_bits, int(frac))

        # If no explicit type annotation, infer from bit width
        if fp_type is None:
            fp_type = FixedPointType(signed, total_bits, 0)  # Default to integer type

        return name, fp_type

    def parse_localparam_declaration(self, line: str) -> Optional[Tuple[str, Optional[FixedPointType]]]:
        """Parse a localparam declaration line like: localparam signed [11:0] FP_0_875 = 12'sd224; // 0.875 in S12F8"""
        # Match pattern: localparam [signed] [range] name = value; // comment
        match = re.match(r'^\s*localparam\s+(signed\s+)?\[(\d+):(\d+)\]\s+(\w+)\s*=\s*(.+?)\s*;(\s*//(.*))?', line.strip())
        if not match:
            return None

        signed_str, msb, lsb, name, value, comment_part, comment_text = match.groups()

        # Calculate bit width
        total_bits = int(msb) - int(lsb) + 1
        signed = signed_str is not None

        fp_type = None
        if comment_text:
            # Find the type anywhere in the comment
            type_match = re.search(r'([SU]\d+F\d+)', comment_text)
            if type_match:
                type_str = type_match.group(1)
                type_match2 = re.match(r'([SU])(\d+)F(\d+)', type_str)
                if type_match2:
                    sign_char, declared_total, frac = type_match2.groups()

                    # Verify the bit width matches
                    if int(declared_total) != total_bits:
                        print(f"Warning: Bit width mismatch for {name}: localparam [{msb}:{lsb}] vs {type_str}")

                    fp_type = FixedPointType(sign_char == 'S', total_bits, int(frac))

        # If no explicit type annotation, infer from bit width
        if fp_type is None:
            fp_type = FixedPointType(signed, total_bits, 0)  # Default to integer type

        return name, fp_type

    def build_type_database(self, filename: str):
        """Build the known_types dictionary by parsing register, wire, and localparam declarations"""
        with open(filename, 'r') as f:
            for line in f:
                # Try to parse register declarations
                reg_result = self.parse_reg_declaration(line)
                if reg_result:
                    name, fp_type = reg_result
                    self.known_registers.add(name)
                    if fp_type:
                        self.known_types[name] = fp_type

                    # Also add the version without _8x suffix if it exists
                    if name.endswith('_8x'):
                        base_name = name[:-3]
                        self.known_registers.add(base_name)
                        if fp_type:
                            self.known_types[base_name] = fp_type
                    continue

                # Try to parse localparam declarations
                localparam_result = self.parse_localparam_declaration(line)
                if localparam_result:
                    name, fp_type = localparam_result
                    if fp_type:
                        self.known_types[name] = fp_type
                    continue

                # Try to parse localparam declarations
                localparam_result = self.parse_localparam_declaration(line)
                if localparam_result:
                    name, fp_type = localparam_result
                    self.known_registers.add(name)
                    if fp_type:
                        self.known_types[name] = fp_type

                    continue

    def parse_type(self, type_str: str) -> FixedPointType:
        """Parse a type string like 'U8F0' or 'S12F11'"""
        match = re.match(r'([SU])(\d+)F(\d+)', type_str)
        if not match:
            raise ValueError(f"Invalid type format: {type_str}")

        sign_char, total, frac = match.groups()
        if sign_char == 'S' and total == frac:
            raise ValueError(f"Invalid signed type: {type_str}")
        return FixedPointType(sign_char == 'S', int(total), int(frac))

    def parse_comment(self, line: str) -> Optional[Tuple[FixedPointType, str]]:
        """Parse a fixed-point arithmetic comment line"""
        # Strip descriptive prefixes like "Volume scaling:", "Attack ramp:", etc.
        line = re.sub(r'^\s*//\s*[A-Za-z ]+:\s*', '// ', line.strip())

        # Match pattern 1: // Type result = expression
        match1 = re.match(r'^\s*//\s*([SU]\d+F\d+)\s+\w+\s*=\s*(.+)$', line.strip())
        if match1:
            result_type_str, full_expression = match1.groups()
            result_type = self.parse_type(result_type_str)
            return result_type, full_expression.strip()

        # Match pattern 2: // expression = Type
        match2 = re.match(r'^\s*//\s*(.+?)\s*=\s*([SU]\d+F\d+)$', line.strip())
        if match2:
            full_expression, result_type_str = match2.groups()
            result_type = self.parse_type(result_type_str)
            return result_type, full_expression.strip()

        return None

    def evaluate_expression(self, expr: str) -> Tuple[FixedPointType, str, List[str]]:
        """Evaluate the type of a fixed-point expression using Lark parser"""
        try:
            self.parser = Lark(EXPRESSION_GRAMMAR, parser='lalr')
            tree = self.parser.parse(expr)
            transformer = TypeTransformer(self)
            ops = FixedPointOps(False, transformer)
            transformer.ops = ops
            result = transformer.transform(tree)
            # Ensure result is a (FixedPointType, str) tuple
            if not isinstance(result, tuple) or len(result) != 2:
                raise ValueError(f"Transformer returned {type(result)} instead of (FixedPointType, str) tuple")
            computed_type, computed_text = result
            if not isinstance(computed_type, FixedPointType):
                raise ValueError(f"Transformer returned {type(computed_type)} instead of FixedPointType")
            return computed_type, computed_text, transformer.annotation_issues
        except FixedPointError:
            raise
        except VisitError as ve:
            if isinstance(ve.orig_exc, FixedPointError):
                raise ve.orig_exc
            else:
                raise ValueError(f"Parse error: {str(ve)}")
        except Exception as e:
            #print(f"Parse error for expression: {expr}")
            #traceback.print_exc()
            raise ValueError(f"Parse error: {str(e)}")

    def check_overflow(self, computed: FixedPointType, declared: FixedPointType) -> List[str]:
        """Check for overflow issues"""
        issues = []

        # Allow result to be wider than declared (Verilog truncates)
        # Only warn if extremely wide (more than 2x)
        if computed.total_bits > declared.total_bits * 2:
            issues.append(f"Result width {computed.total_bits} much larger than declared {declared.total_bits}")

        # Fractional bits should match for the final result
        if computed.frac_bits != declared.frac_bits:
            issues.append(f"Fractional bits {computed.frac_bits} != declared {declared.frac_bits}")

        # Signedness should match
        if computed.signed != declared.signed:
            # Allow implicit unsigned to signed conversion and vice versa
            if computed.signed and not declared.signed and computed.total_bits == declared.total_bits + 1 or \
               not computed.signed and declared.signed and declared.total_bits == computed.total_bits + 1:
                pass
            else:
                issues.append(f"Signedness mismatch: computed {computed.signed}, declared {declared.signed}")

        return issues

    def analyze_file(self, filename: str) -> List[Dict]:
        """Analyze a Verilog file for fixed-point arithmetic issues"""
        # First, build the type database from register declarations
        self.build_type_database(filename)

        results = []

        # Read all lines
        with open(filename, 'r') as f:
            lines = f.readlines()

        i = 0
        last_was_comment = False
        while i < len(lines):
            line = lines[i]
            line_num = i + 1
            if line.strip().startswith('//'):
                parsed = self.parse_comment(line)
                if parsed:
                    declared_type, expression = parsed
                    try:
                        computed_type, computed_text, annotation_issues = self.evaluate_expression(expression)
                        issues = self.check_overflow(computed_type, declared_type) + annotation_issues

                        # Find next Verilog line
                        j = i + 1
                        verilog_line = None
                        verilog_line_num = None
                        while j < len(lines):
                            next_line = lines[j].strip()
                            if next_line and not next_line.startswith('//'):
                                verilog_line = next_line
                                verilog_line_num = j + 1
                                break
                            j += 1

                        if verilog_line:
                            verilog_parsed = self.parse_verilog_assignment(verilog_line)
                            if verilog_parsed:
                                verilog_lhs, verilog_rhs = verilog_parsed
                                try:
                                    verilog_computed, verilog_text, verilog_issues = self.evaluate_expression(verilog_rhs)
                                    verilog_overflow_issues = self.check_overflow(verilog_computed, declared_type)

                                    # Compare computed types
                                    if verilog_computed != computed_type:
                                        verilog_issues.append(f"Verilog type mismatch: comment computed {computed_type}, Verilog computed {verilog_computed}")

                                    result = {
                                        'line': line_num,
                                        'expression': expression,
                                        'computed_text': computed_text,
                                        'declared': declared_type,
                                        'computed': computed_type,
                                        'issues': issues,
                                        'status': 'OK' if not issues else 'ERROR',
                                        'verilog_line': verilog_line_num,
                                        'verilog_expression': verilog_rhs,
                                        'verilog_computed': verilog_computed,
                                        'verilog_issues': verilog_overflow_issues + verilog_issues,
                                        'verilog_status': 'OK' if not (verilog_overflow_issues + verilog_issues) else 'ERROR'
                                    }
                                    results.append(result)
                                except Exception as e:
                                    result = {
                                        'line': line_num,
                                        'expression': expression,
                                        'computed_text': computed_text,
                                        'declared': declared_type,
                                        'computed': computed_type,
                                        'issues': issues,
                                        'status': 'OK' if not issues else 'ERROR',
                                        'verilog_line': verilog_line_num,
                                        'verilog_expression': verilog_rhs,
                                        'verilog_computed': None,
                                        'verilog_issues': [f"Parse error: {str(e)}"],
                                        'verilog_status': 'PARSE_ERROR'
                                    }
                                    results.append(result)
                            else:
                                result = {
                                    'line': line_num,
                                    'expression': expression,
                                    'computed_text': computed_text,
                                    'declared': declared_type,
                                    'computed': computed_type,
                                    'issues': issues,
                                    'status': 'OK' if not issues else 'ERROR'
                                }
                                results.append(result)
                        else:
                            result = {
                                'line': line_num,
                                'expression': expression,
                                'computed_text': computed_text,
                                'declared': declared_type,
                                'computed': computed_type,
                                'issues': issues,
                                'status': 'OK' if not issues else 'ERROR'
                            }
                            results.append(result)
                        last_was_comment = True
                    except Exception as e:
                        error_str = str(e)
                        if "Unknown identifier:" in error_str:
                            unknown_name = error_str.split("Unknown identifier:")[1].strip()
                            if unknown_name in self.known_registers:
                                results.append({
                                    'line': line_num,
                                    'expression': expression,
                                    'declared': declared_type,
                                    'computed': None,
                                    'issues': [f"Register '{unknown_name}' is missing type annotation"],
                                    'status': 'MISSING_TYPE'
                                })
                            else:
                                results.append({
                                    'line': line_num,
                                    'expression': expression,
                                    'declared': declared_type,
                                    'computed': None,
                                    'issues': [f"Parse error: {error_str}"],
                                    'status': 'PARSE_ERROR'
                                })
                        else:
                            results.append({
                                'line': line_num,
                                'expression': expression,
                                'declared': declared_type,
                                'computed': None,
                                'issues': [f"Parse error: {error_str}"],
                                'status': 'PARSE_ERROR'
                            })
                        last_was_comment = True
                else:
                    last_was_comment = False
            else:
                # Non-comment line
                if last_was_comment:
                    last_was_comment = False
                    # Already handled
                else:
                    # Parse as Verilog
                    verilog_parsed = self.parse_verilog_assignment(line)
                    if verilog_parsed:
                        lhs, rhs = verilog_parsed
                        try:
                            computed_type, computed_text, issues = self.evaluate_expression(rhs)
                            if computed_type.frac_bits > 0 and ('+' in rhs or '-' in rhs or '*' in rhs or '/' in rhs):
                                result = {
                                    'line': line_num,
                                    'expression': rhs,
                                    'declared': None,
                                    'computed': computed_type,
                                    'issues': issues + ['Missing comment for fixed point arithmetic'],
                                    'status': 'MISSING_COMMENT'
                                }
                                results.append(result)
                        except Exception as e:
                            # Silently eat
                            pass
                    else:
                        # Silently eat
                        pass
            i += 1
        return results

    def parse_verilog_assignment(self, line: str) -> Optional[Tuple[str, str]]:
        """Parse a Verilog assignment line like: lhs <= rhs; or lhs = rhs;
        Returns (lhs, rhs) or None if not an assignment"""
        # Remove trailing comment, semicolon and whitespace
        line, _ = line.split('//', 1) if '//' in line else (line, '')
        line = line.strip().rstrip(';')

        # Try non-blocking assignment first (<=)
        if '<=' in line:
            lhs, rhs = line.split('<=', 1)
            return lhs.strip(), rhs.strip()

        # Try blocking assignment (=)
        elif '=' in line:
            lhs, rhs = line.split('=', 1)
            return lhs.strip(), rhs.strip()

        return None

    def extract_verilog_expression(self, line: str) -> Optional[str]:
        """Extract the expression from a Verilog line, e.g., RHS of assignment or condition"""
        line = line.strip()
        if not line:
            return None

        # Remove comments
        line = line.split('//')[0].strip()
        if not line:
            return None

        # Remove trailing ;
        line = line.rstrip(';').strip()
        if not line:
            return None

        # Skip lines with unsupported operators
        if '!' in line or '?' in line:
            return None

        # Extract expression
        if '<=' in line:
            parts = line.split('<=', 1)
            if len(parts) == 2:
                rhs = parts[1].strip()
                return rhs if rhs else None
        elif '=' in line and not line.startswith('='):
            match = re.search(r'(?<![\=!<>])=\s*(.+?)\s*$', line)
            if match:
                return match.group(1).strip()

        # For if statements: if (condition)
        match = re.search(r'if\s*\(\s*(.+?)\s*\)', line, re.IGNORECASE)
        if match:
            cond = match.group(1).strip()
            if cond:
                return cond

        # For other expressions, return the line
        return line
def main():
    if len(sys.argv) != 2:
        print("Usage: python fixed_point_checker.py <verilog_file>")
        sys.exit(1)

    filename = sys.argv[1]
    checker = FixedPointChecker()
    results = checker.analyze_file(filename)

    print(f"Fixed-Point Arithmetic Analysis for {filename}")
    print("=" * 60)

    ok_count = 0
    error_count = 0
    parse_error_count = 0
    missing_type_count = 0
    missing_comment_count = 0

    for result in results:
        status = result['status']
        if status == 'OK':
            ok_count += 1
        elif status == 'ERROR':
            error_count += 1
        elif status == 'PARSE_ERROR':
            parse_error_count += 1
        elif status == 'MISSING_TYPE':
            missing_type_count += 1
        elif status == 'MISSING_COMMENT':
            missing_comment_count += 1

        print(f"Line {result['line']}: {status}")
        if result['expression']:
            print(f"  Expression: {result['expression']}")
        if result['declared']:
            print(f"  Declared: {result['declared']}")
        if result['computed']:
            print(f"  Computed: {result['computed']}")
        if result['issues']:
            for issue in result['issues']:
                print(f"  {issue}")

        # Print Verilog analysis if present
        if 'verilog_line' in result:
            print(f"  Verilog Line {result['verilog_line']}: {result.get('verilog_status', 'UNKNOWN')}")
            if result.get('verilog_expression'):
                print(f"    Expression: {result['verilog_expression']}")
            if result.get('verilog_computed'):
                print(f"    Verilog Computed: {result['verilog_computed']}")
            if result.get('verilog_issues'):
                for issue in result['verilog_issues']:
                    print(f"    {issue}")

        print()

    print("=" * 60)
    print(f"Summary: {ok_count} OK, {error_count} Errors, {parse_error_count} Parse Errors, {missing_type_count} Missing Types, {missing_comment_count} Missing Comments")
    print(f"Total fixed-point expressions checked: {len(results)}")


if __name__ == "__main__":
    main()