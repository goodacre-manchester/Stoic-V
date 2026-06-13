# Stoic-V — Setup & Verification Run Guide (fresh clone → run every gate)

How to set up a clone of this repo and run **every** test/verification/perf/timing
gate. Read [`verification.md`](verification.md) for *what each gate proves* and the
methodology (this guide is the *how to install and run*); read [`CLAUDE.md`](../CLAUDE.md)
for the golden rules + autonomous-resume protocol; apply the **conformance carve-out**
(below) so expected failures aren't mistaken for core bugs.

## Verification tiers (run what your environment supports)

| Tier | Gates (`make -C sim …`) | Needs | Where |
|---|---|---|---|
| **0 — portable** | `lint` `test` `determinism` (= `ci`) | Verilator + binutils + python3 | anywhere (incl. the GitHub Actions runner) |
| **1 — functional signoff** | `riscv-tests` `archtest` `cosim` `cosim-fw` `scoreboard` `sva` `formal` `crv` `lmb-contract` `irq-stress` `dmem-matrix` `wcet` `coverage` (`ci-full` = tier0 + these) | + RISC-V GCC (incl. C), Spike, RISCOF, riscv-tests, riscv-arch-test, dtc, **yosys + z3** (for `formal`) | WSL (Spike won't build on native Windows) |
| **2 — performance** | `coremark` `embench` | + xPack `riscv-none-elf-gcc` (newlib), CoreMark + Embench sources | WSL |
| **3 — timing** | `synth` | Vivado UltraScale+ | native (Windows/Linux), **not** WSL |
| **4 — second simulator** | `xsim` | Vivado xsim **+** WSL riscv toolchain (for hex) | native Windows (`pwsh sim/xsim/run_xsim.ps1`); drives WSL for hex |

Tier 0 is the cloud CI (`.github/workflows/ci.yml`) and runs on every push. The
heavy tiers run locally. On a Windows host: tiers 1–2 in **WSL Ubuntu-24.04**, tiers
3–4 in **native Vivado** (tier 4 also calls WSL to assemble the test hex). Tier 4 is
the catch-net for Verilator↔xsim semantic divergences (the 2026-06 forwarding bug
class) that the Verilator-only tiers cannot see — run it on any forwarding/hazard/bus
RTL change (`docs/verification.md` §4.1).

## Install

### Tier 0 — portable (apt)
```bash
sudo apt-get update
sudo apt-get install -y verilator binutils-riscv64-unknown-elf python3
make -C sim ci          # lint + directed tests + determinism (8×286)
```

### Tier 1 — functional signoff (WSL Ubuntu-24.04)
```bash
# RISC-V GCC + device-tree compiler (Ubuntu apt; gcc 13.2)
sudo apt-get install -y gcc-riscv64-unknown-elf device-tree-compiler

# Spike (golden ISS) -> ~/riscv-tools  (matches the gates' default SPIKE_BIN)
git clone https://github.com/riscv-software-src/riscv-isa-sim ~/src/riscv-isa-sim
cd ~/src/riscv-isa-sim && mkdir build && cd build
../configure --prefix=$HOME/riscv-tools && make -j"$(nproc)" && make install

# RISCOF -> ~/riscof-venv  (matches the gates' default VENV)
python3 -m venv ~/riscof-venv && ~/riscof-venv/bin/pip install riscof

# test suites
git clone https://github.com/riscv-software-src/riscv-tests ~/src/riscv-tests
git clone https://github.com/riscv-non-isa/riscv-arch-test ~/src/riscv-arch-test
cd ~/src/riscv-arch-test && git checkout old-framework-3.x
```

### Tier 2 — performance (WSL)
```bash
# xPack riscv-none-elf-gcc 15.2 (ships newlib headers the kernels need) -> ~/opt
mkdir -p ~/opt && cd ~/opt
wget https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz
tar xzf xpack-riscv-none-elf-gcc-15.2.0-1-linux-x64.tar.gz

# benchmark sources
git clone https://github.com/eembc/coremark      ~/src/coremark
git clone https://github.com/embench/embench-iot  ~/src/embench-iot
```

### Tier 3 — timing (native Vivado)
Install **Vivado** (UltraScale+ device support; the build was characterised on
**2025.2.1**). No WSL — `vivado` must be on PATH (Linux) or run the `.bat` directly
(Windows). Default part `xczu9eg-ffvb1156-2-e` (ZCU102, -2).

## Environment contract (override any default)

Every gate keys off overridable variables; the defaults match the install paths above.

| Var | Default | Used by |
|---|---|---|
| `SPIKE_BIN` | `~/riscv-tools/bin` | cosim, archtest, riscv-tests, lmb-contract, irq-stress, coverage |
| `VENV` | `~/riscof-venv` | archtest |
| `RVT` | `~/src/riscv-tests` | riscv-tests, cosim, lmb-contract, coverage |
| `ARCHTEST` | `~/src/riscv-arch-test` (branch `old-framework-3.x`) | archtest, coverage |
| `CM` | `~/src/coremark` | coremark |
| `EMB` | `~/src/embench-iot` | embench |
| `CM_PREFIX` / `CM_BIN` | `riscv64-unknown-elf` / *(empty)* | coremark, embench — set to `riscv-none-elf` / `~/opt/xpack-…/bin` for the xPack toolchain |

## Run everything

```bash
# Tier 0 — anywhere
make -C sim ci

# Tiers 1 — full functional signoff (WSL). From Windows:
wsl -d Ubuntu-24.04 -- bash -lc "make -C /mnt/<path>/sim ci-full"
#   ci-full = lint test determinism archtest riscv-tests cosim cosim-fw scoreboard sva formal crv lmb-contract irq-stress dmem-matrix wcet
make -C sim cosim-fw          # system-level: compiled-C firmware vs Spike on +dfree (in ci-full)
make -C sim scoreboard        # randomized-slave-timing scoreboard: arch invariance vs Spike
make -C sim sva               # LMB-protocol SVA bound onto rv_core (--assert)
sudo apt-get install -y yosys z3   # one-time, for the formal target
make -C sim formal            # FORMAL proof of the LMB handshake (BMC + k-induction)
NPROG=500 make -C sim crv     # constrained-random: hazard-biased random programs vs Spike
make -C sim dmem-matrix       # dmem_stall × {IRQ/branch/muldiv} coincidence: MEI sweep on stalling slaves
make -C sim wcet              # WCET latency constants (µarch §4) + mul/div data-independence
make -C sim coverage          # per-file line coverage over the corpus

# Tier 2 — performance (WSL); the kernels need the xPack toolchain:
CM_PREFIX=riscv-none-elf CM_BIN=$HOME/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin \
  make -C sim coremark
CM_PREFIX=riscv-none-elf CM_BIN=$HOME/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin \
  make -C sim embench
#   non-default core config: add DEFS=+define+CORE_PERF TAG=<distinct> (see sim/*/README.md)

# Tier 3 — timing (native Vivado, NOT WSL)
vivado -mode batch -source vivado/build.tcl              # Linux / vivado on PATH
#   Windows: & "D:/Xilinx/2025.2.1/Vivado/bin/vivado.bat" -mode batch -source vivado/build.tcl
#   override part: -tclargs xczu7ev-ffvc1156-2-e

# Tier 4 — second simulator (native Windows Vivado xsim; calls WSL to assemble hex)
pwsh sim/xsim/run_xsim.ps1                               # all tests/*.s under xsim
#   subset: -Tests fwd_matrix,loadbase_fwd,bus_patterns ; reuse hex: -NoBuild
#   override Vivado: -VivadoBin 'D:\Xilinx\2025.2.1\Vivado\bin'
```

Expected current results (the signoff baseline): `lint` clean · `determinism` 8×286 ·
`test` 21/21 · `riscv-tests` 48/48 · `archtest` 75/75 · `cosim` 48/48 · `cosim-fw` 12/12
(compiled-C firmware vs Spike on the free-running BRAM) · `scoreboard` 128/128 (random
compliant timing, arch-invariant) · `sva` 84 runs clean · `formal` PROVEN (BMC +
k-induction) · `crv` 200/200 (constrained-random hazard-biased vs Spike, incl. CSR RMW) ·
`lmb-contract` (level / edge-detect / free-running / back-pressure PASS
incl. store→load, combinational FAIL) · `irq-stress` 99/99 · `dmem-matrix` 1410/1410 ·
`wcet` (latency constants + mul/div data-independence) · `coverage` ~90% core ·
`xsim` 21/21 (cycle-identical to Verilator) · CoreMark/MHz
1.949 / Embench 0.851 · `synth` WNS +0.167 ns @ 250 MHz OOC (2855 LUT / 1068 FF /
4 DSP48E2 / 0 BRAM; re-validated post CSR-RMW fix, still PASS — this-run +0.182 ns,
within OOC noise).

## ⚠️ Conformance carve-out — MUST apply (v1 scoped decision)

v1 omits **precise synchronous exceptions** and **assumes aligned-only access**
(README Requirements + the §10.3 carve-out). When you run official compliance, these
**will fail/hang and are EXCLUDED from signoff**:
- misaligned load/store suites (expect precise `mcause` 4/6 + `mtval`);
- illegal-instruction / other synchronous-cause trap suites (`mcause` 2/3/5/7, ecall-from-M);
- **Spike lock-step diverges on any misaligned access** (Spike completes them) — the
  in-scope programs are aligned.

**In scope (the signoff target):** the I, M, and Zba/Zbb/Zbs instruction suites, and
the directed MEI trap / `mret` / level / `wfi` behaviour. Never report "arch-test
passes" without stating this carve-out. The gate scripts (`sim/riscof/`,
`sim/cosim/`) already apply the carve-out test-list filter. Adding precise synchronous
traps later (a localised `rv_csr`/`rv_core` change that does not touch the bus
contract) would let you drop it.

## Optional — reference firmware (`fw/`)

`fw/start.S` + `firmware.c` + `link.ld` build with a RISC-V GCC
(`-march=rv32im_zba_zbb_zbs -mabi=ilp32 -mcmodel=medany -nostartfiles`) and run on
`tb_top`: boot → `wfi` → injected MEI → ISR → `mret`. It exercises the M-mode
trap/interrupt contract on the core in isolation — a reference, not a host bring-up
(host memory-map addresses are the integrator's).

## After making a change

Keep `CLAUDE.md` (Current status) and `docs/implementation-backlog.md` checkboxes
updated **in the same commit** as the work. If a change alters a WCET constant or the
golden cycle count, update [`microarchitecture.md`](microarchitecture.md) §4 **and**
`tests/det_check.py` together. Commit on `main`; **after pushing, watch the CI run to
green** (CLAUDE.md "Git / workflow"). Run the tier(s) your change touches before
pushing anything that affects RTL or the WCET/golden numbers.
