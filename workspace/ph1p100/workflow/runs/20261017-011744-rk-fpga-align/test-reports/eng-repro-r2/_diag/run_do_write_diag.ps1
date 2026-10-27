# diagnostics: replicate run_sim.ps1's run.do write step (engineering-r2 tester)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
Write-Host "root = [$root] len=$($root.Length)"
$OutDir = "workflow/runs/20261017-011744-rk-fpga-align/test-reports/eng-repro-r2/_diag"
$outDirF = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $outDirF | Out-Null
$mappedRoot = $root
$drive = $null
foreach ($L in @('R','S','T','U','V','W','X','Y','Z')) {
    $probe = "${L}:\"
    if (-not (Test-Path $probe)) { & subst "${L}:" $root | Out-Null; $drive = $L; $mappedRoot = "${L}:\"; break }
}
Write-Host "subst $drive -> $root"
function To-Mapped([string]$p) {
    if ($drive -and $p.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "$mappedRoot" + $p.Substring($root.Length).TrimStart('\')
    }
    return $p
}
$outMapped = To-Mapped $outDirF
Write-Host "outDirF  = [$outDirF]"
Write-Host "outMapped= [$outMapped]"
Push-Location $outMapped
try {
    $doPath = Join-Path $outDirF "run.do"
    Write-Host "doPath   = [$doPath] len=$($doPath.Length) type=$($doPath.GetType().FullName)"
    $codes = ($doPath.ToCharArray() | ForEach-Object { [int]$_ })
    Write-Host ("doPath char codes (first 40): " + (($codes | Select-Object -First 40) -join ',') + " ... last 10: " + (($codes | Select-Object -Last 10) -join ','))
    try {
        [System.IO.File]::WriteAllLines($doPath, @("run -all", "quit -f"))
        Write-Host "WriteAllLines: OK"
    } catch {
        Write-Host "WriteAllLines FAILED: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    }
    try {
        [System.IO.File]::WriteAllText($doPath, "run -all`r`nquit -f`r`n")
        Write-Host "WriteAllText: OK"
    } catch {
        Write-Host "WriteAllText FAILED: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    }
    try {
        "run -all`r`nquit -f" | Out-File -Encoding ascii (Join-Path $outDirF "run2.do")
        Write-Host "Out-File: OK"
    } catch {
        Write-Host "Out-File FAILED: $($_.Exception.GetType().FullName): $($_.Exception.Message)"
    }
    Write-Host ("cwd = " + (Get-Location).Path)
} finally {
    Pop-Location
    if ($drive) { & subst "$drive`:" /D | Out-Null; Write-Host "subst removed" }
}
