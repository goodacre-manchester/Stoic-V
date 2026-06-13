#!/usr/bin/env bash
# run_dut.sh <elf> <sig_out> <sim_bin> <gen_hex.py>
# Compile artifacts already exist (the plugin ran gcc); here we turn the ELF
# into a flat hex image, pull the tohost/signature addresses out of the symbol
# table, run the Verilator model, and leave the signature in <sig_out>.
set -e
ELF="$1"; SIG="$2"; SIM="$3"; GENHEX="$4"
OBJCOPY="${OBJCOPY:-riscv64-unknown-elf-objcopy}"
NM="${NM:-riscv64-unknown-elf-nm}"
DIR="$(dirname "$ELF")"

# Shift the 0x8000_0000-based image down to offset 0 for $readmemh; the sim's
# BRAM window is based at MEM_BASE=0x8000_0000, so word i loads at addr 0x8000_0000+4i.
"$OBJCOPY" -O binary --change-addresses=-0x80000000 "$ELF" "$DIR/my.bin"
python3 "$GENHEX" "$DIR/my.bin" "$DIR/my.hex"

# Symbol addresses stay 0x8000_0000-based (the core runs there); pass as-is.
sym() { "$NM" "$ELF" | awk -v s="$1" '$3==s {print $1}'; }
TH="$(sym tohost)"
BS="$(sym begin_signature)"
ES="$(sym end_signature)"
if [ -z "$TH" ] || [ -z "$BS" ] || [ -z "$ES" ]; then
  echo "run_dut.sh: missing tohost/begin_signature/end_signature symbol" >&2
  exit 1
fi

# +tohost / +sigbegin / +sigend are parsed as %h (bare hex, no 0x).
"$SIM" +hex="$DIR/my.hex" +tohost="$TH" +sigbegin="$BS" +sigend="$ES" \
       +sig="$SIG" +max=20000000 > "$DIR/dut.log" 2>&1 || true

# A signature must have been produced (an empty/missing file => hang/divergence).
test -s "$SIG"
