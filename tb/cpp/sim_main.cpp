// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 John Goodacre
// sim_main.cpp — Verilator C++ driver for tb_top.
// Drives clk/reset, optionally pulses IRQ at +irq_at / clears at +irq_clr, runs until a
// tohost store or timeout. Exit 0 = PASS (tohost==1), nonzero = FAIL.
#include "Vtb_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtb_top* dut = new Vtb_top;

    long max_cycles = 200000;
    long irq_at = -1, irq_clr = -1;
    for (int i = 1; i < argc; i++) {
        if (!strncmp(argv[i], "+max=", 5))     max_cycles = atol(argv[i] + 5);
        if (!strncmp(argv[i], "+irq_at=", 8))  irq_at   = atol(argv[i] + 8);
        if (!strncmp(argv[i], "+irq_clr=", 9)) irq_clr  = atol(argv[i] + 9);
    }

    // reset
    dut->clk = 0; dut->rst_n = 0; dut->irq = 0;
    for (int i = 0; i < 6; i++) { dut->clk = !dut->clk; dut->eval(); }
    dut->rst_n = 1;

    int rc = 2;
    for (long cyc = 0; cyc < max_cycles; cyc++) {
        if (irq_at  >= 0 && cyc == irq_at)  dut->irq = 1;
        if (irq_clr >= 0 && cyc == irq_clr) dut->irq = 0;
        // rising edge
        dut->clk = 1; dut->eval();
        if (dut->tohost_we) {
            unsigned v = dut->tohost;
            printf("CYCLES=%ld\n", cyc);
            if (v == 1) { printf("PASS\n"); rc = 0; }
            else        { printf("FAIL code=0x%x (test #%u)\n", v, v >> 1); rc = 1; }
            break;
        }
        // falling edge
        dut->clk = 0; dut->eval();
    }
    if (rc == 2) printf("TIMEOUT after %ld cycles\n", max_cycles);
#if VM_COVERAGE
    {
        const char* cf = "coverage.dat";
        for (int i = 1; i < argc; i++)
            if (!strncmp(argv[i], "+covfile=", 9)) cf = argv[i] + 9;
        Verilated::threadContextp()->coveragep()->write(cf);
    }
#endif
    dut->final();
    delete dut;
    return rc;
}
