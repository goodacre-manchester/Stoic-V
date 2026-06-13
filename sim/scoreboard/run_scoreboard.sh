#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
#
# run_scoreboard.sh — randomized-slave-timing scoreboard.
#
# The systematic catch-all for the bus-capture/ordering class (rc4 back-to-back,
# rc7 store→load). Instead of a few HAND-PICKED slave modes, it drives the data bus
# with a RANDOMIZED COMPLIANT registered slave (+drand=<seed>: per access, random
# wait latency × random free-running-vs-held read data — all contract-legal) and
# asserts the core's ARCHITECTURAL result (the committed GPR-write stream) is
# INVARIANT to the timing, i.e. identical to Spike, across a SEED SWEEP. Spike is the
# timing-agnostic golden, so it is computed ONCE per workload; the core is re-run
# under each seed. A divergence on ANY seed is a real bug — a load/store that commits
# the wrong value for some compliant slave timing.
#
# Reuses the sim/cosim-fw C workloads (rich memory traffic: epilogue spill/restore,
# struct copy, pointer chase, in-place sort). WSL: gcc + Spike.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
FW="$REPO/sim/cosim-fw"
SPIKE_BIN="${SPIKE_BIN:-$HOME/riscv-tools/bin}"; export PATH="$SPIKE_BIN:$PATH"
SIM="$REPO/sim/obj_dir_arch/Vtb_top"
GENHEX="$REPO/tests/gen_hex.py"
CMP="$REPO/sim/cosim/cosim_compare.py"
WORK="$SCRIPT_DIR/work"
GCC=riscv64-unknown-elf-gcc
ISA=rv32im_zba_zbb_zbs
OPTS="${OPTS:--O0 -O2}"
SEEDS="${SEEDS:-1 2 3 5 8 13 21 34 55 89 144 233 377 610 987 1597}"
CFLAGS="-march=$ISA -mabi=ilp32 -mcmodel=medany -msmall-data-limit=0 -nostdlib -nostartfiles -ffreestanding -fno-builtin -static"

echo "== sanity =="
command -v spike >/dev/null || { echo "spike not on PATH (SPIKE_BIN=$SPIKE_BIN)"; exit 1; }
command -v "$GCC" >/dev/null || { echo "$GCC missing"; exit 1; }
make -C "$REPO/sim" arch-sim >/dev/null
[ -x "$SIM" ] || { echo "sim not built"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK"
nseeds=$(echo $SEEDS | wc -w)
echo "== scoreboard: architectural invariance under $nseeds random compliant slave timings =="
echo "   seeds: $SEEDS"
pass=0; fail=0; total=0
for c in "$FW"/workloads/*.c; do
  name="$(basename "${c%.c}")"
  for opt in $OPTS; do
    d="$WORK/${name}${opt}"; mkdir -p "$d"
    if ! $GCC $CFLAGS $opt -T "$FW/link.ld" "$FW/crt0.S" "$c" -o "$d/t.elf" 2>"$d/cc.log"; then
      printf "  %-12s %-3s COMPILE-FAIL\n" "$name" "$opt"; fail=$((fail+1)); continue
    fi
    riscv64-unknown-elf-objcopy -O binary --change-addresses=-0x80000000 "$d/t.elf" "$d/t.bin"
    python3 "$GENHEX" "$d/t.bin" "$d/t.hex"
    TH="$(riscv64-unknown-elf-nm "$d/t.elf" | awk '$3=="tohost"{print $1}')"
    spike -l --log-commits --isa=$ISA "$d/t.elf" 2>"$d/spike.log" >/dev/null || true   # golden, once
    seedfail=0
    for s in $SEEDS; do
      total=$((total+1))
      "$SIM" +hex="$d/t.hex" +tohost="$TH" +trace="$d/dut_$s.trc" +drand=$s +max=8000000 >/dev/null 2>&1 || true
      if python3 "$CMP" "$d/dut_$s.trc" "$d/spike.log" >"$d/cmp_$s.txt" 2>&1; then
        pass=$((pass+1))
      else
        fail=$((fail+1)); seedfail=$((seedfail+1))
        if [ "$seedfail" -le 1 ]; then
          printf "  %-12s %-3s seed=%-5s DIVERGE\n" "$name" "$opt" "$s"; sed 's/^/      /' "$d/cmp_$s.txt" | head -6
        fi
      fi
    done
    [ "$seedfail" -eq 0 ] && printf "  %-12s %-3s all %s seeds MATCH\n" "$name" "$opt" "$nseeds"
  done
done

echo
echo "scoreboard: $pass/$total (workload × opt × seed) invariant to random compliant slave timing (== Spike), $fail diverged"
[ "$fail" -eq 0 ]
