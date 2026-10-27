$ErrorActionPreference = 'Stop'
$RunRoot = 'D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict'
$TaskDir = Join-Path $RunRoot 'T10.ss-steady-anchor\r0'
$TestDir = Join-Path $RunRoot 'test-reports\T10.ss-steady-anchor\r0'
$WorkRoot = 'C:\Users\czz\AppData\Local\Temp\opencode\ss-anchor-test'
$Work = Join-Path $WorkRoot 'work'
$Ms = 'D:\intelFPGA\18.1\modelsim_ase\win32aloem'
$Logs = Join-Path $TestDir 'logs'
$Caps = Join-Path $TestDir 'caps'
New-Item -ItemType Directory -Force -Path $Logs, $Caps | Out-Null

$env:MODELSIM = Join-Path $WorkRoot 'modelsim.ini'
$env:PATH = "$Ms;$env:PATH"
$status = [ordered]@{ started = (Get-Date).ToString('o'); work_lib = $Work; modelsim_ini = $env:MODELSIM; steps = @() }

function Step($name, $exe, $argv, $log, $timeout) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $exe -ArgumentList $argv -WorkingDirectory $Work -RedirectStandardOutput ($log + '.out') -RedirectStandardError ($log + '.err') -PassThru -NoNewWindow
    $timedOut = $false
    try { Wait-Process -Id $p.Id -Timeout $timeout -ErrorAction Stop } catch { $timedOut = $true }
    if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force; Start-Sleep -Seconds 2 }
    $p.Refresh()
    $sw.Stop()
    $rec = [ordered]@{ name = $name; exe = $exe; argv = $argv; cwd = $Work; rc = $p.ExitCode; timed_out = $timedOut; seconds = [math]::Round($sw.Elapsed.TotalSeconds,1); timeout_s = $timeout; log = $log }
    $script:status.steps += $rec
    return $rec
}

# 1. vlib
Step 'vlib' (Join-Path $Ms 'vlib.exe') @('work') (Join-Path $Logs 'vlib-test.log') 300 | Out-Null

# 2. vlog: exactly the frozen 13-file compile list (12 DUT/model copies + derived TB)
$src = Join-Path $TaskDir 'src'
$files = @('a1_raw_crop.v','a1_ddr_slot_store.v','a1_uart_export.v','camera_a1_uart_top.v','cam_diag_mailbox.v','a1_frame_top.v','a1_deflate_core.v','p2_ddr_bridge.v','a1_ddr_arb2.v','capture_async_fifo.v','p2_paxi_model_b11.v','a1_ddr_model.v','tb_ss_anchor.v')
$vlogArgs = @('-sv','-work','work','+define+SIMULATION') + ($files | ForEach-Object { Join-Path $src $_ })
Step 'vlog' (Join-Path $Ms 'vlog.exe') $vlogArgs (Join-Path $Logs 'vlog-test.log') 1200 | Out-Null

# 3. vsim FRAMES=2 control
$do = Join-Path $TestDir 'run_all.do'
Set-Content -Path $do -Value 'run -all' -Encoding ascii
Add-Content -Path $do -Value 'quit -f' -Encoding ascii
$stats = Join-Path $Caps 'ss2-test.stats'
$dec = Join-Path $Caps 'ss2-test.dec'
$evt = Join-Path $Caps 'ss2-test.evt'
$vargs = @('-c','-lib','work','-l',(Join-Path $Logs 'control2-test.log'),'tb_ss_anchor',"+STAT=$stats","+DEC=$dec","+EVT=$evt",'-gFRAMES=2','-do',$do)
Step 'vsim_control2' (Join-Path $Ms 'vsim.exe') $vargs (Join-Path $Logs 'control2-test.log') 2700 | Out-Null

$status.finished = (Get-Date).ToString('o')
$status | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $TestDir 'control2-test-status.json') -Encoding utf8
Write-Host ($status | ConvertTo-Json -Depth 6)
