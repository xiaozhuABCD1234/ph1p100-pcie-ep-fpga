# board-runbook.md — 上板下载/读回操作清单 + 读数记录表（P3 用，冻结，T11.runB-debug-spec）

- 触发：P3（`T11.runB-board-readback`）派发 + 用户在场 + P2 `hardware-ready.md` 齐备；相机已接（单 A）。
- 预算：读回 15–30 min（上板窗口 ≤35 min）；单次下载 ≤5 min。执行者：开发子会话 + 用户（物理操作）。
- 安全：**仅 SRAM**（`-mode jtag`）；**绝不写 Flash/efuse/SPI**；不改线/电源/相机；物理断电由用户执行；命令审计零命中（§5）。
- GUI 步骤若无法脚本化，由用户按本清单操作并原样回报；执行者记录在案（**不预设** CLI `rdbk_cwc_data` 可行）。

## 0. 前置检查（下载前）

1. **bit/CWC 配对**：使用 P2 manifest 指定的 debug `compiled.bit`（或 best_result bit）与同源 `compiled.cwc`；两者 SHA256 记录；bit 先复核 SHA 与 P2 manifest 一致（不一致 → 停）。
2. **ASCII 暂存**：把 bit 复制到纯 ASCII 路径（例：`C:\Users\czz\AppData\Local\Temp\opencode\runa_b2\ph1p_pcie_integration_debug.bit`；中文路径 → PRG-8000）；脚本一律**相对路径**调用（先 `Push-Location` 到脚本目录），参数经**环境变量**传入（B1 口径，channel-notes §3.1）。
3. **旧 bit 原位保留**（回退用）：记录旧 bit SHA256（`E81D353B…2B9A` 完整值从 P2/P3 manifest 引用；不移动、不覆盖）。

## 1. SRAM 下载（bw；只写 SRAM）

```
hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0          (先启动并保持；D:/downlaod/bin/hwserver.exe)
connect_cable -host_name 127.0.0.1:5555 -open
read_device_id                                          (期望 PH1P100)
download -bit <ASCII_PATH> -mode jtag -spd 7 -cable 0
connect_cable -close
```

- 成功判据：`PRG-2014 : Chip validation success: PH1P100` + 进度 100% + `download` rc=0 + 时长 ≈28–40 s；旁路 `usb_open() failed` 提示**不单独判败**（bw 自动拉起的第二实例提示）。
- 记录：操作者、时间（含时区）、命令、rc、时长、日志路径（`<脚本cwd>\log\bw_*.log`）、bit SHA。
- 命中 flash 命令或未知提示 → **立即停止**，记录原文，交原规划。

## 2. CWC 读回（≥2 样本，间隔 ≥10 s）

1. 打开 TD（2026.2）→ ChipWatcher → 选择与下载 bit **同源**的 `compiled.cwc` → Watch。
2. 确认 Bit File 指向同目录配对 bit；如 GUI 要求在本窗口下载：允许，但必须记录（同一 `compiled.bit`、SHA 复核，不得换成其他 bit）。
3. Add Signals：`probe-map.md` §3 的 9 个 dbg_bank 字；触发列表留空；Instant Trigger 一次。
4. 从波形/Value 列表读取 9 字**原文**（十六进制原样）→ 填 §4 记录表；间隔 ≥10 s 再采第 2 个样本。
5. **相机采集统计**（相机已接单 A）：同一读法在 ≥10 s 间隔下复读 0x120/0x124（+B 组按条件），记录原文与时间。
6. 失败保留：Idle/Triggered=0/无波形 → 保留界面原文入记录，**不判硬件故障**；可按限次（≤2）重试 Instant Trigger；仍无 → 记录并交原规划 blocked（不盲改、不盲试命令）。
- 非原子告示：同实例内信号视为同时；跨实例/跨时刻分开记录，禁止合并为“原子快照”。

## 3. 异常与回退

- **DDR 校准异常**（黑屏四灯齐报、**D37 灭**）→ **用户物理断电 10 s** → 上电 → 重下同 bit（≤5 min/次）；记录时间与结果。
- 正常结束：保持 SRAM 调试位流（掉电即失）；不写 Flash。
- **回退**（需恢复原状时）：重下旧 bit `E81D353B…2B9A`（SRAM，≈30–40 s；旧文件原位保留）；记录命令/rc/时长/SHA。
- 任何一步失败：保留界面与日志原文，停止修改，交原规划。

## 4. 读数记录表（每样本一行；原文十六进制）

| # | 时间(时区) | 操作者 | CWC 实例 | 0x040 | 0x118 | 0x11C | 0x0A0 | 0x0A4 | 0x0AC | 0x120 | 0x124 | 0x044 | 备注 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 |  |  |  |  |  |  |  |  |  |  |  |  |  |
| 2 |  |  |  |  |  |  |  |  |  |  |  |  |  |

附注行：下载 rc / 时长 / PRG-2014；bit SHA256；`compiled.cwc` SHA256；CWC 实例名；日志路径；失败界面原文。

## 5. 审计清单（P3 收尾逐条勾选）

- [ ] 命令审计：零 flash/efuse/SPI/svf（bw 会话日志逐条核对）
- [ ] 未改线/电源/相机；物理操作均由用户执行并记录
- [ ] bit/CWC 配对与 SHA 记录完整；每条读数绑定通道/时间/操作者/输入哈希
- [ ] ≥2 样本、间隔 ≥10 s；非原子告示在案
- [ ] 回退路径已记录（或已执行重下旧 bit）
