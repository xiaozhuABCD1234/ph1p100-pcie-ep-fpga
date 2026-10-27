# =============================================================================
#  env_check_rerun.ps1 - T11.rk-align-base r0 system tester:
#  independent re-run of the documented env_check.ps1 entry commands.
#  Logs are redirected into this evidence dir (do NOT touch frozen env/logs).
# =============================================================================
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\..")).Path
$script = Join-Path $root "tools\env\env_check.ps1"
$base = Join-Path $PSScriptRoot "env_check_rerun"

$dirA = Join-Path $base "default"
$dirB = Join-Path $base "tdprobe"
New-Item -ItemType Directory -Force -Path $dirA | Out-Null
New-Item -ItemType Directory -Force -Path $dirB | Out-Null

Write-Host "=== run A: documented default command (no -TdProbe) ==="
& powershell -ExecutionPolicy Bypass -File $script -LogDir $dirA
$codeA = $LASTEXITCODE
Write-Host ("run A exit = " + $codeA)

Write-Host "=== run B: documented command with -TdProbe ==="
& powershell -ExecutionPolicy Bypass -File $script -LogDir $dirB -TdProbe
$codeB = $LASTEXITCODE
Write-Host ("run B exit = " + $codeB)

Write-Host ("SUMMARY A_exit=" + $codeA + " B_exit=" + $codeB)
