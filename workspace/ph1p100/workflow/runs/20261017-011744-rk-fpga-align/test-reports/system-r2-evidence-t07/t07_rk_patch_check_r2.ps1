# t07_rk_patch_check_r2.ps1 — r2 re-verification of the RK driver patch
# Runs entirely in %TEMP% (outside the project git repo, where `git apply` behaves
# normal); copies the frozen driver reference, applies the frozen patch, compares
# the applied tree against backend/rk-driver-src, records results in this dir.
$ErrorActionPreference = "Stop"

$runRel = "workflow/runs/20261017-011744-rk-fpga-align"
$root = (Get-Location).Path
$ref   = Join-Path $root "$runRel/references/peer-driver-a0215c5"
$patch = Join-Path $root "$runRel/backend/patches/rka1-driver.patch"
$dst   = Join-Path $root "$runRel/backend/rk-driver-src"

$work = Join-Path $env:TEMP ("t07_r2_patchchk_" + (Get-Random))
$pri  = Join-Path $work "pristine"
New-Item -ItemType Directory -Force -Path $pri | Out-Null
Copy-Item -Path (Join-Path $ref "*") -Destination $pri -Recurse -Force
$localPatch = Join-Path $pri "rka1-driver.patch"
Copy-Item -Path $patch -Destination $localPatch -Force

$log = Join-Path $PSScriptRoot "rk-patch-check-r2.log"
"=== T07 r2 RK patch check ($(Get-Date -Format o)) ===" | Out-File -Encoding utf8 $log
"temp_work = $work" | Out-File -Encoding utf8 -Append $log

Push-Location $pri
try {
    & git apply -p1 --check "rka1-driver.patch" 2>&1 | Out-File -Encoding utf8 -Append $log
    $chk = $LASTEXITCODE; "check exit=$chk" | Out-File -Encoding utf8 -Append $log
    & git apply -p1 "rka1-driver.patch" 2>&1 | Out-File -Encoding utf8 -Append $log
    $app = $LASTEXITCODE; "apply exit=$app" | Out-File -Encoding utf8 -Append $log
    & git apply -p1 -R --check "rka1-driver.patch" 2>&1 | Out-File -Encoding utf8 -Append $log
    $rchk = $LASTEXITCODE; "reverse-check exit=$rchk" | Out-File -Encoding utf8 -Append $log
    Remove-Item -LiteralPath $localPatch -Force
} finally { Pop-Location }

$diffs = @()
$dirs = @()
$priFiles = Get-ChildItem $pri -Recurse -File | ForEach-Object { $_.FullName.Substring($pri.Length+1).Replace('\','/') }
$dstFiles = Get-ChildItem $dst -Recurse -File | ForEach-Object { $_.FullName.Substring($dst.Length+1).Replace('\','/') }
foreach ($f in $dstFiles) {
    $a = Join-Path $pri $f
    if (-not (Test-Path -LiteralPath $a)) { $diffs += "MISSING_IN_APPLIED: $f"; continue }
    $ha = (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash
    $hb = (Get-FileHash -LiteralPath (Join-Path $dst $f) -Algorithm SHA256).Hash
    if ($ha -ne $hb) {
        # check whether it is only CRLF vs LF
        $ca = ([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($a))) -replace "`r`n","`n"
        $cb = ([System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes((Join-Path $dst $f)))) -replace "`r`n","`n"
        if ($ca -eq $cb) { $dirs += "LINE_ENDINGS_ONLY: $f" } else { $diffs += "SHA_DIFF: $f" }
    }
}
foreach ($f in $priFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $dst $f))) { $diffs += "APPLIED_ONLY_FILE: $f" }
}

$summary = [pscustomobject]@{
    check_exit = $chk; apply_exit = $app; reverse_check_exit = $rchk
    applied_files = $priFiles.Count; dst_files = $dstFiles.Count
    content_differences = $diffs.Count; line_ending_only = $dirs.Count
    diffs = $diffs; line_ending_notes = $dirs
}
$summary | ConvertTo-Json -Depth 4 | Out-File -Encoding utf8 (Join-Path $PSScriptRoot "rk-patch-check-result-r2.json")
"content_diffs=$($diffs.Count) line_ending_only=$($dirs.Count)" | Out-File -Encoding utf8 -Append $log
$diffs | Out-File -Encoding utf8 -Append $log
$dirs  | Out-File -Encoding utf8 -Append $log
Get-Content $log | Write-Output
