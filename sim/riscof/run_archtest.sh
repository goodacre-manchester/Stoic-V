#!/usr/bin/env bash
# run_archtest.sh — official RISC-V arch-test (RISCOF) for the custom core.
#
# Runs the in-scope conformance signoff: the I, M and Zba/Zbb/Zbs suites, with
# Spike as the golden reference. Applies the §10.3 carve-out by construction —
# the suite is restricted to I/M/B and the DUT ISA omits Zbc (so clmul* and the
# misaligned / illegal-instruction / synchronous-trap suites are never run).
#
# Prereqs (WSL): Spike at ~/riscv-tools/bin, RISCOF venv at ~/riscof-venv,
# arch-test clone (old-framework-3.x) at $ARCHTEST, riscv64-unknown-elf-gcc,
# verilator. See docs/local-resume.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
ARCHTEST="${ARCHTEST:-$HOME/src/riscv-arch-test}"
VENV="${VENV:-$HOME/riscof-venv}"
SPIKE_BIN="${SPIKE_BIN:-$HOME/riscv-tools/bin}"

WORK="$SCRIPT_DIR/work"
SUITE="$WORK/suite"
ENVDIR="$ARCHTEST/riscv-test-suite/env"
SIM="$REPO/sim/obj_dir_arch/Vtb_top"
GENHEX="$REPO/tests/gen_hex.py"
# Vendored Spike reference plugin (one-line PMP fix for riscv-config >=3.x).
REF_PLUGIN="$REPO/sim/riscof/spike"

export PATH="$SPIKE_BIN:$PATH"
# shellcheck disable=SC1091
source "$VENV/bin/activate"

echo "== sanity =="
command -v spike  >/dev/null || { echo "spike not on PATH ($SPIKE_BIN)"; exit 1; }
command -v riscof >/dev/null || { echo "riscof not in venv"; exit 1; }
command -v riscv64-unknown-elf-gcc >/dev/null || { echo "riscv gcc missing"; exit 1; }
[ -d "$ARCHTEST/riscv-test-suite/rv32i_m" ] || { echo "arch-test suite not at $ARCHTEST"; exit 1; }
[ -d "$REF_PLUGIN" ] || { echo "spike_simple ref plugin not found"; exit 1; }

echo "== build conformance sim (4 MiB BRAM, signature dump) =="
make -C "$REPO/sim" arch-sim
[ -x "$SIM" ] || { echo "sim not built: $SIM"; exit 1; }

echo "== assemble in-scope suite (I, M, Zba/Zbb/Zbs) =="
rm -rf "$WORK"
mkdir -p "$SUITE/rv32i_m"
for g in I M B; do cp -r "$ARCHTEST/riscv-test-suite/rv32i_m/$g" "$SUITE/rv32i_m/$g"; done
# Drop Zbc (carry-less multiply) — not implemented by this core (carve-out).
rm -f "$SUITE"/rv32i_m/B/src/clmul*-01.S
echo "   tests: I=$(ls "$SUITE"/rv32i_m/I/src/*.S | wc -l)  M=$(ls "$SUITE"/rv32i_m/M/src/*.S | wc -l)  B=$(ls "$SUITE"/rv32i_m/B/src/*.S | wc -l)"

echo "== generate config.ini =="
CONFIG="$WORK/config.ini"
cat > "$CONFIG" <<EOF
[RISCOF]
ReferencePlugin=spike_simple
ReferencePluginPath=$REF_PLUGIN
DUTPlugin=fabricrv
DUTPluginPath=$SCRIPT_DIR/dut

[spike_simple]
pluginpath=$REF_PLUGIN
ispec=$REF_PLUGIN/spike_simple_isa.yaml
pspec=$REF_PLUGIN/spike_simple_platform.yaml
jobs=$(nproc)

[fabricrv]
pluginpath=$SCRIPT_DIR/dut
ispec=$SCRIPT_DIR/dut/fabricrv_isa.yaml
pspec=$SCRIPT_DIR/dut/fabricrv_platform.yaml
sim=$SIM
genhex=$GENHEX
jobs=$(nproc)
EOF

echo "== riscof run =="
cd "$WORK"
riscof run --config "$CONFIG" --suite "$SUITE" --env "$ENVDIR" --no-browser
echo
echo "Report: $WORK/riscof_work/report.html"
