param([ValidateSet('A','B','C')][string]$Stage)
$ErrorActionPreference = 'Stop'
$run = 'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017_202845_single_tester_scope_limit'
$evidence = Join-Path $run 'dev-evidence'
$encoding = [Text.UTF8Encoding]::new($false)
$budgetPath = Join-Path $evidence 'recovery-budget.json'
$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
if ($Stage -eq 'A') {
    if (Test-Path -LiteralPath $budgetPath) { throw 'RECOVERY_ALREADY_STARTED_NO_AUTOMATIC_RETRY' }
    [IO.File]::WriteAllText($budgetPath,(@{start_epoch_seconds=$now; deadline_epoch_seconds=($now+300.0); total_deadline_seconds=300; recovery_revision=1} | ConvertTo-Json),$encoding)
}
$budget = Get-Content -LiteralPath $budgetPath -Raw | ConvertFrom-Json
$remaining = [double]$budget.deadline_epoch_seconds - $now
if ($remaining -le 2) { throw 'TOTAL_STATIC_DEADLINE_NO_SAFE_TIME_REMAINING' }
$outPath = Join-Path $evidence ('recovery-launch-'+$Stage.ToLowerInvariant()+'.stdout.txt')
$errPath = Join-Path $evidence ('recovery-launch-'+$Stage.ToLowerInvariant()+'.stderr.txt')
$pythonPath = 'C:/Program Files/Python311/python.exe'
$scriptPath = Join-Path $evidence 'recovery-static.py'
$arguments = @('-u', ('"'+$scriptPath+'"'), $Stage)
$owned = Start-Process -FilePath $pythonPath -ArgumentList $arguments -WorkingDirectory (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $run))) -WindowStyle Hidden -RedirectStandardOutput $outPath -RedirectStandardError $errPath -PassThru
$waitMs = [int]([Math]::Floor(($remaining-1)*1000))
$timedOut = -not $owned.WaitForExit($waitMs)
if ($timedOut) {
    $owned.Kill()
    $terminated = $owned.WaitForExit(1000)
    $exitCode = 124
} else {
    $terminated = $true
    $exitCode = $owned.ExitCode
}
$result = [pscustomobject]@{stage=$Stage; owned_pid=$owned.Id; started_epoch_seconds=$now; ended_utc=[DateTime]::UtcNow.ToString('o'); deadline_seconds=$remaining; timed_out=$timedOut; terminated=$terminated; exit_code=$exitCode; stdout_path=$outPath; stderr_path=$errPath}
[IO.File]::WriteAllText((Join-Path $evidence ('recovery-launch-'+$Stage.ToLowerInvariant()+'.json')),($result | ConvertTo-Json),$encoding)
Get-Content -LiteralPath $outPath -Raw
Get-Content -LiteralPath $errPath -Raw
$result | ConvertTo-Json
exit $exitCode
