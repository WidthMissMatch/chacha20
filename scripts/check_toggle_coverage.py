#!/usr/bin/env python3
"""
VCD toggle coverage analyser for ChaCha20-Poly1305 GHDL testbenches.

Usage:
    python3 check_toggle_coverage.py <vcd_file> [<vcd_file2> ...]
    python3 check_toggle_coverage.py /tmp/vhdl_cov/tb_chacha20_top.vcd

Reports:
  - Total signals, toggled signals, toggle coverage %
  - Signals that never toggled (potential dead logic)
  - FSM state signals (named *state*, *fsm*, *current_state*) — highlighted separately
"""

import sys
import os
import re
from collections import defaultdict
from typing import Dict, List, Tuple, Set


def parse_vcd(filepath: str) -> Tuple[Dict[str, str], Dict[str, bool]]:
    """
    Parse a VCD file.

    Returns:
      name_map : dict  id_code -> full_signal_name
      toggled  : dict  id_code -> True if signal changed value at least once
    """
    name_map: Dict[str, str] = {}    # id_code -> name
    scope_stack: List[str] = []
    toggled: Dict[str, bool] = {}
    last_value: Dict[str, str] = {}

    with open(filepath, "r", errors="replace") as f:
        in_header = True
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Header parsing
            if line.startswith("$scope"):
                parts = line.split()
                if len(parts) >= 3:
                    scope_stack.append(parts[2])

            elif line.startswith("$upscope"):
                if scope_stack:
                    scope_stack.pop()

            elif line.startswith("$var"):
                # $var wire 1 #id signal_name $end
                parts = line.split()
                if len(parts) >= 5:
                    id_code = parts[3]
                    sig_name = parts[4].split("[")[0]   # strip bus index
                    full_name = "/".join(scope_stack + [sig_name]) if scope_stack else sig_name
                    name_map[id_code] = full_name
                    toggled[id_code] = False
                    last_value[id_code] = None

            elif line.startswith("$dumpvars") or line.startswith("$end"):
                in_header = False

            # Value changes
            if not in_header or "$dumpvars" in line:
                # Scalar: 0id, 1id, xid, zid
                m = re.match(r'^([01xzXZ])(\S+)$', line)
                if m:
                    val, id_code = m.group(1), m.group(2)
                    if id_code in last_value:
                        prev = last_value[id_code]
                        if prev is not None and prev != val and val in ('0', '1'):
                            toggled[id_code] = True
                        if val in ('0', '1'):
                            last_value[id_code] = val

                # Vector: b<value> <id>
                m2 = re.match(r'^b([01xzXZ]+)\s+(\S+)$', line)
                if m2:
                    val, id_code = m2.group(1), m2.group(2)
                    if id_code in last_value:
                        prev = last_value[id_code]
                        if prev is not None and prev != val:
                            if any(c in ('0', '1') for c in val):
                                toggled[id_code] = True
                        last_value[id_code] = val

    return name_map, toggled


def analyse(filepath: str) -> bool:
    """Analyse one VCD file and print a coverage report. Returns True if coverage >= 80%."""
    if not os.path.exists(filepath):
        print(f"[ERROR] File not found: {filepath}")
        return False

    print(f"\n{'=' * 65}")
    print(f"VCD: {filepath}")
    print(f"{'=' * 65}")

    name_map, toggled = parse_vcd(filepath)

    total = len(toggled)
    if total == 0:
        print("[WARN] No signals found in VCD file.")
        return False

    toggled_count = sum(1 for v in toggled.values() if v)
    coverage_pct  = 100.0 * toggled_count / total

    print(f"Total signals  : {total}")
    print(f"Toggled        : {toggled_count}")
    print(f"Toggle coverage: {coverage_pct:.1f}%")

    # FSM state signals
    fsm_ids = [id_code for id_code, name in name_map.items()
               if any(kw in name.lower() for kw in ("state", "fsm", "current_state"))]

    if fsm_ids:
        print(f"\n--- FSM / state signals ({len(fsm_ids)}) ---")
        for id_code in sorted(fsm_ids, key=lambda x: name_map[x]):
            status = "[TOGGLE]" if toggled[id_code] else "[STATIC]"
            print(f"  {status}  {name_map[id_code]}")

    # Signals that never toggled (potential dead logic), skip clock/reset
    never_toggled = [
        name_map[id_code] for id_code, v in toggled.items()
        if not v and not any(kw in name_map[id_code].lower()
                             for kw in ("clk", "clock", "rst", "reset"))
    ]
    if never_toggled:
        print(f"\n--- Signals that never toggled ({len(never_toggled)}) ---")
        for name in sorted(never_toggled)[:50]:    # limit to 50 for readability
            print(f"  [STATIC]  {name}")
        if len(never_toggled) > 50:
            print(f"  ... and {len(never_toggled) - 50} more")

    threshold = 80.0
    passed = coverage_pct >= threshold
    result = "PASS" if passed else "WARN"
    print(f"\n[{result}] Toggle coverage {coverage_pct:.1f}% "
          f"({'>='+str(int(threshold)) if passed else '<'+str(int(threshold))}% threshold)")
    return passed


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    vcd_files = sys.argv[1:]
    results = []
    for vf in vcd_files:
        ok = analyse(vf)
        results.append((vf, ok))

    print(f"\n{'=' * 65}")
    print("SUMMARY")
    print(f"{'=' * 65}")
    for vf, ok in results:
        status = "PASS" if ok else "WARN"
        print(f"  [{status}]  {os.path.basename(vf)}")
    all_ok = all(ok for _, ok in results)
    print(f"\nOverall: {'PASSED' if all_ok else 'WARNINGS (see above)'}")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
