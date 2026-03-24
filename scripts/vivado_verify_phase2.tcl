# Vivado Batch-Mode Verification for Poly1305 Phase 2
# Usage: vivado -mode batch -source scripts/vivado_verify_phase2.tcl

set root_dir [file dirname [file dirname [file normalize [info script]]]]
cd $root_dir
set proj_dir "$root_dir/vivado_phase2"

puts "=== Poly1305 Phase 2 Vivado Verification ==="
puts "Root directory: $root_dir"

# 1. Project setup
create_project poly1305_phase2 $proj_dir -part xczu7ev-ffvc1156-2-e -force
set_property target_language VHDL [current_project]

# 2. Add all design sources (Phase 1 + Phase 2) + set VHDL 2008
add_files -norecurse [glob src/*.vhd]
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1]]

# 3. Add Phase 2 sim files only + set VHDL 2008
add_files -fileset sim_1 -norecurse sim/tb_gf_mult_130.vhd
add_files -fileset sim_1 -norecurse sim/tb_poly1305_mac.vhd
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sim_1]]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# 4. Helper proc to run one testbench
proc run_tb {tb_name runtime} {
    puts "========== Running $tb_name =========="
    set_property top $tb_name [get_filesets sim_1]
    set_property -name {xsim.simulate.runtime} -value $runtime -objects [get_filesets sim_1]
    launch_simulation -mode behavioral
    close_sim -force
    puts "========== Done $tb_name =========="
}

# 5. Run Phase 2 testbenches
run_tb tb_gf_mult_130  10us
run_tb tb_poly1305_mac 10us

# 6. Synthesis for poly1305_mac resource utilization
puts "=== Running Synthesis for poly1305_mac ==="
set_property top poly1305_mac [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1
file mkdir $proj_dir/reports
report_utilization -file $proj_dir/reports/utilization.txt
report_timing_summary -file $proj_dir/reports/timing.txt
puts "Synthesis reports saved to $proj_dir/reports/"
close_design

puts "=== Phase 2 Vivado Verification Complete ==="
