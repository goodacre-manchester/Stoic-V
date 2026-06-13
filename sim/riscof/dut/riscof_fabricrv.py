# riscof_fabricrv.py — RISCOF DUT plugin for the custom RV32 core.
#
# For each test it (1) compiles the arch-test assembly to an ELF with our
# memory map (env/link.ld) and halt/signature macros (env/model_test.h), then
# (2) runs it on the Verilator model (Vtb_top) via env/run_dut.sh, which loads
# the image, drives the sim until the `tohost` store, and dumps the memory
# between begin_signature/end_signature in Spike's +signature-granularity=4
# format. RISCOF then diffs that against the Spike reference signature.
#
# Compilation always uses the full in-scope ISA (-march below); the suite is
# restricted to I/M/Zba/Zbb/Zbs upstream (the §10.3 carve-out), so every test
# only emits instructions this core implements.
import os
import logging

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()

# Full in-scope ISA. The carve-out (no Zbc/C/misaligned/sync-trap suites) is
# enforced by the isa.yaml + the restricted suite, not by per-test march.
MARCH = "rv32im_zba_zbb_zbs_zicsr"
MABI  = "ilp32"


class fabricrv(pluginTemplate):
    __model__ = "fabricrv"
    __version__ = "1.0"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get('config')
        if config is None:
            logger.error("No [fabricrv] node in config.ini")
            raise SystemExit(1)

        self.pluginpath = os.path.abspath(config['pluginpath'])
        self.isa_spec = os.path.abspath(config['ispec'])
        self.platform_spec = os.path.abspath(config['pspec'])
        # Absolute path to the Verilator-built unit sim (Vtb_top) and to the
        # repo's bin->hex converter; both come from config.ini.
        self.sim = os.path.abspath(config['sim'])
        self.genhex = os.path.abspath(config['genhex'])
        self.num_jobs = str(config.get('jobs', 1))
        self.target_run = not (config.get('target_run', '1') == '0')
        # riscv64 multilib gcc targeting rv32 (the Xilinx/Ubuntu toolchain).
        self.compiler = config.get('compiler', 'riscv64-unknown-elf-gcc')

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite
        self.compile_cmd = (
            self.compiler + ' -march=' + MARCH + ' -mabi=' + MABI +
            ' -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -g'
            ' -T ' + self.pluginpath + '/env/link.ld'
            ' -I ' + self.pluginpath + '/env/'
            ' -I ' + archtest_env +
            ' {0} -o {1} {2}')   # {0}=macros {1}=elf {2}=test.S

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)['hart0']
        self.xlen = ('64' if 64 in ispec['supported_xlen'] else '32')

    def runTests(self, testList):
        mkpath = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(mkpath):
            os.remove(mkpath)
        make = utils.makeUtil(makefilePath=mkpath)
        make.makeCommand = 'make -k -j' + self.num_jobs

        for testname in testList:
            testentry = testList[testname]
            test = testentry['test_path']
            test_dir = testentry['work_dir']
            elf = 'my.elf'
            sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")
            macros = ' -D' + " -D".join(testentry['macros'])

            compile_cmd = self.compile_cmd.format(macros, elf, test)
            if self.target_run:
                run_cmd = 'bash {0}/env/run_dut.sh {1} {2} {3} {4}'.format(
                    self.pluginpath, elf, sig_file, self.sim, self.genhex)
            else:
                run_cmd = 'echo "NO RUN"'
            execute = '@cd {0}; {1}; {2};'.format(test_dir, compile_cmd, run_cmd)
            make.add_target(execute)

        make.execute_all(self.work_dir, timeout=3600)
        if not self.target_run:
            raise SystemExit(0)
