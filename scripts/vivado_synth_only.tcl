# Lightweight synthesis-only — chacha20_top post-timing-fix
# Uses -jobs 1 to keep memory under 8 GB (safe for 16 GB systems)

set root_dir [file dirname [file dirname [file normalize [info script]]]]
cd $root_dir
set proj_dir "$root_dir/vivado_synth"

puts "=== Synthesis-only: chacha20_top (gf_mult_130 ACCUM_2A/2B fix) ==="

create_project chacha20_synth $proj_dir -part xczu7ev-ffvc1156-2-e -force
set_property target_language VHDL [current_project]

add_files -norecurse [glob $root_dir/src/*.vhd]
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1]]
add_files -fileset constrs_1 -norecurse $root_dir/constraints/zcu106_chacha20.xdc

set_property top chacha20_top [current_fileset]
update_compile_order -fileset sources_1

# Single-threaded synthesis to limit memory
launch_runs synth_1 -jobs 1
wait_on_run synth_1

open_run synth_1
file mkdir $proj_dir/reports
report_utilization    -file $proj_dir/reports/utilization.txt
report_timing_summary -file $proj_dir/reports/timing.txt

# Print key timing numbers
set ts [report_timing_summary -return_string -quiet]
foreach line [split $ts "\n"] {
    if {[regexp {Setup :|Hold :|PW :} $line]} { puts "  $line" }
}
puts ""
report_timing -max_paths 3 -sort_by slack

close_design

# Implementation (P&R) — single-threaded
puts ""
puts "=== Implementation (opt + place + route) ==="
launch_runs impl_1 -jobs 1
wait_on_run impl_1
open_run impl_1 -name impl_1
report_timing_summary -file $proj_dir/reports/impl_timing.txt
report_utilization    -file $proj_dir/reports/impl_utilization.txt

set ti [report_timing_summary -return_string -quiet]
foreach line [split $ti "\n"] {
    if {[regexp {Setup :|Hold :|PW :} $line]} { puts "  $line" }
}
puts ""
report_timing -max_paths 3 -sort_by slack

close_design
puts "=== Done. Reports in $proj_dir/reports/ ==="
