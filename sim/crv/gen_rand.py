#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# gen_rand.py <seed> [n_instr] — constrained-random RISC-V instruction generator (a
# focused ISG, in the spirit of riscv-dv but on the open toolchain). Emits a complete,
# deterministic, self-terminating RV32IM_zba_zbb_zbs_zicsr program whose instruction
# mix is biased HARD toward pipeline-hazard scenarios — back-to-back RAW dependencies
# (forwarding stress), load-to-use, store-then-load (the rc7 class), mul/div-to-use,
# and branches on freshly-computed operands. The run harness lock-steps each program
# against Spike, so any divergence is a real forwarding/hazard/bus bug. Catches the
# corner cases hand-written tests don't think to cover.
#
# Safety (so Spike == core, no faults): all loads/stores use a reserved base register
# (x3=gp) into a zeroed scratch region with masked-aligned offsets (aligned-only per
# the v1 carve-out); branches are forward-only and bounded (always terminates); x0/x3
# are never written by the body. No jal/jalr/ecall/fence/CSR-trap-state — the random
# datapath, not control-flow escapes.
import sys, random

seed   = int(sys.argv[1]) if len(sys.argv) > 1 else 1
N      = int(sys.argv[2]) if len(sys.argv) > 2 else 400
rng    = random.Random(seed)
SCRATCH = 4096                       # bytes of scratch data region
OFFMAX  = 2044                       # max load/store offset (12-bit signed imm; aligned word fits)

POOL = [r for r in range(1, 32) if r != 3]   # writable GPRs (x0=zero, x3=gp=base reserved)
last_dst = [POOL[0]]                          # most-recent destination (RAW-hazard bias)

def rd():  return rng.choice(POOL)
def rs():  return last_dst[0] if rng.random() < 0.5 else rng.choice(POOL + [0])  # bias to last dst
def shamt(): return rng.randint(0, 31)
def bit():   return rng.randint(0, 31)
def simm12(): return rng.randint(-2048, 2047)

RR  = ["add","sub","and","or","xor","sll","srl","sra","slt","sltu",
       "mul","mulh","mulhsu","mulhu","div","divu","rem","remu",
       "sh1add","sh2add","sh3add","andn","orn","xnor","min","max","minu","maxu","rol","ror",
       "bclr","bext","binv","bset"]
RI  = ["addi","andi","ori","xori","slti","sltiu"]
SHI = ["slli","srli","srai","rori","bclri","bexti","binvi","bseti"]
UN  = ["clz","ctz","cpop","sext.b","sext.h","zext.h","orc.b","rev8"]
LD  = [("lw",4),("lh",2),("lhu",2),("lb",1),("lbu",1)]
ST  = [("sw",4),("sh",2),("sb",1)]
BR  = ["beq","bne","blt","bge","bltu","bgeu"]
CSR = ["csrrw","csrrs","csrrc"]

out, lbl = [], [0]
def emit(s): out.append("    " + s)

def gen_rr():
    d = rd(); emit(f"{rng.choice(RR)} x{d}, x{rs()}, x{rs()}"); last_dst[0] = d
def gen_ri():
    d = rd(); emit(f"{rng.choice(RI)} x{d}, x{rs()}, {simm12()}"); last_dst[0] = d
def gen_shi():
    d = rd(); emit(f"{rng.choice(SHI)} x{d}, x{rs()}, {shamt()}"); last_dst[0] = d
def gen_un():
    d = rd(); emit(f"{rng.choice(UN)} x{d}, x{rs()}"); last_dst[0] = d
def gen_load(force_use=False):
    op, al = rng.choice(LD); off = rng.randint(0, OFFMAX) & ~(al - 1)
    d = rd(); emit(f"{op} x{d}, {off}(x3)"); last_dst[0] = d
    if force_use or rng.random() < 0.7:        # load-to-USE hazard
        emit(f"add x{rd()}, x{d}, x{rs()}");
def gen_store():
    op, al = rng.choice(ST); off = rng.randint(0, OFFMAX) & ~(al - 1)
    emit(f"{op} x{rs()}, {off}(x3)")
    if rng.random() < 0.6:                      # store-then-LOAD (rc7 class)
        op2, al2 = rng.choice(LD); off2 = rng.randint(0, OFFMAX) & ~(al2 - 1)
        d = rd(); emit(f"{op2} x{d}, {off2}(x3)"); last_dst[0] = d
def gen_muluse():
    d = rd(); emit(f"{rng.choice(['mul','mulh','div','divu','rem','remu'])} x{d}, x{rs()}, x{rs()}")
    emit(f"xor x{rd()}, x{d}, x{rs()}"); last_dst[0] = d   # mul/div result -> immediate use
def gen_branch():
    l = lbl[0]; lbl[0] += 1
    emit(f"{rng.choice(BR)} x{rs()}, x{rs()}, .Lb{l}")     # operands biased to last dst
    for _ in range(rng.randint(1, 2)):
        rng.choice([gen_rr, gen_ri, gen_shi])()
    out.append(f".Lb{l}:")
def gen_csr():
    d = rd(); emit(f"{rng.choice(CSR)} x{d}, mscratch, x{rs()}"); last_dst[0] = d

# gen_csr is IN the default mix. It originally surfaced a real core-vs-Spike divergence
# on `mscratch` under back-to-back CSR read-modify-write in long programs — a CSR write
# that committed while the instruction was frozen in EX by a dmem_stall, so the rd
# read-back captured the NEW value (the stall-coincident CSR-RMW bug; the simple forward
# case always passed — tests/csr_hazard.s). FIXED in rv_core.sv by gating csr_we with
# ~dmem_stall (regression: tests/csr_dmem_hazard.s); CRV is now clean WITH CSR included.
# Set CRV_CSR=0 to drop CSR ops from the mix.
import os
GENS = ([gen_rr]*10 + [gen_ri]*5 + [gen_shi]*4 + [gen_un]*3 +
        [gen_load]*6 + [gen_store]*5 + [gen_muluse]*4 + [gen_branch]*3)
if os.environ.get("CRV_CSR") != "0":
    GENS += [gen_csr]*2

# ---- prologue: base + zeroed scratch + defined GPR seeds ----
print(".section .text.init\n.global _start\n_start:")
print("    la   x3, _scratch")                 # x3 = scratch base (reserved)
print("    mv   x5, x3")
print("    li   x6, %d" % SCRATCH)
print("    add  x6, x3, x6")
print(".Lzero:\n    sw zero, 0(x5)\n    addi x5, x5, 4\n    bltu x5, x6, .Lzero")
for r in POOL:                                  # defined starting values (vary by reg+seed)
    print(f"    li   x{r}, {((r*2654435761 + seed*40503) & 0xffffffff) - (1<<31)}")
# ---- random body ----
while len(out) < N:
    rng.choice(GENS)()
for line in out:
    print(line)
# ---- epilogue: HTIF tohost exit ----
print("    li   x5, 0\n    la   x6, tohost\n    li   x7, 1\n    sw   x7, 0(x6)")
print(".Lhalt:\n    j .Lhalt")
print(".section .tohost, \"aw\", @progbits\n.align 6\n.global tohost\ntohost: .dword 0")
print(".global fromhost\nfromhost: .dword 0")
print(".section .bss\n.align 6\n_scratch: .zero %d" % SCRATCH)
