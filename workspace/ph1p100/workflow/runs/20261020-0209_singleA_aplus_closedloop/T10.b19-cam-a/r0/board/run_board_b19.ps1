# =============================================================================
# run_board_b19.ps1 -- T10.b19-cam-a r0 single-shot board evidence run.
#
#   0) FTDI preflight (VID_0403&PID_6042 + COM8, COM8 closed) -> absent: blocked, 0 downloads
#   1) clear stale hwserver (COM8 closed)
#   2) SRAM download FIRST (JTAG, volatile)    [exactly 1 download, no retry]
#   3) release JTAG, RESET ALIGNMENT window (operator pulses R14 sys_rst_n)
#   4) open COM8 for 300 s (worst-case stored frame 2,594,706 B = 225.2 s)
#   5) parse v6 packets + A1U1 frames, then apply the b19 A gate
#
# No Flash, no second download, no re-capture.
# =============================================================================
param(
    [int]$Secs = 300,
    [int]$ResetWaitSecs = 60,
    [ValidateSet("yes", "no")][string]$ResetPulse = "no"
)

$ErrorActionPreference = "Stop"
$pkg = "D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b19-cam-a"
$cap = Join-Path $pkg "r0\board\captures_a"
$log = Join-Path $pkg "r0\board\log"
$td  = Join-Path $pkg "r0\td"
$board = Join-Path $pkg "r0\board"
$parser = Join-Path $board "parse_status_v6.py"
New-Item -ItemType Directory -Force -Path $cap | Out-Null
New-Item -ItemType Directory -Force -Path $log | Out-Null
$timeline = Join-Path $log "run_timeline.txt"
function Stamp($msg) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fff"), $msg
    Add-Content -Path $timeline -Value $line
    Write-Host $line
}
"T10.b19-cam-a r0 board run" | Set-Content $timeline
Stamp "STEP0 preflight start"

# ---- STEP0: preflight, no download if absent -------------------------------
$pnp = Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_0403&PID_6042' }
$pnp | Format-List * | Out-String | Set-Content (Join-Path $log "ftdi_preflight.txt")
$present = if ($pnp) { 1 } else { 0 }
Write-Host "FTDI_PRESENT=$present"
$com = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\SERIALCOMM" -ErrorAction SilentlyContinue).PSObject.Properties
$comlist = ($com | Where-Object { $_.Value -match '^COM\d+$' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ','
Write-Host "SERIALCOMM=$comlist"
$com8free = 0
try {
    $sp = New-Object System.IO.Ports.SerialPort("COM8", 115200, "None", 8, "One")
    $sp.Open(); $com8free = 1; $sp.Close(); $sp.Dispose()
} catch { $com8free = 0 }
Write-Host "COM8_CLOSED=$com8free"
if ($present -ne 1 -or $comlist -notmatch 'COM8' -or $com8free -ne 1) {
    "FTDI_PRESENT=$present`nSERIALCOMM=$comlist`nCOM8_CLOSED=$com8free`nboard_blocked_reason=FTDI_0403:6042_or_COM8_absent_or_busy`ndownloads=0`ncaptures=0" |
        Set-Content (Join-Path $log "board_blocked.txt")
    Stamp "BOARD_BLOCKED_FTDI_OR_COM8_ABSENT_OR_BUSY"
    exit 4
}
Stamp "STEP0 preflight ok"

# ---- STEP1: clear stale hwserver, COM8 must stay closed --------------------
Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# ---- STEP2: exactly one SRAM download -------------------------------------
Stamp "STEP2 download start"
Copy-Item (Join-Path $board "dl_b19_r0.tcl") (Join-Path $td "dl_b19_r0.tcl") -Force
Push-Location $td
& "D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe" "dl_b19_r0.tcl" *> (Join-Path $log "download_b19.log")
$dl = $LASTEXITCODE
Pop-Location
Stamp "STEP2 download end exit=$dl"
Get-Content (Join-Path $log "download_b19.log") -ErrorAction SilentlyContinue | Select-Object -Last 8

if ($dl -ne 0) { Stamp "DOWNLOAD_FAILED_NO_RETRY"; exit 2 }
$okmark = Select-String -Path (Join-Path $log "download_b19.log") -Pattern "B19_DL_OK" -Quiet
if (-not $okmark) { Stamp "DOWNLOAD_MARKER_MISSING_NO_RETRY"; exit 3 }

# ---- STEP3: release JTAG, reset alignment --------------------------------
Get-Process hwserver -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$resetTxt = @(
    "reset_source=R14 sys_rst_n (board reset button)",
    "reset_pulse=$ResetPulse",
    "reset_prompt_window_s=$ResetWaitSecs",
    "download_end=$((Get-Date -Format o))",
    "note=SRAM reconfiguration already restarts the design; the operator pulse is the",
    "note=plan-required alignment and is not machine-confirmable from this session."
)
$resetTxt | Set-Content (Join-Path $log "reset_alignment.txt")
Write-Host "================================================================"
Write-Host " RESET ALIGNMENT: press board reset R14 (sys_rst_n) ONCE now."
Write-Host " Waiting $ResetWaitSecs s.  Recorded reset_pulse=$ResetPulse."
Write-Host "================================================================"
Stamp "STEP3 reset window start (R14, $ResetWaitSecs s)"
Start-Sleep -Seconds $ResetWaitSecs
Stamp "STEP3 reset window end; reset_pulse=$ResetPulse"
Start-Sleep -Seconds 2

# ---- STEP4: one 300 s COM8 capture ---------------------------------------
Stamp "STEP4 capture start ($Secs s)"
$p = Start-Process -FilePath "python" `
    -ArgumentList @((Join-Path $board "capture_com8.py"), "--port", "COM8",
                    "--baud", "115200", "--secs", "$Secs", "--outdir", $cap) `
    -RedirectStandardOutput (Join-Path $log "capture_com8.out") `
    -RedirectStandardError  (Join-Path $log "capture_com8.err") `
    -PassThru
Start-Sleep -Seconds 3
if ($p.HasExited) {
    Stamp "CAPTURE_DIED_EARLY exit=$($p.ExitCode)"
    Get-Content (Join-Path $log "capture_com8.err") -ErrorAction SilentlyContinue | Select-Object -Last 10
    exit 9
}
Write-Host "STEP4 capture running pid=$($p.Id)"
$p.WaitForExit()
Stamp "STEP4 capture end exit=$($p.ExitCode)"
Get-Content (Join-Path $log "capture_com8.out") -ErrorAction SilentlyContinue | Select-Object -Last 4

# ---- STEP5: parse + A gate ------------------------------------------------
Stamp "STEP5 parse start"
python $parser --in (Join-Path $cap "com8_${Secs}s.bin") --outdir $cap *> (Join-Path $log "parse_v6.out")
$pc = $LASTEXITCODE
Get-Content (Join-Path $cap "status_v6.txt") -ErrorAction SilentlyContinue | Select-Object -Last 14
Stamp "STEP5 parse exit=$pc"

Stamp "STEP6 board gate (reset_pulse=$ResetPulse)"
python (Join-Path $board "check_b19_board.py") $cap $ResetPulse *> (Join-Path $log "board_gate.out")
$gc = $LASTEXITCODE
Get-Content (Join-Path $cap "board_gate.txt") -ErrorAction SilentlyContinue
Stamp "GATE_EXIT=$gc"
Stamp "BOARD_RUN_DONE"
exit $gc
