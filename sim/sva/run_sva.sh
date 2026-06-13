#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
#
# run_sva.sh — assertion-based verification of the LMB master protocol. Builds the
# unit sim with the `tb/sva/rv_lmb_sva.sv` bind + `verilator --assert`, and runs the
# directed suite under the default slave AND the randomized slave (+drand seeds),
# checking that the concurrent SVA properties (single-outstanding, one strobe per
# access, strobe sequencing — the rc4/rc7 bus invariants) NEVER fire. These same
# properties are the basis for the formal flow (docs/verification.md §4.3).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
R="$REPO/rtl/core"; T="$REPO/tb"

cd "$REPO/sim"
echo "== build unit sim with SVA bind + --assert =="
verilator --cc --exe --build -j 0 -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  --top-module tb_top -I"$R" --assert \
  "$R/rv_pkg.sv" "$R/rv_alu.sv" "$R/rv_bitmanip.sv" "$R/rv_regfile.sv" "$R/rv_decode.sv" \
  "$R/rv_muldiv.sv" "$R/rv_csr.sv" "$R/rv_core.sv" "$R/mbv.sv" \
  "$T/sva/rv_lmb_sva.sv" "$T/models/lmb_bram.sv" "$T/tb_top.sv" "$T/cpp/sim_main.cpp" \
  -o Vtb_sva --Mdir obj_dir_sva >/tmp/sva_build.log 2>&1 || { echo "BUILD-FAIL"; tail -12 /tmp/sva_build.log; exit 1; }
SIM="$REPO/sim/obj_dir_sva/Vtb_sva"

cd "$REPO"
python3 tests/run_tests.py --build-only 'tests/*.s' >/dev/null 2>&1
echo "== run directed suite under default + randomized timing; assert zero SVA failures =="
fail=0; total=0; runs=0
for s in tests/*.s; do
  name="$(basename "${s%.s})")"; name="$(basename "${s%.s}")"
  hex="sim/build/$name.hex"; [ -f "$hex" ] || continue
  for cfg in "" "+drand=1" "+drand=7" "+drand=42"; do
    runs=$((runs+1))
    out=$("$SIM" +hex="$hex" +tohost=7000 +max=200000 $cfg 2>&1 || true)
    if echo "$out" | grep -qiE 'Assertion failed|assert.*fail'; then
      echo "  SVA-FAIL  $name $cfg"; echo "$out" | grep -iE 'Assertion' | head -3 | sed 's/^/      /'; fail=$((fail+1))
    fi
  done
  total=$((total+1))
done
echo
echo "sva: $total tests × 4 timings = $runs runs, $fail SVA assertion failures (LMB protocol: single-outstanding, one-strobe-per-access, sequencing)"
[ "$fail" -eq 0 ]
