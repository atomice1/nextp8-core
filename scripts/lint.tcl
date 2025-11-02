# TCL script for Vivado lint/syntax checking
# This script checks all source files for syntax errors

# Open the project
open_project nextp8.xpr

puts "=== Checking Verilog/SystemVerilog syntax ==="

# Get all Verilog source files
set verilog_files [get_files -filter {FILE_TYPE == Verilog || FILE_TYPE == "Verilog Header" || FILE_TYPE == "SystemVerilog"}]

set error_count 0
foreach file $verilog_files {
    puts "Checking: $file"
    if {[catch {check_syntax -fileset sources_1 -file $file} result]} {
        puts "ERROR in $file: $result"
        incr error_count
    }
}

puts "\n=== Checking VHDL syntax ==="

# Get all VHDL source files
set vhdl_files [get_files -filter {FILE_TYPE == VHDL}]

foreach file $vhdl_files {
    puts "Checking: $file"
    if {[catch {check_syntax -fileset sources_1 -file $file} result]} {
        puts "ERROR in $file: $result"
        incr error_count
    }
}

if {$error_count > 0} {
    puts "\nERROR: Found $error_count syntax errors"
    exit 1
} else {
    puts "\nSUCCESS: All files passed syntax check"
    exit 0
}
