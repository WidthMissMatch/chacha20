#!/usr/bin/env python3
"""
ChaCha20-Poly1305 PyCryptodome reference verifier.
Validates VHDL simulation output against RFC 8439 test vectors.

Usage:
    python3 verify_chacha20_poly1305.py
    python3 verify_chacha20_poly1305.py --key <hex32> --nonce <hex12> --plaintext <hex64>
    python3 verify_chacha20_poly1305.py --vhdl-log <sim_output.txt>

Construction note:
    The VHDL implements a simplified (non-AEAD) ChaCha20-Poly1305:
      1. Poly1305 key  = first 32 bytes of ChaCha20(key, nonce, counter=0)
      2. Ciphertext    = ChaCha20(key, nonce, counter=1) XOR plaintext
      3. Tag           = Poly1305(one_time_key, ciphertext)  [no AAD, no length fields]
    This differs from the full RFC 8439 §2.8 AEAD construction (which includes
    AAD and 16-byte length block).  PyCryptodome's ChaCha20_Poly1305 implements
    the full AEAD; this script uses raw Poly1305 to match the VHDL.
"""

import sys
import argparse

try:
    from Crypto.Cipher import ChaCha20
    from Crypto.Hash  import Poly1305
except ImportError:
    sys.exit("PyCryptodome not found.  Install with:  pip install pycryptodome")

# ---------------------------------------------------------------------------
# RFC 8439 §2.4.2 test vector (ChaCha20 part)
# VHDL expected tag: c6252e9a0a47711f9b0a26d9b516a4d1
# ---------------------------------------------------------------------------
RFC8439_KEY      = bytes.fromhex("000102030405060708090a0b0c0d0e0f"
                                  "101112131415161718191a1b1c1d1e1f")
RFC8439_NONCE    = bytes.fromhex("000000000000004a00000000")
RFC8439_PT       = bytes(64)               # 64 zero bytes
RFC8439_CT_FIRST = 0x22                    # expected ciphertext[0]
# Tag expected by VHDL (raw Poly1305 over ciphertext, no AEAD framing):
RFC8439_TAG_VHDL = bytes.fromhex("c6252e9a0a47711f9b0a26d9b516a4d1")


def chacha20_encrypt(key: bytes, nonce: bytes, plaintext: bytes, counter: int = 0) -> bytes:
    """Encrypt plaintext with ChaCha20, starting at the given block counter."""
    cc = ChaCha20.new(key=key, nonce=nonce)
    cc.seek(counter * 64)   # each block = 64 bytes
    return cc.encrypt(plaintext)


def poly1305_raw(key: bytes, nonce: bytes, message: bytes) -> bytes:
    """
    Compute raw Poly1305 tag over message.
    One-time key derived via RFC 8439 §2.6:
      poly_key = first 32 bytes of ChaCha20(key, nonce, counter=0)
    No AAD, no length fields — matches VHDL poly1305_mac implementation.
    """
    mac = Poly1305.new(key=key, cipher=ChaCha20, nonce=nonce)
    mac.update(message)
    return mac.digest()


def encrypt_and_tag(key: bytes, nonce: bytes, plaintext: bytes):
    """
    ChaCha20 encrypt + raw Poly1305 tag (VHDL-compatible, no AEAD framing).
    Returns (ciphertext, tag).
    """
    ciphertext = chacha20_encrypt(key, nonce, plaintext, counter=1)
    tag = poly1305_raw(key, nonce, ciphertext)
    return ciphertext, tag


def validate_rfc_vector() -> bool:
    """Run the RFC 8439 §2.4.2 vector and report."""
    print("=" * 60)
    print("RFC 8439 §2.4.2 + Raw Poly1305 Test Vector")
    print("=" * 60)
    ct, tag = encrypt_and_tag(RFC8439_KEY, RFC8439_NONCE, RFC8439_PT)
    ok = True

    if ct[0] == RFC8439_CT_FIRST:
        print(f"[PASS] ciphertext[0] = 0x{ct[0]:02X}  (expected 0x{RFC8439_CT_FIRST:02X})")
    else:
        print(f"[FAIL] ciphertext[0] = 0x{ct[0]:02X}  (expected 0x{RFC8439_CT_FIRST:02X})")
        ok = False

    if tag == RFC8439_TAG_VHDL:
        print(f"[PASS] tag = {tag.hex()}")
    else:
        print(f"[FAIL] tag = {tag.hex()}")
        print(f"       exp = {RFC8439_TAG_VHDL.hex()}")
        ok = False

    print(f"\nCiphertext: {ct.hex()}")
    print(f"Tag:        {tag.hex()}")
    return ok


def parse_vhdl_log(logfile: str):
    """
    Parse a GHDL simulation log for lines like:
        CIPHERTEXT: <64-byte hex>
        TAG:        <16-byte hex>
    Returns (ciphertext_hex, tag_hex) or (None, None) if not found.
    """
    ct_hex  = None
    tag_hex = None
    with open(logfile) as f:
        for line in f:
            line = line.strip()
            if line.upper().startswith("CIPHERTEXT:"):
                ct_hex  = line.split(":", 1)[1].strip().replace(" ", "")
            elif line.upper().startswith("TAG:"):
                tag_hex = line.split(":", 1)[1].strip().replace(" ", "")
    return ct_hex, tag_hex


def compare_vhdl_log(logfile: str, key: bytes, nonce: bytes, plaintext: bytes) -> bool:
    """Compare VHDL simulation output with PyCryptodome raw reference."""
    print(f"\nComparing VHDL log: {logfile}")
    ct_ref, tag_ref = encrypt_and_tag(key, nonce, plaintext)
    ct_vhdl_hex, tag_vhdl_hex = parse_vhdl_log(logfile)

    if ct_vhdl_hex is None or tag_vhdl_hex is None:
        print("[WARN] Could not parse CIPHERTEXT/TAG from log file.")
        return False

    ct_vhdl  = bytes.fromhex(ct_vhdl_hex)
    tag_vhdl = bytes.fromhex(tag_vhdl_hex)
    ok = True

    if ct_vhdl == ct_ref:
        print(f"[PASS] Ciphertext matches ({len(ct_ref)} bytes)")
    else:
        print(f"[FAIL] Ciphertext mismatch")
        print(f"  VHDL: {ct_vhdl.hex()}")
        print(f"  Ref:  {ct_ref.hex()}")
        for i, (a, b) in enumerate(zip(ct_vhdl, ct_ref)):
            if a != b:
                print(f"  First diff at byte {i}: VHDL={a:02X} ref={b:02X}")
                break
        ok = False

    if tag_vhdl == tag_ref:
        print(f"[PASS] Poly1305 tag matches ({tag_ref.hex()})")
    else:
        print(f"[FAIL] Poly1305 tag mismatch")
        print(f"  VHDL: {tag_vhdl.hex()}")
        print(f"  Ref:  {tag_ref.hex()}")
        ok = False

    return ok


def main():
    parser = argparse.ArgumentParser(
        description="ChaCha20-Poly1305 PyCryptodome reference verifier (VHDL-compatible)")
    parser.add_argument("--key",       help="32-byte key as hex string (no spaces)")
    parser.add_argument("--nonce",     help="12-byte nonce as hex string (no spaces)")
    parser.add_argument("--plaintext", help="Plaintext as hex string (no spaces)")
    parser.add_argument("--vhdl-log",  help="Path to GHDL simulation log to compare")
    args = parser.parse_args()

    all_ok = True

    # Always run the RFC 8439 built-in vector
    rfc_ok = validate_rfc_vector()
    all_ok = all_ok and rfc_ok

    # Custom vector from CLI
    if args.key or args.nonce or args.plaintext:
        if not (args.key and args.nonce and args.plaintext):
            print("\n[ERROR] --key, --nonce, and --plaintext must all be provided together.")
            sys.exit(1)
        key       = bytes.fromhex(args.key)
        nonce     = bytes.fromhex(args.nonce)
        plaintext = bytes.fromhex(args.plaintext)
        if len(key) != 32:
            print(f"[ERROR] Key must be 32 bytes, got {len(key)}")
            sys.exit(1)
        if len(nonce) != 12:
            print(f"[ERROR] Nonce must be 12 bytes, got {len(nonce)}")
            sys.exit(1)
        ct, tag = encrypt_and_tag(key, nonce, plaintext)
        print("\n" + "=" * 60)
        print("Custom Vector")
        print("=" * 60)
        print(f"Key:        {key.hex()}")
        print(f"Nonce:      {nonce.hex()}")
        print(f"Plaintext:  {plaintext.hex()}")
        print(f"Ciphertext: {ct.hex()}")
        print(f"Tag:        {tag.hex()}")

        if args.vhdl_log:
            cmp_ok = compare_vhdl_log(args.vhdl_log, key, nonce, plaintext)
            all_ok = all_ok and cmp_ok

    elif args.vhdl_log:
        cmp_ok = compare_vhdl_log(args.vhdl_log, RFC8439_KEY, RFC8439_NONCE, RFC8439_PT)
        all_ok = all_ok and cmp_ok

    print("\n" + "=" * 60)
    if all_ok:
        print("OVERALL: PASSED")
    else:
        print("OVERALL: FAILED")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
