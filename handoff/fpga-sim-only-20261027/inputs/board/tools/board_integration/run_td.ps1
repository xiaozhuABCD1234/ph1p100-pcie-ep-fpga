# =============================================================================
# run_td.ps1 -- T11.BRD.P1 single-session TD runner (no download, no Flash)
#
# Preflight (dispatch preflight_requirements):
#   * refuse to start if another pnmain / td_commands_prompt exists (never shared,
#     never killed)
#   * repoint T: to THIS run with tools/td/td_env.ps1 -Force
#   * Y: must be the project root
# Then runs one tcl script in td_commands_prompt.exe with a hard wall-clock
# timeout; on timeout only our own process is stopped.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\board_integration\run_td.ps1 -Script 01_synth -TimeoutMin 30
# =============================================================================
param(
    [Parameter(Mandatory = $true)][string]$Script,
    [int]$TimeoutMin = 30,
    [string]$RunDir = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
if ($RunDir -eq "") { $RunDir = Join-Path $root "workflow\runs\20261027-0726_fpga-board-integration" }
$td = Join-Path $RunDir "T11.BRD.P1\td"
$tdExe = "D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe"

if (-not (Test-Path $td)) { Write-Error "missing td dir: $td"; exit 2 }
if (-not (Test-Path $tdExe)) { Write-Error "missing TD: $tdExe"; exit 2 }
$scriptPath = Join-Path $td "$Script.tcl"
if (-not (Test-Path $scriptPath)) { Write-Error "missing script: $scriptPath"; exit 2 }

# ---- preflight: no foreign TD session ----
$others = @(Get-Process -Name pnmain, td_commands_prompt -ErrorAction SilentlyContinue)
if ($others.Count -gt 0) {
    $ids = ($others | ForEach-Object { "$($_.ProcessName):$($_.Id)" }) -join ", "
    Write-Error "TD busy (not shared, not killed): $ids"
    exit 4
}

# ---- T: must point at THIS run ----
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "tools\td\td_env.ps1") -Force -TdDir $td
if ($LASTEXITCODE -ne 0) { Write-Error "td_env.ps1 -Force failed"; exit 5 }

# ---- Y: must be the project root (marker check; .NET Target on a subst drive
#      returns a relative string, so test two project-specific paths instead) ----
$y = Get-PSDrive -Name Y -ErrorAction SilentlyContinue
if ($null -eq $y) { & subst Y: $root }
if (-not (Test-Path "Y:\fpga\csi2\pcie_integration") -or -not (Test-Path "Y:\workflow\runs")) {
    Write-Error "Y: does not point at $root (markers missing)"; exit 5
}

# ---- run one session with a hard timeout ----
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$log = Join-Path $td ("td_" + $Script + "_" + $stamp + ".log")
$err = "$log.err"
# TD hands the argument to Tcl, so pass forward slashes: a Windows backslash path
# would be eaten as a Tcl escape sequence (\f, \p, ...).
$scriptArg = ($scriptPath -replace '\\', '/')
$p = Start-Process -FilePath $tdExe -ArgumentList "`"$scriptArg`"" -WorkingDirectory $td `
    -RedirectStandardOutput $log -RedirectStandardError $err -PassThru -NoNewWindow
$ok = $p.WaitForExit($TimeoutMin * 60 * 1000)
if (-not $ok) {
    try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch { }
    Write-Output "TD_TIMEOUT script=$Script minutes=$TimeoutMin log=$log"
    exit 3
}
$p.Refresh()
if ($null -eq $p.ExitCode) { $p.WaitForExit() }
$code = $p.ExitCode
Write-Output "TD_EXIT script=$Script code=$code log=$log"
exit $code
