#!/bin/bash
# ChaCha20 Phase 1: Compile and run all testbenches with GHDL
set -e

DIR="/home/arunupscee/Desktop/xtortion/chacha20"
cd "$DIR"

echo "=== Compiling ChaCha20 Phase 1 sources ==="
ghdl -a --std=08 src/chacha20_pkg.vhd
ghdl -a --std=08 src/quarter_round.vhd
ghdl -a --std=08 src/double_round.vhd
ghdl -a --std=08 src/column_round.vhd
ghdl -a --std=08 src/diagonal_round.vhd
ghdl -a --std=08 src/chacha20_state_init.vhd
ghdl -a --std=08 src/round_controller.vhd
ghdl -a --std=08 src/keystream_xor.vhd
ghdl -a --std=08 src/chacha20_core.vhd
echo "All sources compiled successfully."

echo ""
echo "=== Running testbenches ==="

PASS=0
FAIL=0

for tb in tb_quarter_round tb_double_round tb_round_controller tb_chacha20_block tb_chacha20_encrypt; do
    echo ""
    echo "--- $tb ---"
    ghdl -a --std=08 "sim/${tb}.vhd"
    ghdl -e --std=08 "$tb"
    if ghdl -r --std=08 "$tb" --stop-time=10us 2>&1 | tee /dev/stderr | grep -q "PASSED"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
