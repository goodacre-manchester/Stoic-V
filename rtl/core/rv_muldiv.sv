// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// rv_muldiv.sv — M extension. Fixed-latency multiply + NON-early-terminating
// restoring divider (constant 32-iteration latency for ALL operands -> determinism).
//
// Multiply: ONE signed 33x33 product covers mul/mulh/mulhsu/mulhu (operand sign
// bits chosen per op), mapped to a single DSP48E2 cascade with the multiply
// REGISTERED across two pipeline stages (pm1=MREG, pm2=PREG) so the 32x32+cascade
// path closes at 250 MHz. Fixed MUL_LAT = 4 cycles (determinism preserved); ~4
// DSP48E2 (was 12 with three parallel 64b products). See timing-and-resources §2/§3.
module rv_muldiv
  import rv_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,     // 1-cycle pulse to begin (ignored while busy)
    input  logic        hold,      // freeze the FSM (data-bus wait); 0 on a 1-cycle slave
    input  md_op_e      op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        busy,      // high from accept until the cycle before done
    output logic        done,      // 1-cycle pulse: result valid
    output logic [31:0] result
);
  typedef enum logic [2:0] { IDLE, MUL1, MUL2, MUL3, DIVRUN, FIN } state_e;
  state_e st;

  logic [5:0]  cnt;
  md_op_e      op_q;
  logic [31:0] a_q, b_q;

  // ---- multiply: single signed 33x33, pipelined (MREG/PREG) -> fixed MUL_LAT=4 ----
  // a is signed for all but MULHU; b is signed only for MUL/MULH. The 33rd bit is
  // the (op-selected) sign bit so one signed multiply serves every variant.
  wire               a_signed = (op_q != MD_MULHU);
  wire               b_signed = (op_q == MD_MUL) || (op_q == MD_MULH);
  wire signed [32:0] a33  = $signed({a_signed & a_q[31], a_q});
  wire signed [32:0] b33  = $signed({b_signed & b_q[31], b_q});
  wire signed [65:0] prod = a33 * b33;          // -> DSP48E2 cascade
  logic signed [65:0] pm1, pm2;                 // pipeline regs (DSP MREG, PREG)
  wire [31:0] mul_res = (op_q == MD_MUL) ? pm2[31:0] : pm2[63:32];

  // ---- divider state ----
  logic        neg_q, neg_r;          // result sign corrections
  logic [31:0] divr_mag;              // divisor magnitude (the dividend magnitude lives in rq)
  logic        div_zero, div_ovf;
  // Quotient/remainder are NOT separately registered: after the 32 restoring
  // steps rq holds {rem[31:0], quot[31:0]} and is untouched into FIN, so FIN
  // reads them straight out of rq (saves the 64-FF quot/rem copy).

  // restoring step working regs
  logic [63:0] rq;                    // {rem[31:0], quot[31:0]} composite shift
  logic [31:0] sub;
  logic        ge;

  assign sub = rq[62:31] - divr_mag;          // compare top 32 bits with divisor
  assign ge  = (rq[62:31] >= divr_mag);

  function automatic logic [31:0] absval(input logic [31:0] v);
    absval = v[31] ? (~v + 32'd1) : v;
  endfunction

  logic [31:0] div_result;
  always_comb begin
    // Only ONE of quot/rem is the result for a given op, so select first and
    // sign-correct with a SINGLE 2's-complement unit (was one per quot/rem; the
    // tool need not share two negators across the result mux). DIVU/REMU set
    // sel_neg=0 so sel_corrected passes the raw magnitude through unchanged.
    logic [31:0] sel_raw, sel_corrected;
    logic        sel_neg;
    sel_raw       = (op_q == MD_DIV || op_q == MD_DIVU) ? rq[31:0] : rq[63:32];
    sel_neg       = (op_q == MD_DIV) ? neg_q : (op_q == MD_REM) ? neg_r : 1'b0;
    sel_corrected = sel_neg ? (~sel_raw + 32'd1) : sel_raw;   // single shared negate
    unique case (op_q)
      MD_DIV : div_result = div_zero ? 32'hFFFF_FFFF : (div_ovf ? 32'h8000_0000 : sel_corrected);
      MD_DIVU: div_result = div_zero ? 32'hFFFF_FFFF : sel_corrected;
      MD_REM : div_result = div_zero ? a_q          : (div_ovf ? 32'h0000_0000 : sel_corrected);
      MD_REMU: div_result = div_zero ? a_q          : sel_corrected;
      default: div_result = 32'd0;
    endcase
  end

  wire is_div = (op == MD_DIV) || (op == MD_DIVU) || (op == MD_REM) || (op == MD_REMU);

  // SYNCHRONOUS reset (core-wide convention; no `negedge rst_n` in any sensitivity
  // list). Xilinx-recommended for FPGA (UG901): an async reset is a per-register
  // control net that here forbids the DSP48E2 from packing the multiply pipeline
  // regs (pm1=MREG/pm2=PREG are sync-reset-only) and trips "Set+reset same
  // priority" (Synth 8-7137) on the datapath regs. The control regs reset
  // synchronously; the datapath regs carry no reset (don't-care until `done`).
  // Behaviour-identical given reset is held >=1 clock (always true) -> determinism
  // and cycle counts unchanged.
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      st <= IDLE; busy <= 1'b0; done <= 1'b0; result <= 32'd0; cnt <= 6'd0;
    end else if (hold) begin
      // Data-bus wait (dmem_stall): freeze the whole FSM in place — st/cnt/regs/
      // busy/done all hold — so an in-flight mul/div neither advances nor restarts
      // while an older load waits for its registered DReady. hold is 0 on a 1-cycle
      // slave, so this is behaviour/cycle-neutral for every normal build.
    end else begin
      done <= 1'b0;
      unique case (st)
        IDLE: begin
          busy <= 1'b0;
          if (start) begin
            op_q <= op; a_q <= a; b_q <= b; busy <= 1'b1;
            if (is_div) begin
              // capture magnitudes + sign + special cases
              div_zero <= (b == 32'd0);
              div_ovf  <= (op == MD_DIV) && (a == 32'h8000_0000) && (b == 32'hFFFF_FFFF);
              if (op == MD_DIV || op == MD_REM) begin
                neg_q    <= (a[31] ^ b[31]);
                neg_r    <= a[31];
                divr_mag <= absval(b);
              end else begin
                neg_q <= 1'b0; neg_r <= 1'b0;
                divr_mag <= b;
              end
              rq  <= {32'd0, (op==MD_DIV||op==MD_REM) ? absval(a) : a};
              cnt <= 6'd32;
              st  <= DIVRUN;
            end else begin
              st <= MUL1;
            end
          end
        end
        MUL1: begin pm1 <= prod; st <= MUL2; end   // multiply -> MREG
        MUL2: begin pm2 <= pm1;  st <= MUL3; end   // cascade  -> PREG
        MUL3: begin                                // select hi/lo word, retire
          result <= mul_res; done <= 1'b1; busy <= 1'b0; st <= IDLE;
        end
        DIVRUN: begin
          // one restoring step per cycle, fixed 32 iterations
          if (cnt != 6'd0) begin
            if (ge) rq <= {sub, rq[30:0], 1'b1};   // {rem-divr (32b), shifted dividend (31b), q-bit}
            else    rq <= {rq[62:0], 1'b0};
            cnt <= cnt - 6'd1;
          end else begin
            st <= FIN;   // rq holds {rem,quot}; FIN reads it directly (no quot/rem copy)
          end
        end
        FIN: begin
          result <= div_result; done <= 1'b1; busy <= 1'b0; st <= IDLE;
        end
        default: st <= IDLE;
      endcase
    end
  end
endmodule : rv_muldiv
