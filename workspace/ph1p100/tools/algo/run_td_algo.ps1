# run_td_algo.ps1 - T09.rk-align-algo TD runner for the module-level small top.
# Temporary subst for the Chinese project path (own mapping, removed at the end).
# Creates a fresh project under the run's algo/g2/<name>/ and runs the single
# session 00_all.tcl.  No download, no Flash, no other project touched.
param(
    [string]$Name = "smalltop",
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"
if ($Root -ne "") { $root = (Resolve-Path $Root).Path }
else { $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
Write-Host "project_root = $root"

$tdBin = "D:\anlogic\TD_Release_2026.2\bin"
if (-not (Test-Path (Join-Path $tdBin "td_commands_prompt.exe"))) { throw "td_commands_prompt.exe not found" }

$mappedRoot = $root
$substDrive = $null
if ($root -match '[^\x00-\x7F]') {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($L in @('S','T','U','V','W','X','Y','Z')) {
        if ($used -notcontains $L -and -not (Test-Path "${L}:\")) {
            & subst "${L}:" $root | Out-Null
            $substDrive = $L
            $mappedRoot = "${L}:\"
            break
        }
    }
    if (-not $substDrive) { throw "no free drive letter for subst" }
    Write-Host "subst $substDrive`: -> $root (temporary)"
}

function To-Mapped([string]$p) {
    if ($substDrive -and $p.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "$mappedRoot" + $p.Substring($root.Length).TrimStart('\')
    }
    return $p
}

$outDirF = Join-Path $root ("workflow\runs\20261017-011744-rk-fpga-align\algo\g2\" + $Name)
New-Item -ItemType Directory -Force -Path $outDirF | Out-Null
$outMapped = To-Mapped $outDirF

$tclSrc = Join-Path $root "tools\algo\td\00_all.tcl"
$tclDst = Join-Path $outDirF "00_all.tcl"
$txt = [System.IO.File]::ReadAllText($tclSrc)
$txt = $txt.Replace("R:/", ($mappedRoot -replace '\\','/'))
[System.IO.File]::WriteAllText($tclDst, $txt)

$cmdLog = Join-Path $outDirF "commands.log"
"cmd: td_commands_prompt.exe 00_all.tcl (cwd=$outMapped) root=$root at $(Get-Date -Format o)" |
    Out-File -Encoding utf8 -Append $cmdLog

Push-Location $outMapped
try {
    $ErrorActionPreference = "Continue"
    & (Join-Path $tdBin "td_commands_prompt.exe") "00_all.tcl" 2>&1 |
        Tee-Object -FilePath (Join-Path $outDirF "td_00_all.log") | Out-Null
    $exit = $LASTEXITCODE
    "stage=00_all exit=$exit" | Out-File -Encoding utf8 -Append $cmdLog
    Write-Host "== td exit $exit =="
    Get-Content (Join-Path $outDirF "td_00_all.log") -Tail 20
    if ($exit -ne 0) { throw "td 00_all failed (exit $exit)" }
} finally {
    Pop-Location
    if ($substDrive) { & subst "$substDrive`:" /D | Out-Null; Write-Host "subst removed" }
}
