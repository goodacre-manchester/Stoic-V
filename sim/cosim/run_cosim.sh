#!/usr/bin/env bash
# run_cosim.sh — Spike lock-step retire-compare for the custom core.
#
# For each in-scope test, runs the SAME ELF on our Verilator model (emitting a
# per-retire GPR-write trace) and on Spike (`-l --log-commits`), then diffs the
# architectural write streams instruction-by-instruction (cosim_compare.py).
# This is stronger than the end-of-test signature/tohost checks: it catches any
# divergence at the cycle it first commits a wrong value.
#
# Uses the riscv-tests rv32ui+rv32um programs (aligned, in-scope) compiled with
# the custom M-mode env. Carve-out (README §10.3): misaligned ops are excluded
# (Spike would diverge on them, and they hang our aligned-only core), so
# ma_data is skipped along with fence_i (Zifencei). Both DUT and Spike run from
# the same 0x8000_0000 entry; Spike's boot ROM commits (pc < entry) are dropped.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
RVT="${RVT:-$HOME/src/riscv-tests}"
SPIKE_BIN="${SPIKE_BIN:-$HOME/riscv-tools/bin}"
ENV="$REPO/sim/riscv-tests/env"
MACROS="$RVT/isa/macros/scalar"
SIM="$REPO/sim/obj_dir_arch/Vtb_top"
GENHEX="$REPO/tests/gen_hex.py"
CMP="$SCRIPT_DIR/cosim_compare.py"
WORK="$SCRIPT_DIR/work"
export PATH="$SPIKE_BIN:$PATH"
GCC=riscv64-unknown-elf-gcc

EXCLUDE="ma_data fence_i"
ISA=rv32im_zba_zbb_zbs

echo "== sanity =="
command -v spike >/dev/null || { echo "spike not on PATH"; exit 1; }
command -v "$GCC" >/dev/null || { echo "$GCC missing"; exit 1; }
[ -d "$RVT/isa/rv32ui" ] || { echo "riscv-tests not at $RVT"; exit 1; }
echo "== build conformance sim (trace-enabled) =="
make -C "$REPO/sim" arch-sim >/dev/null
[ -x "$SIM" ] || { echo "sim not built"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK"
echo "== carve-out: skipping $EXCLUDE =="
pass=0; fail=0; skip=0; total=0
run_suite() {
  local suite="$1"
  for f in "$RVT/isa/$suite"/*.S; do
    local name; name="$(basename "${f%.S}")"
    for x in $EXCLUDE; do [ "$name" = "$x" ] && { printf "  %-18s SKIP (carve-out)\n" "$suite/$name"; skip=$((skip+1)); continue 2; }; done
    total=$((total+1))
    local d="$WORK/$suite/$name"; mkdir -p "$d"
    if ! "$GCC" -march=$ISA -mabi=ilp32 -static -mcmodel=medany -nostdlib \
        -nostartfiles -g -T "$ENV/link.ld" -I "$ENV" -I "$MACROS" \
        -o "$d/t.elf" "$f" 2>"$d/cc.log"; then
      printf "  %-18s COMPILE-FAIL\n" "$suite/$name"; fail=$((fail+1)); continue
    fi
    riscv64-unknown-elf-objcopy -O binary --change-addresses=-0x80000000 "$d/t.elf" "$d/t.bin"
    python3 "$GENHEX" "$d/t.bin" "$d/t.hex"
    local TH; TH="$(riscv64-unknown-elf-nm "$d/t.elf" | awk '$3=="tohost"{print $1}')"
    "$SIM" +hex="$d/t.hex" +tohost="$TH" +trace="$d/dut.trc" +max=2000000 >/dev/null 2>&1 || true
    spike -l --log-commits --isa=$ISA "$d/t.elf" 2>"$d/spike.log" >/dev/null || true
    if python3 "$CMP" "$d/dut.trc" "$d/spike.log" >"$d/cmp.txt" 2>&1; then
      printf "  %-18s MATCH (%s)\n" "$suite/$name" "$(sed -n 's/.*OK: \([0-9]*\).*/\1 retires/p' "$d/cmp.txt")"
      pass=$((pass+1))
    else
      printf "  %-18s DIVERGE\n" "$suite/$name"; sed 's/^/      /' "$d/cmp.txt" | head -8; fail=$((fail+1))
    fi
  done
}

echo "== rv32ui =="; run_suite rv32ui
echo "== rv32um =="; run_suite rv32um
echo
echo "cosim: $pass/$total matched Spike, $fail diverged, $skip skipped (carve-out)"
[ "$fail" -eq 0 ]
