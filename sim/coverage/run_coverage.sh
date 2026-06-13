#!/usr/bin/env bash
# run_coverage.sh — RTL line+toggle coverage of the core over the test corpus.
#
# Two coverage-instrumented sims are exercised and their coverage.dat merged:
#   * unit build (0x0)      <- the directed suite (I/M/Zb + traps + irq + csr),
#                              which hits control paths the arithmetic suites miss
#   * arch build (0x8...)   <- riscv-tests rv32ui+rv32um (broad arithmetic / ld/st)
# Reports overall line coverage and writes annotated sources + an lcov .info.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
TESTS="$REPO/tests"; RVT="${RVT:-$HOME/src/riscv-tests}"
ENV="$REPO/sim/riscv-tests/env"; MACROS="$RVT/isa/macros/scalar"
SIMU="$REPO/sim/obj_dir_cov/Vtb_top"
SIMA="$REPO/sim/obj_dir_cov_arch/Vtb_top"
GENHEX="$TESTS/gen_hex.py"; WORK="$SCRIPT_DIR/work"
export PATH="${SPIKE_BIN:-$HOME/riscv-tools/bin}:$PATH"
AS=riscv64-unknown-elf-as; LD=riscv64-unknown-elf-ld; OC=riscv64-unknown-elf-objcopy
MARCH=rv32im_zba_zbb_zbs_zicsr

echo "== build coverage sims =="
make -C "$REPO/sim" cov-sim-unit cov-sim-arch >/dev/null
[ -x "$SIMU" ] && [ -x "$SIMA" ] || { echo "cov sims not built"; exit 1; }
rm -rf "$WORK"; mkdir -p "$WORK/dat"; cd "$WORK"

echo "== directed suite on unit cov sim =="
for s in "$TESTS"/*.s; do
  n="$(basename "${s%.s}")"
  $AS -march=$MARCH -mabi=ilp32 -I "$TESTS" "$s" -o "$n.o" 2>/dev/null || { echo "  asm $n FAIL"; continue; }
  $LD -m elf32lriscv -T "$TESTS/link.ld" "$n.o" -o "$n.elf" && $OC -O binary "$n.elf" "$n.bin"
  python3 "$GENHEX" "$n.bin" "$n.hex"
  simargs="$(grep -oE '#\s*SIM:\s*.*' "$s" | sed -E 's/#\s*SIM:\s*//')"
  "$SIMU" +hex="$n.hex" $simargs +covfile="dat/u_$n.dat" >/dev/null 2>&1 || true
  printf "  ran %s\n" "$n"
done

echo "== riscv-tests on arch cov sim =="
for suite in rv32ui rv32um; do
  for f in "$RVT/isa/$suite"/*.S; do
    n="$(basename "${f%.S}")"
    case "$n" in ma_data|fence_i) continue;; esac
    riscv64-unknown-elf-gcc -march=rv32im_zba_zbb_zbs -mabi=ilp32 -static \
      -mcmodel=medany -nostdlib -nostartfiles -g -T "$ENV/link.ld" -I "$ENV" -I "$MACROS" \
      -o "$suite-$n.elf" "$f" 2>/dev/null || continue
    $OC -O binary --change-addresses=-0x80000000 "$suite-$n.elf" "$suite-$n.bin"
    python3 "$GENHEX" "$suite-$n.bin" "$suite-$n.hex"
    TH="$(riscv64-unknown-elf-nm "$suite-$n.elf" | awk '$3=="tohost"{print $1}')"
    "$SIMA" +hex="$suite-$n.hex" +tohost="$TH" +max=2000000 +covfile="dat/a_$suite-$n.dat" >/dev/null 2>&1 || true
  done
done
echo "== arch-test I/M/B on arch cov sim (covers all Zb* encodings) =="
ARCHTEST="${ARCHTEST:-$HOME/src/riscv-arch-test}"
ADENV="$REPO/sim/riscof/dut/env"; AINC="$ARCHTEST/riscv-test-suite/env"
for g in I M B; do
  for f in "$ARCHTEST/riscv-test-suite/rv32i_m/$g/src"/*.S; do
    [ -e "$f" ] || continue
    n="$(basename "${f%.S}")"
    case "$n" in clmul*) continue;; esac
    riscv64-unknown-elf-gcc -march=rv32im_zba_zbb_zbs_zicsr -mabi=ilp32 -static \
      -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g \
      -T "$ADENV/link.ld" -I "$ADENV" -I "$AINC" -DXLEN=32 -DTEST_CASE_1=True \
      -o "at-$g-$n.elf" "$f" 2>/dev/null || continue
    $OC -O binary --change-addresses=-0x80000000 "at-$g-$n.elf" "at-$g-$n.bin"
    python3 "$GENHEX" "at-$g-$n.bin" "at-$g-$n.hex"
    TH="$(riscv64-unknown-elf-nm "at-$g-$n.elf" | awk '$3=="tohost"{print $1}')"
    "$SIMA" +hex="at-$g-$n.hex" +tohost="$TH" +max=2000000 +covfile="dat/at_$g-$n.dat" >/dev/null 2>&1 || true
  done
done
echo "  ran $(ls dat/*.dat | wc -l) coverage runs total"

echo "== merge + report =="
verilator_coverage --write-info cov.info dat/*.dat >/dev/null 2>&1
# annotate from sim/ so the recorded ../rtl/... source paths resolve
( cd "$REPO/sim" && verilator_coverage --annotate "$WORK/annotated" "$WORK"/dat/*.dat ) >/dev/null 2>&1 || true
# line coverage from the lcov .info, broken down core vs TB
python3 - <<'PY'
import re
files={}; cur=None
for ln in open("cov.info"):
    ln=ln.strip()
    if ln.startswith("SF:"): cur=ln[3:]; files.setdefault(cur,[0,0])
    m=re.match(r'DA:\d+,(\d+)', ln)
    if m and cur:
        files[cur][1]+=1
        if int(m.group(1))>0: files[cur][0]+=1
def agg(pred):
    c=t=0
    for f,(cv,tt) in files.items():
        if pred(f): c+=cv; t+=tt
    return c,t
cc,ct = agg(lambda f: "rtl/core" in f.replace("\\","/"))
ac,at = agg(lambda f: True)
print(f"  CORE RTL (rtl/core) line coverage: {cc}/{ct} = {100.0*cc/ct:.1f}%" if ct else "  no core data")
print(f"  all files (incl. TB)            : {ac}/{at} = {100.0*ac/at:.1f}%")
print("  per core file:")
for f in sorted(files):
    if "rtl/core" in f.replace("\\","/"):
        cv,tt=files[f]; print(f"    {100.0*cv/tt:5.1f}%  {cv:3d}/{tt:<3d}  {f.split('/')[-1]}")
print("  annotated sources: sim/coverage/work/annotated/  ('%000000' marks uncovered lines)")
PY
