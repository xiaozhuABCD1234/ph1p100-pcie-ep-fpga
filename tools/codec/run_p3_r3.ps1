# =============================================================================
# run_p3.ps1 -- T10.a1-frame-top P3 regression (offline, no board)
#   gen frames -> vlib/vlog -> vsim per case -> zlib + strict + Bayer verifier
# All commands have an executable timeout; no download/Flash/PCIe/RK.
# =============================================================================
param(
    [string]$Root = "",
    [int]$SimTimeoutSec = 360,
    [int]$VerifyTimeoutSec = 300
)
$ErrorActionPreference = "Stop"
if ($Root -eq "") { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path }
$up  = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$py  = "C:\Program Files\Python311\python.exe"
$msim = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$rel = "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-eng-freeze\\r3\\p3"
$run = Join-Path $Root $rel
New-Item -ItemType Directory -Force -Path $run, "$run\logs", "$run\runs" | Out-Null

$substDrive = "P"
$used = (Get-PSDrive -PSProvider FileSystem).Name
if ($used -contains $substDrive) { subst "${substDrive}:" /D 2>$null | Out-Null }
subst "${substDrive}:" $Root | Out-Null
$X = "${substDrive}:"
$Xrun = "$X\" + ($rel -replace "\\", "\")
$env:PATH = "$msim;" + $env:PATH

$exitLog = Join-Path $run "logs\exitcodes.txt"
"# command exit codes / timeouts (sim ${SimTimeoutSec}s, verify ${VerifyTimeoutSec}s)" | Set-Content $exitLog -Encoding utf8

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

# 1) generate deterministic frames + case wrappers
$rc = Run-Tool $py @((Join-Path $up "tools\codec\a1_p3_gen.py"), $Root, $run) `
      "python a1_p3_gen.py" (Join-Path $run "logs\gen.log") (Join-Path $run "logs\gen.err") 120
if ($rc -ne 0) { Write-Host "GEN FAILED rc=$rc"; Get-Content (Join-Path $run "logs\gen.err"); exit $rc }

# 2) compile
Push-Location $X
if (-not (Test-Path "$Xrun\work_p3")) { & vlib "$Xrun\work_p3" | Out-Null }
$vlogArgs = @(
  "-work", "$Xrun\work_p3",
  "$X\upstream\ph1p100-pcie-ep-fpga\rtl\ep_side\codec\a1_deflate_core.v",
  "$X\upstream\ph1p100-pcie-ep-fpga\rtl\ep_side\codec\a1_frame_top.v",
  "$X\upstream\ph1p100-pcie-ep-fpga\sim\tb\codec\tb_a1_frame_top.v",
  "$Xrun\cases\case_wrappers.v"
)
& vlog @vlogArgs 2>&1 | Tee-Object -FilePath (Join-Path $run "logs\vlog.log") | Out-Null
Log-Exit "vlog" $LASTEXITCODE "work_p3"
if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "VLOG FAILED"; exit 2 }
# lint-only pass on the new top
& vlog -lint -work "$Xrun\work_p3" "$X\upstream\ph1p100-pcie-ep-fpga\rtl\ep_side\codec\a1_frame_top.v" 2>&1 | Tee-Object -FilePath (Join-Path $run "logs\vlog-lint.log") | Out-Null
Log-Exit "vlog-lint" $LASTEXITCODE "a1_frame_top"
Pop-Location

$index = Get-Content (Join-Path $run "cases\index.json") -Raw | ConvertFrom-Json
$fail = 0
foreach ($c in $index.cases) {
    $rd = Join-Path $run ("runs\" + $c.name)
    New-Item -ItemType Directory -Force -Path $rd | Out-Null
    $vargs = @(
        "-c", "-lib", "$Xrun\work_p3",
        "-l", "$Xrun\runs\$($c.name)\sim.log",
        "tb_c_$($c.name)",
        "+MODE=$($c.mode)",
        "+IN=$Xrun\cases\$($c.name)\raw.bin",
        "+OUT=$Xrun\runs\$($c.name)\out.hex",
        "+STAT=$Xrun\runs\$($c.name)\stats.txt",
        "+PREP=$($c.prep)", "+PRED=$($c.pred)"
    )
    if ($c.PSObject.Properties.Name -contains "abort_at" -and $c.abort_at) { $vargs += "+ABORT_AT=$($c.abort_at)" }
    if ($c.PSObject.Properties.Name -contains "rst_at" -and $c.rst_at)     { $vargs += "+RST_AT=$($c.rst_at)" }
    if ($c.PSObject.Properties.Name -contains "proto_at" -and $c.proto_at) { $vargs += "+PROTO_AT=$($c.proto_at)" }
    if ($c.PSObject.Properties.Name -contains "nframes") { $vargs += "+NFRAMES=$($c.nframes)" }
    if ($c.PSObject.Properties.Name -contains "raw2") {
        $vargs += @("+IN2=$Xrun\cases\$($c.name)\raw2.bin",
                    "+OUT2=$Xrun\runs\$($c.name)\out2.hex",
                    "+PREP2=$($c.prep2)", "+PRED2=$($c.pred2)")
    }
    $vargs += @('-do "run -all; quit -f"')
    $rc = Run-Tool "vsim" $vargs "vsim:$($c.name)" (Join-Path $rd "stdout.log") (Join-Path $rd "stderr.log") $SimTimeoutSec
    if ($rc -ne 0) { $fail++; Write-Host "SIM FAIL $($c.name) rc=$rc" }
}
if ($fail -ne 0) { Write-Host "SIM FAILURES=$fail"; exit 3 }

# 3) verify
$rc = Run-Tool $py @((Join-Path $up "tools\codec\a1_p3_verify.py"), $run) `
      "python a1_p3_verify.py" (Join-Path $run "logs\verify.log") (Join-Path $run "logs\verify.err") $VerifyTimeoutSec
Get-Content (Join-Path $run "logs\verify.log")
if (-not (Test-Path (Join-Path $run "result.json"))) {
    Write-Host "VERIFY PRODUCED NO RESULT rc=$rc"
    Get-Content (Join-Path $run "logs\verify.err")
    exit 4
}
$vj = Get-Content (Join-Path $run "result.json") -Raw | ConvertFrom-Json
if ($rc -ne 0 -or $vj.verdict -ne "PASS") {
    Write-Host "VERIFY FAILED rc=$rc verdict=$($vj.verdict)"
    Get-Content (Join-Path $run "logs\verify.err")
    exit 4
}
Write-Host "P3 REGRESSION PASS"
exit 0



