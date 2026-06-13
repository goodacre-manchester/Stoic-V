// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// mbv.sv — synthesizable TOP presenting the EXACT MicroBlaze-V `mbv` slot-in signature
// (docs/microarchitecture.md §9) so a host SoC binds it wherever a MicroBlaze-V would.
// Wraps rv_core. Reset is active-high. Debug ports exist but are functionally omitted (v1).
module mbv #(
    // Reset PC. Default 0x0 (= rv_pkg::C_BASE_VECTORS); a host wrapper binds
    // `mbv` without overriding it (read-only), so the slot-in is unchanged.
    // The arch-test sim overrides it to 0x8000_0000 to match Spike's base.
    parameter logic [31:0] RESET_VEC = 32'h0000_0000
) (
    input  logic        Clk,
    input  logic        Reset,             // active-high (wrapper drives ~rst_n)

    input  logic        Interrupt,
    input  logic [31:0] Interrupt_Address, // unused (vector via mtvec)
    output logic        Interrupt_Ack,     // unused

    // instruction LMB
    output logic [31:0] Instr_Addr,
    input  logic [31:0] Instr,
    output logic        IFetch,
    output logic        I_AS,
    input  logic        IReady,
    input  logic        IWAIT,
    input  logic        ICE,
    input  logic        IUE,

    // data LMB
    output logic [31:0] Data_Addr,
    input  logic [31:0] Data_Read,
    output logic [31:0] Data_Write,
    output logic        D_AS,
    output logic        Read_Strobe,
    output logic        Write_Strobe,
    input  logic        DReady,
    input  logic        DWait,
    input  logic        DCE,
    input  logic        DUE,
    output logic [3:0]  Byte_Enable,

    // debug (present for binding; functionally omitted in v1)
    input  logic        Dbg_Clk,
    input  logic        Dbg_TDI,
    output logic        Dbg_TDO,
    input  logic [7:0]  Dbg_Reg_En,
    input  logic        Dbg_Shift,
    input  logic        Dbg_Capture,
    input  logic        Dbg_Update,
    output logic        Dbg_Trig_In,
    input  logic [7:0]  Dbg_Trig_Ack_In,
    input  logic [7:0]  Dbg_Trig_Out,
    output logic        Dbg_Trig_Ack_Out,
    input  logic        Debug_Rst,
    input  logic        Dbg_Disable
);
  wire rst_n = ~Reset;

  rv_core #(.RESET_VEC(RESET_VEC)) u_core (
    .clk(Clk), .rst_n(rst_n),
    .o_iaddr(Instr_Addr), .o_ifetch(IFetch), .o_ias(I_AS),
    .i_instr(Instr), .i_iready(IReady),
    .o_daddr(Data_Addr), .o_dwrite(Data_Write), .o_das(D_AS),
    .o_rstrobe(Read_Strobe), .o_wstrobe(Write_Strobe), .o_be(Byte_Enable),
    .i_dread(Data_Read), .i_dready(DReady),
    .i_irq(Interrupt)
  );

  // unused outputs tied off
  assign Interrupt_Ack    = 1'b0;
  assign Dbg_TDO          = 1'b0;
  assign Dbg_Trig_In      = 1'b0;
  assign Dbg_Trig_Ack_Out = 1'b0;

  // explicitly mark unused inputs (lint hygiene)
  wire _unused = &{1'b0, Interrupt_Address, IWAIT, ICE, IUE, DWait, DCE, DUE,
                   Dbg_Clk, Dbg_TDI, Dbg_Reg_En, Dbg_Shift, Dbg_Capture, Dbg_Update,
                   Dbg_Trig_Ack_In, Dbg_Trig_Out, Debug_Rst, Dbg_Disable};
endmodule : mbv
