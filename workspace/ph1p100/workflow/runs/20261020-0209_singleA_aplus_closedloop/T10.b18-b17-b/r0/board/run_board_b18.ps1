# =============================================================================
# run_board_b18.ps1 -- T10.b18-b17-b r0 single-shot board evidence run.
#
#   0) FTDI preflight (COM8 stays closed)      -> absent: board=blocked, 0 downloads
#   1) clear stale hwserver (COM8 closed)
#   2) SRAM download FIRST (JTAG, volatile)    [exactly 1 download]
#   3) release JTAG, open COM8 for 150 s
#   4) parse v6 packets + A1U1 frames, then apply the b18 gate
#
# No Flash, no second download, no re-capture.
# =============================================================================
param(
    [int]$Secs = 150
)

$ErrorActionPreference = "Stop"
$pkg = "D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b18-b17-b"
$cap = Join-Path $pkg "r0\board\captures"
$log = Join-Path $pkg "r0\board\log"
$td  = Join-Path $pkg "r0\td"
$board = Join-Path $pkg "r0\board"
$parser = Join-Path $board "parse_status_v6.py"
New-Item -ItemType Directory -Force -Path $cap | Out-Null
New-Item -ItemType Directory -Force -Path $log | Out-Null

Write-Host "STEP0 FTDI preflight (COM8 stays closed)"
$pnp = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_0403&PID_6042' }
$pnp | Format-List * | Out-String | Set-Content (Join-Path $log "ftdi_preflight.txt")
$present = if ($pnp) { 1 } else { 0 }
Write-Host "FTDI_PRESENT=$present"
$com = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SERIALCOMM" -ErrorAction SilentlyContinue).PSObject.Properties
$comlist = ($com | Where-Object { $_.Value -match '^COM\d+$' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ','
Write-Host "SERIALCOMM=$comlist"
if ($present -ne 1 -or $comlist -notmatch 'COM8') {
    "FTDI_PRESENT=$present`nSERIALCOMM=$comlist`nboard_blocked_reason=FTDI_0403:6042_or_COM8_absent`ndownloads=0`ncaptures=0" |
        Set-Content (Join-Path $log "board_blocked.txt")
    Write-Host "BOARD_BLOCKED_FTDI_OR_COM8_ABSENT"
    exit 4
}

Write-Host "STEP1 clear stale hwserver (COM8 must stay closed)"
Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "STEP2 SRAM download FIRST (COM8 closed)"
Copy-Item (Join-Path $board "dl_b18_r0.tcl") (Join-Path $td "dl_b18_r0.tcl") -Force
Push-Location $td
& "D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe" "dl_b18_r0.tcl" *> (Join-Path $log "download_b18.log")
$dl = $LASTEXITCODE
Pop-Location
Write-Host "STEP2 done exit=$dl"
Get-Content (Join-Path $log "download_b18.log") -ErrorAction SilentlyContinue | Select-Object -Last 8

if ($dl -ne 0) { Write-Host "DOWNLOAD_FAILED_NO_RETRY"; exit 2 }
$okmark = Select-String -Path (Join-Path $log "download_b18.log") -Pattern "B18_DL_OK" -Quiet
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

Write-Host "STEP5 parse v6 status + frames"
python $parser --in (Join-Path $cap "com8_${Secs}s.bin") --outdir $cap *> (Join-Path $log "parse_v6.out")
$pc = $LASTEXITCODE
Get-Content (Join-Path $cap "status_v6.txt") -ErrorAction SilentlyContinue | Select-Object -Last 14
Write-Host "PARSE_EXIT=$pc"

Write-Host "STEP6 b18 board gate"
python (Join-Path $board "check_b18_board.py") $cap *> (Join-Path $log "board_gate.out")
$gc = $LASTEXITCODE
Get-Content (Join-Path $cap "board_gate.txt") -ErrorAction SilentlyContinue
Write-Host "GATE_EXIT=$gc"
Write-Host "BOARD_RUN_DONE"
exit 0
