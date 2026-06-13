# sim/Makefile — Verilator lint/sim driver. See docs/verification.md.
# Run from repo root as `make -C sim <target>` or from sim/.
VERILATOR ?= verilator
ROOT      := ..
RTL       := $(ROOT)/rtl/core
TB        := $(ROOT)/tb
TESTS     := $(ROOT)/tests
PY        ?= python3

# rv_pkg.sv FIRST (compiled once; no `include).
PKG  := $(RTL)/rv_pkg.sv
MBV  := $(RTL)/mbv.sv
TBSRC:= $(TB)/models/lmb_bram.sv $(TB)/tb_top.sv
CPP  := $(TB)/cpp/sim_main.cpp

VFLAGS := -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
          --top-module tb_top -I$(RTL)

EXSRC := $(RTL)/rv_core.sv

.PHONY: all lint verilate arch-sim arch-sim-combd cov-sim-unit cov-sim-arch coverage test riscv-tests riscv-tests-directed archtest archtest-directed trap-suite determinism cosim cosim-fw scoreboard sva formal crv lmb-contract irq-stress dmem-matrix wcet coremark embench synth xsim clean ci ci-full

all: verilate

CORE := $(PKG) $(RTL)/rv_alu.sv $(RTL)/rv_bitmanip.sv $(RTL)/rv_regfile.sv \
        $(RTL)/rv_decode.sv $(RTL)/rv_muldiv.sv $(RTL)/rv_csr.sv $(EXSRC) \
        $(MBV) $(TBSRC) $(CPP)

# ---- M0 gate: lint clean (core only, top = mbv) ----
lint:
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
	  -I$(RTL) --top-module mbv $(PKG) $(RTL)/rv_alu.sv $(RTL)/rv_bitmanip.sv \
	  $(RTL)/rv_regfile.sv $(RTL)/rv_decode.sv $(RTL)/rv_muldiv.sv $(RTL)/rv_csr.sv \
	  $(EXSRC) $(MBV)

# ---- build the unit simulator ----
verilate: obj_dir/Vtb_top
obj_dir/Vtb_top: $(PKG) $(RTL)/rv_alu.sv $(RTL)/rv_bitmanip.sv $(RTL)/rv_regfile.sv \
                 $(RTL)/rv_decode.sv $(RTL)/rv_muldiv.sv $(RTL)/rv_csr.sv $(EXSRC) \
                 $(MBV) $(TBSRC) $(CPP)
	$(VERILATOR) --cc --exe --build -j 0 $(VFLAGS) \
	  $(PKG) $(RTL)/rv_alu.sv $(RTL)/rv_bitmanip.sv $(RTL)/rv_regfile.sv $(RTL)/rv_decode.sv \
	  $(RTL)/rv_muldiv.sv $(RTL)/rv_csr.sv $(EXSRC) $(MBV) $(TBSRC) $(CPP) \
	  -o Vtb_top --Mdir obj_dir

# ---- roomy-memory build for official arch-test (RISCOF signature dump) ----
# 4 MiB I/D BRAM based at 0x8000_0000 with the reset PC matched to Spike, so
# PC-relative signatures (auipc/jal/jalr) compare equal. 2147483648 = 0x8000_0000.
arch-sim: obj_dir_arch/Vtb_top
obj_dir_arch/Vtb_top: $(CORE)
	$(VERILATOR) --cc --exe --build -j 0 $(VFLAGS) \
	  -GIAW=22 -GDAW=22 -GRESET_VEC=2147483648 -GMEM_BASE=2147483648 \
	  $(CORE) -o Vtb_top --Mdir obj_dir_arch

# ---- combinational-data build for the LMB negative test (COMB_D=1) ----
# Isolated so the deliberate fetch-path combinational loop never appears in the
# normal/conformance/coverage builds.
arch-sim-combd: obj_dir_combd/Vtb_top
obj_dir_combd/Vtb_top: $(CORE)
	$(VERILATOR) --cc --exe --build -j 0 $(VFLAGS) \
	  -GIAW=22 -GDAW=22 -GRESET_VEC=2147483648 -GMEM_BASE=2147483648 -GCOMB_D=1 \
	  $(CORE) -o Vtb_top --Mdir obj_dir_combd

# ---- coverage builds (line + toggle); writes coverage.dat via +covfile ----
cov-sim-unit: obj_dir_cov/Vtb_top
obj_dir_cov/Vtb_top: $(CORE)
	$(VERILATOR) --cc --exe --build -j 0 $(VFLAGS) --coverage \
	  $(CORE) -o Vtb_top --Mdir obj_dir_cov
cov-sim-arch: obj_dir_cov_arch/Vtb_top
obj_dir_cov_arch/Vtb_top: $(CORE)
	$(VERILATOR) --cc --exe --build -j 0 $(VFLAGS) --coverage \
	  -GIAW=22 -GDAW=22 -GRESET_VEC=2147483648 -GMEM_BASE=2147483648 \
	  $(CORE) -o Vtb_top --Mdir obj_dir_cov_arch

coverage:                      # RTL line+toggle coverage over the corpus. WSL.
	bash $(ROOT)/sim/coverage/run_coverage.sh

# ---- in-container directed suites (self-checking, real riscv assembler) ----
# NOTE: riscv-tests/archtest below are DIRECTED SUBSTITUTES used when Spike/
# RISCOF/riscv-gcc are unavailable. For OFFICIAL compliance, wire RISCOF + Spike
# per docs/local-resume.md and apply the conformance carve-out.
test: verilate
	$(PY) $(TESTS)/run_tests.py 'tests/*.s'

riscv-tests:                   # OFFICIAL Berkeley rv32ui+rv32um, self-checking. WSL.
	bash $(ROOT)/sim/riscv-tests/run_riscv_tests.sh

riscv-tests-directed: verilate # directed substitute (no toolchain/suite needed)
	$(PY) $(TESTS)/run_tests.py 'tests/rv32i_*.s' 'tests/rv32m_*.s'

archtest:                      # OFFICIAL RISCOF vs Spike (I/M/Zba/Zbb/Zbs, carve-out). WSL.
	bash $(ROOT)/sim/riscof/run_archtest.sh

archtest-directed: verilate    # directed Zb* substitute (no Spike/RISCOF needed)
	$(PY) $(TESTS)/run_tests.py 'tests/zb_*.s'

trap-suite: verilate
	$(PY) $(TESTS)/run_tests.py 'tests/trap_*.s'

determinism: verilate
	$(PY) $(TESTS)/det_check.py

cosim:                         # OFFICIAL Spike lock-step retire-compare. WSL.
	bash $(ROOT)/sim/cosim/run_cosim.sh

cosim-fw:                      # SYSTEM-level: compiled-C firmware vs Spike on the free-running slave (+dfree). WSL.
	bash $(ROOT)/sim/cosim-fw/run_cosim_fw.sh

scoreboard:                    # RANDOMIZED-slave-timing scoreboard: arch invariance vs Spike under +drand seed sweep. WSL.
	bash $(ROOT)/sim/scoreboard/run_scoreboard.sh

sva:                           # assertion-based verification: LMB-protocol SVA bind + --assert over the suite (Verilator only).
	bash $(ROOT)/sim/sva/run_sva.sh

formal:                        # FORMAL proof of the LMB handshake (yosys-smtbmc + z3: BMC + k-induction). WSL.
	bash $(ROOT)/sim/formal/run_formal.sh

crv:                           # CONSTRAINED-RANDOM verification: hazard-biased random programs vs Spike (NPROG/NINSTR to tune). WSL.
	bash $(ROOT)/sim/crv/run_crv.sh

coremark:                      # CoreMark/MHz (cycle-exact) on the core. WSL. OPT=-O3 ITER=10 to tune.
	bash $(ROOT)/sim/coremark/run_coremark.sh

embench:                       # Embench-IoT (cycle-exact) on the core. WSL. default 2-cycle load-use + 24/16 fit.
	bash $(ROOT)/sim/embench/run_embench.sh

# M8 synth/timing — native Vivado (UltraScale+), NOT WSL. build.tcl asserts
# WNS >= 0 @ 250 MHz + reports utilization. This `make` target works on Linux or
# when an executable `vivado` is on PATH. On Windows, `vivado` is a .bat that
# make cannot exec via CreateProcess — run Vivado directly instead, e.g.
#   PowerShell:  & "D:/Xilinx/2025.2.1/Vivado/bin/vivado.bat" -mode batch -source vivado/build.tcl
VIVADO ?= vivado
synth:
	$(VIVADO) -mode batch -nojournal -nolog -source $(ROOT)/vivado/build.tcl

# Second-simulator gate — runs the directed suite under Vivado xsim (the host's
# simulator), catching Verilator<->xsim semantic divergences Verilator cannot
# (docs/verification.md §4.1). Windows-native like `synth`: the runner is a
# PowerShell script (it drives Vivado xvlog/xelab/xsim and assembles hex via WSL).
# On Windows run it directly:
#   pwsh sim/xsim/run_xsim.ps1            (or: powershell -File sim/xsim/run_xsim.ps1)
PWSH ?= powershell
xsim:
	$(PWSH) -File $(ROOT)/sim/xsim/run_xsim.ps1

lmb-contract:                  # NEGATIVE tests: 1-cycle registered LMB is required. WSL.
	bash $(ROOT)/sim/lmb-contract/run_lmb_contract.sh

irq-stress:                    # interrupt-injection sweep (entry/return + determinism). WSL.
	bash $(ROOT)/sim/irq-stress/run_irq_stress.sh

dmem-matrix:                   # dmem_stall × {IRQ/branch/muldiv} coincidence: MEI sweep on stalling slaves. WSL.
	bash $(ROOT)/sim/dmem-matrix/run_dmem_matrix.sh

wcet:                          # WCET latency-constant validation + FU data-independence (microarchitecture §4). WSL.
	bash $(ROOT)/sim/wcet/run_wcet.sh

# `ci` is what the GitHub Actions workflow (.github/workflows/ci.yml) runs on each
# push to main (docs-only pushes are skipped via paths-ignore).
ci: lint test determinism          # portable CI (verilator only; runs anywhere)

# full local regression — needs WSL + Spike + the official suites (see CLAUDE.md)
ci-full: lint test determinism archtest riscv-tests cosim cosim-fw scoreboard sva formal crv lmb-contract irq-stress dmem-matrix wcet

clean:
	rm -rf obj_dir obj_dir_arch obj_dir_combd obj_dir_cov obj_dir_cov_arch obj_dir_sva obj_dir_dbg build
	rm -rf riscof/work riscv-tests/work cosim/work cosim-fw/work scoreboard/work formal/work crv/work lmb-contract/work irq-stress/work dmem-matrix/work wcet/work coverage/work
