# TCL script for Vivado lint/syntax checking
# This script checks all source files for syntax errors by running elaboration

# Open the project
open_project nextp8.xpr

puts "=== Running design elaboration for syntax checking ==="

# Reset run
reset_run synth_1

# Launch elaboration (compile step) - this will check syntax
set result [catch {
    synth_design -rtl -name rtl_1
} error_msg]

if {$result != 0} {
    puts "\nERROR: Syntax or elaboration errors found:"
    puts $error_msg
    exit 1
} else {
    puts "\nSUCCESS: All files passed syntax check"
    exit 0
}
