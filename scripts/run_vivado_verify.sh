#!/bin/bash
# Run Vivado batch-mode verification for ChaCha20 Phase 1
set -e

DIR="/home/arunupscee/Desktop/xtortion/chacha20"
cd "$DIR"

echo "=== Starting Vivado Phase 1 Verification ==="
vivado -mode batch -source scripts/vivado_verify_phase1.tcl \
  -log vivado_phase1.log -journal vivado_phase1.jou 2>&1 | tee vivado_phase1_console.log

echo ""
echo "=== Simulation Results ==="
grep -E "PASSED|FAILED|PASS|FAIL" vivado_phase1.log || echo "No PASSED/FAILED found in log"

echo ""
echo "=== Check vivado_phase1.log for full details ==="
