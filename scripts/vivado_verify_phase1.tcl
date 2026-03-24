# Vivado Batch-Mode Verification for ChaCha20 Phase 1
# Usage: vivado -mode batch -source scripts/vivado_verify_phase1.tcl

set root_dir [file dirname [file dirname [file normalize [info script]]]]
cd $root_dir
set proj_dir "$root_dir/vivado_phase1"

puts "=== ChaCha20 Phase 1 Vivado Verification ==="
puts "Root directory: $root_dir"

# 1. Project setup
create_project chacha20_phase1 $proj_dir -part xczu7ev-ffvc1156-2-e -force
set_property target_language VHDL [current_project]

# 2. Add design sources + set VHDL 2008
add_files -norecurse [glob src/*.vhd]
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1]]

# 3. Add simulation files + set VHDL 2008
set sim_files [glob sim/*.vhd]
add_files -fileset sim_1 -norecurse $sim_files
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

# 5. Run all 5 testbenches
run_tb tb_quarter_round    1us
run_tb tb_double_round     1us
run_tb tb_round_controller 1us
run_tb tb_chacha20_block   1us
run_tb tb_chacha20_encrypt 10us

# 6. Synthesis for resource utilization
puts "=== Running Synthesis ==="
set_property top chacha20_core [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1
file mkdir $proj_dir/reports
report_utilization -file $proj_dir/reports/utilization.txt
report_timing_summary -file $proj_dir/reports/timing.txt
puts "Synthesis reports saved to $proj_dir/reports/"
close_design

puts "=== Phase 1 Vivado Verification Complete ==="
