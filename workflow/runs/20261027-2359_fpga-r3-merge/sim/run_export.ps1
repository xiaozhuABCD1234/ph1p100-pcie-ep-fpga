# =============================================================================
# run_export.ps1 -- r3 export regression (two frames / backpressure / ACK / neg)
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\run_export.ps1 -Scen 0 -Nf 3
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\run_export.ps1 -Scen 3 -Nf 3
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\run_export.ps1 -Scen 2 -Nf 2
#   powershell -NoProfile -ExecutionPolicy Bypass -File sim\run_export.ps1 -Scen 0 -Nf 3 -HostModel 1  # r0g legacy decode
# Exit: 0 ran, 3 timeout, 4 missing, 6 compile error
# =============================================================================
param(
    [int]$Scen = 0,
    [int]$Nf = 3,
    [int]$HostModel = 0,
    [int]$TimeoutMin = 20,
    [switch]$NoCompile
)
$ErrorActionPreference = "Stop"
$sim  = $PSScriptRoot
$R3   = (Resolve-Path (Join-Path $sim "..")).Path
$repo = (Resolve-Path (Join-Path $sim "..\..\..\..")).Path
$ms   = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$env:Path = "$ms;" + $env:Path

$IN = Join-Path $repo "handoff\fpga-sim-only-20261027\inputs"
$BF = Join-Path $IN "board-filelist"
$P4 = Join-Path $IN "p4"

$files = @(
    "$R3\rtl\ref\common\TLP_FMT_TYPE.v",
    "$R3\rtl\ref\common\BDF.v",
    "$R3\rtl\ref\ep_side\ddr\ddr_frame_pusher.v",
    "$R3\rtl\brd_export_seq.v",
    "$R3\rtl\brd_cam_fe.v",
    "$R3\rtl\brd_cdc_mailboxes.v",
    "$R3\rtl\brd_ddr_rd_arb.v",
    "$R3\rtl\brd_a1_core_pll.v",
    "$R3\rtl\a1_raw_crop.v",
    "$R3\rtl\p2_ddr_bridge.v",
    "$R3\rtl\brd_board_datapath.v",
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
    "$R3\rtl\a1_core_fix01\a1_frame_top.v",
    "$R3\rtl\a1_core_fix01\a1_deflate_core.v",
    "$R3\rtl\a1_core_fix01\a1_ddr_slot_store.v",
    "$R3\rtl\a1_core_fix01\a1_ddr_arb2.v"
)

Push-Location $sim
try {
    if (-not $NoCompile) {
        if (-not (Test-Path work)) { & "$ms\vlib.exe" work | Out-Null }
        $missing = @($files | Where-Object { -not (Test-Path $_) })
        if ($missing.Count -ne 0) {
            $missing | ForEach-Object { Write-Output "MISSING $_" }
            exit 4
        }
        $all = $files + (Join-Path $R3 "tb\tb_brd_export_r3.v")
        & "$ms\vlog.exe" -quiet -work work @all 2>&1 |
            Tee-Object -FilePath (Join-Path $sim "compile_export.log") | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Output "COMPILE_FAILED"; exit 6 }
        Write-Output "COMPILE_OK"
    }

    $tag = "export_s${Scen}_h${HostModel}"
    $dump = Join-Path $sim $tag
    New-Item -ItemType Directory -Force -Path $dump | Out-Null
    $wlink = Join-Path $dump "work"
    if (-not (Test-Path $wlink)) {
        New-Item -ItemType Junction -Path $wlink -Target (Join-Path $sim "work") | Out-Null
    }
    $do = Join-Path $sim "run_export.do"
    $doLines = @(
        "cd {$(($dump -replace '\\','/'))}",
        "vsim work.tb_brd_export_r3 +SCEN=$Scen +NF=$Nf +HOST_MODEL=$HostModel",
        "run -all",
        "quit -f"
    )
    Set-Content -Path $do -Value $doLines -Encoding ascii

    $log = Join-Path $sim ("sim_" + $tag + "_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
    $p = Start-Process -FilePath "$ms\vsim.exe" -ArgumentList ('-c -quiet -do "do ' + ($do -replace '\\','/') + '"') `
        -WorkingDirectory $sim -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
    if (-not $p.WaitForExit($TimeoutMin * 60 * 1000)) {
        try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
        Write-Output "SIM_TIMEOUT export scen=$Scen host=$HostModel"
        exit 3
    }
    $txt = Get-Content $log -Raw
    foreach ($m in [regex]::Matches($txt, '(?m)^#\s*(TB_SCEN|PAYLOAD_COMPARE|FRAME_RESULT|POS_RESULT|NEG[0-9A-Z]*_RESULT|NEG_RESULT|STREAM_DIFF|E8_NEGCTL|INFO summary|INFO frame|PASS neg|FAIL|ACK_SEND)[^\r\n]*')) {
        Write-Output $m.Value.Trim()
    }
    Write-Output "SIM_LOG=$log"
    exit 0
} finally {
    Pop-Location
}
