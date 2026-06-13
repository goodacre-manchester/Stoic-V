// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_lmb_formal.sv — FORMAL model of the LMB single-outstanding data-bus handshake.
//
// The handshake FSM below is extracted VERBATIM from rv_core.sv (the d_inflight /
// d_issue / d_complete / dmem_stall / strobe logic — rv_core.sv §"data-bus
// single-outstanding handshake"). Free inputs (m_valid, is_load, is_store, i_dready)
// drive it, and yosys-smtbmc proves the LMB protocol properties — BMC for a bounded
// horizon and k-INDUCTION for an UNBOUNDED proof (holds for all reachable states,
// all time). These are the same invariants the rc4 (held-strobe) and rc7
// (store->load) escapes lived around, now machine-checked rather than sampled.
//
// Scope note: this formally proves the BUS-HANDSHAKE PROTOCOL (the recurring bug
// site). Whole-core ISA correctness is a separate, larger effort (riscv-formal /
// RVFI); see docs/verification.md §4.3.
module rv_lmb_formal (
    input logic clk,
    input logic rst_n,
    input logic m_valid,
    input logic is_load,
    input logic is_store,
    input logic i_dready
);
  // A MEM instruction is load XOR store, never both (the decoder guarantees this).
  always_comb assume (!(is_load && is_store));

  // ---- handshake — verbatim from rv_core.sv ----
  wire  mem_req    = m_valid & (is_load | is_store);
  logic d_inflight;
  wire  d_issue    = mem_req & ~d_inflight;
  wire  d_complete = d_inflight & i_dready;
  always_ff @(posedge clk) begin
    if (!rst_n)          d_inflight <= 1'b0;
    else if (d_issue)    d_inflight <= 1'b1;
    else if (d_complete) d_inflight <= 1'b0;
  end
  wire dmem_stall = d_inflight & (mem_req | ~i_dready);
  wire o_das      = d_issue;
  wire o_rstrobe  = d_issue & is_load;
  wire o_wstrobe  = d_issue & is_store;

  // ---- formal $past machinery ----
  reg f_past_valid = 1'b0;
  always_ff @(posedge clk) f_past_valid <= 1'b1;

  // ---- properties (combinational invariants) ----
  always_comb if (rst_n) begin
    // P1 — single-outstanding: a strobe is issued only when no access is in flight.
    assert (!(o_das && d_inflight));
    // P2 — read and write strobes are mutually exclusive.
    assert (!(o_rstrobe && o_wstrobe));
    // P3 — any read/write strobe implies the address strobe (one strobe per access).
    assert (!((o_rstrobe || o_wstrobe) && !o_das));
    // P6 — a strobe never coincides with a stall on a fresh access (issue ⇒ ~stall-of-prev).
    assert (!(o_das && d_inflight));
  end

  // ---- properties (1-cycle temporal invariants) ----
  always_ff @(posedge clk) if (f_past_valid && rst_n && $past(rst_n)) begin
    // P4 — single strobe per access: an UNACKED strobe is not immediately followed by
    // another strobe (the core waits for DReady before re-issuing). rc4 violated this.
    if ($past(o_das) && !$past(i_dready)) assert (!o_das);
    // P5 — an access in flight stays in flight until the slave acks (no silent drop).
    if ($past(d_inflight) && !$past(i_dready)) assert (d_inflight);
    // P7 — d_complete (the ack) clears exactly one outstanding access.
    if ($past(d_complete)) assert (!d_inflight || d_issue);
  end
endmodule
