// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_alu.sv — base RV32I ALU (single-cycle, combinational). Zb* ops are in rv_bitmanip.sv.
module rv_alu
  import rv_pkg::*;
(
    input  alu_op_e     op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] y
);
  // Shifts (SLL/SRL/SRA) and rotates (ROL/ROR) live in the shared funnel shifter
  // in rv_core; this ALU handles the non-shift base ops only.
  always_comb begin
    unique case (op)
      ALU_ADD : y = a + b;
      ALU_SUB : y = a - b;
      ALU_SLT : y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      ALU_SLTU: y = (a < b)                    ? 32'd1 : 32'd0;
      ALU_XOR : y = a ^ b;
      ALU_OR  : y = a | b;
      ALU_AND : y = a & b;
      default : y = a + b;   // shifts/rotates -> funnel shifter; Zb* -> rv_bitmanip
    endcase
  end
endmodule : rv_alu
