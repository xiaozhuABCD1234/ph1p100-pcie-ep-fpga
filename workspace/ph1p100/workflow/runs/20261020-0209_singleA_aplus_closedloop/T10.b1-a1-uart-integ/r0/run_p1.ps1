# =============================================================================
# run_p1.ps1 -- T10.b1-a1-uart-integ r0 P1 offline integration run
#   vlog -> vsim per case -> python decode/verify.  No TD, no bitgen, no board.
# Every external command has an executable timeout.
# =============================================================================
param(
    [string]$Root = "",
    [int]$SimTimeoutFull = 900,
    [int]$SimTimeoutFault = 400,
    [string]$Only = ""
)
$ErrorActionPreference = "Stop"
if ($Root -eq "") { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path }
$py   = "C:\Program Files\Python311\python.exe"
$msim = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$rel  = "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b1-a1-uart-integ\r0"
$run  = Join-Path $Root $rel
New-Item -ItemType Directory -Force -Path $run, "$run\logs", "$run\captures", "$run\decoded" | Out-Null

$substDrive = "P"
$used = (Get-PSDrive -PSProvider FileSystem).Name
if ($used -contains $substDrive) { subst "${substDrive}:" /D 2>$null | Out-Null }
subst "${substDrive}:" $Root | Out-Null
$X    = "${substDrive}:"
$Xrun = "$X\" + $rel
$env:PATH = "$msim;" + $env:PATH

$exitLog = Join-Path $run "logs\exitcodes.txt"
"# exit codes / timeouts (full ${SimTimeoutFull}s, fault ${SimTimeoutFault}s)" | Set-Content $exitLog -Encoding utf8

function Log-Exit([string]$what, [int]$code, [string]$detail) {
    Add-Content $exitLog ("{0}`texit={1}`t{2}`t{3}" -f $what, $code, (Get-Date -Format o), $detail)
}
function Run-Tool([string]$exe, [string[]]$argv, [string]$tag, [string]$stdout, [string]$stderr, [int]$timeoutSec) {
    $p = Start-Process -FilePath $exe -ArgumentList $argv -NoNewWindow -PassThru `
         -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $exited = $p.WaitForExit($timeoutSec * 1000)
    if (-not $exited) {
        try { $p.Kill() } catch {}
        Log-Exit $tag 124 "TIMEOUT after ${timeoutSec}s"
        return 124
    }
    Log-Exit $tag $p.ExitCode "stdout=$stdout stderr=$stderr"
    return [int]$p.ExitCode
}

# ---------------------------------------------------------------- compile
Push-Location $X
if (-not (Test-Path "$Xrun\work")) { & vlib "$Xrun\work" | Out-Null }
$files = @(
  "$X\fpga\csi2\src\a1\a1_raw_crop.v",
  "$X\fpga\csi2\src\a1\a1_ddr_slot_store.v",
  "$X\fpga\csi2\src\a1\a1_ddr_arb2.v",
  "$X\fpga\csi2\src\a1\a1_uart_export.v",
  "$X\fpga\csi2\src\a1\camera_a1_uart_top.v",
  "$X\fpga\csi2\src\mem\capture_async_fifo.v",
  "$X\upstream\ph1p100-pcie-ep-fpga\rtl\ep_side\codec\a1_deflate_core.v",
  "$X\upstream\ph1p100-pcie-ep-fpga\rtl\ep_side\codec\a1_frame_top.v",
  "$Xrun\sim\a1_ddr_model.v",
  "$Xrun\sim\tb_camera_a1_uart_top.v"
)
$vlogArgs = @("-work", "$Xrun\work") + $files
& vlog @vlogArgs 2>&1 | Tee-Object -FilePath (Join-Path $run "logs\vlog.log") | Out-Null
Log-Exit "vlog" $LASTEXITCODE "work"
if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "VLOG FAILED"; exit 2 }
Pop-Location

$cases = @(
  @{ name = "full_grad";   mode = 0; gen = @("-gUART_DIV=1", "-gAW_GAP=2", "-gR_GAP=3"); t = $SimTimeoutFull },
  @{ name = "full_incomp"; mode = 1; gen = @("-gUART_DIV=1", "-gAW_GAP=3", "-gR_GAP=4"); t = $SimTimeoutFull },
  @{ name = "fault";       mode = 2; gen = @("-gCAM_W=128", "-gCAM_H=16", "-gROI_X=0", "-gROI_Y=0", "-gW=64", "-gH=8", "-gUART_DIV=200", "-gAW_GAP=2", "-gR_GAP=3", "-gLINE_GAP=12", "-gFRAME_GAP=200"); t = $SimTimeoutFault }
)

foreach ($c in $cases) {
    if ($Only -ne "" -and $Only -ne $c.name) { continue }
    $cap  = "$Xrun\captures\$($c.name).dec"
    $stat = "$Xrun\captures\$($c.name).stats"
    Remove-Item -Path (Join-Path $run "captures\$($c.name).dec") -ErrorAction SilentlyContinue
    $vargs = @("-c", "-lib", "$Xrun\work", "-l", "$Xrun\logs\sim_$($c.name).log") + $c.gen +
             @("tb_camera_a1_uart_top", "+MODE=$($c.mode)", "+OUT=$cap", "+STAT=$stat") +
             @('-do "run -all; quit -f"')
    $rc = Run-Tool "vsim" $vargs "vsim:$($c.name)" `
          (Join-Path $run "logs\sim_$($c.name).stdout.log") `
          (Join-Path $run "logs\sim_$($c.name).stderr.log") $c.t
    if ($rc -ne 0) { Write-Host "SIM FAIL $($c.name) rc=$rc" }
}

# ---------------------------------------------------------------- verify
$rc = Run-Tool $py @((Join-Path $X "tools\a1\verify_p1.py"), $run) `
      "python verify_p1.py" (Join-Path $run "logs\verify.log") (Join-Path $run "logs\verify.err") 900
Get-Content (Join-Path $run "logs\verify.log") | Write-Host
if (-not (Test-Path (Join-Path $run "result.json"))) {
    Write-Host "VERIFY PRODUCED NO RESULT rc=$rc"
    Get-Content (Join-Path $run "logs\verify.err") | Write-Host
    exit 4
}
$vj = Get-Content (Join-Path $run "result.json") -Raw | ConvertFrom-Json
if ($rc -ne 0 -or $vj.verdict -ne "PASS") {
    Write-Host "VERIFY FAILED rc=$rc verdict=$($vj.verdict)"
    Get-Content (Join-Path $run "logs\verify.err") | Write-Host
    exit 4
}
Write-Host "P1 INTEGRATION PASS"
exit 0
