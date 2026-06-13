# Stoic-V Microarchitecture — detailed design

The implementable detail: pipeline structure, cycle behaviour, hazards,
functional-unit latencies, the WCET constants, the decode tables, and the CSR
bit maps. The **authoritative external contract is the spec in
[`../README.md`](../README.md)** (Requirements section); this document must never
contradict it. Verification is in [`verification.md`](verification.md), timing
closure in [`timing-and-resources.md`](timing-and-resources.md), and live status
in [`implementation-backlog.md`](implementation-backlog.md).

> **Determinism is the prime directive.** Every choice below is data-independent
> in latency: in-order, single-outstanding, no caches, no speculation, no
> early-termination. Any operand-dependent timing is a bug regardless of
> functional correctness.

---

## 0. Scope, goals & repository layout

A synthesizable RV32 core, **`rv32im_zba_zbb_zbs_zicsr`**, **Machine-mode only**,
that drops into a host SoC as a MicroBlaze-V replacement — it presents the
MicroBlaze-V-compatible **LMB v10** master interface, so a host that instantiates
a MicroBlaze-V binds it unchanged. Hard determinism (above) makes per-core WCET
statically analysable.

**Non-goals (v1):** no MMU / caches / PMP (PMP deferred to v2); no S/U mode; no
A/C/F/D/Zbc; no Debug Module (`Dbg_*` tied off, `Dbg_Disable=1`); no burst,
out-of-order, or speculative fetch.

**Repository layout:**
```
rtl/core/   mbv.sv (slot-in top, §9) → rv_core.sv (5-stage, default);
            rv_pkg, rv_decode, rv_regfile, rv_alu, rv_bitmanip, rv_muldiv, rv_csr
            (fetch / LSU / hazards are integrated in rv_core.sv)
fw/         optional example: start.S, firmware.c, link.ld (M-mode bring-up)
tb/         tb_top.sv (unit), models/lmb_bram.sv (registered 1-cycle slave), cpp/sim_main.cpp
tests/      directed self-checking asm + det_check.py
vivado/     build.tcl (synth/impl + WNS gate), timing.xdc
sim/        Makefile + gate harnesses: riscof/ riscv-tests/ cosim/ lmb-contract/
            irq-stress/ coverage/ coremark/ embench/
```

---

## 1. Pipeline overview (classic in-order 5-stage)

```
        IF            ID            EX           MEM           WB
   ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
PC─┤ I-LMB rd ├─►│ decode + ├─►│ ALU/bit/ ├─►│ D-LMB rd ├─►│ regfile  │
   │ (addr→   │  │ regread  │  │ mul/div/ │  │ /wr      │  │ write    │
   │  data)   │  │ + hazard │  │ branch   │  │ (addr→   │  │          │
   └──────────┘  └──────────┘  └──────────┘  │  data)   │  └──────────┘
                                              └──────────┘
   pipeline regs:  IF/ID         ID/EX        EX/MEM        MEM/WB
```

**Key idea — the BRAM's registered output *is* the pipeline register.** The LMB
slave returns ready+data the cycle *after* the strobe (README, Memory interfaces). So:

- **IF** presents `Instr_Addr`/`I_AS`/`IFetch` for the current PC at the start of
  the cycle; the returned `Instr` clocks into the **IF/ID** register at the next
  edge. IF therefore *is* the 1-cycle fetch latency — no extra stall, **1 instr
  issued per cycle** in steady state.
- **MEM** presents `Data_Addr`/`D_AS`/strobes/`Byte_Enable` as a **1-cycle rising-
  edge address-strobe pulse** per access and waits for `DReady` (§9). On a 1-cycle
  registered slave the data clocks into the **MEM/WB** register the next edge (1-cycle
  data latency); the access is **single-outstanding** and the core never holds the
  strobe across accesses — so **consecutive** loads/stores take a fixed 1-cycle gap
  (the next access's rising edge), exactly like MicroBlaze-V. An isolated access
  (followed by a non-memory op) costs nothing extra.

This 5-stage layout is the smallest structure that (a) hides the registered
memory latency at 1 IPC and (b) keeps the critical path short for 250 MHz
(§ `timing-and-resources.md`). It is the v1 baseline; if timing forces an extra
register stage, add it as a *fixed* stage and re-record the WCET constants (§4).

### 1.1 Stage responsibilities & pipeline-register contents

| Stage | Does | Drives (combinational out) | Writes to its output reg |
|---|---|---|---|
| IF | hold PC; issue I-fetch; compute PC+4 / redirect target | `Instr_Addr,I_AS,IFetch` | `IF/ID`: {PC, Instr (from `if_data`), fetch_fault=0} |
| ID | decode, immediate-gen, regfile read, hazard/forward control, detect illegal (v1: only to NOP `wfi` legalise — see §6) | regfile read addrs | `ID/EX`: {PC, rs1v, rs2v, imm, ctrl, rd, csr_addr, is_branch/jal/jalr/load/store/mul/div/csr/system} |
| EX | ALU / bit-manip / branch-compare + target / address-gen (base+imm); launch mul/div; CSR read-modify; resolve redirect | branch taken + target → IF | `EX/MEM`: {alu_y or agen_addr, store_data, rd, ctrl, csr_wdata} |
| MEM | issue D-LMB access; form `Byte_Enable`; place store data on lanes | `Data_Addr,D_AS,Read/Write_Strobe,Byte_Enable,Data_Write` | `MEM/WB`: {alu_y or (captured `Data_Read`), rd, ctrl} |
| WB | lane-select + sign/zero-extend loads; mux ALU/CSR/PC+4/load; write GPR | regfile write port | (architectural state) |

---

## 2. Hazards, forwarding, stalls (all fixed-cycle)

### 2.1 Forwarding (no stall)
- **EX/MEM → EX** and **MEM/WB → EX** forwarding of ALU/CSR results into both
  EX operands. Covers back-to-back ALU dependencies at full rate.
- **MEM/WB → EX** also forwards a *captured load value* once it is in MEM/WB.
- A **mul/div result** is forwarded from a dedicated *registered copy* (off the
  DSP-tied result net, for in-context fmax), never combinationally — an op
  immediately dependent on a mul/div takes one fixed bubble (`P_MDUSE`, §4); the
  generic ALU-result forward stays combinational.

### 2.2 Load-use hazard (`P_LOADUSE = 2` default, data-independent)
A load produces its value at the **MEM/WB** boundary. For in-context 250 MHz the
load result is **registered** (`wl`, `dont_touch`) and the *registered* copy is
forwarded — so `Data_Read→load_ext→bypass→ALU` is never a single-cycle path. A
dependent therefore waits **two** fixed bubbles for the registered value
(`P_LOADUSE=2`, §4). The optional `CORE_PERF` build forwards the combinational
load result instead (`P_LOADUSE=1`, +7% CoreMark) but its single-cycle
IMEM-region load needs that read port banked/multicycle to close 250 MHz, so it
is OFF by default.

### 2.3 Control hazard / redirect (fixed bubble)
Branches/`jal`/`jalr` resolve in **EX** (static **not-taken** fetch in between).
On a taken redirect, squash the younger instructions and present the target to
the I-LMB. **Penalty 3 cycles** (`P_REDIR = 3`, decoupled-FIFO refetch; fixed depth),
direction-, target- and data-independent (a taken branch is a fixed 4 cycles end-to-end,
`make wcet`). No branch predictor, ever.

### 2.4 Multiply (fixed latency)
`mul/mulh/mulhsu/mulhu`: a single signed 33×33 multiply on a DSP48E2 with
registered MREG+PREG → **fixed `MUL_LAT = 4`** cycles, **operand-independent**.
EX stalls the front of the pipe for `MUL_LAT-1` bubbles.

### 2.5 Divide / remainder (fixed latency, NON-early-terminating)
`div/divu/rem/remu`: a radix-2 **restoring** iterative divider taking a
**constant `DIV_LAT = 34` cycles for every operand** (1 accept + 32 fixed steps +
1 finalize — exact, not approximate). **Must not early-terminate** — early-out
reintroduces data-dependent timing and violates the determinism contract. Division-by-zero and signed overflow (`INT_MIN / -1`)
return the ISA-mandated results in the *same* fixed latency.

### 2.6 CSR / system serialisation
CSR ops and `mret` are rare; resolve them in EX and (simplest, safe) **serialise**
by holding younger instructions for a fixed small bubble so CSR side-effects
(e.g. a write to `mstatus.MIE`, `mtvec`, `mie`) are globally visible before the
next instruction's interrupt check. Fixed cost; document the exact bubble count
at M4 in §4.

### 2.7 Bus wait (defensive, normally 0)
v1 BRAM is fixed 1-cycle, but if `IReady`/`DReady` is ever low when expected,
the **whole pipe stalls in lockstep** until ready. The WCET model assumes the
fixed 1-cycle; any real wait is added per the slave's published latency.

---

## 3. Reset & interrupt-entry behaviour

- **Reset** (synchronous, active-high): flush all stages; `PC ← C_BASE_VECTORS`;
  `mstatus.MIE ← 0`, `MPIE ← 0`, `mie ← 0`, `mip ← 0`; CSRs to defined values
  (§ CSR maps). First fetch issues the cycle after reset deasserts.
- **Interrupt entry** (machine external only): taken at the next *instruction
  boundary* when `MIE & MEIE & MEIP`. The in-flight instruction at the chosen
  boundary completes (or is squashed cleanly with `mepc` = its PC); younger
  instructions squashed; redirect to `mtvec.BASE`; CSR side-effects per §3 of
  the trap model (`mepc←PC, mcause←0x8000_000B, MPIE←MIE, MIE←0, MPP←M`).
- **`mip.MEIP` mirrors the (synchronised) input pin level** — it is *not*
  edge-latched. After `mret`, if the line is still high the trap is re-taken; if
  the host interrupt source was cleared (host write-1-clear) mid-handler, no
  spurious re-fire. (README, trap model.)

---

## 4. WCET / latency constants (the determinism contract, in numbers)

These are the published, data-independent timing constants the per-core WCET
analysis consumes — measured from simulation and frozen. Every one is constant
and operand-independent (the determinism contract).

| Symbol | Meaning | Value |
|---|---|---|
| `CPI_base` | steady-state cycles/instr (no hazard) | 1 |
| `LAT_FETCH` | fetch address→data | 1 (registered BRAM) |
| `LAT_LOAD` | load address→data | 1 (registered BRAM) |
| `P_MEMGAP` | gap before a memory access that immediately follows another | **1** (single-outstanding handshake drives one rising-edge strobe per access; the gap is the next access's rising edge — host slave / MB-V LMB requirement, §9. 0 for an isolated access) |
| `P_LOADUSE` | load-use bubble | **2** (the load result is registered (`wl`) and forwarded from the register, so `Data_Read`→`load_ext`→bypass→ALU is not a single-cycle path) |
| `P_REDIR` | taken branch/jump bubble | **3** (decoupled-FIFO refetch; fixed depth, direction/target/data-independent) |
| `MUL_LAT` | multiply latency (accept→result) | **4** (fixed latency; single signed 33×33 on DSP48E2, registered MREG+PREG — `IDLE→MUL1→MUL2→MUL3`) |
| `DIV_LAT` | divide/rem latency (constant ∀ operands) | **34** (1 accept + **32 fixed restoring steps** + 1 finalize; **non-early-terminating** — exact, identical for every operand incl. ÷0 and INT_MIN÷−1) |
| `P_MDUSE` | mul/div-result-use bubble (md result → immediately-dependent op) | 1 (the muldiv result is forwarded from a registered copy off the DSP-tied net; one fixed bubble only on this adjacency) |
| `IRQ_SYNC` | interrupt pin → `mip.MEIP` (2-FF sync) | 2 |

**Determinism verified:** `make determinism` runs an identical instruction stream
with 8 data sets (incl. div-by-0, `INT_MIN/-1`, all-zero/all-ones/alternating-bit
operands; exercises mul{,h,hsu,hu}, div/rem variants, and `clz`/`ctz`/`cpop`) —
all **286 cycles**, data-independent. `P_REDIR` is fixed by the decoupled fetch (a few
cycles of refetch latency, direction/target-independent — exact bubble count is
implementation-fixed, not operand-dependent). These constants are from the v1
RTL and Verilator sim; re-confirm against Vivado timing at M6 (fmax only — cycle
counts do not change).

**Constants validated against the RTL:** `make wcet` ([`sim/wcet/`](../sim/wcet/))
measures the per-op latency directly (slope of a K vs 2K dependent-op chain) and asserts
each against a pinned baseline, and asserts mul/div latency is **operand-invariant**
across adversarial sets. Measured dependent-use latencies (all **exact, fixed**
integers — no approximation): **div 37** (= DIV_LAT 34 + 3 dependent-issue), **mul 6**
(= MUL_LAT 4 + 2), **load-use 4**, **taken-branch 4** — i.e. the FU accept→result
constants above plus the fixed dependent-issue/forward overhead. A latency change fails
the gate and must be landed together with this table.

Recording protocol: when a change alters a constant, update this table **and**
the determinism regression's golden value (`det_check.py`).

---

## 5. Decode (ISA: `rv32im_zba_zbb_zbs_zicsr`)

The decoder produces a uniform control bundle. Encodings follow the ratified
RISC-V unprivileged ISA + Zb*; only the non-obvious (Zb*, system) are tabulated.
The standard RV32I + M encodings are taken as-is from the ISA manual.

### 5.1 Instruction classes the decoder must recognise
- **RV32I**: LUI, AUIPC, JAL, JALR, BEQ/BNE/BLT/BGE/BLTU/BGEU,
  LB/LH/LW/LBU/LHU, SB/SH/SW, ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI,
  ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND, FENCE (NOP-ok), ECALL/EBREAK.
- **M**: MUL/MULH/MULHSU/MULHU/DIV/DIVU/REM/REMU.
- **Zba**: SH1ADD, SH2ADD, SH3ADD.
- **Zbb**: ANDN, ORN, XNOR, CLZ, CTZ, CPOP, MAX, MAXU, MIN, MINU, SEXT.B,
  SEXT.H, ZEXT.H, ROL, ROR, RORI, ORC.B, REV8.
- **Zbs**: BCLR, BCLRI, BEXT, BEXTI, BINV, BINVI, BSET, BSETI.
- **Zicsr / system**: CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI, MRET, WFI.

### 5.2 System / privileged encodings (must-get-right)

| Instr | Encoding (funct12 / funct3 / opcode) | v1 behaviour |
|---|---|---|
| `ecall` | `000000000000` / `000` / `1110011` | v1 may omit precise trap (sync exception carved out, README + the §10.3 carve-out); decode as legal |
| `ebreak` | `000000000001` / `000` / `1110011` | as `ecall` (carved out) |
| `mret` | `001100000010` / `000` / `1110011` | **required**: `MIE←MPIE, MPIE←1, MPP←M, PC←mepc` |
| `wfi` | `000100000101` / `000` / `1110011` | **required, legal NOP-or-sleep — never trap** (README, trap model) |
| CSR* | funct3 ∈ {001,010,011,101,110,111} / `1110011` | Zicsr; rs1/uimm semantics per ISA |

### 5.3 Zbb unary (funct7=`0110000`, OP-IMM `0010011`, funct3=`001/101`)
`CLZ rd,rs1` (rs2-field `00000`), `CTZ` (`00001`), `CPOP` (`00010`),
`SEXT.B` (`00100`), `SEXT.H` (`00101`); `ORC.B` (funct7=`0010100`, f3=`101`,
rs2=`00111`); `REV8` (funct7=`0110100`, f3=`101`, rs2=`11000` — RV32). `ROR/ROL`
(funct7=`0110000`, f3=`101`/`001`), `RORI` (imm form). Implementer note: cross-
check every encoding against the ISA manual at M3; the table is a guide, the
manual is the authority, and **arch-test is the proof**.

> Anything the decoder does not recognise: in v1 (illegal-instruction exception
> carved out) it must resolve to a **defined, side-effect-free NOP** so the
> machine cannot wedge — *except* that all instructions of the target ISA above
> must be fully implemented. Do not silently NOP a real ISA instruction.

---

## 6. CSR file — bit maps (M-mode only)

Only the architectural bits the contract needs are live; the rest read 0.

| CSR | Addr | Live fields | Notes |
|---|---|---|---|
| `mstatus` | 0x300 | MIE[3], MPIE[7], MPP[12:11] | MPP reads `11` (M). Others WPRI/0. |
| `mie` | 0x304 | MEIE[11] | MTIE[7]/MSIE[3] read-0/tied (README, trap model). |
| `mip` | 0x344 | MEIP[11] (RO, mirrors pin) | MTIP/MSIP read-0. **Not** edge-latched. |
| `mtvec` | 0x305 | BASE[31:2], MODE[1:0] | direct mode (MODE=00); firmware only uses direct. |
| `mepc` | 0x341 | [31:1] (bit0=0) | trap PC / `mret` target. |
| `mcause` | 0x342 | Interrupt[31], code[30:0] | MEI = `0x8000_000B`. |
| `mscratch` | 0x340 | 32b | optional (README); implement (cheap, arch-test). |
| `mtval` | 0x343 | 32b | optional; writes-0 ok in v1 (sync exc carved out). |
| `mhartid` | 0xF14 | 32b RO | unused by fw; tie to core id param or 0. |
| `misa` | 0x301 | MXL=1, I, M | RO; value don't-care to fw; B not advertised. |
| `mcycle/h` | 0xB00/0xB80 | 64b counter | free-running; optional for fw. |
| `minstret/h` | 0xB02/0xB82 | 64b retired count | increment on retire; optional. |

CSR access rules: M-mode only → no privilege check needed; CSRRW/S/C with
`rs1=x0` (for S/C) must not write; CSRRWI/SI/CI use the 5-bit uimm. Writes to
read-only CSRs in v1 are NOPs (no illegal-instr trap; carved out).

---

## 7. Register file
- 32 × 32-bit GPRs, `x0` hardwired 0 (reads 0, writes discarded).
- **2 read / 1 write** per cycle. Implement as **distributed RAM (LUTRAM)** with
  two read copies (one per read port) written in parallel, or FF-array if timing
  prefers. Write-first / same-cycle read handled by the forwarding network, so
  the array itself can be read-old. (See `timing-and-resources.md` for the
  LUTRAM rationale and resource cost.)

---

## 8. Module ↔ stage map (for implementation)

> **As built:** the datapath is **integrated in `rv_core.sv`** (one module) —
> fetch FIFO, decode-read, EX forwarding/hazards, the LSU, and stall/flush are
> *not* separate files. Only the genuinely reusable combinational blocks (alu,
> bitmanip, muldiv, regfile, decode, csr) are split out.

| File | Stage(s) | Contents |
|---|---|---|
| `rv_pkg.sv` | — | params (`C_BASE_VECTORS`, `RESET_VEC`), opcode/funct enums, CSR addrs, control-bundle struct |
| `rv_decode.sv` | ID | decoder, immediate-gen, control bundle, illegal→NOP legaliser |
| `rv_regfile.sv` | ID/WB | 2R1W GPRs, write-first |
| `rv_alu.sv` | EX | base ALU (add/sub/logic/shift/compare) |
| `rv_bitmanip.sv` | EX | Zba/Zbb/Zbs ops |
| `rv_muldiv.sv` | EX | single 33×33 mul (`MUL_LAT=4`, DSP) + non-early-term restoring div |
| `rv_csr.sv` | EX/WB | CSR file + trap/interrupt control + `mip.MEIP` mirror |
| `rv_core.sv` | all | **5-stage datapath (default)**: fetch FIFO, decode-read, EX/MEM/WB, forwarding, hazards, LSU, I/D-LMB masters; expose **LMB v10 master** + `Interrupt` |
| `mbv.sv` | top | slot-in `module mbv` (exact signature, §9); wraps `rv_core` |

`rv_core.sv` presents the LMB v10 signal names exactly (README, Memory interfaces) so a host SoC's
MicroBlaze-V wrapper instantiates it unchanged.

---

## 9. Exact top-level slot-in signature (module `mbv`) — DECIDED

A host SoC instantiates its MicroBlaze-V as a module **literally named `mbv`**
with the exact port list below (the MicroBlaze-V port contract). For a host
wrapper to be reused *unchanged*, the synthesizable top of our replacement
**must be `module mbv` with this identical signature** (not a differently-named
`rv_core`). Plan: `rv_core.sv` holds the datapath; a thin `rtl/core/mbv.sv` top
presents these ports and wraps `rv_core`.

The original `mbv` IP is **VHDL** (xsim/synthesis only). A SystemVerilog `mbv`
replacement additionally lets a host wrapper elaborate under Verilator.

| Port | Dir | Width | Connected in wrapper to | Core use |
|---|---|---|---|---|
| `Clk` | in | 1 | `clk` | clock |
| `Reset` | in | 1 | `~rst_n` | **synchronous active-high** reset |
| `Interrupt` | in | 1 | host interrupt source | → `mip.MEIP` (level, no ack) |
| `Interrupt_Address` | in | 32 | `32'h0` | **ignore** (vector via `mtvec`) |
| `Interrupt_Ack` | out | 1 | unconnected | tie 0 (unused) |
| `Instr_Addr` | out | 32 | `instr_addr`→`if_addr` | fetch PC (word-aligned) |
| `Instr` | in | 32 | `instr`←`if_data` | instruction (valid next cycle) |
| `IFetch` | out | 1 | gates `if_re` | fetch active |
| `I_AS` | out | 1 | gates `if_re` | address strobe (1-cycle) |
| `IReady` | in | 1 | `iready`←`if_ready` | instr valid |
| `IWAIT` | in | 1 | `1'b0` | unused (tied off in wrapper) |
| `ICE` | in | 1 | `1'b0` | unused |
| `IUE` | in | 1 | `1'b0` | unused |
| `Data_Addr` | out | 32 | `data_addr`→host data slave | byte address |
| `Data_Read` | in | 32 | `data_read`←host data slave | read data (valid next cycle) |
| `Data_Write` | out | 32 | `data_write`→host data slave | write data |
| `D_AS` | out | 1 | `d_as`→host data slave | address strobe (1-cycle) |
| `Read_Strobe` | out | 1 | host data slave | read access |
| `Write_Strobe` | out | 1 | host data slave | write access |
| `DReady` | in | 1 | `dready`←host data slave | access complete |
| `DWait` | in | 1 | host data slave | unused (tie/ignore) |
| `DCE` | in | 1 | host data slave | unused |
| `DUE` | in | 1 | host data slave | unused |
| `Byte_Enable` | out | 4 | `byte_enable`→`d_be` | byte lanes (slave honours, §5.4) |
| `Dbg_Clk` | in | 1 | `1'b0` | debug — ignore |
| `Dbg_TDI` | in | 1 | `1'b0` | debug — ignore |
| `Dbg_TDO` | out | 1 | unconnected | tie 0 |
| `Dbg_Reg_En` | in | 8 | `8'h0` | debug — ignore |
| `Dbg_Shift` | in | 1 | `1'b0` | debug — ignore |
| `Dbg_Capture` | in | 1 | `1'b0` | debug — ignore |
| `Dbg_Update` | in | 1 | `1'b0` | debug — ignore |
| `Dbg_Trig_In` | out | 1 | unconnected | tie 0 |
| `Dbg_Trig_Ack_In` | in | 8 | `8'h0` | debug — ignore |
| `Dbg_Trig_Out` | in | 8 | `8'h0` | debug — ignore |
| `Dbg_Trig_Ack_Out` | out | 1 | unconnected | tie 0 |
| `Debug_Rst` | in | 1 | `~rst_n` | debug reset — ignore |
| `Dbg_Disable` | in | 1 | `1'b1` | debug disabled — ignore |

Notes (host wrapper mapping):
- **Reset is active-high** (`~rst_n`) — matches README (Clock & reset).
- **Instruction fetch is from a host dual-port instruction memory** (Port A);
  firmware preloaded via `IMEM_INIT`/`MEMFILE`, (re)loadable via Port B.
  `IWAIT/ICE/IUE` are tied 0 in the host wrapper, so the core can ignore them.
- The wrapper mapping `if_re = i_as & ifetch` confirms README (instruction bus).
- The core sees a **single `Interrupt`** bit (the host interrupt source); any
  host-side interrupt aggregation/id signals are **not** core-facing.
- Debug ports must **exist** (exact names/widths above) for an unchanged host
  wrapper to bind, but are functionally **omitted** in v1: drive all debug
  outputs to 0, ignore all debug inputs (`Dbg_Disable=1`).

> Debug port **directions/widths** above are inferred from a host wrapper's
> connections (constant-driven ⇒ input, empty `()` ⇒ unconnected output). They
> match the MicroBlaze-V IP; if the generated IP's component declaration differs
> on any debug pin, the IP declaration is authoritative — adjust the `mbv.sv`
> top to match (the functional pins I/D-LMB + interrupt are certain).

### Data-LMB handshake — the host data-slave contract
A typical host adapter is a **pure pass-through**; the registered 1-cycle
response lives **in the host data slave**, not the adapter:
- `d_we = D_AS & Write_Strobe`, `d_re = D_AS & Read_Strobe`, `d_addr=Data_Addr`,
  `d_wdata=Data_Write`, `d_be=Byte_Enable` — all **combinational**.
- `Data_Read = d_rdata`, `DReady = d_ready` — pass-through; the **host registers**
  them so they arrive the cycle *after* the strobe. `DWait/DCE/DUE = 0`.

Implications for the core's LSU (these are hard requirements, not guesses):
1. **`D_AS` must be a 1-cycle pulse, with a clean RISING EDGE, per access** (so
   `d_we`/`d_re` are single write/read strobes). The host slave starts an access on
   the rising edge (e.g. a host tile with `rd_start = d_re & ~d_re_q`, which
   *registers the read word on that edge*) and holds `DReady` while the strobe stays
   asserted. **Holding `D_AS` high across back-to-back accesses edges only once, so
   every access after the first re-reads the first word.** The LSU therefore implements a **single-outstanding
   handshake**: drive one strobe pulse, wait for `DReady`, complete; a *consecutive*
   access waits one cycle so its strobe is a fresh rising edge (`P_MEMGAP=1`, §4).
2. **`Data_Addr`/`Data_Write`/`Byte_Enable` must be held stable** from the strobe
   cycle until `DReady` — the slave latches the request and replies next cycle
   ("MB-V holds ABus until ready"). The LSU presents the request, then waits for
   `DReady`+`Data_Read`. This matches the registered-BRAM-as-pipe-register model in §1.
3. A combinational/zero-wait response would deliver read data a cycle early and
   **corrupt execution** — the negative test in `verification.md` §2 guards this.

This is exactly MicroBlaze-V's own LMB behaviour, which is why the core slots in
unchanged. `tb/models/lmb_bram.sv` reproduces both the level-ready registered slave
(default) and, with `+dedge=1`, a host tile's **edge-detect + held-ready** slave
(`make lmb-contract` exercises level / edge-detect / back-pressure).

> **Byte-enable — RESOLVED (the byte-enable decision (§9)): the host data slave honours `d_be`.**
> The data slave is expected to mask write lanes by `d_be` (host-side, out of
> our scope). The core therefore drives correct `Byte_Enable` and does **no
> RMW**. ⚠️ **Integration requirement:** if the host data slave does not honour
> `d_be`, sub-word stores (`sb`/`sh`) will clobber adjacent bytes — the host
> must mask lanes by the asserted byte enables.

### Host integration
The host SoC supplies the instruction/data memories and slaves that bind to the
LMB v10 ports above. For standalone verification, the unit TB (`tb/tb_top.sv`) +
`tb/models/lmb_bram.sv` model the registered 1-cycle slave behaviour.
