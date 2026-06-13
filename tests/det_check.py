#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# det_check.py — determinism acceptance gate (determinism contract / verification.md §6).
# The instruction stream is IDENTICAL across runs; only the DATA operands in
# memory differ (incl. div edge cases). Asserts byte-identical cycle counts.
# Any data-dependent timing (e.g. an early-terminating divider) fails this.
import os, sys, subprocess, re

ROOT  = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tests")
SIM   = os.path.join(ROOT, "sim", "obj_dir", "Vtb_top")
BUILD = os.path.join(ROOT, "sim", "build")
AS, LD, OC = "riscv64-unknown-elf-as", "riscv64-unknown-elf-ld", "riscv64-unknown-elf-objcopy"
MARCH = "rv32im_zba_zbb_zbs_zicsr"
os.makedirs(BUILD, exist_ok=True)

# Edge cases stress every operand-dependent-timing suspect: div-by-zero (b=0),
# INT_MIN/-1 overflow, all-zero (clz/ctz=32, cpop=0), all-ones (clz/ctz=0,
# cpop=32), and alternating bits (cpop=16, ctz=1).
DATASETS = [(6, 7), (0x7FFFFFFF, 3), (123, 0), (0x80000000, 0xFFFFFFFF),
            (-100 & 0xFFFFFFFF, 7), (1, 0xFFFFFFFF),
            (0x00000000, 0x00000001), (0xAAAAAAAA, 0x55555555)]

# Operands are LOADED from fixed addresses 0x4000/0x4004 -> instruction stream is
# constant; only the data image changes. Data-dependent timing would show here.
# Covers the usual variable-latency culprits across all variants: mul{,h,hsu,hu},
# div{,u}/rem{,u}, and the Zbb count ops clz/ctz/cpop (on BOTH operands), which
# would fail this gate if ever reimplemented with an early-terminating loop.
PROG = """
.include "test.h"
.section .text.start
.global _start
_start:
    li   s4, 0x4000
    lw   s0, 0(s4)
    lw   s1, 4(s4)
    mul    s2, s0, s1
    mulh   s3, s0, s1
    mulhsu t0, s0, s1
    mulhu  t1, s0, s1
    divu s4, s0, s1
    remu s5, s0, s1
    div  s6, s0, s1
    rem  s7, s0, s1
    clz  t2, s0
    ctz  t5, s0
    cpop t6, s0
    clz  a0, s1
    ctz  a1, s1
    cpop a2, s1
    add  s8, s2, s3
    xor  s9, s4, s5
    sh1add s10, s6, s7
    rev8 s11, s8
    li   t3, 0
    li   t4, 20
1:  addi t3, t3, 1
    blt  t3, t4, 1b
    TEST_PASS
.section .data
.org 0
.word 0
.word 0
"""

def run(cmd): return subprocess.run(cmd, capture_output=True, text=True)

def build_hex():
    src = os.path.join(BUILD, "detp.s")
    open(src, "w").write(PROG)
    o, elf, binf, hexf = (os.path.join(BUILD, "detp."+e) for e in ("o","elf","bin","hex"))
    assert run([AS,"-march="+MARCH,"-mabi=ilp32","-I",TESTS,src,"-o",o]).returncode==0
    assert run([LD,"-m","elf32lriscv","-T",os.path.join(TESTS,"link.ld"),o,"-o",elf]).returncode==0
    assert run([OC,"-O","binary",elf,binf]).returncode==0
    run([sys.executable, os.path.join(TESTS,"gen_hex.py"), binf, hexf])
    return hexf

def cycles_with(hexf, a, b):
    lines = open(hexf).read().splitlines()
    idx = 0x4000 >> 2
    while len(lines) <= idx + 1: lines.append("00000000")
    lines[idx]   = "%08x" % (a & 0xFFFFFFFF)   # 0x4000
    lines[idx+1] = "%08x" % (b & 0xFFFFFFFF)   # 0x4004
    patched = os.path.join(BUILD, "detp_patched.hex")
    open(patched, "w").write("\n".join(lines) + "\n")
    r = run([SIM, "+hex="+patched])
    m = re.search(r"CYCLES=(\d+)", r.stdout)
    assert m and "PASS" in r.stdout, f"run failed: {r.stdout}"
    return int(m.group(1))

def main():
    hexf = build_hex()
    results = [(d, cycles_with(hexf, *d)) for d in DATASETS]
    base = results[0][1]
    ok = all(c == base for _, c in results)
    for d, c in results:
        print(f"  operands=(0x{d[0]:08x},0x{d[1]:08x}) cycles={c} {'OK' if c==base else 'MISMATCH'}")
    if ok:
        print(f"\nDETERMINISM PASS — {len(results)} datasets all {base} cycles (data-independent)")
        return 0
    print("\nDETERMINISM FAIL — cycle count varies with data")
    return 1

if __name__ == "__main__":
    sys.exit(main())
