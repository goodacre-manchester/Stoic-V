// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_core.sv — in-order RV32IM_zba_zbb_zbs_zicsr M-mode core datapath.
// 5-stage pipeline (IF/ID/EX/MEM/WB) + decoupled fetch (depth-2 FIFO).
// Memory contract: registered, single-outstanding, in-order; ONE rising-edge address
// strobe per data access, DReady-handshaked (docs/microarchitecture.md §9).
// Determinism: fixed mul, non-early-terminating div, no caches/speculation/OoO.
module rv_core
  import rv_pkg::*;
#(
    parameter logic [31:0] RESET_VEC = C_BASE_VECTORS   // reset PC; default = build vector
)(
    input  logic        clk,
    input  logic        rst_n,        // synchronous, active-low here (mbv.sv inverts Reset)

    // instruction bus (registered 1-cycle slave)
    output logic [31:0] o_iaddr,
    output logic        o_ifetch,
    output logic        o_ias,
    input  logic [31:0] i_instr,
    input  logic        i_iready,

    // data bus (registered 1-cycle slave)
    output logic [31:0] o_daddr,
    output logic [31:0] o_dwrite,
    output logic        o_das,
    output logic        o_rstrobe,
    output logic        o_wstrobe,
    output logic [3:0]  o_be,
    input  logic [31:0] i_dread,
    input  logic        i_dready,

    // single machine-external interrupt (level)
    input  logic        i_irq
);
  // ===========================================================================
  // Forward declarations of control across stages
  // ===========================================================================
  logic        stall_d, stall_e, flush_younger, squash_ex, take_irq;
  logic        redirect;
  logic [31:0] redirect_pc;
  // Data-bus single-outstanding handshake. Honours DReady so the core works with
  // any FIXED-latency registered slave (1-cycle, or slower/back-pressured), not only
  // an exactly-1-cycle one. On a 1-cycle slave dmem_stall is identically 0 -> the
  // pipeline behaves bit-for-bit as before (determinism golden + all gates unchanged).
  logic        dmem_stall;

  // ===========================================================================
  // FETCH — decoupled, depth-2 instruction FIFO over the registered I-bus
  // ===========================================================================
  logic [31:0] fetch_pc;
  logic        inflight;
  logic [31:0] inflight_pc;

  // FIFO (depth 2)
  localparam int FD = 2;
  logic [31:0] fifo_instr [0:FD-1];
  logic [31:0] fifo_pc    [0:FD-1];
  logic [1:0]  fifo_count;
  logic        fifo_rd, fifo_wr;       // 1-bit pointers (mod 2)

  wire fifo_empty = (fifo_count == 2'd0);
  wire fifo_full  = (fifo_count == 2'd2);

  // returning fetch result this cycle
  wire ret = inflight & i_iready & ~flush_younger;
  // ID consumes (advances to EX)
  wire id_valid = ~fifo_empty;
  wire id_advance = id_valid & ~stall_d & ~stall_e & ~flush_younger & ~dmem_stall;
  // issue a new fetch. Gated by dmem_stall too (like stall_d/stall_e): during a data
  // freeze ID cannot drain the FIFO, so issuing would let it overflow on a long stall.
  wire issue = ~flush_younger & ~stall_d & ~stall_e & ~dmem_stall & (fifo_count < 2'd2) & ~(inflight & ~i_iready);

  wire [31:0] id_instr = fifo_instr[fifo_rd];
  wire [31:0] id_pc    = fifo_pc[fifo_rd];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      fetch_pc    <= RESET_VEC;
      inflight    <= 1'b0;
      inflight_pc <= '0;
      fifo_count  <= 2'd0;
      fifo_rd     <= 1'b0;
      fifo_wr     <= 1'b0;
    end else begin
      // ---- fetch issue / inflight tracking ----
      if (flush_younger) begin
        fetch_pc <= redirect_pc;
        inflight <= 1'b0;                 // drop any in-flight (wrong path)
      end else if (issue) begin
        inflight    <= 1'b1;
        inflight_pc <= fetch_pc;
        fetch_pc    <= fetch_pc + 32'd4;
      end else begin
        inflight <= 1'b0;
      end

      // ---- FIFO update ----
      if (flush_younger) begin
        fifo_count <= 2'd0;
        fifo_rd    <= 1'b0;
        fifo_wr    <= 1'b0;
      end else begin
        // push
        if (ret) begin
          fifo_instr[fifo_wr] <= i_instr;
          fifo_pc[fifo_wr]    <= inflight_pc;
          fifo_wr             <= ~fifo_wr;
        end
        // pop
        if (id_advance) begin
          fifo_rd <= ~fifo_rd;
        end
        // count
        unique case ({ret, id_advance})
          2'b10: fifo_count <= fifo_count + 2'd1;
          2'b01: fifo_count <= fifo_count - 2'd1;
          default: fifo_count <= fifo_count;
        endcase
      end
    end
  end

  assign o_iaddr  = fetch_pc;
  assign o_ias    = issue;
  assign o_ifetch = issue;

  // ===========================================================================
  // DECODE + register read (ID, combinational)
  // ===========================================================================
  ctrl_t id_ctrl;
  rv_decode u_dec (.instr(id_instr), .c(id_ctrl));

  logic [31:0] rf_rs1, rf_rs2;
  logic        rf_we;
  logic [4:0]  rf_wa;
  logic [31:0] rf_wd;
  rv_regfile u_rf (
    .clk(clk), .we(rf_we), .waddr(rf_wa), .wdata(rf_wd),
    .raddr1(id_ctrl.rs1), .raddr2(id_ctrl.rs2),
    .rdata1(rf_rs1), .rdata2(rf_rs2)
  );

  // ===========================================================================
  // ID/EX pipeline register
  // ===========================================================================
  logic        ex_valid;
  logic [31:0] ex_pc, ex_rs1v, ex_rs2v;
  ctrl_t       ex_ctrl;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      ex_valid <= 1'b0; ex_pc <= '0; ex_rs1v <= '0; ex_rs2v <= '0; ex_ctrl <= '0;
    end else if (dmem_stall) begin
      // hold (older load/store awaiting its registered DReady) — global freeze
    end else if (stall_e) begin
      // hold (mul/div busy in EX)
    end else if (stall_d || flush_younger) begin
      ex_valid <= 1'b0; ex_ctrl <= '0;        // bubble
    end else begin
      ex_valid <= id_valid;
      ex_pc    <= id_pc;
      ex_ctrl  <= id_ctrl;
      ex_rs1v  <= rf_rs1;
      ex_rs2v  <= rf_rs2;
    end
  end

  // ===========================================================================
  // EX — forwarding, ALU/bitmanip/muldiv/CSR/branch
  // ===========================================================================
  // forward sources — ALL registered (no combinational load_ext on the bypass net)
  logic        m_valid, m_rd_we, m_is_load;
  logic [4:0]  m_rd;
  logic [31:0] m_result;
  logic        w_valid, w_rd_we, w_is_load;
  logic [4:0]  w_rd;
  logic [31:0] w_result, w_pre;

  // Muldiv-result forward cut (in-context 250 MHz). The muldiv result's source
  // routes through u_md (DSP MREG/PREG), and the EX/MEM-result -> forward -> ALU
  // loop becomes the binding net once in-context routing congestion stretches it.
  // So the muldiv result is EXCLUDED from the combinational m_result/w_pre forward
  // (m_is_md/w_is_md tag it) and instead forwarded from a dedicated registered copy
  // (wmd_*) one stage past EX/MEM, placeable away from the DSP. dont_touch keeps a
  // flattened integration from merging it into the cross-boundary bypass LUTs. The
  // generic ALU-result forward stays combinational (fast). Cost: +1 cycle ONLY when
  // a mul/div result feeds the immediately-next dependent op (mduse_e stall).
  logic        m_is_md, w_is_md;
  logic        wmd_valid, wmd_rd_we;
  logic [4:0]  wmd_rd;
  (* dont_touch = "true" *) logic [31:0] wmd_result;
`ifndef CORE_PERF
  // P_LOADUSE = 2: the load result (load_ext) is combinational off i_dread — a
  // cascaded-BRAM read — so forwarding it puts Data_Read->load_ext->fwd->ALU on a
  // single cycle (a path that misses 250 MHz in a congested place-and-route).
  // Instead, register the load result (wl_*) and forward the REGISTERED copy; the
  // load-use stall grows to 2 so a dependent waits one extra cycle for wl. Loads
  // are therefore NEVER a combinational bypass source. dont_touch keeps a flattened
  // integration from dissolving this flop into the cross-boundary bypass LUTs.
  logic        wl_valid, wl_rd_we;
  logic [4:0]  wl_rd;
  (* dont_touch = "true" *) logic [31:0] wl_result;
`endif

  function automatic logic [31:0] fwd(input logic [4:0] rs, input logic [31:0] raw);
    // newest first. Muldiv results are excluded from the combinational EX/MEM and
    // MEM/WB forwards (!m_is_md/!w_is_md) and taken from the registered wmd copy.
    if      (m_valid   && m_rd_we && !m_is_load && !m_is_md && (m_rd  != 5'd0) && (m_rd  == rs)) fwd = m_result;
    else if (wmd_valid && wmd_rd_we                         && (wmd_rd != 5'd0) && (wmd_rd == rs)) fwd = wmd_result;
`ifdef CORE_PERF
    // 1-cycle load-use (CORE_PERF): forward w_result directly, incl. combinational
    // load_ext. Higher IPC (no load-use 2-cycle stall) but the Data_Read->load_ext->
    // fwd->ALU path is single-cycle -> not usable in a congested P&R (see ip-delivery).
    else if (w_valid  && w_rd_we && !w_is_md && (w_rd != 5'd0) && (w_rd == rs)) fwd = w_result;
`else
    // 2-cycle load-use (default): non-load/non-md from w_pre, load from registered wl.
    else if (w_valid  && w_rd_we && !w_is_load && !w_is_md && (w_rd  != 5'd0) && (w_rd  == rs)) fwd = w_pre;
    else if (wl_valid && wl_rd_we                          && (wl_rd != 5'd0) && (wl_rd == rs)) fwd = wl_result;
`endif
    else                                                                                        fwd = raw;
  endfunction

  logic [31:0] ex_a_fwd, ex_b_fwd;     // forwarded register operands
  // Driven from always_comb, NOT a continuous `assign`. fwd() reads module signals
  // (m_*/w_*/wmd_*/wl_*) that are NOT in its argument list; a continuous `assign` of a
  // function call is sensitised by some simulators (e.g. Vivado xsim) only to the
  // explicit arguments (ex_ctrl.rs1/ex_rs1v), so when the youngest forward source
  // changes while rs1 holds steady, the output goes STALE and the load-base/AGEN
  // forwards the OLDER same-rd writer (2026-06 in-context forward-inversion:
  // two back-to-back writers of the load base, M+W, return the W value). always_comb's
  // sensitivity (IEEE 1800 §9.2.2.2) includes reads inside called functions, so it is
  // tool-portable. Behaviour-identical in Verilator (which tracks the full dependency
  // either way) — every gate is unchanged; this only fixes the xsim sensitivity gap.
  always_comb begin
    ex_a_fwd = fwd(ex_ctrl.rs1, ex_rs1v);
    ex_b_fwd = fwd(ex_ctrl.rs2, ex_rs2v);
  end

  // ALU operand selection
  logic [31:0] alu_a, alu_b;
  always_comb begin
    unique case (ex_ctrl.a_sel)
      A_RS1 : alu_a = ex_a_fwd;
      A_PC  : alu_a = ex_pc;
      A_ZERO: alu_a = 32'd0;
      default: alu_a = ex_a_fwd;
    endcase
    alu_b = (ex_ctrl.b_sel == B_IMM) ? ex_ctrl.imm : ex_b_fwd;
  end

  // ---- shared funnel shifter: SLL/SRL/SRA/ROR/ROL on ONE 64-bit funnel ----
  // y = ({hi,lo} >> sh)[31:0], sh a 6-bit amount (0..32). Replaces the base-ALU
  // shifter AND the bit-manip rotate shifters, which previously coexisted in
  // silicon (op-muxed). SLL/ROL use sh = 32-shamt so shamt==0 needs no &31 mask.
  // Combinational and a *parallel* input to the result mux (not in series with the
  // EX adder), so it is off the critical path -> determinism and fmax unaffected.
  wire  [4:0]  shamt = alu_b[4:0];
  logic [31:0] sh_hi, sh_lo;
  logic [5:0]  sh_amt;
  always_comb begin
    unique case (ex_ctrl.alu_op)
      ALU_SLL: begin sh_hi = alu_a;           sh_lo = 32'd0; sh_amt = 6'd32 - {1'b0, shamt}; end
      ALU_SRA: begin sh_hi = {32{alu_a[31]}}; sh_lo = alu_a; sh_amt = {1'b0, shamt};         end
      ALU_ROL: begin sh_hi = alu_a;           sh_lo = alu_a; sh_amt = 6'd32 - {1'b0, shamt}; end
      ALU_ROR: begin sh_hi = alu_a;           sh_lo = alu_a; sh_amt = {1'b0, shamt};         end
      default: begin sh_hi = 32'd0;           sh_lo = alu_a; sh_amt = {1'b0, shamt};         end // SRL
    endcase
  end
  wire [63:0] funnel  = {sh_hi, sh_lo} >> sh_amt;
  wire [31:0] shift_y = funnel[31:0];
  wire        is_shift = (ex_ctrl.alu_op == ALU_SLL) || (ex_ctrl.alu_op == ALU_SRL)
                      || (ex_ctrl.alu_op == ALU_SRA) || (ex_ctrl.alu_op == ALU_ROL)
                      || (ex_ctrl.alu_op == ALU_ROR);

  logic [31:0] alu_y, bm_y;
  rv_alu      u_alu (.op(ex_ctrl.alu_op), .a(alu_a), .b(alu_b), .y(alu_y));
  rv_bitmanip u_bm  (.op(ex_ctrl.alu_op), .a(alu_a), .b(alu_b), .y(bm_y));
  wire is_bm = (ex_ctrl.alu_op >= ALU_SH1ADD);
  wire [31:0] arith_y = is_shift ? shift_y : (is_bm ? bm_y : alu_y);

  // address generation (load/store): base + imm
  wire [31:0] agen = ex_a_fwd + ex_ctrl.imm;

  // muldiv
  logic        md_start, md_busy, md_done, md_active;
  logic [31:0] md_result;
  rv_muldiv u_md (
    .clk(clk), .rst_n(rst_n), .start(md_start), .hold(dmem_stall), .op(ex_ctrl.md_op),
    .a(ex_a_fwd), .b(ex_b_fwd), .busy(md_busy), .done(md_done), .result(md_result)
  );
  assign md_start = ex_valid & ex_ctrl.is_md & ~md_active & ~md_done & ~dmem_stall;
  always_ff @(posedge clk) begin
    if (!rst_n) md_active <= 1'b0;
    else if (md_start) md_active <= 1'b1;
    else if (md_done)  md_active <= 1'b0;
  end

  // CSR (read combinational; commit in EX)
  logic [31:0] csr_rdata, csr_mtvec, csr_mepc;
  logic        csr_irq_pending;
  logic        csr_we;
  logic [31:0] csr_wsrc;
  logic        trap_take, mret_take;
  assign csr_wsrc = ex_ctrl.csr_imm ? {27'd0, ex_ctrl.rs1} : ex_a_fwd;
  // The CSR write must commit EXACTLY ONCE, on the cycle the instruction advances out
  // of EX — never while it is frozen in EX by a dmem_stall (an older load/store awaiting
  // its DReady in the single-outstanding gap). Without the ~dmem_stall gate, csr_we
  // stays asserted across the freeze: the write commits on the first stalled cycle, so
  // by the time the instruction advances `csr_rdata` (-> rd via ex_wb_value/m_result) is
  // already the NEW value, and a `csrr* rd, mscratch, rs` captures the modified CSR
  // instead of the architectural OLD value (the CRV stall-coincident CSR-RMW divergence,
  // tests/csr_dmem_hazard.s). Gated by ~dmem_stall, the single commit lands on the same
  // edge the EX/MEM register latches `csr_rdata` (still OLD that cycle) — rd gets OLD,
  // the CSR gets the new value, atomically. dmem_stall is the ONLY thing that holds a CSR
  // in EX (stall_e holds only mul/div; stall_d holds ID), so this is sufficient.
  // write happens unless RS/RC with zero source
  wire csr_write_en = ex_valid & ex_ctrl.is_csr & ~squash_ex & ~dmem_stall &
                      ~(((ex_ctrl.csr_op == CSR_RS) || (ex_ctrl.csr_op == CSR_RC)) & (csr_wsrc == 32'd0));
  assign csr_we = csr_write_en;

  rv_csr u_csr (
    .clk(clk), .rst_n(rst_n),
    .csr_addr(ex_ctrl.csr_addr), .csr_rdata(csr_rdata),
    .csr_we(csr_we), .csr_op(ex_ctrl.csr_op), .csr_wsrc(csr_wsrc),
    .irq_pin(i_irq), .irq_pending(csr_irq_pending),
    .trap_take(trap_take), .trap_epc(ex_pc), .mret_take(mret_take),
    .mtvec_o(csr_mtvec), .mepc_o(csr_mepc),
    .retire(w_valid & ~dmem_stall)   // count each instruction once, not per freeze cycle
  );

  // branch / jump resolution
  logic br_taken;
  always_comb begin
    unique case (ex_ctrl.br_funct3)
      3'b000: br_taken = (ex_a_fwd == ex_b_fwd);                 // BEQ
      3'b001: br_taken = (ex_a_fwd != ex_b_fwd);                 // BNE
      3'b100: br_taken = ($signed(ex_a_fwd) <  $signed(ex_b_fwd));// BLT
      3'b101: br_taken = ($signed(ex_a_fwd) >= $signed(ex_b_fwd));// BGE
      3'b110: br_taken = (ex_a_fwd <  ex_b_fwd);                 // BLTU
      3'b111: br_taken = (ex_a_fwd >= ex_b_fwd);                 // BGEU
      default:br_taken = 1'b0;
    endcase
  end

  // BRANCH and JAL share ONE pc-relative adder (identical target); JALR reuses the
  // agen adder (ex_a_fwd+imm), just clearing bit 0 — no separate jalr adder.
  wire [31:0] pcrel_target = ex_pc + ex_ctrl.imm;   // BRANCH + JAL
  wire [31:0] jalr_target  = agen & ~32'd1;          // JALR = (ex_a_fwd+imm) & ~1

  wire ex_branch_redirect = ex_valid & ((ex_ctrl.is_branch & br_taken) | ex_ctrl.is_jal | ex_ctrl.is_jalr);
  wire ex_mret            = ex_valid & ex_ctrl.is_mret;

  // ----- mul/div stall and interrupt entry (no combinational loop) -----
  // wfi is a legal NOP in v1 (spec allows NOP-or-sleep); it has no datapath effect.
  wire md_busy_stall = ex_valid & ex_ctrl.is_md & ~md_done;     // mid mul/div (uninterruptible)
  wire md_done_now   = ex_valid & ex_ctrl.is_md & md_done;      // completing this cycle (let it commit)

  // interrupt entry: at a valid EX boundary, not mid-mul/div, not on the md-complete
  // cycle, and not while an older load/store is awaiting its DReady (finish the
  // outstanding data access in order before trapping).
  assign take_irq = csr_irq_pending & ex_valid & ~md_busy_stall & ~md_done_now & ~dmem_stall;

  assign stall_e = md_busy_stall & ~take_irq;
  // load-use stall. Default (P_LOADUSE=2, the default 250 MHz build): hold the
  // dependent while the load is in EX *or* MEM (2 cycles) so it forwards from the
  // registered wl. CORE_PERF (P_LOADUSE=1): hold only while the load is in EX
  // (1 cycle); the dependent forwards w_result (incl. combinational load_ext) —
  // higher IPC, needs a relaxed clock.
  wire luse_ex = ex_valid & ex_ctrl.is_load & (ex_ctrl.rd != 5'd0)
               & ((id_ctrl.uses_rs1 & (id_ctrl.rs1 == ex_ctrl.rd))
                | (id_ctrl.uses_rs2 & (id_ctrl.rs2 == ex_ctrl.rd)));
  // muldiv-use: a mul/div result completing in EX is not a combinational forward
  // source (excluded from m_result), so hold an immediately-dependent op one cycle
  // in ID; it then forwards the registered wmd copy. +1 cycle, only on this adjacency.
  wire mduse_e = ex_valid & ex_ctrl.is_md & md_done & (ex_ctrl.rd != 5'd0)
               & ((id_ctrl.uses_rs1 & (id_ctrl.rs1 == ex_ctrl.rd))
                | (id_ctrl.uses_rs2 & (id_ctrl.rs2 == ex_ctrl.rd)));
`ifdef CORE_PERF
  assign stall_d = id_valid & (luse_ex | mduse_e) & ~stall_e & ~take_irq;
`else
  wire luse_m  = m_valid & m_is_load & (m_rd != 5'd0)
               & ((id_ctrl.uses_rs1 & (id_ctrl.rs1 == m_rd))
                | (id_ctrl.uses_rs2 & (id_ctrl.rs2 == m_rd)));
  assign stall_d = id_valid & (luse_ex | luse_m | mduse_e) & ~stall_e & ~take_irq;
`endif

  // ----- redirect / flush / trap commit -----
  always_comb begin
    redirect      = 1'b0;
    redirect_pc   = '0;
    trap_take     = 1'b0;
    mret_take     = 1'b0;
    squash_ex     = 1'b0;
    if (dmem_stall) begin
      // freeze: defer all control-flow changes (branch/jump/mret/trap) until the
      // outstanding data access completes, so the older access retires in order.
    end else if (take_irq) begin
      redirect    = 1'b1;  redirect_pc = csr_mtvec; trap_take = 1'b1; squash_ex = 1'b1;
    end else if (ex_mret) begin
      redirect    = 1'b1;  redirect_pc = csr_mepc;  mret_take = 1'b1;
    end else if (ex_branch_redirect) begin
      redirect    = 1'b1;  redirect_pc = ex_ctrl.is_jalr ? jalr_target : pcrel_target;
    end
  end
  assign flush_younger = redirect;

  // EX writeback value (non-load)
  logic [31:0] ex_wb_value;
  always_comb begin
    unique case (ex_ctrl.wb_sel)
      WB_ALU : ex_wb_value = arith_y;
      WB_PC4 : ex_wb_value = ex_pc + 32'd4;
      WB_CSR : ex_wb_value = csr_rdata;
      WB_MD  : ex_wb_value = md_result;
      default: ex_wb_value = arith_y;   // WB_MEM handled in WB stage
    endcase
  end

  // ===========================================================================
  // EX/MEM pipeline register
  // ===========================================================================
  logic [31:0] m_pc;
  ctrl_t       m_ctrl;
  logic [31:0] m_addr, m_storedata;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      m_valid <= 1'b0; m_ctrl <= '0; m_rd <= '0; m_rd_we <= 1'b0; m_is_load <= 1'b0; m_is_md <= 1'b0;
      m_result <= '0; m_addr <= '0; m_storedata <= '0; m_pc <= '0;
    end else if (dmem_stall) begin
      // hold: the MEM access (or the instruction behind a stalled WB load) freezes
      // until the outstanding access is acknowledged (single-outstanding ordering).
    end else if (stall_e) begin
      m_valid <= 1'b0; m_ctrl <= '0; m_rd_we <= 1'b0; m_is_load <= 1'b0; m_is_md <= 1'b0;  // EX stuck -> bubble
    end else begin
      // on stall_d the load in EX advances to MEM normally (only ID/EX bubbles)
      m_valid     <= ex_valid & ~squash_ex;
      m_ctrl      <= ex_ctrl;
      m_pc        <= ex_pc;
      m_rd        <= ex_ctrl.rd;
      m_rd_we     <= ex_ctrl.rd_we & ex_valid & ~squash_ex;
      m_is_load   <= ex_ctrl.is_load & ex_valid & ~squash_ex;
      m_is_md     <= ex_ctrl.is_md   & ex_valid & ~squash_ex;
      m_result    <= ex_wb_value;   // load value comes from load_ext at WB; m_addr carries the address
                                    // (dropping the dead is_load?agen mux also shortens the path into m_result_reg)
      m_addr      <= agen;
      m_storedata <= ex_b_fwd;
    end
  end

  // ===========================================================================
  // MEM — drive the registered data bus (address phase)
  // ===========================================================================
  logic [3:0]  be;
  logic [31:0] sdata;
  always_comb begin
    // byte-enable + lane-aligned store data
    unique case (m_ctrl.mem_size)
      2'd0: begin // byte
        be    = 4'b0001 << m_addr[1:0];
        sdata = m_storedata << (8*m_addr[1:0]);
      end
      2'd1: begin // half
        be    = m_addr[1] ? 4'b1100 : 4'b0011;
        sdata = m_storedata << (8*{m_addr[1],1'b0});
      end
      default: begin // word
        be    = 4'b1111;
        sdata = m_storedata;
      end
    endcase
  end

  // ---- data-bus single-outstanding handshake (one address strobe per access) -----
  // The host data slave (and MicroBlaze-V's own LMB) starts an access on the RISING
  // EDGE of the strobe and HOLDS DReady while the request stays asserted (LMB Ready =
  // registered address-strobe). So the strobe MUST pulse once per access — a strobe
  // held high across back-to-back loads only ever edges once, and every load after the
  // first re-reads the first access's registered data (the in-context stale-read bug).
  //
  // d_inflight tracks the core's OWN outstanding access (set the cycle after a strobe).
  // A new strobe is issued only when nothing is outstanding (d_issue), so consecutive
  // accesses get a one-cycle gap -> a clean rising edge each, matching MB-V. The access
  // completes when the slave returns DReady (d_complete). This also makes the core
  // robust to any FIXED-latency registered slave (1-cycle or slower), not just exactly
  // one cycle. Determinism is preserved: timing depends only on the access pattern and
  // the (data-independent) slave latency, never on data.
  wire mem_req   = m_valid & (m_ctrl.is_load | m_ctrl.is_store);
  logic d_inflight;
  wire  d_issue    = mem_req & ~d_inflight;     // one strobe (rising edge) per access
  wire  d_complete = d_inflight & i_dready;     // our outstanding access acks
  always_ff @(posedge clk) begin
    if (!rst_n)          d_inflight <= 1'b0;
    else if (d_issue)    d_inflight <= 1'b1;
    else if (d_complete) d_inflight <= 1'b0;
  end
  // Freeze the pipeline while an access is outstanding and either (a) a new memory op
  // in MEM is waiting to strobe (single-outstanding + the gap that makes its rising
  // edge), or (b) the slave has not yet acknowledged this access (~DReady). An
  // isolated access (followed by a non-memory op) sees mem_req=0 and, on a 1-cycle
  // slave, DReady the next cycle -> no stall; only consecutive accesses pay the gap.
  assign dmem_stall = d_inflight & (mem_req | ~i_dready);

  assign o_daddr   = m_addr;
  assign o_dwrite  = sdata;
  assign o_rstrobe = d_issue & m_ctrl.is_load;
  assign o_wstrobe = d_issue & m_ctrl.is_store;
  assign o_das     = d_issue;
  assign o_be      = be;

  // ===========================================================================
  // MEM/WB pipeline register
  // ===========================================================================
  ctrl_t       w_ctrl;       // w_pre / w_is_load are declared with the forward sources
  logic [1:0]  w_addrlo;
  logic [31:0] w_pc;        // retiring-instruction PC (cosim retire trace; pruned in synth)
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      w_valid <= 1'b0; w_ctrl <= '0; w_rd <= '0; w_rd_we <= 1'b0; w_is_load <= 1'b0; w_is_md <= 1'b0;
      w_pre <= '0; w_addrlo <= '0; w_pc <= '0;
    end else if (dmem_stall) begin
      // hold the WB load in place until its data arrives (DReady) — see o_das block
    end else begin
      w_valid  <= m_valid;
      w_ctrl   <= m_ctrl;
      w_rd     <= m_rd;
      w_rd_we  <= m_rd_we;
      w_is_load<= m_is_load;
      w_is_md  <= m_is_md;
      w_pre    <= m_result;
      w_addrlo <= m_addr[1:0];
      w_pc     <= m_pc;
    end
  end

  // Registered muldiv-result forward (dont_touch flop, one stage past EX/MEM). It
  // captures the muldiv result while it is in EX/MEM, so a dependent forwards this
  // register (placeable away from the DSP) instead of combinational m_result. Valid
  // for exactly the cycle the muldiv result is MEM/WB-aged; the mduse_e stall holds
  // an immediately-dependent op one cycle so it lands here.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wmd_valid <= 1'b0; wmd_rd_we <= 1'b0; wmd_rd <= '0; wmd_result <= '0;
    end else if (dmem_stall) begin
      // hold (aligned with the frozen EX/MEM stage)
    end else begin
      wmd_valid  <= m_valid & m_is_md;
      wmd_rd_we  <= m_rd_we;
      wmd_rd     <= m_rd;
      wmd_result <= m_result;
    end
  end

  // ===========================================================================
  // WB — load lane-select + sign/zero extend; regfile write; result mux
  // ===========================================================================
  logic [31:0] load_ext;
  logic [31:0] lw;
  // P7.1 store->load fix: latch the load's OWN bus word the cycle its access acks
  // (d_complete & the WB instr is a load), and commit that LATCHED word — not the
  // live bus. On a canonical FREE-RUNNING registered slave (Xilinx BRAM Port A:
  // `q <= mem[addr]` every cycle, e.g. a host tile's `data_rd_q`), the read data
  // tracks o_daddr, which advances to the NEXT access while dmem_stall holds this
  // load in WB across the single-outstanding gap — so a combinational `lw = i_dread`
  // commits the next access's word (the reported stale ra <- next-slot read). The
  // bypass `ld_ack ? i_dread : ld_word` uses the live word on the one cycle it is
  // valid (the isolated/no-stall case) and the latch thereafter. Behaviour-identical
  // on hold-type slaves (level/edge/back-pressure, which hold the word anyway) and
  // determinism-neutral (the commit cycle, rf_we, is unchanged).
  logic [31:0] ld_word;
  wire ld_ack = d_complete & w_valid & w_is_load;   // the cycle THIS load's data is live
  always_ff @(posedge clk) begin
    if (!rst_n)      ld_word <= '0;
    else if (ld_ack) ld_word <= i_dread;
  end
  assign lw = ld_ack ? i_dread : ld_word;
  always_comb begin
    logic [7:0]  b8;
    logic [15:0] h16;
    b8  = lw[8*w_addrlo +: 8];
    h16 = w_addrlo[1] ? lw[31:16] : lw[15:0];
    unique case (w_ctrl.mem_size)
      2'd0: load_ext = w_ctrl.mem_unsigned ? {24'd0, b8}  : {{24{b8[7]}},  b8};
      2'd1: load_ext = w_ctrl.mem_unsigned ? {16'd0, h16} : {{16{h16[15]}},h16};
      default: load_ext = lw;
    endcase
  end

  assign w_result = (w_ctrl.wb_sel == WB_MEM) ? load_ext : w_pre;

`ifndef CORE_PERF
  // P_LOADUSE = 2 register: capture the WB load result so the load-use forward
  // reads a REGISTERED value (wl_result), never combinational load_ext. Only loads
  // load it; otherwise it holds an invalid entry. The regfile write below still
  // commits the load at WB (rf_wd = w_result), so retire timing is unchanged — only
  // the load-USE bypass is one cycle later (absorbed by the 2-cycle load-use stall).
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      wl_valid <= 1'b0; wl_rd_we <= 1'b0; wl_rd <= '0; wl_result <= '0;
    end else if (dmem_stall) begin
      // hold until the load retires; load_ext is only valid on the (un-stalled)
      // cycle DReady acks the load, which is exactly when this flop next updates.
    end else begin
      wl_valid  <= w_valid & (w_ctrl.wb_sel == WB_MEM);
      wl_rd_we  <= w_rd_we;
      wl_rd     <= w_rd;
      wl_result <= load_ext;
    end
  end
`endif

  // commit only when the WB instruction actually retires — never during a data-bus
  // wait (dmem_stall), where load_ext would still be stale. On a 1-cycle slave
  // dmem_stall is 0, so this is the original gate.
  assign rf_we = w_valid & w_rd_we & (w_rd != 5'd0) & ~dmem_stall;
  assign rf_wa = w_rd;
  assign rf_wd = w_result;

`ifdef RV_DBG
  always_ff @(posedge clk) if (rst_n)
    $display("[%0t] EXpc=%08h exv=%b isld=%b rd=%0d | IDpc=%08h idv=%b rs1=%0d uses1=%b | sd=%b se=%b m(v=%b rd=%0d ld=%b res=%08h) w(v=%b rd=%0d res=%08h)",
      $time, ex_pc, ex_valid, ex_ctrl.is_load, ex_ctrl.rd, id_pc, id_valid, id_ctrl.rs1, id_ctrl.uses_rs1,
      stall_d, stall_e, m_valid, m_rd, m_is_load, m_result, w_valid, w_rd, w_result);
`endif

endmodule : rv_core
