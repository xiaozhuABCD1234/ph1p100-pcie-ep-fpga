# attempt-record.md — cwc-cli 自动读回尝试（T11.runB-board-readback）

- 操作者：开发子会话（CLI 触发；非 GUI 自动化）
- 工具：`D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe`（TD 2026.2 / Build 6.2.3.210850，Tcl 8.6.17）
- CWC：`compiled.cwc` SHA256 `FA24E25830FEFE882EDB3B4D9AB18DE8FD39598A9822231B8622C9A0C73F22BB`（81,063 B；ASCII 副本 `%TEMP%\runa_p3\compiled_debug.cwc`，SHA 相同）
- bit（板上 SRAM 已由 bw `-mode jtag` 于 22:21 下载）：SHA256 `2385CDEDAE1D9985687360AF77341183517E34CB18BE9CAD0229291593411873`
- 判定：**CLI 路径未取得任何读数（0 样本）**；无下载、零 Flash、无 GUI 自动化、未改线/电源/相机

## R1-A（22:35:46）：命令表枚举 — PASS

- `td_commands_prompt.exe ./phaseA_probe.tcl` exit=0 / 0.46 s
- 已注册：`get_hw_cws get_cw_probes run_hw_cw wait_on_hw_cw write_hw_cw_data check_cw_trigger config_chipwatcher export_chipwatcher report_cwc_status rdbk_cwc_data read_cwc_data set_cwc write_cwc_reg read_cwc_reg export_chipprobe_config open_chip_viewer connect_cable list_cable`
- `open_hw_manager` 不存在；各命令 `-help` 输出为空

## R1-B（22:36:14）：`config_chipwatcher` — PASS

- `config_chipwatcher C:/.../compiled_debug.cwc` → `KIT-1004: import watcher inst auto_created_cwc1 completed, 9 view node(s), 288 trigger net(s), 288 data net(s)`；Chipwatcher code = 1010110001101100
- `get_hw_cws`（裸）→ `KIT-8414 ERROR: please specify a name of watcher instance`

## R1-B2（22:36:42）：无 config 会话直接读 — FAIL（会话级状态，属已知行为）

- 同一/独立会话中未先 config 时：`get_hw_cws auto_created_cwc1` → `KIT-8000 No ChipWatcher instance found`；`run_hw_cw/wait_on_hw_cw/check_cw_trigger/write_hw_cw_data` → `KIT-8000 No watcher instance matched`

## R1-B3a（22:37:18）：config + 读回同会话 — FAIL（核心卡点首次复现）

- `B3A_HWS OK: auto_created_cwc1`；`get_cw_probes auto_created_cwc1` → `KIT-8000 No probe matched auto_created_cwc1`
- `check_cw_trigger/run_hw_cw/wait_on_hw_cw/write_hw_cw_data`（`auto_created_cwc1`）→ `KIT-8000 No watcher instance matched`；无 CSV

## R1-B4（22:37:54）：对象名枚举 + 完整导出 — 部分 PASS

- `get_hw_cws *` → `auto_created_cwc1`；`get_hw_cws auto_created_cwc1 -verbose` → `KIT-1001 Total Matches 1 / auto_created_cwc1`
- `get_cw_probes *` → `{} {} {} {} {} {} {} {} {}`（9 项，均为空列表）；`get_cw_probes auto_created_cwc1/*` → `KIT-8000 No probe matched`
- `export_chipwatcher` → **成功**，输出 81,063 B XML（`%TEMP%\runa_p3\export_chipwatcher.txt`）：实例 `auto_created_cwc1`，9 个 view node（`u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word0..8[31:0]`，时钟 `u_top/u_uart/u_uart_cdc/core_clk` 16 ns），trigger 名 `auto_created_cwc1_trigger`，15 片 phy_eram 映射（与 `debug-fix/cwc-multipiece-map.json` 一致）
- `export_chipprobe_config` → `KIT-8006 Please import a netlist at first`（0 B）

## R1-B5（22:38:43）：run_hw_cw 参数变体矩阵 — 全部 FAIL

- 变体：`auto_created_cwc1_trigger` / `*` / `[get_hw_cws]` / 无 `-cable` / `-cable` 前置 / `check_cw_trigger *` → 一律 `KIT-8000 No watcher instance matched`
- `report_cwc_status auto_created_cwc1` → OK（无输出值；**Bit File 列为空**，成为 round2 线索）

## R1-B6（22:39:58）：-- 写入 BOM 事故（记录） --

- 脚本经 PowerShell `Set-Content -Encoding UTF8`（PS5.1 带 BOM）→ TD `invalid command name "\ufeffset"`，exit=0/0.29 s、无任何执行

## R1-B7（22:40:22）：去 BOM 重跑 + `connect_cable` 预连接 — FAIL（最终卡点）

- `list_cable` OK（空输出）、`connect_cable -host_name 127.0.0.1:5555 -open` OK、`connect_cable`（裸）OK
- `get_hw_cws *` OK → `auto_created_cwc1`
- `run_hw_cw auto_created_cwc1 -trigger_now -cable 0` → `KIT-8000 No watcher instance matched`
- `wait_on_hw_cw -timeout 20 -cable 0`、`check_cw_trigger -cable 0`、`write_hw_cw_data -csv_file` → 同一 KIT-8000；无 CSV
- 全程 exit=0 / 12.73 s；**未产生任何写板动作**

## 结论（round1）

- 官方 Tcl 命令确实存在且**导入/枚举/导出**可用；但**硬件 watcher 注册**未建立：`run_hw_cw` 家族一律 `KIT-8000 No watcher instance matched`，即使先 `connect_cable`。
- 与 `report_cwc_status` Bit File 行为空一致 → round2 需要验证 “CWC 与配对 bit 同目录同名 / 由 TD 下载注册” 假设。
