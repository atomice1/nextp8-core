# TCL script for Vivado bitstream generation
# This script opens the project and generates the bitstream

# Open the project
open_project nextp8.xpr

# Check that implementation is complete
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation must be run first"
    exit 1
}

# Launch bitstream generation
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

# Check for errors
set status [get_property STATUS [get_runs impl_1]]
if {![string match "*write_bitstream Complete!*" $status]} {
    puts "ERROR: Bitstream generation failed"
    puts "Status: $status"
    exit 1
}

puts "SUCCESS: Bitstream generation completed"

# Find and report bitstream location
set bit_file [get_property DIRECTORY [get_runs impl_1]]/nextp8.bit
if {[file exists $bit_file]} {
    puts "Bitstream file: $bit_file"
} else {
    puts "WARNING: Could not find bitstream file at expected location"
}

exit 0
