# =============================================================================
# run_sim_r1.ps1 -- T11.BRD.P1 r1 local G1 simulation runner (ModelSim ASE)
#
# Compiles the r1 board RTL + the frozen read-only P4 r2 / img / b18 / b20
# closure from the repo handoff snapshot, then runs one scenario with a hard
# wall-clock timeout.  Repo-relative paths only; no TD, no hardware.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_sim_r1.ps1 -Test tb_brd_arb
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_sim_r1.ps1 -Test tb_brd_g1_top -Scen 0 -Prep 0 -Pred 0
# =============================================================================
param(
    [string]$Test = "tb_brd_g1_top",
    [string]$Scen = "0",
    [int]$Prep = 0,
    [int]$Pred = 0,
    [int]$TimeoutMin = 20,
    [switch]$NoCompile
)

$ErrorActionPreference = "Stop"
$sim = $PSScriptRoot
$repo = (Resolve-Path (Join-Path $sim "..\..\..\..\..\..")).Path
$ms = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$env:Path = "$ms;" + $env:Path

$R = Join-Path $repo "workflow\runs\20261027-0726_fpga-board-integration\T11.BRD.P1\r1"
$IN = Join-Path $repo "handoff\fpga-sim-only-20261027\inputs"
$BF = Join-Path $IN "board-filelist"
$P4 = Join-Path $IN "p4"

$files = @(
    "$R\rtl\ref\common\TLP_FMT_TYPE.v",
    "$R\rtl\ref\common\BDF.v",
    "$R\rtl\ref\ep_side\ddr\ddr_frame_pusher.v",
    "$R\rtl\brd_export_seq.v",
    "$R\rtl\brd_cam_fe.v",
    "$R\rtl\brd_cdc_mailboxes.v",
    "$R\rtl\brd_ddr_rd_arb.v",
    "$R\rtl\brd_a1_core_pll.v",
    "$R\rtl\a1_raw_crop.v",
    "$R\rtl\p2_ddr_bridge.v",
    "$R\rtl\brd_board_datapath.v",
    "$BF\fpga\csi2\src\mem\capture_async_fifo.v",
    "$BF\fpga\csi2\src\integrated_delivery\integrated_delivery_top.v",
    "$BF\fpga\csi2\src\integrated_delivery\integrated_input_processing_top.v",
    "$BF\fpga\csi2\src\integrated_delivery\bayer_raw10_demosaic4_p4.v",
    "$BF\fpga\csi2\src\integrated_delivery\img_algo_parallel_top_p4.v",
    "$BF\fpga\csi2\src\integrated_delivery\aplus_pcie_egress_adapter.v",
    "$BF\fpga\csi2\src\integrated_delivery\dual_channel_capture_scheduler.v",
    "$BF\fpga\csi2\src\integrated_delivery\frame_good_publish_cancel.v",
    "$BF\fpga\csi2\src\integrated_delivery\raw10_sample_vector_to_packed.v",
    "$P4\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P4\r2-timing-experiment\algo_rowwin3_p4.v",
    "$P4\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P4\r2-timing-experiment\gray8_gaussian3x3_stream_p4.v",
    "$BF\fpga\csi2\src\img\algo_obuf.v",
    "$BF\fpga\csi2\src\img\algo_rowwin3.v",
    "$BF\fpga\csi2\src\img\algo_rowwin_reader.v",
    "$BF\fpga\csi2\src\img\bayer_raw10_demosaic4.v",
    "$BF\fpga\csi2\src\img\gray8_gaussian3x3_frame.v",
    "$BF\fpga\csi2\src\img\gray8_gaussian3x3_stream.v",
    "$BF\fpga\csi2\src\img\gray8_he_cdfmin_frame.v",
    "$BF\fpga\csi2\src\img\img_algo_parallel_top.v",
    "$BF\fpga\csi2\src\img\img_algo_top_g2.v",
    "$BF\fpga\csi2\src\img\rgb8_gray_stream.v",
    "$BF\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b18-b17-b\r0\changed-src\cam_diag_mailbox.v",
    "$R\rtl\a1_core_fix01\a1_frame_top.v",
    "$R\rtl\a1_core_fix01\a1_deflate_core.v",
    "$R\rtl\a1_core_fix01\a1_ddr_slot_store.v",
    "$R\rtl\a1_core_fix01\a1_ddr_arb2.v"
)

Push-Location $sim
try {
    if (-not $NoCompile) {
        if (-not (Test-Path work)) { & "$ms\vlib.exe" work | Out-Null }
        $missing = @($files | Where-Object { -not (Test-Path $_) })
        if ($missing.Count -ne 0) { $missing | ForEach-Object { Write-Output "MISSING $_" }; exit 4 }
        $all = $files + (Join-Path $sim "tb_brd_g1_r1.v")
        Write-Output "SIM_FILELIST_COUNT=$($all.Count)"
        & "$ms\vlog.exe" -quiet -work work @all 2>&1 | Tee-Object -FilePath compile_r1.log | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Error "vlog failed (see sim/compile_r1.log)"; exit 6 }
        Write-Output "COMPILE_OK"
    }

    $tag = "$Test" + "_scen$Scen" + "_p$($Prep)_d$($Pred)"
    $log = Join-Path $sim ("sim_" + $tag + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
    $argLine = '-c -quiet -do "run -all; quit -f" work.' + $Test
    if ($Test -eq "tb_brd_g1_top") { $argLine += " +SCEN=$Scen +PREP=$Prep +PRED=$Pred" }
    $p = Start-Process -FilePath "$ms\vsim.exe" -ArgumentList $argLine -WorkingDirectory $sim `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
    $ok = $p.WaitForExit($TimeoutMin * 60 * 1000)
    if (-not $ok) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Write-Output "SIM_TIMEOUT test=$Test scen=$Scen minutes=$TimeoutMin log=$log"
        exit 3
    }
    $p.Refresh()
    $txt = Get-Content $log -Raw
    foreach ($m in [regex]::Matches($txt, '(?m)^#\s*(PASS|FAIL|POS_RESULT|NEG[0-9A-Z]*_RESULT|ARB_RESULT|A1U1_HEADER|SLOT_[A-Z_]+)[^\r\n]*')) {
        Write-Output $m.Value.Trim()
    }
    Write-Output "SIM_EXIT=$($p.ExitCode)"
    Write-Output "SIM_LOG=$log"
} finally {
    Pop-Location
}
