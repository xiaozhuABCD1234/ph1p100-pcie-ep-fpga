# preload-record.md — 板窗检查 + SRAM 预加载尝试记录（v2 追加；未下载）

- task：`T11.runC-board-checklist`（0207 线 P4 续接轮）｜时间：2026-10-19 19:34–19:48 +08:00｜角色：fpga-dev（原会话续接）
- 结论：**预加载未执行（0 次 download）**。原因：板卡侧 JTAG 传输失败（`read_device_id` → `PRG-8000 ERROR: transfer failed`），判定为板未上电/线缆未通；按规则**不重试**，保持“回来先重下”分支。**状态仍为 awaiting_user_gui**。
- 冻结候选/预期值/既有证据未变：bit `5B67A8F5…1D52`、CWC `8DDA54D4…664F`（暂存副本 19:34 复核 MATCH）；`board-checklist.md` 预期值表未改（仅修正命令参数，见 §4）。

## 1. 板窗检查（活跃 TD 构建会话 → 有界等待）

- 19:34:27 启动检查：检测到并行线 0212 活跃构建会话（`td_commands_prompt.exe` PID 10996 于 19:14:27、`run_td.ps1` PID 39708、`run_build.py` PID 23400、pwsh PID 5780）；`td.exe` PID 45416 与 `hwserver.exe` PID 49924 为夜间 GUI/线缆实例（**非构建会话，未结束、未触碰**）。
- 有界等待（每 ~2.5 min 复查）：19:37:24 仍活跃 → 19:40:04 仍活跃 → 19:42:43 仍活跃 → **19:45:24 已无活跃构建会话**（累计等待 ≈10.9 min，≤15 min 上限）。未结束任何他人进程。
- 等待期间未连接板卡、未启动 TD/BW 命令。

## 2. 板载现状（只读；未取得 PH1P100）

- 端口/服务：`0.0.0.0:5555 LISTENING PID 49924`（TD GUI 自带 hwserver，复用、未重启、未新建）；`D:\downlaod\bin\bw_commands_prompt.exe` 存在。
- 暂存 SHA 复核（19:34:27）：`compiled.bit`=`5b67a8f5…1d52`（5,224,027 B）MATCH；`compiled.cwc`=`8dda54d4…664f`（143,444 B）MATCH（与 P2 manifest 一致）。
- **尝试 1**（19:45:36–19:45:37）：`read_id.bwcmd` 沿用基线写法（含空 `-usr_args`）→ `USR-8011 ERROR: connect_cable: invalid option -usr_args, param is empty`；rc=0（该 rc 不代表成功）；未发生设备访问。证据：`read_id.log`。
- **尝试 2**（19:45:49，参数纠正后 1 次）：`read_id_fixed.bwcmd`（去掉空 `-usr_args`）→
  - `connect_cable -host_name 127.0.0.1:5555 -open` 完成（0.188 s）；
  - `read_device_id` → **`PRG-8000 ERROR: transfer failed`**（6.52 s）；
  - 随后的 `connect_cable -close` 未在 60 s 内完成，命令被工具超时终止（bw 客户端进程已退出；服务端会话由其自行回收）。证据：`read_id2.log`。
- 判定：**板未响应**（未上电/线缆未通/设备不可达）；**未执行 readback、未执行 download**；不重试、不盲试其它命令。

## 3. 安全与审计

- 仅执行只读命令：`connect_cable` + `read_device_id`；**download 执行 0 次**；零 flash/efuse/SPI/svf；未改线/电源/相机；无 GUI 自动化。
- 既有 `td` 45416 / `hwserver` 49924 未结束、未重启、未改参数；未启动新 hwserver。
- 未写工作树、未 commit/push、未碰共享树、无批量删除。
- 超时终止的是本角色自己发起的 bw 客户端进程（`bw_commands_prompt.exe`），未触碰他人进程。

## 4. 追加/变更记录（v2，只追加；理由）

- 新增暂存文件（D:，未执行）：`read_id.bwcmd`、`read_id.log`、`read_id_fixed.bwcmd`、`read_id2.log`、`download.bwcmd`、`download_fixed.bwcmd`、`preload_fixed.bwcmd`。
- **必须变更**：`board-checklist.md` §1/§2 与 `rollback.md` 的命令去掉了空 `-usr_args`（本机 bw 2026.2 报 `USR-8011`，证据 `read_id.log`）；其余内容/预期值/判据未变。修正版预加载命令用 `preload_fixed.bwcmd`（内容=connect/read/download/read/close，无 `-usr_args`）。
- `candidate-manifest.json`（v1）保持不变；本文件与上述变更由 `candidate-manifest-v2.json` 绑定（append-only supersede）。

## 5. 用户下一步（与 board-checklist §2/§3 一致）

1. 板已上电、线缆通后：确认板窗空闲 → 运行 `D:\anlogic\runa_runC\20261019_192056\preload_fixed.bwcmd`（成功判据：rc=0 + `PRG-2014 : Chip validation success: PH1P100` + 100%，≈28–40 s；失败不重试）。
2. 成功后按 `board-checklist.md` §3 在 TD ChipWatcher 里点两下，回传两样本 16 字原文 + 时间戳（§5 模板）；期望值见 §4。
3. 若板上已有并行线候选/不确定 → 停、不覆盖，交用户/原规划协调。

## 6. 证据文件（本机）

- `D:\anlogic\runa_runC\20261019_192056\read_id.log`（USR-8011）
- `D:\anlogic\runa_runC\20261019_192056\read_id2.log`（RUN-1002/1003/1004 + PRG-8000）
- 暂存目录文件清单与 SHA 见 `candidate-manifest-v2.json.prestage_attempt_files`
