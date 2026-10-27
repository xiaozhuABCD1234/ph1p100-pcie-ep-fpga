param(
  [Parameter(Mandatory=$true)][string]$Exe,
  [Parameter(Mandatory=$true)][string]$WorkDir,
  [Parameter(Mandatory=$true)][string]$ArgLine,
  [Parameter(Mandatory=$true)][string]$LogPath,
  [Parameter(Mandatory=$true)][string]$StdoutPath,
  [Parameter(Mandatory=$true)][string]$Note,
  [int]$TimeoutSec = 300,
  [Parameter(Mandatory=$true)][string]$CmdJsonl
)
$ErrorActionPreference = 'Stop'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
if (-not (Test-Path $WorkDir)) { New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null }
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Exe
$psi.Arguments = $ArgLine
$psi.WorkingDirectory = $WorkDir
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi
[void]$p.Start()
$outTask = $p.StandardOutput.ReadToEndAsync()
$errTask = $p.StandardError.ReadToEndAsync()
$finished = $p.WaitForExit($TimeoutSec * 1000)
$timedOut = $false
if (-not $finished) {
  $timedOut = $true
  try { $p.Kill() } catch {}
  try { [void]$p.WaitForExit(30000) } catch {}
}
$stdout = ''
$stderr = ''
try { $stdout = $outTask.Result } catch {}
try { $stderr = $errTask.Result } catch {}
Set-Content -Path $StdoutPath -Value $stdout -Encoding UTF8
if ($stderr) { Add-Content -Path $StdoutPath -Value $stderr -Encoding UTF8 }
$sw.Stop()
if ($timedOut) { $rc = 124 } else { $rc = $p.ExitCode }
$argList = @($Exe) + @($ArgLine)
$rec = [ordered]@{
  argv = $argList
  cwd = $WorkDir
  rc = $rc
  timed_out = $timedOut
  seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
  timeout_s = $TimeoutSec
  log = $LogPath
  stdout = $StdoutPath
  note = $Note
}
($rec | ConvertTo-Json -Compress) | Add-Content -Path $CmdJsonl -Encoding UTF8
exit $rc
