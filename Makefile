# Makefile — repo-root forwarder to sim/Makefile (the real build/verify driver).
# Lets the documented `make <target>` commands run from the project root; each
# just calls `$(MAKE) -C sim <target>`. See sim/Makefile and docs/verification.md.
SIM := sim

# User-facing targets (mirror sim/Makefile). `make <t>` here == `make -C sim <t>`.
FWD := lint verilate arch-sim test riscv-tests riscv-tests-directed archtest \
       archtest-directed trap-suite determinism cosim cosim-fw scoreboard sva formal crv lmb-contract irq-stress dmem-matrix wcet \
       coremark embench coverage synth xsim ci ci-full clean

.PHONY: $(FWD) help
.DEFAULT_GOAL := help

help:
	@echo "Stoic-V — run any sim target from the repo root (forwards to sim/):"
	@echo "  make ci           # portable: lint + test + determinism (Verilator only)"
	@echo "  make ci-full      # full local regression (WSL: + archtest/riscv-tests/cosim/...)"
	@echo "  make synth        # Vivado timing @ 250 MHz (Linux / Vivado-on-PATH)."
	@echo "                    #   On Windows run Vivado directly (make can't exec a .bat):"
	@echo "                    #     PowerShell:  & \"C:/Xilinx/.../vivado.bat\" -mode batch -source vivado/build.tcl"
	@echo "  (conformance/verification gates run in WSL; see CLAUDE.md / docs/verification.md)"
	@echo "available targets: $(FWD)"

$(FWD):
	@$(MAKE) -C $(SIM) $@
