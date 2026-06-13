# Embench-IoT — cycle-exact, on the custom core, at the 24/16 KiB end-target

`make -C sim embench` (WSL) runs the **Embench-IoT** suite (17 realistic embedded
kernels — crypto, compression, regex, JPEG, sort, state-machines, DSP) on the core
under Verilator and reports, per kernel, **exact cycles, IPC, code/data footprint,
and the Embench relative speed score**. It answers two questions at once:

1. **Does the core run realistic MCU-class kernels, and do they fit 24 KiB I / 16 KiB D?**
2. **How fast is it** on a real embedded workload (vs the Embench Arm Cortex-M4 reference)?

This complements [`../coremark`](../coremark): CoreMark is one throughput number;
Embench is a spread of realistic kernels and a footprint-fit check.

## Result (default config, `-O2`, gcc 15.2)

The **default core config (2-cycle load-use, `P_LOADUSE=2`)** scores
**Embench speed score = 0.851** (geomean, ref Arm Cortex-M4 = 1.00, frequency-independent),
and **all 17 kernels fit the 24/16 budget** — the largest (`wikisort`) at 24.3 KiB
`.text`, right at the 24 KiB edge. The `score (perf)` column is the optional `CORE_PERF`
build (1-cycle load-use, the relaxed-clock / banked-aperture option): **0.874** geomean, +3 %.

| kernel | cycles | IPC | `.text` | data+bss | score | score (perf) | fit 24/16 |
|---|---:|---:|---:|---:|---:|---:|:--:|
| aha-mont64 | 6,001,200 | 0.77 | 4,312 | 148 | 0.667 | 0.667 | ok |
| crc32 | 5,921,676 | 0.59 | 2,929 | 128 | 0.676 | 0.676 | ok |
| edn | 7,498,757 | 0.43 | 5,301 | 1,736 | 0.534 | 0.535 | ok |
| huffbench | 3,930,018 | 0.59 | 4,001 | 8,832 | 1.016 | 1.071 | ok |
| matmult-int | 6,729,275 | 0.48 | 3,985 | 8,132 | 0.596 | 0.596 | ok |
| md5sum | 3,889,116 | 0.73 | 3,033 | 3,224 | 1.011 | 1.011 | ok |
| nettle-aes | 4,570,476 | 0.77 | 15,269 | 1,668 | 0.866 | 0.867 | ok |
| nettle-sha256 | 4,438,173 | 0.82 | 6,957 | 244 | 0.901 | 0.912 | ok |
| nsichneu | 5,510,785 | 0.41 | 18,709 | 192 | 0.781 | 0.907 | ok |
| picojpeg | 4,361,634 | 0.63 | 15,761 | 2,544 | 0.898 | 0.930 | ok |
| qrduino | 4,272,848 | 0.65 | 14,505 | 8,360 | 0.919 | 0.952 | ok |
| sglib-combined | 4,594,574 | 0.54 | 12,653 | 8,800 | 0.899 | 0.971 | ok |
| slre | 4,305,521 | 0.61 | 5,673 | 192 | 0.928 | 0.970 | ok |
| statemate | 4,718,670 | 0.49 | 6,113 | 376 | 1.361 | 1.381 | ok |
| tarfind | 4,286,954 | 0.53 | 2,181 | 9,120 | 0.934 | 0.936 | ok |
| ud | 5,795,958 | 0.44 | 2,781 | 1,888 | 0.679 | 0.684 | ok |
| wikisort | 3,012,486 | 0.55 | 24,296 | 3,324 | 1.202 | 1.225 | ok |
| **geomean** | | | | | **0.851** | **0.874** | **17/17 fit** |

Footprint budget: `.text` ≤ 24 KiB, data+bss ≤ 16 KiB. Max `.text` = wikisort 24,296 B
(98.9 %); max data+bss = tarfind 9,120 B (56 %). **No kernel overflows either budget.**
The single-outstanding LMB (one rising-edge strobe per access; consecutive loads/stores
take a 1-cycle gap — `microarchitecture.md` §9) costs most on the table-lookup / pointer
kernels (nettle-aes, edn, matmult, ud). The `CORE_PERF` gain (+3 %) concentrates on the
load-bound kernels — nsichneu 0.78→0.91, sglib 0.90→0.97, slre 0.93→0.97 — while
pure-compute kernels (crc32, matmult, md5sum) are identical. `cycles`/`IPC` shown are the
default config; build the perf column with `DEFS=+define+CORE_PERF TAG=emb_perf`.

## Why cycle-*exact*

Same argument as CoreMark: no caches, no speculation, no branch prediction, and
deterministic registered single-outstanding memory modelled exactly as the hardware contract,
so **Verilator cycles == silicon cycles, bit-for-bit.** Each kernel is timed by
reading `mcycle`/`minstret` in `start_trigger`/`stop_trigger` (leaf, non-inlined, in
`crt0.S`) straddling Embench's `benchmark()`; correctness is Embench's own
`verify_benchmark` (every kernel reports PASS).

## The score (and why it's frequency-independent)

Embench's convention is to build each kernel at `GLOBAL_SCALE_FACTOR = cpu_mhz` (so
it runs ~4 s on the target) and report `rel = baseline_ms / measured_ms` — geomean
over the suite, **reference Arm Cortex-M4 = 1.00**. Build at `gsf = cpu_mhz` and the
frequency *cancels*: `rel = baseline×1000 / (work×CPI)`, a pure IPC-vs-reference
metric. We build at `gsf = 1` (cheap to simulate) and compute the algebraically
identical `score = baseline×1000 / cycles` — **verified**: building crc32 at
`gsf = 250` and running at 250 MHz gives `rel = 0.677`, matching `baseline×1000/cycles`
here. So the score needs no frequency assumption; **0.851 means ~0.851× a Cortex-M4's
per-cycle throughput, geomean**, at any clock.

## Reading the number (honest context)

0.851 (just under the Cortex-M4 reference) is the expected determinism-first result,
and the per-kernel spread shows exactly why:

- **Branch-, load-, and table-lookup-bound kernels score low** — edn 0.53, matmult
  0.60, ud 0.68, crc32 0.68, nsichneu 0.78, nettle-aes 0.87 — with IPC 0.43–0.59. No
  branch prediction + decoupled-fetch refetch (`P_REDIR`) costs ~3 cycles per taken
  branch; the default 2-cycle load-use bites the pointer-chasers (nsichneu most); and
  the single-outstanding one-strobe-per-access LMB adds a 1-cycle gap to back-to-back
  accesses (the AES sbox-lookup and matmult inner loops feel this).
- **Compute-dense kernels score at/above the reference** — statemate 1.36, wikisort
  1.20, huffbench 1.02, md5sum 1.01 — where the M/Zb* units and a clean 1-cycle-BRAM
  datapath pay off (IPC up to 0.82).

The headline is the **default config (2-cycle load-use)**. The optional `CORE_PERF`
build (1-cycle load-use, for relaxed-clock / banked-aperture deployments — see
[`../coremark`](../coremark/README.md#performance-build-option-core_perf)) lifts the
geomean to 0.874, on the load-bound kernels. Cross-microarchitecture caveat:
Embench is **strongly compiler-sensitive** — always cite the toolchain + flags (here
gcc 15.2 `-O2`).

## Toolchain

Built with the xPack **`riscv-none-elf-gcc 15.2`** (it ships newlib headers, which
the kernels' `<stdlib.h>`/`<string.h>`/`<ctype.h>` need; the apt bare-metal gcc the
verification gates use has none). The gates are **untouched** — this is a separate
toolchain. Override with `CM_PREFIX=`/`CM_BIN=` (see `run_embench.sh`).

## How it works (no new RTL/SV)

Reuses `tb_top` + the RISCOF `+sig` dump. Files here: `crt0.S` (startup +
`mcycle`/`minstret` triggers + signature), `link.ld` (flat, like CoreMark),
`boardsupport.{c,h}` (`GLOBAL_SCALE_FACTOR=1`, no cache-warm), `emb_libc.c`
(strchr/strncmp/memchr/`__errno` beyond the CoreMark `libc.c`), and `run_embench.sh`
(builds a default-config 512 KiB sim, compiles each kernel with Embench `support/` +
`beebsc.c`, runs, scores, and checks each footprint against 24/16). Embench source is
cloned to `~/src/embench-iot` (override `EMB=`). Knobs: `OPT=-O3 BENCH="crc32 edn"
make -C sim embench`. The 512 KiB sim memory is for simulation convenience; the
**24/16 fit is validated from each ELF's section sizes**, not the sim size.
