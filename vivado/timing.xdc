# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# timing.xdc — 250 MHz (4.0 ns) closure target for the core. See docs/timing-and-resources.md.
create_clock -name Clk -period 4.000 [get_ports Clk]

# ---------------------------------------------------------------------------
# I/O timing model — DO NOT false-path the instruction/data buses.
#
# The registered-memory read paths are fmax-determining: a host serves both
# instructions and load data from a registered (cascaded-BRAM-style) memory whose
# clock-to-out + routing feeds combinationally into the core (instruction fetch and
# the load->forward->ALU path). False-pathing the read buses reports a bogus
# "closes"; instead, MODEL the registered read latency at the boundary on the
# instruction AND data read ports so OOC runs see these paths. The integrator's
# place-and-route is authoritative; these numbers are a calibration knob — set them
# to the host memory's actual read Tco.
# ---------------------------------------------------------------------------
set bram_co 1.8   ;# registered read Tco at the read ports (cascaded-BRAM example;
                   ;# a single RAMB36 ~0.6-0.8 — set to the host memory's actual value)
set out_dly 0.5   ;# core outputs -> host address+control setup

# default modest delay on all data inputs, then override the BRAM-read buses
set_input_delay  -clock Clk 0.5      [get_ports -filter {DIRECTION == IN && NAME != Clk} *]
set_input_delay  -clock Clk $bram_co [get_ports {Instr[*]}]
set_input_delay  -clock Clk $bram_co [get_ports IReady]
set_input_delay  -clock Clk $bram_co [get_ports {Data_Read[*]}]
set_input_delay  -clock Clk $bram_co [get_ports DReady]
set_output_delay -clock Clk $out_dly [all_outputs]

set_false_path -from [get_ports Reset]
