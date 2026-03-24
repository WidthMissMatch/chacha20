#!/bin/bash
# ChaCha20-Poly1305 VCD toggle coverage runner
# Runs key testbenches with --vcd dump, then analyses coverage.
# Usage: bash scripts/run_coverage.sh

set -e
DIR="/home/arunupscee/Desktop/xtortion/chacha20"
VCD_DIR="/tmp/vhdl_cov"
SCRIPT_DIR="$DIR/scripts"
cd "$DIR"

mkdir -p "$VCD_DIR"

echo "=== ChaCha20-Poly1305 Toggle Coverage Analysis ==="
echo "VCD output directory: $VCD_DIR"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Compile all phases (reuse existing compile scripts without set -e
#         so we can handle each phase independently)
# ---------------------------------------------------------------------------
echo "--- Compiling Phase 1 (ChaCha20 core) ---"
ghdl -a --std=08 src/chacha20_pkg.vhd
ghdl -a --std=08 src/quarter_round.vhd
ghdl -a --std=08 src/double_round.vhd
# column_round and diagonal_round added by P6; compile if present
[ -f src/column_round.vhd  ] && ghdl -a --std=08 src/column_round.vhd
[ -f src/diagonal_round.vhd ] && ghdl -a --std=08 src/diagonal_round.vhd
ghdl -a --std=08 src/chacha20_state_init.vhd
ghdl -a --std=08 src/round_controller.vhd
ghdl -a --std=08 src/keystream_xor.vhd
ghdl -a --std=08 src/chacha20_core.vhd

echo "--- Compiling Phase 2 (Poly1305 MAC) ---"
ghdl -a --std=08 src/poly1305_pkg.vhd
ghdl -a --std=08 src/gf_reduce_130.vhd
ghdl -a --std=08 src/gf_mult_130.vhd
ghdl -a --std=08 src/poly1305_block.vhd
ghdl -a --std=08 src/poly1305_mac.vhd

echo "--- Compiling Phase 3 (System integration) ---"
ghdl -a --std=08 src/uart_tx.vhd
ghdl -a --std=08 src/uart_rx.vhd
ghdl -a --std=08 src/output_buffer.vhd
ghdl -a --std=08 src/matlab_uart_interface.vhd
ghdl -a --std=08 src/key_nonce_register.vhd

echo "--- Compiling Phase 4 (ECDH + SPI + Diffusion) ---"
ghdl -a --std=08 src/cordic_ec_mult.vhd
ghdl -a --std=08 src/newton_raphson_inv.vhd
ghdl -a --std=08 src/point_add.vhd
ghdl -a --std=08 src/point_double.vhd
ghdl -a --std=08 src/ecdh_key_exchange.vhd
ghdl -a --std=08 src/spi_qrng_interface.vhd
ghdl -a --std=08 src/diffusion_analyzer.vhd
ghdl -a --std=08 src/chacha20_top.vhd

# ---------------------------------------------------------------------------
# Step 2: Run target testbenches with VCD output
# ---------------------------------------------------------------------------
PASS=0; FAIL=0

run_tb_vcd() {
    local TB="$1"
    local SRC="$2"
    local STOP="$3"
    local VCD="$VCD_DIR/${TB}.vcd"
    echo ""
    echo "--- $TB (stop-time=${STOP}) ---"
    ghdl -a --std=08 "$SRC"
    ghdl -e --std=08 "$TB"
    if ghdl -r --std=08 "$TB" --stop-time="$STOP" --vcd="$VCD" 2>&1 | tee /dev/stderr | grep -q "PASSED"; then
        echo "  [PASSED] VCD: $VCD"
        PASS=$((PASS+1))
    else
        echo "  [FAILED] VCD: $VCD"
        FAIL=$((FAIL+1))
    fi
}

# Phase 2 targets
run_tb_vcd tb_gf_mult_130    sim/tb_gf_mult_130.vhd    100us
run_tb_vcd tb_poly1305_mac   sim/tb_poly1305_mac.vhd   100us

# Phase 3 system-level target
run_tb_vcd tb_chacha20_top   sim/tb_chacha20_top.vhd   5ms

# Phase 4 ECDH target
run_tb_vcd tb_ecdh_key_exchange sim/tb_ecdh_key_exchange.vhd 200ms

echo ""
echo "=== Simulation Results: $PASS passed, $FAIL failed ==="

# ---------------------------------------------------------------------------
# Step 3: Analyse VCD toggle coverage
# ---------------------------------------------------------------------------
echo ""
echo "=== Running toggle coverage analysis ==="
python3 "$SCRIPT_DIR/check_toggle_coverage.py" \
    "$VCD_DIR/tb_gf_mult_130.vcd" \
    "$VCD_DIR/tb_poly1305_mac.vcd" \
    "$VCD_DIR/tb_chacha20_top.vcd" \
    "$VCD_DIR/tb_ecdh_key_exchange.vcd"
