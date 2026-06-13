#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
#
# run_wcet.sh — validate the published WCET latency constants (microarchitecture.md §4)
# against the RTL, AND the data-independence (WCET) contract for the operand-dependent
# FUs. For each op it assembles wcet_probe.s at K and 2K dependent ops; the slope
# (cyc2K-cycK)/K is the per-op latency (fixed prologue/fill/drain cancels). For div/mul
# it also runs a fixed K with adversarial operand sets and asserts the cycle count is
# IDENTICAL — non-early-terminating, data-independent timing. WSL: riscv assembler only.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS="$REPO/tests"; SIM="$REPO/sim/obj_dir/Vtb_top"; WORK="$SCRIPT_DIR/work"
AS=riscv64-unknown-elf-as; LD=riscv64-unknown-elf-ld; OC=riscv64-unknown-elf-objcopy
MARCH=rv32im_zba_zbb_zbs_zicsr
K=${K:-64}

# Dependent-chain per-op latency — the WCET-relevant cost when each op's result feeds
# the next. EXACT, fixed integers (no approximation — that is the determinism guarantee):
# the FU accept->result latency (microarchitecture.md §4: MUL_LAT=4, DIV_LAT=34,
# non-early-terminating) PLUS the fixed dependent-issue/forward overhead (2 mul, 3 div)
# to get the result into the following op; load-use and taken-branch are the direct
# penalties. These are the measured, operand-INVARIANT baselines — a change here is a
# real latency regression (update §4 AND this table together, like the determinism
# golden 286). The data-independence check below is the load-bearing assertion.
declare -A EXPECT=( [div]=37 [mul]=6 [loaduse]=4 [branch]=4 )
declare -A OPNUM=(  [div]=0  [mul]=1 [loaduse]=2 [branch]=3 )

echo "== build unit sim =="; make -C "$REPO/sim" verilate >/dev/null
[ -x "$SIM" ] || { echo "sim not built"; exit 1; }
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

# cyc <op> <K> <A> <B>  -> echoes the total cycle count
cyc() {
  local op=$1 k=$2 a=$3 b=$4 tag="${1}_${2}_${3}_${4}"
  $AS -march=$MARCH -mabi=ilp32 -I "$TESTS" \
      --defsym OP=${OPNUM[$op]} --defsym K=$k --defsym A=$a --defsym B=$b \
      "$SCRIPT_DIR/wcet_probe.s" -o "$tag.o" 2>"$tag.aserr" || { echo "ASMERR"; return; }
  $LD -m elf32lriscv -T "$TESTS/link.ld" "$tag.o" -o "$tag.elf" 2>>"$tag.aserr" || { echo "LDERR"; return; }
  $OC -O binary "$tag.elf" "$tag.bin"; python3 "$TESTS/gen_hex.py" "$tag.bin" "$tag.hex"
  "$SIM" +hex="$tag.hex" +max=400000 2>/dev/null | sed -n 's/^CYCLES=//p'
}

fail=0
echo "== per-op latency (slope of K=$K vs 2K dependent ops) vs microarchitecture.md §4 =="
for op in div mul loaduse branch; do
  c1=$(cyc "$op" "$K"        0x40000000 7)
  c2=$(cyc "$op" "$((2*K))"  0x40000000 7)
  if ! [[ "$c1" =~ ^[0-9]+$ && "$c2" =~ ^[0-9]+$ ]]; then
    echo "  $op: MEASURE-FAIL (c1=$c1 c2=$c2)"; fail=$((fail+1)); continue
  fi
  lat=$(( (c2 - c1) / K ))
  exp=${EXPECT[$op]}
  if [ "$lat" -eq "$exp" ]; then ok="OK"; else ok="MISMATCH (doc=$exp)"; fail=$((fail+1)); fi
  printf "  %-8s cyc(%d)=%-6d cyc(%d)=%-6d  -> per-op = %2d cycles   [%s]\n" "$op" "$K" "$c1" "$((2*K))" "$c2" "$lat" "$ok"
done

echo "== data-independence: per-op cycle count must be IDENTICAL across operand sets =="
# div: normal / INT_MIN÷-1 overflow / ÷0 / 0÷x ; mul: normal / INT_MIN² / -1×-1 / 0×0
declare -A SETS=(
  [div]="0x40000000,7 0x80000000,-1 5,0 0,5"
  [mul]="0x40000000,7 0x80000000,0x80000000 -1,-1 0,0"
)
for op in div mul; do
  base=""; inv_ok=1
  for pair in ${SETS[$op]}; do
    a=${pair%,*}; b=${pair#*,}
    c=$(cyc "$op" "$K" "$a" "$b")
    [[ "$c" =~ ^[0-9]+$ ]] || { echo "  $op ($a,$b): MEASURE-FAIL ($c)"; inv_ok=0; continue; }
    if [ -z "$base" ]; then base=$c; fi
    if [ "$c" -ne "$base" ]; then echo "  $op ($a,$b): cyc=$c != $base  DATA-DEPENDENT!"; inv_ok=0; fi
  done
  if [ "$inv_ok" -eq 1 ]; then printf "  %-4s invariant across %d operand sets (cyc=%s)\n" "$op" "$(echo ${SETS[$op]}|wc -w)" "$base"; else fail=$((fail+1)); fi
done

echo
echo "wcet: $([ $fail -eq 0 ] && echo PASS || echo "FAIL ($fail issue(s))")"
[ "$fail" -eq 0 ]
