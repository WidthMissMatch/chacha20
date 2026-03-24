#!/bin/bash
set -e
DIR="/home/arunupscee/Desktop/xtortion/chacha20"
cd "$DIR"

echo "=== Starting Vivado Phase 3 Verification ==="
vivado -mode batch -source scripts/vivado_verify_phase3.tcl \
  -log vivado_phase3.log -journal vivado_phase3.jou 2>&1 | tee vivado_phase3_console.log

echo ""
echo "=== Simulation Results ==="
grep -E "PASSED|FAILED|PASS|FAIL" vivado_phase3.log || echo "No PASSED/FAILED found in log"

echo ""
echo "=== Check vivado_phase3.log for full details ==="
