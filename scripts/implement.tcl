# TCL script for Vivado implementation (place and route)
# This script opens the project and runs implementation

# Open the project
open_project nextp8.xpr

# Check that synthesis is complete
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis must be run first"
    exit 1
}

# Reset implementation run
reset_run impl_1

# Launch implementation
launch_runs impl_1 -jobs 4
wait_on_run impl_1

# Check for errors
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed"
    exit 1
}

if {[get_property STATUS [get_runs impl_1]] != "route_design Complete!"} {
    puts "ERROR: Implementation did not complete successfully"
    exit 1
}

puts "SUCCESS: Implementation completed successfully"

# Report timing summary
open_run impl_1
report_timing_summary -file timing_summary.rpt
report_utilization -file utilization.rpt

puts "Timing and utilization reports written"
exit 0
