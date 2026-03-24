#!/bin/bash
# Comprehensive Vivado verification: 17 TBs + synthesis + P&R
# Skips tb_ecdh_key_exchange (200ms sim time — use GHDL for that)
set -e

DIR="/home/arunupscee/Desktop/xtortion/chacha20"
cd "$DIR"

echo "=== Starting Comprehensive Vivado Verification ==="
echo "  TCL: scripts/vivado_verify_all.tcl"
echo "  Logs: vivado_all.log  vivado_all_console.log"
echo ""

vivado -mode batch \
  -source scripts/vivado_verify_all.tcl \
  -log vivado_all.log \
  -journal vivado_all.jou \
  2>&1 | tee vivado_all_console.log

echo ""
echo "=== Simulation Results (grep PASSED/FAILED) ==="
grep -E "PASSED|FAILED|RESULT:" vivado_all.log 2>/dev/null || \
  grep -E "PASSED|FAILED|RESULT:" vivado_all_console.log || \
  echo "  (check vivado_all.log)"

echo ""
echo "=== Timing Summary ==="
grep -E "WNS|TNS|Setup :|SYNTH TIMING|IMPL TIMING" vivado_all_console.log 2>/dev/null || true

echo ""
echo "=== Reports ==="
ls -lh vivado_all/reports/ 2>/dev/null || echo "  (no reports dir yet)"
