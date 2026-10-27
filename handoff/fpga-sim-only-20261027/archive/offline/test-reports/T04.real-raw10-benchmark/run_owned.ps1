param([Parameter(Mandatory=$true)][string]$Script,[string[]]$RunnerArgs=@(),[Parameter(Mandatory=$true)][string]$LogName,[int]$ExpectedExit=0)
$ErrorActionPreference='Stop'
$ev='D:\fpga\repos\ph1p100-pcie-ep-fpga\workflow\runs\20261027-060708_fpga-parallel-offline-delivery\test-reports\T04.real-raw10-benchmark'
$exe='C:\Program Files\Python311\python.exe'
$info=New-Object System.Diagnostics.ProcessStartInfo
$info.FileName=$exe
$info.Arguments=('-B "'+$Script+'" '+(($RunnerArgs|ForEach-Object{'"'+$_+'"'}) -join ' '))
$info.WorkingDirectory=$ev
$info.UseShellExecute=$false
$info.CreateNoWindow=$true
$info.RedirectStandardOutput=$true
$info.RedirectStandardError=$true
$proc=New-Object System.Diagnostics.Process
$proc.StartInfo=$info
$started=[DateTime]::UtcNow.ToString('o')
[void]$proc.Start()
$stdout=$proc.StandardOutput.ReadToEndAsync()
$stderr=$proc.StandardError.ReadToEndAsync()
$timedOut=-not $proc.WaitForExit(300000)
if($timedOut){$proc.Kill();$proc.WaitForExit()}
$out=$stdout.GetAwaiter().GetResult()
$err=$stderr.GetAwaiter().GetResult()
[IO.File]::WriteAllText((Join-Path $ev "$LogName.stdout.log"),$out)
[IO.File]::WriteAllText((Join-Path $ev "$LogName.stderr.log"),$err)
$record=[ordered]@{executable=$exe;script=$Script;arguments=$RunnerArgs;cwd=$ev;started_utc=$started;ended_utc=[DateTime]::UtcNow.ToString('o');pid=$proc.Id;timeout_seconds=300;timed_out=$timedOut;exit_code=$proc.ExitCode;expected_exit=$ExpectedExit;stdout_path=(Join-Path $ev "$LogName.stdout.log");stderr_path=(Join-Path $ev "$LogName.stderr.log")}
$record|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $ev "$LogName.command.json") -Encoding UTF8
Write-Output $out
if($err){Write-Output $err}
Write-Output "OWNED_RUN exit=$($proc.ExitCode) expected=$ExpectedExit timeout=$timedOut log=$LogName"
if($timedOut -or $proc.ExitCode -ne $ExpectedExit){throw 'owned runner did not meet expected exit'}
