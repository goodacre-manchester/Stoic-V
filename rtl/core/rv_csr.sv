// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_csr.sv — M-mode CSR file + trap/interrupt control. See docs/microarchitecture.md §6.
// Only the architecturally-live fields are implemented; everything else reads 0.
module rv_csr
  import rv_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,

    // CSR instruction access (read combinational; write commits when csr_we)
    input  logic [11:0] csr_addr,
    output logic [31:0] csr_rdata,
    input  logic        csr_we,
    input  csr_op_e     csr_op,
    input  logic [31:0] csr_wsrc,     // rs1 value or zero-extended uimm

    // interrupt pin (level, async to be synced here)
    input  logic        irq_pin,
    output logic        irq_pending,  // MIE & MEIE & MEIP  -> core takes it at a boundary

    // trap / mret commit (driven by the core control)
    input  logic        trap_take,    // commit a machine-external-interrupt trap
    input  logic [31:0] trap_epc,
    input  logic        mret_take,

    output logic [31:0] mtvec_o,
    output logic [31:0] mepc_o,

    input  logic        retire        // a non-bubble instruction retired (minstret)
);
  // architectural state
  logic        mstatus_mie, mstatus_mpie;
  logic        mie_meie;
  logic [31:0] mtvec_r, mepc_r, mcause_r, mscratch_r;
  logic [63:0] mcycle_r, minstret_r;

  // interrupt pin synchroniser + level mirror into mip.MEIP (NOT edge-latched)
  logic meip_s1, meip;
  always_ff @(posedge clk) begin
    if (!rst_n) begin meip_s1 <= 1'b0; meip <= 1'b0; end
    else        begin meip_s1 <= irq_pin; meip <= meip_s1; end
  end

  assign irq_pending = mstatus_mie & mie_meie & meip;
  assign mtvec_o = mtvec_r;
  assign mepc_o  = mepc_r;

  // ---- read mux ----
  always_comb begin
    unique case (csr_addr)
      CSR_MSTATUS : csr_rdata = {19'd0, 2'b11, 3'd0, mstatus_mpie, 3'd0, mstatus_mie, 3'd0};
      CSR_MISA    : csr_rdata = 32'h4000_1100;  // MXL=1, I + M
      CSR_MIE     : csr_rdata = {20'd0, mie_meie, 11'd0};
      CSR_MTVEC   : csr_rdata = mtvec_r;
      CSR_MSCRATCH: csr_rdata = mscratch_r;
      CSR_MEPC    : csr_rdata = mepc_r;
      CSR_MCAUSE  : csr_rdata = mcause_r;
      CSR_MTVAL   : csr_rdata = 32'd0;
      CSR_MIP     : csr_rdata = {20'd0, meip, 11'd0};
      CSR_MHARTID : csr_rdata = C_HART_ID;
      CSR_MCYCLE  : csr_rdata = mcycle_r[31:0];
      CSR_MCYCLEH : csr_rdata = mcycle_r[63:32];
      CSR_MINSTRET: csr_rdata = minstret_r[31:0];
      CSR_MINSTRETH:csr_rdata = minstret_r[63:32];
      default     : csr_rdata = 32'd0;
    endcase
  end

  // ---- write value for CSR instruction ----
  logic [31:0] csr_wval;
  always_comb begin
    unique case (csr_op)
      CSR_RW : csr_wval = csr_wsrc;
      CSR_RS : csr_wval = csr_rdata | csr_wsrc;
      CSR_RC : csr_wval = csr_rdata & ~csr_wsrc;
      default: csr_wval = csr_wsrc;
    endcase
  end

  // ---- update ----
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      mstatus_mie <= 1'b0; mstatus_mpie <= 1'b0; mie_meie <= 1'b0;
      mtvec_r <= 32'd0; mepc_r <= 32'd0; mcause_r <= 32'd0; mscratch_r <= 32'd0;
      mcycle_r <= 64'd0; minstret_r <= 64'd0;
    end else begin
      mcycle_r <= mcycle_r + 64'd1;
      if (retire) minstret_r <= minstret_r + 64'd1;

      if (trap_take) begin
        // machine external interrupt entry
        mepc_r       <= trap_epc;
        mcause_r     <= MCAUSE_MEI;
        mstatus_mpie <= mstatus_mie;
        mstatus_mie  <= 1'b0;
      end else if (mret_take) begin
        mstatus_mie  <= mstatus_mpie;
        mstatus_mpie <= 1'b1;
      end else if (csr_we) begin
        unique case (csr_addr)
          CSR_MSTATUS : begin mstatus_mie <= csr_wval[MSTATUS_MIE];
                              mstatus_mpie <= csr_wval[MSTATUS_MPIE]; end
          CSR_MIE     : mie_meie  <= csr_wval[IRQ_MEI];
          CSR_MTVEC   : mtvec_r   <= {csr_wval[31:2], 2'b00}; // direct mode
          CSR_MSCRATCH: mscratch_r<= csr_wval;
          CSR_MEPC    : mepc_r    <= {csr_wval[31:1], 1'b0};
          CSR_MCAUSE  : mcause_r  <= csr_wval;
          CSR_MCYCLE  : mcycle_r[31:0]   <= csr_wval;
          CSR_MCYCLEH : mcycle_r[63:32]  <= csr_wval;
          CSR_MINSTRET: minstret_r[31:0] <= csr_wval;
          CSR_MINSTRETH:minstret_r[63:32]<= csr_wval;
          default     : ; // read-only / unimplemented -> ignore
        endcase
      end
    end
  end
endmodule : rv_csr
