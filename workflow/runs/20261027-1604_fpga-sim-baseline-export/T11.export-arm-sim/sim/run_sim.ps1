# run_sim.ps1 -- T11.export-arm-sim single entry (compile -> run -> report -> exit code)
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\run_sim.ps1 -Scen 0 -Tag before-fix
# Exit codes: 0 = scenario markers PASS, 3 = timeout, 6 = compile error, 7 = scenario FAIL
param(
    [int]$Scen = 0,
    [string]$Test = "tb_brd_g1_top",
    [int]$TimeoutMin = 5,
    [string]$Tag = "",
    [int]$Nf = 0,
    [switch]$NoCompile
)
$ErrorActionPreference = "Stop"
$sim = $PSScriptRoot
$root = Split-Path $sim -Parent
$logDir = Join-Path $sim "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$env:Path = "D:\intelFPGA\18.1\modelsim_ase\win32aloem;" + $env:Path
if ($Tag -eq "") { $Tag = "scen$Scen" }
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$log = Join-Path $logDir ("{0}_{1}_{2}.log" -f $Tag, $Scen, $stamp)

Push-Location $sim
try {
    if (-not (Test-Path "work")) { vlib work | Out-Null }
    if (-not $NoCompile) {
        & vlog -quiet -work work -f sources.f 2>&1 | Tee-Object -FilePath (Join-Path $logDir ("compile_{0}.log" -f $stamp)) | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Output "COMPILE_FAILED log=$logDir\compile_$stamp.log"; exit 6 }
        Write-Output "COMPILE_OK"
    }
    $vsim = Join-Path $env:Path.Split(';')[0] "vsim.exe"
    # a .do file avoids the Start-Process argument-array flattening that would
    # otherwise split "quit -f" into two argv entries
    $doFile = Join-Path $sim "run_all.do"
    Set-Content -Path $doFile -Value @("run -all", "quit -f") -Encoding ASCII
    $a = @("-c", "-quiet", "-voptargs=+acc", "-do", $doFile, "work.$Test", "+SCEN=$Scen")
    if ($Nf -gt 0) { $a += "+NF=$Nf" }
    $p = Start-Process -FilePath $vsim -ArgumentList $a -WorkingDirectory $sim `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
    $ok = $p.WaitForExit($TimeoutMin * 60 * 1000)
    if (-not $ok) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Write-Output "SIM_TIMEOUT test=$Test scen=$Scen minutes=$TimeoutMin log=$log"
        exit 3
    }
    $txt = Get-Content $log -Raw
    foreach ($m in [regex]::Matches($txt, '(?m)^#\s*(PASS|FAIL|POS_RESULT|NEG1_RESULT|NEG2_RESULT|NEG_RESULT|ARB_RESULT|RESULT|DBG|INFO|TB_SCEN|PAYLOAD_COMPARE|FRAME_RESULT)[^\r\n]*')) {
        Write-Output $m.Value.Trim()
    }
    Write-Output "SIM_LOG=$log"
    if ($txt -match '(?m)^#\s*(POS_RESULT|NEG1_RESULT|NEG2_RESULT|ARB_RESULT|RESULT)=FAIL') { exit 7 }
    exit 0
} finally {
    Pop-Location
}
