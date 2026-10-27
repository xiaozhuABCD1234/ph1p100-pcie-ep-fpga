# =============================================================================
# run_t03.ps1 -- r3 T03 70 B oracle through the slot store and the pusher
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\run_t03.ps1
# Exit: 0 = TB ran, 3 = timeout, 4 = missing file, 6 = compile error
# =============================================================================
param(
    [int]$TimeoutMin = 5,
    [switch]$NoCompile
)
$ErrorActionPreference = "Stop"
$sim  = $PSScriptRoot
$R3   = (Resolve-Path (Join-Path $sim "..")).Path
$ms   = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$env:Path = "$ms;" + $env:Path
$dump = Join-Path $sim "t03map"
New-Item -ItemType Directory -Force -Path $dump | Out-Null

$files = @(
    "$R3\rtl\ref\common\TLP_FMT_TYPE.v",
    "$R3\rtl\ref\common\BDF.v",
    "$R3\rtl\a1_core_fix01\a1_ddr_slot_store.v",
    "$R3\rtl\ref\ep_side\ddr\ddr_frame_pusher.v",
    "$R3\tb\tb_t03_pusher_map.v"
)

Push-Location $sim
try {
    if (-not $NoCompile) {
        if (-not (Test-Path work)) { & "$ms\vlib.exe" work | Out-Null }
        $missing = @($files | Where-Object { -not (Test-Path $_) })
        if ($missing.Count -ne 0) {
            $missing | ForEach-Object { Write-Output "MISSING $_" }
            exit 4
        }
        & "$ms\vlog.exe" -quiet -work work @files 2>&1 |
            Tee-Object -FilePath (Join-Path $sim "compile_t03.log") | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Output "COMPILE_FAILED"; exit 6 }
        Write-Output "COMPILE_OK"
    }

    Copy-Item -Force (Join-Path $R3 "evidence\t03\stream.mem") (Join-Path $dump "t03_stream.mem")
    Copy-Item -Force (Join-Path $R3 "evidence\t03\rtl-slot-read.bin") (Join-Path $dump "rtl-slot-read.bin")
    $wlink = Join-Path $dump "work"
    if (-not (Test-Path $wlink)) {
        New-Item -ItemType Junction -Path $wlink -Target (Join-Path $sim "work") | Out-Null
    }
    $do = Join-Path $sim "run_t03.do"
    $doLines = @("cd {$(($dump -replace '\\','/'))}", "vsim work.tb_t03_pusher_map", "run -all", "quit -f")
    Set-Content -Path $do -Value $doLines -Encoding ascii

    $log = Join-Path $dump ("t03_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
    $p = Start-Process -FilePath "$ms\vsim.exe" -ArgumentList ('-c -quiet -do "do ' + ($do -replace '\\','/') + '"') `
        -WorkingDirectory $sim -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
    if (-not $p.WaitForExit($TimeoutMin * 60 * 1000)) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Write-Output "SIM_TIMEOUT t03"
        exit 3
    }
    Get-Content $log | Where-Object { $_ -match "T03_|Error|error|Warning" } | Write-Output
    Write-Output "SIM_LOG=$log"
    exit 0
} finally {
    Pop-Location
}
