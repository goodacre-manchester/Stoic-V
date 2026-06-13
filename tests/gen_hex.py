#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
# gen_hex.py <in.bin> <out.hex> — convert a flat binary to 32-bit little-endian
# word-per-line hex for $readmemh (mem[i] = word i, i = byte_addr/4).
import sys
data = open(sys.argv[1], "rb").read()
if len(data) % 4:
    data += b"\x00" * (4 - len(data) % 4)
with open(sys.argv[2], "w") as f:
    for i in range(0, len(data), 4):
        w = data[i] | (data[i+1] << 8) | (data[i+2] << 16) | (data[i+3] << 24)
        f.write("%08x\n" % w)
