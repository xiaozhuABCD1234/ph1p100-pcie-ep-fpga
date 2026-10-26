# dev-notes.md — T11.runB-board-readback（P3）

时间线（2026-10-18，+08:00）：
- 22:20:35 开始；SHA 复核 + ASCII 暂存（`%TEMP%\runa_p3\`）
- 22:21:13 hwserver 启动（PID 30988）；22:21:15 监听 5555
- 22:21:16 bw 会话开始（`connect_cable` → `read_device_id`=PH1P100）
- 22:21:16–22:21:45 `download -mode jtag`（28.847945 s，rc=0，PRG-2014，100%）
- 22:21:45 复读 PH1P100 + `connect_cable -close`；bw 退出码 0
- 22:22:17 读回能力核查：TD bin 无 cwc/watcher/rdbk 可执行；`scripts` 抽样 300 tcl 无 `rdbk_cwc/chipwatcher` → GUI-only 判定
- 22:2x 证据冻结；hwserver 停止被宿主权限拒绝（未绕过）

关键事实：
- 下载文件 = 冻结候选 bit（SHA 一致、字节一致），CWC 同源（仅记录，未用于读回）。
- 仅 SRAM；`-mode jtag`；零 flash/efuse/SPI/svf token（hits=0）。
- 未使用 `AFFC4396…`、未动旧 bit `e81d353b…`。
- 板保持 debug SRAM 位流（易失）；未改线/电源/相机。

未决：
- 9 字读回需 GUI（ChipWatcher）→ 用户按清单操作；本包不代填读数、不判 Tier。
- hwserver PID 30988 遗留；TD 若占用冲突由用户结束。

文件：
- `readback-record.md`（含哈希表/命令表/读数表/Tier 状态/回退）
- `command-audit.md`（命令枚举 + 禁止命令扫描）
- `user-gui-checklist.md`（现场逐步清单 + 回报格式）
- `logs/00-hwserver-*.txt`、`logs/01-bw-sram-download.txt`
- `scratch/sram_download_p3.tcl`、`scratch/log/bw_2026-10-18_22-21-16.log(.logw)`
