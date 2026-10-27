# =============================================================================
# run_board_b10.ps1 -- T10.b10-b9-fix r0 single-shot board evidence run.
#
#   1) make sure NOTHING owns COM8 and no hwserver is left over
#   2) download the candidate over JTAG/SRAM FIRST (COM8 closed)
#   3) only then open COM8 for the 180 s capture
#   4) parse the v3 status packets and, if exported>0, decode the frames
#
# No Flash, no second download, no re-capture.
# =============================================================================
param(
    [int]$Secs = 180
)

$ErrorActionPreference = "Stop"
$pkg = "D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b10-b9-fix"
$cap = Join-Path $pkg "r0\board\captures_pwr"
$log = Join-Path $pkg "r0\board\log"
$td  = Join-Path $pkg "r0\td"
New-Item -ItemType Directory -Force -Path $cap | Out-Null
New-Item -ItemType Directory -Force -Path $log | Out-Null

Write-Host "STEP0 clear stale hwserver (COM8 must stay closed)"
Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
$holders = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "python|capture" }
if ($holders) { Write-Host "NOTE other python processes present: $($holders.Id -join ',')" }

Write-Host "STEP1 SRAM download FIRST (COM8 closed)"
Push-Location $td
& "D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe" "download_sram_b10.tcl" *> (Join-Path $log "download_sram_b10.log")
$dl = $LASTEXITCODE
Pop-Location
Write-Host "STEP1 done exit=$dl"
Get-Content (Join-Path $log "download_sram_b10.log") -ErrorAction SilentlyContinue | Select-Object -Last 6

if ($dl -ne 0) { Write-Host "DOWNLOAD_FAILED_NO_RETRY"; exit 2 }

Write-Host "STEP2 release the JTAG/FTDI side, then open COM8 ($Secs s)"
Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$p = Start-Process -FilePath "python" `
    -ArgumentList @((Join-Path $pkg "r0\board\capture_com8.py"), "--port", "COM8",
                    "--baud", "115200", "--secs", "$Secs", "--outdir", $cap) `
    -RedirectStandardOutput (Join-Path $log "capture_com8.out") `
    -RedirectStandardError  (Join-Path $log "capture_com8.err") `
    -PassThru
Start-Sleep -Seconds 3
if ($p.HasExited) {
    Write-Host "CAPTURE_DIED_EARLY exit=$($p.ExitCode)"
    Get-Content (Join-Path $log "capture_com8.err") -ErrorAction SilentlyContinue | Select-Object -Last 10
    exit 9
}
Write-Host "STEP2 OK capture running pid=$($p.Id)"
$p.WaitForExit()
Write-Host "STEP3 capture exit=$($p.ExitCode)"
Get-Content (Join-Path $log "capture_com8.out") -ErrorAction SilentlyContinue | Select-Object -Last 4
Write-Host "BOARD_RUN_DONE"
exit 0
