#!/usr/bin/env bash
# run_lmb_contract.sh — LMB data-bus contract regression (docs/microarchitecture.md §9).
#
# The core is a single-outstanding LMB master that drives ONE rising-edge address
# strobe per access and honours DReady (rtl/core/rv_core.sv data-bus handshake). It
# therefore slots in against ANY fixed-latency REGISTERED slave:
#
#   * registered 1-cycle, LEVEL ready                       -> PASS  (the unit BFM)
#   * registered 1-cycle, EDGE-detect + held ready          -> PASS  (a representative
#       host tile slave: rd_start = re & ~re_q, read mux registered on the
#       rising edge, ready held while the strobe is asserted). A core that HELD its
#       strobe across back-to-back accesses would re-read the FIRST access's word —
#       the 2026-06 in-context stale-ISR-read bug. The per-access rising edge fixes it.
#   * registered MULTI-cycle, back-pressure (DReady low until data) -> PASS  (robust;
#       was unsupported when the core used blind fixed-1-cycle timing).
#   * registered 1-cycle, FREE-RUNNING read (+dfree) -> PASS  (the CANONICAL Xilinx
#       BRAM Port A: data_rd_q <= mem[addr] every cycle, the read tracks the address,
#       NOT the strobe — exactly tile.sv's data path). This is the slave that exposed
#       the 2026-06 P7.1 STORE->LOAD stale read: a load held in WB across the
#       single-outstanding gap must commit its OWN latched word, not the live bus
#       (which has advanced to the next access). Covered by store->load (storeload.s)
#       AND the back-to-back set; both PASS post-fix, FAIL pre-fix.
#   * COMBINATIONAL / zero-wait (read data the SAME cycle as the strobe) -> FAIL
#       (NEGATIVE: the registered contract is violated — the slave delivers data a
#       cycle early and never presents a DReady the core can hand-shake against).
#
# Determinism is preserved across all PASS cases: timing is a function only of the
# access pattern and the (data-independent) slave latency, never of data values.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
RVT="${RVT:-$HOME/src/riscv-tests}"
ENV="$REPO/sim/riscv-tests/env"
MACROS="$RVT/isa/macros/scalar"
SIM="$REPO/sim/obj_dir/Vtb_top"             # unit sim, base 0x0 (directed env)
SIM_ARCH="$REPO/sim/obj_dir_arch/Vtb_top"   # base 0x8000_0000 (riscv-tests env)
SIM_COMBD="$REPO/sim/obj_dir_combd/Vtb_top" # base 0x8000_0000, combinational data bus
GENHEX="$REPO/tests/gen_hex.py"
WORK="$SCRIPT_DIR/work"
export PATH="${SPIKE_BIN:-$HOME/riscv-tools/bin}:$PATH"
GCC=riscv64-unknown-elf-gcc
MAX=200000

echo "== build sims (unit + arch + combinational-data) =="
make -C "$REPO/sim" verilate arch-sim arch-sim-combd >/dev/null
for s in "$SIM" "$SIM_ARCH" "$SIM_COMBD"; do [ -x "$s" ] || { echo "missing $s"; exit 1; }; done

# the back-to-back + store->load regression hexes (directed env: base 0, tohost 0x7000)
python3 "$REPO/tests/run_tests.py" --build-only tests/backtoback.s tests/storeload.s >/dev/null 2>&1 || true
B2B="$REPO/sim/build/backtoback.hex"
STORELOAD="$REPO/sim/build/storeload.hex"
[ -f "$B2B" ] || { echo "backtoback.hex missing"; exit 1; }
[ -f "$STORELOAD" ] || { echo "storeload.hex missing"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"

build() {  # build a self-checking rv32ui test ELF/hex; echo its tohost addr
  $GCC -march=rv32im_zba_zbb_zbs -mabi=ilp32 -static -mcmodel=medany -nostdlib \
    -nostartfiles -g -T "$ENV/link.ld" -I "$ENV" -I "$MACROS" \
    -o "$1.elf" "$RVT/isa/rv32ui/$1.S" 2>/dev/null
  riscv64-unknown-elf-objcopy -O binary --change-addresses=-0x80000000 "$1.elf" "$1.bin"
  python3 "$GENHEX" "$1.bin" "$1.hex"
  riscv64-unknown-elf-nm "$1.elf" | awk '$3=="tohost"{print $1}'
}
declare -A TH
for t in add lw; do TH[$t]="$(build "$t")"; done

rc=0
check() {  # <sim> <hex> <tohost> <expect> <label> <plusargs...>
  local sim="$1" hex="$2" th="$3" expect="$4" lbl="$5"; shift 5
  local r=0
  "$sim" +hex="$hex" +tohost="$th" +max=$MAX "$@" >"$lbl.log" 2>&1 || r=$?
  local got="pass"; [ "$r" -ne 0 ] && got="fail"
  if [ "$got" = "$expect" ]; then
    printf "  OK   %-40s expect=%-4s got=%-4s\n" "$lbl" "$expect" "$got"
  else
    printf "  BAD  %-40s expect=%-4s got=%-4s  <-- contract not as documented\n" "$lbl" "$expect" "$got"
    rc=1
  fi
}

echo "== back-to-back loads/stores must PASS on every registered slave variant =="
check "$SIM" "$B2B" 7000 pass "b2b registered 1-cycle (level)"
check "$SIM" "$B2B" 7000 pass "b2b EDGE-detect tile slave"          +dedge=1
check "$SIM" "$B2B" 7000 pass "b2b back-pressure (dwait=1)"         +dwait=1
check "$SIM" "$B2B" 7000 pass "b2b back-pressure (dwait=3)"         +dwait=3
check "$SIM" "$B2B" 7000 pass "b2b EDGE-detect + back-pressure"     +dedge=1 +dwait=2

echo "== FREE-RUNNING registered read (canonical BRAM Port A / tile.sv) must PASS =="
echo "   (the P7.1 store->load slave: read tracks the address, not the strobe)"
check "$SIM" "$B2B"       7000 pass "b2b FREE-RUNNING (dfree)"              +dfree=1
check "$SIM" "$STORELOAD" 7000 pass "store->load FREE-RUNNING (dfree)"     +dfree=1
check "$SIM" "$STORELOAD" 7000 pass "store->load EDGE-detect (hold slave)" +dedge=1
check "$SIM" "$STORELOAD" 7000 pass "store->load back-pressure (dwait=2)"  +dwait=2

echo "== riscv-tests baseline + back-pressure must PASS =="
check "$SIM_ARCH" "$WORK/add.hex" "${TH[add]}" pass "add baseline (level)"
check "$SIM_ARCH" "$WORK/lw.hex"  "${TH[lw]}"  pass "lw  baseline (level)"
check "$SIM_ARCH" "$WORK/lw.hex"  "${TH[lw]}"  pass "lw  data back-pressure (dwait=1)" +dwait=1

echo "== NEGATIVE: combinational / zero-wait DATA response must FAIL =="
check "$SIM_COMBD" "$WORK/lw.hex" "${TH[lw]}" fail "lw data-combinational (COMB_D)"

echo
if [ "$rc" -eq 0 ]; then
  echo "LMB CONTRACT VERIFIED: single-outstanding, one rising-edge strobe per access,"
  echo "DReady-handshaked. Works with level / edge-detect / back-pressure registered"
  echo "slaves (incl. a host edge-detect tile); a combinational response is rejected."
else
  echo "LMB CONTRACT MISMATCH: see BAD lines above."
fi
exit $rc
