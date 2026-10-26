# =============================================================================
# run_board_b9.ps1 -- T10.b9 r0 single-shot board evidence run.
#
#   1) open the COM8 90 s capture FIRST (the listener owns the port)
#   2) run the ONE authorised SRAM download (download_sram_b9.tcl)
#   3) wait for the capture window, then parse / decode offline
#
# No Flash, no second download, no re-capture.
# =============================================================================
param(
    [int]$Secs = 90,
    [int]$OpenLeadSec = 5
)

$ErrorActionPreference = "Stop"
$pkg = "D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b9-rawstore"
$cap = Join-Path $pkg "r0\board\captures_pwr"
$log = Join-Path $pkg "r0\board\log"
New-Item -ItemType Directory -Force -Path $cap | Out-Null
New-Item -ItemType Directory -Force -Path $log | Out-Null

Write-Host "STEP1 open COM8 capture ($Secs s)"
$p = Start-Process -FilePath "python" `
    -ArgumentList @((Join-Path $pkg "r0\board\capture_com8.py"), "--port", "COM8",
                    "--baud", "115200", "--secs", "$Secs", "--outdir", $cap) `
    -RedirectStandardOutput (Join-Path $log "capture_com8.out") `
    -RedirectStandardError  (Join-Path $log "capture_com8.err") `
    -PassThru

Start-Sleep -Seconds $OpenLeadSec
if ($p.HasExited) {
    Write-Host "CAPTURE_DIED_EARLY exit=$($p.ExitCode)"
    Get-Content (Join-Path $log "capture_com8.err") -ErrorAction SilentlyContinue | Select-Object -Last 10
    exit 9
}
Write-Host "STEP1 OK capture running pid=$($p.Id)"

Write-Host "STEP2 one SRAM download"
Push-Location (Join-Path $pkg "r0\td")
& "D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe" "download_sram_b9.tcl" *> (Join-Path $pkg "r0\board\download_sram_b9.log")
$dl = $LASTEXITCODE
Pop-Location
Write-Host "STEP2 done exit=$dl"

Write-Host "STEP3 wait for the capture window to close"
$p.WaitForExit()
$cap_rc = $p.ExitCode
Write-Host "STEP3 capture exit=$cap_rc"
Get-Content (Join-Path $log "capture_com8.out") -ErrorAction SilentlyContinue | Select-Object -Last 3

if ($dl -ne 0) { Write-Host "DOWNLOAD_FAILED_NO_RETRY"; exit 2 }
if ($cap_rc -ne 0) { Write-Host "CAPTURE_EMPTY"; exit 3 }
Write-Host "BOARD_RUN_OK"
exit 0
