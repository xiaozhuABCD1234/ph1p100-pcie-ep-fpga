# dev-plan.md — 20261018-1347_runA_offline_sim（v3，B1 blocked 处置后更新）

原规划者编写。本轮=Run A 的“离线模拟 + 可机读板级验证”切片（3 小时窗、用户不在场）。**v3 更新**：B1 已执行并**按 blocked 接受**（下载链路+器件 ID 已证；用户寄存器读通道缺失）；B2 因同一读通道缺失改 **awaiting_conditions** 不派发；本轮剩余按 **KIT → P1** 推进（均离线）。不写 Flash、不推送、不改 RK 仓、不重建 bit、不改线/电源。

## 1. 本轮目标与边界

- **主要可验收目标（1 个）**：完成 Run A 的“可机读验证切片”——板级：**下载链路 + 器件 ID 已证**（G3 partial），寄存器级验证因读通道缺失 blocked；离线：KIT 工具包 + P1 读回校验 RTL/TB（在其后按序推进）。
- **顺序与裁剪（r1）**：B1（已 blocked 接受）→ **KIT（ready）→ P1（blocked-by-order）**；B2 不派发。若时间仍不足从尾部裁 P1；被裁/阻塞包由原规划收尾如实登记，不自动续做、不降低门槛赶工。
- **安全边界（全程）**：仅 SRAM、绝不写 Flash；物理断电/上电由用户执行；不改线缆/跳线/相机摆位/电源；单次下载 ≤5 min；不使用目视现象作判据。
- **非目标**：集成/重建新 bit；RK 真机；HDMI/图像目视；长稳（>10 min）；Run B；任何写 Flash。

## 2. 工作包总表

| 顺序 | task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional 验收 | engineering 验收 | system 验收 | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | T11.runA-board-selfcheck | 板级机读自检：下载链路+器件 ID 已证；身份/基线寄存器读 blocked | 只写 run `board-selfcheck/**`（已完成）；**未改上游仓** | 无 | 下载成功+器件 ID pass；身份/基线=blocked（读通道缺失） | 命令/退出码/时间/bit SHA 链闭环（已取证） | SRAM-only 无 Flash、未改线/电源（已证） | G0 继承；G3 partial | **blocked（已接受，见 §10）** | 无（下一步见 §9） |
| 2 | T11.runA-board-capture-readback | 采集统计与读回（不再可行于此路径） | 无（不派发） | B1 读通道（缺失） | not_run | not_run | not_run | G3/G4 not_run | **awaiting_conditions（留用户在场轮）** | 不派发（§7/§9） |
| 3 | T11.runA-bringup-kit | 工具包：寄存器计划 + dump 解析/判定 + CRC 复算 + 夹具 + 记录 schema + runbook（含读通道恢复选项与 JTAG 语义文档初核） | 上游仓新建 `tools/bringup/**` + 本地 commit（不推送）；run `bringup-kit/**` | B1 证据（真实日志/命令格式，只读输入）+ 合成素材（B2 无采集 dump） | 正夹具通过、≥3 负夹具 fail-closed、期望规则 ≥8 条与来源一致、合成件复算一致 | 可复现/编码稳健/依赖声明/无绝对路径/记录 schema | 写范围仅 `tools/bringup/**`；本包不触硬件；回退=反转 commit | G0/G1 | **PASS（r0；报告 test-reports/T11.runA-bringup-kit-r0-integrated.md）** | 无 |
| 4 | T11.runA-readback-checker | 离线模拟：板内 DDR 读回校验核心 RTL + TB（不集成、不构建） | 上游仓新建 `rtl/ep_side/ddr/ddr_frame_readback_checker.v`、`sim/tb/tb_ddr_frame_readback_checker.v`（+允许的追加行）+ 本地 commit；run `ddr-readback-checker/**` | 无 | 新 TB ALL PASS（正例+≥4 负例 fail-closed）+ 既有 8 TB 回归 PASS | 编译干净/端口命名合规/diff 仅允许清单/manifest 0 不一致 | protected 逐字节相等；回退=反转 commit；bit 配对不受影响 | G0/G1（G2 not_applicable） | **补收派发中**（产品已写、TB 自验 ALL PASS；8 TB 回归/commit/manifest 未完成——开发会话 shell Permission denied；未达 ready_for_test、不冒充 PASS） | spawn_agent（补收，同一 task_id）→ fpga-dev |

## 3. 详细工作包

### 3.1 T11.runA-board-selfcheck（r0 已执行 — blocked 接受）

- **结果**：pass=bit SHA 复核（=e81d353b…2b9a）、BW 器件 ID=PH1P100、SRAM 下载成功（PRG-2014，rc=0，29.52 s，仅 `connect_cable/read_device_id/download -mode jtag/connect_cable -close`；无任何 flash/efuse/spi 命令）、未改线/电源；blocked=0x40/0x118/0x11C 与基线寄存器读（无可用机读读通道）。
- **关键发现**：UART 命令通道架构不可用（EP top `uart rx=1'b1`，`rtl/ep_side/ph1p_pcie_ep_top.v` L155/L757；COM8 两次只读探测 0 字节）；COM8 为 FTDI MI_01（VCP），COM3/COM4 实为蓝牙口（更正 input-index 旧登记）；BW 要求 bit 路径 ASCII、脚本相对路径+环境变量传参。
- **证据**：`board-selfcheck/{dev-result.md, channel-notes.md, candidate-manifest.json, logs/, scratch/, lessons-learned.md}`。
- **过程登记**：工具调用 41 次（>冻结 ≤30，如实登记：本机环境发现+1 次有证据参数纠正重试；未扩范围）；耗时 ≈11 min（≤35）。blocked 不经 ready_for_test → **不新建该包综合测试者**。
- **判定接受理由**：阻断为硬缺条件（无读通道），证据充分且无产品缺陷可修；不盲试写操作、不扩权正确执行。

### 3.2 T11.runA-board-capture-readback — awaiting_conditions（不派发）

- 依赖 B1 同一读通道（寄存器/内存读）与相机在场确认；当前均缺失。**不得用任何无证据方式冒充**。
- 内容原样保留给用户在场轮（或其恢复读通道后的增量轮）：采集使能确认、0x120..0x12C 统计、发布确认（seq/len=2,592,768）、100 帧+10 min 短稳、条件读回。
- 对应 §7 主题 2 与 `question-01.md`。

### 3.3 T11.runA-bringup-kit（工具包，开发者，新）

**主要可观察结果**：`tools/bringup/` 工具包（寄存器计划 + dump 解析/判定器 + CRC/长度复算 + 夹具 + 记录 schema + runbook），在 B1 真实日志与合成素材上 dry-run 通过、负例 fail-closed。

- **工作树/允许写范围**：上游仓新建 `tools/bringup/**`；本地 commit（不推送）；run 目录 `bringup-kit/**`；`tools/pcie_integration/**`、contract、artifacts、B1 证据 **只读复用**。
- **protected**：上游仓既有全部、`repo-merge/`/`repo-build/`/`rk-package/`、上一 run、B1 证据、`workflow/tasks.json`。
- **语义步骤（5 项上限）**：
  1. **寄存器读取计划**：按 contract + RTL 冻结全表（0x40/0x44/0x48/0x114/0x118/0x11C/0x100/0x104/0xA0..0xAC/0xE0..0xEC/0xC0..0xCC/0xD0..0xF4/0x120..0x12C），每行期望/解码规则/来源引用；标注“读通道未成立，待 §9 恢复后使用”。
  2. **dump 解析/判定器**：消费 B1 真实日志/命令格式（B2 未执行，无采集 dump）+ 合成格式；输出解码表 + PASS/FAIL + `run-record.json`（schema 冻结）；退出码 0/1/2（fail-closed）。
  3. **CRC/长度复算**：复用 `r10f_strict.py`/`gen_crc32_flat.py` 对合成件离线复算，命令与期望输出写入 README。
  4. **夹具与 dry-run**：≥1 正（B1 真实日志只读副本 + 合成件）≥3 负夹具；`dryrun.log`；负例必须拒收。
  5. **冻结与归档 + 读通道恢复选项 + JTAG 语义文档初核（有界，离线）**：manifest/SHA256、`dev-result.md`、`lessons-learned.md`；runbook 更新（目视/物理项标“用户在场”，并入 §9 四条恢复选项）；对 BW `JTAG_REG_ACCESS`/`JTAG_AXIS_APB_ACCESS` 仅做**文档/命令表级**初核（≤10 次工具调用，**不得调用 bw/硬件、不得盲试**；文档缺失或语义含写/需调试核 → 记“不可用”；若明确存在“无需调试核的只读用户寄存器路径” → 作为证据返回原规划，由其决定是否派一次有界只读补充）。
- **综合测试三维对象**：functional=正/负夹具独立重跑 + ≥8 条期望规则来源抽验 + 合成件复算复跑；engineering=可复现/编码稳健（UTF-8 BOM 规则）/依赖声明/记录 schema/无绝对路径；system=写范围仅 `tools/bringup/**`、本包不触硬件、回退可行。
- **必要 G 层**：G0/G1；G2 not_applicable；G3 not_run（不新增硬件动作）。
- **工具与安全超时**：Python 3.11.5 + PowerShell；单命令 ≤60 s；不访问网络/硬件。
- **失败即停/回退**：缺输入 → blocked；回退=反转 commit 或丢弃 `tools/bringup/`。
- **预算（冻结）**：开发 ≤15 min / ≤25 次工具调用。

### 3.4 T11.runA-readback-checker（离线 RTL+TB，尾部可裁）

- **工作树/允许写范围**：新建 `rtl/ep_side/ddr/ddr_frame_readback_checker.v`、`sim/tb/tb_ddr_frame_readback_checker.v`；可**追加**条目至 `sim/compile_checked.f` / `tools/pcie_integration/run_sim.ps1`（记录追加行）；本地 commit（不推送）；run `ddr-readback-checker/**`。
- **protected**：既有 `rtl/**`、`constraints/**`、`sim/tb/*` 既有文件、`docs/protocol/**`、既有 `tools/**`、全部既有证据。
- **语义步骤（5 项上限）**：1) 口径核对+模块实现（单时钟 dhi_clk、AXI4 读主、控制 {start,base,frame_bytes,abort}、状态 {busy,done,逐项 ok,err_code,rd_crc,words_read,≥6 抽样字}）；2) 校验逻辑（magic、header_crc32、payload_crc32、长度、抽样、读超时 ≥2× 最坏理论值）；3) TB（AXI 读内存模型+独立参考 CRC；正例小尺寸+1080p 全帧；≥4 负例）；4) 新 TB + 既有 8 TB 回归（判定以 vsim.log）；5) commit/manifest/dev-result/lessons。
- **综合测试三维对象**：functional=独立重跑 TB（含测试者自建负例）+ 抽验既有 TB；engineering=编译/清单/端口规范/哈希/diff（含追加行审计）；system=protected 比对/回退/写范围。
- **必要 G 层**：G0/G1；G2 not_applicable；G3/G4 not_run。
- **工具与安全超时**：ModelSim 入口 `run_sim.ps1`；单 TB ≤5 min、回归 ≤15 min；不用 TD。
- **预算（冻结）**：开发 ≤25 min / ≤30 次工具调用；窗口不足则登记“未开始/下一轮入口”。

## 4. 综合测试者安排（独立于全部开发者）

- 本轮**一个**综合测试者；**r1 覆盖范围：KIT、P1**（B1 为 blocked 接受，不经 ready_for_test，**不新建**该包综合测试者、不出 integrated 报告；B2 不派发）。
- 逐任务每轮一份报告：`test-reports/<task_id>-r0-integrated.md`（首行唯一判定标题）；三维=同一测试者检查清单；写 G 层（pass/not_run/not_applicable/fail + 理由）与绑定（manifest/命令/版本）。
- 离线包：独立重跑脚本/TB 与负例；抽验来源一致性、哈希、BOM/编码；不要求硬件。
- 失败：同任务续**原**开发/原综合测试（round1—3，最多三轮实际修复）；受影响项必须复测。
- 预算（冻结）：KIT ≤7 min、P1 ≤8 min；≤25 次工具调用/包。

## 5. 统一阈值

| 门槛 | 值 |
|---|---|
| 板级（B1 已证部分） | bit SHA=e81d353b…；器件 ID=PH1P100；SRAM 下载 rc=0；Flash 零痕迹（命令审计） |
| 读通道（当前） | blocked（UART 架构不可用、无 PCIe 主机、无 CWC、JTAG 语义未证）→ 由 §9 选项恢复 |
| TB/回归（P1） | 新 TB ALL PASS；负例 fail-closed；既有 8/8 PASS（判定以 vsim.log） |
| CRC 交叉核对（KIT） | `gen_crc32_flat.py` 对合成 `.dma` 与 `check-1080p.json` 一致 |
| 工具包（KIT） | 正夹具通过、≥3 负夹具拒收；重跑同输入输出一致；期望规则 ≥8 条来源一致；退出码 0/1/2 |
| protected/diff | 除允许清单与记录在案的追加行外逐字节相等 |
| manifest | 0 不一致；新文件/日志可复算 SHA256 |

## 6. 预算、停止与回退

- **总窗口**：3 小时（含已用）。剩余按 KIT ≤15+7、P1 ≤25+8 推进；不足从尾部裁 P1。**板级任务预算复核**：B1 实况 41 calls（>30）登记为过程观察；同类“本机环境发现型”板级探测在下一轮可预冻结 ≤45 calls（理由：中文路径/argv/USB 通道枚举不确定性），本轮不追溯扩权。
- **安全边界（板级，沿用）**：仅 SRAM；绝不写 Flash；复位仅 JTAG 重下同 bit（物理断电由用户）；不改线/电源/相机；≤10 min 连续；无目视判据。
- **默认时限**：读/搜 60 s；单 TB ≤5 min；回归 ≤15 min；不用 TD。
- **停止**：缺工具/资料/授权 → blocked；连续 2 循环无新证据 → NO_PROGRESS；预算耗尽 → LIMIT_REACHED；外部错误不自动重试、不扩权。
- **回退**：板级=重下同 bit/掉电即失；离线=反转 commit/丢弃新文件；旧证据全程只读。

## 7. 后续主题（≤3，不自动续做）

1. **读通道恢复 + 寄存器级板验证（用户在场轮）**：§9 四选一（PCIe 主机 / CWC 版 bit / JTAG 只读语义确认 / bring-up bit）；恢复后补齐 B1 的寄存器部分 + B2 全部（采集统计、发布确认、100 帧+10 min 短稳、条件读回）。
2. **checker 集成 + 新候选重建**：AXI 读仲裁、回读状态寄存器、集成后重跑 G1/G2 重建并列新候选；用于板内 DDR 读回自证（读通道不恢复时的替代路径）。
3. **Run B**：三算法接入生产主工程 + 板级验证（依赖真实几何/相位与板级链路）。

## 8. 任务状态与收尾口径

- 本 run 的“done”仅指交付包；T11/T07 不置 done；`workflow/tasks.json` 由原规划按判定更新。
- 收尾：`handoff.md`、`final-summary.md`、`user-summary.md`（规划）；`lessons-learned.md`（开发，各包目录）。
- 统计：B1=blocked 接受（G3 partial）；B2=awaiting_conditions；KIT/P1 按判定；G2 not_run、G3 partial、G4 not_run。

## 9. 读通道恢复选项（用户回来决策；配合 question-01.md）

**(a)** 用户在场提供 PCIe 主机（RK 或 PC）读 BAR0 寄存器（RK 尚缺 KDIR/交叉工具链）；
**(b)** 授权构建带 CWC/调试核的新候选 bit（bit 更替 → 需重新冻结候选与 G1/G2）；
**(c)** 确认 BW `JTAG_REG_ACCESS`/`JTAG_AXIS_APB_ACCESS` 的**只读**语义（KIT 已完成文档级初核：仓库/TD 文本文档均无参数与读写语义、候选无 CWC/调试核 → 记**不可用**、无补充建议；此选项保留给用户/原厂书面确认）；
**(d)** 授权 bring-up bit（rdx 引出/回环，需改线，agent 不做物理操作）。
另需现场确认：相机是否已接（单 A）——机读不可达，仅用户可答。

## 10. 执行记录（规划维护）

- **r0 B1（T11.runA-board-selfcheck）— blocked（已接受）**：pass=bit SHA 复核、BW 器件 ID=PH1P100、SRAM 下载成功（rc=0，29.52 s，无任何 flash/efuse/spi 命令）、未改线/电源；blocked=身份/基线寄存器读（无读通道）。证据 `board-selfcheck/`：dev-result.md、channel-notes.md、candidate-manifest.json、logs/、scratch/。不新建综合测试者。**预算超用登记：41 次工具调用（冻结 ≤30），耗时 ≈11 min（≤35）**；未扩范围、未做计划外硬件动作。
- **r0 B2 — awaiting_conditions**：不派发；原因=读通道缺失（同 B1）。
- **r0 KIT（T11.runA-bringup-kit）— PASS（round0 首次验收）**：integrated 报告 `test-reports/T11.runA-bringup-kit-r0-integrated.md`（首行 PASS；functional/engineering/system 全 pass；G0/G1 pass、G2 not_applicable、G3/G4 not_run、硬件层 not_applicable）；manifest `bringup-kit/candidate-manifest.json` SHA256 `7e0ae0a0…268e3`；上游本地 commit `48be9f20`（`tools/bringup/` 14 文件，未推送，parent=ab811c8f）；无 blocked、无 retest。**预算恰用尽登记：25/25 次工具调用、约 15/15 min**（含 1 次自身命令拼装错误后的有证据重跑；未扩范围）。**JTAG 文档级初核结论（登记）**：仓库与 TD 文本文档均无 `JTAG_REG_ACCESS/JTAG_REG_ACCESS_VEC/JTAG_AXIS_APB_ACCESS` 的参数与读写语义，且候选无 CWC/调试核 → 记“不可用”；**未发现“无需调试核的只读用户寄存器路径”文档证据**，无补充建议；选项 (c) 保留给用户/原厂确认。
- **r0 P1（T11.runA-readback-checker）— blocked/partial（补收派发中）**：产品已写（`ddr_frame_readback_checker.v` + `tb_ddr_frame_readback_checker.v` + `sim/compile_checked.f` 追加 1 行）；新 TB 自验 vsim.log `*** ALL PASS ***`（正例含 1080p 全帧；负例 N1—N5/T8/T9/T0 全命中；busy 重入拒绝）。未完成=8 TB 回归重跑、本地 commit、candidate.diff、candidate-manifest.json 冻结。原因：该开发会话 shell 连续 3 次 `Permission denied`（含最简 git 形态；同期 KIT/测试者会话命令正常 → 判为**会话级可恢复**，非环境性缺权限）。problem 登记：`T11.runA-readback-checker:PERMISSION_MISSING:shell`（reason_code=PERMISSION_MISSING、new_information=true、evidence=`ddr-readback-checker/dev-notes.md`；预算 ~30 calls 达上限，未扩权未绕过）。**处置：派发一次有界补收（同一 task_id、新开发会话，仅“回归+commit+diff+manifest 冻结”，≤15 min/≤20 calls；再次权限拒绝即停止并 blocked 接受；不得绕过权限）**；判定后回原规划，再按计划新建 P1 综合测试者出 r0 integrated 报告（判定以 vsim.log）。另登记：`compile_checked.f` 曾现 OneDrive 同步竞争（写后短时不可见），补收前须以同一绝对路径复核文件状态；本包只新增 2 文件 + 追加 1 行，共享清单全量编译 Errors: 0。
- **重要发现（写入 handoff/上板前置）**：①UART 命令通道架构不可用（EP top rx 固定 1；COM8 实测 0 字节；`doc/uart_cmd_file_pcie.txt` 命令面对本 bit 不可用）；②FTDI 复合设备 MI_00=WinUSB(JTAG)/MI_01=VCP=COM8，COM3/4=蓝牙口（更正旧登记）；③bw 约束：bit 路径须 ASCII、脚本相对路径+环境变量传参；④板上当前 SRAM= e81d353b…2b9a（易失）。

## 11. 收盘时 handoff/final-summary 预写要点

- 交付物与哈希（board-selfcheck 证据包、tools/bringup、ddr-readback-checker）；G 层分账（G3 partial／G2 not_run／G4 not_run）与四类清单（已证/条件项/blocked/未开始）。
- 必须登记：**UART 架构限制与 COM 口更正**、**B1 预算超用（41 calls）**、B1=blocked 接受、B2=awaiting_conditions、KIT/P1 判定；bit 配对（e81d353b ↔ ab811c8f，未重建）。
- 恢复与回退入口（重下同 bit；掉电即失；`scratch/sram_download_runa.tcl` 可复用但 bit 须 ASCII 路径）；读通道四选一与相机确认（question-01.md）；下一轮用户输入格式。
