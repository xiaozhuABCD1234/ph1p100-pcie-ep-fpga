# run_integrated_sim.ps1 - INT.P4 integrated delivery simulation entry.
#
# Compiles the frozen candidate (INT.P1 top + b20 r0 A+ read-only core + INT.P2
# egress adapter + INT.P3 scheduler + the INT.P4 integration glue) with real
# DUTs and runs the integrated TB.  TB-side models only: DDR array, capture
# frame sources, PCIe backend / host-ACK model.
#
#   -Mode   P1 output mode (0 raw,1 gray,2 gaussian,3 HE,4 raw bypass). Default 4.
#   -Sample 1 = emit tools/integrated_delivery/evidence/integrated_sample.* from T1
#   -Extra  also run the multi-scenario schedule (T2 backpressure, T3 abort,
#           T4 A-disabled/B-priority, T5 bad ACK, T6 truncated frame)
#   -Full   additionally compile+run the existing P1/P2/P3 package TBs and the
#           Python package tools (this is what INT.P4-build-entry.md documents)
#
# All logs go to <run>/INT.P4/regression/ (and <run>/INT.P4/sim/run/).
# No TD, no bitgen, no CWC, no download, no Flash.
param(
  [switch]$Full,
  [int]$Mode = 4,
  [int]$Sample = 1,
  [switch]$Extra,
  [string]$Tag = "",
  [string]$SampleDir = ""
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$run  = Join-Path $root "workflow\runs\20261026-2138_fpga-integrated-delivery"
# -Tag r3 isolates a later round's compile dir/logs from the frozen r2 evidence.
$base = Join-Path $run "INT.P4"
if ($Tag -ne "") { $base = Join-Path $base $Tag }
$cmp  = Join-Path $base "sim\compile"
$rlog = Join-Path $base "regression"
$sdir = if ($SampleDir -ne "") { $SampleDir } else { Join-Path $root "tools\integrated_delivery\evidence" }
New-Item -ItemType Directory -Force -Path $cmp,$rlog,$sdir | Out-Null
$env:Path = "D:\intelFPGA\18.1\modelsim_ase\win32aloem;" + $env:Path
$b20 = Join-Path $root "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b20-a-timing\r0\changed-src"
$cand = Join-Path $root "fpga\csi2\src\integrated_delivery"
$img  = Join-Path $root "fpga\csi2\src\img"
$src = @(
 (Join-Path $cand "integrated_delivery_top.v"), (Join-Path $cand "integrated_input_processing_top.v"),
 (Join-Path $cand "raw10_sample_vector_to_packed.v"), (Join-Path $cand "frame_good_publish_cancel.v"),
 (Join-Path $cand "aplus_pcie_egress_adapter.v"), (Join-Path $cand "dual_channel_capture_scheduler.v"),
 # INT.P4 r2/r3 timing-only derived variants (same ports/semantics as the img base)
 (Join-Path $cand "bayer_raw10_demosaic4_p4.v"), (Join-Path $cand "img_algo_parallel_top_p4.v"),
 (Join-Path $cand "algo_rowwin3_p4.v"), (Join-Path $cand "gray8_gaussian3x3_stream_p4.v"),
 (Join-Path $b20 "a1_frame_top.v"), (Join-Path $b20 "a1_deflate_core.v"),
 (Join-Path $b20 "a1_ddr_slot_store.v"), (Join-Path $b20 "a1_ddr_arb2.v")
) + (Get-ChildItem $img -Filter *.v | Select-Object -ExpandProperty FullName)
$tbs = @(
 (Join-Path $cand "tb_integrated_delivery_top.v"),
 (Join-Path $cand "tb_img_algo_equiv_p4.v"),
 (Join-Path $cand "tb_raw10_packer.v"),
 (Join-Path $cand "tb_aplus_pcie_egress_adapter.v"),
 (Join-Path $cand "tb_dual_channel_capture_scheduler.v")
)
Push-Location $cmp
try {
  if (-not (Test-Path work)) { vlib work | Out-Null }
  vlog -quiet -work work @src 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "vlog candidate failed" }
  vlog -quiet -work work @tbs 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "vlog tb failed" }

  $suffix = ""
  if ($Extra) { $suffix = "_extra" }
  $log = Join-Path $rlog "integrated_mode$Mode$suffix.log"
  $plus = @("+MODE=$Mode", "+SAMPLE=$Sample",
            "+SAMPLE_DIR=$sdir")
  if ($Extra) { $plus += "+EXTRA=1" }
  vsim -c -quiet -do "run -all; quit -f" tb_integrated_delivery_top @plus 2>&1 |
       Tee-Object -FilePath $log | Out-Null
  Get-Content $log | Select-String -Pattern "TB_INTEGRATED_DELIVERY_TOP|FAIL" |
       ForEach-Object { $_.Line }

  if ($Full) {
    # ---- derived-variant data-sequence equivalence (r2; three seed modes) ----
    foreach ($sm in 0,1,2) {
      $elog = Join-Path $rlog ("equiv_seedmode" + $sm + ".log")
      vsim -c -quiet -do "run -all; quit -f" -l $elog tb_img_algo_equiv_p4 +SEEDMODE=$sm 2>&1 | Out-Null
      Get-Content $elog | Select-String -Pattern "CHECK_REF_NEW|TB_IMG_ALGO_EQUIV_P4|CONTROL_REF_REF2 diffs|EQUIV_COUNTS" |
           ForEach-Object { $_.Line }
    }
    # ---- existing P1/P2/P3 package TBs (same frozen candidate) ----
    foreach ($pair in @(
        @("tb_raw10_packer", "p1_tb_raw10_packer.log"),
        @("tb_aplus_pcie_egress_adapter", "p2_tb_egress.log"),
        @("tb_dual_channel_capture_scheduler", "p3_tb_scheduler.log"))) {
      $tlog = Join-Path $rlog $pair[1]
      vsim -c -quiet -do "run -all; quit -f" $pair[0] 2>&1 |
           Tee-Object -FilePath $tlog | Out-Null
      Get-Content $tlog | Select-String -Pattern "PASS|FAIL|TIMEOUT" |
           Select-Object -Last 1 | ForEach-Object { $_.Line }
    }
    # ---- Python package tools ----
    $py = @(
      @("raw10_pack.py", @()),
      @("verify_input_processing.py", @()),
      @("dual_channel_schedule.py", @()),
      @("a1u1_decode.py", @((Join-Path $root "tools\integrated_delivery\evidence\integrated_sample.a1u1"), "4096")),
      @("verify_integrated_sample.py", @(
          (Join-Path $root "tools\integrated_delivery\evidence\integrated_sample.a1u1"),
          (Join-Path $root "tools\integrated_delivery\evidence\integrated_sample.raw"),
          (Join-Path $root "tools\integrated_delivery\evidence\integrated_sample.json")))
    )
    foreach ($p in $py) {
      $tlog = Join-Path $rlog ("py_" + ($p[0] -replace "\.py$", ".log"))
      & python (Join-Path $root ("tools\integrated_delivery\" + $p[0])) @($p[1]) 2>&1 |
           Tee-Object -FilePath $tlog | Out-Null
      if ($LASTEXITCODE -ne 0) { "PY_FAIL $($p[0]) exit=$LASTEXITCODE" }
      else { Get-Content $tlog | Select-Object -Last 1 }
    }
  }
} finally { Pop-Location }
