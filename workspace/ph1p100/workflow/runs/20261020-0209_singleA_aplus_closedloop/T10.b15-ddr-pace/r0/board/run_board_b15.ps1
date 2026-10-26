# =============================================================================
# run_board_b15.ps1 -- T10.b15-ddr-pace r0 single-shot board evidence run.
#
#   0) FTDI preflight (COM8 stays closed)
#   1) make sure nothing owns COM8 and no hwserver is left over
#   2) download the r0 candidate over JTAG/SRAM FIRST (COM8 closed)  [1 download]
#   3) only then open COM8 for the 150 s capture
#   4) parse v5 packets (with rlast) + A1U1 frames, then apply the b15 gate
#
# No Flash, no second download, no re-capture.
# =============================================================================
param(
    [int]$Secs = 150
)

$ErrorActionPreference = "Stop"
$pkg = "D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b15-ddr-pace"
$cap = Join-Path $pkg "r0\board\captures"
$log = Join-Path $pkg "r0\board\log"
$td  = Join-Path $pkg "r0\td"
$board = Join-Path $pkg "r0\board"
$parser = Join-Path $board "parse_status_v5.py"
New-Item -ItemType Directory -Force -Path $cap | Out-Null
New-Item -ItemType Directory -Force -Path $log | Out-Null

Write-Host "STEP0 FTDI preflight (COM8 stays closed)"
$pnp = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_0403&PID_6042' }
$pnp | Format-List * | Out-String | Set-Content (Join-Path $log "ftdi_preflight.txt")
$present = if ($pnp) { 1 } else { 0 }
Write-Host "FTDI_PRESENT=$present"
if ($present -ne 1) {
    "FTDI_PRESENT=0`nboard_blocked_reason=FTDI_0403:6042_absent`ndownloads=0" |
        Set-Content (Join-Path $log "board_blocked.txt")
    Write-Host "BOARD_BLOCKED_FTDI_ABSENT"
    exit 4
}

Write-Host "STEP1 clear stale hwserver (COM8 must stay closed)"
Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "STEP2 SRAM download FIRST (COM8 closed)"
Copy-Item (Join-Path $board "dl_b15.tcl") (Join-Path $td "dl_b15.tcl") -Force
Push-Location $td
& "D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe" "dl_b15.tcl" *> (Join-Path $log "download_b15.log")
$dl = $LASTEXITCODE
Pop-Location
Write-Host "STEP2 done exit=$dl"
Get-Content (Join-Path $log "download_b15.log") -ErrorAction SilentlyContinue | Select-Object -Last 8

if ($dl -ne 0) { Write-Host "DOWNLOAD_FAILED_NO_RETRY"; exit 2 }
$okmark = Select-String -Path (Join-Path $log "download_b15.log") -Pattern "B15_DL_OK" -Quiet
if (-not $okmark) { Write-Host "DOWNLOAD_MARKER_MISSING_NO_RETRY"; exit 3 }

Write-Host "STEP3 release the JTAG/FTDI side, then open COM8 ($Secs s)"
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
Write-Host "STEP3 OK capture running pid=$($p.Id)"
$p.WaitForExit()
Write-Host "STEP4 capture exit=$($p.ExitCode)"
Get-Content (Join-Path $log "capture_com8.out") -ErrorAction SilentlyContinue | Select-Object -Last 4

Write-Host "STEP5 parse v5 status + frames"
python $parser --in (Join-Path $cap "com8_${Secs}s.bin") --outdir $cap *> (Join-Path $log "parse_v5.out")
$pc = $LASTEXITCODE
Get-Content (Join-Path $cap "status_v5.txt") -ErrorAction SilentlyContinue | Select-Object -Last 14
Write-Host "PARSE_EXIT=$pc"

Write-Host "STEP6 b15 board gate"
python (Join-Path $board "check_b15_board.py") $cap *> (Join-Path $log "board_gate.out")
$gc = $LASTEXITCODE
Get-Content (Join-Path $cap "board_gate.txt") -ErrorAction SilentlyContinue
Write-Host "GATE_EXIT=$gc"
Write-Host "BOARD_RUN_DONE"
exit 0
