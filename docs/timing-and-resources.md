# Stoic-V Timing & Resources — 250 MHz on UltraScale+

Companion to [`microarchitecture.md`](microarchitecture.md).

## 1. Target (DECIDED)

| Item | Value |
|---|---|
| Clock | single synchronous `Clk` |
| **Closure target** | **250 MHz → 4.000 ns period, WNS > 0 (positive slack)** |
| Target FPGA | AMD **UltraScale+** (Zynq UltraScale+ / Kintex/Virtex UltraScale+) |
| **Target board / part** | **ZCU102 → `xczu9eg-ffvb1156-2-e`** (Zynq US+ XCZU9EG, **-2**) — the real silicon (build.tcl default) |
| Setup signoff | positive slack at the board's **-2** grade |
| Hold | 0 violations (synchronous single-clock design — should be automatic) |

Rationale for 250 MHz on US+: closing a small RV32 core at 250 MHz is
comfortable and leaves ample margin for the bit-manip/multiplier paths and for
host-side routing, while preserving the determinism contract (timing changes
never alter cycle counts — only fmax). The part is a build parameter
(`vivado/build.tcl -tclargs <part>`); the default is the real board, the
**ZCU102 / XCZU9EG-2** silicon, which is the signoff target.

The clock constraint (`vivado/timing.xdc`):
```tcl
create_clock -name Clk -period 4.000 [get_ports Clk]
# input/output delays modelled at the host SoC level; core is fully synchronous.
```

ASIC target: ≈ 800 MHz at 22 nm FD-SOI (within a documented 700–900
MHz GF 22FDX estimate); the FPGA constraint above is the hard signoff gate.

## 2. Likely critical paths and the mitigation for each

| Path | Risk | Mitigation (determinism-safe) |
|---|---|---|
| 32×32 multiply (`mulh*`) | high | map to **DSP48E2** with **registered inputs and outputs**; `MUL_LAT` fixed (**= 4**: single signed 33×33, MREG+PREG — see §6) |
| Bit-manip combinational (`cpop/clz/ctz/rev8/ror`) + ALU result mux | medium | single-cycle (meets 4 ns); `cpop/clz/ctz` could move behind one **fixed** extra cycle if a path ever needs it (record in WCET table) |
| Forwarding muxes into EX operands | medium | minimise forward sources (2: EX/MEM, MEM/WB); no 3-deep bypass |
| Branch compare + target adder + redirect to IF PC mux | medium | precompute branch target in parallel with compare; single redirect mux in IF |
| Divider iteration combinational depth | low | radix-2 per cycle keeps each iteration shallow; `DIV_LAT` fixed |
| Regfile read → EX | low | distributed-RAM read is fast; old-value read + forwarding |

Every mitigation that adds a stage adds **fixed** latency only → determinism
preserved; just re-record the affected WCET constant
([`microarchitecture.md`](microarchitecture.md) §4).

## 3. Resource budget (acceptance envelope, single core)

Targets for the **core only** (`rtl/core/*`), excluding host-provided/BRAM memories.
These are upper bounds the timing gate (M6) checks against; a small in-order RV32IM+Zb*
comfortably fits well under them.

| Resource | Budget (per core) | Notes |
|---|---|---|
| CLB LUTs | ≤ 4,000 | **2855** (OOC synth, xczu9eg-2) for RV32IM + Zb* |
| CLB FFs | ≤ 3,000 | **1068** — pipeline regs + CSRs + the `wmd` muldiv-forward register + `d_inflight` + the `ld_word` load-data latch |
| DSP48E2 | ≤ 4 | **4** — multiplier; `mul`+`mulh*` (signed 33×33) |
| BRAM (RAMB36/18) | 0 | **0** — regfile in distributed RAM; IMEM/DMEM are host-side |
| LUTRAM | ≤ 256 | 2R1W GPRs as 2× RAM32M copies |
| Fmax (impl, -2) | ≥ 250 MHz | **WNS > 0** is the hard gate |

If any budget is exceeded, prefer a microarchitectural fix that keeps
determinism (e.g. share the shifter between base ALU and `ror/rol`) over relaxing
the determinism contract — the contract is non-negotiable, the budget is a target.

## 4. Regfile implementation note (resource-driven)
2R1W 32×32: implement as **two parallel RAM32M (LUTRAM) copies**, both written by
the WB port, each serving one read port. Cost ≈ a few dozen LUTs, **0 BRAM, 0
DSP**. `x0` handled by forcing read-0 / write-mask, not a RAM cell. FF-array
(1024 FF + 32:1 muxes) is the fallback if LUTRAM hurts timing.

## 5. Build & report flow (`vivado/build.tcl`)
1. `read_verilog -sv` all of `rtl/core/*` (plus any host wrapper when integrating).
2. `read_xdc vivado/timing.xdc`.
3. `synth_design -top mbv -part xczu9eg-ffvb1156-2-e` (ZCU102; override via `-tclargs`).
4. `opt_design; place_design; phys_opt_design; route_design`.
5. `report_timing_summary -file build/timing.rpt` → assert **WNS ≥ 0**.
6. `report_utilization -file build/util.rpt` → assert within §3 budget.
7. Non-zero WNS or over-budget → **the timing gate fails** (CI returns non-zero).

A headless `vivado -mode batch -source vivado/build.tcl` is the synth command (M6); the
gate script greps `report_timing_summary` for WNS and fails on negative slack.

## 6. Synth results (M6)

Direct OOC synth, Vivado 2025.2.1, `xczu9eg-ffvb1156-2-e`, 4.000 ns (250 MHz). The
default 5-stage **closes the OOC timing gate**:

| Scope | Config | WNS @ 4.000 ns | DSP / BRAM | LUT / FF | Worst path |
|---|---|---|---|---|---|
| Core OOC (reg→reg) | default 5-stage | **+0.167 ns** | 4 / 0 | **2855 / 1068** | `w_is_md → forward → ALU → m_result`, **14 levels**, logic 1.231 ns / route ≈ 2.6 ns (route-dominated) |

**OOC is route-dominated** (68 % route): the worst path is a tiny core spread
across the large ZU9EG with no floorplan. The default's combinational **logic is
≈ 1.2 ns** of the 4.000 ns budget — well under, so the core logic closes 250 MHz
with large margin; the residual is OOC routing of a floorplan-less design, not logic
depth.

**Re-validated after the 2026-06 P7.1 store→load fix** (the `ld_word` load-data latch
+ commit mux, off the binding path): still **PASS, WNS +0.167 ns** @ 250 MHz OOC, area
2855 LUT / 1068 FF (+76 / +29 for the latch). The
binding path is the *same* EX result-forward loop (`forward → ALU → m_result`); the
handshake logic (`dmem_stall`/`d_inflight`) sits in register clock-enables, **not on
the data path** — combinational logic is essentially unchanged (1.21 → 1.23 ns). The
slack drop from +0.209 ns is **route**, not logic: the +18 LUT / +2 FF of handshake
logic perturbed the placement of the floorplan-less OOC design (route 2.56 → 2.68 ns,
68 % of the path). Combinational logic depth — the timing the core actually owns — is
unchanged, so this remains a logic-sanity result, not a route-closure result.

**Load-use path (`P_LOADUSE` = 2):** when the host serves an instruction-memory
word as a *data* read (a cascaded-BRAM read latency on the data LMB), a load feeds
`Data_Read → load_ext → forward → ALU → m_result`. To keep this off the critical
path, the load result is registered (`wl`, `dont_touch`) and the load-use bypass
forwards that **register**, never the combinational `load_ext`; the load-use stall
is **2 cycles** (`P_LOADUSE` = 2). The registered LMB contract (single-outstanding,
one strobe edge per access) is preserved and the change is core-internal. The OOC harness models the cascaded-BRAM read
latency (`bram_co` ≈ 1.8 ns / ≈ 1.05 ns on the two buses) rather than
false-pathing the LMB I/O, so the timed load path is the real one. (A fetch FIFO
isolates the *instruction* fetch, so fetch is not the binding path.) Determinism
golden cycle count is **286** (8/8 identical; `det_check.py` checks identity, not an
absolute).

**Muldiv-result forward (`P_MDUSE`):** in a dense host placement, routing
congestion stretches the EX-result-forward→ALU loop whose slow source routes
through the mul/div result (`u_md`, DSP MREG/PREG). The muldiv result is therefore
forwarded from a dedicated `dont_touch` register (`wmd`), off that combinational
net; the generic ALU-result forward stays combinational (fast). Cost: **+1 cycle
only when a mul/div feeds the immediately-next dependent** (`P_MDUSE`) — CoreMark
1.949, Embench 0.851; determinism golden 286 (the adjacency does
not occur in the determinism stream). A single-instance in-context P&R has closed at
+0.30 ns @ 4.0 ns.

**OOC I/O methodology:** LMB I/O timing is a **host-level** concern (§1); the OOC
ports have no `PARTPIN_LOCS`, so Vivado flags raw port→reg timing as inaccurate
(`Route 35-198`) and cannot estimate clock skew (`Timing 38-242`). The OOC harness
therefore times **register-to-register** core logic plus the modelled BRAM-read
latency on the LMB buses, so the gate reads the one OOC-meaningful number; final I/O
closure happens in-context at the host SoC.

**Multiply (§2 multiply row):** `rv_muldiv` computes **one signed 33×33** product
(operand sign bits selected per op — serves mul/mulh/mulhsu/mulhu) instead of three
parallel 64-bit products, and pipelines it across two register stages (`pm1`=MREG,
`pm2`=PREG) so the DSP48E2 cascade closes the 4.000 ns budget. This keeps DSP usage
at **4** (within the ≤4 budget) and breaks the long combinational path. `MUL_LAT` is
**4** (fixed → determinism preserved). Functionally verified: `cosim` 48/48 vs Spike,
`riscv-tests` 48/48, `archtest` 75/75, `determinism` 8×286.

**Synchronous reset (DSP packing + clean warnings):** the whole core uses
**synchronous reset** (no `negedge rst_n` in any sensitivity list). An async reset is
a per-register control net that (a) forbids the DSP48E2 from absorbing the multiply
pipeline regs (`pm1`=MREG/`pm2`=PREG are sync-reset-only) and (b) trips
`Synth 8-7137` ("Set+reset same priority") + Verilator `SYNCASYNCNET`. Synchronous
reset is the Xilinx-preferred FPGA style (UG901): it lets the multiply pack fully
into the DSP (lower FF, better mul timing in-context) and clears the warnings.
Behaviour-neutral (reset held ≥1 clock) — verified `lint` clean / `determinism`
8×286 / `riscv-tests` 48/48 / `cosim` 48/48 / `archtest` 75/75. The integration
manifest, port + LMB contract, and pblock/DSP must-checks are in
[`ip-delivery.md`](ip-delivery.md).
