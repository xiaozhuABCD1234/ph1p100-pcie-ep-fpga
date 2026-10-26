# diagnostics 5: what PowerShell 5.1 sees in run_td.ps1 vs raw bytes (engineering-r2 tester)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
foreach ($rel in @("tools\pcie_integration\run_td.ps1", "tools\pcie_integration\run_sim.ps1")) {
    $f = Join-Path $root $rel
    $gc = Get-Content -LiteralPath $f
    $ral = [System.IO.File]::ReadAllLines($f)
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
    $astlines = @($ast.FindAll({ param($n) $n.Extent -ne $null }, $true) | ForEach-Object { $_.Extent.StartLineNumber })
    $maxast = if ($astlines.Count) { ($astlines | Measure-Object -Maximum).Maximum } else { 0 }
    Write-Host ("FILE {0}" -f $rel)
    Write-Host ("  Get-Content lines = {0};  ReadAllLines lines = {1};  AST max line = {2}" -f $gc.Count, $ral.Count, $maxast)
    $thrown = @()
    foreach ($m in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.ThrowStatementAst] }, $true)) {
        $thrown += ("throw@L{0}" -f $m.Extent.StartLineNumber)
    }
    Write-Host ("  throws: " + ($thrown -join ", "))
}
