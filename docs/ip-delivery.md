# Stoic-V — IP Integration Guide (adopting the core into a host SoC)

Integration guide for instantiating **Stoic-V** (the deterministic RV32 core) as
the **`mbv`** slot-in inside any host SoC. The IP is branded **Stoic-V**, but its
synth top module is **`module mbv`** with the exact MicroBlaze-V LMB v10 port
signature — that fixed name *is* the drop-in contract, so the core binds into a
MicroBlaze-V socket **unchanged**; do not rename it.
Pairs with [`README.md`](../README.md) (authoritative spec),
[`verification-status.md`](verification-status.md) (evidence), and
[`timing-and-resources.md`](timing-and-resources.md) (closure).

> **One-line summary:** drop the 9 `rtl/core/*` files in as your `mbv`, point the
> instruction LMB at firmware, give the host's pblock for this core a DSP column,
> and honour the single-outstanding LMB contract (one rising-edge strobe per access, DReady-handshaked). It already passes the full
> verification suite (cosim/archtest/riscv-tests/lmb-contract/irq-stress/
> determinism), is **lock-stepped against Spike as compiled-C firmware on the canonical
> free-running BRAM** (`make cosim-fw`, 12/12 — the slave model your tile uses), is
> re-validated under **Vivado xsim** (`make xsim`, 21/21, cycle-identical to
> Verilator), and meets 250 MHz OOC. Everything else below is detail.

---

## 1. What you are adopting

A `rv32im_zba_zbb_zbs_zicsr`, **Machine-mode-only**, in-order, **statically
WCET-analysable** core (no caches, no MMU, no speculation, no branch prediction,
no early-terminating mul/div). It presents the **MicroBlaze-V `mbv` signature**
so a host SoC that instantiates a MicroBlaze-V can bind it unchanged. It is a
functional slot-in for the MicroBlaze-V soft core.

## 2. File manifest (the deliverable)

Self-contained; the only inter-file dependency is the package, compiled **first**.
Compile order:

| # | File | Role |
|---|---|---|
| 1 | `rtl/core/rv_pkg.sv` | types, opcodes, CSR addrs, params (**must be first**) |
| 2 | `rtl/core/rv_alu.sv` | base ALU |
| 3 | `rtl/core/rv_bitmanip.sv` | Zba/Zbb/Zbs (combinational) |
| 4 | `rtl/core/rv_regfile.sv` | 2R1W GPRs (LUTRAM, no reset) |
| 5 | `rtl/core/rv_decode.sv` | decoder |
| 6 | `rtl/core/rv_muldiv.sv` | M ext: fixed-latency mul (DSP) + restoring divider |
| 7 | `rtl/core/rv_csr.sv` | Zicsr + trap/IRQ |
| 8 | `rtl/core/rv_core.sv` | 5-stage pipeline + fetch FIFO |
| 9 | `rtl/core/mbv.sv` | **top** — wraps `rv_core`, presents the `mbv` ports |

**The deliverable is exactly the 9 `rtl/core/*` files above plus the standalone
OOC harness.** `vivado/timing.xdc` and `vivado/build.tcl` are that *standalone OOC
harness* (logic sanity only — see §7); the host owns the real constraints. No
host-side sources travel with the IP.

## 3. Top module & port contract

`module mbv #(parameter logic [31:0] RESET_VEC = 32'h0000_0000)` with the exact
MicroBlaze-V port list ([`rtl/core/mbv.sv`](../rtl/core/mbv.sv)). The host
instantiates `module mbv` by name with every port matched — **no wrapper edits
required**. Ports of note:

- **`Clk`** — single synchronous clock.
- **`Reset`** — **active-high** (the wrapper drives `~rst_n`; the core inverts).
- **Instruction LMB:** `Instr_Addr`/`Instr`/`IFetch`/`I_AS`/`IReady` used;
  `IWAIT`/`ICE`/`IUE` ignored (contract §5).
- **Data LMB:** `Data_Addr`/`Data_Read`/`Data_Write`/`D_AS`/`Read_Strobe`/
  `Write_Strobe`/`Byte_Enable`/`DReady` used; `DWait`/`DCE`/`DUE` ignored.
- **`Interrupt`** — a single level-sensitive external interrupt from the host
  (write-1-clear at the host; no hardware-acknowledge handshake) → `mip.MEIP`
  (vector via `mtvec`; `Interrupt_Address` unused). `Interrupt_Ack` tied 0.
- **Debug port group** — present for binding, **functionally omitted in v1**
  (`Dbg_*` tied off). No JTAG-debug.

## 4. Clocking, reset, parameters

- **Single synchronous clock `Clk`.** No derived/gated clocks.
- **Synchronous reset throughout** (core-wide convention — Xilinx UG901). Reset
  must be **held ≥ 1 `Clk` edge** (always true in the host). Rationale: an async
  reset blocks DSP48E2 register packing and proliferates control sets; sync reset
  is the FPGA-preferred style and lets the multiply pack into the DSP.
- **`RESET_VEC`** (default `0x0000_0000`) — boot PC. The host binds `mbv`
  **without** overriding it, so the core boots from `0x0` (the host's
  instruction-memory base). Override only if your reset vector differs. (The
  conformance sim overrides it to `0x8000_0000` to match Spike; synth/firmware
  use the `0x0` default.)
- **Memory aperture (recommended end-target sizing): 24 KiB I / 16 KiB D, no
  compressed (`C`) ISA.** The core RTL is size-agnostic — it only drives LMB
  addresses, so aperture depth lives entirely host-side; this is an integration
  recommendation, not a core parameter. Rationale: the host targets **realistic
  MCU-class kernels**, not just boot/ISR stubs. 24 KiB uncompressed ≈ **~18 KB of
  Thumb-2/RVC** in logical capacity → M0-class footprint, holds a CoreMark-class
  kernel (16.9 KB at `-O3`, ~11 KB `-Os`) with headroom; the **code-heavy 1.5:1**
  I:D shape leans the way shipping similar-perf MCUs do (flash:SRAM ~4:1–8:1).
  The **`C` extension is deliberately omitted** — on a cacheless core `C` is 1:1
  expansion (≈0 IPC gain) and it adds fetch-alignment logic plus a WCET fetch-
  uniformity term; the asymmetric aperture carries the density instead.
  - **Validated against real kernels:** all **17 Embench-IoT** realistic MCU
    kernels (crypto, JPEG, regex, sort, state-machines, DSP) **fit and pass**
    cycle-exact on the core — max `.text` = `wikisort` 24.3 KiB (right at the
    24 KiB edge), max data+bss = `tarfind` 9.1 KiB (see [`sim/embench/`](../sim/embench/)).
    Embench speed score **0.851** (geomean, ref Arm Cortex-M4 = 1.0, **default 2-cycle
    load-use config**; 0.874 with the optional `CORE_PERF` 1-cycle build).
    This is the evidence the 24/16 budget is correctly sized for the workload.
  - **BRAM budget:** 24 KiB I = 6× RAMB36, 16 KiB D = 4× → **10 RAMB36 / instance**.
  - **⚠ Aperture Tco:** the instruction-aperture read is the load-use timing
    limiter (~1.8 ns on the cascaded read; see §7.3). **Bank/organise the 24 KiB
    I-aperture to keep the read mux shallow** — a 6-deep *ripple* cascade worsens
    that Tco; parallel banks + one mux level do not. This directly affects Fmax.

## 5. LMB bus contract — **REQUIRED, load-bearing**

The core is a **single-outstanding LMB master that drives one rising-edge address
strobe per access and honours DReady**. It works with any **FIXED-latency registered
slave** on **both** buses — level-ready, edge-detect (held-ready), or
back-pressure — and matches MicroBlaze-V's LMB. A combinational/zero-wait response
is **not** supported. Consecutive accesses take a fixed 1-cycle gap (deterministic):

- read data / instruction is available no earlier than the **cycle after** the strobe (registered, fixed-latency);
- address is held until consumed; one request outstanding at a time;
- the core drives **one rising-edge address strobe per access** and **honours
  `DReady`/`IReady`** before completing it — the strobe is never held across
  back-to-back accesses (single-outstanding sequencing).

This is by design (a variable-latency memory would make WCET contention-
dependent — it violates the determinism prime directive). **The host's LMB slave
MUST present a fixed-latency registered response** (data no earlier than the cycle
after the strobe). A combinational / zero-wait slave **corrupts execution** — there
is a negative regression for exactly this (`make lmb-contract`).

## 6. Resource profile (per core, OOC on `xczu9eg-2`)

| Resource | This core | ZU9EG | Note |
|---|---|---|---|
| CLB LUTs | **2855** (1.0 %) | 274,080 | incl. the load-data latch (`ld_word`) + commit mux |
| CLB FFs | **1068** (0.2 %) | 548,160 | measured OOC; incl. the `wmd` muldiv-forward register, `d_inflight`, the `ld_word` load latch; multiply PREG packs into the DSP; quot/rem dropped |
| DSP48E2 | **4** (0.2 %) | 2,520 | signed 33×33 multiply, pipelined (PREG packed) |
| BRAM | **0** | 912 | regfile is LUTRAM; IMEM/DMEM are host-side |

Per-instance (post-route, `xczu9eg-2`): `u_core` own 1569 LUT / 415 FF · `u_md`
599 / 290 / 4 DSP · `u_csr` 466 / 259 · `u_rf` 124 / 0 (LUTRAM). A comfortably
small footprint, competitive with MicroBlaze-V.

## 7. Integration requirements & checks (verify during host integration)

1. **The host's pblock for this core MUST span a DSP column.** The multiply uses
   **4 DSP48E2**. If a replicated pblock region contains no DSP column, either
   extend the region to include one, or force a LUT-based multiply (different
   resource profile + a likely timing hit — not recommended). **Verify per
   replicated instance**, since pblocks repeat across the device. *(This is the one
   hard integration gotcha.)*
2. **The host's pblock for this core resource budget** must hold ~3.5k LUT /
   ~1.2k FF / 4 DSP / 0 BRAM (§6). Very likely already satisfied if it held
   MicroBlaze-V.
3. **Timing: default config meets 250 MHz OOC.**
   The default 2-cycle load-use config **meets 250 MHz OOC** (WNS ≈ **+0.167 ns**
   at the 4.000 ns period; the residual is OOC routing of a floorplan-less design, not
   logic depth); the core logic worst-path ≈ **1.23 ns**
   closes 250 MHz with large margin. The load result is registered (`P_LOADUSE` = 2): the load
   result is registered (`wl`, `dont_touch` so the host flatten can't merge it
   into the cross-boundary bypass LUTs) and the load-use bypass forwards that
   register, never combinational `load_ext`; the load-use stall is 2 cycles. The
   **mul/div result is likewise forwarded from a dedicated `dont_touch` register**
   (`wmd`), removing it from the combinational EX-forward→ALU loop whose slow source
   routes through the DSP (`u_md`) — the binding net that routing congestion can
   stretch; **+1 cycle only when a mul/div feeds the immediately-next
   dependent** (`P_MDUSE`), the generic ALU forward stays combinational. The
   host serves the IMEM aperture as a *data* read (cascaded BRAM → `Data_Read`),
   so `Data_Read → load_ext → forward → ALU → m_result` is the load-use path the
   harness models (cascaded-BRAM read Tco). The **full suite is green** (cosim
   48/48, cosim-fw 12/12, archtest 75/75, riscv-tests 48/48, lmb-contract, irq-stress,
   xsim 21/21; CoreMark 1.949 CRC-validated; Embench 0.851; determinism golden 286).
   To integrate, instantiate as `mbv` and close timing in the host's pblock for this
   core (it supplies the locality the floorplan-less OOC lacks); a single-instance
   in-context P&R has closed at +0.30 ns @ 4.0 ns.
   `CORE_PERF` is the 1-cycle load-use option for relaxed/banked deployments
   (+6 % CoreMark / +3 % Embench; still deterministic); its 1-cycle IMEM-aperture load needs the
   aperture banked or made multicycle to close 250 MHz. Area/FF (§6) unaffected.
4. **Both LMB adapters stay registered single-outstanding (one rising-edge strobe per access)** (§5) — the `P_LOADUSE` fix is
   **core-internal** and does **not** change the bus contract. Confirm the
   cascaded-BRAM read Tco the core sees at bring-up (the harness models ~1.8 ns
   IMEM-aperture / ~1.05 ns DMEM; see §7.3).

## 8. Conformance & the carve-out — **REQUIRED to state downstream**

Per the **§10.3 carve-out**, v1 **omits precise synchronous exceptions** and
assumes **aligned-only** access:

- `ecall`/`ebreak`/illegal-instruction/misaligned access **do NOT trap**; an
  unrecognised instruction decodes to a defined **NOP**.
- Consequently the misaligned / illegal-instruction / sync-cause arch-test and
  `rv32mi` suites are **out of signoff**, and Spike lock-step excludes misaligned
  ops.
- **The controlled firmware target must not rely on synchronous traps.** Closing
  this is a localised `rv_csr`/LSU change that does **not** touch the bus
  contract — a clean v2 item.

**Required must-haves are present** (firmware depends on them): `wfi` legal
NOP/sleep; `mret` MIE/MPIE restore; **level-sensitive** `mip.MEIP` (no
edge-latch); MEI trap → `mtvec`; the `mstatus`/`mie`/`mtvec`/`mepc`/`mcause` set.

## 9. Verification evidence (all green locally — WSL Ubuntu-24.04)

Full detail in [`verification-status.md`](verification-status.md). Summary:

| Gate | Result |
|---|---|
| `archtest` (RISCOF vs Spike, I/M/Zba/Zbb/Zbs) | **75/75, 0 failed** (carve-out) |
| `riscv-tests` (Berkeley rv32ui+rv32um) | **48/48** |
| `cosim` (Spike `--log-commits` lock-step, riscv-tests) | **48/48** GPR-write streams identical |
| `cosim-fw` (**system-level**: compiled-C firmware vs Spike on the **free-running BRAM**) | **12/12** (`-O0/-O2/-O3`; ~22 k retires each) — the slave model your tile uses |
| `scoreboard` (**randomized** compliant slave timing, arch-invariant vs Spike) | **128/128** (workload × opt × seed) — catches bus-capture bugs across the timing space |
| `sva` (LMB-protocol assertions bound onto `rv_core`) | **84 runs, 0 failures** (single-outstanding, one-strobe-per-access, sequencing) |
| `formal` (LMB handshake, yosys-smtbmc + z3) | **PROVEN** — BMC + k-induction (unbounded); the bus-handshake protocol your tile relies on |
| `crv` (constrained-random hazard-biased programs vs Spike, incl. CSR RMW) | **200/200** — datapath/forwarding/hazard/CSR logic robust across thousands of random instructions |
| `determinism` | **8 datasets × 286 cycles** (data-independent) |
| `lmb-contract` (level / edge-detect / **free-running** / back-pressure; incl. store→load) | 1-cycle-registered required (negative tests fire) |
| `irq-stress` | **99/99** MEI injection points |
| `dmem-matrix` (`dmem_stall` × {IRQ/branch/muldiv} coincidence) | **1410/1410** — MEI swept on stalling/free-running slaves while a data access is outstanding |
| `wcet` (latency constants + FU data-independence) | per-op latency pinned vs µarch §4 (div 37 / mul 6 / load-use 4 / branch 4); mul & div latency **operand-invariant** |
| `xsim` (second simulator — directed suite under **Vivado xsim**, the host's sim) | **21/21**, cycle-identical to Verilator; catches the Verilator↔xsim divergence class |
| `coverage` | 89.8 % core lines (datapath ~98–100 %) |

The above was **re-confirmed after** the synchronous-reset tidy (lint / det /
riscv-tests / cosim / archtest all still green), proving that change is
behaviour-neutral.
