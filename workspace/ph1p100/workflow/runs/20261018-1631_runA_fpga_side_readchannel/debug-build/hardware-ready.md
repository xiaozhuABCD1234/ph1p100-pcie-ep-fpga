# hardware-ready.md — T11.runB-debug-build（P2 冻结：READY-FOR-P3，附前提）

状态：**READY-FOR-P3（前提见 §1；P2 r0 未完成前不得上板）**。日期 2026-10-18；原规划冻结（构建与 STA/CWC 证据来自 P1-fix 验证构建，未重建）。

## 1. 上板前提（全部满足才执行）

1. P2 r0 integrated PASS（独立核对 `debug-build/candidate-manifest.json` 的哈希/绑定/本文件前提）。
2. 用户在场；相机单 A 已接；无 PCIe 主机依赖（本轮不验证 PCIe）。
3. bit 以 **ASCII 路径**暂存并复核 SHA256=`2385CDEDAE1D9985687360AF77341183517E34CB18BE9CAD0229291593411873`（5,224,027 B）。
4. CWC 文件 `compiled.cwc` SHA256=`FA24E25830FEFE882EDB3B4D9AB18DE8FD39598A9822231B8622C9A0C73F22BB`（81,063 B）。
5. 仅 SRAM 下载（`-mode jtag`）；会话命令审计须**零** flash/efuse/SPI/svf 命中。

## 2. 下载（执行者=现场操作者；记录命令/退出码/时间）

1. `hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0`（后台）。
2. `bw_commands_prompt.exe` → `connect_cable -host_name 127.0.0.1:5555 -open` → `read_device_id`（期望 `PH1P100`）。
3. `download -bit <ASCII位流路径> -mode jtag -spd 7 -cable 0`。
4. 成功判据：`PRG-2014 : Chip validation success: PH1P100` + 进度 100% + rc=0 + 28–40 s；旁路 `usb_open() failed` 不单独判败。
5. 失败：仅在有新证据/参数纠正时重试 1 次；仍失败→停止并保留日志（不写 Flash、不换工具静默重试）。

## 3. ChipWatcher 读回（执行者=操作者；步骤见 `debug-spec/board-runbook.md`）

1. TD 欢迎页 → ChipWatcher → 打开构建目录内 `compiled.cwc`（Bit File 应指向同目录 `compiled.bit`，SHA 同上）。
2. **Watch** → 实例 `auto_created_cwc1` → **Add Signals** 选入 9 个探针：`dbg_bank_word0..dbg_bank_word8`（对应 0x140..0x160 字序）。
3. 触发方式 **Instant Trigger**；Value 列切 Unsigned/Hex 原样记录。
4. **至少 2 个样本、间隔 ≥10 s**；同实例内 9 字视为同时；跨时刻分开记录（禁止拼成原子快照）。
5. 若出现 code mismatch/设备未识别/无波形：**停在该提示、保留界面与原文**，不重综合、不重烧、不反复点。

## 4. 期望值（判定用；详见 `debug-spec/readback-criteria.md`）

| 探针 | 期望/说明 |
|---|---|
| word0 | `0x50434946`（"FICP"） |
| word1 | `0x31414B52`（"RKA1"） |
| word2 | `0x00010000`（v1.0） |
| word3 | DDR_SEQ_A：采集活时应 ≥1 且样本间增长 |
| word4 | DDR_BASE_A：非零、128 B 对齐（低 7 位=0） |
| word5 | DDR_LEN_A：`2,592,768` |
| word6 | CSI_DIAG_A：`{good,bad,hdr_err,crc_err}` 原值+解码 |
| word7 | CSI_DIAG_A2：`{last_lines,last_wc}` |
| word8 | CTRL 读回：bit0=1、bit5=1、bit4=0、bit6/7/8=0（debug-only 默认开启；[31:9]=0） |

- 身份三字任一不符 → **Tier-1 FAIL**，停止并回报（不得改判据）。
- 相机已接时 good 计数应随样本增长；不增长按“使能/采集状态”如实记录并交原规划判定。

## 5. 停止与恢复

- 命中任何 flash/efuse/SPI/svf 命令、或工具要求未知确认 → 立即停止并留原文。
- DDR 校准异常（黑屏四灯齐报、**D37 灭**）→ **用户物理断电 10 s** → 上电 → 重下同 bit（≤5 min/次）。
- 回退：重下旧 bit `E81D353B…2B9A`（配对 `ab811c8f…`；SRAM 易失，不写 Flash，≈30–40 s）。

## 6. 证据字段（必须齐备）

操作者、时间（含时区）、bit SHA256、CWC 文件 SHA、实例名、命令与退出码、读数原文（≥2 样本）、判定（Tier-1/Tier-2）、恢复/回退记录；任何目视现象不得单独作判据。

## 7. 预算

上板窗口 ≤35 min、读回 15—30 min；执行角色 ≤45 min/≤30 calls；单命令 ≤60 s（下载 28–40 s 除外）。
