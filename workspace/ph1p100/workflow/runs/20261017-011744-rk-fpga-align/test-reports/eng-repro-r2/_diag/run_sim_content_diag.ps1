# diagnostics 2: what PowerShell sees in run_sim.ps1 (engineering-r2 tester)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
$f = Join-Path $root "tools\pcie_integration\run_sim.ps1"
$l = Get-Content -LiteralPath $f
Write-Host ("lines as PS sees = " + $l.Count)
Write-Host ("L116 = [" + $l[115] + "]")
Write-Host ("L123 = [" + $l[122] + "]")
Write-Host ("L124 = [" + $l[123] + "]")
Write-Host ("raw bytes  = " + (Get-Item -LiteralPath $f).Length)
Write-Host ("hash       = " + (Get-FileHash -Algorithm SHA256 -LiteralPath $f).Hash)
$ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
$hits = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Value -eq 'WriteAllLines' }, $true)
foreach ($h in $hits) {
    Write-Host ("AST WriteAllLines at line " + $h.Extent.StartLineNumber + " col " + $h.Extent.StartColumnNumber + " : " + $h.Extent.Text.Substring(0, [Math]::Min(90, $h.Extent.Text.Length)))
}
# compare PS-side hash with manifest value
$mp = Join-Path $root "workflow\runs\20261017-011744-rk-fpga-align\backend\candidate-manifest.json"
$m = Get-Content -LiteralPath $mp -Raw | ConvertFrom-Json
$entry = $m.build_scripts | Where-Object { $_.path -eq "tools/pcie_integration/run_sim.ps1" }
Write-Host ("manifest sha = " + $entry.sha256)
