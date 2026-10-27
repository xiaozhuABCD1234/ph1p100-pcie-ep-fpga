# =============================================================================
#  run_sim.ps1 — T07.rk-align-backend 的 ModelSim 统一入口（可复现、留全日志）
#
#  为什么需要它：
#   · 项目路径含中文，ModelSim(vlog/vsim) 打不开中文路径 → 本脚本自动用 subst
#     建一个**临时**盘符映射（只映射项目根，用完立即撤销，不改任何文件）。
#   · 所有 vlog/vsim 命令、cwd、退出码、日志都落盘，便于三测试独立复核。
#
#  用法（项目根下）：
#    powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 `
#        -Tb tb_ddr_frame_pusher_rka1 `
#        -OutDir workflow/runs/20261017-011744-rk-fpga-align/backend/g1/msim/pusher_rka1 `
#        -TbFiles sim/tb/tb_ddr_frame_pusher_rka1.v `
#        -Defines MIPI_PHY_SIM_STUB
#
#  参数：
#    -Tb        顶层 TB 模块名（vsim 参数）
#    -OutDir    输出目录（相对项目根；work 库、日志都放这里）
#    -TbFiles   额外编译的 TB 文件（相对 fpga/csi2/pcie_integration 或绝对路径）
#    -Defines   逗号分隔的 +define 宏
#    -VsimArgs  额外 vsim 参数
# =============================================================================
param(
    [Parameter(Mandatory=$true)][string]$Tb,
    [Parameter(Mandatory=$true)][string]$OutDir,
    [string[]]$TbFiles = @(),
    [string]$Defines = "",
    [string]$VsimArgs = "",
    [int]$RunTimeSec = 1800,
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"
if ($Root -ne "") { $root = (Resolve-Path $Root).Path }
else { $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path }
Write-Host "project_root = $root"

$msimBin = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
if (-not (Test-Path (Join-Path $msimBin "vlog.exe"))) { throw "ModelSim vlog not found at $msimBin" }
$env:PATH = "$msimBin;$env:PATH"

# ---- 中文路径处理：临时 subst 映射（只建自己的，用完撤自己的）----
$mappedRoot = $root
$substDrive = $null
if ($root -match '[^\x00-\x7F]') {
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    foreach ($L in @('R','S','T','U','V','W','X','Y','Z')) {
        if ($used -notcontains $L) {
            $probe = "${L}:\"
            if (Test-Path $probe) { continue }
            & subst "${L}:" $root | Out-Null
            $substDrive = $L
            $mappedRoot = "${L}:\"
            break
        }
    }
    if (-not $substDrive) { throw "no free drive letter for subst" }
    Write-Host "subst $substDrive`: -> $root (temporary, removed at end)"
}

function To-Mapped([string]$p) {
    if ($substDrive -and $p.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return "$mappedRoot" + $p.Substring($root.Length).TrimStart('\')
    }
    return $p
}

$intRoot  = To-Mapped (Join-Path $root "fpga\csi2\pcie_integration")
$outDirF  = Join-Path $root $OutDir
New-Item -ItemType Directory -Force -Path $outDirF | Out-Null
$outMapped = To-Mapped $outDirF

$vlogLog = Join-Path $outDirF "vlog.log"
$vsimLog = Join-Path $outDirF "vsim.log"
$cmdLog  = Join-Path $outDirF "commands.log"

"# run_sim.ps1 $(Get-Date -Format o)" | Out-File -Encoding utf8 $cmdLog
"root        = $root"                | Out-File -Encoding utf8 -Append $cmdLog
"mapped_root = $mappedRoot"          | Out-File -Encoding utf8 -Append $cmdLog
"tb          = $Tb"                  | Out-File -Encoding utf8 -Append $cmdLog
"outdir      = $outDirF"             | Out-File -Encoding utf8 -Append $cmdLog
"defines     = $Defines"             | Out-File -Encoding utf8 -Append $cmdLog

# ---- 生成绝对路径文件清单（把 -f 的相对路径按 sim 根展开）----
$flist = Join-Path $outDirF "abs.f"
$simRoot = (($intRoot -replace '\\','/') + "/sim")
$lines = Get-Content (Join-Path $root "fpga\csi2\pcie_integration\sim\compile_checked.f")
$abs = @()
foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -eq "" -or $t.StartsWith("#")) { continue }
    if ($t -match '^[A-Za-z]:') { $abs += ($t -replace '\\','/') }
    else { $abs += ($simRoot + "/" + $t) }
}
foreach ($f in $TbFiles) {
    if ($f -match '^[A-Za-z]:') { $abs += ($f -replace '\\','/') }
    else { $abs += ($simRoot + "/" + $f) }
}
$abs | Out-File -Encoding ascii $flist

Push-Location $outMapped
try {
    $ErrorActionPreference = "Continue"   # 原生命令的 stderr 不当异常
    $defArgs = @()
    if ($Defines -ne "") { foreach ($d in $Defines.Split(',')) { if ($d.Trim() -ne "") { $defArgs += "+define+$($d.Trim())" } } }

    "vlib work" | Out-File -Encoding utf8 -Append $cmdLog
    & vlib work 2>&1 | Tee-Object -FilePath $vlogLog | Out-Null

    $vlogArgs = @() + $defArgs + @("-f", "abs.f")
    "vlog $($vlogArgs -join ' ')  (cwd=$outMapped)" | Out-File -Encoding utf8 -Append $cmdLog
    & vlog @vlogArgs 2>&1 | Tee-Object -FilePath $vlogLog -Append | Out-Null
    $vlogExit = $LASTEXITCODE
    "vlog exit=$vlogExit" | Out-File -Encoding utf8 -Append $cmdLog
    if ($vlogExit -ne 0) {
        Write-Host "== vlog FAILED (exit $vlogExit) =="
        Get-Content $vlogLog -Tail 40
        throw "vlog failed"
    }

    # vsim 通过 cmd /c 调（PowerShell 5.1 的数组 splat 会把它不认识的选项传错）；
    # 命令放 .do 文件（cwd 已是 ASCII 映射路径）；写完后立即校验内容再跑。
    $doPath = Join-Path $outDirF "run.do"
    [System.IO.File]::WriteAllLines($doPath, @("run -all", "quit -f"))
    $doCheck = [System.IO.File]::ReadAllText($doPath)
    if ($doCheck -notmatch "run -all") { throw "run.do write failed: $doCheck" }
    $vsimCmd = "vsim -c -l vsim.log -do run.do $Tb"
    if ($VsimArgs -ne "") { $vsimCmd = $vsimCmd + " " + $VsimArgs }
    "cmd /c `"$vsimCmd`"  (cwd=$outMapped)" | Out-File -Encoding utf8 -Append $cmdLog
    cmd /c $vsimCmd 2>&1 | Tee-Object -FilePath (Join-Path $outDirF "vsim_stdout.log") | Out-Null
    $vsimExit = $LASTEXITCODE
    "vsim exit=$vsimExit" | Out-File -Encoding utf8 -Append $cmdLog

    Write-Host "== result (vsim exit $vsimExit) =="
    if (Test-Path (Join-Path $outDirF "vsim.log")) { Get-Content (Join-Path $outDirF "vsim.log") -Tail 30 }
    else { Get-Content (Join-Path $outDirF "vsim_stdout.log") -Tail 30 }
} finally {
    Pop-Location
    if ($substDrive) {
        & subst "$substDrive`:" /D | Out-Null
        Write-Host "subst $substDrive`: removed"
        "subst $substDrive`: removed" | Out-File -Encoding utf8 -Append $cmdLog
    }
}
