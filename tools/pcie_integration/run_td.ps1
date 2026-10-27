# =============================================================================
#  run_td.ps1 — T07.rk-align-backend：TD 6.2.3 CLI 统一入口（可复现、留全日志）
#
#  与 run_sim.ps1 同样处理中文路径：临时 subst 映射（只建自己的，用完撤自己的）。
#  注意：
#   · 只在新工程目录（OUTPUT_DIR/backend/candidate/prj）里建工程；
#   · 不执行 peer 的 download_sram.tcl，不 reset/clean 别人的工程，不写 Flash。
#
#  用法（项目根下）：
#    powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_td.ps1 -Stage 01_create
# =============================================================================
param(
    [Parameter(Mandatory=$true)][string]$Stage,
    [string]$OutDir = "build/td",
    [string]$Root = "",
    [int]$TimeoutMin = 90
)

$ErrorActionPreference = "Stop"
if ($Root -ne "") { $root = (Resolve-Path $Root).Path }
else { $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
Write-Host "project_root = $root"

$tdBin = $env:TD_BIN
if (-not $tdBin) { throw "TD_BIN not set (export e.g. <TD_Release_2026.2>\bin)" }
if (-not (Test-Path (Join-Path $tdBin "td_commands_prompt.exe"))) { throw "td_commands_prompt.exe not found" }

# ---- 中文路径：临时 subst ----
$mappedRoot = $root
$substDrive = $null
if ($root -match '[^\x00-\x7F]') {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($L in @('R','S','T','U','V','W','X','Y','Z')) {
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

if ([System.IO.Path]::IsPathRooted($OutDir)) { $outDirF = $OutDir } else { $outDirF = Join-Path $root $OutDir }
New-Item -ItemType Directory -Force -Path $outDirF | Out-Null
$outMapped = To-Mapped $outDirF
$substDriveOut = $null
if ($outMapped -match '[^\x00-\x7F]') {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($L in @('R','S','T','U','V','W','X','Y','Z')) {
        if ($used -notcontains $L -and -not (Test-Path "${L}:\")) {
            & subst "${L}:" $outDirF | Out-Null
            $substDriveOut = $L
            $outMapped = "${L}:\"
            break
        }
    }
    if (-not $substDriveOut) { throw "no free drive letter for outdir subst" }
}
$tclSrc = Join-Path $root ("tools\pcie_integration\td\" + $Stage + ".tcl")
if (-not (Test-Path $tclSrc)) { throw "script not found: $tclSrc" }

# 脚本复制到工程目录并做盘符替换（用 [System.IO.File] 保证内容正确）
$tclDst = Join-Path $outDirF ($Stage + ".tcl")
$txt = [System.IO.File]::ReadAllText($tclSrc)
$txt = $txt.Replace("REPO_ROOT", ($mappedRoot -replace '\\','/').TrimEnd('/'))
$txt = $txt.Replace("SKIP_MARKER", "unused")
[System.IO.File]::WriteAllText($tclDst, $txt)
$logPath = Join-Path $outDirF ("td_" + $Stage + ".log")
$cmdLog  = Join-Path $outDirF "commands.log"
"cmd: td_commands_prompt.exe $($Stage).tcl  (cwd=$outMapped) root=$root at $(Get-Date -Format o)" |
    Out-File -Encoding utf8 -Append $cmdLog

Push-Location $outMapped
try {
    $ErrorActionPreference = "Continue"
    & (Join-Path $tdBin "td_commands_prompt.exe") ($Stage + ".tcl") 2>&1 |
        Tee-Object -FilePath $logPath | Out-Null
    $exit = $LASTEXITCODE
    "stage=$Stage exit=$exit" | Out-File -Encoding utf8 -Append $cmdLog
    Write-Host "== td exit $exit =="
    Get-Content $logPath -Tail 25
    if ($exit -ne 0) { throw "td stage $Stage failed (exit $exit)" }
} finally {
    Pop-Location
    if ($substDriveOut) { & subst "$substDriveOut`:" /D | Out-Null; Write-Host "outdir subst removed" }
    if ($substDrive) { & subst "$substDrive`:" /D | Out-Null; Write-Host "subst removed" }
}
