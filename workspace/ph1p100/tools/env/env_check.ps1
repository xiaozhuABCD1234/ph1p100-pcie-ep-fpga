# =============================================================================
#  env_check.ps1 — PH1P100 立体视觉项目：FPGA 开发/构建/仿真环境自检
#
#  目的：把本机环境事实变成可复跑、可交接的自检基线——
#    · 只读：除 -LogDir（默认 run 的 env/logs/）外不写任何位置；
#    · 不安装工具、不改 PATH/环境变量/注册表、不写 D 盘；
#    · subst 只报告（-TdProbe 例外：只建临时映射跑 TD 版本探针，finally 立即撤销）；
#    · 输出人类可读日志 + 机器可读 JSON（时间戳/命令/退出码/结果）。
#
#  用法（项目根下）：
#    powershell -ExecutionPolicy Bypass -File tools/env/env_check.ps1
#    powershell -ExecutionPolicy Bypass -File tools/env/env_check.ps1 -TdProbe
#
#  已知坑（本机实测：PowerShell 5.1 + ACP=936）：
#    · UTF-8 无 BOM + 中文注释会被按 GBK 解码吞换行（run_sim.ps1/run_td.ps1 的
#      BOM 是功能性要求）→ 本脚本必须带 UTF-8 BOM；且用 SelfCheck 哨兵计数
#      验证"每一行都真的被执行"，防止吞行后静默半途而废。
#    · 判据看产物不看退出码：本脚本落 env_check_*.json / *.log，并在最后显式
#      exit 0/1；即使 -File 下行为异常，也以 JSON 里的 verdict 为准。
# =============================================================================
param(
    [string]$Root = "",
    [string]$LogDir = "",
    [string]$Inventory = "",
    [switch]$TdProbe,
    [switch]$SkipHash
)

$ErrorActionPreference = "Stop"
$script:SelfCheck = 0
$script:SelfCheckExpected = 6   # 必须等于脚本中 $script:SelfCheck++ 的出现次数

# ---------------------------------------------------------------------------
# 0. 基本路径（-Root 默认 = 本脚本上两级；-LogDir 默认 = 本 run 的 env/logs）
#    哨兵1：若上方中文注释吞掉本行，SelfCheck 计数会少 1 → 自检 FAIL。
# ---------------------------------------------------------------------------
$script:SelfCheck++
if ($Root -ne "") {
    $root = (Resolve-Path $Root).Path
} else {
    $root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}
if ($LogDir -ne "") {
    $logDir = $LogDir
} else {
    $logDir = Join-Path $root "workflow\runs\20261017-011744-rk-fpga-align\env\logs"
}
if ($Inventory -ne "") {
    $inventoryPath = $Inventory
} else {
    $inventoryPath = Join-Path $root "workflow\runs\20261017-011744-rk-fpga-align\env\environment-inventory.json"
}
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$stamp     = Get-Date -Format "yyyyMMdd-HHmmss"
$logPath   = Join-Path $logDir ("env_check_" + $stamp + ".log")
$jsonPath  = Join-Path $logDir ("env_check_" + $stamp + ".json")
$selfSha   = (Get-FileHash -Algorithm SHA256 -Path $PSCommandPath).Hash
$records   = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------------
# 1. 记录工具函数：所有检查统一成 {id,name,status,command,cwd,exit_code,summary}
# ---------------------------------------------------------------------------
function Add-Record {
    param(
        [string]$Id, [string]$Name, [string]$Status,
        [string]$Command = "", [string]$Cwd = "", $ExitCode = $null,
        [string]$Summary = "", $Extra = $null
    )
    $rec = [pscustomobject]@{
        id = $Id; name = $Name; status = $Status
        command = $Command; cwd = $Cwd; exit_code = $ExitCode
        summary = $Summary; extra = $Extra
    }
    $records.Add($rec) | Out-Null
    $tag = "[" + $Status.PadRight(4) + "]"
    Write-Host ($tag + " " + $Id + " — " + $Summary)
    return $rec
}

function Run-Native {
    param([string]$Command, [string[]]$Arguments = @(), [string]$WorkDir = "", [switch]$Utf8)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = ""; $code = $null
    $pushed = $false
    $prevOutEnc = [Console]::OutputEncoding
    try {
        if ($Utf8) { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 }   # git 输出 UTF-8 文件名
        if ($WorkDir -ne "") { Push-Location $WorkDir; $pushed = $true }
        $out = (& $Command @Arguments 2>&1 | Out-String)
        $code = $LASTEXITCODE
    } catch {
        $out = "EXCEPTION: " + $_.Exception.Message
        $code = -1
    } finally {
        if ($pushed) { Pop-Location }
        if ($Utf8) { [Console]::OutputEncoding = $prevOutEnc }
        $ErrorActionPreference = $prev
    }
    return [pscustomobject]@{ Output = $out.Trim(); ExitCode = $code }
}

function Test-Bom {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    $b = [System.IO.File]::ReadAllBytes($Path)
    return ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

# ---------------------------------------------------------------------------
# 2. 主机 / PowerShell / 代码页（ACP=936 是本机已知坑的前提）
#    哨兵2：吞行会让本行消失 → 计数少 1。
# ---------------------------------------------------------------------------
$script:SelfCheck++
$acp    = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').ACP
$oemcp  = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Nls\CodePage').OEMCP
$hostInfo = [pscustomobject]@{
    computer   = $env:COMPUTERNAME
    user       = $env:USERNAME
    os         = [System.Environment]::OSVersion.VersionString
    ps_version = $PSVersionTable.PSVersion.ToString()
    ps_edition = $PSVersionTable.PSEdition
    acp        = $acp
    oemcp      = $oemcp
    culture    = (Get-Culture).Name
    console_out_encoding = [Console]::OutputEncoding.WebName
    output_encoding      = $OutputEncoding.WebName
}
Add-Record -Id "host_ps" -Name "主机 / PowerShell / 代码页" -Status "INFO" `
    -Command "`$PSVersionTable + HKLM:\...\Nls\CodePage + [Console]::OutputEncoding" -Cwd $root -ExitCode 0 `
    -Summary ("PS " + $hostInfo.ps_version + " (" + $hostInfo.ps_edition + "), ACP=" + $acp + ", OEMCP=" + $oemcp + ", culture=" + $hostInfo.culture) `
    -Extra $hostInfo
if ($acp -eq 936 -and $PSVersionTable.PSVersion.Major -eq 5) {
    Add-Record -Id "host_ps_known_trap" -Name "已知坑前提（PS5.1 + ACP936）" -Status "PASS" `
        -Summary "与 run_sim.ps1/run_td.ps1 BOM 修复的前提一致；所有 .ps1 必须带 UTF-8 BOM" `
        -Extra @{ rule = "UTF-8 with BOM for *.ps1 containing non-ASCII" }
} else {
    Add-Record -Id "host_ps_known_trap" -Name "已知坑前提（PS5.1 + ACP936）" -Status "WARN" `
        -Summary "本机不是 PS5.1+ACP936；BOM 规则仍按保守执行（脚本统一带 BOM）"
}

# ---------------------------------------------------------------------------
# 3. TD 工具链：存在性 + SHA256（-SkipHash 可跳过）
# ---------------------------------------------------------------------------
$tdBin = "D:\anlogic\TD_Release_2026.2\bin"
$tdFiles = @("td_commands_prompt.exe", "td.exe", "IpTool.exe", "bw.exe", "bw_commands_prompt.exe")
$tdHashes = [ordered]@{}
$tdMissing = @()
foreach ($f in $tdFiles) {
    $p = Join-Path $tdBin $f
    if (Test-Path $p) {
        if (-not $SkipHash) {
            $h = Get-FileHash -Algorithm SHA256 -Path $p
            $tdHashes[$f] = @{ path = $p; sha256 = $h.Hash; bytes = (Get-Item $p).Length }
        } else {
            $tdHashes[$f] = @{ path = $p; sha256 = "skipped"; bytes = (Get-Item $p).Length }
        }
    } else {
        $tdMissing += $p
    }
}
if ($tdMissing.Count -eq 0) {
    Add-Record -Id "tools_td" -Name "TD 6.2.3 工具链" -Status "PASS" `
        -Command ("Test-Path + Get-FileHash " + $tdBin + "\*") -Cwd $root -ExitCode 0 `
        -Summary ("5 个二进制齐备" + $(if ($SkipHash) { "（SHA 跳过）" } else { "，SHA 已取" })) `
        -Extra $tdHashes
} else {
    Add-Record -Id "tools_td" -Name "TD 6.2.3 工具链" -Status "FAIL" `
        -Command ("Test-Path " + $tdBin + "\*") -Cwd $root -ExitCode 1 `
        -Summary ("缺少: " + ($tdMissing -join "; ")) -Extra $tdHashes
}

# TD license（fresh install 曾因缺 license 在 optimize_rtl 报 RUN-8008）
$licPath = "D:\anlogic\TD_Release_2026.2\license\Anlogic.lic"
if (Test-Path $licPath) {
    $licSha = if ($SkipHash) { "skipped" } else { (Get-FileHash -Algorithm SHA256 -Path $licPath).Hash }
    Add-Record -Id "tools_td_license" -Name "TD license 文件" -Status "PASS" `
        -Command ("Test-Path " + $licPath) -Cwd $root -ExitCode 0 `
        -Summary "存在（RUN-8008 类问题的根因文件）" -Extra @{ path = $licPath; sha256 = $licSha }
} else {
    Add-Record -Id "tools_td_license" -Name "TD license 文件" -Status "WARN" `
        -Command ("Test-Path " + $licPath) -Cwd $root -ExitCode 1 `
        -Summary "未找到；综合 worker 可能报 RUN-8008（缺 license）" -Extra @{ path = $licPath }
}

# ---------------------------------------------------------------------------
# 4. TD CLI 版本探针（可选 -TdProbe；临时 subst，finally 撤销）
#    哨兵3：吞行会让本行消失 → 计数少 1。
# ---------------------------------------------------------------------------
$script:SelfCheck++
function Invoke-TdProbe {
    param([string]$TdExe, [string]$LogDir)
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    $letter = $null
    foreach ($L in @('S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z')) {
        if (($used -notcontains $L) -and (-not (Test-Path ($L + ":\")))) { $letter = $L; break }
    }
    if (-not $letter) {
        return [pscustomobject]@{ Ok = $false; Summary = "无空闲盘符可建临时 subst"; Output = ""; Letter = "" }
    }
    $probeTcl = Join-Path $LogDir "td_probe.tcl"
    $tcl = @(
        'foreach name {open_project import_device launch_runs wait_run bitgen report_timing_summary create_ip get_ips get_property set_property generate_target} {'
        ' if {[llength [info commands $name]] == 0} {puts stderr "MISSING $name"; exit 1}'
        ' puts "REGISTERED $name"'
        '}'
        'puts "TCL_VERSION [info patchlevel]"'
        'puts "READ_ONLY_CLI_PROBE_OK"'
        'exit 0'
    )
    [System.IO.File]::WriteAllLines($probeTcl, $tcl)
    try {
        & subst ($letter + ":") $LogDir | Out-Null
        $r = Run-Native -Command $TdExe -Arguments @("td_probe.tcl") -WorkDir ($letter + ":\")
        return [pscustomobject]@{ Ok = $true; Summary = ""; Output = $r.Output; ExitCode = $r.ExitCode; Letter = $letter }
    } catch {
        return [pscustomobject]@{ Ok = $false; Summary = ("探针异常: " + $_.Exception.Message); Output = ""; Letter = $letter }
    } finally {
        if ($letter) { & subst ($letter + ":") /D | Out-Null }
    }
}

if ($TdProbe) {
    $probe = Invoke-TdProbe -TdExe (Join-Path $tdBin "td_commands_prompt.exe") -LogDir $logDir
    $probeOut = $probe.Output
    [System.IO.File]::WriteAllText((Join-Path $logDir "td_probe_stdout.log"), $probeOut, (New-Object System.Text.UTF8Encoding($false)))
    $regCount = ([regex]::Matches($probeOut, "REGISTERED ")).Count
    $okMarker = $probeOut -match "READ_ONLY_CLI_PROBE_OK"
    $verMatch = [regex]::Match($probeOut, "TD Release_(\S+)")
    $buildMatch = [regex]::Match($probeOut, "Build number = ([\d\.]+)")
    $tclMatch = [regex]::Match($probeOut, "TCL_VERSION ([\d\.]+)")
    $probeInfo = [pscustomobject]@{
        subst_letter = $probe.Letter
        td_version   = if ($verMatch.Success) { $verMatch.Groups[1].Value } else { "?" }
        build        = if ($buildMatch.Success) { $buildMatch.Groups[1].Value } else { "?" }
        tcl_version  = if ($tclMatch.Success) { $tclMatch.Groups[1].Value } else { "?" }
        registered   = $regCount
        marker       = $okMarker
    }
    $probeStatus = "FAIL"
    if ($probe.Ok -and $okMarker -and ($regCount -eq 11) -and $verMatch.Success) { $probeStatus = "PASS" }
    Add-Record -Id "td_cli_probe" -Name "TD CLI 只读版本探针" -Status $probeStatus `
        -Command ("td_commands_prompt.exe td_probe.tcl (cwd=临时 subst " + $probe.Letter + ": → env/logs)") -Cwd $logDir -ExitCode $probe.ExitCode `
        -Summary ("version=" + $probeInfo.td_version + " build=" + $probeInfo.build + " tcl=" + $probeInfo.tcl_version + " registered=" + $regCount + " marker=" + $okMarker) `
        -Extra $probeInfo
} else {
    Add-Record -Id "td_cli_probe" -Name "TD CLI 只读版本探针" -Status "INFO" `
        -Command "-TdProbe 未启用（默认静态检查）" -Summary "跳过；需要版本证据时用 -TdProbe 复跑" -ExitCode $null
}

# ---------------------------------------------------------------------------
# 5. ModelSim / Python / GCC / Git / tclsh：存在性与版本
# ---------------------------------------------------------------------------
$msBin = "D:\intelFPGA\18.1\modelsim_ase\win32aloem"
$msOk = (Test-Path (Join-Path $msBin "vsim.exe")) -and (Test-Path (Join-Path $msBin "vlog.exe"))
if ($msOk) {
    $vsim = Run-Native -Command (Join-Path $msBin "vsim.exe") -Arguments @("-version")
    $vlog = Run-Native -Command (Join-Path $msBin "vlog.exe") -Arguments @("-version")
    $vsimLine = ($vsim.Output -split "`r?`n" | Select-Object -First 1)
    $vlogLine = ($vlog.Output -split "`r?`n" | Select-Object -First 1)
    Add-Record -Id "tools_modelsim" -Name "ModelSim 入口" -Status "PASS" `
        -Command ("vsim -version / vlog -version @ " + $msBin) -Cwd $msBin -ExitCode $vsim.ExitCode `
        -Summary ("vsim: " + $vsimLine + " | vlog: " + $vlogLine) `
        -Extra @{ vsim = (Join-Path $msBin "vsim.exe"); vlog = (Join-Path $msBin "vlog.exe"); vsim_exit = $vsim.ExitCode; vlog_exit = $vlog.ExitCode }
} else {
    Add-Record -Id "tools_modelsim" -Name "ModelSim 入口" -Status "FAIL" `
        -Command ("Test-Path " + $msBin + "\vsim.exe|vlog.exe") -Cwd $root -ExitCode 1 `
        -Summary "vsim.exe/vlog.exe 缺失" -Extra @{ bin = $msBin }
}

$compilers = [ordered]@{}
foreach ($tool in @(@("python", @("--version")), @("gcc", @("--version")), @("git", @("--version")), @("tclsh", @("PROBE_FILE")))) {
    $name = $tool[0]; $toolArgs = $tool[1]
    $cmdPath = (Get-Command $name -ErrorAction SilentlyContinue).Source
    if ($cmdPath) {
        if ($name -eq "tclsh") {
            # tclsh 无参数会读 stdin 挂住；用临时脚本文件探测（写在 env/logs 内）
            $tclProbeFile = Join-Path $logDir "tcl_version_probe.tcl"
            [System.IO.File]::WriteAllText($tclProbeFile, "puts [info patchlevel]`n", (New-Object System.Text.UTF8Encoding($false)))
            $toolArgs = @($tclProbeFile)
        }
        $r = Run-Native -Command $cmdPath -Arguments $toolArgs
        $firstLine = ($r.Output -split "`r?`n" | Select-Object -First 1)
        $compilers[$name] = @{ path = $cmdPath; version_line = $firstLine; exit_code = $r.ExitCode }
    } else {
        $compilers[$name] = @{ path = "(not found)"; version_line = ""; exit_code = $null }
    }
}
$missingCompilers = @($compilers.Keys | Where-Object { $compilers[$_].path -eq "(not found)" })
if ($missingCompilers.Count -eq 0) {
    Add-Record -Id "tools_compilers" -Name "Python / GCC / Git / tclsh" -Status "PASS" `
        -Command "python --version; gcc --version; git --version" -Cwd $root -ExitCode 0 `
        -Summary (($compilers.Keys | ForEach-Object { $_ + ": " + $compilers[$_].version_line }) -join " | ") `
        -Extra $compilers
} else {
    Add-Record -Id "tools_compilers" -Name "Python / GCC / Git / tclsh" -Status "WARN" `
        -Command "Get-Command + --version" -Cwd $root -ExitCode 1 `
        -Summary ("缺少: " + ($missingCompilers -join ",")) -Extra $compilers
}

# ---------------------------------------------------------------------------
# 6. 入口脚本存在性 + BOM/编码在位（run_sim/run_td/env_check 自身）
#    哨兵4：吞行会让本行消失 → 计数少 1。
# ---------------------------------------------------------------------------
$script:SelfCheck++
$entryScripts = @(
    "tools\pcie_integration\run_sim.ps1",
    "tools\pcie_integration\run_td.ps1",
    "tools\env\env_check.ps1"
)
$entryInfo = [ordered]@{}
$entryFail = @()
foreach ($rel in $entryScripts) {
    $p = Join-Path $root $rel
    if (Test-Path $p) {
        $bom = Test-Bom -Path $p
        $sha = if ($SkipHash) { "skipped" } else { (Get-FileHash -Algorithm SHA256 -Path $p).Hash }
        $entryInfo[$rel] = @{ exists = $true; bom = $bom; sha256 = $sha; bytes = (Get-Item $p).Length }
        if (-not $bom) { $entryFail += $rel }
    } else {
        $entryInfo[$rel] = @{ exists = $false; bom = $false; sha256 = ""; bytes = 0 }
        $entryFail += $rel
    }
}
if ($entryFail.Count -eq 0) {
    Add-Record -Id "entry_scripts_bom" -Name "入口脚本 BOM/编码" -Status "PASS" `
        -Command "ReadAllBytes first3 == EF BB BF" -Cwd $root -ExitCode 0 `
        -Summary "3 个 .ps1 均存在且带 UTF-8 BOM（功能性要求）" -Extra $entryInfo
} else {
    Add-Record -Id "entry_scripts_bom" -Name "入口脚本 BOM/编码" -Status "FAIL" `
        -Command "ReadAllBytes first3 == EF BB BF" -Cwd $root -ExitCode 1 `
        -Summary ("BOM 缺失或文件不存在: " + ($entryFail -join "; ")) -Extra $entryInfo
}

$tdTclDir = Join-Path $root "tools\pcie_integration\td"
$tclNeeded = @("00_all.tcl", "01_create.tcl", "02_syn.tcl", "03_phy.tcl")
$tclInfo = [ordered]@{}
$tclMissing = @()
foreach ($t in $tclNeeded) {
    $p = Join-Path $tdTclDir $t
    $tclInfo[$t] = (Test-Path $p)
    if (-not (Test-Path $p)) { $tclMissing += $t }
}
$compileF = Join-Path $root "fpga\csi2\pcie_integration\sim\compile_checked.f"
$tclInfo["sim/compile_checked.f"] = (Test-Path $compileF)
if (-not (Test-Path $compileF)) { $tclMissing += "compile_checked.f" }
if ($tclMissing.Count -eq 0) {
    Add-Record -Id "entry_td_sim_scripts" -Name "TD/仿真入口脚本" -Status "PASS" `
        -Command "Test-Path tools/pcie_integration/td/*.tcl + sim/compile_checked.f" -Cwd $root -ExitCode 0 `
        -Summary "00_all/01/02/03 + compile_checked.f 齐备（00_all 为唯一可跑入口）" -Extra $tclInfo
} else {
    Add-Record -Id "entry_td_sim_scripts" -Name "TD/仿真入口脚本" -Status "FAIL" `
        -Command "Test-Path" -Cwd $root -ExitCode 1 `
        -Summary ("缺少: " + ($tclMissing -join "; ")) -Extra $tclInfo
}

# ---------------------------------------------------------------------------
# 7. subst 只报告（不建、不删；残留映射只登记）
# ---------------------------------------------------------------------------
$substOut = (Run-Native -Command "subst" -Arguments @()).Output
$substLines = @($substOut -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
Add-Record -Id "subst_report" -Name "subst 映射（只报告）" -Status "INFO" `
    -Command "subst" -Cwd $root -ExitCode 0 `
    -Summary (($substLines | ForEach-Object { $_.Trim() }) -join " ; ") `
    -Extra @{ mappings = $substLines; note = "本脚本不建/不删映射；run_sim/run_td 只用完撤自己的临时映射" }

# ---------------------------------------------------------------------------
# 8. 输出目录可达 + 写探针（只写 env/logs 内）
# ---------------------------------------------------------------------------
$envDir = Join-Path $root "workflow\runs\20261017-011744-rk-fpga-align\env"
$reportsDir = Join-Path $root "workflow\runs\20261017-011744-rk-fpga-align\test-reports"
$dirInfo = [ordered]@{
    log_dir      = $logDir
    env_dir      = $envDir
    reports_dir  = $reportsDir
    tools_env    = (Join-Path $root "tools\env")
}
$probeFile = Join-Path $logDir ".write_probe.tmp"
try {
    [System.IO.File]::WriteAllText($probeFile, "probe")
    $ok = (Test-Path $probeFile)
    Remove-Item $probeFile -Force
    Add-Record -Id "output_dirs" -Name "输出目录可达" -Status "PASS" `
        -Command "write+delete probe in env/logs" -Cwd $logDir -ExitCode 0 `
        -Summary "env/logs 可写；env/test-reports/tools/env 存在性已记录" -Extra $dirInfo
} catch {
    Add-Record -Id "output_dirs" -Name "输出目录可达" -Status "FAIL" `
        -Command "write probe in env/logs" -Cwd $logDir -ExitCode 1 `
        -Summary ("不可写: " + $_.Exception.Message) -Extra $dirInfo
}

# ---------------------------------------------------------------------------
# 9. D 盘只读约定 + 临时参考库
# ---------------------------------------------------------------------------
$dOk = Test-Path "D:\"
$refRoot = Join-Path $env:LOCALAPPDATA "Temp\opencode"
$refs = @()
if (Test-Path $refRoot) {
    $refs = @(Get-ChildItem -Path $refRoot -Directory -Filter "ref_*" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
}
Add-Record -Id "d_readonly" -Name "D 盘只读约定" -Status $(if ($dOk) { "PASS" } else { "WARN" }) `
    -Command "Test-Path D:\ ; 只读约定（本脚本不写 D:）" -Cwd $root -ExitCode $(if ($dOk) { 0 } else { 1 }) `
    -Summary ("D: 存在=" + $dOk + "；约定：TD/ModelSim/IP 工具只读使用；不安装、不改全局；工具运行产物经 subst 限定在项目/run 内") `
    -Extra @{ d_exists = $dOk; td_bin = $tdBin; ms_bin = $msBin; note = "临时参考库: " + ($refs -join ",") }

# ---------------------------------------------------------------------------
# 10. Git 状态 + HEAD（只报告，不改）
# ---------------------------------------------------------------------------
$gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
$gitInfo = [ordered]@{}
if ($gitExe) {
    $head = Run-Native -Command $gitExe -Arguments @("-C", $root, "rev-parse", "HEAD") -Utf8
    $dirty = Run-Native -Command $gitExe -Arguments @("-C", $root, "status", "--porcelain") -Utf8
    $dirtyLines = @($dirty.Output -split "`r?`n" | Where-Object { $_.Trim() -ne "" })
    $gitInfo["head"] = $head.Output.Trim()
    $gitInfo["dirty_count"] = $dirtyLines.Count
    $gitInfo["dirty_sample"] = @($dirtyLines | Select-Object -First 10)
    Add-Record -Id "git_state" -Name "Git 状态（只报告）" -Status "INFO" `
        -Command "git -C <root> rev-parse HEAD; git status --porcelain" -Cwd $root -ExitCode $head.ExitCode `
        -Summary ("HEAD=" + $gitInfo["head"].Substring(0, [Math]::Min(12, $gitInfo["head"].Length)) + " dirty=" + $dirtyLines.Count + " 条") `
        -Extra $gitInfo
} else {
    Add-Record -Id "git_state" -Name "Git 状态（只报告）" -Status "WARN" -Command "git" -Cwd $root -ExitCode 1 -Summary "git 不可用"
}

# ---------------------------------------------------------------------------
# 11. 与环境清单（inventory）的一致性核对（可选：inventory 存在才做）
#    哨兵5：吞行会让本行消失 → 计数少 1。
# ---------------------------------------------------------------------------
$script:SelfCheck++
if (Test-Path $inventoryPath) {
    $invText = [System.IO.File]::ReadAllText($inventoryPath, [System.Text.Encoding]::UTF8)
    $inv = $null
    $invErr = ""
    try { $inv = $invText | ConvertFrom-Json } catch { $invErr = $_.Exception.Message }
    if ($inv -eq $null) {
        Add-Record -Id "inventory_consistency" -Name "环境清单一致性" -Status "FAIL" `
            -Command ("ReadAllText+ConvertFrom-Json " + $inventoryPath) -Cwd $root -ExitCode 1 `
            -Summary ("清单解析失败: " + $invErr)
    } else {
        $mismatch = @()
        foreach ($key in @("td_commands_prompt.exe", "td.exe", "IpTool.exe", "bw.exe", "bw_commands_prompt.exe")) {
            if ((-not $SkipHash) -and $inv.tools_td.$key.sha256) {
                if ($tdHashes[$key].sha256 -ne $inv.tools_td.$key.sha256) {
                    $mismatch += ($key + " SHA 不符: 实测 " + $tdHashes[$key].sha256.Substring(0, 16) + " vs 清单 " + $inv.tools_td.$key.sha256.Substring(0, 16))
                }
            }
        }
        if ($mismatch.Count -eq 0) {
            Add-Record -Id "inventory_consistency" -Name "环境清单一致性" -Status "PASS" `
                -Command ("核对 " + $inventoryPath) -Cwd $root -ExitCode 0 `
                -Summary ("TD 二进制 SHA 与清单一致（清单版本: " + $inv.inventory_version + "）")
        } else {
            Add-Record -Id "inventory_consistency" -Name "环境清单一致性" -Status "FAIL" `
                -Command ("核对 " + $inventoryPath) -Cwd $root -ExitCode 1 `
                -Summary ($mismatch -join " ; ")
        }
    }
} else {
    Add-Record -Id "inventory_consistency" -Name "环境清单一致性" -Status "WARN" `
        -Command ("Test-Path " + $inventoryPath) -Cwd $root -ExitCode 1 `
        -Summary "环境清单不存在（首次运行正常）；本次输出可用来生成清单"
}

# ---------------------------------------------------------------------------
# 12. 自检哨兵（编码/吞行）：计数必须等于预期；再验证 JSON 可回读
#     哨兵6放在本检查之前——若任何一行被吞，计数就不够。
# ---------------------------------------------------------------------------
$script:SelfCheck++
$sentinelOk = ($script:SelfCheck -eq $script:SelfCheckExpected)
Add-Record -Id "selfcheck_encoding" -Name "脚本编码自检（哨兵）" -Status $(if ($sentinelOk) { "PASS" } else { "FAIL" }) `
    -Command "脚本内 SelfCheck 哨兵计数" -Cwd $root -ExitCode $(if ($sentinelOk) { 0 } else { 1 }) `
    -Summary ("SelfCheck=" + $script:SelfCheck + "/" + $script:SelfCheckExpected + "；自身 BOM=" + (Test-Bom -Path $PSCommandPath)) `
    -Extra @{ self_sha256 = $selfSha; self_bom = (Test-Bom -Path $PSCommandPath) }

# ---------------------------------------------------------------------------
# 13. 汇总输出：人类日志 + 机器 JSON（JSON 用无 BOM UTF-8，便于脚本消费）
# ---------------------------------------------------------------------------
$counts = @{ PASS = 0; FAIL = 0; WARN = 0; INFO = 0 }
foreach ($r in $records) { $counts[$r.status] = $counts[$r.status] + 1 }
$verdict = "PASS"
if ($counts["FAIL"] -gt 0) { $verdict = "FAIL" }

$result = [ordered]@{
    schema             = 1
    tool               = "tools/env/env_check.ps1"
    script_sha256      = $selfSha
    generated_at       = (Get-Date -Format o)
    project_root       = $root
    log_dir            = $logDir
    inventory_path     = $inventoryPath
    td_probe_requested = [bool]$TdProbe
    skip_hash          = [bool]$SkipHash
    host               = $hostInfo
    checks             = $records
    summary            = $counts
    verdict            = $verdict
}
$json = ($result | ConvertTo-Json -Depth 8)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($jsonPath, $json, $utf8NoBom)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# env_check — " + $result.generated_at)
$lines.Add("script_sha256 = " + $selfSha)
$lines.Add("root = " + $root)
$lines.Add("verdict = " + $verdict + "  (PASS=" + $counts["PASS"] + " FAIL=" + $counts["FAIL"] + " WARN=" + $counts["WARN"] + " INFO=" + $counts["INFO"] + ")")
$lines.Add("")
foreach ($r in $records) {
    $lines.Add("[" + $r.status + "] " + $r.id + " | " + $r.name)
    if ($r.command) { $lines.Add("    cmd : " + $r.command) }
    if ($r.cwd) { $lines.Add("    cwd : " + $r.cwd) }
    if ($r.exit_code -ne $null) { $lines.Add("    exit: " + $r.exit_code) }
    $lines.Add("    ->  " + $r.summary)
}
$lines.Add("")
$lines.Add("JSON: " + $jsonPath)
[System.IO.File]::WriteAllLines($logPath, $lines, $utf8NoBom)

# JSON 回读自检（防写出坏 JSON）
$jsonBack = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
if ($jsonBack.verdict -eq $verdict) {
    Write-Host ("JSON round-trip OK: " + $jsonPath)
} else {
    Write-Host "JSON round-trip FAILED"
    $verdict = "FAIL"
}
Write-Host ("env_check verdict = " + $verdict + " (PASS=" + $counts["PASS"] + " FAIL=" + $counts["FAIL"] + " WARN=" + $counts["WARN"] + ")")
Write-Host ("log : " + $logPath)
Write-Host ("json: " + $jsonPath)

# 说明：SelfCheck 计数在 §12 检查点之前必须为 6（6 个哨兵）；若任一行被吞会少计
# → selfcheck_encoding 记录 FAIL。exit 码与 JSON verdict 一致，判据仍以产物为准。
if ($verdict -eq "PASS") { exit 0 } else { exit 1 }
