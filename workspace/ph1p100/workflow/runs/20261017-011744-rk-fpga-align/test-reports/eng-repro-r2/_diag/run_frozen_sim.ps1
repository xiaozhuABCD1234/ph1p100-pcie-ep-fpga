# engineering-r2 independent re-run wrapper (tester-owned, not part of the candidate).
# Executes the FROZEN tools/pcie_integration/run_sim.ps1 CONTENT verbatim, but decodes it as
# UTF-8 explicitly. Reason: Windows PowerShell 5.1 (ACP 936) reads the frozen script as ANSI,
# swallows 8 LF breaks inside Chinese comment lines, and merges the statement
# `$doPath = Join-Path $outDirF "run.do"` (raw line 123) into a comment, so the script aborts
# at WriteAllLines with "Empty path name is not legal". This wrapper passes -Root explicitly
# (scriptblocks created from text have no $PSScriptRoot).
param(
    [Parameter(Mandatory=$true)][string]$Tb,
    [Parameter(Mandatory=$true)][string]$OutDir,
    [string[]]$TbFiles = @(),
    [string]$Defines = ""
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..\..")).Path
$scriptPath = Join-Path $root "tools\pcie_integration\run_sim.ps1"
$content = [System.IO.File]::ReadAllText($scriptPath, [System.Text.Encoding]::UTF8)
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $scriptPath).Hash
Write-Host ("frozen run_sim.ps1 SHA256 = " + $hash)
$sb = [scriptblock]::Create($content)
& $sb -Tb $Tb -OutDir $OutDir -TbFiles $TbFiles -Defines $Defines -Root $root
Write-Host ("wrapper done, LASTEXITCODE=" + $LASTEXITCODE)
