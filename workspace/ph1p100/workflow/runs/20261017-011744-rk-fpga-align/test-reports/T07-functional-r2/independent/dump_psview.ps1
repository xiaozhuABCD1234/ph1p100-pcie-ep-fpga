# dump_psview.ps1 -- dump Get-Content (ANSI) view of a target script to a UTF-8 file for offline diff (ASCII only)
param([Parameter(Mandatory=$true)][string]$Target, [Parameter(Mandatory=$true)][string]$OutFile)
$lines = Get-Content -LiteralPath $Target
[System.IO.File]::WriteAllLines($OutFile, $lines, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("dumped " + $lines.Count + " lines -> " + $OutFile)
