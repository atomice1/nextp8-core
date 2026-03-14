// fp_ops.sv — Parameterized fixed-point multiply and divide functions.
//
// Implements fp_mul and fp_div as static methods of a parameterized class,
// since SystemVerilog does not support standalone parameterized functions.
//
// Parameters:
//   WID_X, PRC_X  — width and fractional bits of result x
//   WID_Y, PRC_Y  — width and fractional bits of operand y
//   WID_Z, PRC_Z  — width and fractional bits of operand z
//   POST_SHIFT    — additional left-shift applied to result (≥0)
//
// Five signedness variants each for mul and div:
//   _ss   signed × signed   → signed
//   _su   signed × unsigned → signed
//   _us   unsigned × signed → signed
//   _uu   unsigned × unsigned → unsigned
//   _uu_s unsigned × unsigned → signed

class fp #(
    parameter int WID_X = 16, int PRC_X = 0,
    parameter int WID_Y = 16, int PRC_Y = 0,
    parameter int WID_Z = 16, int PRC_Z = 0,
    parameter int POST_SHIFT = 0
);

    localparam int H = PRC_X + POST_SHIFT;

    // Multiplication intermediate width: full product of (WID_Y + WID_Z) bits
    localparam int MUL_W = WID_Y + WID_Z;

    // Shift amount for multiplication: PRC_Y + PRC_Z - H
    // Positive means right-shift, negative means left-shift
    localparam int MUL_SHIFT = PRC_Y + PRC_Z - H;

    // Division: numerator is extended by PRC_Z bits → width = WID_Y + PRC_Z
    // After dividing, raw quotient has PRC_Y fractional bits → adjust by PRC_Y - H
    localparam int DIV_NUM_W = WID_Y + PRC_Z;
    localparam int DIV_SHIFT = PRC_Y - H;

    // Division: denominator extended to match numerator width
    // Extension count = WID_Y + PRC_Z - WID_Z (must be ≥ 0)
    localparam int DIV_DEN_EXT = WID_Y + PRC_Z - WID_Z;

    // For div_us: numerator gets extra sign bit → width = WID_Y + PRC_Z + 1
    localparam int DIV_US_NUM_W = WID_Y + PRC_Z + 1;
    localparam int DIV_US_DEN_EXT = WID_Y + PRC_Z + 1 - WID_Z;

    // ===== MULTIPLICATION =====

    // SS: signed × signed → signed
    static function signed [WID_X-1:0] mul_ss(input signed [WID_Y-1:0] y, input signed [WID_Z-1:0] z);
        logic signed [MUL_W-1:0] product;
        product = $signed({{WID_Z{y[WID_Y-1]}}, y}) * $signed({{WID_Y{z[WID_Z-1]}}, z});
        if (MUL_SHIFT > 0)
            mul_ss = WID_X'(product >>> MUL_SHIFT);
        else if (MUL_SHIFT == 0)
            mul_ss = WID_X'(product);
        else
            mul_ss = WID_X'(product <<< (-MUL_SHIFT));
    endfunction

    // SS with bias: (signed × signed + bias) → signed
    // Bias is added at full product width before shifting.
    static function signed [WID_X-1:0] mul_ss_bias(
        input signed [WID_Y-1:0] y,
        input signed [WID_Z-1:0] z,
        input signed [MUL_W-1:0] bias
    );
        logic signed [MUL_W-1:0] product;
        product = $signed({{WID_Z{y[WID_Y-1]}}, y}) * $signed({{WID_Y{z[WID_Z-1]}}, z}) + bias;
        if (MUL_SHIFT > 0)
            mul_ss_bias = WID_X'(product >>> MUL_SHIFT);
        else if (MUL_SHIFT == 0)
            mul_ss_bias = WID_X'(product);
        else
            mul_ss_bias = WID_X'(product <<< (-MUL_SHIFT));
    endfunction

    // SU: signed × unsigned → signed
    static function signed [WID_X-1:0] mul_su(input signed [WID_Y-1:0] y, input [WID_Z-1:0] z);
        logic signed [MUL_W-1:0] product;
        // Both must be $signed for signed multiplication.
        // Zero-extending z guarantees MSB=0, so $signed preserves its value.
        product = $signed({{WID_Z{y[WID_Y-1]}}, y}) * $signed({{WID_Y{1'b0}}, z});
        if (MUL_SHIFT > 0)
            mul_su = WID_X'(product >>> MUL_SHIFT);
        else if (MUL_SHIFT == 0)
            mul_su = WID_X'(product);
        else
            mul_su = WID_X'(product <<< (-MUL_SHIFT));
    endfunction

    // US: unsigned × signed → signed
    static function signed [WID_X-1:0] mul_us(input [WID_Y-1:0] y, input signed [WID_Z-1:0] z);
        logic signed [MUL_W-1:0] product;
        // Both must be $signed for signed multiplication.
        // Zero-extending y guarantees MSB=0, so $signed preserves its value.
        product = $signed({{WID_Z{1'b0}}, y}) * $signed({{WID_Y{z[WID_Z-1]}}, z});
        if (MUL_SHIFT > 0)
            mul_us = WID_X'(product >>> MUL_SHIFT);
        else if (MUL_SHIFT == 0)
            mul_us = WID_X'(product);
        else
            mul_us = WID_X'(product <<< (-MUL_SHIFT));
    endfunction

    // UU: unsigned × unsigned → unsigned
    static function [WID_X-1:0] mul_uu(input [WID_Y-1:0] y, input [WID_Z-1:0] z);
        logic [MUL_W-1:0] product;
        product = {{WID_Z{1'b0}}, y} * {{WID_Y{1'b0}}, z};
        if (MUL_SHIFT > 0)
            mul_uu = WID_X'(product >> MUL_SHIFT);
        else if (MUL_SHIFT == 0)
            mul_uu = WID_X'(product);
        else
            mul_uu = WID_X'(product << (-MUL_SHIFT));
    endfunction

    // UU→S: unsigned × unsigned → signed
    static function signed [WID_X-1:0] mul_uu_s(input [WID_Y-1:0] y, input [WID_Z-1:0] z);
        logic [MUL_W-1:0] product;
        product = {{WID_Z{1'b0}}, y} * {{WID_Y{1'b0}}, z};
        if (MUL_SHIFT > 0)
            mul_uu_s = WID_X'($signed({1'b0, product}) >>> MUL_SHIFT);
        else if (MUL_SHIFT == 0)
            mul_uu_s = WID_X'($signed({1'b0, product}));
        else
            mul_uu_s = WID_X'($signed({1'b0, product}) <<< (-MUL_SHIFT));
    endfunction

    // ===== DIVISION =====

    // SS: signed / signed → signed
    static function signed [WID_X-1:0] div_ss(input signed [WID_Y-1:0] y, input signed [WID_Z-1:0] z);
        logic signed [DIV_NUM_W-1:0] num;
        logic signed [DIV_NUM_W-1:0] den;
        logic signed [DIV_NUM_W-1:0] quotient;
        num = $signed({y, {PRC_Z{1'b0}}});
        den = $signed({{DIV_DEN_EXT{z[WID_Z-1]}}, z});
        quotient = num / den;
        if (DIV_SHIFT > 0)
            div_ss = WID_X'(quotient >>> DIV_SHIFT);
        else if (DIV_SHIFT == 0)
            div_ss = WID_X'(quotient);
        else
            div_ss = WID_X'(quotient <<< (-DIV_SHIFT));
    endfunction

    // SU: signed / unsigned → signed (requires WID_Y + PRC_Z > WID_Z)
    static function signed [WID_X-1:0] div_su(input signed [WID_Y-1:0] y, input [WID_Z-1:0] z);
        logic signed [DIV_NUM_W-1:0] num;
        logic signed [DIV_NUM_W-1:0] den;
        logic signed [DIV_NUM_W-1:0] quotient;
        num = $signed({y, {PRC_Z{1'b0}}});
        // Both must be $signed; zero-extension adds ≥1 bit (DIV_DEN_EXT > 0).
        den = $signed({{DIV_DEN_EXT{1'b0}}, z});
        quotient = num / den;
        if (DIV_SHIFT > 0)
            div_su = WID_X'(quotient >>> DIV_SHIFT);
        else if (DIV_SHIFT == 0)
            div_su = WID_X'(quotient);
        else
            div_su = WID_X'(quotient <<< (-DIV_SHIFT));
    endfunction

    // US: unsigned / signed → signed
    static function signed [WID_X-1:0] div_us(input [WID_Y-1:0] y, input signed [WID_Z-1:0] z);
        logic signed [DIV_US_NUM_W-1:0] num;
        logic signed [DIV_US_NUM_W-1:0] den;
        logic signed [DIV_US_NUM_W-1:0] quotient;
        // Prepend 1'b0 to unsigned numerator so $signed preserves its value.
        num = $signed({1'b0, y, {PRC_Z{1'b0}}});
        den = $signed({{DIV_US_DEN_EXT{z[WID_Z-1]}}, z});
        quotient = num / den;
        if (DIV_SHIFT > 0)
            div_us = WID_X'(quotient >>> DIV_SHIFT);
        else if (DIV_SHIFT == 0)
            div_us = WID_X'(quotient);
        else
            div_us = WID_X'(quotient <<< (-DIV_SHIFT));
    endfunction

    // UU: unsigned / unsigned → unsigned
    static function [WID_X-1:0] div_uu(input [WID_Y-1:0] y, input [WID_Z-1:0] z);
        logic [DIV_NUM_W-1:0] num;
        logic [DIV_NUM_W-1:0] den;
        logic [DIV_NUM_W-1:0] quotient;
        num = {y, {PRC_Z{1'b0}}};
        den = {{DIV_DEN_EXT{1'b0}}, z};
        quotient = num / den;
        if (DIV_SHIFT > 0)
            div_uu = WID_X'(quotient >> DIV_SHIFT);
        else if (DIV_SHIFT == 0)
            div_uu = WID_X'(quotient);
        else
            div_uu = WID_X'(quotient << (-DIV_SHIFT));
    endfunction

    // UU→S: unsigned / unsigned → signed
    static function signed [WID_X-1:0] div_uu_s(input [WID_Y-1:0] y, input [WID_Z-1:0] z);
        logic [DIV_NUM_W-1:0] num;
        logic [DIV_NUM_W-1:0] den;
        logic [DIV_NUM_W-1:0] quotient;
        num = {y, {PRC_Z{1'b0}}};
        den = {{DIV_DEN_EXT{1'b0}}, z};
        quotient = num / den;
        if (DIV_SHIFT > 0)
            div_uu_s = WID_X'($signed({1'b0, quotient}) >>> DIV_SHIFT);
        else if (DIV_SHIFT == 0)
            div_uu_s = WID_X'($signed({1'b0, quotient}));
        else
            div_uu_s = WID_X'($signed({1'b0, quotient}) <<< (-DIV_SHIFT));
    endfunction

    // ===== CONSTANTS =====

    // Convert a real value to fixed-point with PRC_X fractional bits.
    // Truncates toward zero (same as $rtoi).
    // Usage: fp_s22::constant(2.0)  →  22'sd524288  (S22F18 representation of 2.0)
    static function signed [WID_X-1:0] constant(real value);
        constant = WID_X'($rtoi(value * (2.0 ** PRC_X)));
    endfunction

endclass
