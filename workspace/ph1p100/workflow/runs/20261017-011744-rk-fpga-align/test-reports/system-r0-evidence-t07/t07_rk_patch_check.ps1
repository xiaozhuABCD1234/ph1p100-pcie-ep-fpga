# t07_rk_patch_check.ps1 — independent offline verification of T07 RK driver patch
# 1) copy the FROZEN reference tree (read-only source) to this evidence dir
# 2) git apply --check, apply, reverse-check, reverse
# 3) compare applied tree byte-for-byte against backend/rk-driver-src
# 4) dump ABI-relevant diffs (ioctl header / rust ioctl) as evidence
$ErrorActionPreference = "Stop"

$runRel = "workflow/runs/20261017-011744-rk-fpga-align"
$root = (Get-Location).Path
$ref  = Join-Path $root "$runRel/references/peer-driver-a0215c5"
$patch = Join-Path $root "$runRel/backend/patches/rka1-driver.patch"
$delsrc = Join-Path $root "$runRel/backend/rk-driver-src"
$work = Join-Path $PSScriptRoot "rk-patch-check"
$pristine = Join-Path $work "pristine"

if (-not (Test-Path $ref)) { throw "frozen reference missing: $ref" }
if (-not (Test-Path $patch)) { throw "patch missing: $patch" }

# fresh working copy (only inside evidence dir)
if (Test-Path $pristine) { throw "evidence subdir already exists; inspect manually: $pristine" }
New-Item -ItemType Directory -Force -Path $pristine | Out-Null
Copy-Item -Path (Join-Path $ref "*") -Destination $pristine -Recurse -Force

$log = Join-Path $work "rk-patch-check.log"
"=== T07 RK patch independent check ($(Get-Date -Format o)) ===" | Out-File -Encoding utf8 $log
"ref_tree = $ref" | Out-File -Encoding utf8 -Append $log

# local ASCII patch copy
$localPatch = Join-Path $pristine "rka1-driver.patch"
Copy-Item -Path $patch -Destination $localPatch -Force

Push-Location $pristine
try {
    "--- git apply --check ---" | Out-File -Encoding utf8 -Append $log
    & git apply -p1 --check "rka1-driver.patch" 2>&1 | Out-File -Encoding utf8 -Append $log
    $chk = $LASTEXITCODE
    "check exit=$chk" | Out-File -Encoding utf8 -Append $log

    "--- git apply ---" | Out-File -Encoding utf8 -Append $log
    & git apply -p1 "rka1-driver.patch" 2>&1 | Out-File -Encoding utf8 -Append $log
    $app = $LASTEXITCODE
    "apply exit=$app" | Out-File -Encoding utf8 -Append $log

    "--- git apply -R --check (reverse after apply) ---" | Out-File -Encoding utf8 -Append $log
    & git apply -p1 -R --check "rka1-driver.patch" 2>&1 | Out-File -Encoding utf8 -Append $log
    $rchk = $LASTEXITCODE
    "reverse-check exit=$rchk" | Out-File -Encoding utf8 -Append $log

    Remove-Item -LiteralPath $localPatch -Force
} finally {
    Pop-Location
}

# ---- byte compare: pristine(patched) vs backend/rk-driver-src ----
$differences = @()
$refFiles = Get-ChildItem $pristine -Recurse -File | ForEach-Object { $_.FullName.Substring($pristine.Length+1).Replace('\','/') }
$dstFiles = Get-ChildItem $delsrc -Recurse -File | ForEach-Object { $_.FullName.Substring($delsrc.Length+1).Replace('\','/') }
foreach ($f in $dstFiles) {
    $a = Join-Path $pristine $f
    if (-not (Test-Path -LiteralPath $a)) { $differences += "MISSING_IN_APPLIED: $f"; continue }
    $ha = (Get-FileHash -LiteralPath $a -Algorithm SHA256).Hash
    $hb = (Get-FileHash -LiteralPath (Join-Path $delsrc $f) -Algorithm SHA256).Hash
    if ($ha -ne $hb) { $differences += "SHA_DIFF: $f" }
}
foreach ($f in $refFiles) {
    $b = Join-Path $delsrc $f
    if (-not (Test-Path -LiteralPath $b)) { $differences += "APPLIED_ONLY_FILE: $f" }
}

# ---- ABI-relevant diffs as evidence ----
foreach ($abi in @("include/anlogic_pci_ioctl.h","app/rs/src/ioctl.rs","src/anlogic_pci.h")) {
    $a = Join-Path $ref $abi
    $b = Join-Path $pristine $abi
    $out = Join-Path $work ("diff-" + $abi.Replace('/','_') + ".txt")
    if ((Test-Path (Join-Path $ref $abi)) -and (Test-Path $b)) {
        $da = Get-Content $a -Encoding UTF8; $db = Get-Content $b -Encoding UTF8
        Compare-Object $da $db | ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" } | Out-File -Encoding utf8 $out
    }
}

$summary = [pscustomobject]@{
    check_exit = $chk
    apply_exit = $app
    reverse_check_exit = $rchk
    applied_vs_rk_driver_src_differences = $differences.Count
    differences = $differences
}
$summary | ConvertTo-Json -Depth 4 | Out-File -Encoding utf8 (Join-Path $work "rk-patch-check-result.json")
"diff_count=$($differences.Count)" | Out-File -Encoding utf8 -Append $log
$differences | Out-File -Encoding utf8 -Append $log
Get-Content $log | Write-Output
