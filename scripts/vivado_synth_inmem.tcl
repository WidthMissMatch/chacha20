# In-memory synthesis — single Vivado process, no child spawning
# Much lower memory footprint than launch_runs

set root_dir [file dirname [file dirname [file normalize [info script]]]]
cd $root_dir

puts "=== In-memory synthesis: chacha20_top ==="

# Create in-memory project (no disk project overhead)
create_project -in_memory -part xczu7ev-ffvc1156-2-e
set_property target_language VHDL [current_project]

# Add sources
foreach f [glob $root_dir/src/*.vhd] {
    read_vhdl -vhdl2008 $f
}
read_xdc $root_dir/constraints/zcu106_chacha20.xdc

# Synthesis in current process (no child)
synth_design -top chacha20_top -part xczu7ev-ffvc1156-2-e

# Reports
file mkdir $root_dir/vivado_inmem/reports
report_utilization    -file $root_dir/vivado_inmem/reports/utilization.txt
report_timing_summary -file $root_dir/vivado_inmem/reports/timing.txt

puts ""
puts "=== SYNTHESIS TIMING ==="
set ts [report_timing_summary -return_string -quiet]
foreach line [split $ts "\n"] {
    if {[regexp {Setup :|Hold :|PW :} $line]} { puts "  $line" }
}
puts ""
puts "=== TOP 3 CRITICAL PATHS ==="
report_timing -max_paths 3 -sort_by slack

# Place & route
puts ""
puts "=== Running opt_design + place_design + route_design ==="
opt_design
place_design
route_design

report_timing_summary -file $root_dir/vivado_inmem/reports/impl_timing.txt
report_utilization    -file $root_dir/vivado_inmem/reports/impl_utilization.txt

puts ""
puts "=== POST-P&R TIMING ==="
set ti [report_timing_summary -return_string -quiet]
foreach line [split $ti "\n"] {
    if {[regexp {Setup :|Hold :|PW :} $line]} { puts "  $line" }
}
puts ""
puts "=== TOP 3 POST-P&R PATHS ==="
report_timing -max_paths 3 -sort_by slack

puts ""
puts "=== Done. Reports in vivado_inmem/reports/ ==="
