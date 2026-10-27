# New-instance workaround launcher (F1): execute the FROZEN run_sim.ps1 text with correct UTF-8 decoding.
# The frozen file is UTF-8 without BOM; PowerShell 5.1 (ACP 936) mis-decodes it and swallows newlines
# inside Chinese comments, which breaks $doPath (reproduced by this instance at 06:34 on Oct 17).
# This launcher: (1) verifies the frozen file hash, (2) reads it as UTF-8 text, (3) runs it as a scriptblock.
# The frozen file on disk is never modified.
param(
    [Parameter(Mandatory=$true)][string]$Tb,
    [Parameter(Mandatory=$true)][string]$OutDir,
    [string]$TbFiles = "",
    [string]$Defines = "",
    [Parameter(Mandatory=$true)][string]$Root
)
$ErrorActionPreference = "Stop"
$srcRel = "tools\pcie_integration\run_sim.ps1"
$srcAbs = Join-Path $Root $srcRel
$expected = "33399210C389818A8601B2710FF08FC1B46312976B35D6FB9A0DE1B50674229E"
$actual = (Get-FileHash -Algorithm SHA256 $srcAbs).Hash.ToUpper()
if ($actual -ne $expected) { throw "run_sim.ps1 SHA256 mismatch: $actual (expected $expected)" }
Write-Host "frozen run_sim.ps1 SHA256 OK: $actual"
$text = [System.IO.File]::ReadAllText($srcAbs, [System.Text.Encoding]::UTF8)
$sb = [scriptblock]::Create($text)
$p = @{ Tb = $Tb; OutDir = $OutDir; Root = $Root }
if ($TbFiles -ne "") { $p["TbFiles"] = ($TbFiles -split ',') }
if ($Defines -ne "") { $p["Defines"] = $Defines }
& $sb @p
Write-Host ("LAUNCHER_DONE tb=" + $Tb)
