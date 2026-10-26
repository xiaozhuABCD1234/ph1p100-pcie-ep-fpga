# TD 命令行使用说明

核验日期：2026-10-10。

## 当前状态

本机 TD 已自带 CLI，无需另行下载或安装。现有用户 PATH 已包含 `D:\downlaod\bin\`，本轮没有修改环境变量或 TD 安装文件。

- CLI：`D:\downlaod\bin\td_commands_prompt.exe`
- 实测版本：`TD Release_2026.1_SP2`，构建号 `6.2.2.200067`
- Tcl：`8.6.15`
- 已验证命令注册：`open_project`、`import_device`、`launch_runs`、`wait_run`、`bitgen`、`report_timing_summary`

本轮只验证启动和 Tcl 执行，未验证具体工程的综合、布局布线、位流生成或板卡下载。

## PowerShell 中启动交互命令行

```powershell
td_commands_prompt.exe
```

看到 `td >` 后即可输入 Tcl 命令。执行现有脚本及退出的示例：

```tcl
source ./demo.tcl
exit
```

若新终端找不到命令，可使用完整路径：

```powershell
& 'D:\downlaod\bin\td_commands_prompt.exe'
```

## PowerShell 中批量执行 Tcl 文件

先进入脚本／工程所在目录，再传入脚本文件：

```powershell
td_commands_prompt.exe ./demo.tcl
```

`demo.tcl` 是示例文件名，需替换成实际脚本。TD 脚本路径使用正斜杠 `/`。实测 `./td_cli_probe.tcl` 成功，而 `.\td_cli_probe.tcl` 被 TD 解析出转义字符而失败。多行 Tcl 使用文件执行；本机多行标准输入验证出现括号解析错误。

本机 `-help` 被当作脚本文件名，而不是帮助参数。脚本加载失败时也可能返回退出码 0，自动化必须同时检查日志或显式成功标记。

## 重跑已通过的只读自检

从项目根目录执行：

```powershell
Push-Location ./tmp
try {
    $tdOutput = & td_commands_prompt.exe ./td_cli_probe.tcl 2>&1
    $tdExit = $LASTEXITCODE
    $tdOutput
    if ($tdExit -ne 0 -or -not ($tdOutput -match '^TD_CLI_OK$')) {
        throw "TD CLI verification failed; exit code: $tdExit"
    }
} finally {
    Pop-Location
}
```

自检成功标记为 `TD_CLI_OK`。TD 会在工作目录生成运行日志。

官方依据：本机 `D:\downlaod\Doc\SWUG\SWUG105_TCL_Command_User_Guide.pdf`，TD6.2.2 版，2026.01，正文第 1–2 页（PDF 第 8–9 页），分别介绍 Windows 交互模式和批处理模式。

Codex 当前普通沙箱终端仍有初始化错误；本轮自检通过获准的原生 PowerShell 执行。该问题与 TD CLI 是否安装是两个独立事项。

## 2026-10-16 复核实测增补（6.2.2 端到端 + 6.2.3 双版本）

以下为 T01.tool-A/B/D 批次在真实工程链上复核/新增的结论；上文 2026-10-10 记录保持不改。证据：`docs/evidence/td_cli_commands_20261016.json`、`td2026_ipgen_20261016.json`；完整报告 `docs/TD_CLI_IpTool修缮与验证_2026-10-16.md`。

### 退出码语义（实证）

- 脚本内**显式 `exit 1` 会传播**（绝对脚本 + 错误 cwd 的 PRJ-8642 场景实测 exit 1）。
- **加载失败/未捕获错误仍 exit 0**（5 处实证：开不存在工程 PRJ-8642、invalid command、反斜杠脚本名、`-help` 当脚本名、中文路径参数）——错误打印后落入 `td >` 交互提示、进程 exit 0。
- 因此自动化判定必须"退出码 + 显式成功标记 + 非空产物（+哈希）"三件套；单看 exit code 会漏判。

### 调用约定补充

- `.\x.tcl` 失败机制 = Tcl 字符串转义吃字符（实参被吃成 `.q2_backslash.tcl`）；`./x.tcl` 或绝对正斜杠路径可用。
- 相对路径全部按 **cwd** 解析、与脚本所在位置无关；cwd=脚本/工程目录是硬约束；`td_*.log/.logw` 严格写 cwd。
- stdin 多行口径修正：简单 3 行管道 stdin 实测可用；真实流程仍一律文件执行。
- 不在中文 cwd/中文脚本路径下执行任何工程动作（复证：中文路径参数报 `no such file or directory`）。

### 六命令 scratch 端到端（0→bit）已跑通

6.2.2 实测（16 阶段）：`import_device`(ARC-1001)→`create_project`→`add_files`→`top_module`→`create_run`/`reset_runs`→`launch_runs`+`wait_run`→`open_run`(PRJ-1408)→`update_timing -mode final`→`report_timing_summary`（SWNS 17.081/HWNS 0.222/PERIOD 0.000）→`bitgen`（BIT-1003；bit 5,223,983 B，未下载）。6.2.3 回归同套件（仅 2 行常量重定向，副本 `F916DDA1…`）在新装全 PASS（bit 5,223,979 B，未下载；两版 DB_VERSION 均为 46207）。

- 管理器注意：`PRJ-8806` 类 "Run has exited unexpectedly" 间歇出现（本批 1/4 复现）；**`wait_run` 报错 ≠ 产物失败**——该场景 worker 完整完成、place/pr 产物可用、下游可续行；判读结合 `run.log`/`flow.status`/DB。
- `save_best_bits`：两版本均"调用被接受、无产物"（观察项，不作验收）。
- bit 确定性：同一设计不同会话的 bit 仅差头部 `# Date:` 字段（2 字节），Global CRC 相同；`.al/.db/rpt` 含路径/时间戳字节差异属正常，勿按逐字节判定。

### 双版本共存（2026-10-16 新装 6.2.3）

- 新装根：`D:\anlogic\TD_Release_2026.2`（TD Release_2026.2 / 6.2.3.210850 / Tcl 8.6.17）；旧 6.2.2 `D:\downlaod` 未动。
- 新锚点（SHA256 前缀）：`td_commands_prompt.exe 2629E474…`、`td.exe FA2A5AC6…`、`IpTool.exe 5B0654AA…`、`ph1_100p.db 939EC294…`。
- PATH：用户 PATH 新 bin **追加在旧 bin 之后**——裸名 `td_commands_prompt` 仍先命中 6.2.2；**脚本/文档一律写绝对路径**。
- `.al` 默认关联已切到新版本（双击 .al 打开 2026.2 GUI）；旧版仍可用绝对路径/右键打开。
- 6.2.3 新增 Tcl IP flow 命令族：`create_ip/get_ipdefs/get_ips/set_property/get_property/load_project_ips/close_project_ips/generate_target`（`help` 只打印整表）；`create_ip -export_path` 必须指向已存在目录；set 后复读 `.params_*`。DDR1333 参数注入成功但 `generate_target` 卡 `<comp>_adc.log` staging（需 GUI ADC apply 物化；GUI 为下一步，未执行）——本条不得表述为"CLI 生成已跑通"。
- 安装器副作用（如实记录）：PATH 追加、`.al` ProgID/默认关联、公共桌面快捷方式、卸载注册项；新装 license 需手动复制（缺 license 的合成报 `RUN-8008`，外层易误判为管理器缺陷）。细节见报告 §4.3。
