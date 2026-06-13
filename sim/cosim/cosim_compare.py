#!/usr/bin/env python3
# cosim_compare.py <dut.trc> <spike.log> [entry_hex]
# Lock-step compare of the architectural GPR-write stream: our core's retire
# trace vs Spike's `-l --log-commits` output. Both reduce to a sequence of
# (pc, rd, val) for committed writes to x1..x31; Spike's boot ROM (pc < entry)
# is skipped. Exits 0 on identical sequences, 1 on the first divergence.
import sys, re

ENTRY = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x80000000
M32 = 0xFFFFFFFF

def load_dut(path):
    out = []
    for ln in open(path):
        p = ln.split()
        if len(p) != 3:
            continue
        pc, rd, val = int(p[0], 16), int(p[1]), int(p[2], 16) & M32
        if rd != 0 and pc >= ENTRY:
            out.append((pc, rd, val))
    return out

# core N: <priv> 0x<pc> (0x<insn>) x<rd> 0x<val>  [mem ...]
SPIKE = re.compile(r'core\s+\d+:\s+\d+\s+0x([0-9a-fA-F]+)\s+\(0x[0-9a-fA-F]+\)\s+x\s*(\d+)\s+0x([0-9a-fA-F]+)')

def load_spike(path):
    out = []
    for ln in open(path):
        m = SPIKE.search(ln)
        if not m:
            continue
        pc, rd, val = int(m.group(1), 16), int(m.group(2)), int(m.group(3), 16) & M32
        if rd != 0 and pc >= ENTRY:
            out.append((pc, rd, val))
    return out

def main():
    dut, ref = load_dut(sys.argv[1]), load_spike(sys.argv[2])
    n = min(len(dut), len(ref))
    for i in range(n):
        if dut[i] != ref[i]:
            lo = max(0, i - 3)
            print(f"  DIVERGE at retire #{i}:")
            for j in range(lo, min(n, i + 2)):
                mark = ">>" if j == i else "  "
                d, r = dut[j], ref[j]
                print(f"   {mark} dut pc={d[0]:08x} x{d[1]}={d[2]:08x}   spike pc={r[0]:08x} x{r[1]}={r[2]:08x}")
            return 1
    if len(dut) != len(ref):
        print(f"  LENGTH MISMATCH: dut={len(dut)} writes, spike={len(ref)} writes (matched first {n})")
        return 1
    print(f"  OK: {len(dut)} GPR-write retires identical")
    return 0

if __name__ == "__main__":
    sys.exit(main())
