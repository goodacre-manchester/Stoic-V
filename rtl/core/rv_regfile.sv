// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_regfile.sv — 32x32 GPRs, 2 read / 1 write, x0 hardwired 0.
// Synchronous write; combinational read (write-first handled by forwarding network in core).
module rv_regfile (
    input  logic        clk,
    input  logic        we,
    input  logic [4:0]  waddr,
    input  logic [31:0] wdata,
    input  logic [4:0]  raddr1,
    input  logic [4:0]  raddr2,
    output logic [31:0] rdata1,
    output logic [31:0] rdata2
);
  logic [31:0] regs [1:31];

  // Power-up value. On a Xilinx FPGA the regfile is distributed RAM (LUTRAM),
  // which configures to a DEFINED 0 at programming time, so model that here. The
  // `initial` is synthesised as the LUTRAM INIT — it adds NO reset port, so the
  // LUTRAM inference (and timing/area) is unchanged. Without it, 4-state sim
  // (Vivado xsim) reads X for any never-written GPR, and that X propagates into a
  // load base (-> wrong/0 address) or a ret/jalr target (-> PC 0) the moment
  // firmware touches an untouched register — the 2026-06 P7.1 xsim wedge.
  // In 2-state sim it reads 0 and hides the gap. Defining the power-up state
  // makes sim faithful to silicon; it is NOT an architectural reset (the ISA does
  // not define GPR reset values, and firmware must still initialise before use).
  initial begin
    for (int i = 1; i <= 31; i++) regs[i] = 32'd0;
  end

  always_ff @(posedge clk) begin
    if (we && (waddr != 5'd0)) regs[waddr] <= wdata;
  end

  // write-first (internal forwarding): a read in the same cycle as a write to the
  // same register returns the new value. Covers the WB->ID same-cycle RAW hazard.
  wire wr_fwd1 = we && (waddr != 5'd0) && (waddr == raddr1);
  wire wr_fwd2 = we && (waddr != 5'd0) && (waddr == raddr2);
  assign rdata1 = (raddr1 == 5'd0) ? 32'd0 : wr_fwd1 ? wdata : regs[raddr1];
  assign rdata2 = (raddr2 == 5'd0) ? 32'd0 : wr_fwd2 ? wdata : regs[raddr2];
endmodule : rv_regfile
