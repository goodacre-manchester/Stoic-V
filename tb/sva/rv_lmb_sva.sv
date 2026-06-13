// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_lmb_sva.sv — concurrent SVA assertions on the LMB data-bus master + the
// single-outstanding handshake. Bound onto rv_core (so it sees the internal
// strobe/handshake signals) and checked in SIMULATION (`verilator --assert`) across
// the whole directed suite + the scoreboard — assertion-based verification of the
// bus protocol the rc4/rc7 escapes lived in. The same properties are the basis for
// the formal (bounded-model-check) flow; see docs/verification.md §4.3.
module rv_lmb_sva (
    input logic clk,
    input logic rst_n,
    input logic o_das,        // data address strobe (1-cycle pulse per access)
    input logic o_rstrobe,    // read strobe
    input logic o_wstrobe,    // write strobe
    input logic i_dready,     // slave ack
    input logic d_inflight    // the core's one outstanding access
);
  // P1 — single-outstanding: a strobe is issued only when no access is in flight.
  a_idle_strobe: assert property (@(posedge clk) disable iff (!rst_n)
    o_das |-> !d_inflight);

  // P2 — read and write strobes are mutually exclusive.
  a_rw_excl:     assert property (@(posedge clk) disable iff (!rst_n)
    !(o_rstrobe && o_wstrobe));

  // P3 — any read/write strobe implies the address strobe (one strobe per access).
  a_strobe_das:  assert property (@(posedge clk) disable iff (!rst_n)
    (o_rstrobe || o_wstrobe) |-> o_das);

  // P4 — single strobe per access: an UNACKED strobe is not immediately followed by
  // another strobe (the core waits for DReady before re-issuing). This is the
  // property the rc4 held-strobe bug violated.
  a_one_per_ack: assert property (@(posedge clk) disable iff (!rst_n)
    (o_das && !i_dready) |=> !o_das);

  // P5 — an access in flight stays in flight until the slave acks (DReady): the core
  // does not silently drop an outstanding access.
  a_inflight_until_ack: assert property (@(posedge clk) disable iff (!rst_n)
    (d_inflight && !i_dready) |=> d_inflight);
endmodule

bind rv_core rv_lmb_sva u_lmb_sva (
  .clk(clk), .rst_n(rst_n),
  .o_das(o_das), .o_rstrobe(o_rstrobe), .o_wstrobe(o_wstrobe),
  .i_dready(i_dready), .d_inflight(d_inflight)
);
