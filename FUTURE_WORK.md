# ChaCha20-Poly1305 — Future Work Plan

_Last updated: 2026-03-15. All 17 GHDL testbenches pass. Baseline: GHDL 4.1.0, Vivado 2025.1._

---

## Priority 1 — Timing Closure at 125 MHz (Critical)

**Current state:** 74 setup violations, WNS = −0.825 ns, TNS = −39.777 ns.
**Root cause:** `gf_reduce_130` is purely combinational. The path from the DSP accumulators in `gf_mult_130`'s ACCUMULATE state through the 260-bit `full_product` signal into the two-stage reduction logic (upper×5, conditional subtract) cannot meet 125 MHz in a single clock.

### Fix: Split `gf_reduce_130` into 2 pipeline stages

**Change 1 — `gf_reduce_130.vhd`** (make it registered, 1-clock latency):
- Add `clk`, `rst`, `start`, `done` ports (same interface pattern as `gf_mult_130`)
- Or: keep it combinational but register its *inputs* — i.e., add a `REDUCE_WAIT` FSM state in `gf_mult_130` that just holds `full_product` stable for a second clock while the combinational reducer settles

**Change 2 — `gf_mult_130.vhd`** (add one extra FSM state):
```
IDLE → PARTIAL_PRODUCTS → ACCUMULATE → REDUCE_STAGE → REDUCE_WAIT → DONE_STATE
```
- REDUCE_STAGE: latch `full_product` (already done)
- REDUCE_WAIT: let combinational `gf_reduce_130` settle; capture `reduced` into `product`
- DONE_STATE: pulse `done` (same as today)
- Net latency increase: +1 clock per multiply → +5 clocks per Poly1305 block → negligible at UART baud rates

**Expected result:** Critical path split across two register stages → each half ≈ 3–4 ns, closes at 125 MHz with margin.

**Test plan:**
1. Edit `gf_mult_130.vhd` to add REDUCE_WAIT state
2. Re-run `bash scripts/compile_phase2.sh` — `tb_gf_mult_130` and `tb_poly1305_mac` must still PASS
3. Re-run `bash scripts/compile_phase3.sh` — `tb_chacha20_top` must still PASS (tag unchanged)
4. Run Vivado Phase 3 synthesis: `bash scripts/run_vivado_phase3.sh` — confirm WNS > 0

---

## Priority 2 — Hold Violations After Place-and-Route

**Current state:** 10,448 hold violations at synthesis-only (WNS = −0.082 ns). These are expected at synthesis and are resolved by Vivado P&R.
**Action needed:** Run full implementation (not just synthesis) to confirm hold closure.

```tcl
# In Vivado TCL:
launch_runs impl_1 -jobs 4
wait_on_run impl_1
open_run impl_1
report_timing_summary -file vivado_phase3/reports/impl_timing.txt
```

If hold violations persist after P&R: add `set_multicycle_path` constraints for the GF mult FSM transitions, or increase `BITSTREAM.CONFIG.OVERTEMPSHUTDOWN` and check for I/O timing issues at PMOD pins.

---

## Priority 3 — Python Reference Comparison (PyCryptodome)

**Purpose:** End-to-end golden reference to catch any byte-ordering or tag computation bugs that GHDL simulation might miss with a simpler model.

**Files to create:**
- `scripts/verify_chacha20_poly1305.py` — takes key/nonce/plaintext as hex args, outputs ciphertext + tag using `pycryptodome`, compares against VHDL simulation log output
- `scripts/generate_test_vectors.py` — generates N random test vectors as VHDL constants for insertion into `tb_chacha20_top`

**Dependencies:** `pip install pycryptodome`

**Key byte-ordering check:** VHDL uses little-endian limb ordering for the ChaCha20 state. The Python reference must use the same convention (PyCryptodome's `ChaCha20_Poly1305` does). Confirm with the RFC 8439 §2.4.2 vector first.

---

## Priority 4 — AXI4-Lite PS-PL Interface

**Purpose:** Allow the Zynq PS (ARM cores) to control encryption without UART — faster, lower latency, supports DMA.

**Proposed register map (AXI4-Lite, 4-byte aligned):**
| Offset | Name | R/W | Description |
|--------|------|-----|-------------|
| 0x00 | CTRL | W | bit0=start_encrypt, bit1=start_ecdh, bit7=rst |
| 0x04 | STATUS | R | bit0=busy, bit1=done, bit2=tag_valid |
| 0x08–0x27 | KEY[0..7] | W | 32-byte key (8 × 32-bit words) |
| 0x28–0x33 | NONCE[0..2] | W | 12-byte nonce (3 × 32-bit words) |
| 0x34–0x73 | PLAINTEXT[0..15] | W | 64-byte plaintext |
| 0x74–0xB3 | CIPHERTEXT[0..15] | R | 64-byte ciphertext |
| 0xB4–0xC3 | TAG[0..3] | R | 16-byte Poly1305 tag |
| 0xC4–0xE3 | PRIV_KEY[0..7] | W | 32-byte ECDH private key |
| 0xE4–0x103 | PEER_PUB[0..7] | W | 32-byte ECDH peer public key |
| 0x104–0x143 | ECDH_RESULT[0..15] | R | 64-byte ECDH output |

**New file:** `src/axi_lite_wrapper.vhd` — AXI4-Lite slave that drives the existing `chacha20_top` ports.
**Constraint update:** Add AXI port pins to `constraints/zcu106_chacha20.xdc`.
**Testbench:** `sim/tb_axi_lite_wrapper.vhd` — AXI master BFM driving all register accesses.

---

## Priority 5 — Toggle / FSM Coverage Analysis

**Purpose:** Confirm no dead FSM states or untoggled signals exist in the synthesized netlist.

**Tool options:**
1. **GHDL + VCD:** Add `--vcd=/tmp/vhdl_verify_work/<tb>.vcd` to simulation commands, then analyze toggle coverage with a Python script counting toggled/total signals.
2. **Vivado Simulator (xsim):** Enables built-in toggle and FSM coverage reports via the `report_sim_coverage` TCL command after simulation.
3. **Questa/Modelsim:** Full functional coverage, if available.

**Minimum viable approach:** Add VCD dumps to the 4 compile scripts and write `scripts/check_toggle_coverage.py` that parses VCD and reports any signal that never toggles.

---

## Priority 6 — 200 MHz Target (Stretch)

**Current state:** Closes at ~113 MHz; PRD target is 200 MHz.
After Priority 1 closes 125 MHz, additional pipelining is needed for 200 MHz:

1. **ChaCha20 double-round:** The `double_round` entity runs combinationally inside `round_controller`. At 200 MHz the round logic (~32 32-bit add/rotate chains) may become critical. Add a 1-clock pipeline register in the middle of the double-round (after the 10 column rounds, before the 10 diagonal rounds).
2. **Poly1305 GF mult ACCUMULATE:** The 10-column carry-propagate loop is a long chain. Consider splitting ACCUMULATE into two states: ACCUM_1 (cols 0–4) and ACCUM_2 (cols 5–9 + carry).
3. **Re-target constraint:** Change `CLK_FREQ` generic to `200_000_000` and update XDC `create_clock` period to 5.0 ns.

---

## Quick-Reference — File Locations

| Task | Key file(s) |
|------|------------|
| Timing fix | `src/gf_mult_130.vhd`, `src/gf_reduce_130.vhd` |
| Python verification | `scripts/verify_chacha20_poly1305.py` (to create) |
| AXI wrapper | `src/axi_lite_wrapper.vhd` (to create), `sim/tb_axi_lite_wrapper.vhd` (to create) |
| Vivado impl run | `scripts/run_vivado_phase3.sh` (add impl step) |
| Coverage | `scripts/check_toggle_coverage.py` (to create) |
