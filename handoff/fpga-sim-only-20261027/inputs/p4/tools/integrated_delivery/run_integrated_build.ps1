# run_integrated_build.ps1 - INT.P4 isolated TD synthesis entry (synth only).
# Project dir is <run>\INT.P4\td\<Subdir> (fresh per run).  No bitgen / CWC /
# download / Flash.  The TD process is started, waited on with a hard timeout and
# stopped by PID if it overruns (only our own process is ever touched).
param(
  [string]$Stage = "01_synth",
  [int]$TimeoutMin = 25,
  [string]$Subdir = ""
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$tdBase = Join-Path $root "workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P4\td"
$tdDir = if ($Subdir -ne "") { Join-Path $tdBase $Subdir } else { $tdBase }
$tools = Join-Path $root "tools\integrated_delivery\td"
New-Item -ItemType Directory -Force -Path $tdDir | Out-Null
$p = Get-Process pnmain,td_commands_prompt -ErrorAction SilentlyContinue
if ($p) { throw "another TD/pnmain process is active; refusing to share" }
Copy-Item (Join-Path $tools "$Stage.tcl") (Join-Path $tdDir "$Stage.tcl") -Force
Copy-Item (Join-Path $tools "integrated_core.sdc") (Join-Path $tdDir "integrated_core.sdc") -Force
$exe = "D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe"
if (-not (Test-Path $exe)) { throw "TD CLI not found: $exe" }
Push-Location $tdDir
try {
  $log = Join-Path $tdDir ("td_" + $Stage + "_console.log")
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $proc = Start-Process -FilePath $exe -ArgumentList "$Stage.tcl" -WorkingDirectory $tdDir `
            -RedirectStandardOutput $log -NoNewWindow -PassThru
  "td_pid=$($proc.Id) started=$((Get-Date).ToString('s'))" | Out-File -Encoding utf8 -Append $log
  if (-not $proc.WaitForExit($TimeoutMin * 60000)) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    "TIMEOUT stage=$Stage after $TimeoutMin min - own process $($proc.Id) stopped" |
      Out-File -Encoding utf8 -Append $log
    throw "TD stage $Stage timed out after $TimeoutMin min (own pid $($proc.Id) stopped)"
  }
  $sw.Stop()
  "stage=$Stage exit=$($proc.ExitCode) elapsed_s=$([int]$sw.Elapsed.TotalSeconds)" |
    Out-File -Encoding utf8 -Append $log
  Get-Content $log | Select-String -Pattern "INT_SYN|ERROR" | Select-Object -Last 8 | ForEach-Object { $_.Line }
  if ($proc.ExitCode -ne 0) { throw "TD stage $Stage failed (exit $($proc.ExitCode))" }
} finally { Pop-Location }
