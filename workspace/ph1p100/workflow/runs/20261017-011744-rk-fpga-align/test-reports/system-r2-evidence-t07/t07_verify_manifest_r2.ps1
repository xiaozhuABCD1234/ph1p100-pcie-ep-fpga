# t07_verify_manifest_r2.ps1 — T07 r2 system-dimension independent verification
# Verifies every SHA256 entry in the round2 candidate manifest against the files.
# Read-only. Uses the manifest's own path_base mapping; falls back to the other base.
# Run from the project root.
param(
    [string]$Root = "",
    [string]$RunDir = "workflow/runs/20261017-011744-rk-fpga-align"
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrEmpty($Root)) { $Root = (Get-Location).Path }
$manifestPath = Join-Path $Root "$RunDir/backend/candidate-manifest.json"
$manifestSha = (Get-FileHash $manifestPath -Algorithm SHA256).Hash
$m = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

$sections = @("production_inputs","build_scripts","test_inputs","rk_patch_inputs","build_artifacts")
$result = @()
$missing = 0; $mismatch = 0; $checked = 0
foreach ($sec in $sections) {
    $base = "root"
    if ($m.path_base -and ($m.path_base.$sec -match "run")) { $base = "run" }
    foreach ($e in $m.$sec) {
        $p = if ($base -eq "run") { Join-Path $Root (Join-Path $RunDir $e.path) } else { Join-Path $Root $e.path }
        if (-not (Test-Path -LiteralPath $p)) {
            # fallback to the other base
            $p2 = if ($base -eq "run") { Join-Path $Root $e.path } else { Join-Path $Root (Join-Path $RunDir $e.path) }
            if (Test-Path -LiteralPath $p2) { $p = $p2; $base = ($base + "+fb") }
        }
        $checked++
        if (-not (Test-Path -LiteralPath $p)) {
            $missing++
            $result += [pscustomobject]@{ section=$sec; path=$e.path; base=$base; status="MISSING" }
            continue
        }
        $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
        $ok = ($h -eq $e.sha256)
        if (-not $ok) { $mismatch++ }
        $sz = ""
        if ($e.size) { $actual=(Get-Item -LiteralPath $p).Length; $sz = if ($actual -eq $e.size) {"size_ok"} else {"SIZE_MISMATCH:$actual"} }
        $result += [pscustomobject]@{ section=$sec; path=$e.path; base=$base; status=$(if($ok){"OK"}else{"SHA_MISMATCH"}); size=$sz }
    }
}

$candRoot = Join-Path $Root $m.candidate_root
$volatile = $null
if ($m.volatile_excluded) { $volatile = ($m.volatile_excluded | ConvertTo-Json -Depth 3 -Compress) }

$out = [pscustomobject]@{
    manifest_path = "$RunDir/backend/candidate-manifest.json"
    manifest_sha256 = $manifestSha
    schema = $m.schema
    round = $m.round
    checked = $checked
    missing = $missing
    sha_mismatch = $mismatch
    candidate_root_exists = (Test-Path -LiteralPath $candRoot)
    volatile_excluded_present = ($null -ne $m.volatile_excluded)
    details = $result
}
$outPath = Join-Path $PSScriptRoot "manifest-verify-result-r2.json"
$out | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Output ("checked=$checked missing=$missing sha_mismatch=$mismatch schema=" + $m.schema + " round=" + $m.round)
Write-Output ("volatile_excluded_present=" + ($null -ne $m.volatile_excluded))
Write-Output ("RESULT_JSON=" + $outPath)
