#!/usr/bin/env bash
# run_irq_stress.sh — sweep the MEI injection cycle across the whole pipeline.
#
# Builds tests/irq_stress.s once and runs it many times, firing the interrupt at
# every cycle in a window that spans the mul, div, load-use, and branch-loop of
# the test's computation. Each run must PASS: the transparent ISR must leave the
# result unchanged AND the interrupt must actually be taken (the test's wait-spin
# turns a missed/dropped interrupt into a TIMEOUT). This stresses interrupt entry
# at awkward points (mid-mul/div deferral, load shadow, branch redirect) and the
# mret resume path far more than the single directed trap test.
#
# irq is held high for HOLD cycles (>= divide latency) so it is guaranteed
# latched regardless of injection point (level-sensitive, no edge latch), then
# deasserted so the program can finish.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS="$REPO/tests"
SIM="$REPO/sim/obj_dir/Vtb_top"
WORK="$SCRIPT_DIR/work"
export PATH="${SPIKE_BIN:-$HOME/riscv-tools/bin}:$PATH"
AS=riscv64-unknown-elf-as; LD=riscv64-unknown-elf-ld; OC=riscv64-unknown-elf-objcopy
MARCH=rv32im_zba_zbb_zbs_zicsr
FROM=${FROM:-12}; TO=${TO:-110}; HOLD=${HOLD:-50}; MAX=${MAX:-12000}

echo "== build unit sim =="
make -C "$REPO/sim" verilate >/dev/null
[ -x "$SIM" ] || { echo "sim not built"; exit 1; }
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

echo "== assemble irq_stress.s =="
$AS -march=$MARCH -mabi=ilp32 -I "$TESTS" "$TESTS/irq_stress.s" -o t.o
$LD -m elf32lriscv -T "$TESTS/link.ld" t.o -o t.elf
$OC -O binary t.elf t.bin
python3 "$TESTS/gen_hex.py" t.bin t.hex

echo "== sweep MEI injection cycle $FROM..$TO (hold $HOLD) =="
pass=0; fail=0; firstbad=""
for ((at=FROM; at<=TO; at++)); do
  clr=$((at+HOLD))
  if "$SIM" +hex=t.hex +irq_at=$at +irq_clr=$clr +max=$MAX >"run_$at.log" 2>&1; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); [ -z "$firstbad" ] && firstbad="$at"
    printf "  FAIL irq_at=%-4d %s\n" "$at" "$(grep -oE 'FAIL.*|TIMEOUT.*' run_$at.log | head -1)"
  fi
done
n=$((pass+fail))
echo
echo "irq-stress: $pass/$n injection points PASS, $fail failed"
[ "$fail" -eq 0 ]
