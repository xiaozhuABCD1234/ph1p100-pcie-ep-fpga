# fpga-design-guide.md — 20261018-1347_runA_offline_sim（v2，含板级机读验证冻结）

本指南由规划者冻结本任务相关工程语义；只冻结相关项，其余引用原文件。`dev-plan.md` 的验收/预算优先。不新增角色、不替代实际工具报告。

## 1. 工作树、入口与基线

- 工作树：`upstream/ph1p100-pcie-ep-fpga`，分支 `codex/raw10-rka1`，基线 commit `ab811c8f820c3ae6601507b54ec45a74c6607855`（未推送）。**本轮不重建 bit**；P1/KIT 允许本地 commit（不推送），板级包只读仓。
- 候选 bit（上板）：`workflow/runs/20261018-0001_merge_raw_into_upstream/repo-build/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit`（`best_result/` 同 SHA）；下载前必须复核 SHA256=`e81d353b284cb4e99ec86bcd7d511691cda187254f801c4832916f0000692b9a`、5,224,023 B。
- 工具（实查，`20261017-011744-rk-fpga-align/env/environment-handbook.md`）：TD `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe`；硬件/BW 入口 `D:\anlogic\TD_Release_2026.2\bin\bw_commands_prompt.exe`；ModelSim `D:\intelFPGA\18.1\modelsim_ase\win32aloem`（vsim 10.5b）；Python `C:\Program Files\Python311\python.exe` 3.11.5；license `...\license\Anlogic.lic`。
- 仿真：`tools/pcie_integration/run_sim.ps1`（自动 subst；`-TbFiles` 相对基准=`sim/`）；**判定以 `vlog.log` Errors:0 + `vsim.log` ALL PASS 为准，退出码单独不可信**。单 TB ≤5 min、回归整组 ≤15 min。
- 构建：本轮不使用（G2 not_run）。如未来构建：`run_td.ps1 -Stage 00_all`、单会话、≤30 min、不下载不写 Flash。
- 编码/路径：项目路径含中文；脚本须显式 UTF-8（含非 ASCII 的 `.ps1` 必须 UTF-8 BOM；JSON/日志无 BOM UTF-8）；`subst` 只建自用、用后撤销、目标限于项目内；禁止把 OutDir 指向既有证据/候选。

## 2. 帧/数据口径（读回校验对象）

| 项 | 冻结值 | 来源 |
|---|---|---|
| 帧格式 | R10F：128B 帧头 + packed RAW10 载荷 + 尾填充；magic `0x46303152` | handoff §3 |
| 几何（占位） | 1920×1080；packed 载荷 2,592,000 B；DMA/发布长度 2,592,768（128 + 2,592,000 + 640 尾填充） | handoff §3、user-precheck §5 |
| 帧内布局 | 头 `[base, base+128)`；载荷 `[base+128, base+2,592,128)`；base 来自写者发布（128B 对齐） | `cam_r10f_writer.v` 注释 |
| CRC32 | poly `0xEDB88320`（反射），与 `gen_crc32_flat.py` 一致 | handoff §3 |
| `payload_crc32`(0x54) / `raw_crc32`(0x50) | 覆盖 packed 有效载荷 | `cam_r10f_writer.v` 注释 |
| `header_crc32`(0x58) | 0x58..0x5B 置 0 后覆盖 128B | 同上 |
| 几何/相位状态 | W/H/X0/Y0/SKIP_ROWS/BAYER_PHASE 均为**占位**；真实值由本轮/上板读数回填，不得当真实颜色证据 | board-env-checklist §4 |

复核规则：以 `cam_r10f_writer.v`/contract/artifacts 为准；实质不一致按 `INPUT_CONFLICT` 交原规划。

## 3. 读回校验模块接口（仅 P1 离线包；不集成）

- 模块 `rtl/ep_side/ddr/ddr_frame_readback_checker.v`（新增，不接入顶层）。单时钟域 `dhi_clk`（100 MHz）、AXI4 读主（256-bit/INCR，沿用 `ddr_frame_pusher.v` 风格）、控制 `{start, base[63:0], frame_bytes[31:0], abort}`、状态 `{busy, done, magic/hdr_crc/payload_crc/length ok, err_code, rd_header_crc32, rd_payload_crc32, words_read, ≥6 抽样字}`。
- 校验：读 128B 头 + packed 载荷；核对 magic、header_crc32、payload_crc32、长度；抽样为证据不自动判定；busy 重入拒绝；读超时阈值 ≥2× 最坏理论值（≈81 万拍 @32B/拍、100 MHz），具体值包内冻结并记录。
- 本包不集成、不构建；集成设计（AXI 读仲裁、状态寄存器分配）列入后续主题。

## 4. 工具包口径（KIT）

- 真值来源：contract `registers.json` + RTL 注释（`ep_bar_win.v`/`cam_r10f_writer.v`/`ddr_frame_pusher.v`）+ B1/B2 实测通道记录；每条期望规则附来源引用。
- dump 格式：以 B1/B2 **真实日志格式**为第一优先（保留原样行）；解析器同时接受冻结的 `offset value` 文本/JSON 形态；输入不合法 → 退出码 2（fail-closed）。
- 输出：解码表 + 逐项 PASS/FAIL + `run-record.json`（`run_id, timestamp, operator, channel, readings[], verdicts[], notes`）；退出码 0/1/2。
- 复用：`r10f_strict.py`、`gen_crc32_flat.py`、`gen_crc16_flat.py` 只读调用，不修改。
- 脚本不得写死绝对路径；输出 UTF-8/ASCII 明确；重跑同输入输出一致。

## 5. 板级机读验证（本轮新增，冻结）

### 5.1 通道（按优先级；B1 第 1 步有界探测）

1. **UART（首选）**：板卡经 FTDI VID0403/PID6042 双通道呈现串口（项目实况登记 COM3/COM4；`doc/uart_cmd_file_pcie.txt` 说明“双串口取高号口”）；**115200、8 数据位、奇校验(ODD)、1 停止位、hex 模式**；参考命令族：APB 读/写、CFGRD/CFGWR（EP 配置空间）、用户 MEMWR/MEMRD（EP BAR 空间，含 1..1024 DW 示例）；只读探测优先，命令回响应含 `41 42 43 44 45 46`/`46 45 44 43 42 41` 头与状态字节。
2. **BW/JTAG**：`bw_commands_prompt.exe` 只读链扫描/器件 ID（PH1P100SBG484）+ SRAM 下载（`-mode jtag` 等效）。
3. **RK PCIe**：本轮不可用（驱动未编译、KDIR 缺）→ 不尝试。
探测规则：每命令 ≤60 s 无响应即换候选；≥2 候选失败 → blocked（不盲试、不改接线）。

### 5.2 寄存器与期望（板级包最低读取集）

| offset | 名称 | 期望/解码 |
|---|---|---|
| 0x040 | MAGIC | `0x50434946`（"FICP"），否则停止 |
| 0x044 | CTRL | 位语义按 contract ctrl_bits（bit5 ddr_enable、bit6 push_enable 等）；只读快照 |
| 0x048 | IMG_STATUS | 状态位快照/解码 |
| 0x0A0..0x0AC / 0x0E0..0x0EC | 写者 A/B seq/base/status/len | seq 单调、base 双缓冲、**len=2,592,768**、status 无 err |
| 0x0C0..0x0C8 | PUSH_DONE/STATUS/ERR | 计数/错误码；本包不 ARM，记录保持值 |
| 0x0D0..0x0F4 | 相机诊断/丢弃 | 读数与解码（按 RTL 注释） |
| 0x114 | TX_STATUS | armed/busy/held/rejected/draining 位快照（只读） |
| 0x118 / 0x11C | EXT_MAGIC / VER | `0x31414B52`("RKA1") / 1.0；不匹配=配对风险，停止 |
| 0x120/0x124、0x128/0x12C | checked CSI A/B 诊断 | {good,bad,hdr_err,crc_err} 低 8 位 + {last_lines,last_wc}；几何/相位回填依据 |
| 0x080..0x098 | 原相机状态字 | lane_valid/cfg_done/in_frame/in_line/tap（只读） |
| 0x100 / 0x104 | 授权容量/会话 | 只读快照；活动期写入应被拒（如执行写测试，须按 contract 且最小化） |

### 5.3 板卡安全边界（硬性）

- 仅 SRAM；**绝不写 Flash**（出现 flash 字样命令即停止）。
- 复位只允许 JTAG 重下同 bit；物理断电/上电由用户执行（agent 不作电源/线缆操作）。
- 不改线缆/跳线/相机摆位/供电；单次下载 ≤5 min；连续采集 ≤10 min；不使用目视现象作判据。
- 下载前复核 bit SHA256 与 5,224,023 B；不匹配不得下载。
- 板卡按用户口径独占；发现他人占用迹象（读数跳变/链路异常活跃）→ 停止并记录。

### 5.4 证据要求（每个板级包）

- 操作者（角色 + 真实会话 ID + 宿主）、时间（上海时区，起止与关键步骤时刻）。
- bit/DB 身份（来源路径、SHA256、大小、manifest 引用）；未重建声明。
- 电源/连接/负载：记录“未拔插、未断电、未改线、未改负载”的事实与时间；若用户曾披露电源事件则登记。
- 原始命令与退出码、原始响应/日志（不删改）、寄存器读数原值 + 解析、时间序列采样。
- 回退与恢复：重下同 bit 的入口与结果；掉电即失说明；回退 bit 路径（旧候选/主线）只作参考不执行。
- 判据分级 `pass/fail/not_run/blocked/not_applicable`，不把“没测”写成通过；条件项（DDR 读回）不可达时记 `blocked` 并写原因。

### 5.5 失败即停（板级）

通道 ≥2 候选不可达；下载重试后失败；身份寄存器不匹配；读命令连续 3 次无响应；相机未接/无时钟；错误计数异常增长；任何需要改线/目视/写 Flash 的步骤。

## 6. 证据与 manifest 约定

- 每包证据目录：`workflow/runs/20261018-1347_runA_offline_sim/<pkg>/`（`board-selfcheck/`、`board-capture-readback/`、`bringup-kit/`、`ddr-readback-checker/`）：`dev-result.md`、`dev-notes/`、原始日志、`candidate-manifest.json`（0 不一致）、`lessons-learned.md`。
- 报告：`test-reports/<task_id>-r0-integrated.md`，首行唯一判定；含三维适用项、G 层（pass/not_run/not_applicable/fail + 理由）、绑定（manifest/命令/版本）。
- G 层：G0=输入/基线冻结；G1=离线仿真/工具 dry-run；G2=TD 构建；G3=板测（本轮仅机读部分）；G4=长稳/性能（本轮仅 10 min 短窗）。

## 7. 已冻结 / 待确认 / 不适用

- **已冻结**：工作树与基线、候选 bit 身份（§1）；帧/CRC 口径（§2）；P1 接口（§3）；KIT 格式（§4）；板级通道候选/寄存器表/安全边界/证据/失败即停（§5）；证据约定（§6）；写范围与 protected、预算（dev-plan §3/§6）。
- **待确认（由 B1 实测或用户在场解决）**：UART 端口与命令是否可用（B1 探测）；相机是否已接（机读判定）；物理断电执行者=用户；真实几何/相位数值；checker 集成与新候选重建。
- **不适用**：本轮不构建（无 G2）、不做 HDMI/图像目视、不做长稳（>10 min）、不做 RK 真机、不做 Run B、不写 Flash、不推送。

## 8. 本次综合测试的三维边界

- B1：functional=独立复测身份/关键只读读数并核验下载记录；engineering=命令/退出码/时间/操作者/bit SHA 链闭环；system=Flash 零痕迹、未改线/电源、无目视依赖、回退。G0 继承 + G3 部分。
- B2：functional=复测发布/计数/100 帧/10 min 数据；engineering=日志-命令-时间-哈希可复算；system=SRAM/无 Flash/失败即停执行/回退。G3；G4 短窗（达标才记）。
- KIT：functional=夹具正/负重跑 + 规则来源抽验 + 复算；engineering=可复现/编码/依赖/schema；system=写范围/无硬件副作用/回退。G0/G1。
- P1：functional=TB 重跑（含自建负例）+ 回归抽验；engineering=编译/规范/哈希/diff；system=protected/回退。G0/G1。
- 不得以“离线或机读 PASS”声称真实图像、HDMI、端到端 RK 收帧、长稳或完整 G3/G4 已通过。
