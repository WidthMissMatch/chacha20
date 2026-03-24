#!/bin/bash
# ChaCha20-Poly1305 Phase 3: Compile and run UART/buffer/system testbenches with GHDL
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

echo "=== Compiling Phase 2 dependencies ==="
ghdl -a --std=08 src/poly1305_pkg.vhd
ghdl -a --std=08 src/gf_reduce_130.vhd
ghdl -a --std=08 src/gf_mult_130.vhd
ghdl -a --std=08 src/poly1305_block.vhd
ghdl -a --std=08 src/poly1305_mac.vhd

echo "=== Compiling Phase 3 sources ==="
ghdl -a --std=08 src/uart_tx.vhd
ghdl -a --std=08 src/uart_rx.vhd
ghdl -a --std=08 src/output_buffer.vhd
ghdl -a --std=08 src/matlab_uart_interface.vhd
ghdl -a --std=08 src/key_nonce_register.vhd

echo "=== Compiling Phase 4 ECDH/SPI dependencies for chacha20_top ==="
ghdl -a --std=08 src/cordic_ec_mult.vhd
ghdl -a --std=08 src/newton_raphson_inv.vhd
ghdl -a --std=08 src/point_add.vhd
ghdl -a --std=08 src/point_double.vhd
ghdl -a --std=08 src/ecdh_key_exchange.vhd
ghdl -a --std=08 src/spi_qrng_interface.vhd

ghdl -a --std=08 src/chacha20_top.vhd
echo "All Phase 3 sources compiled successfully."

echo ""
echo "=== Running Phase 3 testbenches ==="

PASS=0
FAIL=0

for tb in tb_uart_tx tb_uart_rx tb_output_buffer tb_matlab_uart_interface tb_chacha20_top; do
    echo ""
    echo "--- $tb ---"
    ghdl -a --std=08 "sim/${tb}.vhd"
    ghdl -e --std=08 "$tb"

    # Use longer stop time for system-level TB
    if [ "$tb" = "tb_chacha20_top" ]; then
        STOP_TIME="5ms"
    elif [ "$tb" = "tb_matlab_uart_interface" ]; then
        STOP_TIME="10ms"
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
echo "=== Phase 3 Results: $PASS passed, $FAIL failed ==="
