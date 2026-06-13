// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_bitmanip.sv — Zba/Zbb/Zbs ops (single-cycle, combinational, data-independent latency).
module rv_bitmanip
  import rv_pkg::*;
(
    input  alu_op_e     op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] y
);
  logic [4:0]  bidx;
  assign bidx  = b[4:0];

  // count trailing zeros (0..32)
  function automatic logic [5:0] ctz_f(input logic [31:0] v);
    logic [5:0] n; logic done;
    begin
      n = 6'd0; done = 1'b0;
      for (int i = 0; i < 32; i++) begin
        if (!done && v[i]) done = 1'b1;
        else if (!done)   n = n + 6'd1;
      end
      ctz_f = n;              // returns 32 if v==0
    end
  endfunction

  function automatic logic [5:0] cpop_f(input logic [31:0] v);
    logic [5:0] n;
    begin
      n = 6'd0;
      for (int i = 0; i < 32; i++) n = n + {5'd0, v[i]};
      cpop_f = n;
    end
  endfunction

  // clz(a) == ctz(reverse(a)) — share ONE count-trailing-zeros unit; the reverse
  // is free wiring, so the separate clz counter is gone (input muxed for CLZ).
  wire [31:0] a_rev = {<<{a}};
  wire [5:0]  tz    = ctz_f((op == ALU_CLZ) ? a_rev : a);

  // SLL/SRL/SRA/ROL/ROR are handled by the shared funnel shifter in rv_core.
  always_comb begin
    y = '0;
    unique case (op)
      ALU_SH1ADD: y = (a << 1) + b;
      ALU_SH2ADD: y = (a << 2) + b;
      ALU_SH3ADD: y = (a << 3) + b;
      ALU_ANDN  : y = a & ~b;
      ALU_ORN   : y = a | ~b;
      ALU_XNOR  : y = ~(a ^ b);
      ALU_CLZ   : y = {26'd0, tz};
      ALU_CTZ   : y = {26'd0, tz};
      ALU_CPOP  : y = {26'd0, cpop_f(a)};
      ALU_MIN   : y = ($signed(a) < $signed(b)) ? a : b;
      ALU_MINU  : y = (a < b) ? a : b;
      ALU_MAX   : y = ($signed(a) > $signed(b)) ? a : b;
      ALU_MAXU  : y = (a > b) ? a : b;
      ALU_SEXTB : y = {{24{a[7]}},  a[7:0]};
      ALU_SEXTH : y = {{16{a[15]}}, a[15:0]};
      ALU_ZEXTH : y = {16'd0, a[15:0]};
      ALU_ORCB  : begin
        y[7:0]   = (|a[7:0])   ? 8'hFF : 8'h00;
        y[15:8]  = (|a[15:8])  ? 8'hFF : 8'h00;
        y[23:16] = (|a[23:16]) ? 8'hFF : 8'h00;
        y[31:24] = (|a[31:24]) ? 8'hFF : 8'h00;
      end
      ALU_REV8  : y = {a[7:0], a[15:8], a[23:16], a[31:24]};
      ALU_BCLR  : y = a & ~(32'd1 << bidx);
      ALU_BEXT  : y = {31'd0, a[bidx]};
      ALU_BINV  : y = a ^ (32'd1 << bidx);
      ALU_BSET  : y = a | (32'd1 << bidx);
      default   : y = '0;
    endcase
  end
endmodule : rv_bitmanip
