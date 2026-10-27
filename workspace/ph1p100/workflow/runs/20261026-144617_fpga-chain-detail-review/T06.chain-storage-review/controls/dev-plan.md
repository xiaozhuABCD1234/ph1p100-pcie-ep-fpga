# FPGA 整链路细节审查计划

规划冻结：2026-10-26；PROJECT_ROOT=`D:/fpga/ph1p100`；BATCH_SIZE=1。原始需求见同目录 `request.md`。本轮唯一主要结果是**一套覆盖 FPGA 链路、逐检查点可追溯的逻辑审查与优化结论**；交付审查文档、检查表和少量离线见证，不实施优化、不生成新硬件候选。

## 事实基线与范围选择

- 采用代码与证据并存的分支图，不假定“相机→三算法→压缩→PCIe”已串成一条生产路径。相机/DDR/HDMI、A+ UART 诊断、既有 PCIe RAW 路径、离线同步/恢复轨道分别标为实际接入、隔离验证、参考或仅规划。
- 主仓库 HEAD=`27c596b01cd961dfa9d0850e4fbf879fe249de90`，分支 `codex/ddr-timing-margin`；工作树已有大量修改/历史删除，所有者未逐项确认，全部保护。本轮只写本 run。另一 Bayer 工作树只读，不合并。
- b15 是本轮可定位的既有板级诊断源；板上缺 R、enc/exported=0 保持未闭环。2026-10-26 b15 审计已提供原生 PAXI 地址、mask、并发及模型资格的具体问题，但不等于真实 MC 根因签核。不要把 b15 原报告错误的 cam12 几何解释、确定第1239字或 L_max=1 推断继续当事实。
- b17 在规划读取时只有计划/指南/索引，尚未发现实施源或验收报告；它是另一活动线，不能把计划修复写成已实现，更不能覆盖它。b11 与 b15 不视作同候选。
- 20261025-233401 四包已 PASS，其 headline 仅 `G0_feasible_for_scope`：单路单核187.5MHz、合成/代理、TB slot-free、93.75MB/s sink、行为 DDR。strict-serial 与不可压缩内容仍存在门槛缺口；不得扩成生产双路已过。
- 20261026-143924 已有独立生产前提收口需求；本 run 不代做其真实内容四帧、slot-free 候选、fast-sink 开发，不共享库、设备或候选。
- 当前 FPGA 范围到双路同步及 FPGA→RK 接口；RK 深度/NPU仍暂缓，只登记边界，不重新启动。

## 正式工作包与顺序

仅以下4包属于调度任务。包内“检查点”是审查表行，不是第三级任务，不另派代理。各包有一个主要文档主题、最多5项语义步骤。按生产依赖顺序逐包开发→停止修改/冻结→一个新综合测试者→原规划放行下一包。未知硬件条件记审查发现，不为只读审查启动板测。

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要G层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| T02.chain-input-review | 相机控制、CSI/RAW几何、输入裁决、双路同步检查表及审查报告 | 主仓库；仅本run/T02.chain-input-review/** | 基线快照 | 包/像素/帧语义、错误拒绝、同步证明边界 | 源码/编译选择、时钟复位与CDC证据审查 | 无反压入口、捕获序号、恢复/配对 | G0+G1审查工具 | ready | 新fpga-dev |
| T06.chain-storage-review | DDR/PAXI、槽所有权、队列/仲裁/恢复检查表及审查报告 | 仅本run/T06.chain-storage-review/** | 上包PASS | 地址/掩码/接受事件、容量/隔离、超时与旧响应 | 原生参考绑定、CDC/约束已有证据与缺口 | capture/encode/export并发服务与最坏RAW读写 | G0+G1审查工具 | blocked_dependency | 前包后原规划派发 |
| T10.chain-transform-review | 三算法分支与A+编码/回退检查表及审查报告 | 仅本run/T10.chain-transform-review/** | 上包PASS | 位宽/舍入/边界/LUT、编码格式/回退/长度校验 | 真实DUT和参考来源、资源/时序旧证据资格 | 模式切换、原始/处理数据区别、持续服务 | G0+G1审查工具 | blocked_dependency | 前包后原规划派发 |
| T11.chain-egress-review | 发布/导出/PCIe接口检查表与整链路审查总表 | 仅本run/T11.chain-egress-review/** | 前三包PASS | 长度/CRC/帧事务、DMA/TLP边界、完成与回收 | 实际IP版本/候选绑定、证据矩阵、引用/算术独立核对 | 连续路径、背压、链路守恒、最坏吞吐及风险排序 | G0+G1审查工具 | blocked_dependency | 前三包后原规划派发 |

所有包 G2/G3/G4/G5 **本轮新执行不适用**：只读审查，不改RTL/时钟/IP/协议/约束，不交付新bit，不签核硬件；审查内容涉及的既有G2–G5必须按原始候选逐项列 pass/fail/not_run/blocked，缺口不得删除。G0指工作流接口层；性能门槛另名 `P1080`，避免与以往吞吐报告所称G0混淆。

### T02.chain-input-review（5步）

1. 从冻结顶层/工程列表重建输入路径与参数，辨别实际A/B接入、调试/回放及未接入模块。
2. 逐检查相机I2C角色/启动/重试、软PHY/CSI VC/DT/ECC/CRC、FS/FE/行长和RAW10四像素解包，裁剪起点/相位/短行/尾组与坏帧撤销。
3. 逐检查valid/ready与不可反压入口、跨域数据/sideband、复位、溢出拒整帧、capture_seq、曝光同步与SOF配对/重新锁定区别。
4. 形成证据化的冗余/谬误/优化表；为最重要的1项用小型离线解析/算术/状态轨迹给可检查见证。无需重复完整帧仿真。
5. 交付 `review.md`、`checkpoints.csv`、`findings.json`、`source-map.json`、`witness/`、`commands.json`、`lessons.md`，结束活动并冻结 `manifest-r0.json`。

### T06.chain-storage-review（5步）

1. 逐检查RAW/CMP槽布局、字/字节/PAXI单位、地址扩展与溢出、单一边界转换、stride/尾部/容量隔离，绑定真实生成IP参考。
2. 逐检查mask、AW/W/AR接纳和stall保持、pending/响应归属、一次读在途与读写互斥区别、FIFO/full/skid及本域复位。
3. 逐检查FREE/WRITING/READY/READING/SENDING转换、发布前最后写可见性、不可覆盖、满队列拒整帧、abort/timeout/purge/晚响应/新会话隔离及仲裁公平。
4. 独立重算RAW最坏读写流量、每路/双路共享服务预算，审计模型是否真实执行地址/mask/冲突；复核一个小图样/状态轨迹反例。保留 b17 待实施状态。
5. 交付与冻结同上；引用前包冻结manifest，不改其产物。

### T10.chain-transform-review（5步）

1. 分开列当前A+/LZ77/DEFLATE路径、历史BPR1/Rice参考、三算法与RAW旁路，核对实际编译实例/像素格式/顺序，禁止让历史指南覆盖当前实现。
2. 审查灰度、Gaussian边界/舍入、HE前帧LUT/首帧/坏帧/四lane同bin冲突、模式切换与元数据一致性，确认它们是否真正接入编码链。
3. 审查编码输入/字典边界、匹配/投机abort、bit打包/尾零、stored/RAW回退、膨胀上界、字节顺序、完整帧长度与各CRC/Adler覆盖；冗余副本/校验须证明消费者和故障模型后才建议删。
4. 复核一个最小独立解码/边界见证与吞吐/资源引用；自然图、合成图、proxy、冷启动、稳态和sink受限分列，不跑另一run的四帧矩阵。
5. 交付与冻结同上。

### T11.chain-egress-review（5步）

1. 区分UART诊断导出、RAW/R10F PCIe生产参考、压缩封装待接入，逐查内外长度/填充/CRC/序号/模式及完整帧事务发布。
2. 查PCIe真实IP端口、DW-valid/byte-keep、MPS/4KiB/BE、DMA地址容量、host授权、完成可见性/ACK/回收、复位重试；未接入处写接口缺口，不能按路径存在宣称集成完成。
3. 合并前三包的源映射，检查每条生产者→消费者边的格式/单位/时钟/接受条件/所有权/复位契约，形成 `chain-review.md`、`chain-map.mmd`、`coverage.csv`。
4. 独立计算77.760/155.520MB/s原始需求及头/填充/RAW回退/DDR多次搬运；列基于证据的冗余、谬误与优化建议，按正确性→可观测性→吞吐→资源排序，每项带收益依据/代价/验证/回退，不能空报百分比。
5. 交付本包标准产物、跨包总表和最多3条后续主题，冻结manifest；综合测试必须绑定前3份已PASS manifest。

## 全包产物合同与验收阈值

`checkpoints.csv` 每行至少：`checkpoint,stage,parent_task,producer,consumer,source_path,source_sha256,line_start,line_end,input_output_units,clock_reset,acceptance_event,ownership,invariant,failure_recovery,result,evidence,optimization,verification_next`。`checkpoint`为包内局部标签，不是调度ID。

`findings.json` 每项含 `finding_id,severity,kind,claim,evidence_refs,reproduction,impact,recommendation,expected_benefit,tradeoff,validation,disposition`。kind 仅 `confirmed_issue / redundancy_candidate / evidence_gap / no_issue_found`。不强求发现缺陷数；no_issue_found必须有核对依据，不等于数学证明。

验收阈值：

- 规划各语义检查簇覆盖率100%，零空白/未审查行；不存在实现时用 `evidence_gap` 并给检索范围、实际未接入证据、最小后续验证，不能凭空填PASS。有效分支共享相同检查点可引用一次，不能重复算工作。
- 所有确定性缺陷和删除冗余建议100%带冻结源码/参考定位与触发条件；纯推断显式标明。模型结论不能冒充真实MC/板级事实。
- 每包至少1个与纯自述不同的可复查见证；测试者至少用一个与开发不同的判据（独立解析/独立重算/变异负例）验证本包最高风险判断，且检查全部高风险发现与其余检查点引用存在性。
- manifest SHA核对100%；测试前后冻结输入零漂移；候选代号、实际编译路径及旧证据范围不得混拼。
- 审查报告PASS只表示审查完整/结论可靠，不表示被审查DUT通过。已确认缺陷可以存在于PASS审查中，必须保留其严重性、影响与后续门槛。
- 四包完成才称“本轮整条FPGA链路已完成细节审查”；任何包未验收则如实给覆盖范围和未完成部分，不把范围冻结当完成。

## 工具、权限、预算与停止

允许：只读git/rg/文件读取、Python标准库小型校验、隔离的微型模型/仿真。优先复用已存在的证据，不下载新资料、不自动联网、不向队友/其他聊天发消息。确需澄清规则只列缺口。

每次角色派发/续接≤30实际工具调用；开发/测试各≤45分钟；规划≤15分钟。单一未决问题搜索/读取≤3轮；同失败命令首次+至多1次有新证据重试；连续2循环无进展即blocked。读/搜实际60秒deadline，局部静态/微仿真300秒deadline；每次角色最多3次微仿真、累计≤10分钟。**TD/综合/布线/bitgen/CWC/下载/Flash/COM/JTAG/板卡/RK=0**。不使用共享盘符或共享ModelSim库。

启动命令必须落实真实timeout或安全终止自有进程；`yield_time_ms`不算timeout。可用PowerShell后台Job+Wait-Job -Timeout+Stop-Job处理读/写脚本；有子进程的仿真须用能终止自有进程树的受控runner，不能保证则不启动，返回TOOL_CONTROL_MISSING。

写范围：开发只写自身任务目录，测试只写本run/test-reports/<task_id>/**及一份 `<task_id>-rN-integrated.md`；原规划写本run控制/收尾。`baseline/**`只读。禁止改 `workflow/tasks.json`、现有任务记录、docs junction、生产源、其他run、外部工程/工具配置、旧报告。没有commit/push/发布授权。不删除任何文件；不用reset/clean。

每包round0首次独立验收；真实FAIL续原开发/原测试最多3轮实际修复，其他包新角色。缺工具/资料/额度/授权直接blocked交原规划；审查中发现硬件未知不是擅自获取硬件授权的理由。审查源快照自身缺失/不一致才阻塞本审查，设计的已知缺陷与未证明性能按发现记录。输入漂移不追逐最新候选；先固定本轮快照，变化列到后续。

回退是保留原方案与所有生产候选；本轮无生产改动需要回滚。发现错误审查结论只在本包新轮次改文档并重冻，旧结果保留。完成后原规划写handoff/final-summary/user-summary，父T02/T06/T10/T11不置done。

## 本轮不自动续做的后续主题（最多3条）

1. 原生PAXI合同修复/小图样真实读回/缺R事务证据：归b17活动线及后续明确授权。
2. 1080p30真实内容、生产slot-free与sink/双路资源签核：归20261026-143924，不重复开发。
3. 按本审查优先级实施优化并做生产G2/板级曝光同步、完整帧、恢复与稳定性验收。

恢复入口：`使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review；本轮目标：继续当前dispatch指定的整链路细节只读审查包，保留既有四包/修复/问题计数及baseline，不操作硬件、不自动实施优化。`
