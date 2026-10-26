# probe_run_r2.ps1 — T07 r2 system-dimension probe runner
# Same compile path as the delivered pusher-TB entry: compile_checked.f + probe TB,
# NO +define and NO -suppress (this run doubles as the F2 compile-reproducibility check).
$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
Write-Host "project_root = $root"

$msimBin = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
if (-not (Test-Path (Join-Path $msimBin "vlog.exe"))) { throw "ModelSim vlog not found at $msimBin" }
$env:PATH = "$msimBin;$env:PATH"

$substDrive = $null
$mappedRoot = $root
if ($root -match '[^\x00-\x7F]') {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($L in @('R','S','T','U','V','W','X','Y','Z')) {
        if ($used -notcontains $L) {
            $probe = "${L}:\"
            if (Test-Path $probe) { continue }
            & subst "${L}:" $root | Out-Null
            $substDrive = $L
            $mappedRoot = "${L}:\"
            break
        }
    }
    if (-not $substDrive) { throw "no free drive letter for subst" }
    Write-Host "subst $substDrive`: -> $root (temporary, removed at end)"
}

$outDirF = $PSScriptRoot
$outMapped = ("$mappedRoot" + $outDirF.Substring($root.Length)).Replace("\","/")
$simMapped = ("$mappedRoot" + "fpga\csi2\pcie_integration\sim").Replace("\","/")

$cmdLog = Join-Path $outDirF "probe-commands.log"
"# probe_run_r2.ps1 $(Get-Date -Format o)" | Out-File -Encoding utf8 $cmdLog
"root=$root  mapped=$mappedRoot" | Out-File -Encoding ascii -Append $cmdLog

$flist = Join-Path $outDirF "probe_abs.f"
$lines = Get-Content (Join-Path $root "fpga\csi2\pcie_integration\sim\compile_checked.f")
$abs = @()
foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    if ($t -match '^[A-Za-z]:') { $abs += ($t -replace '\\','/') }
    else { $abs += ($simMapped + "/" + $t) }
}
$abs += ("$outMapped/tb_t07_src_release_probe_r2.v")
$abs | Out-File -Encoding ascii $flist

Push-Location $outMapped
try {
    "vlib work" | Out-File -Encoding ascii -Append $cmdLog
    & vlib work 2>&1 | Tee-Object -FilePath (Join-Path $outDirF "vlib.log") -Append | Out-Null
    "vlog -f probe_abs.f   (no define, no suppress)" | Out-File -Encoding ascii -Append $cmdLog
    & vlog "-f" "probe_abs.f" 2>&1 | Tee-Object -FilePath (Join-Path $outDirF "probe-vlog.log") | Out-Null
    $vlogExit = $LASTEXITCODE
    "vlog exit=$vlogExit" | Out-File -Encoding ascii -Append $cmdLog
    if ($vlogExit -ne 0) { Write-Host "== vlog FAILED =="; Get-Content (Join-Path $outDirF "probe-vlog.log") -Tail 40; throw "vlog failed" }

    [System.IO.File]::WriteAllLines((Join-Path $outDirF "probe_run.do"), @("run -all", "quit -f"))
    "cmd: vsim -c -l probe-vsim.log -do probe_run.do tb_t07_src_release_probe_r2" | Out-File -Encoding ascii -Append $cmdLog
    & cmd /c "vsim -c -l probe-vsim.log -do probe_run.do tb_t07_src_release_probe_r2" 2>&1 | Tee-Object -FilePath (Join-Path $outDirF "probe-vsim-stdout.log") | Out-Null
    $vsimExit = $LASTEXITCODE
    "vsim exit=$vsimExit" | Out-File -Encoding ascii -Append $cmdLog
    Write-Host "== vsim exit $vsimExit =="
    Get-Content (Join-Path $outDirF "probe-vsim.log") -Tail 45
} finally {
    Pop-Location
    if ($substDrive) { & subst "$substDrive`:" /D | Out-Null; Write-Host "subst $substDrive`: removed" }
}
