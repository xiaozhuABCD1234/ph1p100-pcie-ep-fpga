# T02 下一步用户操作说明（recovery01，Phase A 只读）

时间：2026-10-19 22:45 +08:00｜run：`20261019-2117_runD_batch2_continue`｜任务：`T02.codex-singleA-board`
当前状态：**NEEDS_USER_SERVER_CLEANUP**。你已关闭另一个 TD 窗口（`td.exe` PID 23384 已消失），但 5555 仍**没有 listener**，且残留一个**不持 FTDI** 的 `hwserver.exe` PID 37440。开发本轮 **0 次 read_device_id、0 次 download**。

## 1. 现在屏幕上应关/不关什么

| 进程 | 处置 | 判断依据 |
|---|---|---|
| `hwserver.exe` **PID 37440** | **请结束它** | 启动于 21:48:47；父进程 45596 已不存在；无 `hwserver` 可执行路径/命令行、无 FTDI/USB/mpsse 模块、无 TCP 端点、5555 无监听；是旧 server 退出后的残留，不是持 FTDI 的实例。 |
| `td.exe` **PID 45416** | **绝对不能关** | 旧 TD GUI（00:59 启动）；本轮及后续只观察，不做 GUI 自动化，不杀。 |
| `td.exe` PID 23384 | 已由你关闭 | 本轮复查已不存在；无需再操作。 |
| 新启动的 `hwserver`（只应有一个） | **保持窗口打开** | 它应打印 `Open device vid=0x0403 pid=0x6042` 并监听 5555；这是后续只读 ID/下载的唯一 server。 |

> 只关闭 PID 37440；不要关 `td.exe` 45416，也不要关即将启动的持 FTDI hwserver。不要用任务管理器“结束所有 hwserver”。

## 2. 逐步命令（照做即可）

### 第 1 步：结束残留 hwserver 37440

打开一个 **命令提示符**（普通或管理员均可；若提示拒绝访问，用管理员重开）：

```bat
taskkill /PID 37440 /F
```

看到“成功: 已终止 PID 37440 的进程”即可。若提示“没有找到进程”，说明它已自行退出，继续下一步。

### 第 2 步：只启动一个持 FTDI 的 hwserver

在命令提示符执行（沿用 0207 成功路径的 server）：

```bat
cd /d D:\downlaod\bin
hwserver.exe -r -f 1 -s 5555
```

- **保持这个窗口打开**，不要最小化到关闭。
- 正常应看到类似：
  `Anlogic hwserver v1.0c (g1deb3940) Build 2024-12-09`
  `Initialize ftdi`
  `Use channel A`
  `Open device vid=0x0403 pid=0x6042`
- 如果提示 5555 端口被占用：说明还有另一个 server，回到第 1 步/任务管理器只保留这一个；不要开第二个。
- 如果提示找不到 `hwserver.exe`：确认 `D:\downlaod\bin\hwserver.exe` 是否存在（本 run 记录的成功工具目录是 `D:\downlaod\bin`）。

### 第 3 步：验证“只有一个 listener / 一个 hwserver”

**另开**一个命令提示符（不要关 server 窗口），执行：

```bat
tasklist | findstr /i hwserver
netstat -ano | findstr :5555
```

通过标准：

- `tasklist` **只有一行** `hwserver.exe`，记下它的 PID（例如 74620）。
- `netstat` **只有一行** 带 `LISTENING`，其最后一列 PID 与上面 hwserver PID **完全一致**；不应出现第二个 PID，也不应出现 `TIME_WAIT`/`ESTABLISHED` 的多余会话。
- `tasklist | findstr /i td.exe` 应只有 PID **45416**（不应再有 23384）。

### 第 4 步：回主一句话

把下面这句（按实际 PID 替换）发给主：

> server 已清理：hwserver PID=<实际PID>，5555 唯一 LISTENING，td 仅 45416；请续 Phase A 只读 ID，不下载。

主会续本开发会话；开发只运行**一次** ≤60 s 的只读 `read_id_v6.bwcmd`（connect → read_device_id → close），日志写到本 run `board/sram/<时间戳>/`。**这一步仍然不下载**。

## 3. 只读 ID 成功后会发生什么

开发会记录：server PID、FTDI `VID_0403/PID_6042`、工具路径/版本、时间、耗时、`PH1P100` 原文。然后**停下来**，因为板上当前是 **0207 候选** `5B67A8F5…1D52`，且 0207 已有 `board-samples-01/02` 与 T11 r0 报告。T02 要下载的是另一个候选 `b68c6e18…f9bf`；下载会覆盖 0207 当前候选。

请明确选择：

- **A（推荐）**：0207 采样已完成，窗口给 T02。回主：“选 A：0207 采完，窗口给 T02 下载”。
- **B**：明确授权 T02 立即覆盖 0207 当前候选。回主：“授权 B：覆盖 0207，T02 下载”。0207 这次采样窗口作废，需以后重下。
- **C**：只做只读 ID/排查，暂不下载；等你现场确认后再决定。

**A/B 未明确前，开发不会 download。** 选择 A/B 后，另派 Phase B：复核身份 → 写新租约 → 用 `bw_commands_prompt.exe` 执行一次 `download -mode jtag`（≤180 s，不重试）→ 成功判据 `PRG-2014 Chip validation success: PH1P100` + 100% + 下载后 `read_device_id=PH1P100`。成功后仍不判 G3，需你按 CWC 清单点两下采样。

## 4. 失败时怎么分流（不要反复重试）

| 现象 | 含义/下一步 |
|---|---|
| `read_device_id` 60 s 超时、日志 0 字节 | server 窗口可能已退出/不在 5555；回到第 3 步确认唯一 listener；不要连续重跑。 |
| `usb_open() failed` + `PRG-8000 transfer failed` | 常见于重复 server 或 TD 抢占 FTDI；只保留一个持 FTDI server，关闭多余 TD（但不要关 45416）；核对 PnP。 |
| 设备管理器没有 `USB-JTAG Cable` / `VID_0403&PID_6042` / COM8 | 物理层/线缆/口/驱动问题：换口、重插、检查驱动；不要在无设备时反复跑 ID。 |
| `td.exe` 提示 cable 被占用 | 关闭新开的 TD 实例（23384 已关）；保留 45416，不自动化其 GUI。 |
| 读到非 `PH1P100` 或 `PRG-2014` 不成功 | 停，保存原文，不下载；报主/原规划，不换同名文件。 |
| 下载 180 s 超时/失败 | 停，不重试；保留日志，回退按旧 bit/CWC 或断电由用户执行，不自动电源循环。 |

## 5. 边界（全程）

仅 SRAM；**0 Flash/efuse/SPI/svf**；0 CLI readback；0 GUI 自动化；不推送；不接 PCIe/RK；不 commit/push；不批量删除；不杀 `td.exe` 45416 或持 FTDI 的 hwserver；不覆盖 0207/B01/T02 冻结件。A/B 未明确前不下载。

## 6. 本轮已准备好的文件（开发未执行）

| 文件 | 用途 | SHA256 |
|---|---|---|
| `board/t02/recovery01/read_id_v6.bwcmd` | 85 B，ASCII/CRLF/正斜杠，仅 connect/read/close | `07ffe8129f8d2da43c288d99ad61b2a68d02804d60ad5a4f03492092a179dbc2` |
| `board/t02/recovery01/run_read_id_v6.py` | 60 s 上限、预检唯一 5555 listener、own PID tree、日志/结果落盘 | `69b8ef618c38d93ef58edec7f31225fb3d6a832281ddc9e9ea3db9c3504c1fc1` |
| `board/t02/recovery01/download_v6.draft.bwcmd` | **草案，含占位符，不可直接运行**；Phase B 填 ASCII bit 路径后一次执行 | `96419834a79c193f15f7617331052e282a71fc9ff57050bccee2ef3753f1e9d3` |
| `board/t02/recovery01/lease-draft-v6.json` | 租约草案（候选 SHA、进程快照、0207 状态、下载 gate） | `4b38da11e668edabb1c803f9ffc594b0d7a59fb7c5914f8f16e1c2a42f8c38d2` |
| `board/t02/recovery01/phase-a-readonly.md` | 上一轮只读诊断记录 | `b50ce892cb7094ee0f1ea8d3449bc47c85ea06153e652e5d3de9c5bad1a98e73` |

> 这些 SHA 在 `board/t02/recovery01/verification-recovery02.txt` 中由脚本复算；本文件写入后不再改动其内容。
