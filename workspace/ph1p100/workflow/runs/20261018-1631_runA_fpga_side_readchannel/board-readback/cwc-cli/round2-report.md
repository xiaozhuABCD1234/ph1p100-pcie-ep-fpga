# round2-report.md — cwc-cli 最终 CLI 轮（T11.runB-board-readback）

- 操作者：开发子会话（TD 官方 Tcl；无 GUI 自动化）；时间 2026-10-18 22:48–22:53（+08:00）
- 结论：**最终 CLI 轮失败 → blocked**（0 样本）。B（配对）与 C（TD download）后 `run_hw_cw` 仍 `KIT-8000 No watcher instance matched`；TD 侧的 `download`/`read_device_id` 全部 `PRG-9505 USB device open error` / `PRG-9525 Chip validation failed` → 无法建立 TD 侧硬件通道。**不再有 CLI round3**，回 GUI 清单兜底。
- 安全性：仍**零 Flash/efuse/SPI/svf**（B/C 轮 stdout 扫描 hits=0；TD `download` 未成功、无写板）；未改线/电源/相机；未混拼 AFFC4396/旧 bit；未用 GUI 自动化；板未断电，SRAM 内仍是 debug 位流（`2385CDED…`，本次未重下成功）。

## A. round1 证据冻结（本次完成）

- `cwc-cli/attempt-record.md`（F8CA0709…D2A01D / 4,517 B）：round1 全部 8 份 stdout 的逐步原文摘要（命令、退出、KIT 号、时间戳）
- `board-readback/candidate-manifest.json` 升级为 v2：新增 `td_tcl_probe.round1` 区块与 cwc-cli 24 个文件哈希（含 13 对 `td_*.log/.logw`）
- 关键事实：`export_chipwatcher` 导出 XML 与 `compiled.cwc` **SHA 相同**（FA24E258…22BB / 81,063 B）

## B. 配对修复（零硬件）— FAIL

- 建立 ASCII 同名对目录 `%TEMP%\runa_p3\cw_pair\{compiled.cwc, compiled.bit}`（SHA 复核：`FA24E258…22BB` / `2385CDED…1873`，与冻结候选逐字节一致）
- B9（22:49:52，`phaseB9_pair.tcl`）：
  - `config_chipwatcher .../cw_pair/compiled.cwc` → KIT-1004 OK（9 view / 288+288）
  - `report_cwc_status auto_created_cwc1` → rc=0（无输出值）
  - `get_hw_cws *` → `auto_created_cwc1`
  - **`run_hw_cw auto_created_cwc1 -trigger_now -cable 0` → `KIT-8000 No watcher instance matched`（rc=1）**
  - 中文原始路径因 Tcl 源码编码（UTF-8）在 TD 内显示为乱码、`ORIG_FILE=0`，且该进程异常退出（exit 码非 0）；结论不依赖该路径（ASCII 同名对已满足配对假设）
- B8（22:49:29）为先导失败：脚本内 `$tag_CONFIG` 变量名拼接错误（应 `${tag}_CONFIG`），已修正；其 stdout 保留

## C. TD download 假设 — FAIL（USB 打不开）

- C1（22:50:18，`phaseC1_probe.tcl`）：确认 TD 器件操作模式表 `doc/config/config.json`：`PROGRAM_SRAM` ↔ macro `"jtag"`（即 `-mode jtag` 就是 SRAM；Flash 系 macro 为 `program_spi/erase_spi/rdbk_spi/…`，本包未用）；`download -help` 无输出；`info args` 对这批命令不可用
- C2（22:50:40，`phaseC2_download.tcl`）：`read_device_id` → `PRG-9505 USB device open error`；`download -bit … -mode jtag -cable 0`（10,103 ms）与 `-mode PROGRAM_SRAM`（10,124 ms）均 rc=1 + `PRG-9525 Chip validation failed`；`config_chipwatcher` OK 后 `run_hw_cw` 仍 KIT-8000
- 期间处置：结束上一轮遗留 `hwserver.exe`（PID 30988，本角色自有进程；22:5x 成功停止，5555 释放）后重试
- C3（22:52:14，`phaseC3_download.tcl`）：hwserver 已停止状态下仍 `PRG-9505` → **TD 2026.2 CLI 侧无法打开 JTAG/USB 设备**（提示 “please re-connect the USB cable”）；说明 `run_hw_cw` 的 KIT-8000 与 TD 自身 USB 通道建立失败同源，非仅配对问题
- 未做：未再尝试其它 download 变体（按“不盲试未知命令”停止）

## D. 读数 — 无

- 无 CSV、无样本；Tier-1/Tier-2 `not_evaluated`、G3 `not_run`（判据未改动、未代填）

## 证据文件（本次新增，均在 `board-readback/cwc-cli/`）

`phaseB8_pair.tcl/.stdout`、`phaseB9_pair.tcl/phaseB9_stdout.txt`、`phaseC1_probe.tcl/phaseC1_stdout.txt`、`phaseC2_download.tcl/phaseC2_stdout.txt`、`phaseC3_download.tcl/phaseC3_stdout.txt`、以及 22:48 后的 `td_*.log/.logw` 会话日志。

> 哈希补充说明：轮末 shell 工具被宿主权限层拒绝（两次），无法为本轮新文件重算 SHA256；文件原位保留、大小见 manifest `round2.artifacts`（`sha256: null` = 待下轮/测试者复算）。这是本轮唯一未完成的冻结步骤。

## lessons（round2）

1. **配对文件名/目录不是 KIT-8000 的根因**：ASCII 同名对 `compiled.cwc`+`compiled.bit` 无法让 `run_hw_cw` 匹配 watcher。
2. **TD CLI 侧 USB 通道是硬门槛**：`PRG-9505 USB device open error` + `PRG-9525 Chip validation failed` 在结束 6.2.2 hwserver 后仍出现 → TD 2026.2 `td_commands_prompt.exe` 无法接管该 FTDI/JTAG（或需要 GUI/驱动侧重新枚举后才行）。`run_hw_cw` 的 KIT-8000 应视为“TD 硬件会话未建立”的同源症状。
3. **`config.json` 是确认 SRAM 模式的可靠依据**：`Mode_Macro.PROGRAM_SRAM = "jtag"`；Flash 系 macro 明确列出，可用于命令审计。
4. **Tcl 变量插值**：`"$tag_CONFIG"` 会解析成变量 `tag_CONFIG`；应写 `"${tag}_CONFIG"`。
5. **中文路径不要进入 TD Tcl 脚本**（编码不可控 → 乱码/崩溃）；一律用 `%TEMP%` ASCII 路径。
6. **进程清理会受宿主权限影响**：`Stop-Process` 首次被拒、同角色二次尝试通过；不能假定总能自动化清理，UI 兜底清单里要保留“结束 hwserver”步骤。
