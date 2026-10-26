# rerun_all.ps1 - functional tester independent replay of the G1/T07-regression suite
# ASCII-only script: uses paths relative to the project root (current directory).
# Writes logs under the evidence dir only. Does not modify any frozen input.
$ErrorActionPreference = "Continue"
$ev = "workflow/runs/20261017-011744-rk-fpga-align/test-reports/T11.rk-align-raw-r0-functional-evidence"
$jobs = @(
    @{ Tb = "tb_t11_csi_enable_corner";   Dir = "p3_enable";   TbFile = "tb/tb_t11_csi_enable_corner.v" },
    @{ Tb = "tb_ddr_frame_pusher_rka1";   Dir = "r_t07_pusher"; TbFile = "tb/tb_ddr_frame_pusher_rka1.v" },
    @{ Tb = "tb_csi_integrity_diff";      Dir = "r_t07_diff";   TbFile = "tb/tb_csi_integrity_diff.v" },
    @{ Tb = "tb_csi_checked";             Dir = "r_t07_checked"; TbFile = "tb/tb_csi_checked.v" },
    @{ Tb = "tb_ep_bar_win_rka1";         Dir = "r_t07_bar";    TbFile = "tb/tb_ep_bar_win_rka1.v" },
    @{ Tb = "tb_ddr_wr_arb_peer";         Dir = "r_t07_arb";    TbFile = "tb/tb_ddr_wr_arb_peer.v" }
)
foreach ($j in $jobs) {
    Write-Host "==================== $($j.Tb) ===================="
    & powershell -ExecutionPolicy Bypass -File "tools/pcie_integration/run_sim.ps1" `
        -Tb $j.Tb -OutDir "$ev/msim/$($j.Dir)" -TbFiles $j.TbFile -Defines MIPI_PHY_SIM_STUB `
        *> "$ev/msim/$($j.Dir)_console.txt"
    Write-Host "exitcode=$LASTEXITCODE"
}
Write-Host "RERUN_ALL_DONE"
