# preload-record-v5.md — .bwcmd 路径解析根因诊断 + V5 脚本 + 只读探测（USB open 失败，未下载）

- task：`T11.runC-board-checklist`（0207 线 P4 续接轮 4）｜时间：2026-10-19 21:44–21:52 +08:00｜角色：fpga-dev（原会话续接）
- 结论：**下载仍未发生（0 次）**。用户运行 `preload_fixed.bwcmd` 的失败已定位=**BW 命令解析器把 Windows 反斜杠当转义符**（非编码问题）；已修正为**正斜杠路径**脚本 `download_v5.bwcmd`。本轮只读复测 `read_device_id` 又遇 **`usb_open() failed`**（5555 端口存在**两个 hwserver 监听**，我们的会话落在未持有 FTDI 的实例）→ 按规则不重试、不结束他人进程，交用户做一次窗口清理后按 §5 命令表执行。

## 1. 用户运行的证据（机械转录 + 原始日志）

- `log\bw_2026-10-19_21-44-07.log`、`log\bw_2026-10-19_21-46-04.log`（BW Release_2026.1_SP2，build 6.2.2.200067，Executable=`D:/downlaod/bin/bw_commands_prompt.exe`）。
- `connect_cable -host_name 127.0.0.1:5555 -open` 成功（0.015 s）。
- `download` 失败原文（ASCII 化）：
  - 解析后命令：`download -bit D:?nlogic?una_runC?61019_192056compiled.bit -mode jtag -spd 7 -cable 0`
  - `PRG-8000 ERROR: File path: ?1019_192056compiled.bit invalid, please modify to correct English path`
  - 0.0003 s 返回 → **未发生实际下载/写入**。

## 2. 根因（字节级）

- 脚本 `preload_fixed.bwcmd` 实际字节（hex 片段）：`... 44 3A 5C 61 6E 6C 6F 67 69 63 5C 72 75 6E 61 5F 72 75 6E 43 5C 32 30 32 36 ...` = 纯 ASCII `D:\anlogic\runa_runC\2026...`；UTF-8 no BOM、CRLF → **不是编码/BOM/中文路径问题**。
- BW 解析时做了反斜杠转义替换：`\a`→BEL、`\r`→CR、`\n`→LF、`\2`→STX、`\c`→`c`（反斜杠被吞），于是 `D:\anlogic\runa_runC\20261019_192056\compiled.bit` 被解析成 `D:`+BEL+`nlogic`+CR+`una_runC`+STX+`0261019_192056`+`compiled.bit`，控制字符在控制台显示为 `?`，文件语义已破坏 → 报路径非法。
- 结论：**该工具链的脚本行按 Tcl/类 shell 语义处理 `\` 转义**；Windows 单反斜杠路径不可直接写。基线审计表里的 `C:\...` 写法在本机 BW build 上不可复用（本证据为准）。

## 3. 修正（已验证准备、待设备可用后执行）

- 规则：路径一律用**正斜杠 `/`**（BW 自身 banner 即 `D:/downlaod/bin/...`），或“cwd+相对文件名”；脚本保持纯 ASCII、UTF-8 no BOM、CRLF。
- 新增（D: 暂存，未执行/未成功执行）：
  - `read_id_v5.bwcmd`：`connect_cable -host_name 127.0.0.1:5555 -open` / `read_device_id` / `connect_cable -close`
  - `download_v5.bwcmd`：`connect_cable ... -open` / `download -bit D:/anlogic/runa_runC/20261019_192056/compiled.bit -mode jtag -spd 7 -cable 0` / `read_device_id` / `connect_cable -close`
- bit/CWC 内容与预期值未改；暂存 SHA 复核：bit `5B67A8F5…1D52`、CWC `8DDA54D4…664F` 均 MATCH（21:44 前复核）。

## 4. 本轮只读探测（21:48:47）

- `read_id_v5.bwcmd`（无路径，纯连接）：connect OK（0.0166 s）；`read_device_id` → `Error @ mpsse.cpp:90 : usb_open() failed` + `PRG-8000 ERROR: transfer failed`（6.8 s）；close 正常；rc=0，总 7.1 s。证据：`read_id_v5.log`。
- **下载被门控跳过（fail-closed）**：未执行 `download_v5.bwcmd`，本轮 download 尝试 0 次。
- 现场状态（只读）：5555 端口同时有两个 `D:/downlaod/bin/hwserver.exe -r -f 1 -s 5555` 监听——PID **45596**（21:19:57 启动）与 PID **74620**（21:46:04 启动，用户手动启动、控制台显示 `Open device vid=0x0403 pid=0x6042` / `Enable mpsse` / 1 MHz / `Start remote bitbang server at :5555`）。本角色**未结束/未重启任何进程**，未启动新 hwserver。
- 判定：`usb_open() failed` 与“落在未持有 FTDI 的 hwserver 实例”一致（板卡供电/线缆状态未改变，仍 unknown）；非板卡新故障证据。

## 5. 用户可见的逐条命令（用户在场，可直接执行）

前置：确保 5555 只保留**持有 FTDI 的那个** hwserver（即控制台打印 `Open device vid=0x0403 pid=0x6042` 的窗口）；若还有另一个 hwserver 实例/窗口（如 PID 45596），请用户自行关闭该窗口/结束该进程（本人不结束他人进程）。**不要**结束 `td.exe` 45416。

```bat
cd /d D:\anlogic\runa_runC\20261019_192056
D:\downlaod\bin\bw_commands_prompt.exe read_id_v5.bwcmd < NUL
```
- 判据：输出含 `PH1P100`。

```bat
D:\downlaod\bin\bw_commands_prompt.exe download_v5.bwcmd < NUL
```
- 判据：`PRG-2014 : Chip validation success: PH1P100` + 进度 100% + rc=0 + 时长 ≈28–40 s；**失败不重试**。
- 成功后按 `board-checklist.md` §3 点两下（16 字 ×2、间隔 ≥10 s），期望值见 §4。

## 6. 安全与变更（v5）

- 仅 SRAM；零 flash/efuse/SPI/svf；无 GUI 自动化；未 commit/push；未写工作树/共享树；无批量删除；未动他人进程。
- 变更（记录于 v5 manifest）：`board-checklist.md` §1/§2 改用正斜杠修正脚本并加“重复 hwserver”提示；`lessons.md` 追加一条根因；其余预期值/判据/候选均未改。
