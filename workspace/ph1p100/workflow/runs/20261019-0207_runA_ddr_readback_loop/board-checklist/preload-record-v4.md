# preload-record-v4.md — 板窗复检 + 只读探测（仍 PRG-8000，未下载）

- task：`T11.runC-board-checklist`（0207 线 P4 续接轮 3）｜时间：2026-10-19 21:19:07–21:23:00 +08:00｜角色：fpga-dev（原会话续接）
- 触发：用户报告“窗口应已空出、同意直接开始使用 TD”；按 resume_plan 执行 板窗机械检查 → 只读 read_device_id → SRAM 预加载。
- 结论：**预加载仍未执行（0 次 download）**。板卡侧 JTAG 传输失败（`PRG-8000 ERROR: transfer failed`，27.1 s）→ 按规则**不重试**、保持 awaiting_user_gui。**用户请先做物理检查（见 §5）**，回来后直接重跑 `preload_fixed.bwcmd`。

## 1. 板窗机械检查（21:19:07）

- **无活跃 TD 构建会话**（`td_commands_prompt`/`run_td`/`run_build` 均无；唯一匹配进程为本角色自己的检查 shell）。
- 环境状态：`td.exe` PID 45416 存活（未触碰）；`hwserver.exe` 由 PID 47904 更替为 **PID 45596（21:19:57 启动，非本角色启动，未触碰）**，5555 端口由其监听。
- 暂存复核：`compiled.bit`=`5b67a8f5…1d52` MATCH；`compiled.cwc`=`8dda54d4…664f` MATCH。
- 并行线占用核对（只读，判定“板上是否已有 0212 刚下载的候选”）：
  - 0212/T02 SRAM 尝试 `board\sram-b01-20261019T205946`（20:59:46–21:01:48）：`result.json` = exit 1 / timeout true / elapsed 121.3 s / **pass=false**；`sram-execution.json` = `download_success=false`、`success_marker_present=false`、`device_lines=[]`、manifest 前后 699 项零漂移、活动已停止；`download.log` 仅含调用与 PID 行（cwd=`Z:/`），无任何设备行/成功标记。
  - 判定：**未发现“0212 已成功下载候选在板”的证据**（其尝试无设备接触、无成功标记、load state unknown，且其自行停止、有对用户的待答问题）。据用户本轮明确指令（窗口空出、同意使用 TD）继续执行只读探测。

## 2. 板载现状（只读；仍未取得 PH1P100）

- 21:20:10 起执行 `read_id_fixed.bwcmd`（connect → read_device_id → close）：
  - `connect_cable -host_name 127.0.0.1:5555 -open` 完成（0.015 s）；
  - `read_device_id` → **`PRG-8000 ERROR: transfer failed`**（27.1 s，与 19:45 同现象）；
  - `connect_cable -close` 未在 120 s 内完成，命令被工具超时终止（本角色自有 bw 客户端；服务端会话自回收）。
- 证据：`read_id3.log`（RUN-1002/1003/1004）。
- **未执行 readback、未执行 download**；不重试。

## 3. 安全与审计

- 命令集仅 `connect_cable`/`read_device_id`；**download 0 次**；零 flash/efuse/SPI/svf；无 GUI 自动化。
- 未结束/未干扰任何他人进程（含 `td.exe` 45416、`hwserver.exe` 45596、0212 相关已退出进程）；未启动新 hwserver。
- 未写工作树、未 commit/push、未碰共享树、无批量删除。
- 超时终止的是本角色自己发起的 bw 客户端进程（同 v2 轮记录口径）。

## 4. 与 0212 线的协调事实（只读记录）

- 0212/T02 于 20:59:46 尝试一次 SRAM 进入（其 1/1 额度）→ 120 s 期限超时失败、无成功标记、加载状态 unknown、已停止并交其原规划；其后有 `question-t02-tool-state.md` 待用户回复（**我不代答、不干预**）。
- 本线本轮据用户指令继续；未覆盖任何已确认的对方候选。

## 5. 用户下一步（物理检查 → 重跑）

1. 检查：板电源开关与指示灯（含 D37/DDR 校准指示）；USB/JTAG 线是否为板卡口并已插稳；必要时换线/换口。
2. 板刚上电时等待 DDR 校准完成（数秒）再试。
3. 回来后（或现场）直接运行：`D:\anlogic\runa_runC\20261019_192056\preload_fixed.bwcmd`（≤1 次；成功判据 `PRG-2014 : Chip validation success: PH1P100` + 100% + rc=0，≈28–40 s；失败不重试）。
4. 成功后按 `board-checklist.md` §3 点两下（16 字 ×2、间隔 ≥10 s），期望值见 §4。

## 6. 变更记录（v4）

- 无既有文档改动；本文件为追加记录，由 `candidate-manifest-v4.json` 绑定。
