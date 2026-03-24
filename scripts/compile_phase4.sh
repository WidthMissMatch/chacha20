#!/bin/bash
# ChaCha20-Poly1305 Phase 4: Compile and run ECDH + SPI testbenches with GHDL
set -e

DIR="/home/arunupscee/Desktop/xtortion/chacha20"
cd "$DIR"

echo "=== Compiling Phase 1 dependencies ==="
ghdl -a --std=08 src/chacha20_pkg.vhd
ghdl -a --std=08 src/quarter_round.vhd
ghdl -a --std=08 src/double_round.vhd
ghdl -a --std=08 src/column_round.vhd
ghdl -a --std=08 src/diagonal_round.vhd
ghdl -a --std=08 src/chacha20_state_init.vhd
ghdl -a --std=08 src/round_controller.vhd
ghdl -a --std=08 src/keystream_xor.vhd
ghdl -a --std=08 src/chacha20_core.vhd

echo "=== Compiling Phase 4 ECDH sources ==="
ghdl -a --std=08 src/cordic_ec_mult.vhd
ghdl -a --std=08 src/newton_raphson_inv.vhd
ghdl -a --std=08 src/point_add.vhd
ghdl -a --std=08 src/point_double.vhd
ghdl -a --std=08 src/ecdh_key_exchange.vhd
ghdl -a --std=08 src/diffusion_analyzer.vhd
ghdl -a --std=08 src/spi_qrng_interface.vhd
echo "All Phase 4 sources compiled successfully."

echo ""
echo "=== Running Phase 4 testbenches ==="

PASS=0
FAIL=0

for tb in tb_cordic_ec_mult tb_newton_raphson_inv tb_ecdh_key_exchange tb_spi_qrng_interface tb_diffusion_analyzer; do
    echo ""
    echo "--- $tb ---"
    ghdl -a --std=08 "sim/${tb}.vhd"
    ghdl -e --std=08 "$tb"

    if [ "$tb" = "tb_ecdh_key_exchange" ]; then
        STOP_TIME="200ms"
    elif [ "$tb" = "tb_newton_raphson_inv" ]; then
        STOP_TIME="5ms"
    elif [ "$tb" = "tb_cordic_ec_mult" ]; then
        STOP_TIME="50us"
    elif [ "$tb" = "tb_diffusion_analyzer" ]; then
        STOP_TIME="200ns"
    else
        STOP_TIME="1ms"
    fi

    if ghdl -r --std=08 "$tb" --stop-time=$STOP_TIME 2>&1 | tee /dev/stderr | grep -q "PASSED"; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done

echo ""
echo "=== Phase 4 Results: $PASS passed, $FAIL failed ==="
