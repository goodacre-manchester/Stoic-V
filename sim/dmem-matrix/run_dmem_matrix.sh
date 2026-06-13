#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
#
# run_dmem_matrix.sh — the dmem_stall × {IRQ / branch / muldiv} interaction gate.
#
# Closes the one remaining verification cross-matrix: each axis is covered alone
# (irq-stress sweeps the MEI across the pipeline; lmb-contract/scoreboard cover the data
# stall; fwd_stall covers forwarding under back-pressure) but nothing crossed all three.
# This sweeps the MEI injection cycle across `dmem_matrix.s` (whose back-to-back accesses
# put a memory op outstanding while a taken branch / a counting mul/div is in flight) on
# EVERY compliant slave timing. The architectural result (s1 = 638) must be invariant to
# the injection point AND the slave timing, and the interrupt must be taken — a missed
# IRQ turns the wait-spin into a TIMEOUT, a mis-ordered trap/branch/muldiv corrupts s1.
#
# Pure self-check (no Spike): the kernel asserts its own result via tohost, so the sim
# exits non-zero on FAIL/TIMEOUT. WSL: needs the riscv assembler only.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS="$REPO/tests"
SIM="$REPO/sim/obj_dir/Vtb_top"
WORK="$SCRIPT_DIR/work"
AS=riscv64-unknown-elf-as; LD=riscv64-unknown-elf-ld; OC=riscv64-unknown-elf-objcopy
MARCH=rv32im_zba_zbb_zbs_zicsr
FROM=${FROM:-6}; TO=${TO:-240}; HOLD=${HOLD:-70}; MAX=${MAX:-30000}
# Compliant slave timings to cross with the injection sweep. "" = default level-ready
# 1-cycle; +dwait=N = N-wait back-pressure (every access stalls); +dfree = free-running
# (canonical BRAM, b2b gap); +dedge = edge-detect held-ready.
CFGS=("" "+dwait=1" "+dwait=2" "+dwait=3" "+dfree=1" "+dedge=1")

echo "== build unit sim =="
make -C "$REPO/sim" verilate >/dev/null
[ -x "$SIM" ] || { echo "sim not built"; exit 1; }
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

echo "== assemble dmem_matrix.s =="
$AS -march=$MARCH -mabi=ilp32 -I "$TESTS" "$SCRIPT_DIR/dmem_matrix.s" -o t.o
$LD -m elf32lriscv -T "$TESTS/link.ld" t.o -o t.elf
$OC -O binary t.elf t.bin
python3 "$TESTS/gen_hex.py" t.bin t.hex

echo "== sweep MEI injection $FROM..$TO (hold $HOLD) × ${#CFGS[@]} slave timings =="
pass=0; fail=0; firstbad=""
# Every run injects an MEI (the kernel's wait-spin requires the interrupt to be taken,
# like irq_stress.s); architectural invariance to slave timing without interrupts is
# covered by lmb-contract / cosim / scoreboard. This gate's job is the coincidence.
for cfg in "${CFGS[@]}"; do
  label="${cfg:-default}"
  cfgpass=0; cfgfail=0
  for ((at=FROM; at<=TO; at++)); do
    clr=$((at+HOLD))
    if "$SIM" +hex=t.hex +irq_at=$at +irq_clr=$clr +max=$MAX $cfg >"run_${label}_$at.log" 2>&1; then
      cfgpass=$((cfgpass+1))
    else
      cfgfail=$((cfgfail+1)); [ -z "$firstbad" ] && firstbad="$label irq_at=$at"
      printf "  FAIL  %-10s irq_at=%-4d %s\n" "$label" "$at" "$(grep -oE 'FAIL.*|TIMEOUT.*' run_${label}_$at.log | head -1)"
    fi
  done
  pass=$((pass+cfgpass)); fail=$((fail+cfgfail))
  printf "  %-10s : %d/%d injection points PASS\n" "$label" "$cfgpass" "$((TO-FROM+1))"
done

n=$((pass+fail))
echo
echo "dmem-matrix: $pass/$n (slave-timing × injection) points PASS, $fail failed"
[ -n "$firstbad" ] && echo "  first failure: $firstbad"
[ "$fail" -eq 0 ]
