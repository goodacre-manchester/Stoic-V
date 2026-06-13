// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// tb_xsim.sv — Vivado xsim driver for the directed unit suite.
//
// This is the SystemVerilog analogue of tb/cpp/sim_main.cpp: it generates the
// clock, holds reset, pulses IRQ at +irq_at / clears at +irq_clr, and runs the
// `tb_top` unit testbench until a tohost store (value 1 = PASS, odd>1 = FAIL) or
// a +max cycle timeout — printing the SAME stdout markers (CYCLES=, PASS, FAIL,
// TIMEOUT) so the PowerShell runner can score xsim runs identically to Verilator.
//
// WHY THIS EXISTS: every functional gate otherwise runs only on Verilator. The
// two integrator-reported defects (the LMB back-to-back stale read and the
// continuous-assign forwarding-sensitivity gap) lived in the *semantic delta*
// between Verilator and Vivado xsim (the simulator the host SoC actually uses).
// Verilator computed the correct answer regardless of stimulus, so no Verilator
// test vector could catch the forwarding bug — only running the SAME programs
// under xsim does. This wrapper makes that a repeatable local gate. See
// sim/xsim/run_xsim.ps1 and docs/verification.md.
//
// The DUT modules read their own plusargs via $value$plusargs (+hex= in
// lmb_bram, +tohost=/+trace= in tb_top, +dwait=/+dedge=/+iwait= in lmb_bram), so
// this wrapper only owns clk/reset/irq/timeout — exactly sim_main.cpp's split.
//
// No `timescale directive here: the core RTL carries none, so the time unit is
// set uniformly via `xelab --timescale 1ns/1ps` (see run_xsim.ps1). Keeping the
// source timescale-neutral avoids any mixed-timescale elaboration conflict.
module tb_xsim;

  logic        clk = 1'b0;
  logic        rst_n = 1'b0;
  logic        irq = 1'b0;
  logic [31:0] tohost;
  logic        tohost_we;

  // ---- plusargs (mirror sim_main.cpp) ----
  longint unsigned max_cycles;
  longint          irq_at, irq_clr;
  initial begin
    if (!$value$plusargs("max=%d", max_cycles)) max_cycles = 200000;
    if (!$value$plusargs("irq_at=%d", irq_at))  irq_at  = -1;
    if (!$value$plusargs("irq_clr=%d", irq_clr)) irq_clr = -1;
  end

  // ---- DUT: the same unit testbench Verilator builds ----
  tb_top u_tb (
    .clk(clk), .rst_n(rst_n), .irq(irq),
    .tohost(tohost), .tohost_we(tohost_we)
  );

  // ---- 100 MHz clock (period only affects #-delays, not cycle counts) ----
  always #5 clk = ~clk;

  // ---- reset: hold low ≥1 clock, release on a falling edge so it is stable
  //      high before the next rising edge (behaviour-identical to sim_main's
  //      "rst_n=0 for a few half-toggles, then rst_n=1"; reset is held ≥1 clk
  //      everywhere so the sync-reset core is unaffected by the exact length) ----
  initial begin
    rst_n = 1'b0;
    repeat (8) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
  end

  // ---- drive irq + timeout + pass/fail detect, counting cycles from reset
  //      release. Ordering matches sim_main.cpp: set irq for this cycle, take the
  //      rising edge, then sample the registered tohost outputs. ----
  longint unsigned cyc;
  initial begin
    irq = 1'b0;
    @(posedge rst_n);
    for (cyc = 0; cyc < max_cycles; cyc++) begin
      if (irq_at  >= 0 && cyc == irq_at)  irq = 1'b1;
      if (irq_clr >= 0 && cyc == irq_clr) irq = 1'b0;
      @(posedge clk);
      #1;  // let posedge-registered tohost/tohost_we settle before sampling
      if (tohost_we) begin
        $display("CYCLES=%0d", cyc);
        if (tohost == 32'd1) $display("PASS");
        else                 $display("FAIL code=0x%0x (test #%0d)", tohost, tohost >> 1);
        $finish;
      end
    end
    $display("TIMEOUT after %0d cycles", max_cycles);
    $finish;
  end

endmodule : tb_xsim
