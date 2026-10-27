# readback-record.md — T11.runB-board-readback（P3，真实上板；部分执行）

- 操作者：开发子会话（下载与审计，机器执行）；**物理操作（断电/接线/相机）无**（本包未触发）
- 时间：2026-10-18 22:20:35 – 22:22:17（**+08:00**；下文时间同）
- 环境：Windows，PowerShell 5.1；hwserver 6.2.2（`D:\downlaod\bin\hwserver.exe`，v1.0c g1deb3940 2024-12-09）/ bw 6.2.2（`D:\downlaod\bin\bw_commands_prompt.exe`）
- 状态：**下载 PASS；CWC 读回未取得（需 TD GUI 交互）→ 本包 blocked，Tier-1/Tier-2 均未判定**

## 1. 前置：位流/CWC 哈希复核（PASS）

| 项 | 路径 | SHA256 | 字节 |
|---|---|---|---|
| debug bit（源，冻结候选） | `debug-fix\prj\ph1p_pcie_integration_Runs\phy_1\ph1p_pcie_integration.bit` | `2385CDEDAE1D9985687360AF77341183517E34CB18BE9CAD0229291593411873` | 5,224,027 |
| 同源 CWC（源） | `...\phy_1\cw\compiled.cwc` | `FA24E25830FEFE882EDB3B4D9AB18DE8FD39598A9822231B8622C9A0C73F22BB` | 81,063 |
| bit（ASCII 暂存，实际下载用） | `%TEMP%\runa_p3\ph1p_pcie_integration_debug.bit` | `2385CDED…1873`（同上，复核相等） | 5,224,027 |
| CWC（ASCII 暂存备查） | `%TEMP%\runa_p3\compiled_debug.cwc` | `FA24E258…22BB`（同上，复核相等） | 81,063 |

- 与 `hardware-ready.md` §1 第 3/4 条、`rollback.md` §1 冻结身份一致；ASCII 复制 `ASCII_OK=True,True`。
- 旧 bit `e81d353b…2b9a` 原位未动；未使用 `AFFC4396…`。

## 2. SRAM 下载（PASS，仅 SRAM）

| 时间 | 命令（原样） | 结果 |
|---|---|---|
| 22:21:13 | `hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0`（PID 30988） | 监听 5555（22:21:15） |
| 22:21:16 | `connect_cable -host_name 127.0.0.1:5555 -usr_args -open` | OK（variant=host_name+usr_args，0.014 s） |
| 22:21:16 | `read_device_id` | **PH1P100** |
| 22:21:16–22:21:45 | `download -bit C:\Users\czz\AppData\Local\Temp\runa_p3\ph1p_pcie_integration_debug.bit -mode jtag -spd 7 -cable 0` | **PRG-2014 : Chip validation success: PH1P100**；进度 **100%**；rc=0；**28.847945 s**（脚本总时长 29.18 s） |
| 22:21:45 | `read_device_id` | PH1P100 |
| 22:21:45 | `connect_cable -close` | OK |

- bw 进程退出码 **0**；`RUNA_P3_DL_END result=ok`。
- 伴随行 `Error @ mpsse.cpp:90 : usb_open() failed` 按 runbook 为第二实例提示，不单独判败。
- 脚本：`board-readback\scratch\sram_download_p3.tcl`（相对路径调用、bit 经环境变量 `RUNA_P3_BIT`）；bw 会话日志：`board-readback\scratch\log\bw_2026-10-18_22-21-16.log`（2,009 B）。
- 原始输出：`board-readback\logs\01-bw-sram-download.txt`。

## 3. CWC 读回（未取得 — 需 GUI）

- 9 字（`dbg_bank_word0..word8` ↔ 0x140..0x160 ↔ 0x040/0x118/0x11C/0x0A0/0x0A4/0x0AC/0x120/0x124/0x044）**未读数**。
- 原因：TD 2026.2 ChipWatcher 读回为 GUI 流程（打开 `compiled.cwc` → Watch → 实例 `auto_created_cwc1` → Add Signals → Instant Trigger）；本角色无 GUI 点击能力。检查 `D:\anlogic\TD_Release_2026.2\bin` 无 cwc/watcher/rdbk 可执行，`scripts` 抽样 300 个 tcl 无 `rdbk_cwc/chipwatcher` 命中 → 无已证实可脚本化入口；按派发要求**不盲试未知命令**。
- 给现场的逐步清单见 `board-readback\user-gui-checklist.md`。

### 3.1 读数记录表（待用户回报后填写；**不得代填/推测**）

| # | 时间(+08:00) | 操作者 | CWC 实例 | word0/0x040 | word1/0x118 | word2/0x11C | word3/0x0A0 | word4/0x0A4 | word5/0x0AC | word6/0x120 | word7/0x124 | word8/0x044 | 备注 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | — | — | — | — | — | — | — | — | — | — | — | — | 未采集 |
| 2 | — | — | — | — | — | — | — | — | — | — | — | — | 未采集 |

## 4. 判定（分 tier，按实况）

| 项 | 结论 | 依据 |
|---|---|---|
| Tier-1（身份三字） | **not_evaluated**（非 PASS、非 FAIL） | 无首样本读数；身份未被否定，只是未读到 |
| Tier-2（基线/CSI） | **not_evaluated** | 同上 |
| G3 | **not_run**（本包 blocked） | 无读回证据 |
| G4 | **not_run** | 范围外（仅短窗） |

- 判据未改动；未以目视/推测替代读数。

## 5. 现场状态与回退

- 板当前运行 **debug 位流（SRAM，易失）**；未写 Flash/efuse/SPI/svf；未改线/电源/相机。
- 本会话启动的 hwserver **仍在运行（PID 30988，22:21:13 启动）**：本角色尝试结束时被宿主 shell 权限层拒绝（未绕过）。TD GUI 若报线缆被占用，由用户结束该 hwserver 后重连。
- 回退：断电 10 s 后上电即清除 SRAM；或重下旧 bit `e81d353b…2b9a`（≈30–40 s，SRAM）。
- DDR 校准异常（D37 灭/四灯）→ 用户断电 10 s→上电→重下同 bit；本包未触发。

## 6. TD Tcl 自动读回尝试（round1 + round2，最终 CLI 轮；2026-10-18 22:35–22:53 +08:00）

- 操作者：开发子会话（TD 2026.2 官方 Tcl，非 GUI 自动化）；工具 `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe`（6.2.3.210850）
- 结果：**0 样本**；Tier-1/Tier-2 仍 `not_evaluated`、G3 `not_run`（判据未改、未代填）
- round1（≤20 calls 用尽）：`config_chipwatcher <compiled.cwc>` 成功（KIT-1004：`auto_created_cwc1`，9 view/288+288）、`get_hw_cws *` OK、`export_chipwatcher` 导出 XML 与 `.cwc` **同 SHA**；但 `run_hw_cw/wait_on_hw_cw/check_cw_trigger/write_hw_cw_data` 一律 `KIT-8000 No watcher instance matched`（含 `connect_cable` 前后）。细节：`cwc-cli/attempt-record.md`
- round2（最终轮）：B 配对修复＝建 ASCII 同名对 `cw_pair\compiled.cwc`+`compiled.bit`（SHA 复核一致）→ `run_hw_cw` 仍 KIT-8000；C TD `download`（先以 `doc/config/config.json` 确认 `PROGRAM_SRAM` macro=`jtag`）→ `download -mode jtag` 与 `-mode PROGRAM_SRAM` 均 **rc=1**，`PRG-9505 USB device open error`×11 + `PRG-9525 Chip validation failed`；结束上一轮遗留 hwserver（PID 30988，本角色自有）后重试仍 `PRG-9505`。细节：`cwc-cli/round2-report.md`
- 结论：TD CLI 侧无法建立 JTAG/USB 硬件会话（KIT-8000 与其同源）；**CLI 路径关闭，不再有 CLI round3**。转 `user-gui-checklist.md` 兜底。
- 安全：零 Flash/efuse/SPI/svf（round2 stdout 扫描 hits=0）；round2 无成功写板；未改线/电源/相机；未混拼 AFFC4396/旧 bit；hwserver 已停止、5555 已释放，板仍上电且 SRAM 内为 debug 位流（`2385CDED…1873`）。
- 冻结：本轮新增文件哈希因轮末宿主 shell 权限两次拒绝而**未能复算**（manifest 中记 `sha256: null`，文件原位保留，交综合测试者/下轮复算并绑定）。

## 7. ASCII 路径有界重试（issue-01 核实；2026-10-18 23:23–23:25 +08:00）

- 目录：`D:\anlogic\runa_p3\ascii_20261018_232333\`（新建；仅复制 `compiled.cwc` `FA24E258…22BB` 与 `compiled.bit` `2385CDED…1873`，SHA 与冻结候选一致；未写 TD 安装、未删未覆盖）
- **结论：issue-01（非英文路径）假设排除**
  - 同一 ASCII cwd、无 hwserver：`read_device_id` 仍 `PRG-9505`（与中文 cwd 相同）
  - 同一 ASCII cwd、启动 **TD 2026.2 自带 `bin\hwserver.exe`**（PID 73028）后：`connect_cable -host_name 127.0.0.1:5555 -open` OK → **`read_device_id`=PH1P100** → `config_chipwatcher` OK → `report_cwc_status` 打印 **`compile chipwatcher successfully!`**
  - 即便如此，`run_hw_cw`（实例名 / `_trigger` / `*` / 9 个探针总线名 / 有无 `-cable`）**全部 `KIT-8000 No watcher instance matched`** → 路径、配对、USB 均非 KIT-8000 根因
- 探针总线名（A3 KIT-1001 原文）：`u_top/u_pcie_ep_engine/u_ep_bar_win/g_dbg_mark$dbg_mark_word0[31:0]` … `word8[31:0]`
- 读数：仍 **0 样本**、无 CSV；Tier-1/Tier-2 `not_evaluated`、G3 `not_run`
- 安全：本轮**未重下 bit**、零写板、零 Flash/efuse/SPI/svf、未改线/电源/相机、无 GUI 自动化
- 残留：**TD hwserver 6.2.3（PID 73028）仍在运行并占用 5555**（轮末 shell 权限拒绝，未能停止）→ 用户开 TD GUI 前请先在任务管理器结束 `hwserver.exe`
- 细节：`cwc-cli/ascii-attempt-record.md`；stdout：`cwc-cli/phaseASCII1..4_stdout.txt`

## 8. 最终 CLI 尝试（同会话 download → run_hw_cw；2026-10-18 23:34 +08:00）

- 环境：TD hwserver（PID 35108，TD 2026.2 自带，结束后已停止）+ ASCII cwd `D:\anlogic\runa_p3\ascii_20261018_232333\`
- 经过：`connect_cable -host_name 127.0.0.1:5555 -open` OK → `read_device_id`=PH1P100 → **`download -bit compiled.bit -mode jtag -cable 0` 成功（`PRG-2014`，rc=0，25,871 ms，同 SHA 仅 SRAM）** → `read_device_id`=PH1P100 → `config_chipwatcher` OK → `report_cwc_status`=`compile chipwatcher successfully!` → **`run_hw_cw auto_created_cwc1 -trigger_now -cable 0` 仍 `KIT-8000 No watcher instance matched`**
- **结论：CLI 永久关闭（同会话 download 亦不能注册 hw watcher 句柄）；GUI 两样本是唯一路径。**
- 读数：仍 **0 样本**、无 CSV；Tier-1/Tier-2 `not_evaluated`、G3 `not_run`；判据未改、未代填。
- 安全：下载 1 次同 SHA 位流（SRAM，`-mode jtag`）、零 Flash/efuse/SPI/svf、未改线/电源/相机、无 GUI 自动化；hwserver 已停、5555 已释放；板保持上电（SRAM 内为本次 fresh download 的 debug 位流）。
- 细节：`cwc-cli/final-attempt-record.md`；stdout：`cwc-cli/phaseFINAL_stdout.txt`

## 9. 用户 GUI 实读（ChipWatcher，2026-10-18 23:43:39 +08:00）— **NOT MATCHED（全零）**

来源：`user-input-08.md`（用户原话+截图转述，原样保存）。操作者=现场用户；通道=ChipWatcher GUI（`auto_created_cwc1`）。

### 9.1 读数原文

| # | 时间(+08:00) | 操作者 | 实例 | word0/0x040 | word1/0x118 | word2/0x11C | word3/0x0A0 | word4/0x0A4 | word5/0x0AC | word6/0x120 | word7/0x124 | word8/0x044 | 备注 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 23:43:39 | 现场用户 | auto_created_cwc1 | `00000000` | `00000000` | `00000000` | `00000000` | `00000000` | `00000000` | `00000000` | `00000000` | `00000000` | Status=Idle；**Triggered: 1**；波形 115–140 全 0；触发位置 127/1024；Bit File=`D:\anlogic\runa_p3\ascii_20261018_232333\compiled.bit`（SHA 2385CDED…1873，与冻结候选一致） |
| 2 | — | — | — | — | — | — | — | — | — | — | — | — | **未采集**（首样本全零，按判据不再采样） |

- 9 个信号齐全（`dbg_mark$dbg_mark_word0[31:0]` … `word8[31:0]`），Value 列十六进制、波形窗口 115–140、触发标记 127、Window data depth=1024、Trigger Condition=Basic AND、Number of windows=1。

### 9.2 判定

| 项 | 结论 |
|---|---|
| Tier-1（身份三字） | **NOT MATCHED**（word0=0x00000000 ≠ `0x50434946`；三字全零）——**不得记 PASS**；本次读数无法用于验收 |
| Tier-2 | `not_evaluated`（无从判定；MAGIC 常量字亦为 0，说明并非“计数未动”而是探针域整体冻结，见 §9.3） |
| G3 | `not_run`（无有效样本） |
| 用户操作 | **无误**（信号、触发、取值列均符合清单；唯一未做项=未采第二样本，因首样本即全零按判据停） |

### 9.3 全零根因（证据链，详见 `zero-read-diagnosis.md`）

- RTL：`ep_bar_win.v` 的 9 个 `MARK_DEBUG` 快照寄存器为 `always @(posedge clk or posedge rst)`，`clk=tl_clk_user`、`rst=tl_rst_user`（`pcie_ep_engine.v` 例化处 `.clk(tl_clk_user)`/`.rst(tl_rst_user)`），复位值全 0。
- `tl_rst_user` 由 `ph1p_pcie_rst_sync`（`LTSSM_VAULE=5'h10`）产生：只有当 `pl_link_up==1` 且 LTSSM==L0 持续足够拍数后才释放（`rst_dly[10]`），否则一直保持复位（`rst_sync=1`）。
- 本轮为**严格 FPGA 侧、未接 PCIe 主机**：链路无法训练到 L0 → `tl_rst_user` 持续有效 → 9 个快照寄存器被钉在复位值 0 → ChipWatcher（其采样/触发时钟仍然在跑，故 `Triggered: 1`）采到的就是恒定全零。
- 因此这是**探针所在时钟域/复位条件问题（设计侧）**，与用户操作、CWC 配对、位流 SHA、trigger 位置均无关；**GUI 重试不会改变结果**。

## 10. P1-fix3 新候选 SRAM 下载（2026-10-19 00:41–00:42 +08:00）— 下载 PASS，待用户 GUI 两样本

- 背景：issue-02（复位域）修复后新候选 `debug-fix3`：bit `BFAFDF97FF78D6F6D2646FFC706542A0BBBB7E11869043BA754CF68A270813D0`（5,224,027 B）、CWC `8D2998B96EF1763C14A1302118235A687488297CE496692B1F6CD95D76981026`（81,063 B）。
- ASCII 暂存：`D:\anlogic\runa_p3\p1fix3_20261019_004115\`（新建，不覆盖）：`compiled.bit`/`compiled.cwc` 与源逐字节一致（SHA 复核相等）。
- 通道：**复用用户 TD GUI 已运行的 TD hwserver（PID 30928，23:43 启动，5555）**，未另起服务。
- 命令与结果（原文 `cwc-cli/phaseP3R_stdout.txt`、`D:\anlogic\runa_p3\p1fix3_20261019_004115\td_20261019_004143.log`）：

| 时间 | 命令 | 结果 |
|---|---|---|
| 00:41:43 | `connect_cable -host_name 127.0.0.1:5555 -open` | OK |
| 00:41:43 | `read_device_id` | **PH1P100** |
| 00:41:43–00:42:12 | `download -bit D:/anlogic/runa_p3/p1fix3_20261019_004115/compiled.bit -mode jtag -cable 0` | **`PRG-2014 : Chip validation success: PH1P100`**；rc=0；**28,356 ms**（仅 SRAM） |
| 00:42:12 | `read_device_id` | PH1P100 |

- 会话 exit=0 / 31.47 s；全程仅 4 条命令（connect/read_id/download/read_id），**零 flash/efuse/SPI/svf**；未改线/电源/相机；无 GUI 自动化；旧候选（`e81d353b…`、`2385cded…`）与 `AFFC4396…` 未混拼、未改动。
- 读数：仍 **0 样本**（等用户按新清单点 2 次 Instant Trigger）；Tier-1/Tier-2 `not_evaluated`、G3 `not_run`。
- 新清单：`board-readback/user-gui-checklist-p1fix3.md`（旧清单 `user-gui-checklist.md` 作废，不再使用）。

## 11. 用户 GUI 两样本（新候选 P1-fix3）— **Tier-1 PASS / Tier-2 部分通过**

来源：`user-input-10.md`（4 张 ChipWatcher 截图，Value=Hex；**两组具体时间用户未标注**，上一轮截图 Updated 时间 1:0:15 / 1:1:26 疑同两次触发，**时间待用户确认**）。操作者=现场用户；实例 `auto_created_cwc1`；bit/CWC SHA 同 §10。

| # | 时间 | 操作者 | word0 | word1 | word2 | word3 | word4 | word5 | word6 | word7 | word8 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A | 未标注 | 现场用户 | `50434946` | `31414B52` | `00010000` | `00006EF2` | `00900000` | `00279000` | `F2000000` | `089012DE` | `00000021` |
| B | 未标注 | 现场用户 | `50434946` | `31414B52` | `00010000` | `0000700B` | `00100000` | `00279000` | `0B000000` | `089012DE` | `00000021` |

- 逐字解码与完整判定见 `board-readback/tier-evaluation-p1fix3.md`：
  - word3：28,402 → 28,683（Δ=281 帧，递增）；word4：9 MiB ↔ 1 MiB（均 128 B 对齐，缓冲切换）；word5=2,592,768 两样本一致；word8=`0x21`（bit0 使能、bit5 ddr_en，push/TX 位全 0）；word6 good=242/11（bad=hdr=crc=0）；word7=0x089012DE（last_lines=2192、last_wc=4830，两样本相同）。
- **Tier-1 = PASS**（身份三字全中 + word0/1/2/5/7/8 逐字可复读、word3/4 可解释）。
- **Tier-2 = 部分通过**（word3/4/5/8 与 word6/7 原文解码命中；word6 good 非单调，如实记录并归因，见评价文件 §3）。
- **G3 = pass（仅 FPGA 侧读通道及上述观察项）**；**G4 = not_run**；PCIe 主机侧、端到端图像与长稳**未覆盖**（评价文件 §4）。
- **更正（r0 FAIL 修复）**：按 dev-plan §3.5 L174/L180，**G3 = `partial`**（Tier-1 过而 Tier-2 有 1 项未达），此前记 pass 属判据放宽，已在 `tier-evaluation-p1fix3.md` §2/§5 与 manifest v10 同步更正。
- **格式门未闭环**：两组读数无用户标注时间、间隔不可核（`user-input-09.md` 的二进制截图经核对不能与 hex 读数绑定）→ 需**一次有界重采**（见 `tier-evaluation-p1fix3.md` §6）；重采前本判定为**暂定**，不据此发 PASS。

## 12. 用户 GUI 有界重采（带时间；**当前判定依据**）— Tier-1 PASS / Tier-2 部分通过

来源：`user-input-12.md`（4 张 ChipWatcher 截图，Value=Hex，Updated at 可见；操作者=现场用户；实例 `auto_created_cwc1`；bit/CWC 同 §10）。

| # | 时间(+08:00) | 操作者 | word0 | word1 | word2 | word3 | word4 | word5 | word6 | word7 | word8 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **2026/10/19 1:30:48**（完整） | 现场用户 | `50434946` | `31414B52` | `00010000` | `0000B1BE` | `00900000` | `00279000` | `BE000000` | `089012DE` | `00000021` |
| 2 | **2026/10/19 1:31:7x**（秒位被截图截断，下界 1:31:07） | 现场用户 | `50434946` | `31414B52` | `00010000` | `0000B2EA` | `00900000` | `00279000` | `EA000000` | `089012DE` | `00000021` |

- **间隔**：1:30:48 → ≥1:31:07 ⇒ **≥19 s（≥10 s，可核）**；上限（若为 1:31:59）为 71 s。
- 解码：
  - word0/1/2 身份三字全中（FICP / RKA1 / v1.0）；word5=`00279000`=2,592,768；word8=`00000021`（bit0=1、bit5=1、bit4=0、bit6/7/8=0、[31:9]=0）。
  - word3：`0xB1BE`=45,502 → `0xB2EA`=45,802，**Δ=0x12C=300 帧**（非减且 ≥1；与 ≥19 s 间隔下的采集流水一致）。
  - word4：两样本同为 `00900000`（9 MiB，非零且 128 B 对齐）。
  - word6：`0xBE000000`→`0xEA000000` ⇒ good[31:24]=190→234（**+44**，本对样本内增长），bad/hdr_err/crc_err 均为 0。
  - word7：`089012DE` 两样本一致（last_lines=2192、last_wc=4830）。
- **判定（以本 §12 为准）**：Tier-1 = PASS；Tier-2 = 部分通过（word3/4/5/8 与 word6/7 原文解码命中；"good 增长"在**本对**样本内成立，但 §11 早期一对曾出现回退，故该项判据仍按“两样本不稳定”记，**G3 保持 `partial`，不升 pass**）；G4 = not_run。
- **superseded 说明**：§11 的两样本（无时间、时间/间隔不可核）现仅作历史观察；其读数与解码未变、仍可复核，但**不作为当前判定依据**。
- 安全：两样本期间无任何命令执行（用户仅点击 Instant Trigger），零写板、零 Flash；候选未改动。
- 安全：word8 无 push/TX 位被误开；本轮零写板、零 Flash、未改候选。
