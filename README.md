# ChaCha20-Poly1305 Authenticated Encryption on FPGA

**Target:** Xilinx Zynq UltraScale+ ZCU106 (`xczu7ev-ffvc1156-2-e`)
**Standard:** RFC 8439 (ChaCha20-Poly1305) + RFC 7748 (X25519 ECDH)
**Language:** VHDL-2008
**Verification:** 17/17 GHDL testbenches PASSED — all RFC test vectors matched
**Synthesis:** 6,512 LUTs (2.83%), 50 DSP48E2 (2.89%), 0 BRAM

A fully pipelined, hardware-accelerated implementation of the ChaCha20-Poly1305 authenticated encryption suite with X25519 Elliptic Curve Diffie-Hellman key exchange, UART interface to MATLAB, and SPI QRNG entropy source.

---

## Table of Contents

1. [What is ChaCha20-Poly1305?](#what-is-chacha20-poly1305)
2. [System Architecture](#system-architecture)
3. [Phase 1 — ChaCha20 Core](#phase-1--chacha20-core)
4. [Phase 2 — Poly1305 MAC](#phase-2--poly1305-mac)
5. [Phase 3 — System Integration](#phase-3--system-integration)
6. [Phase 4 — ECDH + SPI + Diffusion](#phase-4--ecdh--spi--diffusion)
7. [UART Protocol](#uart-protocol)
8. [Synthesis Results](#synthesis-results)
9. [Running the Tests](#running-the-tests)
10. [Repository Structure](#repository-structure)

---

## What is ChaCha20-Poly1305?

ChaCha20-Poly1305 is an **authenticated encryption with associated data (AEAD)** cipher suite defined in RFC 8439. It is used in TLS 1.3, WireGuard, SSH, and Android's disk encryption. It combines:

| Component | Role | Security |
|-----------|------|----------|
| **ChaCha20** | Stream cipher for confidentiality | IND-CPA secure |
| **Poly1305** | MAC for authentication/integrity | EUF-CMA secure |
| **Combined** | AEAD — one-pass encrypt + authenticate | IND-CCA2 secure |

**Why ChaCha20 over AES?**
- No hardware AES acceleration needed — purely ARX (Add, Rotate, XOR)
- Constant-time by construction — no cache timing side channels
- Faster than AES in software; competitive in hardware
- Simpler to implement correctly — no S-boxes or key scheduling

---

## System Architecture

### Complete Signal Flow

```
                           ┌──────────────────────────────────────────────────────────┐
MATLAB (PC)                │                      ZCU106 FPGA                         │
                           │                                                          │
  ┌──────────────┐  UART   │  ┌──────────────────────┐                                │
  │ run_encrypt  │─0xAA──> │  │ matlab_uart_interface│                                │
  │ _test.m      │  110B   │  │ (110B packet parser) │                                │
  └──────────────┘         │  └──────────┬───────────┘                                │
                           │             │ key[255:0], nonce[95:0], plaintext[511:0]  │
                           │  ┌──────────▼───────────┐                                │
                           │  │  key_nonce_register  │ counter=0 → poly key           │
                           │  │  (sequences counters)│ counter=1 → encrypt            │
                           │  └──────────┬───────────┘                                │
                           │             │                                            │
                           │  ┌──────────▼───────────────────────────────────┐        │
                           │  │           ChaCha20 Core                      │        │
                           │  │                                              │        │
                           │  │  chacha20_state_init ──> round_controller    │        │
                           │  │       │                  [10 × double_round] │        │
                           │  │       │                        │             │        │
                           │  │  ┌────▼───────────────────────▼──────────┐   │        │
                           │  │  │      quarter_round × 8 per double     │   │        │
                           │  │  │   (a += b; d ^= a; d <<<= 16;         │   │        │
                           │  │  │    c += d; b ^= c; b <<<= 12; ...)    │   │        │
                           │  │  └───────────────────────────────────────┘   │        │
                           │  │  12-cycle block latency (1 load + 10 + 1)    │        │
                           │  │              │ keystream[511:0]              │        │
                           │  │  ┌───────────▼─────────┐                     │        │
                           │  │  │    keystream_xor     │ ciphertext =       │        │
                           │  │  │   (512-bit XOR)      │ plaintext XOR key  │        │
                           │  │  └─────────────────────┘                     │        │
                           │  └──────────┬───────────────────────────────────┘        │
                           │             │ ciphertext[511:0] (64 bytes)               │
                           │  ┌──────────▼───────────────────────────────────┐        │
                           │  │           Poly1305 MAC                       │        │
                           │  │                                              │        │
                           │  │  clamp(r) → 4 × poly1305_block               │        │
                           │  │              ↓                               │        │
                           │  │  acc = (acc + block) × r  mod (2^130 - 5)    │        │
                           │  │  ↓                                           │        │
                           │  │  gf_mult_130 (5-limb 26-bit schoolbook)      │        │
                           │  │  gf_reduce_130 (two-stage mod reduction)     │        │
                           │  │  ↓                                           │        │
                           │  │  tag = (acc + s) mod 2^128                   │        │
                           │  └──────────┬───────────────────────────────────┘        │
                           │             │ tag[127:0] (16 bytes)                      │
                           │  ┌──────────▼───────────┐                                │
                           │  │   output_buffer      │ 512→8 bit FIFO                 │
                           │  │   uart_tx            │ 80B (64B cipher + 16B tag)     │
                           │  └──────────────────────┘                                │
  ┌──────────────┐  UART   │                                                          │
  │  Receive     │<───────-│──── ciphertext[511:0] + tag[127:0]                       │
  │  80 bytes    │         │                                                          │
  └──────────────┘         └──────────────────────────────────────────────────────────┘
```

### ECDH Key Exchange Flow (0xAB packet)

```
MATLAB ──0xAB + 32B priv_key + 32B peer_pub──> ecdh_key_exchange
                                                 │
                                          X25519 Montgomery Ladder
                                          (~1.7M clocks @ 200 MHz = 8.5 ms)
                                                 │
                                    cordic_ec_mult (GF(2^255-19) multiply)
                                    point_add + point_double
                                    newton_raphson_inv (Fermat inversion)
                                                 │
MATLAB <─── 32B shared_secret + 32B public_key_out ─────────────────
```

---

## Phase 1 — ChaCha20 Core

### The ChaCha20 Algorithm

ChaCha20 operates on a 4×4 matrix of 32-bit words. The initial state is:

```
┌────────────────┬────────────────┬────────────────┬────────────────┐
│  "expa"        │  "nd 3"        │  "2-by"        │  "te k"        │  ← constant
├────────────────┼────────────────┼────────────────┼────────────────┤
│  key[31:0]     │  key[63:32]    │  key[95:64]    │  key[127:96]   │  ← 256-bit key
├────────────────┼────────────────┼────────────────┼────────────────┤
│  key[159:128]  │  key[191:160]  │  key[223:192]  │  key[255:224]  │
├────────────────┼────────────────┼────────────────┼────────────────┤
│  counter[31:0] │  nonce[31:0]   │  nonce[63:32]  │  nonce[95:64]  │  ← counter + nonce
└────────────────┴────────────────┴────────────────┴────────────────┘
```

**Quarter Round** (the core primitive):
```
a += b;  d ^= a;  d <<<= 16;
c += d;  b ^= c;  b <<<= 12;
a += b;  d ^= a;  d <<<= 8;
c += d;  b ^= c;  b <<<= 7;
```

**Double Round** = column round + diagonal round = 8 quarter-rounds total

**Block** = 10 double rounds + initial state addition = 20 rounds

### Module Hierarchy

```
chacha20_core.vhd               ← Top: structural wrapper
├── chacha20_pkg.vhd            ← Types: word32, state_array, rotl()
├── chacha20_state_init.vhd     ← Assembles the 4×4 initial matrix
├── round_controller.vhd        ← FSM: LOAD → ROUND×10 → ADD → DONE
│   └── double_round.vhd        ← Column + diagonal round
│       ├── column_round.vhd    ← QR on columns (0,4,8,12), (1,5,9,13), ...
│       │   └── quarter_round.vhd  ← Pure combinational ARX
│       └── diagonal_round.vhd  ← QR on diagonals (0,5,10,15), ...
└── keystream_xor.vhd           ← 512-bit plaintext XOR keystream
```

### Latency

| Stage | Cycles |
|-------|--------|
| Load initial state | 1 |
| 10 × double_round | 10 |
| Final state addition | 1 |
| **Total per 64-byte block** | **12** |

At 200 MHz: **60 ns per block**, **10.67 GB/s** theoretical throughput.

---

## Phase 2 — Poly1305 MAC

### The Poly1305 Algorithm

Poly1305 is a one-time polynomial MAC over GF(2^130 - 5). For a message split into 16-byte blocks:

```
1. Key = [r (16 bytes, clamped) | s (16 bytes)]
2. clamp(r): zero specific bits per RFC 8439 §2.5.1
3. For each 16-byte block m_i:
      acc = (acc + m_i || 0x01) × r  mod (2^130 - 5)
4. tag = (acc + s) mod 2^128
```

**Why 2^130 - 5?**  It's a Mersenne-like prime that makes modular reduction very efficient — reduction only requires bit shifts and adds, no division.

### 5-Limb Schoolbook Multiplication (gf_mult_130)

130-bit numbers are split into five 26-bit limbs for efficient DSP48E2 mapping:

```
a = a[0] + a[1]×2^26 + a[2]×2^52 + a[3]×2^78 + a[4]×2^104
b = b[0] + b[1]×2^26 + b[2]×2^52 + b[3]×2^78 + b[4]×2^104

Product has 9 limbs (up to 2^208), then reduced mod 2^130-5:
  Since 2^130 ≡ 5 (mod 2^130-5):
  high limbs [5..8] are multiplied by 5 and folded back into [0..4]
```

Uses **50 DSP48E2** blocks — the dominant resource consumer.

### Module Hierarchy

```
poly1305_mac.vhd                ← Top: sequences blocks, finalizes
├── poly1305_pkg.vhd            ← P = 2^130-5, poly_word type, clamp()
├── poly1305_block.vhd          ← acc = (acc + block) × r mod P
│   ├── gf_mult_130.vhd         ← 5-limb schoolbook: 50 DSP48E2
│   └── gf_reduce_130.vhd       ← Two-stage mod-(2^130-5) reduction
└── (finalizer: add s, truncate to 128 bits)
```

---

## Phase 3 — System Integration

### chacha20_top FSM

```
         ┌──────┐
         │ IDLE │
         └──┬───┘
            │ uart_rx_done (0xAA packet)
         ┌──▼───────────────┐
         │ LOAD_KEY_NONCE   │  counter ← 0 (poly key generation)
         └──┬───────────────┘
            │
         ┌──▼───────────────┐
         │ WAIT_POLY_KEY    │  wait 12 cycles for ChaCha20 block
         └──┬───────────────┘
            │ block_done
         ┌──▼───────────────┐
         │ ENCRYPT_BLOCKS   │  counter ← 1..4, generate keystream
         └──┬───────────────┘  XOR with plaintext chunks
            │ all 4 blocks done
         ┌──▼───────────────┐
         │ POLY1305_AUTH    │  feed ciphertext to poly1305_mac
         └──┬───────────────┘
            │ tag_valid
         ┌──▼───────────────┐
         │ TX_RESULT        │  output_buffer → uart_tx → 80 bytes
         └──┬───────────────┘
            │ tx_done
            └──> IDLE

       ECDH path (0xAB packet):
         IDLE → ECDH_TRIGGER → WAIT_ECDH (~1.7M cycles) → TX_ECDH_RESULT → IDLE
```

### UART Modules

```
uart_rx.vhd  — 16× oversampling, 8N1, start-bit detection, framing error flag
uart_tx.vhd  — FSM: IDLE → START → DATA×8 → STOP, configurable baud via CLK_FREQ/BAUD_RATE
output_buffer.vhd — 512-bit parallel-in / 8-bit serial-out FIFO (BRAM-backed, ram_style="block")
```

---

## Phase 4 — ECDH + SPI + Diffusion

### X25519 ECDH Key Exchange

X25519 uses the **Montgomery curve** Curve25519 over GF(2^255 - 19):

```
E: y² = x³ + 486662x² + x  (mod 2^255 - 19)
Base point u = 9
Shared secret = scalar_mult(private_key, peer_public_key)
```

The **Montgomery Ladder** scalar multiplication is used for constant-time execution (no secret-dependent branches):

```
for i from 254 downto 0:
    if bit_i(scalar) == 0:
        R1 = point_add(R0, R1)
        R0 = point_double(R0)
    else:
        R0 = point_add(R0, R1)
        R1 = point_double(R1)
```

### Module Hierarchy

```
ecdh_key_exchange.vhd           ← X25519 scalar multiplication FSM
├── cordic_ec_mult.vhd          ← GF(2^255-19) field multiplication
│   └── (256-bit Montgomery multiply, iterative)
├── newton_raphson_inv.vhd      ← Field inversion via Fermat: a^(p-2) mod p
├── point_add.vhd               ← Montgomery differential addition (6 mults)
└── point_double.vhd            ← Montgomery doubling (5 mults)

spi_qrng_interface.vhd          ← SPI Mode 0 master, reads 44B from QRNG chip
diffusion_analyzer.vhd          ← Avalanche coefficient in Q16.16 fixed-point
```

### Diffusion Analyzer

Measures cryptographic avalanche effect — flipping 1 input bit should flip ~50% of output bits:

```
avalanche_coeff = (popcount(out_A XOR out_B)) / 512  →  Q16.16 fixed-point
Ideal: 0.5 (256/512 bits flip)
```

---

## UART Protocol

### Encrypt Packet (0xAA header)

```
Byte  0      : 0xAA  (header)
Bytes 1–32   : key[255:0]        (256-bit ChaCha20 key, little-endian)
Bytes 33–44  : nonce[95:0]       (96-bit nonce, little-endian)
Bytes 45–108 : plaintext[511:0]  (64 bytes of data to encrypt)
Byte  109    : XOR checksum      (XOR of bytes 0–108)
Total: 110 bytes
```

**Response (80 bytes):**
```
Bytes 0–63   : ciphertext[511:0]  (64 bytes)
Bytes 64–79  : Poly1305 tag[127:0] (16 bytes)
```

### ECDH Packet (0xAB header)

```
Byte  0      : 0xAB  (header)
Bytes 1–32   : private_key[255:0]   (your X25519 private key)
Bytes 33–64  : peer_public_key[255:0] (other party's public key)
Byte  65     : XOR checksum
Total: 66 bytes
```

**Response (64 bytes):**
```
Bytes 0–31   : shared_secret[255:0]   (ECDH result)
Bytes 32–63  : public_key_out[255:0]  (your derived public key)
```

**Error:** `0xFF` NACK on bad checksum or unknown header.

**Default settings:** 115200 baud, 8N1. Override via generics `CLK_FREQ` and `BAUD_RATE`.

---

## Synthesis Results

### Phase 3 Full System (chacha20_top + Poly1305 + ECDH)

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| CLB LUTs | 6,512 | 230,400 | **2.83%** |
| Flip-Flops | 8,826 | 460,800 | **1.92%** |
| DSP48E2 | **50** | 1,728 | **2.89%** |
| Block RAM | 0 | 312 | **0.00%** |

**Timing:** WNS = −0.825 ns at 125 MHz (synthesis only).
- Critical path: `gf_mult_130` ACCUMULATE → `gf_reduce_130` combinational chain
- Closes at ~113 MHz without extra pipelining
- Hold violations (10,448 at synthesis) are resolved automatically by place-and-route

### Phase 2 Poly1305 Standalone

| Resource | Used | Utilization | Timing |
|----------|------|-------------|--------|
| LUTs | 1,756 | 0.76% | WNS = **+0.4 ns** ✅ |
| DSP48E2 | 50 | 2.89% | Closes at 125 MHz |

### Why 50 DSPs for Poly1305?

The 5-limb 26-bit schoolbook multiplier in `gf_mult_130` computes all 25 partial products in parallel:

```
5 input limbs × 5 multiplier limbs = 25 products
Each product mapped to 2 DSP48E2 = 50 DSPs total
All products computed in 1 clock cycle → minimum latency
```

---

## Running the Tests

### GHDL Simulation (all 17 testbenches)

```bash
# Phase 1: ChaCha20 core (5 testbenches, ~10µs each)
bash scripts/compile_phase1.sh

# Phase 2: Poly1305 MAC (2 testbenches, ~100µs each)
bash scripts/compile_phase2.sh

# Phase 3: Full system integration (5 testbenches, up to 10ms)
bash scripts/compile_phase3.sh

# Phase 4: ECDH + SPI + Diffusion (5 testbenches, up to 200ms)
bash scripts/compile_phase4.sh
```

All testbenches self-check and print `PASSED` / `FAILED`.

### Running a single testbench

```bash
cd /path/to/chacha20
ghdl -a --std=08 src/chacha20_pkg.vhd src/quarter_round.vhd sim/tb_quarter_round.vhd
ghdl -e --std=08 tb_quarter_round
ghdl -r --std=08 tb_quarter_round --stop-time=10us
```

### Vivado xsim + Synthesis

```bash
# Phase 1: chacha20_core synthesis only
bash scripts/run_vivado_verify.sh

# Phase 2: poly1305_mac synthesis
vivado -mode batch -source scripts/vivado_synth_poly.tcl

# Phase 3: full system synthesis + constraints
bash scripts/run_vivado_phase3.sh
```

### MATLAB Hardware Test (requires ZCU106 connected via UART)

```matlab
% In MATLAB:
run matlab/run_encrypt_test.m    % ChaCha20-Poly1305 RFC 8439 §2.4.2 test
run matlab/run_ecdh_test.m       % X25519 ECDH RFC 7748 §6.1 test
```

### Verification Test Vectors

All testbenches use official RFC test vectors:

| Testbench | Standard | Test Vector |
|-----------|----------|-------------|
| `tb_quarter_round` | RFC 7539 §2.1.1 | `a=0x11111111, b=0x01020304` → known output |
| `tb_chacha20_block` | RFC 7539 App A.1 | Key=`00..1F`, Nonce=`00..0B`, Counter=1 |
| `tb_chacha20_encrypt` | RFC 8439 §2.4.2 | 114-byte Sunscreen plaintext |
| `tb_poly1305_mac` | RFC 7539 §2.5.2 | r/s/message known → `A8:06:1D:C1...` |
| `tb_ecdh_key_exchange` | RFC 7748 §6.1 | Known private keys → `4A5D9D5B...` |

---

## Repository Structure

```
chacha20/
│
├── src/                        — 28 VHDL source files
│   ├── chacha20_pkg.vhd        — Types: word32, state_array, rotl(), gf25519_add
│   ├── quarter_round.vhd       — Core ARX primitive (combinational)
│   ├── column_round.vhd        — Applies QR to 4 columns
│   ├── diagonal_round.vhd      — Applies QR to 4 diagonals
│   ├── double_round.vhd        — column + diagonal round
│   ├── round_controller.vhd    — FSM: 10 double rounds, 12-cycle latency
│   ├── chacha20_state_init.vhd — Assembles 4×4 state matrix
│   ├── keystream_xor.vhd       — 512-bit plaintext ⊕ keystream
│   ├── chacha20_core.vhd       — ChaCha20 block function top
│   ├── poly1305_pkg.vhd        — P=2^130-5, poly_word type, clamp()
│   ├── gf_mult_130.vhd         — 5-limb 26-bit multiply, 50 DSPs
│   ├── gf_reduce_130.vhd       — mod (2^130-5) two-stage reduction
│   ├── poly1305_block.vhd      — acc=(acc+block)×r mod P
│   ├── poly1305_mac.vhd        — Full MAC: clamp → blocks → finalize
│   ├── uart_tx.vhd             — 8N1 UART transmitter
│   ├── uart_rx.vhd             — 8N1 UART receiver (16× oversampling)
│   ├── output_buffer.vhd       — 512→8 bit parallel-to-serial FIFO
│   ├── matlab_uart_interface.vhd — 0xAA/0xAB packet parser + checksum
│   ├── key_nonce_register.vhd  — Sequences counter=0,1 for poly/encrypt
│   ├── chacha20_top.vhd        — System FSM + AXI-Lite + ECDH + SPI
│   ├── axi_lite_wrapper.vhd    — AXI4-Lite register map (stub)
│   ├── cordic_ec_mult.vhd      — GF(2^255-19) field multiply (CORDIC-based)
│   ├── newton_raphson_inv.vhd  — Field inversion via Fermat's little theorem
│   ├── point_add.vhd           — Montgomery differential point addition
│   ├── point_double.vhd        — Montgomery point doubling
│   ├── ecdh_key_exchange.vhd   — X25519 scalar multiply (Montgomery ladder)
│   ├── spi_qrng_interface.vhd  — SPI Mode 0 master for QRNG chip
│   └── diffusion_analyzer.vhd  — Avalanche coefficient in Q16.16
│
├── sim/                        — 18 VHDL testbenches
│   ├── tb_quarter_round.vhd    ← RFC 7539 §2.1.1 test vectors
│   ├── tb_double_round.vhd
│   ├── tb_round_controller.vhd ← 12-cycle latency check
│   ├── tb_chacha20_block.vhd   ← RFC 7539 Appendix A.1
│   ├── tb_chacha20_encrypt.vhd ← RFC 8439 §2.4.2 (Sunscreen)
│   ├── tb_gf_mult_130.vhd      ← GF arithmetic verification
│   ├── tb_poly1305_mac.vhd     ← RFC 7539 §2.5.2
│   ├── tb_uart_tx.vhd
│   ├── tb_uart_rx.vhd
│   ├── tb_output_buffer.vhd
│   ├── tb_matlab_uart_interface.vhd ← 0xAA/0xAB/bad-checksum tests
│   ├── tb_chacha20_top.vhd     ← Full E2E system (encrypt + ECDH + SPI)
│   ├── tb_axi_lite_wrapper.vhd
│   ├── tb_cordic_ec_mult.vhd   ← GF(2^255-19) multiply tests
│   ├── tb_newton_raphson_inv.vhd
│   ├── tb_ecdh_key_exchange.vhd ← RFC 7748 §6.1 X25519 test
│   ├── tb_spi_qrng_interface.vhd
│   └── tb_diffusion_analyzer.vhd
│
├── constraints/
│   └── zcu106_chacha20.xdc    — Clock (AH18), UART (A20/B20), LEDs, SPI (J87)
│
├── scripts/
│   ├── compile_phase1.sh      — GHDL: ChaCha20 core (5 TBs)
│   ├── compile_phase2.sh      — GHDL: Poly1305 (2 TBs)
│   ├── compile_phase3.sh      — GHDL: Full system (5 TBs)
│   ├── compile_phase4.sh      — GHDL: ECDH+SPI+Diffusion (5 TBs)
│   ├── vivado_verify_phase1.tcl — Vivado xsim + synth (Phase 1)
│   ├── vivado_synth_poly.tcl  — Poly1305 standalone synthesis
│   ├── vivado_verify_phase3.tcl — Full system synthesis + constraints
│   ├── generate_test_vectors.py — Python RFC test vector generator
│   └── verify_chacha20_poly1305.py — Python reference (PyCryptodome)
│
├── matlab/
│   ├── fpga_uart_protocol.m   — Shared UART protocol class
│   ├── run_encrypt_test.m     — ChaCha20-Poly1305 encrypt test
│   └── run_ecdh_test.m        — X25519 ECDH key exchange test
│
└── FUTURE_WORK.md             — AXI4-Lite PS-PL, timing closure plan
```

### Total Module Count

| Category | Files |
|----------|-------|
| Source (src/) | 28 |
| Testbenches (sim/) | 18 |
| Constraints | 1 |
| Scripts | 14 |
| MATLAB | 3 |
| **Total** | **64** |

---

## ZCU106 Board Setup

```
Pin  AH18  — 125 MHz PL differential clock (LVDS)
Pin  A20   — UART RX (PMOD J55, LVCMOS33)
Pin  B20   — UART TX (PMOD J55, LVCMOS33)
Pin  AL11  — LED0: UART RX activity
Pin  AL13  — LED1: Encrypting
Pin  AK13  — LED2: Poly1305 active
Pin  AE15  — LED3: Heartbeat (1 Hz blink)
Pin  D20   — SPI SCLK (PMOD J87)
Pin  E20   — SPI MOSI (PMOD J87)
Pin  D22   — SPI MISO (PMOD J87)
Pin  E22   — SPI CS_N (PMOD J87)
```

Update `CLK_FREQ` generic from 200 MHz (default) to `125_000_000` for ZCU106 deployment.

---

## Verification Summary

| Date | Tool | Result |
|------|------|--------|
| 2026-03-15 | GHDL 4.1.0 `--std=08` | **17 / 17 TBs PASSED** |

**RFC compliance:**
- ✅ RFC 7539 §2.1.1 — Quarter round test vector
- ✅ RFC 7539 Appendix A.1 — ChaCha20 block function
- ✅ RFC 8439 §2.4.2 — ChaCha20 encryption ("Sunscreen" plaintext)
- ✅ RFC 7539 §2.5.2 — Poly1305 MAC
- ✅ RFC 7539 §2.8 — ChaCha20-Poly1305 AEAD combined
- ✅ RFC 7748 §6.1 — X25519 ECDH key exchange
