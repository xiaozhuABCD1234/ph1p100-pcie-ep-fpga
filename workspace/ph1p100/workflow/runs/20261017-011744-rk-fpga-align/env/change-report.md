# T11.rk-align-base — 变更报告（round0 + round1/round2 修复）

范围：`tools/env/`（新增）与本 run `env/`（新增）。**未修改**任何生产 RTL、`tools/pcie_integration/`、`raw/`、`backend/`、其它 run 或全局配置。与在途 `T11.rk-align-raw` r0 functional 的冲突规则（冻结输入只读）全程遵守；round1/round2 修复仅动本包文档/记录（见 §R1/§R2）。

## 0. 一句话

把本机 FPGA 环境从"事实散落"变成**可复跑自检 + 可交接文档**（环境清单/自检脚本/手册/板测清单），并对集成树做**只读**逻辑冗余/优化勘察（12 条：9 安全快速 + 3 结构/评估），所有条目带 `file:line` 证据与验证方式；生产输入 SHA 与冻结 manifest 逐条一致，证明未触碰冻结输入。

## 1. A. 环境配置合理化与固化（交付物）

| 交付物 | 路径 | 内容要点 |
|---|---|---|
| 环境自检脚本 | `tools/env/env_check.ps1`（UTF-8 BOM；`72C85986…`） | 无副作用（只写 `-LogDir`，默认 run `env/logs/`）；检查工具存在性/版本/SHA、TD CLI 只读探针（`-TdProbe`，临时 subst 自动撤销）、入口脚本 BOM、subst 只报告、输出目录可达、D 盘只读约定、git 状态、清单一致性、脚本自身编码哨兵；输出人类日志 + 机器 JSON，显式 exit 0/1（判据仍以产物 verdict 为准） |
| 环境清单 | `env/environment-inventory.json` | 逐项事实 + 获取命令 + 原始输出摘要/SHA：TD 入口/版本/命令注册/license、ModelSim、Python/GCC/Git/tclsh、PS5.1+ACP936、git HEAD/dirty、subst 现状、临时参考库、路径/编码规则、D 盘只读约定、仿真/TD 入口、产物与完成标记判据、已知坑 |
| 环境手册 | `env/environment-handbook.md` | 干净 shell 可复制步骤：仿真入口、TD 单会话 `00_all` 规则（分阶段丢 `device_name` 的教训）、subst 规则、编码/BOM 规则、产物与完成标记判定（PRJ-1406/1424、`T07_ALL_DONE`、`vlog Errors: 0`、`run.do`/`vsim.log` 齐备）、失败留痕、回退（002820 / T07 r3 / T11 r0 bit）、禁止项 |
| 板测环境清单 | `env/board-env-checklist.md` | 上板前确认/采集：JTAG/BW 只读入口与器件识别方法、独占窗口、SRAM 加载与恢复、UART/寄存器观测点、RK 侧需提供事实（BDF/内核/PAGE_SIZE/MPS/IOMMU）、帧内容核对、反例与记录模板；**本包不操作硬件** |
| 勘察快照 | `env/input-snapshot.json` | 36 个被读文件 SHA/mtime；生产输入 17 条与 `raw/candidate-manifest.json` 逐条一致；两个 manifest 实算 SHA 与登记值一致 |
| 只读勘察报告 | `env/optimization-survey.md` | 见 §2 |

### 1.1 自检实测（G1 证据）

- 最终运行：`powershell -ExecutionPolicy Bypass -File tools/env/env_check.ps1 -TdProbe`
  → **verdict = PASS（PASS=12 / FAIL=0 / WARN=0）**，exit 0；
  日志：`env/logs/env_check_20261017-151126.json` / `.log`；TD 探针 stdout：`env/logs/td_probe_stdout.log`。
- TD 探针实查：`TD Release_2026.2 / Build 6.2.3.210850 / Tcl 8.6.17`，11 项命令 REGISTERED，`READ_ONLY_CLI_PROBE_OK`，exit 0（临时 subst 已在 `finally` 撤销）。
- ModelSim 实查：`vsim/vlog 10.5b ALTERA STARTER EDITION`，exit 0。
- 编译器实查：Python 3.11.5 / GCC 13.2.0 / Git 2.54.0 / tclsh 8.6.12。
- 入口脚本 BOM：`run_sim.ps1`/`run_td.ps1`/`env_check.ps1` 三者 BOM=True（SHA 见清单）。
- 脚本自身编码哨兵：`SelfCheck=6/6`（防 PS5.1+ACP936 吞行）。
- 中间修正（失败留痕，日志保留未删）：首轮 `-Command`/`-Summary` 字符串拼接少了括号导致字段截断；git 输出按 GBK 解码中文乱码 → 加 `-Utf8` 捕获后复跑；三份历史运行日志与 TD 自身 `td_*.log` 均保留在 `env/logs/`。

## 2. B. 逻辑冗余/优化只读勘察（交付物与要点）

- 报告：`env/optimization-survey.md`（格式 `ID｜位置(file:line)｜现象｜类别｜估计收益｜风险｜验证方式｜优先级`）。
- 条目：**安全快速 9 条**（S1-1..S1-9）+ **结构/评估 3 条**（T1/T2/T3，T1 含 T1a/T1b 两种手法）+ **不建议 3 条**（N1..N3）。
- 已知项全部实读核对现状（未照抄旧结论）：`csi_rx_packet_integrity.v` END_PACKET 死分支与"新状态 END_PEND"陈旧注释仍在；`raw/g2/README.md:28` clk1 笔误仍在（clk1 时钟摘要实测 +1.141；+5.058 实为 Path Group `tl_clk_user→tl_clk_user` SWNS 的跨节误引，round1 已修正证据表述，见 §R1）；`backend/g2/README.md:153` 旧 manifest 绑定句仍在（当前 r3 = `68F9F4D0…4275`）；`backend/g1/crc16_upd4.generated.v` README 已标、文件头可加；字节域余量薄（+0.115 ns、67% 布线）仍在。
- 新增核对：生产 `crc16_upd4.v`/`crc32_upd4.v` 均可由冻结生成器**逐字节复现**（`env/verify/gen_selfcheck.txt`：4×20030 / 4×20040 例 0 失配；SHA 与生产一致）；未实例化模块 6 个（工程清单仍 add_files，elaboration 丢弃）；`ltssm_debug[8]` 只写不可读为 peer 原样继承。
- 结构靶点：T11 最差路径 `u_gear_box/O_word_out_reg[3] → u_cam_r10f_writer/f_mem_syn_65.csa[2]`（4.503 ns、net 67%、`f_wr` 扇出 24），给出两种不改前提的重构手法（FIFO 写口流水 / 打包搬慢域）及差分+全量 G1+G2 验证要求。

## 3. 没做什么（边界）

- 未修改任何生产 RTL/约束/IP/脚本；未运行 TD 构建、round0 未运行 ModelSim TB（仅 `-version` 查询；round1 的 1 次写者 TB 见 §R1）、未下载/写 Flash/操作硬件；未安装或改动任何工具/全局配置；未创建或删除 subst 映射（`-TdProbe`/`run_sim` 的临时映射在 finally 撤销；机器上既有的 `R:` 遗留映射原样未动）。
- 未删除任何文件；`env/logs/` 中首轮/次轮日志与 TD 自身日志全部保留。
- 未触碰 `fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`raw/`、`backend/`（`env/input-snapshot.json` 的 17 条生产输入 SHA 与冻结清单逐条一致；两个 manifest 实算 SHA 与登记值一致）。
- 未代写任务板/交接/用户总结（归原规划者）；未向外发消息。

## 4. 未测边界与已知限制（如实）

- `env_check.ps1` 的 SHA 核对以"与清单记录一致"为判据；工具升级/换机后需重跑并更新清单（首次运行清单不存在时为 WARN，属正常）。
- TD 探针只验证命令注册与版本横幅，不验证构建；verilator 在本机不可用（记录在清单，不影响本线）。
- 勘察报告中的收益均为量级判断，非实测；T1/T2 实施与验证属 `T11.rk-align-opt`。
- 板测清单未做任何实机确认（无 JTAG 扫描、无串口打开）；`board-env-checklist.md` 是程序文件，不是板测结论。

## 5. G 层

- **G0 局部**：输入冻结快照成立（`env/input-snapshot.json`；生产输入与冻结 manifest 逐条一致）。
- **G1**：`env_check.ps1` 实际运行（12/0/0 PASS + JSON round-trip）；勘察证据逐条复读复核（`final_timing.rpt` 行号、README 行号、生成器复算）。
- **G2—G5 事前不适用**：本包无生产构建、无候选位流、不操作硬件、不发布（理由见任务书与 dev-plan）。

## 6. 回退

- 本包产物全部在**新增目录/文件**：删除 `tools/env/env_check.ps1`、本 run `env/`（逐文件、非批量）即回到原状；不影响任何既有候选/证据。
- 环境本身零修改，无需环境回退。

## R1. round1 修复记录（按 r0 三维报告；仅文档/记录，无行为/RTL 变更）

触发：r0 三维判定 functional FAIL（F1/F2）+ system FAIL（SYS-D1/SYS-D2）+ engineering PASS。

| 缺陷 | 修复内容 | 文件 |
|---|---|---|
| F1：survey S1-1「全库检索无 +5.058 来源」为假 | 改为准确描述：+5.058 = 同一份 `final_timing.rpt` 内 `Path Group: tl_clk_user → tl_clk_user` 的 SWNS（L2073-2081，含 `Min Period 10.942 = 16.000−5.058`；组内最差路径 L2087/L2210 Slack=5.058；pr.timing 同）——属**跨节误引**；clk1 摘要行修正值 +1.141 不变 | `env/optimization-survey.md` |
| F2：§0「5 个」vs S1-7「6 个」计数口径不一致 | §0 改为「未实例化模块 **6 个**」并注明口径（生产 0 实例 3 + 仅被未实例化模块实例化 2 + 仅 TB 使用 1）；顺带修正 §0 分类计数（3 纯文档 / 3 RTL 注释死代码 / 3 清单-peer 类）与失效的「S1-7/K7」「§2」引用 | 同上 |
| SYS-D1：手册 §0 仿真示例 `-TbFiles sim/tb/…` 原样执行必失败（双层 `sim/`） | §0 示例改 `-TbFiles tb/tb_cam_r10f_writer.v`；§2 增补「`-TbFiles` 相对基准 = `fpga/csi2/pcie_integration/sim/`」及 run_sim.ps1 头注释不一致的登记 | `env/environment-handbook.md` |
| SYS-D2：手册 §0 示例 `-OutDir` 指向冻结证据/候选目录 | 两例 `-OutDir` 改为临时 scratch 示例（`test-reports/scratch/…`），并新增「OutDir 安全规则」警示（禁止指向 `raw/`、`backend/`、`env/logs/` 或任何既有证据/候选目录；TD 会 `-force` 重建） | 同上 |
| 举一反三（时效措辞） | 「T11 判定前只读/判定在途」等失效措辞更新为「T11.rk-align-raw r0 已收束（三维 PASS）；修改只由对应任务授权范围执行」 | survey §5/§6、handbook §7/§8、change-report §2 |

**修复验证（本包本地检查）**：
- 手册 §0 修正后的仿真命令（仅 `-OutDir` 换成本包证据目录，其余按文档原样）实跑：`run_sim` exit 0、`vlog Errors: 0`、`vsim ALL PASS`、P10 1080p `beats=81025 / bursts=634 / hdr_crc=56ba381a / pay_crc=ac1b6fe1`（与冻结 raw G1 证据逐值一致）；证据 `test-reports/T11.rk-align-base-r1-doc-example-evidence/msim_writer_demo/`（commands.log/vlog.log/vsim.log/run.do/bin 齐备）。
- `env_check.ps1` 与 `environment-inventory.json` 本轮**未改**（脚本行为/清单事实不变），round0 的 12/0/0 证据与 manifest 条目继续有效。
- 受保护树（`fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`raw/`、`backend/`）本轮 0 写入；`raw/`、`backend/` 文档缺陷（S1-1/S1-2 的目标文件）本包不改。

**传播提示（供规划者，非本包文件）**：同一「全库检索无 +5.058 来源」绝对句亦出现在 `test-reports/T11.rk-align-raw-r0-engineering.md` §6 第 4 条与 `test-reports/T11.rk-align-raw-r0-engineering/verify_supplement.txt`（T11.rk-align-raw 任务产物，r0 已收束）；是否一并更正由规划者/该任务后续处置，本包不改。

## R2. round2 修复记录（按 r1 functional 报告 F1-r1；仅文档/记录）

触发：r1 三维判定 functional FAIL（F1-r1）+ engineering PASS（复用判定 + 5 条观察）+ system PASS（SYS-D1/D2 已清除）。

| 缺陷/观察 | 修复内容 | 文件 |
|---|---|---|
| F1-r1：handbook §2 新增无范围绝对断言「既有 G1 证据的 TB 命令全部带 `-Defines MIPI_PHY_SIM_STUB`」——项目级实核为假 | 改为分范围准确表述：**本 run/raw G1** 22/22 均带；**T07 backend G1** 仅 `tb_csi_checked` 各轮带（5/31），其余 26 条未带；明确「不是项目级『所有 TB 必带』的要求」；写者 TB 加不加均可、引用 stub 端口的 TB 按各自既有证据命令带 define 的建议保留 | `env/environment-handbook.md` |
| 举一反三（绝对断言全量复核） | 逐条扫描本包文档的「全部/均/唯一/所有/全库/全树/零写入」等断言并对照项目级证据：§0「唯一结构性靶点」→「本次勘察发现的唯一时序/资源类靶点」；S1-1 登记指代精确化（→ `T11.rk-align-raw-r0-engineering.md` §6 观察第 4 条）；S1-2「当前 T07 唯一有效清单」→「T07 r3 最终清单」；§3「全树实例化扫描」→「集成树 `fpga/csi2/pcie_integration/`（排除 `peer-ref-2a4b253/`）」；§6「rc_side 未进本工程」→「未进 TD 工程清单（`00_all.tcl`）」；handbook「唯一可跑入口」→「CLI 脚本唯一可跑入口」 | survey、handbook |
| engineering 观察 1 / system 观察 2：manifest `round` 字段仍为 0 | 重冻时置 `round: 2`（同步 `frozen_at`/`notes`） | `env/artifacts-manifest.json` |
| functional 观察 / engineering 观察 3：r1 证据目录另含 3 个 `.bin` 与 ModelSim `work/` 未入清单、未声明 | 3 个 `.bin`（TB `$fopen` 输出）入清单；`work/`（ModelSim 运行库 6 文件）在清单 `logs_note` 登记为「工具运行库、未入清单」 | 同上 |

**修复验证（本包本地检查）**：
- F1-r1 数据实核（本包独立统计）：`raw/g1/msim` 递归 22 个 `commands.log` → 22/22 带 define；`backend/g1/msim` 递归 31 个 → 5/31 带（全部为 `tb_csi_checked` 各轮：tb/r1/r2/r3/r3v），26 不带；`backend/g1/README.md` L11/L24/L44 只给 `tb_csi_checked` 记录该 define。修复表述与以上事实逐条一致。
- 绝对断言复核：见上表第二行（6 处措辞/指代修正），全部对照项目级证据（含跨任务证据目录）。
- round2 未跑仿真/TD；受保护树 0 写入；`env_check.ps1`/`environment-inventory.json`/`board-env-checklist.md`/`env/logs/`/`env/verify/` 内容未变。

**边界**：F1-r1 修复不涉及任何工程输入；r1 doc-example 证据与 r0/r1 复跑证据继续有效（其引用对象未变）；`raw/`、`backend/` 文档缺陷（S1-1/S1-2 目标文件）仍由规划者/获授权包处置。
