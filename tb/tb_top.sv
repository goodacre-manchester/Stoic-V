// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// tb_top.sv — unit testbench top: mbv core + registered I/D BRAM models + IRQ + tohost.
// Flat low-address memory (both BRAMs load the same image); the real 0x1000_0000 map is
// a tile concern (M6). Completion: a store to TOHOST signals pass(1)/fail(odd>1).
//
// TOHOST address defaults to 0x0000_7000 (the directed tests' convention) but can be
// overridden with +tohost=<hex> so the RISCOF flow can point it at the test's `tohost`
// symbol. When the data memory is built with DUMP=1 and given +sig/+sigbegin/+sigend,
// it writes the architectural signature on completion (see sim/riscof/).
module tb_top #(
    parameter int          IAW       = 16,
    parameter int          DAW       = 16,
    parameter logic [31:0] RESET_VEC = 32'h0000_0000,  // core reset PC (arch-test: 0x8000_0000)
    parameter logic [31:0] MEM_BASE  = 32'h0000_0000,  // BRAM window base (arch-test: 0x8000_0000)
    parameter bit          COMB_I    = 1'b0,           // I-bus combinational (NEGATIVE test)
    parameter bit          COMB_D    = 1'b0            // D-bus combinational (NEGATIVE test)
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        irq,
    output logic [31:0] tohost,
    output logic        tohost_we
);
  logic [31:0] TOHOST;
  initial if (!$value$plusargs("tohost=%h", TOHOST)) TOHOST = 32'h0000_7000;

  // ---- core <-> buses ----
  logic [31:0] Instr_Addr, Instr, Data_Addr, Data_Read, Data_Write;
  logic        IFetch, I_AS, IReady, D_AS, Read_Strobe, Write_Strobe, DReady;
  logic [3:0]  Byte_Enable;
  wire         Reset = ~rst_n;

  mbv #(.RESET_VEC(RESET_VEC)) u_cpu (
    .Clk(clk), .Reset(Reset),
    .Interrupt(irq), .Interrupt_Address(32'h0), .Interrupt_Ack(),
    .Instr_Addr(Instr_Addr), .Instr(Instr), .IFetch(IFetch), .I_AS(I_AS),
    .IReady(IReady), .IWAIT(1'b0), .ICE(1'b0), .IUE(1'b0),
    .Data_Addr(Data_Addr), .Data_Read(Data_Read), .Data_Write(Data_Write),
    .D_AS(D_AS), .Read_Strobe(Read_Strobe), .Write_Strobe(Write_Strobe),
    .DReady(DReady), .DWait(1'b0), .DCE(1'b0), .DUE(1'b0), .Byte_Enable(Byte_Enable),
    .Dbg_Clk(1'b0), .Dbg_TDI(1'b0), .Dbg_TDO(), .Dbg_Reg_En(8'h0), .Dbg_Shift(1'b0),
    .Dbg_Capture(1'b0), .Dbg_Update(1'b0), .Dbg_Trig_In(), .Dbg_Trig_Ack_In(8'h0),
    .Dbg_Trig_Out(8'h0), .Dbg_Trig_Ack_Out(), .Debug_Rst(Reset), .Dbg_Disable(1'b1)
  );

  // instruction memory (read-only)
  wire if_re = I_AS & IFetch;
  lmb_bram #(.AW(IAW), .LOAD(1'b1), .DUMP(1'b0), .MEM_BASE(MEM_BASE), .COMB(COMB_I)) u_imem (
    .clk(clk), .addr(Instr_Addr), .re(if_re), .we(1'b0), .be(4'h0), .wdata(32'h0),
    .rdata(Instr), .ready(IReady), .halt(1'b0)
  );

  // data memory (read/write)
  wire d_re = D_AS & Read_Strobe;
  wire d_we = D_AS & Write_Strobe;
  wire halt = d_we & (Data_Addr == TOHOST);   // end-of-test: trigger signature dump
  lmb_bram #(.AW(DAW), .LOAD(1'b1), .DUMP(1'b1), .MEM_BASE(MEM_BASE), .COMB(COMB_D)) u_dmem (
    .clk(clk), .addr(Data_Addr), .re(d_re), .we(d_we), .be(Byte_Enable), .wdata(Data_Write),
    .rdata(Data_Read), .ready(DReady), .halt(halt)
  );

  // tohost capture
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tohost <= 32'd0; tohost_we <= 1'b0;
    end else begin
      tohost_we <= halt;
      if (halt) tohost <= Data_Write;
    end
  end

  // ---- cosim retire trace (gated by +trace=<file>) ----
  // One line per committed GPR write: "<pc> <rd> <val>" (hex pc/val, decimal rd),
  // matching the x-register commits in Spike's `-l --log-commits` output. Reads the
  // core's WB-stage commit signals by hierarchical reference (sim-only).
  string  trc_file;
  integer trc_fd;
  logic   have_trc;
  initial begin
    have_trc = $value$plusargs("trace=%s", trc_file);
    if (have_trc) trc_fd = $fopen(trc_file, "w");
  end
  always_ff @(posedge clk) begin
    if (rst_n & have_trc & u_cpu.u_core.rf_we)
      $fdisplay(trc_fd, "%08x %0d %08x",
                u_cpu.u_core.w_pc, u_cpu.u_core.rf_wa, u_cpu.u_core.rf_wd);
  end
  final if (have_trc) $fclose(trc_fd);
endmodule : tb_top
