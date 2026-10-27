# input-index — FPGA 方案知识书（run 20261017_162355_fpga_knowledge_book）

- 规划日期：2026-10-17（周六）。角色：fpga-planner。纯文档/知识型交付：无硬件、无 TD、无下载、无外部消息。
- 本文登记本次采用的输入、版本/哈希、方案事实来源与未决事项；供开发/测试按需读取，不复制全文内容。
- 写边界：规划者只写本 run 目录；开发者（KB0）只新建 `docs/知识书/` 及本 run 目录内笔记/清单。不修改任何既有文件。

## 1. 本次需求

| 对象 | 路径 | 版本锚 |
|---|---|---|
| 用户原话（含主 Agent 机械登记） | `workflow/runs/20261017_162355_fpga_knowledge_book/requirement.md` | SHA256(前16)=`FA5DD38E6CB280A4`（851B） |

需求摘要（理解用，非替代原话）：把本项目 FPGA 部分**现行方案**拆成细碎的基础知识，做成**由浅入深、书式分章**的个人知识储备；辅以网上优质视频/文档；目标是让用户对方案**至少具备独立判断力**（示例问题：DDR1600、1333、800E 的区别与划分）。

## 2. 与需求相关的项目材料（规划者已读或定位核实）

| 路径 | 版本/哈希（前16） | 本次用途 |
|---|---|---|
| `AGENTS.md`（根） | `BD3E1CC32B6E03DC` | 多智能体工作流与角色边界 |
| `workflow/README.md` | `1EC0D073E01EEFFA` | §4 六层验证 G0–G5；§5.1 交付必检；状态机与文档权威位置 |
| `workflow/tasks.json` | `91CDFE22539FF222`（23058B，2026-10-17 观测） | T01–T14 现状：T01 active（DDR1333 链打通）、T11 active（raw r0 三维 PASS）、T02 awaiting_hardware、T08=终点、T09/T10 ready、T12 深度/NPU 本轮不做 |
| `docs/DeepSeek独立检测与现行方案整合_2026-10-16.md` | `96DA69508E9CAF96` | 现行方向、R10F/BPR1 冲突裁决、算法共同口径、DDR 审阅修正、未来候选 O01–O08 |
| `docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md` | `1F7B4CD95D01A55C` | F1–F9 工作包、压缩技术路线与验收、吞吐/资源预算、时间停止条件 |
| `workflow/runs/20261017_161109_decisions_compare_freeze/decision-register.md` | `4DC44C4D68540D49` | M1–M5 决策冻结登记：DDR 三候选（1600K/1333J/800E）对比与裁定规则、统一路径 M2a–M2e、显示 M3、工具链 M4、悬置 M5 |
| `workflow/runs/20261017_153201_T01_ddr1333_integration/dev-plan.md` | （同日，E1 已派发） | DDR1333 集成/对比链的工程细节、0.300ns 口径来源、1600ctl 控制候选设计 |
| `当前必读/01_FPGA主线学习手册_由浅入深.md` | `A307548186B09C5E` | 既有由浅入深教材（10-09/10-10 版；含 RAW12 主线、LZ77 候选等**历史口径**）；新书的前置阅读与对照物，不修改 |
| `workflow/runs/20261017-011744-rk-fpga-align/`（closeout/handoff/backend） | 见各文件 | T03/T07/T11 后端冻结：R10F 非压缩、peer `2a4b253`/driver `a0215c5`、CTRL 0x61、one-shot/ACK |
| `parallel/docs/帧与元数据接口合同_2026-10-15.md`、`parallel/frame/frame_contract.py` | 见文件 | R10F 128B 头/三层 CRC 的参考字段表；正式拒收缺口 |
| `.agents/skills/fpga-orchestrator/references/{relay-contract,report-contract}.md` | 见文件 | 派发/报告元数据约定；测试报告第一行判定格式 |
| `当前必读/选题三_重新对齐后的方案基线.md`、`docs/双目首版_整链路方案与团队交付.md` | 见文件 | 方案基线与整链路候选（章节写作可按需引用） |

## 3. 章节写作必须一致的"方案事实"基线（只列稳定事实；写作时引用左侧来源路径）

1. **主线数据**：双路 1920×1080@30fps、RAW10 packed（10bit 样本）；双路预算 155.520 MB/s（+25% ≈ 194.400 MB/s，头/报文另计）。来源：策略文档 §6、project-context。
2. **压缩路线（R3 合规最终答复，2026-10-17 user-feedback-06）**：**LZ77 基线 + Bayer 自有优化**混合、单编码器：LZ77 熵编码合规基线 + Bayer 相位重排/同色预测前端（可开关 A/B）+ 块级 RAW 回退；输出优先 **DEFLATE/GZIP 兼容**或自描述格式+自研软件解码（**不得**用自定义 token 声称 zlib 互通）；**BPR1（Bayer 预测+有界 Rice+RAW 回退）转拓展/可选第二模式**，不作本轮必需。来源：tasks.json T10/T04 注、decision-register M5.4。
3. **传输格式**：R10F 128B 头；**2,592,768B**（633×4096）DMA 长；`payload_bytes=2,592,000`；尾 640B 零填充；三层 CRC（内头 CRC / 外层头 CRC / 恢复 RAW CRC）；host 数据偏移 128B。压缩经 R10F 需正式 adapter（原长/内长/外长/DMA 长分别命名），**不能只改 `codec_id`**。来源：decision-register M2c/M2d、整合 §3.1/§3.2、T11 raw r0。
4. **DDR 三候选现状**：A=1600K/PAXI（现役基线 002820，STA setup +0.000ns 薄）；B=1333J/PAXI（新 IP 已生成，E1 派生完成、E2 构建对比进行中）；C=800E/AXI（队友/PCIe 后端轨道现用）。三者带宽均足够（≈6.4/5.33/3.2 GB/s 理论×32），**不构成区分因子**；区分在手册口径（DS1300：PH1P100 DDR3=800Mbps）、时序余量、接口族（PAXI vs AXI）与集成分工。频点终选=用户后续决策。来源：decision-register M1、T01 run。
5. **三算法**：Bayer→Y8 灰度（half-up，`Y=(77R+150G+29B+128)>>8`）、3×3 高斯 `[1 2 1;2 4 2;1 2 1]`+`(sum+8)>>4`+复制边界、前帧 CDF-min HE（首帧恒等、坏帧不更新、换帧锁定、四像素同 bin 冲突处理）；要求真实硬件并行结构与资源/吞吐证据。来源：整合 §3.3、策略 §5 F4、tasks.json T09。
6. **采集/几何**：IMX415 双模组、4lane CSI-2、当前单 A 实测接收；真实包几何/ROI/Bayer 相位**待板证**（T02 awaiting_hardware）；接收走**普通 IO/软 PHY 路线**（该封装无硬 D-PHY 证据）。来源：F9P 核验、PH1P100 接收路线证据、tasks.json T02。
7. **显示出口**：HDMI 1080p60 为工作基线（148.5/742.5MHz、1485Mbps/lane，超手册 650MHz/332Mbps → 资格未决、彩点未定位）；下一里程碑=4Kp30 显示输出尝试（用户既定方向）。HDMI 仅是**调试出口**，非最终交付路径。来源：decision-register M3。
8. **同步口径**：共享 XHS/XVS、A 主 B 从候选；SOF 差值/同帧号**不能代替曝光同步**；终点=双路同步成功（T08）。来源：当前硬件_引脚电气与同步证据、tasks.json T08。
9. **工具链**：TD 2026.2（6.2.3.210850）forward + 6.2.2 只读遗留；DDR MC 变体走"CLI 引导配方+一次用户在场 GUI Generate"；bitgen fail-closed；无 headless 全自动路径。来源：decision-register M4、T01 run §1。
10. **证据纪律**：G0–G5 分层；每次交付执行 workflow/README §5.1；未实测不写"通过"；设计候选≠已实现；组织方对替代 JPEG/LZ77 的口径**仍待确认**（不写"已获官方批准"）。来源：workflow/README §4/§5.1、整合开篇。
11. **当前不算数的事**：真实完整 RAW 的几何/CRC 未板验（T06 backlog）；双路 B 路未验收；RK 深度/NPU 本轮明确不做（T05/T12 暂缓）；主线频点未终定。

> 写作红线：以上事实**只能按来源引用路径表述**；任何"已通过/已实现"必须能指到证据文件；不确定处标【待验证】或【设计候选】。

## 4. 既有可复用写作资产

- `当前必读/01_FPGA主线学习手册_由浅入深.md`：已有"由浅入深"组织法与自测题式结尾，可借鉴结构；但其 RAW12/LZ77/RGB565 主线段为历史口径，**新书按现行方案更新**并在 README 中注明二者关系（不改旧文件）。
- `docs/` 下按主题的复盘文档（CSI、DDR、RGB565、TMDS 等）：可作为"本项目实例"小节的一手素材来源。
- `parallel/*` 参考模型与向量：解释算法/R10F 时可引用（标记为独立轨道产物）。

## 5. 未决事项与风险（写作时如实标注，不得替用户/组织方拍板）

1. 组织方对"BPR1/自研路线替代 JPEG/LZ77 基础项"的接受口径**未确认**；R3 已按 LZ77 基线合规路线执行。
2. DDR 频点终选未定（E2 数据未出）；1333 vs 1600 vs 800E 的"手册资格"问题未获官方澄清。
3. 真实相机几何、B 路、双路同步均待板验。
4. 外部视频/文档链接的可用性受网络环境限制——链接核验规则见 `fpga-design-guide.md`（本 run）§5。
5. `workflow/tasks.json` 被并行线持续更新：本知识书流**不改任务板**（默认）；如需全局登记由用户另行确认（见 open-questions.md）。

## 6. 旧失败证据目录

本知识书为首次创建，`workflow/runs/` 下无相关旧失败 run；**旧失败证据目录不适用**（无需引用）。若后续修复轮产生失败现场，保留在本 run 目录，不覆盖。
