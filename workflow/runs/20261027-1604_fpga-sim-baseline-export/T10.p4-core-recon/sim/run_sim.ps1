# run_sim.ps1 - task T10.p4-core-recon (candidate P4.core-recon-r0) one-shot entry.
#
# One invocation: compile the frozen closure -> run the golden/differential testbench in
# normal-ready mode (+BP=0) and backpressure mode (+BP=1) -> run the independent Python
# reference-model comparison -> exit non-zero on any FAIL.
#
# Work area (ModelSim library, transcript, .wlf) is created under %TEMP%, never inside the
# deliverable tree.  Logs and token dumps stay in <work root>\sim\logs (text only).
# No TD / synthesis / STA / bitgen / CWC / JTAG / download / Flash.
param(
  [string]$MsPath = 'D:\intelFPGA\18.1\modelsim_ase\win32aloem',
  [int]$SimTimeoutMs = 300000
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'rtl'))) { throw "work root not found (rtl/ missing): $root" }
$rtl  = Join-Path $root 'rtl'
$tb   = Join-Path $root 'tb'
$mdl  = Join-Path $root 'model'
$logs = Join-Path $root 'sim\logs'
$evd  = Join-Path $root 'evidence'
New-Item -ItemType Directory -Force -Path $logs, $evd | Out-Null
$env:Path = $MsPath + ';' + $env:Path

$work = Join-Path $env:TEMP ('fpga_t10_p4core_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
Write-Host "WORKDIR $work"

# ---------------------------------------------------------------- compile
Push-Location $work
try {
  & vlib work *> (Join-Path $logs 'vlib.log')
  if ($LASTEXITCODE -ne 0) { throw 'vlib work failed' }
  $files = @(Get-ChildItem $rtl -Filter *.v | Sort-Object Name | ForEach-Object { $_.FullName })
  $files += (Join-Path $tb 'tb_p4_core_golden.v')
  & vlog -quiet -work work @files *> (Join-Path $logs 'compile.log')
  $rc = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($rc -ne 0) {
  Write-Host 'COMPILE FAIL - see sim\logs\compile.log'
  exit 1
}
$errs = Get-Content (Join-Path $logs 'compile.log') -ErrorAction SilentlyContinue | Select-String -Pattern '\*\* Error'
if ($errs) { Write-Host 'COMPILE FAIL (errors in log)'; exit 1 }
Write-Host 'COMPILE OK'

# ---------------------------------------------------------------- simulate
foreach ($m in 0, 1) {
  $tok = Join-Path $logs ("tokens_bp{0}.txt" -f $m)
  $log = Join-Path $logs ("sim_bp{0}.log" -f $m)
  # -do must reach vsim as ONE quoted argv element: build a single command line string.
  $cmd = '-c -quiet -do "run -all; quit -f" tb_p4_core_golden +BP=' + $m
  $p = Start-Process -FilePath 'vsim' -ArgumentList $cmd -WorkingDirectory $work `
                     -NoNewWindow -PassThru `
                     -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
  if (-not $p.WaitForExit($SimTimeoutMs)) {
    try { $p.Kill() } catch { }
    Write-Host ("SIM TIMEOUT BP={0} after {1} ms" -f $m, $SimTimeoutMs)
    exit 1
  }
  $txt = Get-Content $log -ErrorAction SilentlyContinue
  $err = $txt | Select-String -Pattern '\*\* Error'
  if ($err) {
    Write-Host ("SIM FAIL BP={0} (vsim errors)" -f $m)
    $err | ForEach-Object { Write-Host $_.Line }
    exit 1
  }
  $stats   = ($txt | Select-String -Pattern 'TB_STATS' | Select-Object -Last 1).Line
  $verdict = ($txt | Select-String -Pattern 'TB_P4_CORE_GOLDEN (PASS|FAIL)' | Select-Object -Last 1).Line
  # token dump is written relative to the temp run directory; keep the text copy next to the log
  $rawtok = Join-Path $work ("tokens_bp{0}.txt" -f $m)
  if (Test-Path $rawtok) { Copy-Item $rawtok $tok -Force; Write-Host ("TOKENS bp{0}: {1} bytes" -f $m, (Get-Item $tok).Length) }
  else { Write-Host ("TOKENS bp{0}: MISSING" -f $m) }
  Write-Host ("MODE bp{0}: {1}" -f $m, $stats)
  Write-Host ("MODE bp{0}: {1}" -f $m, $verdict)
  if (-not $verdict -or $verdict -notmatch 'TB_P4_CORE_GOLDEN PASS') {
    Write-Host ("SIM FAIL BP={0} (testbench verdict)" -f $m)
    exit 1
  }
}

# ---------------------------------------------------------------- independent model comparison
$pyout = & python (Join-Path $mdl 'compare_p4.py') `
                  --bp0 (Join-Path $logs 'tokens_bp0.txt') `
                  --bp1 (Join-Path $logs 'tokens_bp1.txt') `
                  --out $evd 2>&1
$pyrc = $LASTEXITCODE
$pyout | ForEach-Object { Write-Host $_ }
if ($pyrc -ne 0) { Write-Host 'COMPARE FAIL (model/compare_p4.py)'; exit 1 }

Write-Host 'T10_P4_CORE_RECON SIM PASS'
exit 0
