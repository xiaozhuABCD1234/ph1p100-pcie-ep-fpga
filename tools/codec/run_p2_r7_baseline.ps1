# =============================================================================
# run_p2.ps1 -- T10.a1-enc-rtl P2 regression (offline, no board)
#   gen cases -> vlib/vlog -> vsim per case (+ backpressure/gap/abort/reset)
#   -> independent verifier (zlib + strict parser + Bayer inverse) -> manifest
# All paths are recorded; no download/Flash/PCIe/RK.
# =============================================================================
param(
    [string]$Root = "",
    [int]$SimTimeoutSec = 300
)
$ErrorActionPreference = "Stop"
if ($Root -eq "") { $Root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..")).Path }
$up  = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$run = Join-Path $Root "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-eng-freeze\\r7\\p2-baseline"
$py  = "C:\Program Files\Python311\python.exe"
$env:A1_P2_RUN = "r7/p2-baseline"
$msim = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
New-Item -ItemType Directory -Force -Path $run, "$run\logs", "$run\runs" | Out-Null

$substDrive = "P"
$used = (Get-PSDrive -PSProvider FileSystem).Name
if ($used -contains $substDrive) { subst "${substDrive}:" /D 2>$null | Out-Null }
subst "${substDrive}:" $Root | Out-Null
$X = "${substDrive}:"
$r3dir = Join-Path $Root "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-eng-freeze\r7"
if ((Get-PSDrive -PSProvider FileSystem).Name -contains "W") { subst W: /D 2>$null | Out-Null }
subst W: $r3dir | Out-Null
$Xrun = "W:\p2-baseline"
$env:PATH = "$msim;" + $env:PATH

$exitLog = Join-Path $run "logs\exitcodes.txt"
"# command exit codes / timeouts (single TB limit ${SimTimeoutSec}s)" | Set-Content $exitLog -Encoding utf8

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

# 1) regenerate cases (deterministic)
$genOut = Join-Path $run "logs\gen.log"
$genErr = Join-Path $run "logs\gen.err"
$rc = Run-Tool $py @((Join-Path $up "tools\codec\a1_p2_gen_r3.py")) "python a1_p2_gen_r3.py" $genOut $genErr 90
if ($rc -ne 0) { Write-Host "GEN FAILED rc=$rc"; exit $rc }

# 2) compile (vlog)
Push-Location $X
if (-not (Test-Path "$Xrun\work_p2")) { & vlib "$Xrun\work_p2" | Out-Null }
& vlog -work "$Xrun\work_p2" "$X\upstream\ph1p100-pcie-ep-fpga\rtl\ep_side\codec\a1_deflate_core.v" "$X\upstream\ph1p100-pcie-ep-fpga\sim\tb\codec\tb_a1_deflate_core.v" 2>&1 | Tee-Object -FilePath (Join-Path $run "logs\vlog.log") | Out-Null
Log-Exit "vlog" $LASTEXITCODE "work_p2"
if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "VLOG FAILED"; exit 2 }
Pop-Location

$index = Get-Content (Join-Path $run "cases\index.json") -Raw | ConvertFrom-Json
$cases = @($index.cases)

function Invoke-Case([string]$name, [string]$inName, [string]$extraArgs, [string]$tag) {
    $rd = Join-Path $run "runs\$name"
    New-Item -ItemType Directory -Force -Path $rd | Out-Null
    $vargs = @(
        "-c", "-lib", "$Xrun\work_p2",
        "-l", "$Xrun\runs\$name\sim.log",
        "tb_a1_deflate_core",
        "+IN=$Xrun\cases\$inName.hex",
        "+META=$Xrun\cases\$inName.meta",
        "+OUT=$Xrun\runs\$name\out.hex",
        "+STAT=$Xrun\runs\$name\stats.txt"
    )
    if ($extraArgs -ne "") { $vargs += $extraArgs.Split(" ") }
    $vargs += @('-do "run -all; quit -f"')
    return Run-Tool "vsim" $vargs "vsim:$tag" (Join-Path $rd "stdout.log") (Join-Path $rd "stderr.log") $SimTimeoutSec
}

$fail = 0
foreach ($c in $cases) {
    $rc = Invoke-Case $c.name $c.name "" $c.name
    if ($rc -ne 0) { $fail++; Write-Host "SIM FAIL $($c.name) rc=$rc" }
}

# backpressure + input-gap reruns on the same candidate/input
$rc = Invoke-Case "p2_frame_16x8_bp" "p2_frame_16x8" "+BP=1" "bp"
if ($rc -ne 0) { $fail++ }
$rc = Invoke-Case "p2_frame_16x8_gapbp" "p2_frame_16x8" "+BP=1 +GAP=1" "gapbp"
if ($rc -ne 0) { $fail++ }

# abort / reset mid-block: must not publish a complete frame
$rc = Invoke-Case "abort_midblock" "p2_frame_16x8" "+ABORT_AT=50" "abort"
if ($rc -ne 0) { $fail++ }
$rc = Invoke-Case "reset_midblock" "p2_frame_16x8" "+RST_AT=50" "reset"
if ($rc -ne 0) { $fail++ }

if ($fail -ne 0) { Write-Host "SIM FAILURES=$fail"; exit 3 }

# 3) independent verification
$verOut = Join-Path $run "logs\verify.log"
$verErr = Join-Path $run "logs\verify.err"
$rc = Run-Tool $py @((Join-Path $up "tools\codec\a1_p2_verify_r3.py")) "python a1_p2_verify_r3.py" $verOut $verErr 180
Get-Content $verOut
$vj = Get-Content (Join-Path $run "result.json") -Raw | ConvertFrom-Json
if ($rc -ne 0 -or $vj.verdict -ne "PASS") { Write-Host "VERIFY FAILED rc=$rc verdict=$($vj.verdict)"; exit 4 }
Write-Host "P2 REGRESSION PASS"
exit 0







