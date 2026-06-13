# LMB timing-contract negative tests

`make -C sim lmb-contract` proves the core's bus assumption is real and
load-bearing: it is a **single-outstanding LMB master that drives one rising-edge
address strobe per access and honours DReady** — working with level-ready,
edge-detect, or back-pressure registered slaves on both the instruction and data
buses (a deliberate consequence of the determinism prime directive — a
variable-latency memory would make WCET contention-dependent).

The test injects contract-violating slave behaviour via opt-in plusargs in
[`tb/models/lmb_bram.sv`](../../tb/models/lmb_bram.sv) and asserts the expected
outcome:

| Mode | Slave behaviour | Expected |
|---|---|---|
| (none) | registered 1-cycle, level-ready | PASS |
| `+dedge` (runtime) | edge-detect (start on the strobe's rising edge) | PASS |
| `+dwait=N` (runtime) | back-pressure (N-cycle fixed-latency registered) | PASS |
| `COMB_D=1` (compile-time, `make arch-sim-combd`) | combinational / zero-wait data | FAIL (loads corrupt) |

(`COMB` is a compile-time parameter, not a plusarg, because a combinational data
response forms a deliberate combinational loop on the fetch path — keeping it
compile-time leaves the normal/conformance/coverage builds loop-free.)

The gate passes when the fixed-latency registered slaves (level-ready, edge-detect,
back-pressure) all pass **and** the combinational/zero-wait slave fails — i.e. a
fixed-latency registered response is genuinely required, while a combinational one
corrupts execution. This is the negative test the golden rules refer to. See
[`docs/verification-status.md`](../../docs/verification-status.md) §4.

**Integration note:** the host SoC's LMB memory slave must present a fixed-latency
registered response (level-ready, edge-detect, or back-pressure — not
combinational); confirm at in-context integration.

Prereqs (WSL): `riscv64-unknown-elf-gcc`, verilator, riscv-tests at
`~/src/riscv-tests` (override `RVT=`).
