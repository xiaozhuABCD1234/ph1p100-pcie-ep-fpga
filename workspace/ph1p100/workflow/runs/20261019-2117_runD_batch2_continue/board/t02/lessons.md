# T02 lessons — runD batch2（2026-10-19）

## 可复用根因/触发

1. **JTAG 传输层失败会表现为“无输出 + 超时”**：本 run 两次 `bw.exe` 只读探测均在 60 s 被自有进程树终止，stdout/stderr 均 0 字节；0207 同时段 `read_device_id` 报 `PRG-8000 ERROR: transfer failed`（27.1 s）。因此“日志为空”不能当成功或“未接触设备”，必须按超时/身份未知处理。
2. **0212 的 120 s 下载超时同源**：`sram-execution.json` 记录 121.3 s、0 device lines、无成功标记、load unknown。加长到 180 s 不会修复物理链路；先做电源/USB/JTAG/校准检查。
3. **板窗协调有效**：0207 v4 明确 0 次下载、未持有窗口；本 run 探测失败后立即释放租约，不阻塞并行线。不要杀 `td.exe`/`hwserver`，也不要另起 server。
4. **记录脚本本身的错误会吞掉证据**：PowerShell 5.1 不支持 `if` 作为表达式；先落 `probe-result.json` 再打印，或拆成独立语句。重试仅限“记录纠正”，不是硬件重试。

## 验证入口

- `board/sram/20261019_213000/probe-result.json`、`read_id*.log`（0 字节）
- `board/board-window-lease.json`（进程快照/0207 结论/窗口释放）
- `workflow/runs/20261019-0207_runA_ddr_readback_loop/board-checklist/preload-record-v4.md`（PRG-8000 旁证）
- 0212 `board/t02/sram-execution.json`（历史 120 s 超时）

## 下次最小动作

物理检查（电源/指示灯/DDR 校准/USB-JTAG 线）→ 新授权轮次重跑机械检查 → 只读 `read_device_id`（≤60 s）→ 仅在 `PH1P100` 后写新租约并做一次 ≤180 s SRAM 下载；仍零 Flash、零 CLI 读回、零 GUI 自动化。
