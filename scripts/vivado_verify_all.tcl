# Vivado Comprehensive Verification — ChaCha20-Poly1305 All Phases
# Usage: vivado -mode batch -source scripts/vivado_verify_all.tcl
#
# Runs 17 behavioural testbenches (all except tb_ecdh_key_exchange which needs
# 200 ms sim time), then synthesis + P&R for chacha20_top on xczu7ev-ffvc1156-2-e.

set root_dir [file dirname [file dirname [file normalize [info script]]]]
cd $root_dir
set proj_dir "$root_dir/vivado_all"

puts "=== ChaCha20-Poly1305 Comprehensive Vivado Verification ==="
puts "Root directory: $root_dir"
puts "Project dir:    $proj_dir"

# ─────────────────────────────────────────────────────────────────────────────
# 1. Create Vivado project
# ─────────────────────────────────────────────────────────────────────────────
create_project chacha20_all $proj_dir -part xczu7ev-ffvc1156-2-e -force
set_property target_language VHDL [current_project]

# ─────────────────────────────────────────────────────────────────────────────
# 2. Add ALL design sources and mark as VHDL 2008
# ─────────────────────────────────────────────────────────────────────────────
add_files -norecurse [glob $root_dir/src/*.vhd]
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1]]

# ─────────────────────────────────────────────────────────────────────────────
# 3. Add ALL testbench sources and mark as VHDL 2008
# ─────────────────────────────────────────────────────────────────────────────
set sim_files [list \
    $root_dir/sim/tb_quarter_round.vhd        \
    $root_dir/sim/tb_double_round.vhd         \
    $root_dir/sim/tb_round_controller.vhd     \
    $root_dir/sim/tb_chacha20_block.vhd       \
    $root_dir/sim/tb_chacha20_encrypt.vhd     \
    $root_dir/sim/tb_gf_mult_130.vhd          \
    $root_dir/sim/tb_poly1305_mac.vhd         \
    $root_dir/sim/tb_uart_tx.vhd              \
    $root_dir/sim/tb_uart_rx.vhd              \
    $root_dir/sim/tb_output_buffer.vhd        \
    $root_dir/sim/tb_matlab_uart_interface.vhd\
    $root_dir/sim/tb_chacha20_top.vhd         \
    $root_dir/sim/tb_axi_lite_wrapper.vhd     \
    $root_dir/sim/tb_cordic_ec_mult.vhd       \
    $root_dir/sim/tb_newton_raphson_inv.vhd   \
    $root_dir/sim/tb_spi_qrng_interface.vhd   \
    $root_dir/sim/tb_diffusion_analyzer.vhd   \
]
add_files -fileset sim_1 -norecurse $sim_files
set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sim_1]]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ─────────────────────────────────────────────────────────────────────────────
# 4. Helper: run one testbench (launch → close)
#    tb_name  - entity name
#    runtime  - xsim simulation stop time string (e.g. "5ms")
# ─────────────────────────────────────────────────────────────────────────────
set pass_count 0
set fail_count 0

proc run_tb {tb_name runtime} {
    global pass_count fail_count
    puts ""
    puts "========== $tb_name (stop=$runtime) =========="
    set_property top $tb_name [get_filesets sim_1]
    set_property -name {xsim.simulate.runtime} -value $runtime -objects [get_filesets sim_1]
    if {[catch {launch_simulation -mode behavioral} err]} {
        puts "  ERROR launching simulation: $err"
        incr fail_count
        return
    }
    # Pull log text and search for PASSED / FAILED markers
    set log_dir "[get_property DIRECTORY [current_project]]/[current_project].sim/sim_1/behav/xsim"
    set log_file "$log_dir/${tb_name}.log"
    if {[file exists $log_file]} {
        set fh [open $log_file r]
        set contents [read $fh]
        close $fh
        # Print relevant lines
        foreach line [split $contents "\n"] {
            if {[regexp -nocase {PASS|FAIL|ERROR|assert|note|warn} $line]} {
                puts "  LOG: $line"
            }
        }
        if {[string match -nocase "*PASSED*" $contents]} {
            puts "  RESULT: PASSED"
            incr pass_count
        } elseif {[string match -nocase "*FAILED*" $contents]} {
            puts "  RESULT: FAILED"
            incr fail_count
        } else {
            puts "  RESULT: NO PASS/FAIL marker (check log)"
            incr fail_count
        }
    } else {
        puts "  RESULT: log not found at $log_file"
        incr fail_count
    }
    close_sim -force
    puts "========== Done $tb_name =========="
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Phase 1 — ChaCha20 core testbenches
# ─────────────────────────────────────────────────────────────────────────────
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "PHASE 1: ChaCha20 Core"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_tb tb_quarter_round       10us
run_tb tb_double_round        10us
run_tb tb_round_controller    10us
run_tb tb_chacha20_block       1us
run_tb tb_chacha20_encrypt    10us

# ─────────────────────────────────────────────────────────────────────────────
# 6. Phase 2 — Poly1305 MAC testbenches
# ─────────────────────────────────────────────────────────────────────────────
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "PHASE 2: Poly1305 MAC"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_tb tb_gf_mult_130         100us
run_tb tb_poly1305_mac          5us

# ─────────────────────────────────────────────────────────────────────────────
# 7. Phase 3 — UART / System integration testbenches
# ─────────────────────────────────────────────────────────────────────────────
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "PHASE 3: UART & System Integration"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_tb tb_uart_tx               1ms
run_tb tb_uart_rx               2ms
run_tb tb_output_buffer         1ms
run_tb tb_matlab_uart_interface 50ms
run_tb tb_chacha20_top          20ms

# ─────────────────────────────────────────────────────────────────────────────
# 8. AXI4-Lite wrapper testbench
# ─────────────────────────────────────────────────────────────────────────────
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "AXI4-Lite Wrapper"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_tb tb_axi_lite_wrapper     10ms

# ─────────────────────────────────────────────────────────────────────────────
# 9. Phase 4 — ECDH + SPI + Diffusion (skip tb_ecdh_key_exchange: 200 ms)
# ─────────────────────────────────────────────────────────────────────────────
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "PHASE 4: ECDH / SPI / Diffusion (ecdh_key_exchange skipped - 200ms sim)"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
run_tb tb_cordic_ec_mult      500us
run_tb tb_newton_raphson_inv   50ms
run_tb tb_spi_qrng_interface   10ms
run_tb tb_diffusion_analyzer    1us

# ─────────────────────────────────────────────────────────────────────────────
# 10. Simulation summary
# ─────────────────────────────────────────────────────────────────────────────
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "SIMULATION SUMMARY: $pass_count passed, $fail_count failed"
puts "  (tb_ecdh_key_exchange skipped — 200 ms sim time, use GHDL)"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─────────────────────────────────────────────────────────────────────────────
# 11. Add XDC constraints
# ─────────────────────────────────────────────────────────────────────────────
add_files -fileset constrs_1 -norecurse $root_dir/constraints/zcu106_chacha20.xdc
set_property USED_IN_SYNTHESIS true  [get_files $root_dir/constraints/zcu106_chacha20.xdc]
set_property USED_IN_IMPLEMENTATION true [get_files $root_dir/constraints/zcu106_chacha20.xdc]

# ─────────────────────────────────────────────────────────────────────────────
# 12. Synthesis — chacha20_top (with updated gf_mult_130 ACCUM_2A/B split)
# ─────────────────────────────────────────────────────────────────────────────
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "SYNTHESIS: chacha20_top @ 125 MHz (xczu7ev-ffvc1156-2-e)"
puts "  Key change: gf_mult_130 ACCUM_2→ACCUM_2A+ACCUM_2B pipeline split"
puts "  Previous WNS: -0.825 ns (74 failing endpoints)"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
set_property top chacha20_top [current_fileset]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1
file mkdir $proj_dir/reports
report_utilization    -file $proj_dir/reports/utilization.txt
report_timing_summary -file $proj_dir/reports/timing.txt
puts "Synthesis reports written to $proj_dir/reports/"

# Quick WNS summary
set tu [report_timing_summary -return_string -quiet]
foreach line [split $tu "\n"] {
    if {[regexp {WNS|TNS Failing|Setup :} $line]} {
        puts "  SYNTH TIMING: $line"
    }
}
close_design

# ─────────────────────────────────────────────────────────────────────────────
# 13. Implementation (Place & Route) — resolves hold violations
# ─────────────────────────────────────────────────────────────────────────────
puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "IMPLEMENTATION (opt + place + route)"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
launch_runs impl_1 -jobs 4
wait_on_run impl_1
open_run impl_1 -name impl_1
report_timing_summary -file $proj_dir/reports/impl_timing.txt
report_utilization    -file $proj_dir/reports/impl_utilization.txt

# Print WNS from implementation
set tu_impl [report_timing_summary -return_string -quiet]
foreach line [split $tu_impl "\n"] {
    if {[regexp {WNS|TNS Failing|Setup :} $line]} {
        puts "  IMPL TIMING: $line"
    }
}
close_design

puts ""
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts "COMPLETE. Reports in $proj_dir/reports/"
puts "  utilization.txt      — synth resource usage"
puts "  timing.txt           — synthesis timing (WNS post-fix)"
puts "  impl_timing.txt      — post-P&R timing (authoritative)"
puts "  impl_utilization.txt — post-P&R resource usage"
puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
