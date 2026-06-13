#!/usr/bin/env bash
# run_coremark.sh — CoreMark on the custom RV32 core, cycle-exact (no caches +
# registered-1-cycle memory => Verilator cycles == silicon cycles). CoreMark/MHz =
# iterations*1e6/cycles (frequency-independent). Output is captured via ee_printf ->
# a buffer dumped through the RISCOF +sig path, then decoded back to text.
set -uo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SRC/../.." && pwd)"
CM="${CM:-$HOME/src/coremark}"
ITER="${ITER:-10}"
OPT="${OPT:--O2}"            # gcc optimization level (report it with the score)
DEFS="${DEFS:-}"             # extra Verilator defines, e.g. DEFS=+define+CORE_PERF
TAG="${TAG:-cm}"             # obj_dir tag (use a distinct one per RTL config)
WORK="$SRC/work"; mkdir -p "$WORK"
# Toolchain override (does NOT affect the verification gates, which call the apt
# riscv64-unknown-elf-gcc directly). Default = apt 13.2. For a newer compiler:
#   CM_PREFIX=riscv-none-elf CM_BIN=$HOME/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin
CM_PREFIX="${CM_PREFIX:-riscv64-unknown-elf}"
CM_BIN="${CM_BIN:-}"
[ -n "$CM_BIN" ] && export PATH="$CM_BIN:$PATH"
GCC=${CM_PREFIX}-gcc; OC=${CM_PREFIX}-objcopy; NM=${CM_PREFIX}-nm
GENHEX="$REPO/tests/gen_hex.py"
SIM="$REPO/sim/obj_dir_$TAG/Vtb_top"

command -v "$GCC" >/dev/null || { echo "$GCC missing"; exit 1; }
echo "== toolchain: $($GCC --version | head -1) =="
[ -d "$CM" ] || { echo "coremark not at $CM"; exit 1; }

# 1) build the roomy (256 KiB) CoreMark sim if needed
if [ ! -x "$SIM" ]; then
  echo "== verilate CoreMark sim (256 KiB I/D BRAM) =="
  RTL="$REPO/rtl/core"; TB="$REPO/tb"
  verilator --cc --exe --build -j 0 -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
    --top-module tb_top -I"$RTL" -GIAW=18 -GDAW=18 $DEFS \
    "$RTL/rv_pkg.sv" "$RTL/rv_alu.sv" "$RTL/rv_bitmanip.sv" "$RTL/rv_regfile.sv" "$RTL/rv_decode.sv" \
    "$RTL/rv_muldiv.sv" "$RTL/rv_csr.sv" "$RTL/rv_core.sv" "$RTL/mbv.sv" \
    "$TB/models/lmb_bram.sv" "$TB/tb_top.sv" "$TB/cpp/sim_main.cpp" \
    -o Vtb_top --Mdir "$REPO/sim/obj_dir_$TAG" || { echo "VERILATE FAIL"; exit 1; }
fi

# 2) build CoreMark (PERFORMANCE_RUN seeds 0,0,0x66 -> standard CRC 0xe9f5)
echo "== build CoreMark (gcc -O2, rv32im_zba_zbb_zbs, ITERATIONS=$ITER) =="
MARCH=rv32im_zba_zbb_zbs_zicsr   # zicsr: core_portme reads mcycle
CFLAGS="-march=$MARCH -mabi=ilp32 -mcmodel=medany $OPT -ffreestanding -nostdlib \
  -include stddef.h -I$CM -I$CM/barebones -I$SRC \
  -DPERFORMANCE_RUN=1 -DITERATIONS=$ITER -DHAS_FLOAT=0 -DHAS_TIME_H=0 -DUSE_CLOCK=0 \
  -DHAS_STDIO=0 -DHAS_PRINTF=0 -DMAIN_HAS_NOARGC=1"
OBJS=""
for f in "$CM/core_main.c" "$CM/core_list_join.c" "$CM/core_matrix.c" "$CM/core_state.c" \
         "$CM/core_util.c" "$SRC/core_portme.c" "$SRC/ee_printf_min.c" "$SRC/libc.c"; do
  o="$WORK/$(basename "$f").o"
  $GCC $CFLAGS "-DFLAGS_STR=\"$OPT rv32im_zba_zbb_zbs\"" -c "$f" -o "$o" || { echo "CC FAIL $f"; exit 1; }
  OBJS="$OBJS $o"
done
$GCC -march=$MARCH -mabi=ilp32 -c "$SRC/start.S" -o "$WORK/start.o" || { echo "AS FAIL"; exit 1; }
$GCC -march=$MARCH -mabi=ilp32 -nostdlib -nostartfiles -T "$SRC/link.ld" \
  $OBJS "$WORK/start.o" -lgcc -o "$WORK/coremark.elf" || { echo "LINK FAIL"; exit 1; }

$OC -O binary "$WORK/coremark.elf" "$WORK/coremark.bin"
python3 "$GENHEX" "$WORK/coremark.bin" "$WORK/coremark.hex"
echo "  image = $(stat -c%s "$WORK/coremark.bin") bytes"

# 3) symbols for the TB
TH=$($NM "$WORK/coremark.elf" | awk '$3=="tohost"{print $1}')
OB=$($NM "$WORK/coremark.elf" | awk '$3=="ee_outbuf"{print $1}')
OE=$(printf '%08x' $((0x$OB + 4096)))
echo "  tohost=$TH  ee_outbuf=$OB..$OE"

# 4) run (cycle-exact)
echo "== run on the core =="
"$SIM" +hex="$WORK/coremark.hex" +tohost="$TH" +sigbegin="$OB" +sigend="$OE" \
       +sig="$WORK/out.sig" +max=120000000 | tee "$WORK/sim.log"

# 5) decode the ee_printf buffer (RISCOF hex words, little-endian) -> text
echo; echo "================ CoreMark report ================"
python3 - "$WORK/out.sig" <<'PY'
import sys
b=bytearray()
for line in open(sys.argv[1]):
    w=line.strip()
    if not w: continue
    v=int(w,16)
    b += bytes([v&0xff,(v>>8)&0xff,(v>>16)&0xff,(v>>24)&0xff])
txt=b.split(b'\x00',1)[0].decode('latin1')
print(txt)
# CoreMark/MHz cross-check from integer fields
import re
it=re.search(r'Iterations\s*:\s*(\d+)',txt); tk=re.search(r'Total ticks\s*:\s*(\d+)',txt)
if it and tk and int(tk.group(1))>0:
    print("CoreMark/MHz (iter*1e6/cycles) = %.3f" % (int(it.group(1))*1e6/int(tk.group(1))))
PY
echo "================================================="