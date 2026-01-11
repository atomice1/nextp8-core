# Script to regenerate all IP cores simulation netlists using OOC runs

open_project nextp8-issue5.xpr

# Upgrade IP if needed
upgrade_ip [get_ips]

# For each IP, create and launch OOC synthesis runs to generate simulation netlists
foreach ip [get_ips] {
    puts "Generating OOC run for IP: $ip"
    set ip_file [get_files [get_property IP_FILE $ip]]

    # Reset targets
    reset_target all $ip_file

    # Generate all output products
    generate_target all $ip_file

    # Create OOC synthesis run (this generates simulation netlists)
    create_ip_run $ip_file

    # Export IP user files
    export_ip_user_files -of_objects $ip_file -no_script -sync -force -quiet
}

# Launch all OOC synthesis runs to generate simulation netlists
set ooc_runs [get_runs *_synth_1]
if {[llength $ooc_runs] > 0} {
    puts "Launching OOC synthesis runs: $ooc_runs"
    launch_runs $ooc_runs
    wait_on_runs $ooc_runs
}

puts "SUCCESS: All IP simulation netlists regenerated"
close_project
