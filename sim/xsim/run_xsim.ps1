# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 John Goodacre
#
# run_xsim.ps1 — run the directed unit suite under Vivado xsim (Windows-native).
#
# WHY: every other functional gate runs only on Verilator. The two
# integrator-reported defects (LMB back-to-back stale read; continuous-assign
# forwarding-sensitivity gap) lived in the SEMANTIC DELTA between Verilator and
# Vivado xsim — the simulator the host SoC actually uses. Verilator computed the
# correct answer regardless of stimulus, so no Verilator vector could catch the
# forwarding bug; running the SAME programs under xsim does. This script is that
# second-simulator gate. See tb/xsim/tb_xsim.sv and docs/verification.md.
#
# FLOW (two native toolchains, like `make synth`):
#   1. WSL assembles each tests/*.s -> sim/build/<name>.hex via run_tests.py
#      --build-only (the canonical riscv64-unknown-elf toolchain).
#   2. Windows Vivado xvlog/xelab compiles the RTL + tb_top + tb_xsim ONCE, then
#      xsim replays each hex (plusargs from the test's `# SIM:` line), scoring
#      PASS/FAIL on the same stdout markers Verilator's sim_main.cpp emits.
#
# USAGE (from a Windows terminal, repo root or anywhere):
#   pwsh sim/xsim/run_xsim.ps1                       # all tests/*.s
#   pwsh sim/xsim/run_xsim.ps1 -Tests fwd_*,loadbase_fwd
#   pwsh sim/xsim/run_xsim.ps1 -NoBuild              # reuse existing sim/build/*.hex
#   pwsh sim/xsim/run_xsim.ps1 -VivadoBin 'D:\Xilinx\2025.2.1\Vivado\bin'
# Exit code 0 = all PASS, nonzero = any FAIL/TIMEOUT (gate semantics).

[CmdletBinding()]
param(
  [string[]] $Tests   = @('*'),                       # base-name globs under tests/ (no .s)
  [string]   $VivadoBin = '',                          # auto-detected if empty
  [string]   $WslDistro = 'Ubuntu-24.04',
  [string[]] $ExtraPlusargs = @(),                      # extra plusargs for EVERY test (e.g. dfree=1)
  [switch]   $NoBuild,                                 # skip WSL hex (re)build
  [switch]   $KeepWork                                 # keep sim/xsim/work after run
)
$ErrorActionPreference = 'Stop'

# ---- locate repo + vivado ----
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Tb       = Join-Path $RepoRoot 'tb'
$Rtl      = Join-Path $RepoRoot 'rtl\core'
$Build    = Join-Path $RepoRoot 'sim\build'
$Work     = Join-Path $PSScriptRoot 'work'

if (-not $VivadoBin) {
  foreach ($c in @($env:XILINX_VIVADO, 'D:\Xilinx\2025.2.1\Vivado', 'C:\Xilinx\2025.2.1\Vivado')) {
    if ($c -and (Test-Path (Join-Path $c 'bin\xvlog.bat'))) { $VivadoBin = (Join-Path $c 'bin'); break }
  }
}
if (-not $VivadoBin -or -not (Test-Path (Join-Path $VivadoBin 'xvlog.bat'))) {
  throw "Vivado xsim tools not found. Pass -VivadoBin '<...\Vivado\bin>' or set XILINX_VIVADO."
}
$xvlog = Join-Path $VivadoBin 'xvlog.bat'
$xelab = Join-Path $VivadoBin 'xelab.bat'
$xsim  = Join-Path $VivadoBin 'xsim.bat'
Write-Host "== Vivado xsim: $VivadoBin"

# ---- resolve the test list (base-name globs -> tests/<name>.s) ----
$srcFiles = @()
foreach ($g in $Tests) {
  $g2 = $g -replace '\.s$',''
  $srcFiles += Get-ChildItem -Path (Join-Path $RepoRoot 'tests') -Filter "$g2.s" -File -ErrorAction SilentlyContinue
}
$srcFiles = $srcFiles | Sort-Object FullName -Unique
if (-not $srcFiles) { throw "no tests matched: $($Tests -join ', ')" }
$names = $srcFiles | ForEach-Object { $_.BaseName }
Write-Host "== tests ($($names.Count)): $($names -join ', ')"

# ---- 1. build hex via WSL (canonical riscv toolchain) ----
if (-not $NoBuild) {
  # Windows path -> WSL /mnt path (done here; passing a backslash path through
  # `wsl -- wslpath` loses the separators during arg tokenisation).
  $wslRepo = '/mnt/' + $RepoRoot.Substring(0,1).ToLower() + ($RepoRoot.Substring(2) -replace '\\','/')
  $globs   = ($names | ForEach-Object { "tests/$_.s" }) -join ' '
  Write-Host "== building hex in WSL ($WslDistro): $globs"
  & wsl -d $WslDistro -- bash -lc "cd '$wslRepo' && python3 tests/run_tests.py --build-only $globs"
  if ($LASTEXITCODE -ne 0) { throw "WSL hex build failed (exit $LASTEXITCODE)" }
}

# ---- 2a. compile + elaborate ONCE ----
$null = New-Item -ItemType Directory -Force -Path $Work
Push-Location $Work
# From here we drive native Vivado tools and score them by $LASTEXITCODE, so do
# NOT let stderr-as-ErrorRecord (PS 5.1 + Stop) abort us — switch to Continue and
# gate on explicit exit-code checks / throws below.
$ErrorActionPreference = 'Continue'
try {
  # rv_pkg.sv FIRST (package), then core, mbv, tb models, tb_top, tb_xsim.
  $sources = @(
    "$Rtl\rv_pkg.sv", "$Rtl\rv_alu.sv", "$Rtl\rv_bitmanip.sv", "$Rtl\rv_regfile.sv",
    "$Rtl\rv_decode.sv", "$Rtl\rv_muldiv.sv", "$Rtl\rv_csr.sv", "$Rtl\rv_core.sv",
    "$Rtl\mbv.sv", "$Tb\models\lmb_bram.sv", "$Tb\tb_top.sv", "$Tb\xsim\tb_xsim.sv"
  ) | ForEach-Object { $_ -replace '\\','/' }

  Write-Host "== xvlog (compile) =="
  $clog = & $xvlog -sv @sources 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Write-Host $clog; throw "xvlog failed" }

  Write-Host "== xelab (elaborate tb_xsim) =="
  $elog = & $xelab work.tb_xsim -s tb_xsim_snap -timescale 1ns/1ps -debug off -relax 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Write-Host $elog; throw "xelab failed" }

  # ---- 2b. replay each hex under xsim ----
  $pass = 0; $fail = 0; $results = @()
  foreach ($src in $srcFiles) {
    $name = $src.BaseName
    $srcHex = Join-Path $Build "$name.hex"
    if (-not (Test-Path $srcHex)) {
      Write-Host ("  {0,-26} NO-HEX (build skipped?)" -f $name); $fail++; continue
    }
    # Copy the hex into the work dir and pass a BARE relative filename: xsim runs
    # with cwd = the work dir, so $readmemh resolves it, and a relative name has
    # no drive-letter colon for the batch wrapper to choke on.
    Copy-Item $srcHex (Join-Path $Work "$name.hex") -Force
    # plusargs: hex + whatever the test's `# SIM:` line carries (+max/+irq_at/...),
    # each as `--testplusarg "name=value"` (strip the leading '+').
    $plusList = @("hex=$name.hex")
    $simline = (Select-String -Path $src.FullName -Pattern '#\s*SIM:\s*(.*)' |
                Select-Object -First 1)
    if ($simline) {
      foreach ($tok in ($simline.Matches[0].Groups[1].Value -split '\s+')) {
        if ($tok -like '+*') { $plusList += $tok.TrimStart('+') }
      }
    }
    foreach ($e in $ExtraPlusargs) { if ($e) { $plusList += $e.TrimStart('+') } }
    # Run via a per-test .bat so QUOTING is fully under our control: the xsim.bat
    # wrapper splits an unquoted "name=value" arg on '=' (PowerShell's native-arg
    # quoting can't reliably stop that), but a `"name=value"` token inside a .bat
    # survives cmd's for-tokeniser intact. --runall must stay a CLI flag (it does
    # not take effect from a -f command file). Output -> xsim_one.log.
    $pa = ($plusList | ForEach-Object { "--testplusarg `"$_`"" }) -join ' '
    @('@echo off',
      "`"$xsim`" tb_xsim_snap --runall --onerror quit --onfinish quit $pa > xsim_one.log 2>&1"
     ) | Set-Content -Encoding ascii (Join-Path $Work 'run_one.bat')
    & cmd /c (Join-Path $Work 'run_one.bat') | Out-Null
    $out = Get-Content (Join-Path $Work 'xsim_one.log') -Raw -ErrorAction SilentlyContinue
    if ($out -match '(?m)^PASS\s*$') {
      $cyc = if ($out -match 'CYCLES=(\d+)') { $matches[1] } else { '?' }
      Write-Host ("  {0,-26} PASS ({1} cyc)" -f $name, $cyc); $pass++
      $results += [pscustomobject]@{ test=$name; result='PASS'; cyc=$cyc }
    } else {
      $reason = if ($out -match '(?m)^(FAIL[^\r\n]*)') { $matches[1] }
                elseif ($out -match 'TIMEOUT[^\r\n]*') { $matches[0] }
                else { 'NO-MARKER' }
      Write-Host ("  {0,-26} FAIL: {1}" -f $name, $reason); $fail++
      $results += [pscustomobject]@{ test=$name; result='FAIL'; cyc=$reason }
      Write-Host ($out -split "`n" | Select-String 'Error|FATAL|\$finish|tohost' |
                  Select-Object -First 6 | ForEach-Object { "      $_" })
    }
  }

  $total = $pass + $fail
  Write-Host ""
  Write-Host "xsim: $pass/$total passed under Vivado xsim"
  Pop-Location
  if (-not $KeepWork) { Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue }
  if ($fail -ne 0) { exit 1 } else { exit 0 }
}
catch {
  Pop-Location -ErrorAction SilentlyContinue
  Write-Host "ERROR: $_"
  exit 2
}
