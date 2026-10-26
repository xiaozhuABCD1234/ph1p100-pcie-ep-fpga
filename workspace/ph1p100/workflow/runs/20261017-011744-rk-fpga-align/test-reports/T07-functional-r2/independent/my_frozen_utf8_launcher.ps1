# my_frozen_utf8_launcher.ps1 (functional-r2 independent re-check; tester-owned evidence file; ASCII-only)
# Executes the FROZEN tools/pcie_integration/run_sim.ps1 CONTENT verbatim, decoding it explicitly as UTF-8.
# Needed because Windows PowerShell 5.1 (ACP 936) mis-decodes the no-BOM frozen script and aborts it
# before vsim (defined-by-testing defect; see report). The frozen file itself is never modified.
param(
    [Parameter(Mandatory=$true)][string]$Tb,
    [Parameter(Mandatory=$true)][string]$OutDir,
    [string[]]$TbFiles = @(),
    [string]$Defines = "",
    [string]$Root = "",
    [string]$ScriptPath = ""
)
$ErrorActionPreference = "Stop"
if ($Root -ne "") { $root = (Resolve-Path $Root).Path }
else { $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path }
if ($ScriptPath -ne "") { $src = (Resolve-Path $ScriptPath).Path }
else { $src = Join-Path $root "tools\pcie_integration\run_sim.ps1" }
$expected = "33399210C389818A8601B2710FF08FC1B46312976B35D6FB9A0DE1B50674229E"
$actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $src).Hash.ToUpper()
if ($actual -ne $expected) { throw "run_sim.ps1 content hash mismatch: $actual" }
Write-Host ("frozen run_sim.ps1 SHA256 verified: " + $actual + " (UTF-8 launcher; content verbatim)")
$text = [System.IO.File]::ReadAllText($src, [System.Text.Encoding]::UTF8)
$sb = [scriptblock]::Create($text)
& $sb -Tb $Tb -OutDir $OutDir -TbFiles $TbFiles -Defines $Defines -Root $root
Write-Host ("launcher done; LASTEXITCODE=" + $LASTEXITCODE)
