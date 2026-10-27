# final-attempt-record.md — 最终 CLI 尝试（同会话 download → run_hw_cw）

- 时间：2026-10-18 23:34:04–23:34:47（+08:00）；操作者=开发子会话（TD 官方 Tcl；无 GUI 自动化）
- 环境：TD 2026.2 `td_commands_prompt.exe`（6.2.3.210850）+ TD 自带 `D:\anlogic\TD_Release_2026.2\bin\hwserver.exe`（PID 35108，23:34:04 启动，结束后已停止、5555 已释放）
- cwd：`D:\anlogic\runa_p3\ascii_20261018_232333\`（ASCII；`compiled.cwc` `FA24E258…22BB`、`compiled.bit` `2385CDED…1873`，SHA 与冻结候选一致）
- **结论：download 成功，但 `run_hw_cw` 仍 KIT-8000 → CLI 永久关闭；GUI 两样本是唯一路径。** 0 样本、无 CSV。

## 执行序列（原文见 `board-readback/cwc-cli/phaseFINAL_stdout.txt`）

| 时间 | 命令 | 结果 |
|---|---|---|
| 23:34:20 | `connect_cable -host_name 127.0.0.1:5555 -open` | OK |
| 23:34:20 | `read_device_id` | **PH1P100** |
| 23:34:21–23:34:47 | `download -bit .../compiled.bit -mode jtag -cable 0` | **`PRG-2014 : Chip validation success: PH1P100`；rc=0；25,871 ms**（同 SHA；仅 SRAM） |
| 23:34:47 | `read_device_id` | PH1P100 |
| 23:34:47 | `config_chipwatcher .../compiled.cwc` | KIT-1004：`auto_created_cwc1`（9 view / 288+288） |
| 23:34:47 | `get_hw_cws *` | `auto_created_cwc1` |
| 23:34:47 | `report_cwc_status auto_created_cwc1` | `KIT-1004 : compile chipwatcher successfully!` |
| 23:34:47 | `run_hw_cw auto_created_cwc1 -trigger_now -cable 0` | **`KIT-8000 No watcher instance matched`（rc=1）** |

- 会话尾部伴随行 `Error @ mpsse.cpp:90 : usb_open() failed` 为第二实例提示，不判败（download 已成功）。
- 未执行 `wait_on_hw_cw` / `write_hw_cw_data`（run 未成功，按停止条件不再变体）。

## 停止判定（符合裁定）

- 命中停止条件：“download 成功但 `run_hw_cw` 仍 KIT-8000 → 最终停；结论=CLI 需 GUI Watch 句柄，GUI 唯一路径”。
- **不再有 CLI 轮**；不换名再试、不做 GUI 自动化、不重综合、不重建。

## 安全审计（本轮）

- 下载：同 SHA bit `2385CDED…1873`，`-mode jtag`=PROGRAM_SRAM（TD `doc/config/config.json` 已确认 macro 语义），**仅 SRAM、1 次**；零 flash/efuse/SPI/svf；未混拼 AFFC4396/旧 bit。
- 未改线/电源/相机；未改 TD 安装目录；未删除/覆盖既有文件；未推送；无网络。
- 板：SRAM 现载 debug 位流（本次 fresh download 后未断电）；hwserver 已停、5555 已释放。

## 冻结

- 新增文件：`board-readback/cwc-cli/phaseFINAL_stdout.txt`、ASCII 目录 `final_dl.tcl`、`hwserver_final_out/err.txt`、23:34 的 `td_*.log(.logw)`；哈希见 manifest v6。
