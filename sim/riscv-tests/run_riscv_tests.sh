#!/usr/bin/env bash
# run_riscv_tests.sh — official Berkeley riscv-tests (rv32ui + rv32um) on the
# custom core. Self-checking via tohost (no Spike needed). Uses a custom M-mode,
# no-trap env (env/riscv_test.h) that signals pass/fail with a direct tohost
# store. Links at 0x8000_0000; reuses the arch sim (make arch-sim).
#
# Carve-out (README §10.3): ma_data (misaligned) and fence_i (Zifencei — not
# claimed; no I-cache to make coherent) are out of scope and skipped.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
RVT="${RVT:-$HOME/src/riscv-tests}"
ENV="$SCRIPT_DIR/env"
MACROS="$RVT/isa/macros/scalar"
SIM="$REPO/sim/obj_dir_arch/Vtb_top"
GENHEX="$REPO/tests/gen_hex.py"
WORK="$SCRIPT_DIR/work"
GCC=riscv64-unknown-elf-gcc
OC=riscv64-unknown-elf-objcopy
NM=riscv64-unknown-elf-nm

# Out-of-scope per the carve-out (no silent drops — logged below).
EXCLUDE="ma_data fence_i"

echo "== sanity =="
command -v "$GCC" >/dev/null || { echo "$GCC missing"; exit 1; }
[ -d "$RVT/isa/rv32ui" ] || { echo "riscv-tests not at $RVT"; exit 1; }
echo "== build conformance sim =="
make -C "$REPO/sim" arch-sim >/dev/null
[ -x "$SIM" ] || { echo "sim not built: $SIM"; exit 1; }

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
    if ! "$GCC" -march=rv32im_zba_zbb_zbs -mabi=ilp32 -static -mcmodel=medany \
        -nostdlib -nostartfiles -g -T "$ENV/link.ld" -I "$ENV" -I "$MACROS" \
        -o "$d/t.elf" "$f" 2>"$d/cc.log"; then
      printf "  %-18s COMPILE-FAIL\n" "$suite/$name"; fail=$((fail+1)); continue
    fi
    "$OC" -O binary --change-addresses=-0x80000000 "$d/t.elf" "$d/t.bin"
    python3 "$GENHEX" "$d/t.bin" "$d/t.hex"
    local TH; TH="$("$NM" "$d/t.elf" | awk '$3=="tohost"{print $1}')"
    if "$SIM" +hex="$d/t.hex" +tohost="$TH" +max=2000000 >"$d/sim.log" 2>&1; then
      printf "  %-18s PASS  (%s)\n" "$suite/$name" "$(grep -oE 'CYCLES=[0-9]+' "$d/sim.log" | head -1)"
      pass=$((pass+1))
    else
      printf "  %-18s FAIL  (%s)\n" "$suite/$name" "$(tail -1 "$d/sim.log")"
      fail=$((fail+1))
    fi
  done
}

echo "== rv32ui =="; run_suite rv32ui
echo "== rv32um =="; run_suite rv32um
echo
echo "riscv-tests: $pass/$total passed, $fail failed, $skip skipped (carve-out)"
[ "$fail" -eq 0 ]
