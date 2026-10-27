# dev-result.md — T11.runB-board-readback（P3）

- task_id：`T11.runB-board-readback`
- status：**blocked**（部分执行：SRAM 下载 PASS；CWC 读回未取得）
- reason_code：`TOOL_UNAVAILABLE`（ChipWatcher 读回为 TD GUI 交互，本角色无可脚本化读回入口；已排除“设备缺失”：`read_device_id`=PH1P100、下载成功）
- new_information：true
- blocked 内容：需现场用户按 `board-readback/user-gui-checklist.md` 点击 Watch/Add Signals/Instant Trigger 并原样回报 9 字（两样本 ≥10 s）
- evidence：`board-readback/readback-record.md`、`board-readback/command-audit.md`、`board-readback/logs/01-bw-sram-download.txt`、`board-readback/scratch/log/bw_2026-10-18_22-21-16.log`
- manifest：`board-readback/candidate-manifest.json`
- resume_input_path：`board-readback/user-gui-checklist.md`（用户回报后由同任务开发/规划续收）

## 已做

1. bit/CWC SHA 复核（`2385CDED…1873` / `FA24E258…22BB`）＋ ASCII 暂存后复核一致。
2. `read_device_id`=PH1P100（下载前/后各一次）。
3. `download -mode jtag`（仅 SRAM）→ PRG-2014 + 100% + rc=0 + 28.85 s；命令审计零 flash/efuse/SPI/svf。
4. 证据冻结：读数表（空，未代填）、命令审计、用户 GUI 清单、日志原文、manifest。

## 未做 / 未达

- 9 字读回 0 样本 → Tier-1/Tier-2 **not_evaluated**、G3 not_run；不得记 PASS。
- hwserver（PID 30988）仍运行：停止请求被宿主 shell 权限层拒绝，未绕过。

## 建议下一步（交原规划）

1. 将 `user-gui-checklist.md` 原样转现场用户；用户回报两组 9 字原文（含时间戳/界面原文）。
2. 用户回报后：同 task_id 有界续收（填写读数表、逐条判 Tier-1/Tier-2、关 hwserver、按需回退/保持 SRAM），再交综合测试者。
3. 若用户侧 TD 版本/CWC 不匹配（code mismatch）→ 保留界面原文，按 INPUT_CONFLICT 交原规划，不重建候选。
