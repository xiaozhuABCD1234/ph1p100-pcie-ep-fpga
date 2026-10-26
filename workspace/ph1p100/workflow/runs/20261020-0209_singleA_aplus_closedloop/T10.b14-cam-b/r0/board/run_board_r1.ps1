# =============================================================================
# run_board_r1.ps1 -- T10.b13-ddr-retry r1 single-shot board evidence run.
#
#   1) make sure NOTHING owns COM8 and no hwserver is left over
#   2) download the r1 candidate over JTAG/SRAM FIRST (COM8 closed)  [1 download]
#   3) only then open COM8 for the 150 s capture
#   4) parse v5 packets + A1U1 frames with the frozen r0 parser
#
# No Flash, no second download, no re-capture.
# =============================================================================
param(
    [int]$Secs = 150
)

$ErrorActionPreference = "Stop"
$pkg = "D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b13-ddr-retry"
$cap = Join-Path $pkg "r1\board\captures"
$log = Join-Path $pkg "r1\board\log"
$td  = Join-Path $pkg "r1\td"
$board = Join-Path $pkg "r1\board"
$parser = Join-Path $pkg "r0\board\parse_status_v5.py"
New-Item -ItemType Directory -Force -Path $cap | Out-Null
New-Item -ItemType Directory -Force -Path $log | Out-Null

Write-Host "STEP0 clear stale hwserver (COM8 must stay closed)"
Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "STEP1 SRAM download FIRST (COM8 closed)"
Copy-Item (Join-Path $board "dl_b13.tcl") (Join-Path $td "dl_b13.tcl") -Force
Push-Location $td
& "D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe" "dl_b13.tcl" *> (Join-Path $log "download_r1.log")
$dl = $LASTEXITCODE
Pop-Location
Write-Host "STEP1 done exit=$dl"
Get-Content (Join-Path $log "download_r1.log") -ErrorAction SilentlyContinue | Select-Object -Last 8

if ($dl -ne 0) { Write-Host "DOWNLOAD_FAILED_NO_RETRY"; exit 2 }
$okmark = Select-String -Path (Join-Path $log "download_r1.log") -Pattern "B13_DL_OK" -Quiet
if (-not $okmark) { Write-Host "DOWNLOAD_MARKER_MISSING_NO_RETRY"; exit 3 }

Write-Host "STEP2 release the JTAG/FTDI side, then open COM8 ($Secs s)"
Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$p = Start-Process -FilePath "python" `
    -ArgumentList @((Join-Path $board "capture_com8.py"), "--port", "COM8",
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

Write-Host "STEP4 parse v5 status + frames (frozen r0 parser)"
python $parser --in (Join-Path $cap "com8_${Secs}s.bin") --outdir $cap *> (Join-Path $log "parse_v5.out")
$pc = $LASTEXITCODE
Get-Content (Join-Path $cap "status_v5.txt") -ErrorAction SilentlyContinue | Select-Object -Last 12
Write-Host "PARSE_EXIT=$pc"
Write-Host "BOARD_RUN_DONE"
exit 0
