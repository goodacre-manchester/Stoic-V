# Stoic-V

[![CI](https://github.com/goodacre-manchester/Stoic-V/actions/workflows/ci.yml/badge.svg)](https://github.com/goodacre-manchester/Stoic-V/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
![ISA](https://img.shields.io/badge/ISA-rv32im__zba__zbb__zbs__zicsr-informational)

**Stoic-V** is a custom **RV32 RISC-V core in SystemVerilog** — *unmoved by its
data*: no caches, no speculation, no branch prediction, no early-terminating
mul/div, so every instruction's timing is fixed and **worst-case execution time
is statically analysable** (hard determinism). It is a *drop-in replacement* for
the AMD MicroBlaze-V soft core in a host SoC.

It targets `rv32im_zba_zbb_zbs_zicsr`, Machine mode only, no MMU. It presents the
**MicroBlaze-V-compatible LMB v10** master interface — the synth top is `module
mbv` with the exact MicroBlaze-V port signature — so a host SoC that instantiates
a MicroBlaze-V can bind Stoic-V in its place **unchanged**.

## Status

**A complete, verified, deterministic RV32 core.** The `rv32im_zba_zbb_zbs_zicsr`
M-mode core (`rtl/core/`, synth top `mbv.sv`) is **green on every gate below**. Full
evidence and methodology: [`docs/verification-status.md`](docs/verification-status.md).

### Verification

| Check | Command | Result |
|---|---|---|
| Verilator lint | `make lint` | clean |
| Directed self-checking tests | `make test` | **21 / 21** |
| Determinism — cycle-exact regression | `make determinism` | **8 datasets × 286 cycles** (data-independent) |
| Architectural conformance vs Spike — I / M / Zba/Zbb/Zbs | `make archtest` (RISCOF) | **75 / 75** |
| Berkeley ISA tests — rv32ui + rv32um | `make riscv-tests` | **48 / 48** |
| Spike lock-step — per-retire GPR compare | `make cosim` | **48 / 48** |
| System-level lock-step — compiled-C firmware vs Spike on the free-running BRAM | `make cosim-fw` | **12 / 12** |
| Constrained-random — hazard-biased random streams vs Spike (incl. CSR RMW) | `make crv` | **200 / 200** |
| LMB bus contract — level / edge / free-running / back-pressure pass, combinational fails | `make lmb-contract` | all pass |
| Bus timing scoreboard — randomized compliant slave timing, arch-invariant vs Spike | `make scoreboard` | **128 / 128** |
| LMB-protocol SVA assertions bound onto the core | `make sva` | **84 runs, 0 fail** |
| LMB handshake formal proof — yosys-smtbmc + z3 (BMC + k-induction) | `make formal` | **PROVEN** |
| Interrupt entry/return swept across every pipeline position | `make irq-stress` | **99 / 99** |
| `dmem_stall` × {IRQ / branch / muldiv} coincidence — MEI swept on stalling slaves | `make dmem-matrix` | **1410 / 1410** |
| WCET latency constants + mul/div data-independence | `make wcet` | per-op latency pinned vs µarch §4; **operand-invariant** |
| RTL line coverage | `make coverage` | **89.8 % core** |
| Second simulator — directed suite under Vivado xsim | `make xsim` | **21 / 21**, cycle-identical |

All conformance is reported with the **§10.3 carve-out** (no precise synchronous
exceptions; aligned-only access — see the [conformance caveat](#slot-in-replacement--conformance-checklist)
in the spec below).

### Performance — cycle-exact on the core

No caches + registered single-outstanding memory ⇒ Verilator cycles = silicon cycles
(reference Arm Cortex-M4 = 1.0, frequency-independent):

| Benchmark | Result |
|---|---|
| CoreMark | **1.949 CoreMark/MHz** |
| Embench-IoT (geomean) | **0.851** — all 17 kernels fit the 24 / 16 KiB budget |

Methodology + CI perf regression: [`docs/verification.md`](docs/verification.md) §9.

### Timing & deliverable

The default config **meets 250 MHz on UltraScale+** out-of-context (WNS ≈ +0.167 ns;
core logic ≈ 1.23 ns of the 4.0 ns budget); a **22 nm FD-SOI ASIC** target is ≈ 800 MHz.
The deliverable is the verified RTL plus this OOC synth result
([`docs/timing-and-resources.md`](docs/timing-and-resources.md)); adopt it as the
MicroBlaze-V **`mbv`** drop-in via [`docs/ip-delivery.md`](docs/ip-delivery.md).

### Build

`make -C sim ci` runs the portable Verilator subset (lint + directed tests +
determinism) anywhere; `make -C sim ci-full` runs the full local regression (WSL).
Fresh-clone setup for every gate (toolchains, WSL, Vivado) →
[`docs/local-resume.md`](docs/local-resume.md). Licensed **Apache-2.0**
([`LICENSE`](LICENSE) · [`NOTICE`](NOTICE)).

## Documentation

| Document | Purpose |
|---|---|
| [README.md](README.md) (this file) | Authoritative spec (Requirements, below) + project intro |
| [docs/microarchitecture.md](docs/microarchitecture.md) | Scope/layout, pipeline, hazards, FU latencies, WCET constants, decode + CSR maps — the design spine |
| [docs/timing-and-resources.md](docs/timing-and-resources.md) | 250 MHz UltraScale+ closure, critical paths, resource budget, XDC |
| [docs/verification.md](docs/verification.md) | Toolchain, suites, `make` targets, gates, **perf benchmarking + CI perf regression** |
| [docs/verification-status.md](docs/verification-status.md) | Living evidence record: what is verified, and how |
| [docs/implementation-backlog.md](docs/implementation-backlog.md) | Executable checkbox task list — the progress source of truth |
| [docs/ip-delivery.md](docs/ip-delivery.md) | IP integration guide for any host SoC: manifest, port/LMB contract, carve-out, integration |
| [docs/known-limitations.md](docs/known-limitations.md) | **Known limitations & errata** — scope decisions + verification-coverage boundaries (start here before signoff) |
| [docs/local-resume.md](docs/local-resume.md) | **Setup & run guide** — fresh clone → install every toolchain (portable / WSL / Vivado) and run every gate, with the conformance carve-out |
| [CHANGELOG.md](CHANGELOG.md) | Release history (`v1.0.0-rcN` → v1.0.0) |
| [sim/coremark/README.md](sim/coremark/README.md) | CoreMark/MHz harness, results, deterministic-core comparison band |
| [sim/embench/README.md](sim/embench/README.md) | Embench-IoT harness, results, 24/16 KiB fit validation |
| [CLAUDE.md](CLAUDE.md) | Project guide + autonomous-resume driver + current status |

Per-gate detail lives in the `sim/<gate>/README.md` files (`riscof`, `cosim`,
[`cosim-fw`](sim/cosim-fw/README.md) — system-level compiled-C lock-step,
[`scoreboard`](sim/scoreboard/README.md) — randomized-timing, [`sva`](sim/sva/README.md)
+ [`formal`](sim/formal/README.md) — LMB-protocol assertions + proof,
[`crv`](sim/crv/README.md) — constrained-random ISG, `lmb-contract`, `irq-stress`,
[`xsim`](sim/xsim/README.md) — the second-simulator gate, …).

---

# Requirements / Specification

> The following is the authoritative core specification. It is captured here
> section by section as the project requirements.

## Processor Core — Configuration & Interface (drop-in replacement spec)

This core is a drop-in replacement for an AMD MicroBlaze-V soft core in a host
SoC. This section specifies the exact configuration and signal-level interface a
host system depends on, so a MicroBlaze-V can be replaced by an equivalent
RISC-V core (custom or third-party) with **no changes to the host**. A conforming
replacement need only present the bus + interrupt behaviour below; nothing in the
host reads any MicroBlaze-specific feature.

### ISA & functional configuration

| Property | Value | Rationale |
|---|---|---|
| Base ISA / XLEN | RV32I, 32-bit, little-endian, 32 GPRs | RV32 LMB-native; ≤32-bit signal model |
| Extensions | M (mul + div), Zba/Zbb/Zbs (bit-manipulation), Zicsr → `rv32im_zba_zbb_zbs_zicsr` | mul/div + barrel + bit-ops for fixed-point / signal pack-unpack inner loops |
| Privilege | Machine mode only (no S/U mode, no Zbc, no A/C/F/D) | bare-metal RTOS; smallest deterministic core |
| MMU / virtual memory | none | no address translation; flat 32-bit physical map |
| Caches | none (no I-cache, no D-cache) | bypasses cache-related preemption delay at the root — mandatory for determinism |
| PMP / memory protection | none in v1 | deferred to v2 |
| Reset vector | parameter (`C_BASE_VECTORS`): `0x0` app-direct, `0x7800` for the baked boot-ROM build | PC ← base on reset |
| Counters | `mcycle` / `minstret` present | optional; firmware does not require them |
| `wfi` | may execute as sleep or no-op (`C_USE_SLEEP=0`) | firmware idles on `wfi` but dispatch is ISR-driven, so either is fine |

### Trap / interrupt model

Standard RISC-V machine mode (this is the only control-flow contract the
firmware relies on; the optional example `fw/start.S` + `fw/firmware.c`):

- A single external interrupt input is the **machine external interrupt**
  (`mip.MEIP`, cause 11). It is a **single level-sensitive external interrupt
  from the host**; the source deasserts when firmware clears it (write-1-clear at
  the host), so **no hardware acknowledge handshake** is required.
- Enabled by `mstatus.MIE` (bit 3) and `mie.MEIE` (bit 11). On trap the core
  sets `mepc ← PC`, `mcause ← 0x8000000B`, clears `mstatus.MIE`; it vectors to
  `mtvec` (firmware uses **direct mode** — all traps to `mtvec.BASE`). `mret`
  restores `MIE` from `MPIE` and returns.
- Required CSRs a replacement must implement: `mstatus`, `mie`, `mtvec`,
  `mepc`, `mcause`, `misa`/`mhartid` (read-only ok). The legacy
  `Interrupt_Address` vector input is **not used** (RISC-V uses `mtvec`); tie it
  to 0.

### Clock & reset

- **`Clk`** — single PL clock (the 250 MHz PL domain). Fully synchronous core.
- **Reset** — synchronous, active-high (the wrapper drives `~rst_n`). Asserting
  it forces `PC ← reset vector` and clears `mstatus.MIE`.

### Memory interfaces (Harvard: two independent 32-bit buses)

The core is a Harvard master: an **instruction bus** (read-only) and a **data
bus** (read/write), each a **single-outstanding, in-order** access with
**registered (BRAM-style 1-cycle) response** — the address is presented with a
1-cycle strobe and held until ready; the slave returns ready + data the next
cycle. The strobe is **one rising-edge pulse per access** — the master never
holds it asserted across back-to-back accesses (so a host slave may start an
access on the strobe's *rising edge*, exactly like the AMD core); **consecutive
accesses therefore take a fixed 1-cycle gap**. A zero-wait (combinational)
response delivers read data a cycle early and **corrupts execution** — the
1-cycle registered latency is part of the contract (and is what the determinism
analysis assumes). There is **no burst, no out-of-order, no speculative fetch**.

The core presents the MicroBlaze-V-compatible **LMB v10** master signals below;
the host SoC may consume them directly or via a thin adapter that maps each LMB
signal to its native memory ports.

#### Instruction bus

Core = master; the host maps it to its instruction-memory port:

| LMB signal | Dir (core) | Width | Host-native | Meaning |
|---|---|---|---|---|
| `Instr_Addr` | out | 32 | `if_addr` | fetch address (word-aligned) |
| `IFetch` | out | 1 | gates `if_re` | fetch active |
| `I_AS` | out | 1 | gates `if_re` | address strobe (1-cycle) |
| `Instr` | in | 32 | `if_data` | instruction word (valid next cycle) |
| `IReady` | in | 1 | `if_ready` | data valid (1 cycle after strobe) |
| `IWAIT`, `ICE`, `IUE` | in | 1 | tie 0 | wait / correctable / uncorrectable error — unused |

Typical host mapping: `if_re = I_AS & IFetch`, `if_addr = Instr_Addr`,
`Instr = if_data`, `IReady = if_ready`.

#### Data bus

Core = master; the host maps it to its data-memory slave:

| LMB signal | Dir (core) | Width | Host-native | Meaning |
|---|---|---|---|---|
| `Data_Addr` | out | 32 | `d_addr` | byte address |
| `Data_Write` | out | 32 | `d_wdata` | write data |
| `Write_Strobe` | out | 1 | gates `d_we` | write access |
| `Read_Strobe` | out | 1 | gates `d_re` | read access |
| `D_AS` | out | 1 | gates `d_we/d_re` | address strobe (1-cycle) |
| `Byte_Enable` | out | 4 | `d_be` | byte lanes |
| `Data_Read` | in | 32 | `d_rdata` | read data (valid next cycle) |
| `DReady` | in | 1 | `d_ready` | access complete (1 cycle after) |
| `DWait`, `DCE`, `DUE` | in | 1 | tie 0 | wait / errors — unused |

Typical host mapping: `d_we = D_AS & Write_Strobe`, `d_re = D_AS & Read_Strobe`,
`d_addr = Data_Addr`, `d_wdata = Data_Write`, `d_be = Byte_Enable`;
`Data_Read = d_rdata`, `DReady = d_ready`.

The data bus issues loads/stores into a **flat 32-bit physical space that the
host SoC decodes** — the core just presents the address. A representative map:

| Base | Region |
|---|---|
| `0x0000_0000` | instruction memory |
| `0x1000_0000` | data memory |
| `0xC000_0000` | memory-mapped peripherals (host-defined) |

Host-defined peripherals are reached with ordinary loads/stores, so a
replacement needs **no special I/O port**.

### Interrupt & debug ports

| Port | Dir | Width | Notes |
|---|---|---|---|
| `Interrupt` | in | 1 | single level-sensitive external interrupt from the host → machine external interrupt |
| `Interrupt_Address` | in | 32 | tie 0 — unused (RISC-V vectors via `mtvec`) |
| `Interrupt_Ack` | out | — | unused (deassertion is via host write-1-clear, not a handshake) |
| `Dbg_*` (RISC-V Debug Module / JTAG) | — | — | tied off in v1 (`Dbg_Disable=1`); a replacement may omit debug |

### Determinism contract (what a replacement must preserve)

Fixed, data-independent fetch and load/store latency (registered, single-outstanding,
in-order; one rising-edge strobe per access, so consecutive accesses take a fixed
1-cycle gap); no caches, no speculation, no variable-latency or out-of-order
behaviour; bounded interrupt-entry latency. These — not any
MicroBlaze-specific feature — are what make the per-core WCET statically
analysable. **Anything meeting this section is a valid drop-in.**

### Slot-in replacement — conformance checklist

The details are spread across this section; this is the consolidated must-have /
may-skip list for an alternative core. A core meeting these runs the v1 firmware
unmodified.

**MUST implement** (load-bearing — the firmware/host depends on each):

- **CSRs actually used:** `mstatus` (MIE/MPIE/MPP stack), `mie` (MEIE), `mtvec`
  (direct mode), `mepc`, `mcause` — plus `mip.MEIP`. `mhartid`/`misa`
  read-only-ok (the firmware reads neither — any core-id coordinate comes from a
  host-defined memory-mapped register, not `mhartid`).
- **Machine-external-interrupt trap** (`mcause = 0x8000000B`) → `mtvec`, per the
  trap model above. This is the only trap the dispatch relies on.
- **`mret` restores `mstatus.MIE` from `MPIE`** (and trap entry sets
  `MPIE←MIE`, `MIE←0`, `MPP←M`). The ISR re-enables interrupts only via `mret` —
  there is no explicit re-enable in the handler.
- **Interrupt is level-sensitive, no acknowledge handshake:** `mip.MEIP` follows
  the pin level (the host source deasserts only on firmware write-1-clear). **Do
  not edge-latch** — a level still high after the ISR must re-trap; a level
  cleared mid-handler must not spuriously re-fire.
- **`wfi` decodes as a legal NOP-or-sleep** (never illegal/trap): `main()` idles
  on `wfi`. This is required, not stubbable — and note it compounds with
  omitting the illegal-instruction exception.
- **Registered 1-cycle LMB timing, one rising-edge strobe per access:** ready+data
  the cycle after the strobe, ABus held until ready, in-order single-outstanding.
  Drive **one strobe pulse per access** with a clean rising edge — **do not hold
  the strobe across back-to-back accesses** (a host slave may start an access, and
  register the read word, on that rising edge; holding it re-reads the first
  word). Consecutive accesses take a fixed 1-cycle gap. A zero-wait/combinational
  response delivers read data a cycle early and **corrupts execution** (see Memory
  interfaces above).
- **Sub-word store byte-enables on DMEM** (`sb`/`sh` drive `d_be`; no RMW in the
  core); loads are full-word with core-side lane select (see Sub-word access
  contract above).

**MAY skip / stub** (nothing in v1 depends on it):

- **Synchronous exceptions** — misaligned (`mcause` 4/6), illegal-instruction
  (2), bus-error (5/7): optional (see the trap model). The baked AMD core traps
  precisely; a minimal core may assume aligned-only access and omit them.
  `mtval`/`mscratch` are then vestigial (the trap entry uses a single stack, no
  `mscratch` swap; `mtval` only carries exception info) — cheap to add for
  arch-test, but not required.
- **Counters** `mcycle`/`minstret`, **RISC-V Debug Module / JTAG** (`Dbg_*`),
  **`Interrupt_Address`**.
- **Instruction/data-memory sizes + writable-IMEM** and the **layout and
  register/bit map of any host-defined memory-mapped peripherals** are
  memory-map / firmware concerns — the core just issues loads/stores and sees
  one `Interrupt` pin.

**Verification caveat:** because synchronous exceptions are optional, a minimal
core is **not fully riscv-arch-test / RISCOF conformant** — the misaligned-access,
illegal-instruction, and synchronous-cause trap suites must be carved out of
signoff, and Spike lock-step will diverge on misaligned accesses (Spike emulates
and completes them). The integer / M / Zba/Zbb/Zbs instruction suites — the ones
that matter for this core — are unaffected. **Don't report "arch-test passes"
without the carve-out.**
