#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
#
# run_cosim_fw.sh — SYSTEM-LEVEL lock-step: COMPILED C firmware vs Spike, on the
# canonical FREE-RUNNING registered slave (+dfree). This closes the biggest
# verification gap behind the integrator escapes: all directed tests were hand-written
# asm on benign BFMs, but the bugs lived in REAL compiled-code patterns (function
# epilogues / stack spill-restore / back-to-back memory / pointer chases) on the
# canonical BRAM. Here gcc -O0/-O2/-O3 compiles those patterns (different codegen per
# level, like the P7.1 refactor), runs them on the core against +dfree, and compares
# EVERY committed GPR write against Spike instruction-by-instruction. A divergence is
# a real architectural bug. (Pure compute+memory — no MMIO — so Spike is the golden
# model; MMIO aperture timing is the integrator's, not the core's.)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPIKE_BIN="${SPIKE_BIN:-$HOME/riscv-tools/bin}"
export PATH="$SPIKE_BIN:$PATH"
SIM="$REPO/sim/obj_dir_arch/Vtb_top"      # base 0x8000_0000, matches Spike + link.ld
GENHEX="$REPO/tests/gen_hex.py"
CMP="$REPO/sim/cosim/cosim_compare.py"
WORK="$SCRIPT_DIR/work"
GCC=riscv64-unknown-elf-gcc
ISA=rv32im_zba_zbb_zbs
OPTS="${OPTS:--O0 -O2 -O3}"
SLAVE="${SLAVE:-+dfree=1}"                 # the canonical free-running slave (override e.g. SLAVE=+dedge=1)
CFLAGS="-march=$ISA -mabi=ilp32 -mcmodel=medany -msmall-data-limit=0 -nostdlib -nostartfiles -ffreestanding -fno-builtin -static -Wall"

echo "== sanity =="
command -v spike >/dev/null || { echo "spike not on PATH (SPIKE_BIN=$SPIKE_BIN)"; exit 1; }
command -v "$GCC" >/dev/null || { echo "$GCC missing"; exit 1; }
echo "== build arch sim (trace-enabled, base 0x8000_0000) =="
make -C "$REPO/sim" arch-sim >/dev/null
[ -x "$SIM" ] || { echo "sim not built"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK"
echo "== lock-step: C workloads vs Spike on the free-running slave ($SLAVE) =="
pass=0; fail=0; total=0
for c in "$SCRIPT_DIR"/workloads/*.c; do
  name="$(basename "${c%.c}")"
  for opt in $OPTS; do
    total=$((total+1))
    d="$WORK/${name}${opt}"; mkdir -p "$d"
    if ! $GCC $CFLAGS $opt -T "$SCRIPT_DIR/link.ld" "$SCRIPT_DIR/crt0.S" "$c" -o "$d/t.elf" 2>"$d/cc.log"; then
      printf "  %-12s %-3s COMPILE-FAIL\n" "$name" "$opt"; sed 's/^/      /' "$d/cc.log" | head -4; fail=$((fail+1)); continue
    fi
    riscv64-unknown-elf-objcopy -O binary --change-addresses=-0x80000000 "$d/t.elf" "$d/t.bin"
    python3 "$GENHEX" "$d/t.bin" "$d/t.hex"
    local_th="$(riscv64-unknown-elf-nm "$d/t.elf" | awk '$3=="tohost"{print $1}')"
    "$SIM" +hex="$d/t.hex" +tohost="$local_th" +trace="$d/dut.trc" $SLAVE +max=8000000 >/dev/null 2>&1 || true
    spike -l --log-commits --isa=$ISA "$d/t.elf" 2>"$d/spike.log" >/dev/null || true
    if python3 "$CMP" "$d/dut.trc" "$d/spike.log" >"$d/cmp.txt" 2>&1; then
      printf "  %-12s %-3s MATCH (%s)\n" "$name" "$opt" "$(sed -n 's/.*OK: \([0-9]*\).*/\1 retires/p' "$d/cmp.txt")"
      pass=$((pass+1))
    else
      printf "  %-12s %-3s DIVERGE\n" "$name" "$opt"; sed 's/^/      /' "$d/cmp.txt" | head -8; fail=$((fail+1))
    fi
  done
done

echo
echo "cosim-fw: $pass/$total compiled-C workloads matched Spike on the free-running slave ($SLAVE), $fail diverged"
[ "$fail" -eq 0 ]
