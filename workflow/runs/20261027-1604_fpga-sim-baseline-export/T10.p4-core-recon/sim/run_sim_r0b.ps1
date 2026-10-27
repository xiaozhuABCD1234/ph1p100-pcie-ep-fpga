# run_sim_r0b.ps1 - T10.p4-core-recon round0 attempt2 entry (narrowed rework).
#
# One invocation: compile the frozen closure (rtl/ unchanged, 14 files) -> run the r2
# frame-control contract testbench (tb/tb_p4_equiv_golden.v = r2 tb_img_algo_equiv_p4.v
# + token dump tap) in the r2 ready modes (+SEEDMODE=0/1/2, 2 = always ready) plus one
# repeat run of mode 0 for E4 -> independent reference-model comparison (F1/F2/F5/E4/
# abort semantics/negative control) -> exit non-zero on any FAIL.
#
# No TD / synthesis / STA / bitgen / CWC / JTAG / download / Flash.
# ModelSim work area lives under %TEMP%; only text logs/dumps stay in sim\logs.
param(
  [string]$MsPath = 'D:\intelFPGA\18.1\modelsim_ase\win32aloem',
  [int]$SimTimeoutMs = 300000
)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'rtl'))) { throw "work root not found: $root" }
$rtl  = Join-Path $root 'rtl'
$tb   = Join-Path $root 'tb'
$mdl  = Join-Path $root 'model'
$logs = Join-Path $root 'sim\logs'
$evd  = Join-Path $root 'evidence'
New-Item -ItemType Directory -Force -Path $logs, $evd | Out-Null
$env:Path = $MsPath + ';' + $env:Path

$work = Join-Path $env:TEMP ('fpga_t10_p4core_r0b_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
Write-Host "WORKDIR $work"

# ---------------------------------------------------------------- compile (rtl untouched)
Push-Location $work
try {
  & vlib work *> (Join-Path $logs 'r0b_vlib.log')
  if ($LASTEXITCODE -ne 0) { throw 'vlib work failed' }
  $files = @(Get-ChildItem $rtl -Filter *.v | Sort-Object Name | ForEach-Object { $_.FullName })
  $files += (Join-Path $tb 'tb_p4_equiv_golden.v')
  & vlog -quiet -work work @files *> (Join-Path $logs 'r0b_compile.log')
  $rc = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($rc -ne 0) { Write-Host 'COMPILE FAIL - see sim\logs\r0b_compile.log'; exit 1 }
$errs = Get-Content (Join-Path $logs 'r0b_compile.log') -ErrorAction SilentlyContinue | Select-String -Pattern '\*\* Error'
if ($errs) { $errs | ForEach-Object { Write-Host $_.Line }; Write-Host 'COMPILE FAIL'; exit 1 }
Write-Host 'COMPILE OK'

# ---------------------------------------------------------------- simulate
# (mode, tag): 2 = always ready (r2 SEEDMODE=2), 0/1 = LFSR stall patterns; tag 1 repeats mode 0 for E4
foreach ($pair in @(@(0, 0), @(1, 0), @(2, 0), @(0, 1))) {
  $sm = $pair[0]; $tg = $pair[1]
  $stem = "tokens_sm{0}_t{1}" -f $sm, $tg
  $log  = Join-Path $logs ("r0b_sim_{0}.log" -f $stem)
  $cmd  = '-c -quiet -do "run -all; quit -f" tb_img_algo_equiv_p4 +SEEDMODE=' + $sm + ' +TAG=' + $tg
  $p = Start-Process -FilePath 'vsim' -ArgumentList $cmd -WorkingDirectory $work `
                     -NoNewWindow -PassThru `
                     -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
  if (-not $p.WaitForExit($SimTimeoutMs)) {
    try { $p.Kill() } catch { }
    Write-Host ("SIM TIMEOUT SEEDMODE={0} TAG={1}" -f $sm, $tg)
    exit 1
  }
  $txt = Get-Content $log -ErrorAction SilentlyContinue
  $verr = $txt | Select-String -Pattern '\*\* Error'
  if ($verr) { $verr | ForEach-Object { Write-Host $_.Line }; Write-Host ("SIM ERROR SEEDMODE={0}" -f $sm); exit 1 }
  $ck  = ($txt | Select-String -Pattern 'CHECK_REF_NEW (PASS|FAIL)' | Select-Object -Last 1).Line
  $ver = ($txt | Select-String -Pattern 'TB_IMG_ALGO_EQUIV_P4 (PASS|FAIL)' | Select-Object -Last 1).Line
  $cnt = ($txt | Select-String -Pattern 'EQUIV_COUNTS' | Select-Object -Last 1).Line
  Write-Host ("MODE sm{0}/t{1}: {2}" -f $sm, $tg, $cnt)
  Write-Host ("MODE sm{0}/t{1}: {2}" -f $sm, $tg, $ck)
  Write-Host ("MODE sm{0}/t{1}: {2}" -f $sm, $tg, $ver)
  $dump = Join-Path $work ("{0}.txt" -f $stem)
  if (Test-Path $dump) { Copy-Item $dump (Join-Path $logs ("{0}.txt" -f $stem)) -Force }
  else { Write-Host ("DUMP MISSING {0}" -f $stem); exit 1 }
  if (-not $ck -or $ck -notmatch 'CHECK_REF_NEW PASS') {
    Write-Host ("CHECK_REF_NEW FAIL SEEDMODE={0} TAG={1} (base-vs-candidate token mismatch)" -f $sm, $tg)
    exit 2
  }
  if (-not $ver -or $ver -notmatch 'TB_IMG_ALGO_EQUIV_P4 PASS') {
    Write-Host ("TB FAIL SEEDMODE={0} TAG={1}" -f $sm, $tg)
    exit 1
  }
}

# ---------------------------------------------------------------- independent model comparison
$pyout = & python (Join-Path $mdl 'compare_p4b.py') --dir $logs --out $evd 2>&1
$pyrc = $LASTEXITCODE
$pyout | ForEach-Object { Write-Host $_ }
if ($pyrc -ne 0) { Write-Host 'COMPARE FAIL (model/compare_p4b.py)'; exit 1 }

Write-Host 'T10_P4_CORE_RECON_R0B SIM PASS'
exit 0
