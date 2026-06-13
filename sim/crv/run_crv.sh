#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
#
# run_crv.sh — Constrained-Random Verification. Generates N pseudo-random,
# hazard-biased RV32IM_zba_zbb_zbs_zicsr programs (sim/crv/gen_rand.py), runs each on
# the core against the free-running slave (+dfree), and LOCK-STEPS the committed
# GPR-write stream against Spike. A divergence is a real forwarding/hazard/bus bug the
# hand-written tests never thought to cover. Each program is one seed -> a failure is
# trivially reproduced (`gen_rand.py <seed>`). Spike is the oracle; pure compute+memory
# (no MMIO/traps), so it is the golden architectural model.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
SPIKE_BIN="${SPIKE_BIN:-$HOME/riscv-tools/bin}"; export PATH="$SPIKE_BIN:$PATH"
SIM="$REPO/sim/obj_dir_arch/Vtb_top"
GENHEX="$REPO/tests/gen_hex.py"
CMP="$REPO/sim/cosim/cosim_compare.py"
LINK="$REPO/sim/cosim-fw/link.ld"
WORK="$SCRIPT_DIR/work"
GCC=riscv64-unknown-elf-gcc
ISA=rv32im_zba_zbb_zbs           # Spike --isa (zicsr implied)
ISA_AS=rv32im_zba_zbb_zbs_zicsr  # assembler -march
NPROG="${NPROG:-200}"
NINSTR="${NINSTR:-400}"
SLAVE="${SLAVE:-+dfree=1}"
SEED0="${SEED0:-1}"
CFLAGS="-march=$ISA_AS -mabi=ilp32 -mcmodel=medany -msmall-data-limit=0 -nostdlib -nostartfiles -static"

echo "== sanity =="
command -v spike >/dev/null || { echo "spike not on PATH"; exit 1; }
command -v "$GCC" >/dev/null || { echo "$GCC missing"; exit 1; }
make -C "$REPO/sim" arch-sim >/dev/null
[ -x "$SIM" ] || { echo "sim not built"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK"
echo "== CRV: $NPROG random programs ($NINSTR instr, hazard-biased) vs Spike on $SLAVE =="
pass=0; fail=0; firstfail=""
for i in $(seq 0 $((NPROG-1))); do
  s=$((SEED0 + i)); d="$WORK/p$s"
  python3 "$SCRIPT_DIR/gen_rand.py" "$s" "$NINSTR" > "$d.s"
  if ! $GCC $CFLAGS -T "$LINK" "$d.s" -o "$d.elf" 2>"$d.cc"; then
    echo "  seed=$s ASM-FAIL"; sed 's/^/      /' "$d.cc" | head -3; fail=$((fail+1)); [ -z "$firstfail" ] && firstfail=$s; continue
  fi
  riscv64-unknown-elf-objcopy -O binary --change-addresses=-0x80000000 "$d.elf" "$d.bin"
  python3 "$GENHEX" "$d.bin" "$d.hex"
  TH="$(riscv64-unknown-elf-nm "$d.elf" | awk '$3=="tohost"{print $1}')"
  "$SIM" +hex="$d.hex" +tohost="$TH" +trace="$d.trc" $SLAVE +max=4000000 >/dev/null 2>&1 || true
  spike -l --log-commits --isa=$ISA "$d.elf" 2>"$d.spike" >/dev/null || true
  if python3 "$CMP" "$d.trc" "$d.spike" >"$d.cmp" 2>&1; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); [ -z "$firstfail" ] && firstfail=$s
    echo "  seed=$s DIVERGE"; sed 's/^/      /' "$d.cmp" | head -6
  fi
  if [ $((i % 50)) -eq 49 ]; then echo "  ... $((i+1))/$NPROG done ($pass matched)"; fi
done

echo
echo "crv: $pass/$NPROG random hazard-biased programs matched Spike on $SLAVE, $fail diverged"
[ -n "$firstfail" ] && echo "  reproduce the first failure: python3 sim/crv/gen_rand.py $firstfail $NINSTR"
[ "$fail" -eq 0 ]
