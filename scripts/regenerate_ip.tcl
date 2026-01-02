# Script to regenerate all IP cores after configuration changes

open_project nextp8-issue5.xpr

# Upgrade and regenerate all IP
upgrade_ip [get_ips]
generate_target all [get_ips pll_hdmi]
export_ip_user_files -of_objects [get_ips pll_hdmi] -no_script -sync -force -quiet

# Regenerate all other IPs to ensure consistency
foreach ip [get_ips] {
    puts "Regenerating IP: $ip"
    generate_target all [get_ips $ip]
}

export_simulation -of_objects [get_files] -directory nextp8.ip_user_files/sim_scripts -force -quiet

puts "SUCCESS: All IP cores regenerated"
close_project
