$ErrorActionPreference = 'Stop'
$root = 'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
$run = Join-Path $root 'workflow/runs/20261017_202845_single_tester_scope_limit'
$baseline = Get-Content -LiteralPath (Join-Path $run 'config-baseline.json') -Raw | ConvertFrom-Json
$dispatch = Get-Content -LiteralPath (Join-Path $run 'dispatch.json') -Raw | ConvertFrom-Json
if ($dispatch.plan_revision -ne 2) { throw 'PLAN_REVISION_CONFLICT' }
$updates = Get-Content -LiteralPath (Join-Path $run 'dev-evidence/config-updates.json') -Raw | ConvertFrom-Json
$allowed = @($dispatch.write_scope.configuration_paths)
$names = @($updates.PSObject.Properties.Name)
if (@(Compare-Object $allowed $names).Count -ne 0) { throw 'WRITE_SCOPE_CONFLICT' }
$rootPath = (Resolve-Path -LiteralPath $root).Path.TrimEnd('\')
foreach ($relative in $names) {
    $path = [IO.Path]::GetFullPath((Join-Path $root $relative))
    if (-not $path.StartsWith($rootPath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "OUT_OF_SCOPE: $relative" }
    $cursorPath = $path
    while (-not (Test-Path -LiteralPath $cursorPath)) { $cursorPath = Split-Path -Parent $cursorPath }
    $cursor = Get-Item -LiteralPath $cursorPath
    while ($cursor.FullName.Length -ge $rootPath.Length) {
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "REPARSE_POINT: $relative" }
        if ($cursor.FullName -eq $rootPath) { break }
        if ($cursor -is [IO.FileInfo]) { $cursor = $cursor.Directory } else { $cursor = $cursor.Parent }
    }
}
foreach ($entry in $baseline.files) {
    if ((Get-FileHash -LiteralPath $entry.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.sha256) { throw "BASELINE_DRIFT: $($entry.path)" }
}
foreach ($newPath in @('.agents/skills/fpga-tester/SKILL.md','.agents/skills/fpga-orchestrator/references/work-limits.md','.agents/skills/fpga-orchestrator/agents/openai.yaml')) {
    if (Test-Path -LiteralPath (Join-Path $root $newPath)) { throw "UNEXPECTED_NEW_FILE: $newPath" }
}
$encoding = [Text.UTF8Encoding]::new($false)
foreach ($relative in $names) {
    $path = Join-Path $root $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    $text = [string]$updates.$relative
    if ($relative -eq 'AGENTS.md') {
        $original = [IO.File]::ReadAllBytes($path)
        $prefixLength = [int]$baseline.agents_protected_prefix.byte_length
        $prefix = [byte[]]$original[0..($prefixLength - 1)]
        $marker = '## 后续任务的默认工作流'
        $suffix = $encoding.GetBytes($text.Substring($text.IndexOf($marker, [StringComparison]::Ordinal)))
        [IO.File]::WriteAllBytes($path, [byte[]]($prefix + $suffix))
    } else {
        [IO.File]::WriteAllText($path, $text, $encoding)
    }
}
Write-Output 'APPLY_PASS: 19 explicitly allowed configuration files synchronized; protected AGENTS prefix copied verbatim.'
