# Vivado Batch-Mode Verification for ChaCha20-Poly1305 Phase 3 (System Integration)
# Usage: vivado -mode batch -source scripts/vivado_verify_phase3.tcl

set root_dir [file dirname [file dirname [file normalize [info script]]]]
cd $root_dir
set proj_dir "$root_dir/vivado_phase3"

puts "=== ChaCha20-Poly1305 Phase 3 Vivado Verification ==="
puts "Root directory: $root_dir"

# 1. Project setup
create_project chacha20_phase3 $proj_dir -part xczu7ev-ffvc1156-2-e -force
set_property target_language VHDL [current_project]

# 2. Add ALL design sources (Phase 1 + Phase 2 + Phase 3) + set VHDL 2008
add_files -norecurse [glob src/*.vhd]
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1]]

# 3. Add ALL Phase 3 sim files + set VHDL 2008
add_files -fileset sim_1 -norecurse sim/tb_uart_tx.vhd
add_files -fileset sim_1 -norecurse sim/tb_uart_rx.vhd
add_files -fileset sim_1 -norecurse sim/tb_output_buffer.vhd
add_files -fileset sim_1 -norecurse sim/tb_matlab_uart_interface.vhd
add_files -fileset sim_1 -norecurse sim/tb_chacha20_top.vhd
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

# 5. Run Phase 3 testbenches
run_tb tb_uart_tx               100us
run_tb tb_uart_rx               200us
run_tb tb_output_buffer         100us
run_tb tb_matlab_uart_interface 5ms
run_tb tb_chacha20_top          5ms

# 6. Add constraints file
add_files -fileset constrs_1 -norecurse constraints/zcu106_chacha20.xdc

# 7. Synthesis for chacha20_top (full system) resource utilization
puts "=== Running Synthesis for chacha20_top ==="
set_property top chacha20_top [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1
file mkdir $proj_dir/reports
report_utilization -file $proj_dir/reports/utilization.txt
report_timing_summary -file $proj_dir/reports/timing.txt
puts "Synthesis reports saved to $proj_dir/reports/"
close_design

# 8. Full implementation (place & route) — resolves hold violations
puts "=== Running Implementation (opt + place + route) ==="
launch_runs impl_1 -jobs 4
wait_on_run impl_1
open_run impl_1 -name impl_1
file mkdir $proj_dir/reports
report_timing_summary -file $proj_dir/reports/impl_timing.txt
report_utilization    -file $proj_dir/reports/impl_utilization.txt
puts "Implementation reports saved to $proj_dir/reports/"
puts "  impl_timing.txt      -- WNS > 0 expected after P1 timing fix"
puts "  impl_utilization.txt -- final resource usage after P&R"
close_design

puts "=== Phase 3 Vivado Verification + Implementation Complete ==="
