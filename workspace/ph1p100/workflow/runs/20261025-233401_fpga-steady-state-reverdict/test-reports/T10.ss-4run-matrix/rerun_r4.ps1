# Tester-owned independent R4 control rerun (full size, 4 frames, comp proxy/slot-free/SINK=1)
# Writes only under test-reports/T10.ss-4run-matrix/.  Hard cap 2700 s.
$ErrorActionPreference = 'Stop'
$base = 'D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-4run-matrix'
$src  = Join-Path $base 'r0\src'
$con  = Join-Path $base 'r0\content'
$work = 'D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\test-reports\T10.ss-4run-matrix\simwork'
$out  = 'D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\test-reports\T10.ss-4run-matrix\rerun'
New-Item -ItemType Directory -Force -Path $work, $out | Out-Null
$vlib = 'D:\intelFPGA\18.1\modelsim_ase\win32aloem\vlib.exe'
$vlog = 'D:\intelFPGA\18.1\modelsim_ase\win32aloem\vlog.exe'
$vsim = 'D:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe'
$status = [ordered]@{ started = (Get-Date).ToString('s'); vlib_rc = $null; vlog_rc = $null;
                      vsim_rc = $null; timed_out = $false; elapsed_s = $null; finished = $null }
Push-Location $work
try {
  & $vlib work *> (Join-Path $out 'vlib.log')
  $status.vlib_rc = $LASTEXITCODE
  $files = @('a1_raw_crop.v','a1_ddr_slot_store.v','a1_uart_export.v','camera_a1_uart_top.v',
             'cam_diag_mailbox.v','a1_frame_top.v','a1_deflate_core.v','p2_ddr_bridge.v',
             'a1_ddr_arb2.v','capture_async_fifo.v','p2_paxi_model_b11.v','a1_ddr_model.v','tb_ss_4run.v')
  $vargv = @('-sv','-work','work','+define+SIMULATION') + ($files | ForEach-Object { Join-Path $src $_ })
  & $vlog $vargv *> (Join-Path $out 'vlog.log')
  $status.vlog_rc = $LASTEXITCODE
  if ($status.vlog_rc -eq 0 -and $status.vlib_rc -eq 0) {
    $log = Join-Path $out 'r4-rerun.log'
    $argstr = '-c -lib work -l "' + $log + '" tb_ss_4run ' +
              '"+STAT=' + (Join-Path $out 'r4-rerun.stats') + '" ' +
              '"+EVT='  + (Join-Path $out 'r4-rerun.evt')  + '" ' +
              '"+HDR='  + (Join-Path $out 'r4-rerun.hdr')  + '" ' +
              '-gFRAMES=4 -gCONTENT=1 -gPACING=0 -gSINK=1 -gCAPTURE=0 ' +
              '"+RAW=' + (Join-Path $con 'comp_raw.hex') + '" ' +
              '"+VEC=' + (Join-Path $con 'comp_vec.hex') + '" ' +
              '-do "run -all; quit -f"'
    Set-Content -Encoding UTF8 (Join-Path $out 'vsim-argv.txt') $argstr
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $vsim -ArgumentList $argstr -WorkingDirectory $work -PassThru `
         -RedirectStandardOutput (Join-Path $out 'r4-rerun.stdout') `
         -RedirectStandardError  (Join-Path $out 'r4-rerun.stderr')
    $ok = $p.WaitForExit(2700000)
    $sw.Stop()
    $status.elapsed_s = [math]::Round($sw.Elapsed.TotalSeconds, 1)
    if (-not $ok) { $status.timed_out = $true; try { $p.Kill() } catch {} }
    try { $p.WaitForExit(30000) | Out-Null } catch {}
    try { $p.Refresh(); $status.vsim_rc = $p.ExitCode } catch { $status.vsim_rc = 'unavailable' }
  }
} catch {
  $status.error = $_.Exception.Message
} finally {
  Pop-Location
  $status.finished = (Get-Date).ToString('s')
  $status | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $out 'rerun-status.json')
}
