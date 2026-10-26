# preload-record-v3.md — 板窗复检（用户报告“板子上电了”）+ 等待超限记录（未下载）

- task：`T11.runC-board-checklist`（0207 线 P4 续接轮 2）｜时间：2026-10-19 19:58:30–20:13:44 +08:00｜角色：fpga-dev（原会话续接）
- 触发：用户报告“板子上电了”；按 resume_plan 执行 板窗机械检查 → 只读 read_device_id → SRAM 预加载。
- 结论：**预加载仍未执行（0 次 download）**。板窗被并行线 0212 的活跃 TD 构建会话占用，有界等待 ≈15.2 min 未结束（达到 15 min 上限）→ 按规则**保持 awaiting_user_gui、记录证据并返回**；未连接板卡、未做任何设备访问。**板已上电条件下，下一轮（构建会话结束后）可直接用 `preload_fixed.bwcmd` 重试预加载。**

## 1. 板窗机械检查（19:58:30）

- 检出**新的活跃 TD 构建会话**（并行线 0212 `remaining-attempts01` attempt 5，19:53:41–19:53:43 启动）：`pwsh.exe` PID 73228、`python.exe`（run_build.py）PID 48208、`powershell.exe`（run_td.ps1）PID 52464、`td_commands_prompt.exe` PID 45868。
- **环境状态变化（如实记录）**：夜间 `hwserver.exe` **PID 49924 已退出**；5555 端口现由 **PID 47904**（新 hwserver 实例，非本角色启动）监听。`td.exe` PID 45416 仍在（GUI 夜间实例，未触碰）。本角色未启动、未结束、未改任何 hwserver 参数。
- 暂存复核（19:58:30）：`compiled.bit`=`5b67a8f5…1d52` MATCH；`compiled.cwc`=`8dda54d4…664f` MATCH；`preload_fixed.bwcmd` 就绪（connect → download(-mode jtag) → read_device_id → close）。

## 2. 有界等待（每 ~2.5 min 复查；累计 ≤15 min）

| 复查时刻 | 结果 |
|---|---|
| 20:01:20 | STILL（4 进程均在） |
| 20:04:05 | STILL |
| 20:06:47 | STILL |
| 20:09:29 | STILL |
| 20:12:06 | STILL |
| 20:13:44 | STILL（累计 ≈15.2 min → 达上限，停止等待） |

- 未结束/未触碰任何他人进程；等待期间未连接板卡、未启动 TD/BW 命令。

## 3. 未执行项与安全审计

- `connect_cable`：未执行；`read_device_id`：未执行（本轮未取得 PH1P100，亦无 PRG-8000 新增记录）；`download`：**0 次**；零 flash/efuse/SPI/svf；未改线/电源/相机；无 GUI 自动化。
- 未写工作树、未 commit/push、未碰共享树、无批量删除。
- 既有 `td.exe` 45416 未触碰；hwserver 实例（47904）非本角色进程，未触碰。

## 4. 用户可点的前提（与 `board-checklist.md` §3/§4 一致）

1. 待 0212 构建会话结束（或用户明确协调窗口）后：板已上电 → 运行 `D:\anlogic\runa_runC\20261019_192056\preload_fixed.bwcmd`（成功判据：`PRG-2014 : Chip validation success: PH1P100` + 100% + rc=0，≈28–40 s；失败不重试）。
2. 成功后按 `board-checklist.md` §3 在 TD ChipWatcher 点两下（16 字 ×2 样本、间隔 ≥10 s），回传原文+时间戳；期望值见 §4。
3. 板上若已有并行线候选/不确定 → 停、不覆盖。

## 5. 变更记录（v3）

- 无既有文档改动（`board-checklist.md`/`rollback.md`/`preload-record.md` 均未动）；本文件为追加记录，由 `candidate-manifest-v3.json` 绑定。
