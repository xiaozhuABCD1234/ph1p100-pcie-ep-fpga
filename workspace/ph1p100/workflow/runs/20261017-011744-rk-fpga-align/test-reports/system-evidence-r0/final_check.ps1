$ErrorActionPreference = 'Stop'
$taskRun = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$taskManifestPath = Join-Path $taskRun 'candidate-manifest.json'
$taskManifest = Get-Content -Raw -LiteralPath $taskManifestPath | ConvertFrom-Json
$taskExpected = '9662167a4af6fcea43a76491a9507b191552fa52209648147de02f91cfd877c5'
$taskErrors = @()
foreach ($taskEntry in $taskManifest.files) {
    $taskInfo = Get-Item -LiteralPath $taskEntry.path
    $taskHash = (Get-FileHash -LiteralPath $taskEntry.path -Algorithm SHA256).Hash.ToLower()
    if ($taskInfo.Length -ne $taskEntry.bytes -or $taskHash -ne $taskEntry.sha256) { $taskErrors += $taskEntry.path }
}
$taskReport = Join-Path (Split-Path -Parent $PSScriptRoot) 'T03.rk-align-freeze-r0-system.md'
$taskText = Get-Content -Raw -LiteralPath $taskReport
$taskTitleCount = [regex]::Matches($taskText, '(?m)^### 判定：').Count
$taskReportOkay = $taskText.StartsWith('### 判定：PASS') -and $taskTitleCount -eq 1
$taskFinalHash = (Get-FileHash -LiteralPath $taskManifestPath -Algorithm SHA256).Hash.ToLower()
$taskGitVersion = (& git --version | Out-String).Trim()
$taskGitExit = $LASTEXITCODE
$taskOutput = [ordered]@{
    marker='SYSTEM_FINAL_CHECK_COMPLETE'
    recorded_at=(Get-Date).ToString('o')
    cwd=(Get-Location).Path
    powershell_version=$PSVersionTable.PSVersion.ToString()
    git_version=$taskGitVersion
    git_version_exit=$taskGitExit
    manifest_path=$taskManifestPath
    manifest_sha256=$taskFinalHash
    expected_manifest_sha256=$taskExpected
    frozen_file_count=$taskManifest.files.Count
    frozen_file_mismatches=$taskErrors
    report_path=$taskReport
    report_bytes=(Get-Item -LiteralPath $taskReport).Length
    report_sha256=(Get-FileHash -LiteralPath $taskReport -Algorithm SHA256).Hash.ToLower()
    unique_pass_first_line=$taskReportOkay
    complete=($taskFinalHash -eq $taskExpected -and $taskErrors.Count -eq 0 -and $taskReportOkay -and $taskGitExit -eq 0)
}
$taskOutput | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'final-check.json') -Encoding utf8
$taskOutput | ConvertTo-Json -Depth 8
if (-not $taskOutput.complete) { exit 1 }
