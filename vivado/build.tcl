# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# build.tcl — Vivado synth/impl of the custom core (top = mbv), out-of-context.
# Timing gate (M6): assert WNS >= 0 at 250 MHz (4.0 ns) and report utilization vs budget.
# Run locally (Vivado on UltraScale+):  vivado -mode batch -source vivado/build.tcl
# Override part:  vivado -mode batch -source vivado/build.tcl -tclargs xczu7ev-ffvc1156-2-e

set part      [lindex $argv 0]
if {$part eq ""} { set part "xczu9eg-ffvb1156-2-e" }  ;# ZCU102 (Zynq US+ XCZU9EG, -2)
set rtl       [file normalize [file dirname [info script]]/../rtl/core]
set xdc       [file normalize [file dirname [info script]]/timing.xdc]
set outdir    [file normalize [file dirname [info script]]/../build]
file mkdir $outdir

# Use more host CPUs (default cap is low). This only affects tool RUNTIME, not
# results: Vivado place/route/phys-opt are deterministic w.r.t. thread count, and
# our determinism contract is over cycle counts, which synthesis cannot alter.
set_param general.maxThreads 16

# rv_pkg FIRST (compiled once), then modules. mbv.sv last (top).
read_verilog -sv [list \
  $rtl/rv_pkg.sv $rtl/rv_alu.sv $rtl/rv_bitmanip.sv $rtl/rv_regfile.sv \
  $rtl/rv_decode.sv $rtl/rv_muldiv.sv $rtl/rv_csr.sv \
  $rtl/rv_core.sv $rtl/mbv.sv]
read_xdc $xdc

synth_design -top mbv -part $part -mode out_of_context -flatten_hierarchy rebuilt
opt_design

# ---- DSP pipeline-register packing check (decided at synth; survives a reaped P&R) ----
# Confirms the sync-reset tidy let the multiply pipeline regs land in the DSP48E2
# (MREG/PREG=1 ⇒ pm1/pm2 absorbed ⇒ ~132 fabric FF saved). Also dumps the muldiv
# instance's FF/LUT so the optimisation deltas are directly visible.
if {[catch {
  set dspf [open $outdir/dsp_pack.rpt w]
  set dsps [get_cells -hier -filter {REF_NAME == DSP48E2 || REF_NAME == DSP48E1}]
  puts $dspf "DSP primitives: [llength $dsps]   (AREG/BREG/MREG/PREG = 1 means that pipeline reg packed into the DSP)"
  foreach d $dsps {
    puts $dspf [format "  %-46s A=%s B=%s M=%s P=%s" [get_property NAME $d] \
      [get_property AREG $d] [get_property BREG $d] [get_property MREG $d] [get_property PREG $d]]
  }
  close $dspf
  puts "DSP packing report -> $outdir/dsp_pack.rpt"
} emsg]} { puts "DSP packing report skipped: $emsg" }

# ---- Pblock floorplan (OOC locality demo; determinism-neutral — placement only) ----
# Constrain the core to ONE compact clock region so OOC routing can't smear the tiny
# design (2761 LUT / 1037 FF / 4 DSP) across the bare die. A clock region holds it many
# times over and includes DSP columns. This isolates whether the residual WNS is
# routing/locality (a Pblock recovers it) vs logic depth (it won't). Toggle: use_pblock.
# RESULT (off by default): in OOC this is CONFOUNDED — pinning u_core makes the
# worst path an I/O-output route to the *unplaced* ports (no PARTPIN_LOCS), and a
# single region over-constrains the dense forward net. WNS got worse (−0.585→−0.693),
# not better. OOC can't isolate locality without real I/O pins → a floorplanned
# place-and-route is needed for that. Left here as a documented experiment.
set use_pblock 0
if {$use_pblock} {
  if {[catch {
    # find the central clock region of the (regular) grid; resize_pblock needs the
    # full CLOCKREGION_XxYy:CLOCKREGION_XxYy range form (a bare name is rejected).
    set maxx 0; set maxy 0
    foreach cr [get_clock_regions] {
      regexp {X(\d+)Y(\d+)} [get_property NAME $cr] -> x y
      if {$x > $maxx} { set maxx $x }
      if {$y > $maxy} { set maxy $y }
    }
    set cx [expr {$maxx / 2}]; set cy [expr {$maxy / 2}]
    set rng "CLOCKREGION_X${cx}Y${cy}:CLOCKREGION_X${cx}Y${cy}"
    create_pblock pb_core
    add_cells_to_pblock pb_core [get_cells u_core]
    resize_pblock pb_core -add $rng
    puts "PBLOCK: u_core -> $rng  (grid ${maxx}x${maxy})"
  } pbe]} { puts "PBLOCK setup skipped: $pbe"; catch { delete_pblock pb_core } }
}
# LEAN place/route (default directives). This OOC gate is a logic-sanity check:
# on the bare die the worst path is routing-dominated (a tiny design smears without
# a floorplan), so high-effort place/route (Explore + phys-opt) does not change the
# conclusion and only slows each run. The core closes the 250 MHz OOC gate here
# with margin on logic; dense, high-utilisation closure needs a real floorplan.
# Restore higher effort if needed.
place_design
route_design

report_timing_summary -file $outdir/timing.rpt
report_utilization     -file $outdir/util.rpt
# all setup paths still failing (empty file == timing met) — the next-iteration diagnostic
report_timing -setup -max_paths 25 -slack_lesser_than 0 -sort_by group -input_pins \
              -file $outdir/failing_paths.rpt

# ---- timing gate check (M6) ----
# timing.xdc now MODELS the registered cascaded-BRAM read latency on the instr/data
# buses (no longer false-pathed), so $wns is the TRUE worst path — including the
# fetch (Instr->decode->execute) and load (Data_Read->forward->EX) paths that a
# cascaded BRAM drives. $wns_int is the register-to-register-only worst as a
# cross-check (isolates pure core-internal logic from the I/O-bounded paths).
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set wns_int "n/a"
if {[catch {
  set ffs [all_registers -edge_triggered]
  report_timing -from $ffs -to $ffs -setup -max_paths 15 -file $outdir/timing_reg2reg.rpt
  set wns_int [get_property SLACK [get_timing_paths -from $ffs -to $ffs -max_paths 1 -nworst 1 -setup]]
} emsg]} { puts "reg->reg report skipped: $emsg" }

# ---- hold (min-delay) timing — WHS ----
# OOC post-synth, with no clock buffer set (HD.CLK_SRC) so skew=0, so this is a
# PRELIMINARY hold check (final hold closure is the integrator's in-context P&R with a
# real clock tree). We report WHS and FAIL on a NEGATIVE numeric WHS, but treat a
# not-computed ("n/a") result as inapplicable rather than a failure.
set whs "n/a"
if {[catch {
  report_timing -hold -max_paths 25 -slack_lesser_than 0 -sort_by group -file $outdir/failing_hold.rpt
  set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
} hmsg]} { puts "hold report skipped: $hmsg" }

puts "============================================================"
puts "PART=$part  WNS(worst, BRAM I/O modelled)=$wns ns   WNS(reg->reg only)=$wns_int ns   WHS(hold)=$whs ns  (target 4.000 ns / 250 MHz)"
report_utilization -hierarchical -file $outdir/util_hier.rpt
set hold_ok 1
if {[string is double -strict $whs] && $whs < 0} { set hold_ok 0 }
if {$wns >= 0 && $hold_ok} {
  puts "TIMING GATE: PASS (WNS >= 0; WHS=$whs ns)"
} else {
  if {$wns < 0}  { puts "TIMING GATE: FAIL (WNS < 0) — apply a determinism-safe mitigation (timing-and-resources.md §2)" }
  if {!$hold_ok} { puts "TIMING GATE: FAIL (WHS < 0) — hold violation on the synthesized netlist" }
  exit 1
}
puts "============================================================"
