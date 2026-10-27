# =============================================================================
# run_sim_r2.ps1 -- T11.BRD.P1 r2 local G1 simulation runner (ModelSim ASE)
#
# r2 delta vs run_sim_r1.ps1:
#   * compiles the r2 work root (r2/rtl + r2/sim/tb_brd_g1_r2.v)
#   * every scenario writes its dumps into its OWN directory
#       sim\scen0, sim\scen1, sim\scen2, sim\scen3, sim\scen4, sim\prep, sim\arb
#     so a diagnostic/variant run can never overwrite the frozen candidate dump
#     (r1 lost the scen0 dump that way and had to restore it).
#   * a per-run do-file `cd`s into that directory before `run -all`.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_sim_r2.ps1 -Test tb_brd_arb
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_sim_r2.ps1 -Test tb_brd_g1_top -Scen 0
#   powershell -NoProfile -ExecutionPolicy Bypass -File run_sim_r2.ps1 -Test tb_brd_g1_top -Scen 0 -Prep 1 -Pred 1
# =============================================================================
param(
    [string]$Test = "tb_brd_g1_top",
    [string]$Scen = "0",
    [int]$Prep = 0,
    [int]$Pred = 0,
    [int]$TimeoutMin = 20,
    [string]$DumpDir = "",
    [switch]$NoCompile,
    [switch]$CompileOnly
)

$ErrorActionPreference = "Stop"
$sim  = $PSScriptRoot
$R2   = (Resolve-Path (Join-Path $sim "..")).Path
$repo = (Resolve-Path (Join-Path $sim "..\..\..\..\..\..")).Path
$ms   = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$env:Path = "$ms;" + $env:Path

$IN = Join-Path $repo "handoff\fpga-sim-only-20261027\inputs"
$BF = Join-Path $IN "board-filelist"
$P4 = Join-Path $IN "p4"

$files = @(
    "$R2\rtl\ref\common\TLP_FMT_TYPE.v",
    "$R2\rtl\ref\common\BDF.v",
    "$R2\rtl\ref\ep_side\ddr\ddr_frame_pusher.v",
    "$R2\rtl\brd_export_seq.v",
    "$R2\rtl\brd_cam_fe.v",
    "$R2\rtl\brd_cdc_mailboxes.v",
    "$R2\rtl\brd_ddr_rd_arb.v",
    "$R2\rtl\brd_a1_core_pll.v",
    "$R2\rtl\a1_raw_crop.v",
    "$R2\rtl\p2_ddr_bridge.v",
    "$R2\rtl\brd_board_datapath.v",
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
    "$R2\rtl\a1_core_fix01\a1_frame_top.v",
    "$R2\rtl\a1_core_fix01\a1_deflate_core.v",
    "$R2\rtl\a1_core_fix01\a1_ddr_slot_store.v",
    "$R2\rtl\a1_core_fix01\a1_ddr_arb2.v"
)

if ($DumpDir -eq "") {
    if ($Test -ne "tb_brd_g1_top") { $DumpDir = Join-Path $sim "arb" }
    elseif (($Prep -ne 0) -or ($Pred -ne 0)) { $DumpDir = Join-Path $sim "prep" }
    else { $DumpDir = Join-Path $sim "scen$Scen" }
}

Push-Location $sim
try {
    if (-not $NoCompile) {
        if (-not (Test-Path work)) { & "$ms\vlib.exe" work | Out-Null }
        $missing = @($files | Where-Object { -not (Test-Path $_) })
        if ($missing.Count -ne 0) { $missing | ForEach-Object { Write-Output "MISSING $_" }; exit 4 }
        $all = $files + (Join-Path $sim "tb_brd_g1_r2.v")
        Write-Output "SIM_FILELIST_COUNT=$($all.Count)"
        & "$ms\vlog.exe" -quiet -work work @all 2>&1 | Tee-Object -FilePath compile_r2.log | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Error "vlog failed (see sim/compile_r2.log)"; exit 6 }
        Write-Output "COMPILE_OK"
    }
    if ($CompileOnly) { Write-Output "COMPILE_ONLY=1"; exit 0 }

    if (-not (Test-Path $DumpDir)) { New-Item -ItemType Directory -Path $DumpDir | Out-Null }
    # vsim resolves the `work` mapping relative to the session CWD, so each dump
    # directory gets a junction to sim\work (no copy, no second library).
    $wlink = Join-Path $DumpDir "work"
    if (-not (Test-Path $wlink)) {
        New-Item -ItemType Junction -Path $wlink -Target (Join-Path $sim "work") | Out-Null
    }
    $tag = "$Test" + "_scen$Scen" + "_p$($Prep)_d$($Pred)"
    $do  = Join-Path $sim ("run_" + $tag + ".do")
    # vsim refuses `cd` once the design is loaded, so the do-file changes the
    # simulator working directory FIRST, then loads the unit by its mapped
    # library name (`work` was resolved when the session started in sim\).
    $vs = "vsim work." + $Test
    if ($Test -eq "tb_brd_g1_top") { $vs += " +SCEN=$Scen +PREP=$Prep +PRED=$Pred" }
    $doLines = @("cd {$(($DumpDir -replace '\\','/'))}", $vs, "run -all", "quit -f")
    Set-Content -Path $do -Value $doLines -Encoding ascii

    $log = Join-Path $sim ("sim_" + $tag + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
    $argLine = '-c -quiet -do "do ' + ($do -replace '\\','/') + '"'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath "$ms\vsim.exe" -ArgumentList $argLine -WorkingDirectory $sim `
        -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
    $ok = $p.WaitForExit($TimeoutMin * 60 * 1000)
    if (-not $ok) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Write-Output "SIM_TIMEOUT test=$Test scen=$Scen minutes=$TimeoutMin log=$log"
        exit 3
    }
    $sw.Stop()
    $p.Refresh()
    $txt = Get-Content $log -Raw
    foreach ($m in [regex]::Matches($txt, '(?m)^#\s*(PASS|FAIL|POS_RESULT|NEG[0-9A-Z]*_RESULT|ARB_RESULT|A1U1_HEADER|STIM_PROBE|STIM|SLOT_[A-Z_]+|CROP_GEOM[A-Z_]*)[^\r\n]*')) {
        Write-Output $m.Value.Trim()
    }
    Write-Output "SIM_EXIT=$($p.ExitCode) SIM_SECONDS=$([int]$sw.Elapsed.TotalSeconds) DUMP_DIR=$DumpDir"
    Write-Output "SIM_LOG=$log"
} finally {
    Pop-Location
}
