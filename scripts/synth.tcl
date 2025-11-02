# TCL script for Vivado synthesis
# This script opens the project and runs synthesis

# Open the project
open_project nextp8.xpr

# Reset synthesis run
reset_run synth_1

# Launch synthesis
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# Check for errors
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed"
    exit 1
}

if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    puts "ERROR: Synthesis did not complete successfully"
    exit 1
}

puts "SUCCESS: Synthesis completed successfully"
exit 0
