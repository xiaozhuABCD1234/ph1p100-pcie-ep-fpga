# fpga-design-guide.md — 20261018-1631_runA_fpga_side_readchannel

原规划者冻结（2026-10-18）。本文件=本任务数据/接口/参数/工作目录/构建入口与现有约束的冻结值；只冻结相关项，其余引用原文件。冲突时以本文件冻结值为准，未列项沿用既有工程约定。
背景技能：[fpga-design-guide/SKILL.md](../../../.agents/skills/fpga-design-guide/SKILL.md)；有界规则见 [work-limits.md](../../../.agents/skills/fpga-orchestrator/references/work-limits.md)。

## 1. 任务数据与读回字（冻结）

**唯一权威表**=`upstream/ph1p100-pcie-ep-fpga/tools/bringup/registers-plan.md`（R01—R17 规则 + `expected_rules.json`）。本任务**只读回、不新造**寄存器语义；下表按优先级冻结本轮必须读回的字（偏移=BAR0 dword 偏移）：

| 优先级 | 偏移 | 名称 | 期望/判据（规则 id） |
|---|---|---|---|
| A（必须） | 0x040 | MAGIC | =`0x50434946`（"FICP"，R01） |
| A | 0x118 | EXT_MAGIC | =`0x31414B52`（"RKA1"，R03；`0xDEADBEEF`=扩展缺失，停） |
| A | 0x11C | EXT_VERSION | =`0x00010000`（R04） |
| A | 0x0A0 | DDR_SEQ_A | 帧序号，单调不减；采集活时样本间应增长 |
| A | 0x0A4 | DDR_BASE_A | 首帧后非零、**128 B 对齐**（低 7 位=0，R07/R16） |
| A | 0x0AC | DDR_LEN_A | 成帧后 =**2,592,768**（R05） |
| A | 0x120 | CSI_DIAG_A | `{good[31:24], bad[23:16], hdr_err[15:8], crc_err[7:0]}`（原始值+解码，人工诊断项） |
| A | 0x124 | CSI_DIAG_A2 | `{last_lines[31:16], last_wc[15:0]}` |
| B（可延展） | 0x0A8 / 0x0E8 | DDR_STATUS_A/B | 位图见 R09/R10 |
| B | 0x080..0x098 | CAM_STAT_080..098 | 原始 dword 保留（位图未冻结，勿按猜测解码判故） |
| B | 0x0C0/0x0C4/0x0CC/0x0C8 | PUSH_DONE/STATUS/TLP_CNT/ERR | 规则 R11/R12/R15 |
| B | 0x0DC/0x0F0/0x0F4 | CAM_DROP_A/A2/A3 | 丢弃计数/判决位（R14） |

约束：
- 字段字节序=左高右低（0x120 的拼接顺序按 RTL 左侧为最高字节）；解码前先对 `ep_bar_win.v` header 复核（只读）。
- 偏移为 dword 偏移，不传字节地址。
- 不得以单次快照当原子采样；不同时刻/不同时钟域的读数分开记录（见 §6）。

## 2. 采样机制与调试核接口（冻结）

- **通道**：TD **ChipWatcher（CWC）** 调试核，经 JTAG 读回（这是本项目已证可行的唯一 FPGA 侧读通道；UART/PCIe 均不可用，不得复活）。
- **实例规划**：优先 **1 个 CWC 实例**、设在 `ep_bar_win` 所在时钟域（A 组 8 字≈256 bit，历史单实例位宽 449 可容）。若工具位宽/容量限制，允许**同域**第二实例，或经“调试字库”扫描；二选一须在 P0 冻结、P1 实现，并在 candidate diff 记录。
- **调试字库契约（如采用）**：固定字序/偏移（与 §1 A 组一一对应）、**只读镜像**、同域采样、**无副作用**（不驱动任何控制/总线/外发路径）；P1 必须用 TB 证明镜像值=寄存器原值（含边界帧）。
- **探针层级名**：P0 冻结每个读回字↔探针路径的对应表（写 `debug-spec/probe-map.md`）；名字必须与 RTL 层次一致（P1 实现时以 elaboration/仿真复核；名字不确定时改用字库镜像名）。
- **CWC 产物**：必须经 TD `setup_debugger -prj <prj>` 生成 `cw/compiled.cwc`（**不得**只跑 `export_chipwatcher`——历史缺物理 ERAM 映射→空白波形）；生成后跑 `tools/td/check_chipwatcher_readback.py`（CWC↔BID 映射校验）**0 失败**；注意该校验器仅支持单段/全深几何，多段需另证或改单段。
- **bit 与 CWC 配对**：下载用的 `compiled.bit`（或 `best_result` bit）与 `compiled.cwc` 必须同一构建来源；如两者 SHA 不同，两者都记录并说明（历史例中曾逐字节相同）。

## 3. 默认使能/采集状态（冻结策略）

- P0 从 RTL 冻结 `CTRL(0x44)` 复位默认（enable/trigger/reinit/test_pattern/ddr_enable/push_enable/push_source/camera_ab）并写 `debug-spec/enable-state.md`。
- 若默认**未开**采集/写存 → 调试版允许**最小 debug-only 默认开启**（只动采集/DDR 使能域；**禁止** TX arm、push/doorbell、任何面向主机外发的开启），全部写入 candidate diff + guide 备注；生产与旧候选不受影响。
- 若默认已开 → 不得再改默认值；读数按 §1 判据即可。

## 4. 构建、工作目录与入口（冻结）

- 工作树：`upstream/ph1p100-pcie-ep-fpga`（分支 `codex/raw10-rka1`）；**本 run 唯一 RTL 写树**；产出本地 commit（**不推送**）。
- 构建入口（沿用、可复跑）：`tools/pcie_integration/run_td.ps1 -Stage 00_all -OutDir <out>`；debug 构建新增独立 stage/入口而**不得改动 `00_all` 默认行为**（保证旧 bit `e81d353b…` 仍可复现）。
- 单会话硬超时 wrapper ≤30 min（`WaitForExit(1800000)` + `taskkill /PID ... /T /F`）；**单次会话 ≤30 min、最多 2 次**（用户冻结）。
- 产物位置：`<out>/…/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit`（+ `place.db/pr.db`、`final_timing.rpt/*.area`）；debug 位流与旧位流**并列保存、不覆盖**。
- 复跑判定：`td_00_all.log` 含 `PRJ-1406 Run phy_1 finished` + `PRJ-1424 saved as best result` + `T07_ALL_DONE`；`commands.log` 含 `stage=… exit=0`；`final_timing.rpt Confidence=Routed`。USR-8001（未 import netlist 的 report_area/timing skip）沿用既有说明，判定用 phy_1 目录内 TD 自产报告。
- 仿真入口：`run_sim.ps1 -Tb <tb> -OutDir <dir> -TbFiles tb/<file>.v`；`MSIM_BIN=D:\intelFPGA\18.1\modelsim_ase\win32aloem`；既有回归统一 `-Defines MIPI_PHY_SIM_STUB`；新增 TB 同口径。

## 5. 板级通道约定（冻结，沿用 B1 已证）

- 下载：`hwserver.exe -r -s 5555 -f 12 -v -w 5556 -i 0` →`connect_cable -host_name 127.0.0.1:5555 -open`→`read_device_id`（=PH1P100）→`download -bit <bit> -mode jtag -spd 7 -cable 0`（**仅 SRAM**）。
- **bit 路径必须 ASCII/英文**（中文路径→PRG-8000）；脚本经相对路径调用、参数经环境变量传入（B1 踩坑）。
- 成功判据：`PRG-2014 : Chip validation success: PH1P100` + 进度 100% + rc=0 + 28–40 s；旁路 `usb_open() failed` 提示不单独判败。
- 读回：TD ChipWatcher 打开 `compiled.cwc`→Watch→Add Signals→Instant Trigger→记录 Value 原文（历史 2026-10-13/14 文档流程）；每次读回 ≥2 个样本、间隔 ≥10 s；Idle/Triggered=0 且无波形时保留界面原文、不判硬件故障。
- 禁止命令面：`program_spi/erase_spi/program_efuse/read_flash/program_svf/*flash*` 等；会话命令审计须零命中。
- DDR 校准异常 SOP：黑屏四灯齐报、**D37 灭** → **用户物理断电 10 s** → 上电 → 重下同 bit（≤5 min/次）；不自行改线/电源。

## 6. 证据记录约定（冻结）

- 记录载体：复用 `tools/bringup/run_record.schema.json`（如扩展须在 run 内声明并保留兼容字段）；读数**原文**（十六进制/十进制原样）+ 时间戳 + 操作者 + 工具版本 + bit SHA256 + BID/CWC 文件名与 SHA。
- 每条读数绑定：通道（bw/CWC 实例名）、命令与退出码、输入哈希；目视现象不得单独作判据。
- CWC 样本非原子：同一实例内信号视为同时；跨实例/跨时刻分开记录，禁止合并成一次“原子快照”。
- 板测记录必须含：操作者、时间（含时区）、bit/DB 身份、命令与退出码、读数原文、恢复/回退记录。
- 离线包证据：命令+退出码+日志路径+manifest SHA256；diff 与允许清单一致。

## 7. 新旧位流并列规则（冻结）

- 新 debug 位流=**新候选**（新 manifest/SHA/candidate diff），与旧 `e81d353b…2b9a`（配对 `ab811c8f`）**并列**；不得混拼、不得以旧证据充新候选（反之亦然）。
- 旧候选仅作**来源/回退**：回退动作=重下 `e81d353b…`（SRAM，≈30–40 s；旧 bit 文件保留不动）。
- SRAM 易失：板上位流不构成持久变更；**全程不写 Flash**。

## 8. 已冻结 / 待确认 / 不适用（本轮）

- **已冻结**：§1 读回字与判据；§2 CWC 机制与产物要求；§3 使能策略；§4 构建入口/时限/产物；§5 板级通道与安全；§6 证据；§7 并列/回退。
- **待确认（由 P0 冻结，不阻塞计划）**：CWC 实例数与位宽落点；探针层级名逐字表；是否采用字库扫描；CTRL 复位默认与是否需 debug-only 默认开启；CWC GUI 是否有可脚本化读回（默认按人工操作准备）。
- **不适用（本轮）**：UART 命令面（架构不可用）；PCIe/BAR0 主机读（用户已排除）；JTAG_REG_ACCESS 盲试（无只读语义，禁止）；Flash/持久化（禁止）；长稳 G4（范围外）。
- **综合测试三维边界**：functional=回归/TB/判据一致性与读数解码复核；engineering=构建/时限/STA/资源/CWC 映射/manifest/diff/路径规则；system=写范围/protected/命令审计（无 flash）/回退链/证据绑定（板包含操作者与恢复记录）。不适用项须在报告写明理由。
