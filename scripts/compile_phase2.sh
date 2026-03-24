#!/bin/bash
# ChaCha20-Poly1305 Phase 2: Compile and run Poly1305 testbenches with GHDL
set -e

DIR="/home/arunupscee/Desktop/xtortion/chacha20"
cd "$DIR"

echo "=== Compiling Phase 1 dependencies ==="
ghdl -a --std=08 src/chacha20_pkg.vhd

echo "=== Compiling Phase 2 sources ==="
ghdl -a --std=08 src/poly1305_pkg.vhd
ghdl -a --std=08 src/gf_reduce_130.vhd
ghdl -a --std=08 src/gf_mult_130.vhd
ghdl -a --std=08 src/poly1305_block.vhd
ghdl -a --std=08 src/poly1305_mac.vhd
echo "All Phase 2 sources compiled successfully."

echo ""
echo "=== Running Phase 2 testbenches ==="

PASS=0
FAIL=0

for tb in tb_gf_mult_130 tb_poly1305_mac; do
    echo ""
    echo "--- $tb ---"
    ghdl -a --std=08 "sim/${tb}.vhd"
    ghdl -e --std=08 "$tb"
    if ghdl -r --std=08 "$tb" --stop-time=100us 2>&1 | tee /dev/stderr | grep -q "PASSED"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Phase 2 Results: $PASS passed, $FAIL failed ==="
