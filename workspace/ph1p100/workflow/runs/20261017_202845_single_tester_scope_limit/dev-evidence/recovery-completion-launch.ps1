$ErrorActionPreference = 'Stop'
$run='C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017_202845_single_tester_scope_limit'
$evidence=Join-Path $run 'dev-evidence'
$recordPath=Join-Path $evidence 'recovery-completion-launch.json'
if (Test-Path -LiteralPath $recordPath) { throw 'LAST_OPPORTUNITY_ALREADY_EXECUTED_NO_RETRY' }
$outPath=Join-Path $evidence 'recovery-completion-launch.stdout.txt'
$errPath=Join-Path $evidence 'recovery-completion-launch.stderr.txt'
$scriptPath=Join-Path $evidence 'recovery-completion.py'
$encoding=[Text.UTF8Encoding]::new($false)
$started=[DateTime]::UtcNow.ToString('o')
$owned=Start-Process -FilePath 'C:/Program Files/Python311/python.exe' -ArgumentList @('-u',('"'+$scriptPath+'"')) -WorkingDirectory $run -WindowStyle Hidden -RedirectStandardOutput $outPath -RedirectStandardError $errPath -PassThru
$timedOut=-not $owned.WaitForExit(179000)
if ($timedOut) { $owned.Kill(); $terminated=$owned.WaitForExit(1000); $exitCode=124 } else { $terminated=$true; $exitCode=$owned.ExitCode }
$result=[pscustomobject]@{started_utc=$started; ended_utc=[DateTime]::UtcNow.ToString('o'); owned_pid=$owned.Id; deadline_seconds=180; timed_out=$timedOut; terminated=$terminated; exit_code=$exitCode; stdout_path=$outPath; stderr_path=$errPath}
[IO.File]::WriteAllText($recordPath,($result|ConvertTo-Json),$encoding)
Get-Content -LiteralPath $outPath -Raw
Get-Content -LiteralPath $errPath -Raw
$result|ConvertTo-Json
exit $exitCode
