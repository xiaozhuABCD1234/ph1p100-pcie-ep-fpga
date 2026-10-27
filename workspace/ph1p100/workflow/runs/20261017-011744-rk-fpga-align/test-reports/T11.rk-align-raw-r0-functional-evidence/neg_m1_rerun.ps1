# neg_m1_rerun.ps1 - functional tester independent negative-control replay (M1: pack order swap)
# ASCII-only. Creates an isolated copy under the evidence dir; never touches frozen sources.
# Expected: tb_cam_r10f_writer FAILs (mutation must be caught by the frozen testbench).
$ErrorActionPreference = "Continue"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
$evdir = Join-Path $PSScriptRoot "msim\neg_m1_rerun"
New-Item -ItemType Directory -Force -Path $evdir | Out-Null

$src  = Join-Path $root "fpga\csi2\pcie_integration\rtl\ep_side\ddr\cam_r10f_writer.v"
$crcd = Join-Path $root "fpga\csi2\pcie_integration\rtl\ep_side\ddr\crc32_upd4.v"
$tb   = Join-Path $root "fpga\csi2\pcie_integration\sim\tb\tb_cam_r10f_writer.v"

$txt = [System.IO.File]::ReadAllText($src)
$from = "{cam_pix[31:30], cam_pix[21:20], cam_pix[11:10], cam_pix[1:0]}"
$to   = "{cam_pix[1:0], cam_pix[11:10], cam_pix[21:20], cam_pix[31:30]}"
if (-not $txt.Contains($from)) { Write-Host "MUTATION PATTERN NOT FOUND - abort"; exit 2 }
$mut = $txt.Replace($from, $to)
$mutPath = Join-Path $evdir "cam_r10f_writer_m1.v"
[System.IO.File]::WriteAllText($mutPath, $mut)
Copy-Item $crcd (Join-Path $evdir "crc32_upd4.v") -Force

$shaMut = (Get-FileHash $mutPath -Algorithm SHA256).Hash
$shaFrozen = (Get-FileHash $src -Algorithm SHA256).Hash
Write-Host "frozen sha256 = $shaFrozen"
Write-Host "mutated sha256 = $shaMut"
"frozen_sha256=$shaFrozen`nmutated_sha256=$shaMut`nmutation=low2bit pack order reversed`nexpected=FAIL" |
    Out-File -Encoding ascii (Join-Path $evdir "mutation_local.txt")

# --- subst mapping (Chinese path -> ASCII drive) ---
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
$tbMapped = "${substDrive}:" + $tb.Substring($root.Length)
Write-Host "subst ${substDrive}: -> $root ; evMapped=$evMapped"

Push-Location $evMapped
try {
    & vlib work 2>&1 | Out-File -Encoding utf8 vlib.log
    $flist = @("cam_r10f_writer_m1.v", ($tbMapped.Replace('\','/')))
    $flist | Out-File -Encoding ascii compile.f
    & vlog +define+MIPI_PHY_SIM_STUB -f compile.f 2>&1 | Out-File -Encoding utf8 vlog.log
    Write-Host "vlog exit=$LASTEXITCODE"
    "run -all`nquit -f" | Out-File -Encoding ascii run.do
    & cmd /c "vsim -c -l vsim.log -do run.do tb_cam_r10f_writer" 2>&1 | Out-File -Encoding utf8 vsim_stdout.log
    Write-Host "vsim exit=$LASTEXITCODE"
} finally {
    Pop-Location
    & subst "${substDrive}:" /D | Out-Null
}
Write-Host "NEG_M1_DONE"
