#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
#
# run_formal.sh — formal proof of the LMB single-outstanding handshake protocol.
# Compiles the extracted handshake FSM (sim/formal/rv_lmb_formal.sv) with yosys,
# emits SMT2, and runs yosys-smtbmc with z3: BMC for a bounded horizon AND k-INDUCTION
# for an UNBOUNDED proof (the properties hold for ALL reachable states, all time).
# Proves the bus-handshake invariants (single-outstanding, one-strobe-per-access,
# no-silent-drop) the rc4/rc7 escapes lived around. Needs: yosys, yosys-smtbmc, z3.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
WORK="$SCRIPT_DIR/work"; mkdir -p "$WORK"

command -v yosys >/dev/null       || { echo "yosys not installed (apt-get install yosys)"; exit 1; }
command -v yosys-smtbmc >/dev/null || { echo "yosys-smtbmc not found"; exit 1; }
command -v z3 >/dev/null          || { echo "z3 not installed (apt-get install z3)"; exit 1; }

echo "== yosys: elaborate handshake FSM -> SMT2 =="
yosys -q -p "read_verilog -sv -formal rv_lmb_formal.sv; prep -top rv_lmb_formal; write_smt2 -wires $WORK/lmb.smt2" \
  || { echo "YOSYS ELABORATION FAILED"; exit 1; }

rc=0
echo
echo "== BMC: no protocol violation reachable within 25 steps =="
if yosys-smtbmc -s z3 -t 25 --dump-vcd "$WORK/bmc.vcd" "$WORK/lmb.smt2" 2>&1 | tee "$WORK/bmc.log" | grep -qiE 'Status: PASSED'; then
  echo "  BMC: PASSED (P1..P7 hold for 25 steps from reset)"
else
  echo "  BMC: FAILED — counterexample in work/bmc.vcd"; rc=1; tail -6 "$WORK/bmc.log" | sed 's/^/    /'
fi

echo
echo "== k-induction: UNBOUNDED proof (holds for all reachable states, all time) =="
if yosys-smtbmc -s z3 -i -t 25 "$WORK/lmb.smt2" 2>&1 | tee "$WORK/ind.log" | grep -qiE 'Status: PASSED'; then
  echo "  INDUCTION: PASSED — the LMB handshake protocol properties are PROVEN (unbounded)"
else
  echo "  INDUCTION: not proven at depth 25 — see work/ind.log"; rc=1; tail -6 "$WORK/ind.log" | sed 's/^/    /'
fi

echo
if [ "$rc" -eq 0 ]; then
  echo "formal: LMB handshake protocol PROVEN (BMC + k-induction, z3) — P1..P7:"
  echo "  single-outstanding · read/write-strobe exclusivity · strobe⇒address-strobe ·"
  echo "  one-strobe-per-access · in-flight-until-ack · ack-clears-one."
else
  echo "formal: a property did not pass — see bmc.log / ind.log"
fi
exit $rc
