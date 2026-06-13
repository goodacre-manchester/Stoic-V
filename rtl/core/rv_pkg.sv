// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_pkg.sv — shared parameters, enums, and the decode control bundle.
// See docs/microarchitecture.md. RV32IM_zba_zbb_zbs_zicsr, M-mode, little-endian.
`ifndef RV_PKG_SV
`define RV_PKG_SV

package rv_pkg;

  // ---------------------------------------------------------------------------
  // Build-time parameters
  // ---------------------------------------------------------------------------
  parameter logic [31:0] C_BASE_VECTORS = 32'h0000_0000; // reset PC (0x7800 for boot-ROM build)
  parameter logic [31:0] C_HART_ID      = 32'h0000_0000; // mhartid (unused by fw)

  // ---------------------------------------------------------------------------
  // ALU / functional-unit operation select (base + Zb*).
  // ---------------------------------------------------------------------------
  typedef enum logic [5:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU, ALU_XOR, ALU_SRL, ALU_SRA,
    ALU_OR,  ALU_AND,
    // Zba
    ALU_SH1ADD, ALU_SH2ADD, ALU_SH3ADD,
    // Zbb
    ALU_ANDN, ALU_ORN, ALU_XNOR, ALU_CLZ, ALU_CTZ, ALU_CPOP,
    ALU_MIN, ALU_MINU, ALU_MAX, ALU_MAXU, ALU_SEXTB, ALU_SEXTH, ALU_ZEXTH,
    ALU_ROL, ALU_ROR, ALU_ORCB, ALU_REV8,
    // Zbs
    ALU_BCLR, ALU_BEXT, ALU_BINV, ALU_BSET
  } alu_op_e;

  // M-extension op
  typedef enum logic [2:0] {
    MD_MUL, MD_MULH, MD_MULHSU, MD_MULHU, MD_DIV, MD_DIVU, MD_REM, MD_REMU
  } md_op_e;

  // Writeback source
  typedef enum logic [2:0] { WB_ALU, WB_MEM, WB_PC4, WB_CSR, WB_MD } wb_sel_e;

  // ALU operand-A / operand-B source
  typedef enum logic [1:0] { A_RS1, A_PC, A_ZERO } a_sel_e;
  typedef enum logic [0:0] { B_RS2, B_IMM } b_sel_e;

  // CSR micro-op (built from funct3)
  typedef enum logic [1:0] { CSR_RW, CSR_RS, CSR_RC } csr_op_e;

  // ---------------------------------------------------------------------------
  // Decode control bundle — flows down the pipeline with each instruction.
  // ---------------------------------------------------------------------------
  typedef struct packed {
    logic [4:0]  rd;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic        uses_rs1;
    logic        uses_rs2;
    logic        rd_we;        // writes a GPR
    logic [31:0] imm;
    alu_op_e     alu_op;
    a_sel_e      a_sel;
    b_sel_e      b_sel;
    wb_sel_e     wb_sel;
    logic        is_branch;
    logic [2:0]  br_funct3;
    logic        is_jal;
    logic        is_jalr;
    logic        is_load;
    logic        is_store;
    logic [1:0]  mem_size;     // 0=byte,1=half,2=word
    logic        mem_unsigned;
    logic        is_md;        // M-extension
    md_op_e      md_op;
    logic        is_csr;
    csr_op_e     csr_op;
    logic [11:0] csr_addr;
    logic        csr_imm;      // uimm form (CSRRWI/SI/CI)
    logic        is_mret;
    // NOTE: legal / is_wfi / is_ecall / is_ebreak are intentionally NOT pipeline
    // fields. `legal` is a decoder-local that squashes unrecognised instructions
    // to a NOP (v1 §10.3 carve-out: no illegal-instr trap); wfi/ecall/ebreak are
    // legal NOPs with no datapath effect, so nothing downstream reads them.
  } ctrl_t;

  // ---------------------------------------------------------------------------
  // CSR addresses (M-mode)
  // ---------------------------------------------------------------------------
  parameter logic [11:0] CSR_MSTATUS  = 12'h300;
  parameter logic [11:0] CSR_MISA     = 12'h301;
  parameter logic [11:0] CSR_MIE      = 12'h304;
  parameter logic [11:0] CSR_MTVEC    = 12'h305;
  parameter logic [11:0] CSR_MSCRATCH = 12'h340;
  parameter logic [11:0] CSR_MEPC     = 12'h341;
  parameter logic [11:0] CSR_MCAUSE   = 12'h342;
  parameter logic [11:0] CSR_MTVAL    = 12'h343;
  parameter logic [11:0] CSR_MIP      = 12'h344;
  parameter logic [11:0] CSR_MHARTID  = 12'hF14;
  parameter logic [11:0] CSR_MCYCLE   = 12'hB00;
  parameter logic [11:0] CSR_MCYCLEH  = 12'hB80;
  parameter logic [11:0] CSR_MINSTRET = 12'hB02;
  parameter logic [11:0] CSR_MINSTRETH= 12'hB82;

  // mstatus bit indices
  parameter int MSTATUS_MIE  = 3;
  parameter int MSTATUS_MPIE = 7;
  // mie/mip bit indices
  parameter int IRQ_MEI = 11;   // machine external interrupt

  // mcause for machine external interrupt
  parameter logic [31:0] MCAUSE_MEI = 32'h8000_000B;

  // major opcodes
  parameter logic [6:0] OP_LUI    = 7'b0110111;
  parameter logic [6:0] OP_AUIPC  = 7'b0010111;
  parameter logic [6:0] OP_JAL    = 7'b1101111;
  parameter logic [6:0] OP_JALR   = 7'b1100111;
  parameter logic [6:0] OP_BRANCH = 7'b1100011;
  parameter logic [6:0] OP_LOAD   = 7'b0000011;
  parameter logic [6:0] OP_STORE  = 7'b0100011;
  parameter logic [6:0] OP_OPIMM  = 7'b0010011;
  parameter logic [6:0] OP_OP     = 7'b0110011;
  parameter logic [6:0] OP_FENCE  = 7'b0001111;
  parameter logic [6:0] OP_SYSTEM = 7'b1110011;

endpackage : rv_pkg

`endif
