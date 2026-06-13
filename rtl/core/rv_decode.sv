// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_decode.sv — instruction decoder + immediate generation.
// Produces the ctrl_t control bundle (rv_pkg). RV32IM_zba_zbb_zbs_zicsr, M-mode.
module rv_decode
  import rv_pkg::*;
(
    input  logic [31:0] instr,
    output ctrl_t       c
);
  logic [6:0] opcode, funct7;
  logic [2:0] funct3;
  logic [4:0] rd, rs1, rs2;
  logic [11:0] csr_addr;

  assign opcode = instr[6:0];
  assign rd     = instr[11:7];
  assign funct3 = instr[14:12];
  assign rs1    = instr[19:15];
  assign rs2    = instr[24:20];
  assign funct7 = instr[31:25];
  assign csr_addr = instr[31:20];

  // immediates
  logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
  assign imm_i = {{20{instr[31]}}, instr[31:20]};
  assign imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  assign imm_u = {instr[31:12], 12'd0};
  assign imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

  always_comb begin
    logic legal;   // decoder-local "recognised instruction?" — gates the illegal->NOP
                   // squash below; NOT a pipeline field (v1 omits illegal-instr trap, §10.3)
    // defaults: illegal NOP (carved-out: illegal -> defined NOP, see README trap model / the §10.3 carve-out)
    c = '0;
    legal        = 1'b0;
    c.rd         = rd;
    c.rs1        = rs1;
    c.rs2        = rs2;
    c.imm        = imm_i;
    c.alu_op     = ALU_ADD;
    c.a_sel      = A_RS1;
    c.b_sel      = B_IMM;
    c.wb_sel     = WB_ALU;
    c.md_op      = MD_MUL;
    c.csr_op     = CSR_RW;
    c.csr_addr   = csr_addr;
    c.mem_size   = 2'd2;

    unique case (opcode)
      OP_LUI: begin
        legal = 1'b1; c.rd_we = 1'b1; c.imm = imm_u;
        c.a_sel = A_ZERO; c.b_sel = B_IMM; c.alu_op = ALU_ADD;
      end
      OP_AUIPC: begin
        legal = 1'b1; c.rd_we = 1'b1; c.imm = imm_u;
        c.a_sel = A_PC; c.b_sel = B_IMM; c.alu_op = ALU_ADD;
      end
      OP_JAL: begin
        legal = 1'b1; c.rd_we = 1'b1; c.is_jal = 1'b1; c.imm = imm_j;
        c.wb_sel = WB_PC4;
      end
      OP_JALR: begin
        if (funct3 == 3'b000) begin
          legal = 1'b1; c.rd_we = 1'b1; c.is_jalr = 1'b1; c.imm = imm_i;
          c.uses_rs1 = 1'b1; c.wb_sel = WB_PC4;
        end
      end
      OP_BRANCH: begin
        unique case (funct3)
          3'b000,3'b001,3'b100,3'b101,3'b110,3'b111: begin
            legal = 1'b1; c.is_branch = 1'b1; c.br_funct3 = funct3; c.imm = imm_b;
            c.uses_rs1 = 1'b1; c.uses_rs2 = 1'b1;
          end
          default: ;
        endcase
      end
      OP_LOAD: begin
        unique case (funct3)
          3'b000,3'b001,3'b010,3'b100,3'b101: begin
            legal = 1'b1; c.rd_we = 1'b1; c.is_load = 1'b1; c.imm = imm_i;
            c.uses_rs1 = 1'b1; c.wb_sel = WB_MEM;
            c.mem_size     = funct3[1:0];
            c.mem_unsigned = funct3[2];
          end
          default: ;
        endcase
      end
      OP_STORE: begin
        unique case (funct3)
          3'b000,3'b001,3'b010: begin
            legal = 1'b1; c.is_store = 1'b1; c.imm = imm_s;
            c.uses_rs1 = 1'b1; c.uses_rs2 = 1'b1;
            c.mem_size = funct3[1:0];
          end
          default: ;
        endcase
      end
      OP_OPIMM: begin
        legal = 1'b1; c.rd_we = 1'b1; c.uses_rs1 = 1'b1; c.imm = imm_i;
        c.a_sel = A_RS1; c.b_sel = B_IMM;
        unique case (funct3)
          3'b000: c.alu_op = ALU_ADD;                 // ADDI
          3'b010: c.alu_op = ALU_SLT;                 // SLTI
          3'b011: c.alu_op = ALU_SLTU;                // SLTIU
          3'b100: c.alu_op = ALU_XOR;                 // XORI
          3'b110: c.alu_op = ALU_OR;                  // ORI
          3'b111: c.alu_op = ALU_AND;                 // ANDI
          3'b001: begin                               // SLLI / Zb* single-bit-imm / count
            unique case (funct7)
              7'b0000000: c.alu_op = ALU_SLL;
              7'b0110000: begin                       // Zbb unary (CLZ/CTZ/CPOP/SEXT.B/SEXT.H)
                unique case (rs2)
                  5'b00000: c.alu_op = ALU_CLZ;
                  5'b00001: c.alu_op = ALU_CTZ;
                  5'b00010: c.alu_op = ALU_CPOP;
                  5'b00100: c.alu_op = ALU_SEXTB;
                  5'b00101: c.alu_op = ALU_SEXTH;
                  default : legal = 1'b0;
                endcase
              end
              7'b0010100: c.alu_op = ALU_BSET;        // BSETI
              7'b0100100: c.alu_op = ALU_BCLR;        // BCLRI
              7'b0110100: c.alu_op = ALU_BINV;        // BINVI
              default   : legal = 1'b0;
            endcase
          end
          3'b101: begin                               // SRLI/SRAI/RORI/Zbs/ORC.B/REV8
            unique case (funct7)
              7'b0000000: c.alu_op = ALU_SRL;
              7'b0100000: c.alu_op = ALU_SRA;
              7'b0110000: c.alu_op = ALU_ROR;         // RORI
              7'b0100100: c.alu_op = ALU_BEXT;        // BEXTI
              7'b0010100: begin                       // ORC.B (rs2=00111) else illegal
                if (rs2 == 5'b00111) c.alu_op = ALU_ORCB; else legal = 1'b0;
              end
              7'b0110100: begin                       // REV8 (rs2=11000 on rv32)
                if (rs2 == 5'b11000) c.alu_op = ALU_REV8; else legal = 1'b0;
              end
              default   : legal = 1'b0;
            endcase
          end
          default: legal = 1'b0;
        endcase
      end
      OP_OP: begin
        legal = 1'b1; c.rd_we = 1'b1; c.uses_rs1 = 1'b1; c.uses_rs2 = 1'b1;
        c.a_sel = A_RS1; c.b_sel = B_RS2;
        unique case (funct7)
          7'b0000000: begin
            unique case (funct3)
              3'b000: c.alu_op = ALU_ADD;
              3'b001: c.alu_op = ALU_SLL;
              3'b010: c.alu_op = ALU_SLT;
              3'b011: c.alu_op = ALU_SLTU;
              3'b100: c.alu_op = ALU_XOR;
              3'b101: c.alu_op = ALU_SRL;
              3'b110: c.alu_op = ALU_OR;
              3'b111: c.alu_op = ALU_AND;
              default: legal = 1'b0;
            endcase
          end
          7'b0100000: begin
            unique case (funct3)
              3'b000: c.alu_op = ALU_SUB;
              3'b101: c.alu_op = ALU_SRA;
              3'b100: c.alu_op = ALU_XNOR;            // Zbb
              3'b110: c.alu_op = ALU_ORN;             // Zbb
              3'b111: c.alu_op = ALU_ANDN;            // Zbb
              default: legal = 1'b0;
            endcase
          end
          7'b0000001: begin                           // M extension
            c.is_md = 1'b1; c.wb_sel = WB_MD;
            unique case (funct3)
              3'b000: c.md_op = MD_MUL;
              3'b001: c.md_op = MD_MULH;
              3'b010: c.md_op = MD_MULHSU;
              3'b011: c.md_op = MD_MULHU;
              3'b100: c.md_op = MD_DIV;
              3'b101: c.md_op = MD_DIVU;
              3'b110: c.md_op = MD_REM;
              3'b111: c.md_op = MD_REMU;
              default: legal = 1'b0;
            endcase
          end
          7'b0010000: begin                           // Zba sh#add
            unique case (funct3)
              3'b010: c.alu_op = ALU_SH1ADD;
              3'b100: c.alu_op = ALU_SH2ADD;
              3'b110: c.alu_op = ALU_SH3ADD;
              default: legal = 1'b0;
            endcase
          end
          7'b0010100: begin                           // Zbs BSET / Zbb min/max(u) share funct7 0000101
            unique case (funct3)
              3'b001: c.alu_op = ALU_BSET;            // BSET
              default: legal = 1'b0;
            endcase
          end
          7'b0100100: begin                           // BCLR / BEXT
            unique case (funct3)
              3'b001: c.alu_op = ALU_BCLR;
              3'b101: c.alu_op = ALU_BEXT;
              default: legal = 1'b0;
            endcase
          end
          7'b0110100: begin                           // BINV
            unique case (funct3)
              3'b001: c.alu_op = ALU_BINV;
              default: legal = 1'b0;
            endcase
          end
          7'b0110000: begin                           // ROL / ROR
            unique case (funct3)
              3'b001: c.alu_op = ALU_ROL;
              3'b101: c.alu_op = ALU_ROR;
              default: legal = 1'b0;
            endcase
          end
          7'b0000101: begin                           // Zbb MIN/MAX/MINU/MAXU
            unique case (funct3)
              3'b100: c.alu_op = ALU_MIN;
              3'b101: c.alu_op = ALU_MINU;
              3'b110: c.alu_op = ALU_MAX;
              3'b111: c.alu_op = ALU_MAXU;
              default: legal = 1'b0;
            endcase
          end
          7'b0000100: begin                           // ZEXT.H (rv32: funct7=0000100, rs2=0, f3=100)
            if (funct3 == 3'b100 && rs2 == 5'b00000) c.alu_op = ALU_ZEXTH;
            else legal = 1'b0;
          end
          default: legal = 1'b0;
        endcase
      end
      OP_FENCE: begin
        legal = 1'b1;                               // FENCE/FENCE.I -> NOP
      end
      OP_SYSTEM: begin
        unique case (funct3)
          3'b000: begin
            unique case (instr[31:20])
              12'h000: legal = 1'b1;                          // ECALL  -> NOP (v1: no trap)
              12'h001: legal = 1'b1;                          // EBREAK -> NOP (v1: no trap)
              12'h302: begin legal = 1'b1; c.is_mret = 1'b1; end
              12'h105: legal = 1'b1;                          // WFI    -> NOP/sleep
              default: legal = 1'b0;
            endcase
          end
          3'b001,3'b010,3'b011: begin                 // CSRRW/S/C
            legal = 1'b1; c.is_csr = 1'b1; c.rd_we = 1'b1; c.wb_sel = WB_CSR;
            c.uses_rs1 = 1'b1;
            c.csr_op = (funct3 == 3'b001) ? CSR_RW : (funct3 == 3'b010) ? CSR_RS : CSR_RC;
          end
          3'b101,3'b110,3'b111: begin                 // CSRRWI/SI/CI
            legal = 1'b1; c.is_csr = 1'b1; c.rd_we = 1'b1; c.wb_sel = WB_CSR;
            c.csr_imm = 1'b1;
            c.csr_op = (funct3 == 3'b101) ? CSR_RW : (funct3 == 3'b110) ? CSR_RS : CSR_RC;
          end
          default: legal = 1'b0;
        endcase
      end
      default: legal = 1'b0;
    endcase

    // illegal instruction -> harmless NOP that writes nothing (v1 omits illegal-instr trap)
    if (!legal) begin
      c.rd_we = 1'b0; c.is_branch = 1'b0; c.is_jal = 1'b0; c.is_jalr = 1'b0;
      c.is_load = 1'b0; c.is_store = 1'b0; c.is_md = 1'b0; c.is_csr = 1'b0;
      c.is_mret = 1'b0;
      c.uses_rs1 = 1'b0; c.uses_rs2 = 1'b0;
    end
  end
endmodule : rv_decode
