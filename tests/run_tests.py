#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# run_tests.py [glob...] — assemble each test, run the Verilator sim, report PASS/FAIL.
# Per-test sim options: a line "# SIM: <plusargs>" in the .s is forwarded to the sim.
import sys, os, glob, subprocess, re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TESTS = os.path.join(ROOT, "tests")
SIM   = os.path.join(ROOT, "sim", "obj_dir", "Vtb_top")
BUILD = os.path.join(ROOT, "sim", "build")
AS    = "riscv64-unknown-elf-as"
LD    = "riscv64-unknown-elf-ld"
OC    = "riscv64-unknown-elf-objcopy"
MARCH = "rv32im_zba_zbb_zbs_zicsr"

os.makedirs(BUILD, exist_ok=True)

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

def build_and_run(src, build_only=False):
    name = os.path.splitext(os.path.basename(src))[0]
    o    = os.path.join(BUILD, name + ".o")
    elf  = os.path.join(BUILD, name + ".elf")
    binf = os.path.join(BUILD, name + ".bin")
    hexf = os.path.join(BUILD, name + ".hex")
    r = run([AS, "-march="+MARCH, "-mabi=ilp32", "-I", TESTS, src, "-o", o])
    if r.returncode: return ("ASM-ERR", r.stderr.strip())
    r = run([LD, "-m", "elf32lriscv", "-T", os.path.join(TESTS, "link.ld"), o, "-o", elf])
    if r.returncode: return ("LD-ERR", r.stderr.strip())
    r = run([OC, "-O", "binary", elf, binf])
    if r.returncode: return ("OC-ERR", r.stderr.strip())
    run([sys.executable, os.path.join(TESTS, "gen_hex.py"), binf, hexf])
    # --build-only stops here (just emits sim/build/<name>.hex). Used by the
    # Vivado-xsim gate (sim/xsim/run_xsim.ps1), which assembles via this WSL
    # toolchain then runs the same hex under xsim — no Verilator binary needed.
    if build_only:
        return ("BUILT", os.path.relpath(hexf, ROOT))
    sim_opts = []
    for line in open(src):
        m = re.search(r"#\s*SIM:\s*(.*)", line)
        if m: sim_opts = m.group(1).split()
    r = run([SIM, "+hex="+hexf] + sim_opts)
    out = r.stdout.strip()
    return ("PASS" if r.returncode == 0 else "FAIL", out)

def main():
    args = sys.argv[1:]
    build_only = "--build-only" in args
    pats = [a for a in args if a != "--build-only"] or [os.path.join(TESTS, "*.s")]
    files = []
    for p in pats:
        files += sorted(glob.glob(p if os.path.isabs(p) else os.path.join(ROOT, p)))
    files = [f for f in files if f.endswith(".s")]
    if not files:
        print("no tests found"); return 1
    npass = 0
    for f in files:
        status, msg = build_and_run(f, build_only)
        ok = status in ("PASS", "BUILT")
        npass += ok
        print(f"[{status:5s}] {os.path.basename(f):28s} {msg}")
    print(f"\n{npass}/{len(files)} {'built' if build_only else 'passed'}")
    return 0 if npass == len(files) else 1

if __name__ == "__main__":
    sys.exit(main())
