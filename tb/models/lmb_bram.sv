// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// lmb_bram.sv — registered (BRAM-style 1-cycle) LMB slave model for the unit TB.
// Honours byte-enables (the host LMB slave must honour d_be for sub-word stores).
// Response is REGISTERED: ready+data the cycle AFTER the strobe. A combinational
// model would deliver read data a cycle early and corrupt execution (negative test).
//
// Response modes (default = registered 1-cycle, unchanged):
//   +iwait=N / +dwait=N : runtime plusarg — insert N extra wait cycles (slow
//                         registered slave with back-pressure). Role = "i" for
//                         fetch, "d" for DUMP/data.
//   COMB parameter      : combinational/zero-wait response (NEGATIVE test — this
//                         violates the registered-1-cycle contract and must
//                         corrupt execution). Compile-time (it loops the fetch
//                         path). See sim/lmb-contract/.
//
// DUMP=1 instances (the data memory) can emit a RISCOF signature on `halt`:
// with +sig=<file> +sigbegin=<hex> +sigend=<hex>, the byte range [begin,end)
// is written as one little-endian 32-bit word per line (8 hex digits) — the
// exact format Spike produces with +signature-granularity=4. See sim/riscof/.
module lmb_bram #(
    parameter int          AW       = 16,           // address width (bytes) -> 2^AW byte memory
    parameter bit          LOAD     = 1'b0,          // load image from +hex=<file> at time 0
    parameter bit          DUMP     = 1'b0,          // dump signature on `halt` (data memory only)
    parameter logic [31:0] MEM_BASE = 32'h0000_0000, // window base; index = (addr-MEM_BASE)>>2
    parameter bit          COMB     = 1'b0           // NEGATIVE test: combinational/zero-wait
) (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic        re,
    input  logic        we,
    input  logic [3:0]  be,
    input  logic [31:0] wdata,
    output logic [31:0] rdata,
    output logic        ready,
    input  logic        halt   // 1-cycle: end-of-test, trigger signature dump
);
  localparam int DEPTH = (1 << (AW-2));
  logic [31:0] mem [0:DEPTH-1];

  wire [31:0]   off = addr - MEM_BASE;
  wire [AW-3:0] idx = off[AW-1:2];

  // ---- response-mode config ----
  // Wait-state injection is a runtime plusarg (+iwait/+dwait); the combinational
  // mode is the compile-time COMB parameter (it forms a deliberate combinational
  // loop on the fetch path, so keeping it compile-time leaves all normal builds
  // loop-free / UNOPTFLAT-clean — only a dedicated COMB build has it).
  int unsigned waits;
  // edge_mode: a representative host tile slave starts an access on the
  // RISING EDGE of the strobe (rd_start = re & ~re_q) and HOLDS ready while the
  // request stays asserted. A strobe held high across back-to-back accesses edges
  // ONCE, so a core that holds its strobe re-reads the first access's data. This
  // mode reproduces that faithfully so the lmb-contract regression covers it.
  bit edge_mode;
  // free_mode (+dfree): the CANONICAL Xilinx BRAM Port A read — `data_rd_q <=
  // mem[addr]` registered EVERY cycle, so the read data tracks the CURRENT address,
  // not the strobe (this is exactly tile.sv's `data_rd_q <= data_mem[data_idx]`).
  // It is contract-compliant (registered 1-cycle) but, unlike the capture-and-hold
  // models, does NOT hold a load's word past the next access — so a core that
  // commits a load by sampling the live bus a cycle late reads the wrong word (the
  // P7.1 store->load stale read). Ready is the edge-held form (tile.sv d_ready).
  bit free_mode;
  // drand_mode (+drand=<seed>): the SCOREBOARD slave. Per access it independently
  // rolls a COMPLIANT registered response — random extra wait latency (0..3) and
  // random read-data style {free-running | capture-and-hold} — all contract-legal
  // (registered, data valid no earlier than the cycle ready asserts, single-
  // outstanding honoured by the core). The architectural result MUST be invariant to
  // this timing, so the scoreboard harness lock-steps it vs Spike across many seeds;
  // a divergence is a real bus-capture/ordering bug. Seeded (deterministic per seed).
  bit          drand_mode;
  bit          cur_free;                     // standing data-delivery mode (free-running vs latched)
  int unsigned rng_state;
  function automatic int unsigned rng_next();
    rng_state = rng_state * 32'd1103515245 + 32'd12345;
    return rng_state;
  endfunction
  initial begin
    waits = 0;
    edge_mode = 1'b0;
    free_mode = 1'b0;
    drand_mode = 1'b0;
    rng_state = 32'd1;
    if (DUMP) begin
      void'($value$plusargs("dwait=%d", waits));
      void'($value$plusargs("dedge=%d", edge_mode));
      void'($value$plusargs("dfree=%d", free_mode));
      if ($value$plusargs("drand=%d", rng_state)) drand_mode = 1'b1;
    end else begin
      void'($value$plusargs("iwait=%d", waits));
    end
  end

  initial begin
    if (LOAD) begin
      string f;
      if ($value$plusargs("hex=%s", f)) $readmemh(f, mem);
    end
  end

  // registered response (+ optional N-cycle back-pressure; single-outstanding)
  logic        ready_r;
  logic [31:0] rdata_r;
  logic        busy = 1'b0;
  logic [AW-3:0] lat_idx;
  logic        lat_re, lat_we;
  logic [3:0]  lat_be;
  logic [31:0] lat_wd;
  logic [7:0]  cnt;
  logic        re_q, we_q;                  // edge-detect history (edge_mode)
  wire         rd_start = re & ~re_q;
  wire         wr_start = we & ~we_q;

  task automatic do_write(input logic [AW-3:0] wi, input logic [3:0] m, input logic [31:0] d);
    if (m[0]) mem[wi][7:0]   <= d[7:0];
    if (m[1]) mem[wi][15:8]  <= d[15:8];
    if (m[2]) mem[wi][23:16] <= d[23:16];
    if (m[3]) mem[wi][31:24] <= d[31:24];
  endtask

  always_ff @(posedge clk) begin
    re_q <= re; we_q <= we;
    if (drand_mode) begin
      // SCOREBOARD: the adversarial compliant slave — the CANONICAL free-running read
      // (`rdata_r <= mem[idx]` UNCONDITIONALLY every cycle, the bug-exposing data
      // path, like +dfree) with a RANDOM per-access ack latency (1..4 cycles). The
      // core holds the address until ack (single-outstanding), so this is fully
      // contract-legal; the architectural result must be invariant to the random
      // latency, so the harness lock-steps it vs Spike across a seed sweep. Includes
      // the tight latency-1 free-running case where the store→load class lives.
      // Per access, randomly pick a COMPLIANT behaviour: free-running 1-cycle (==
      // +dfree — the read tracks the address; exposes the store→load class) OR
      // latched with 1..6 wait states (== +dwait — the strobe-cycle address is
      // latched, the canonical multi-cycle slave). Both are contract-legal; the
      // architectural result must be invariant. A free-running slave is only legal at
      // 1-cycle latency (the core presents the address for ONE cycle then advances),
      // so the latency lives on the LATCHED variant — that is the key compliance rule
      // my first cut got wrong.
      if (cur_free) rdata_r <= mem[idx];                 // standing free-running (free-mode accesses + their WB-hold)
      if (!busy) begin
        ready_r <= 1'b0;
        if (re | we) begin
          automatic logic [2:0] r = (rng_next() >> 16) & 3'h7;   // 0..7
          lat_idx <= idx; lat_re <= re; lat_we <= we; lat_be <= be; lat_wd <= wdata;
          if (r < 3'd2) begin                            // ~25%: free-running 1-cycle (== +dfree)
            cur_free <= 1'b1;
            ready_r  <= 1'b1;
            rdata_r  <= mem[idx];
            if (we) do_write(idx, be, wdata);
          end else begin                                 // latched, (r-2) extra waits (0..5)
            cur_free <= 1'b0;
            busy <= 1'b1; cnt <= {5'd0, (r - 3'd2)};
          end
        end
      end else begin
        if (cnt != 0) begin
          cnt <= cnt - 8'd1; ready_r <= 1'b0;
        end else begin
          busy <= 1'b0; ready_r <= 1'b1;
          if (lat_re) rdata_r <= mem[lat_idx];           // LATCH the strobe-cycle word (compliant multi-cycle)
          if (lat_we) do_write(lat_idx, lat_be, lat_wd);
        end
      end
    end else if (free_mode) begin
      // canonical BRAM Port A: FREE-RUNNING registered read (tracks the current
      // address every cycle) + edge-held ready. The read data is NOT held to the
      // strobe, so it exposes a late load-data capture in the core.
      rdata_r <= mem[idx];
      if (rd_start | wr_start) ready_r <= 1'b1;
      else if (!re && !we)     ready_r <= 1'b0;
      if (wr_start) do_write(idx, be, wdata);
    end else if (edge_mode) begin
      // tile-faithful: rising-edge access detect + ready held while request asserted
      // (rtl/tile.sv d_ready/rd_start). The read data registers on the rising edge,
      // so a strobe held across back-to-back accesses re-reads the first word.
      if (rd_start | wr_start) ready_r <= 1'b1;
      else if (!re && !we)     ready_r <= 1'b0;
      if (rd_start) rdata_r <= mem[idx];
      if (wr_start) do_write(idx, be, wdata);
    end else begin
    ready_r <= 1'b0;
    if (waits == 0) begin
      ready_r <= re | we;
      if (re) rdata_r <= mem[idx];
      if (we) do_write(idx, be, wdata);
    end else begin
      if (!busy) begin
        if (re | we) begin
          busy <= 1'b1; cnt <= waits[7:0];
          lat_idx <= idx; lat_re <= re; lat_we <= we; lat_be <= be; lat_wd <= wdata;
        end
      end else if (cnt != 0) begin
        cnt <= cnt - 8'd1;
      end else begin
        busy <= 1'b0; ready_r <= 1'b1;
        if (lat_re) rdata_r <= mem[lat_idx];
        if (lat_we) do_write(lat_idx, lat_be, lat_wd);
      end
    end
    end
  end

  // combinational (NEGATIVE-test) override vs registered response. COMB is a
  // compile-time parameter, so for the default COMB=0 this folds to the
  // registered path (no combinational loop).
  assign ready = COMB ? (re | we) : ready_r;
  assign rdata = COMB ? mem[idx]  : rdata_r;

  // ---- RISCOF signature dump (DUMP instances only) ----
  if (DUMP) begin : g_sig
    string         sigfile;
    logic [31:0]   sig_b, sig_e;
    logic          have_sig, dumped;
    integer        fd;
    logic [31:0]   a, di;
    initial begin
      have_sig = $value$plusargs("sig=%s", sigfile)
               & $value$plusargs("sigbegin=%h", sig_b)
               & $value$plusargs("sigend=%h", sig_e);
      dumped = 1'b0;
    end
    always_ff @(posedge clk) begin
      if (halt & have_sig & ~dumped) begin
        dumped <= 1'b1;
        fd = $fopen(sigfile, "w");
        for (a = sig_b; a < sig_e; a = a + 32'd4) begin
          di = (a - MEM_BASE) >> 2;
          $fdisplay(fd, "%08x", mem[di[AW-3:0]]);
        end
        $fclose(fd);
      end
    end
  end
endmodule : lmb_bram
