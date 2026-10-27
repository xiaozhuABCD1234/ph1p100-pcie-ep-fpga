# diagnostics 6: dump PowerShell 5.1 view of run_td.ps1 (engineering-r2 tester)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
$f = Join-Path $root "tools\pcie_integration\run_td.ps1"
$gc = Get-Content -LiteralPath $f
Write-Host ("PSCount=" + $gc.Count)
for ($i = 0; $i -lt $gc.Count; $i++) {
    Write-Host ("PS{0:d3}|{1}" -f ($i+1), $gc[$i])
}
