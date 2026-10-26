# neg_m1_e2e.ps1 - functional tester: same M1 mutation, full e2e compile list (isolated).
# Compiles the frozen sim list but substitutes the mutated writer copy; expects tb_t11_r10f_e2e to FAIL.
$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
$evdir = Join-Path $PSScriptRoot "msim\neg_m1_rerun"
$mutRel = "workflow/runs/20261017-011744-rk-fpga-align/test-reports/T11.rk-align-raw-r0-functional-evidence/msim/neg_m1_rerun/cam_r10f_writer_m1.v"

$msimBin = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$env:PATH = "$msimBin;$env:PATH"
$substDrive = $null
foreach ($L in @('R','S','T','U','V','W','X','Y','Z')) {
    if ((Get-PSDrive -PSProvider FileSystem).Name -notcontains $L) {
        if (Test-Path "${L}:\") { continue }
        & subst "${L}:" $root | Out-Null
        $substDrive = $L
        break
    }
}
if (-not $substDrive) { Write-Host "no free drive letter"; exit 3 }
$evMapped = "${substDrive}:" + $evdir.Substring($root.Length)
$simRoot = "${substDrive}:/fpga/csi2/pcie_integration/sim"

# build abs list mirroring run_sim.ps1 expansion, with writer replaced by the mutated copy
$lines = Get-Content (Join-Path $root "fpga\csi2\pcie_integration\sim\compile_checked.f")
$abs = @()
foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    if ($t -match '^[A-Za-z]:') { $p = ($t -replace '\\','/') } else { $p = ($simRoot + "/" + $t) }
    if ($p -like "*cam_r10f_writer.v") { $p = "${substDrive}:/" + $mutRel }
    $abs += $p
}
$abs += ($simRoot + "/tb/tb_t11_r10f_e2e.v")

Push-Location $evMapped
try {
    $abs | Out-File -Encoding ascii abs_mut.f
    & vlib work 2>&1 | Out-File -Encoding utf8 vlib_e2e.log
    & vlog +define+MIPI_PHY_SIM_STUB -f abs_mut.f 2>&1 | Out-File -Encoding utf8 vlog_e2e.log
    Write-Host "vlog exit=$LASTEXITCODE"
    "run -all`nquit -f" | Out-File -Encoding ascii run_e2e.do
    & cmd /c "vsim -c -l vsim_e2e.log -do run_e2e.do tb_t11_r10f_e2e" 2>&1 | Out-File -Encoding utf8 vsim_e2e_stdout.log
    Write-Host "vsim exit=$LASTEXITCODE"
} finally {
    Pop-Location
    & subst "${substDrive}:" /D | Out-Null
}
Write-Host "NEG_M1_E2E_DONE"
