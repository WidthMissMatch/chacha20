# Targeted synthesis: poly1305_mac only — proves gf_mult_130 timing fix
# Small design (~1,756 LUTs + 50 DSPs), runs in <4 GB RAM

set root_dir [file dirname [file dirname [file normalize [info script]]]]
cd $root_dir

puts "=== Targeted synthesis: poly1305_mac (gf_mult_130 timing fix) ==="
puts "  Previous poly1305_mac: WNS = +0.400 ns at 125 MHz (6-clock gf_mult_130)"
puts "  This run: 7-clock gf_mult_130 with ACCUM_2A/2B pipeline split"

create_project -in_memory -part xczu7ev-ffvc1156-2-e
set_property target_language VHDL [current_project]

read_vhdl -vhdl2008 $root_dir/src/poly1305_pkg.vhd
read_vhdl -vhdl2008 $root_dir/src/gf_reduce_130.vhd
read_vhdl -vhdl2008 $root_dir/src/gf_mult_130.vhd
read_vhdl -vhdl2008 $root_dir/src/poly1305_block.vhd
read_vhdl -vhdl2008 $root_dir/src/poly1305_mac.vhd

# Write a temporary XDC with the 125 MHz clock constraint
set xdc_file [file join $root_dir vivado_poly poly_clock.xdc]
file mkdir [file join $root_dir vivado_poly]
set fh [open $xdc_file w]
puts $fh "create_clock -name sys_clk -period 8.000 \[get_ports clk\]"
close $fh
read_xdc $xdc_file

synth_design -top poly1305_mac -part xczu7ev-ffvc1156-2-e

file mkdir $root_dir/vivado_poly/reports
report_utilization    -file $root_dir/vivado_poly/reports/utilization.txt
report_timing_summary -file $root_dir/vivado_poly/reports/timing.txt

puts ""
puts "=== SYNTHESIS TIMING (poly1305_mac @ 125 MHz) ==="
set ts [report_timing_summary -return_string -quiet]
foreach line [split $ts "\n"] {
    if {[regexp {Setup :|Hold :|PW :} $line]} { puts "  $line" }
}
puts ""
puts "=== TOP 5 CRITICAL PATHS ==="
report_timing -max_paths 5 -sort_by slack

# P&R for authoritative timing
puts ""
puts "=== opt_design + place_design + route_design ==="
opt_design
place_design
route_design

report_timing_summary -file $root_dir/vivado_poly/reports/impl_timing.txt
report_utilization    -file $root_dir/vivado_poly/reports/impl_utilization.txt

puts ""
puts "=== POST-P&R TIMING ==="
set ti [report_timing_summary -return_string -quiet]
foreach line [split $ti "\n"] {
    if {[regexp {Setup :|Hold :|PW :} $line]} { puts "  $line" }
}
puts ""
puts "=== TOP 5 POST-P&R PATHS ==="
report_timing -max_paths 5 -sort_by slack

puts ""
puts "=== Done. Reports in vivado_poly/reports/ ==="
