#!/usr/bin/env bash
# run_embench.sh — Embench-IoT on the custom RV32 core, cycle-exact (no caches +
# registered-1-cycle memory => Verilator cycles == silicon cycles). Each kernel is
# timed with mcycle/minstret around benchmark() via start_/stop_trigger (crt0.S),
# the four counters dumped through the RISCOF +sig path. Score = geomean of the
# Embench relative speed (baseline/measured); rel_per_mhz = baseline*1000/cycles is
# frequency-independent (the Embench analogue of CoreMark/MHz). Footprint per kernel
# is checked against the 24 KiB I / 16 KiB D end-target budget.
set -uo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SRC/../.." && pwd)"
EMB="${EMB:-$HOME/src/embench-iot}"
OPT="${OPT:--O2}"
# Default = the core's default config (2-cycle load-use, P_LOADUSE=2 — the default
# FPGA build). For the relaxed-clock 1-cycle option: DEFS=+define+CORE_PERF TAG=emb_perf.
DEFS="${DEFS:-}"
TAG="${TAG:-emb}"
IAW="${IAW:-19}"; DAW="${DAW:-19}"    # sim memory = 512 KiB flat (fit is checked vs 24/16 separately)
WORK="$SRC/work"; mkdir -p "$WORK"
RES="$WORK/results.txt"; : > "$RES"
# 24/16 KiB end-target budget (bytes) for the fit check
IBUDGET=$((24*1024)); DBUDGET=$((16*1024))

CM_PREFIX="${CM_PREFIX:-riscv64-unknown-elf}"; CM_BIN="${CM_BIN:-}"
[ -n "$CM_BIN" ] && export PATH="$CM_BIN:$PATH"
GCC=${CM_PREFIX}-gcc; OC=${CM_PREFIX}-objcopy; NM=${CM_PREFIX}-nm; SZ=${CM_PREFIX}-size
GENHEX="$REPO/tests/gen_hex.py"
SIM="$REPO/sim/obj_dir_$TAG/Vtb_top"
MARCH=rv32im_zba_zbb_zbs_zicsr

command -v "$GCC" >/dev/null || { echo "$GCC missing"; exit 1; }
[ -d "$EMB" ] || { echo "embench not at $EMB (set EMB=)"; exit 1; }
echo "== toolchain: $($GCC --version | head -1) =="
echo "== config: OPT=$OPT DEFS='$DEFS' (sim mem ${IAW}/${DAW} aw) =="

# 1) build the CORE_PERF sim if needed
if [ ! -x "$SIM" ]; then
  echo "== verilate Embench sim (DEFS='$DEFS', 512 KiB I/D) =="
  RTL="$REPO/rtl/core"; TB="$REPO/tb"
  verilator --cc --exe --build -j 0 -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    --top-module tb_top -I"$RTL" -GIAW=$IAW -GDAW=$DAW $DEFS \
    "$RTL/rv_pkg.sv" "$RTL/rv_alu.sv" "$RTL/rv_bitmanip.sv" "$RTL/rv_regfile.sv" "$RTL/rv_decode.sv" \
    "$RTL/rv_muldiv.sv" "$RTL/rv_csr.sv" "$RTL/rv_core.sv" "$RTL/mbv.sv" \
    "$TB/models/lmb_bram.sv" "$TB/tb_top.sv" "$TB/cpp/sim_main.cpp" \
    -o Vtb_top --Mdir "$REPO/sim/obj_dir_$TAG" || { echo "VERILATE FAIL"; exit 1; }
fi

# benchmark list (override with BENCH="crc32 edn ...")
BENCHES="${BENCH:-aha-mont64 crc32 edn huffbench matmult-int md5sum nettle-aes nettle-sha256 \
  nsichneu picojpeg qrduino sglib-combined slre statemate tarfind ud wikisort}"
# (depthconv/xgboost omitted from the default set: heavier/float — add via BENCH= if wanted)

# -std=gnu11: gcc-15 defaults to C23 where `bool` is a keyword (wikisort typedefs it).
CFLAGS="-march=$MARCH -mabi=ilp32 -mcmodel=medany $OPT -std=gnu11 -ffreestanding -nostdlib -w \
  -DHAVE_BOARDSUPPORT_H -I$SRC -I$EMB/support"
# newlib's <ctype.h> macros index _ctype_[]; provide the standard table (slre uses isX()).
python3 - > "$WORK/emb_ctype.c" <<'PY'
f=[0]*257  # [0]=EOF slot; [1+ch]=class(ch)
for ch in range(256):
    v=0
    if ch<128:
        c=chr(ch)
        if c.isupper(): v|=1
        if c.islower(): v|=2
        if c.isdigit(): v|=4
        if ch in (0x20,0x09,0x0a,0x0b,0x0c,0x0d): v|=8        # _S (space/blanks)
        if 0x21<=ch<=0x7e and not c.isalnum(): v|=16          # _P (punct)
        if ch<0x20 or ch==0x7f: v|=32                         # _C (control)
        if c in '0123456789abcdefABCDEF': v|=64               # _X (hex)
        if ch==0x20: v|=128                                   # _B (printable blank)
    f[1+ch]=v
print('const char _ctype_[257] = {'+','.join(str(x) for x in f)+'};')
print('const char *__ctype_ptr__ = _ctype_ + 1;')
PY
COMMON="$EMB/support/main.c $EMB/support/beebsc.c $SRC/boardsupport.c $REPO/sim/coremark/libc.c $SRC/emb_libc.c $WORK/emb_ctype.c"

for b in $BENCHES; do
  bdir="$EMB/src/$b"
  [ -d "$bdir" ] || { echo "  !! $b: no src dir"; continue; }
  rm -f "$WORK"/*.o
  ok=1; OBJS=""
  for f in "$bdir"/*.c $COMMON; do
    o="$WORK/$(basename "${f%.c}").$(echo "$f" | md5sum | cut -c1-6).o"
    $GCC $CFLAGS -I"$bdir" -c "$f" -o "$o" 2>"$WORK/cc.err" || { echo "  !! $b: CC FAIL $(basename "$f")"; head -3 "$WORK/cc.err"; ok=0; break; }
    OBJS="$OBJS $o"
  done
  [ $ok -eq 1 ] || continue
  $GCC $CFLAGS -c "$SRC/crt0.S" -o "$WORK/crt0.o" 2>/dev/null
  if ! $GCC -march=$MARCH -mabi=ilp32 -nostdlib -nostartfiles -T "$SRC/link.ld" \
        $OBJS "$WORK/crt0.o" -lm -lgcc -o "$WORK/$b.elf" 2>"$WORK/ld.err"; then
    echo "  !! $b: LINK FAIL"; head -4 "$WORK/ld.err"; continue
  fi
  # footprint
  read TEXT DATA BSS <<<"$($SZ "$WORK/$b.elf" | awk 'NR==2{print $1, $2, $3}')"
  $OC -O binary "$WORK/$b.elf" "$WORK/$b.bin"
  python3 "$GENHEX" "$WORK/$b.bin" "$WORK/$b.hex"
  TH=$($NM "$WORK/$b.elf" | awk '$3=="tohost"{print $1}')
  BS=$($NM "$WORK/$b.elf" | awk '$3=="begin_signature"{print $1}')
  BE=$(printf '%08x' $((0x$BS + 20)))
  # run (cycle-exact)
  t0=$(date +%s)
  "$SIM" +hex="$WORK/$b.hex" +tohost="$TH" +sigbegin="$BS" +sigend="$BE" \
         +sig="$WORK/$b.sig" +max=3000000000 >"$WORK/$b.simlog" 2>&1
  t1=$(date +%s)
  # parse signature words: startcyc stopcyc startinst stopinst code
  mapfile -t W < <(awk 'NF{print strtonum("0x"$1)}' "$WORK/$b.sig")
  if [ "${#W[@]}" -lt 5 ]; then echo "  !! $b: no/short signature (${#W[@]} words)"; continue; fi
  CYC=$(( ${W[1]} - ${W[0]} )); INST=$(( ${W[3]} - ${W[2]} )); CODE=${W[4]}
  [ "$CYC" -le 0 ] && { echo "  !! $b: bad cycle delta ($CYC)"; continue; }
  PASS="PASS"; [ "$CODE" = "1" ] || PASS="FAIL(code=$CODE)"
  printf '%-15s cyc=%-10d inst=%-10d ipc=%.3f text=%-6d data=%-5d bss=%-7d %s (%ds)\n' \
    "$b" "$CYC" "$INST" "$(awk "BEGIN{print $INST/$CYC}")" "$TEXT" "$DATA" "$BSS" "$PASS" "$((t1-t0))"
  echo "$b $CYC $INST $TEXT $DATA $BSS $CODE" >> "$RES"
done

# 2) score.  Embench convention: build each kernel at GLOBAL_SCALE_FACTOR = cpu_mhz
# so the relative score rel = baseline_ms/measured_ms cancels frequency and reduces
# to baseline*1000/(work*CPI) -- a pure IPC-vs-reference metric (ref Arm Cortex-M4
# = 1.0, frequency-independent). We build at gsf=1 (cheap to simulate) and compute
# score = baseline*1000/cycles, which is algebraically identical (verified: crc32
# built at gsf=266 gives rel=0.677 == baseline*1000/cycles here). Geomean over the
# suite is the headline Embench speed score.
echo; echo "================ Embench report (OPT=$OPT, DEFS='$DEFS') ================"
python3 - "$RES" "$EMB/baseline-data/speed.json" "$IBUDGET" "$DBUDGET" <<'PY'
import sys, json, math
res, basef, ib, db = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
base = json.load(open(basef))
rows = [l.split() for l in open(res) if l.strip()]
if not rows:
    print("no results"); sys.exit(0)
print(f"{'kernel':15} {'cycles':>10} {'IPC':>5} {'.text':>6} {'data+bss':>9} {'score':>7} {'fit24/16':>9}")
prod=0.0; n=0
for b,cyc,inst,text,data,bss in [(r[0],int(r[1]),int(r[2]),int(r[3]),int(r[4]),int(r[5])) for r in rows]:
    ipc=inst/cyc
    score = base.get(b,0)*1000.0/cyc if b in base else 0.0   # == standard Embench rel (freq-indep)
    dtot=data+bss
    fit = "ok" if (text<=ib and dtot<=db) else (("I!" if text>ib else "")+("D!" if dtot>db else ""))
    if score>0: prod+=math.log(score); n+=1
    print(f"{b:15} {cyc:>10} {ipc:>5.2f} {text:>6} {dtot:>9} {score:>7.3f} {fit:>9}")
if n:
    g=math.exp(prod/n)
    print(f"\nEmbench speed score (geomean, ref Arm Cortex-M4 = 1.00, frequency-independent) "
          f"= {g:.3f}  over {n} kernels")
print(f"Fit budget: .text <= {ib} B (24 KiB), data+bss <= {db} B (16 KiB).  I!/D! = over budget.")
PY
echo "========================================================================"
