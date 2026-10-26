# diagnostics 3: compare PowerShell vs raw view of run_sim.ps1 line structure
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
$f = Join-Path $root "tools\pcie_integration\run_sim.ps1"
$gc = Get-Content -LiteralPath $f
$ral = [System.IO.File]::ReadAllLines($f)
$txt = [System.IO.File]::ReadAllText($f)
$split = $txt.Split("`n")
Write-Host ("Get-Content Count        = " + $gc.Count)
Write-Host ("ReadAllLines Count       = " + $ral.Count)
Write-Host ("ReadAllText split(n)     = " + $split.Count)
Write-Host ("ReadAllText contains CR  = " + $txt.Contains("`r"))
Write-Host "----- Get-Content lines 55..100 (PS view) -----"
for ($i = 54; $i -lt [Math]::Min(100, $gc.Count); $i++) {
    Write-Host ("PS{0:d3}| {1}" -f ($i+1), $gc[$i])
}
