# =============================================================================
# open_td.ps1 -- set up T:/Y: and open the canonical TD project.
#
# Default project: T10.a1-eng-freeze/r10/td/a1_eng_freeze_r10.al
# Use -NoLaunch to only verify/mapping without opening the GUI.
#
# Example:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\open_td.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\td\open_td.ps1 `
#       -TdDir "workflow\runs\...\T10.a1-g2-2cyc\r0\td" -NoLaunch
# =============================================================================
param(
    [string]$TdDir = "",
    [string]$Al = "",
    [string]$TdExe = "D:\anlogic\TD_Release_2026.2\bin\td.exe",
    [switch]$NoLaunch,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path

if ($TdDir -eq "") {
    $TdDir = Join-Path $root "workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-eng-freeze\r10\td"
}
if ($Al -eq "") {
    $Al = Join-Path $TdDir "a1_eng_freeze_r10.al"
}
if (-not (Test-Path -LiteralPath $Al)) {
    throw "TD project file not found: $Al"
}

& (Join-Path $PSScriptRoot "td_env.ps1") -TdDir $TdDir -Root $root -Force:$Force

if ($NoLaunch) {
    Write-Host "NoLaunch: would start `"$TdExe`" `"$Al`""
    return
}
if (-not (Test-Path -LiteralPath $TdExe)) {
    throw "TD executable not found: $TdExe"
}
Start-Process -FilePath $TdExe -ArgumentList ('"' + $Al + '"')
Write-Host "Started TD with $Al"
