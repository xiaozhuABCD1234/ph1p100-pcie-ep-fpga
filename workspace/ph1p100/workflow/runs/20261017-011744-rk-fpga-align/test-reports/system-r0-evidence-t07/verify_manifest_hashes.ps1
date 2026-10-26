# T07.rk-align-backend r0 system-dimension independent verification
# Verifies every SHA256 entry in backend/candidate-manifest.json against the actual files.
# Read-only. Writes result JSON next to this script.
# Run from the project root (no Chinese literals inside this file).
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
    foreach ($e in $m.$sec) {
        # Paths are either project-root-relative (fpga/..., tools/...) or run-dir-relative (backend/...).
        $p = Join-Path $Root $e.path
        $base = "root"
        if (-not (Test-Path -LiteralPath $p)) {
            $p2 = Join-Path $Root (Join-Path $RunDir $e.path)
            if (Test-Path -LiteralPath $p2) { $p = $p2; $base = "run" }
        }
        $checked++
        if (-not (Test-Path -LiteralPath $p)) {
            $missing++
            $result += [pscustomobject]@{ section=$sec; path=$e.path; base=$base; status="MISSING"; expected=$e.sha256 }
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

# Candidate root existence
$candRoot = Join-Path $Root $m.candidate_root
$candExists = Test-Path -LiteralPath $candRoot

$out = [pscustomobject]@{
    manifest_path = "$RunDir/backend/candidate-manifest.json"
    manifest_sha256 = $manifestSha
    checked = $checked
    missing = $missing
    sha_mismatch = $mismatch
    candidate_root_exists = $candExists
    sections = $sections
    details = $result
}
$outPath = Join-Path $PSScriptRoot "manifest-verify-result.json"
$out | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $outPath -Encoding UTF8
Write-Output ("checked=$checked missing=$missing sha_mismatch=$mismatch candidate_root_exists=$candExists")
Write-Output ("RESULT_JSON=" + $outPath)
