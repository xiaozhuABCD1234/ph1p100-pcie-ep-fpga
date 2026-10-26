# preload-record-v6.md — SRAM 预加载成功（板载=新候选 5B67A8F5…）

- task：`T11.runC-board-checklist`（0207 线 P4 续接轮 5）｜记录时间：2026-10-19 21:58 +08:00｜操作者：**用户（czz，控制台）**；本角色仅核对日志并机械记录（未执行下载）。
- **结论：预加载成功（本任务 download 1/1 已用，后续不再下载）**。板载候选=本线 P2 新候选 `5B67A8F5…1D52`；**可以点了**（按 `board-checklist.md` §3/§4）。SRAM 易失：**采样前勿断电**；若断电需按 §2 重下（超出本轮 1/1，需另轮/协调）。

## 1. 判据对照（清单 §2，逐条）

| 判据 | 实测 | 结论 |
|---|---|---|
| `connect_cable` 成功 | 0.024659 s（RUN-1003） | PASS |
| 下载命令路径 | `download -bit D:/anlogic/runa_runC/20261019_192056/compiled.bit -mode jtag -spd 7 -cable 0`（正斜杠，未被转义） | PASS |
| `PRG-2014 : Chip validation success: PH1P100` | 原文出现 | PASS |
| 进度 100% | 进度条到 100% | PASS |
| 时长 ≈28–40 s | **30.037585 s** wall（RUN-1003 finish） | PASS |
| 下载后身份 | `read_device_id` → `PH1P100`（0.032953 s） | PASS |
| `connect_cable -close` | 0.000096 s | PASS |
| `usb_open() failed` 旁路提示 | 出现（`mpsse.cpp:90`），为清单 §2 注明的 bw 自动拉起第二实例提示，**不单独判败** | 可解释 |
| bit SHA | 暂存 `compiled.bit` = `5B67A8F5925327BA9D0442D9E4228FCFD254C80A2F86D921CEDA70ECAE111D52`（复核 MATCH） | PASS |
| 仅 SRAM / 零 Flash | `-mode jtag`；命令审计无 flash/efuse/SPI/svf | PASS |

## 2. 证据（原始日志）

- 成功日志：`D:\anlogic\runa_runC\20261019_192056\log\bw_2026-10-19_21-56-23.log`（sha256 `838742d826461c583aaf6364a810c49960557ace52ea90eb3c4a850d3cb9b09d`，1690 B，21:56:53）
- 预检查（两次只读，均 PH1P100）：`log\bw_2026-10-19_21-55-48.log`（`8beaaa5e…e218`）、`log\bw_2026-10-19_21-56-21.log`（`15de272f…be22`）
- 用户控制台原文：本 run `user-input-05.md`（含 tasklist/taskkill 45596→未找到、read_id_v5 ×2、download_v5、一次粘贴粘连命令报“系统找不到指定的文件”无副作用）
- 现场进程（只读）：`hwserver.exe` 74620（用户控制台实例，21:46:04）＋ 37440（bw 自动拉起，20 K）；`td.exe` 45416；**均未结束/未触碰**

## 3. 执行链（用户操作，按时间）

1. 清理重复 hwserver：`taskkill /PID 45596 /F` → 系统提示未找到（该实例已自行退出，无影响）；保留 74620（持 FTDI）。
2. 21:55:48、21:56:21 两次 `read_id_v5.bwcmd`：`PH1P100`（第二次含 `Use channel A` / `Open device vid=0x0403 pid=0x6042`）。
3. 21:56:23–21:56:53 `download_v5.bwcmd`：成功（见 §1）。
4. 一条粘贴粘连命令（`... < NULcd /d ...`）→ “系统找不到指定的文件”；（无副作用，未执行下载）。

## 4. 板载状态与用户下一步

- **当前板载 = 新候选**（bit `5B67A8F5…1D52` / CWC `8DDA54D4…664F`，16 字 `auto_created_cwc1`）。
- **可以点了**：按 `board-checklist.md` §3 在 TD ChipWatcher 选配对 `compiled.cwc` → Watch → Add Signals word0..15 → Instant Trigger ×2（间隔 ≥10 s）→ 回传 16 字十六进制原文 + 时间戳（§5 模板）。
- 期望值见 §4（word0/1/2、word3 推进、word6 good 增长、word9=0x3E、word10=0x0009E400、word13≥1 且增量≈word3 增量、word11/12 原文、word14/15=head[20]/head[21]）。
- **SRAM 易失**：采样前勿断电/勿重下其它候选；若断电，本任务下载额度 1/1 已用，需另轮或由原规划协调。

## 5. 安全审计

- 本角色本轮**未执行** connect/download/read；仅只读核对日志与 SHA；未结束/未重启任何进程（含用户 hwserver 74620、自动拉起 37440、td 45416）；未启动新 hwserver。
- 零 Flash/efuse/SPI/svf；未 commit/push；未写工作树/共享树；无 GUI 自动化；无批量删除。

## 6. 变更记录（v6）

- `board-checklist.md`：顶部状态改为“板载=新候选、可以点了 + 预加载时间/SHA + SRAM 易失提示”（预期值/判据/§3/§4/§8 未改）。
- 本文件为追加记录；由 `candidate-manifest-v6.json` 绑定。
