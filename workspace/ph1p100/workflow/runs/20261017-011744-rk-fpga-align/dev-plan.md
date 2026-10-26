# 可验收工作包与持续派发

run=20261017-011744-rk-fpga-align，batch_size=1。用户授权推进适配和必要板验；主只转发。每包新开发/三测试，所有角色禁止递归派生；本规划者持续更新。

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要G层 | 初始状态/下一动作 |
|---|---|---|---|---|---|---|---|---|
| T03.rk-align-freeze | 先完整备份可恢复起点，固定三仓版本，生成分工/接口/RK修改包和后续输入 | 当前根；本run的backup/references/contract/artifacts/evidence/lessons；不改生产RTL | 无 | 重新计算尺寸/寄存器，检查分层头和CRC，列出旧行为负例 | 备份zip+git bundle校验、dirty归属、pin SHA、工具真实版本、恢复清单 | 对应实际peer源逐项交叉检查，RK清单可执行、硬件窗口与回退明确；G3不适用纯备份合同 | 局部G0/G1，G2—5不适用；双方正式签收仍待 | ready→新开发 |
| T07.rk-align-backend | 真正引入匹配EP核/后端，接入本方checked CSI，修DMA边界/锁存/所有权/包内反压；可构建独立候选 | 新`fpga/csi2/pcie_integration/`、`tools/pcie_integration/`，本run candidate/evidence；不改旧主线 | 上包PASS | peer TB+独立TLP oracle，BAR/endian/CRC、+16负例、容量/4K/反压/timeout/reset，checked真实连接 | TD6.2.3最终DB/STA/资源/约束/CDC/IP与bit manifest；旧代码不漂移 | top完整连线、RK补丁/参数一致、回退和板测准备；G3留给单独实际硬件包 | G0(局部)/G1/G2；G3—5不适用此component产物，不声称DMA实收 | waiting_dependencies |
| T11.rk-align-raw | 1080p packed RAW10+R10F零填充→AXI缓存→peer发送，全帧CRC/持有/ACK，RK局部补丁及严格解析工具 | 同新目录；本run交付包 | 后端PASS；真实几何待板测前核实 | 缩小+完整几何仿真，逐样本/CRC、EOF坏帧禁止发布、RAW尾/容量高位/溢出/序号、consumer慢和复位 | 同候选最终STA/CDC/资源/bit，所有构建入口与参数冻结 | 驱动/用户态补丁apply-check、64/32地址、槽布局/ACK/严格解析，实际板验包可操作 | G0局部/G1/G2；G3/G4单列下包，G5未完成 | waiting_dependencies |
| T07.rk-align-board | 同一最终bit真实SRAM板验：链路/BAR/合成PCIT或R10F固定数据、UART/JTAG计数、恢复 | 只允许本run证据/工具；硬件system独占 | 后端/RAW至少一个最终G2候选；可用JTAG/主机通道 | 固定块/帧预期字节与实际一致，CRC/长度/计数 | 最终DB/bit与板用SHA相同，CWC适用检查 | G3真实器件/时间/操作者/下载日志；若RK可达则实收100帧零CRC错，恢复1次；无RK时仅板内证据不可当DMA实收 | G3必需；G4短稳10min，记录负载/错误/帧率，无法实收保留blocked | 条件待查询；不阻塞上方代码包 |
| T11.rk-align-release | 用户可审阅组合版、RK修改清单/patch/样例/命令、完整备份回退、界限与下一入口 | 本run release、handoff/final-summary/user-summary；规划可定向更新tasks T03/T07/T11/records | 有已冻结产物即独立整理；真实硬件未过明确⚠ | 发布内容与验证身份一致 | 清单hash/重现命令/原始证据/失败留存 | 将RK必须修改、可选优化、未测条件清楚列出 | 仅G5交付可恢复性子范围；不等于端到端G5 | 待上一包结果后派发 |

上述局部标签沿用原T任务，不新增全局ID。单包“done/PASS”只对预设子范围成立。T03全局仍待双方签收；T07全局仍待真实主机DMA；T11全局仍待压缩/真实端到端，不能因本轮非压缩版完成而转done。

## 首包开发具体要求

读`task-T03.rk-align-freeze.md`；仅本run内写。先保护dirty和回退，后产生合同/后续输入，不应耗时重做旧工具安装或DDR1333调参。本包只收工具和硬件接入事实，不运行生产构建、不下载硬件。

## 修复、停止与回退

round0首次验收，round1—3最多三轮实际修复。FAIL按原开发/原测试；每次重冻manifest与复测维度清单，不拼不同输入PASS。缺必需工具、板、资料/额度直接blocked交原规划，不消耗修复轮。三轮未过保留⚠，派发仍可独立RK包/交付包。

备份未独立校验前不做生产修改。禁止删除、reset/clean、覆盖旧候选/其他run、外部D写入、向peer推送/发消息、Flash与自动化。只在新文件新工程实现，恢复通过新目录解包/选回既有002820 bit，不把备份覆盖到dirty目录。发现源漂移/别的硬件操作者停止共享资源动作并交原规划。

板验不是因为“明天”而省略；“明天看到组合版”以实际候选状态、已验证范围与未测条件交付，不预言完整双路性能通过。系统具备条件则直接执行已授权SRAM板验。无RK通道先交FPGA板内证据和RK必改包，缺口不阻塞本地适配。

## T07 修复轮记账与 G2 决策（round2 派发，2026-10-17）

- **轮次记账**：round0 首验三维 FAIL（F2 编译阻塞 / F1 system 所有权 / F3 冻结漂移 + G2 setup 未达）；round1=实际修复①，F1/F2/F3 已修复并由开发复验（默认入口四 TB ALL PASS、manifest 428C0B33…C1BB 自检 228/0），G2 重建后 setup −2.507 ns / STNS −300.004 ns（181 端点全在 cam_a/cam_b 187.5 MHz 字节域，最差路径=本包 checked 完整性链）仍未达 → 开发者按令 blocked、未放宽判据。
- **规划决策**：**不改相机链路速率 / T11 相机前提**（该前提调整属用户级，未到必须选择前不转用户）；**先做本域有界时序重构** = round2 实际修复②，续原开发 ses_eb9ff4ea6ffe2uONmThm2oHkpZ（原 write_scope 不变）；「检查搬到带缓冲慢域」留作 round3 备选，不预先授权。
- **round2 路线与边界**：重构 `fpga/csi2/pcie_integration/rtl/checked/` 完整性链——① CRC 比较 / 错误与坏帧计数 / 计数器更新移出每拍同拍链（用 END_PACKET / 尾部排空拍或限定 wait 拍，数据流不反压、不丢拍）；② CRC 递推改合成友好并行形式；仍超预算才允许分拍递推 / 2 路交织 + 末帧 GF(2) 合并与小缓冲（ERAM 134/300 有余量）。行为等价必须用现版模块作差分 oracle + 随机/边界流量证明；O_payload_* 与像素流对齐不变；good/abort 允许有限拍滞后但须在本帧发布裁决前生效；诊断计数滞后要记录。
- **禁止项**：放宽 SDC / set_multicycle / set_max_delay；改 187.5 MHz 或相机速率；改 `fpga/csi2/src/csi` 原源（保持只读作差分参照）；改 wrapper 对外接口 / 顶层连线（确需则停止交规划）；批量删除。
- **停止条件**：重构 + G1 重跑 + TD 重建最多两次；若 setup 仍 <0 或残差无实质改善，记录残差分布与所做尝试后停止返回 blocked（不擅自搬域 / 调速率）。
- **合并复测**：新 manifest 冻结后，主按合同续接本任务 round0 记录的三测试者对同一新 manifest 复测（三维必需，input_status=changed）；system 探针按 change-report §7.2 接 rel_tgl2/3；测试轮次按实际修复轮计（本轮=修复② ⇒ r2；r1 无独立测试事件，r0 失败报告保留）。
- **额度**：round2 后剩实际修复③一轮；三轮仍不达则保留 ⚠未通过、由规划派发可独立继续任务；板测包依赖 G2 达标候选，不放松。

## T07 收束与 T11 派发（2026-10-17，round3 后）

- **修复轮记账（3/3 用尽后通过）**：round0 三维 FAIL → 修复①（F1/F2/F3；G2 仍 −2.507 ns）→ 修复②（本域有界时序重构；G2 +0.107 ns 达标；r2 = system/engineering PASS、functional FAIL）→ 修复③（tool-only：入口 BOM 修复 + 文档更正；RTL/SDC/bit/DB 零变化）→ **r3 三维同候选 PASS**。唯一候选：manifest `68f9f4d0…4275`、bit `0943cb36…8b0a`；判定矩阵 `verdict-matrix-T07.rk-align-backend-r3.json`。本包 G0局部/G1/G2 成立；G3—G5 未做；父 T07 不置 done。
- **遗留（不影响判定）**：F5-r3（`backend/g2/README.md` §6 文档绑定句留待下次触碰改绑）；functional r2 §6.1 enable 角落用例 → 列入 T11 增补；RTL 头注释陈旧、`g1/crc16_upd4.generated.v` 标注、仓库根 `run2.do` 与 `R:` subst 残留由用户/后续处置（handoff/final-summary 已登记）。
- **角色替换合规核对**：r2/r3 测试者与开发原会话因上游请求超限被主重建（main-log 27/28/32 行），均同冻结输入/范围、登记新旧映射、不假称 resume；G2 决策由临时新规划实例 `ses_eb95ca92…` 出具（未改速率/前提），本恢复实例收尾。未发现越权或跨任务复用。
- **下一包 T11.rk-align-raw（已派发；新开发+新三测试）**：正式 packed RAW10→R10F 非压缩通路（几何参数化、未板证标 synthetic/diagnostic）、完整帧所有权与 one-shot 发送、严格解析工具与按需 RK 补丁增量；写入=`fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`run/raw/`、`test-reports/`；`backend/` 与首包冻结只读；G0局部/G1/G2（相机字节域 setup≥0 回归门槛）。板层 G3/G4 留 `T07.rk-align-board`（先查 JTAG/主机通道与 RK 条件），G5 留 `T11.rk-align-release`。
- **板测备条件**：JTAG/BW 入口与独占窗口、可用下载路径（用户已接板）、RK 可达（BDF/内核/PAGE_SIZE/MPS/IOMMU）与已打 RKA1 补丁的驱动；缺失不阻塞 T11 离线包。

## FPGA 侧基础夯实与优化子轨（user-feedback-03，2026-10-17）

用户新要求：先推进 FPGA 侧——环境配置合理化、FPGA 侧基础任务做完以达后续要求、逻辑冗余寻找、逻辑优化。拆分与排序：

| 子包 | 对应要求 | 内容 | 顺序/依赖 | 写范围 | G层 |
|---|---|---|---|---|---|
| T11.rk-align-base | 环境配置合理化 + 逻辑冗余寻找 | 环境清单/env_check 自检脚本/环境手册/板测环境清单 + 逻辑冗余/优化**只读**勘察（逐条证据、收益、风险、验证、优先级） | **立即可派**；与 T11.rk-align-raw 在途 functional 不冲突：只写新目录 `tools/env/`、run `env/`、test-reports 本包文件；其余只读 | 新 `tools/env/`、run `env/` | G0局部/G1；G2—G5 事前 N/A（无生产构建/硬件） |
| T11.rk-align-opt | 逻辑优化 + 基础任务达标 | 按勘察清单实施优化（时序余量/死代码/重复逻辑等），新候选 + G1/G2 | **必须等 T11.rk-align-raw r0 functional 判定登记且 T11 收束后**（PASS→规划收尾；FAIL→原开发修复轮）；基于 T11 冻结候选与新 manifest | 集成树 + 新候选（opt/）；不改 backend 冻结 | G0局部/G1/G2（相机字节域 setup≥0 回归门槛）；G3/G4 留板测包、G5 未完成 |
| T07.rk-align-board | 基础/板验（既有） | 同最终候选 SRAM 板验与观测、RK 实收（若可达） | 条件：JTAG/BW 窗口 + RK 侧事实；不阻塞 base/opt | 只允许本 run 证据/工具 | G3 必需；G4 短稳 |
| T11.rk-align-release | 组合版交付（既有） | 用户可审阅组合版 + RK 清单/patch/样例/命令 | 最后 | 本 run release 等 | G5 子范围 |

- **与全局任务板的关系**：逻辑冗余/优化属 T14 域，但本轮按用户要求提前在集成线执行（T11.rk-align-base/opt 子轨）；不改变 T14 全局（提交后性能优化）的状态与退出条件，子包完成不置 T14/T11/T07 done。T01–T02/T06 等旧线不受本子轨影响，硬件窗口仍按既有规则协调。
- **冲突规则（硬约束）**：T11.rk-align-raw r0 functional 在途期间，`fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`raw/` 冻结输入不得被任何新角色修改（同一冻结输入不得边改边测）；优化实施只在其判定/收束后开始。
- **板测接线结论（答复用户）**：FPGA 单板基础观测不需要 RK；PCIe 链路需要主机（PC 或 RK）；端到端实收需要 FPGA 插在 RK 上 + 已打 T07/T11 补丁的驱动。详见 user-summary.md。

## 基础任务扩展：三种算法与压缩（user-feedback-04，2026-10-17）

用户补充：“基础任务还有例如3种算法和压缩，压缩选一个就行”。核对既有决策与任务板：

- **3种算法 = T09 三种四像素预处理**（灰度、高斯、CDF-min 前帧均衡），与 T09 记录一致。现有资产（只读）：Bayer 工作树 `fpga/csi2/src/img/{rgb8_gray_stream.v,gray8_gaussian3x3_frame.v}` + `tools/rtl_checks/verify_{gray,gaussian}.py`；主项目 `parallel/algorithms/*` 软件参考。缺口：灰度只接 RGB8（缺 Bayer→Y8 去马赛克前端）、HE 与并行组织未做。
- **压缩 = T10**；“选一个”与 T04 既有用户决策一致：**Bayer 同色预测 + 有界 Rice + RAW 回退（BPR1）为唯一方案**；不复活 LZ77/LZSS、不默认 JPEG（T14 O 系列仍为封存/未来候选）；真实 RAW 图集与规则接受口径风险保留（T13/规则矩阵）。**结论：无范围歧义，不需要向用户提问。**
- 现有资产（只读）：Bayer 工作树 `fpga/csi2/src/codec/{bayer_samecolor_predict,bayer_rice_codeword,bayer_rice_row_stream,bayer_bit_packer}.v` + `tools/bayer_codec/*`；缺口：RAW 选择/行头/CRC/帧发布/长度，及持续服务率证据。

新增排队子包（batch=1 顺序执行；详细 task 文件由规划在派发时写入）：

| 子包 | 内容 | 顺序/依赖 | 写范围 | G层 |
|---|---|---|---|---|
| T09.rk-align-algo | 三算法真实 RTL：引入工作树候选（provenance）+ 补 Bayer→Y8 前端 / HE（换 LUT、首帧、四像素同 bin 冲突）/ 并行组织；边界/首帧/坏帧/切换/停顿；独立软件模型交叉 | 排在 T11.rk-align-base 收束后；T02 真实几何/坏帧板证仍为后续板验前提（离线用合成/参数化） | 新 `fpga/csi2/src/img/`、本 run `algo/`、test-reports | G0局部/G1/G2；G3/G4 留板测；G5 未完成 |
| T10.rk-align-codec | BPR1 单方案真实 RTL：引入 codec 四文件（provenance）+ 补 RAW 选择/行头/CRC/帧发布/长度/完整有效帧才发布；码长上限/位序/填充；软件解码 round-trip 与负例（短尾/坏帧/切换）；最坏 RAW 回退吞吐预算（头/报文另计） | 排在 T09 后；T04 软件参考 ready；不触碰 T11 冻结输入；不把 BPR1 装进 codec=0、不分配压缩枚举 | 新 `fpga/csi2/src/codec/`、本 run `codec/`、test-reports | G0局部/G1/G2；G3/G4 留板测；G5 未完成 |

- **总队列**（默认顺序，规划可依证据/窗口调整）：T11.rk-align-base（在途）→ **T09.rk-align-algo** → **T10.rk-align-codec** → T11.rk-align-opt（须 T11.rk-align-raw 判定与收束后）→ T07.rk-align-board（条件）→ T11.rk-align-release。
- **与 T11 判定/上板的关系**：T09/T10 在新目录工作，不触碰 `fpga/csi2/pcie_integration/`、`tools/pcie_integration/`、`raw/` 冻结输入；但按 batch=1 顺序，不与其在途测试并行派发。算法/压缩接入传输顶层（压缩集成）是后续独立集成包；本轮先各自出候选，BPR1 不进入 R10F codec=0。
- **验收与边界**：两包均要求真实 RTL 仿真 + 独立软件模型、同一最终 DB 的 STA/资源（模块级小顶可）、停止修改后冻结；板测/实收留板测包；不得用 8bit 原型或 stub TB 充当达标证据。

## 比赛要求对齐（user-feedback-05，2026-10-17）

复读 `docs/赛题条款与验收矩阵.md`（R1–R6 原文短引）、`docs/规则修订来源记录.md`、`docs/导师复核与提交前并行推进建议_2026-10-15.md`、`docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md`、`docs/DeepSeek独立检测与现行方案整合_2026-10-16.md`。逐项对齐：

| 项 | 要求（原文短引） | 当前计划/证据 | 状态 |
|---|---|---|---|
| R1 | MIPI CSI FPGA 驱动 IP，至少单路高清实时采集 | checked CSI 链路 + T11 raw 写者（仿真验证；真实几何/相位待板证） | 已覆盖（离线）/待办（板验） |
| R2 | 至少3种基础预处理（灰度/高斯/直方图均衡；剩余两项必须硬件并行实现） | T09.rk-align-algo（三算法+并行组织） | 待办（已排队；验收含真实并行硬件证据） |
| R3 | 搭建 JPEG/LZ77 任一硬件压缩加速模块 | 当前主线 BPR1（Bayer+Rice+RAW回退）≠ JPEG/LZ77；替代接受口径为规则确认事项 | **风险/待用户确认**（question-01.md） |
| R4 | MIPI/PCIe 二选一，稳定传输压缩图像帧 | PCIe 链路已通（T07/T11）；压缩帧传输集成未在队列→新增 `T11.rk-align-compress-int` | 部分覆盖/新增待办 |
| R5 | RK NPU 轻量化目标检测推理 | RK 队友（T05 blocked / T12） | 队友范围/待办 |
| R6 | 帧率/延迟/资源/压缩率/推理耗时量化数据 | 资源（G2 已有）；压缩率（T10/compress-int）；帧率/延迟/推理耗时需板测+RK | 待办（板测/发布包汇总） |

- 场景级数值（60fps、压缩率≥30%、延迟<50ms、2h 长稳、同步<1ms）是场景/拓展口径，非基础统一门槛；首个 1080p30 里程碑不变；最终口径需组织方确认（Q-RULE-2/3 仍开放），不擅自改写规则。
- **队列调整**：T11.rk-align-raw r0 三维 PASS（0 修复轮）→ 已收束；T11.rk-align-opt 解禁（仍排 T09/T10 之后）；新增 `T11.rk-align-compress-int`（压缩帧经 PCIe 传输集成 + RK 软解码工具 + 实测压缩率/吞吐；排在 opt 之后、板测之前）；T10 压缩基线已由 user-feedback-06 定为 LZ77+Bayer 混合（见下节），不再等待。
- 总队列：T11.rk-align-base（在途）→ T09.rk-align-algo → T10.rk-align-codec（LZ77+Bayer 混合，见下节）→ T11.rk-align-opt → T11.rk-align-compress-int → T07.rk-align-board（条件）→ T11.rk-align-release（含 R6 量化汇总）。

## R3 压缩合规决策：LZ77 基线 + Bayer 自有优化（user-feedback-06，2026-10-17）

用户答复（原话见 user-feedback-06.md）：采用“Bayer 加上 LZ77”的混合方式——有 LZ77（符合官方要求）也有自己的优化。核对记录与可行性：

- 既有记录：原 LZ77 主线 → 2026-10-15 用户改选 Bayer 预测+有界 Rice（BPR1）为研发主线，替代接受口径留“规则确认事项”（导师复核：无组织方接受前 BPR1 只能列拓展；O05：组织方否决或收益不达再切 LZ77/JPEG）。项目内**无已实现的 LZ77 资产**（主仓库与 Bayer 工作树检索均无 lz77/lzss/deflate/gzip 文件），LZ77 需新做。
- 可行性证据：RAW Bayer 强项是局部/通道相关而非长距离重复，通用字典匹配收益有限且搜索带宽大；但“packed RAW 字节组织会影响字典压缩效果”（导师复核）→ **Bayer 域预处理可提升 LZ77 有效性**：①四相位去交织（同色相邻）；②同色预测残差化（残差聚集在 0 附近，利于匹配/游程）；③块级模式选择（plain LZ77 / Bayer+LZ77 / RAW 回退）。可同时满足 R3（真实 LZ77 硬件编码器）与“自有优化”（增益需实测证明）。
- **推荐形态（本轮采用）**：单编码器架构 = **LZ77 熵编码（合规基线；块头/长度/CRC 规范）+ Bayer 预处理前端（相位重排+同色预测，自有优化，可开关以做 A/B 对照）+ 块级 RAW 回退（防最差膨胀）**；输出优先 DEFLATE/GZIP 兼容（RK 可直接 zlib 解码）或明确自描述格式+自研软件解码器（不得硬件自定义 token 却声称 zlib 互通）。BPR1（预测+Rice）保留为软件对照与后续可选第二模式（O 系列），不作本轮必需。
- 备选：B. 双编码器可选模式（LZ77 基线 + BPR1 高比率）——工作量最大，留拓展；C. 纯 LZ77（无 Bayer 优化）——合规但无创新、RAW 压缩率可能差，不推荐单独；D. 纯 BPR1——合规风险（已否）。
- 资源/时序/风险预估（待实测，不作承诺）：参考 Gzip 核（LZ77+Huffman，作者平台 128MHz≈128MB/s、GPL-3.0、数据不可照搬）——**单核吞吐低于双路 155.52 MB/s 预算**（60fps 更高），需并行/多核或分阶段降速；字典/匹配逻辑 RAM 与 LUT 开销须在本板实测；ERAM 现余约 164/300；任何集成改动须重跑 G2（相机字节域 setup≥0 门槛）。真实 RAW 图集仍缺（比率/最差膨胀证据受限，先用合成/冻结向量并如实标注）；许可与来源贡献须记录（优先自研或宽松许可，不直接照搬 GPL 代码）。
- 验收要点（T10）：官方 R3 满足（LZ77 硬件编码器 + 软件解码 round-trip + 块头/CRC/长度 + 最差膨胀回退）；自有优化证据（Bayer 预处理相对 plain LZ77 的比率增益 A/B 实测，含低纹理/高纹理/噪声）；吞吐按最坏 RAW 回退算；与 `T11.rk-align-compress-int` 的格式/枚举合同（R10F 外层 + LZ77 载荷、codec_id 分配、RK 解码路径）由 compress-int 包冻结。
- 队列：T10 不再等待（question-01 已答复），仍排在 T09 后；范围按本节更新（BPR1→LZ77+Bayer 优化）；`T11.rk-align-compress-int` 承接 T10 输出做传输/RK 解码/实测。
- 组织方接受口径：因基线含真实 LZ77，R3 字面合规已满足；BPR1/混合形态的“创新加分”表述如需官方口径，保留为可选外部确认（非阻塞）。

## 终点与范围调整（user-feedback-07，2026-10-17）

用户原话：“这次的任务最终停在进行双路同步成功即可，最后的RK深度/NPU不用进行”。

- **终点**：双路同步成功（对应 T08：双路真实数据、曝光同步证据、失锁恢复；不以同帧号代替同步）。未经验证不置 done。
- **排除**：RK 深度/NPU 明确不进行（T12 的深度/NPU 部分关闭/暂缓；T05 的 RK 离线双目/NPU 相应部分排除）。tasks.json T04/T05/T08/T12/T13/T14 已按事实记录。
- **队列关系与优先级**：T09（三算法）、T10（LZ77+Bayer 压缩）、T11.rk-align-opt（逻辑优化）、T11.rk-align-compress-int（压缩帧传输集成）仍属本次范围——它们是用户此前明确要求的基础任务与 R2/R3/R4 合规项，不因终点调整取消；双路同步验收包（板测类，需 T02/T06、双路相机与板窗口）在条件具备时优先排入；离线包继续按队列推进。
- **口径说明**：双路同步的验收证据按 T08 原文（FPGA 侧真实双路数据/曝光同步证据/失锁恢复）；若用户希望“经 RK 实收”验证同步，则由 compress-int/board 包并入提供——当前不阻塞，如有不同口径用户可纠正。
- T13/T14：提交材料与提交后优化不在本轮终点范围（材料口径待用户后续安排）；不虚报完成。

## 队列暂停（user-feedback-08，2026-10-17）

用户原话：“完成三种算法后先停下来，过会我们统一下进度，只开一个对话推进，不然一直并行推进会比较乱”。

- **暂停点**：T09.rk-align-algo 照常完成开发+三维验收+收束；**收束后暂停队列**——不派发 T10.rk-align-codec 及后续（T11.rk-align-opt/compress-int/board/release）。T10 等保持排队但不派发。
- **恢复条件**：用户统一进度后（由本 run 规划者在本对话链路恢复队列；恢复时不再开并行工作链）。
- **登记**：dispatch.json status_after_t09=await_user_sync + sequencing.hold_after_t09/single_conversation + next_action.after_completion；tasks.json T10/T11 已记；handoff 同步。

## T09 修复轮1（blocked 处置，2026-10-17）

T09.rk-align-algo round0 返回 **blocked**（未达 ready_for_test）。条件清单与处置：

- **G1 未达**：core 用例 16 条逐样本 mismatch（多帧 HE/中止交互段 branch1/2；branch0 同段正确；首错 cycle6930：branch2 idx=8 got=00000000 exp=ffff3333；branch1 idx=8 got=1c020000 exp=b7b08069）。修复路径=软件模型差分隔离 HE 跨帧 LUT/bank/abort 语义；修复后全量重跑 core + 负对照。
- **G2 未达**：小顶（img_algo_parallel_top + pin 级包装 img_algo_top_g2）已 Routed、bit 已保存（PRJ-1424）、hold +0.021ns；187.5MHz 下 setup SWNS -3.870ns / STNS -505.059ns（365 违例端点）。修复路径=算法链有界流水化（重点 HE 直方图/CDF 与去马赛克前端组合链）；**不放宽 SDC、不改 187.5MHz 前提**；TD 重建≤2 次；2 次后仍<0 则停止并返回 blocked（附残差分布与候选：更慢域+缓冲 / 进一步流水），由规划决策（可能上升为用户取舍）。
- **额度/未跑项**：gray 模块 TB 首向量超时（TB 侧）未定位；rate/gauss_frame/负对照未跑（本轮额度用尽）。修复轮1 必须补齐。
- **预算与停止**：修复轮1（实际修复 1/3 轮，上限三轮）；每轮 TD 重建≤2 次；冻结后按复测清单走三维（functional 全量、engineering TD 重建、system 接口/并行结构复核）；三轮仍不达则保留 ⚠未通过、暂停等用户同步。
- **与暂停的关系**：修复轮1 属“完成 T09”范围（同任务同链，非并行新链）；T09 收束后队列暂停（T10 及后续不派发）不变；若修复轮1 结束仍 blocked，则直接进入暂停，把 blocked 状态与选项并入用户同步材料。
