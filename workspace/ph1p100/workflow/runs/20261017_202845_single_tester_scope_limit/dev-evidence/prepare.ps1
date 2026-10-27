$ErrorActionPreference = 'Stop'
$root = 'C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道'
$run = Join-Path $root 'workflow/runs/20261017_202845_single_tester_scope_limit'
$baseline = Get-Content -LiteralPath (Join-Path $run 'config-baseline.json') -Raw | ConvertFrom-Json
$configPaths = (Get-Content -LiteralPath (Join-Path $run 'dispatch.json') -Raw | ConvertFrom-Json).write_scope.configuration_paths
$resolvedRoot = (Resolve-Path -LiteralPath $root).Path.TrimEnd('\')
foreach ($relative in $configPaths) {
    $path = Join-Path $root $relative
    $parent = Split-Path -Parent $path
    while (-not (Test-Path -LiteralPath $parent)) { $parent = Split-Path -Parent $parent }
    $resolvedParent = (Resolve-Path -LiteralPath $parent).Path
    if (-not $resolvedParent.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and $resolvedParent -ne $resolvedRoot) { throw "OUT_OF_SCOPE_PARENT: $relative" }
    $cursor = Get-Item -LiteralPath $parent
    while ($cursor.FullName.Length -ge $resolvedRoot.Length) {
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "REPARSE_POINT: $relative" }
        if ($cursor.FullName -eq $resolvedRoot) { break }
        $cursor = $cursor.Parent
    }
    if (Test-Path -LiteralPath $path) {
        if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "REPARSE_FILE: $relative" }
    }
}
foreach ($item in $baseline.files) {
    if ((Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.sha256) { throw "BASELINE_DRIFT: $($item.path)" }
    $relative = $item.path.Substring($resolvedRoot.Length + 1)
    $destination = Join-Path (Join-Path $run 'dev-evidence/before') $relative
    [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
    [IO.File]::WriteAllBytes($destination, [IO.File]::ReadAllBytes($item.path))
}
Write-Output 'PREPARE_PASS: all 18 configuration paths contained; 16 baseline hashes match; originals preserved.'
