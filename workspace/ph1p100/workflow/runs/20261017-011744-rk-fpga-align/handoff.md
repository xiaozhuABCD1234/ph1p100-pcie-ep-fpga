# 当前交接（2026-10-17，T07.rk-align-backend 收束后）

## 本次收束结论

T07.rk-align-backend：round0 三维 FAIL → 修复①（F1/F2/F3）→ 修复②（G2 本域时序重构达标）→ 修复③（tool-only 入口 BOM + 文档更正）→ **r3 三维同候选 PASS（实际修复 3/3 轮用尽，第 3 轮通过）**。唯一候选 manifest=`backend/candidate-manifest.json` SHA256=`68f9f4d0…4275`（232 条自检 0 不一致）；bit=`backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration.bit` SHA256=`0943cb36…8b0a`（5,224,023 B，与 best_result 同源）；G2=SWNS +0.107 ns/STNS 0.000/0 违例端点、hold +0.020 ns、Routed；G1 五 TB+入口/负对照；判定矩阵=`verdict-matrix-T07.rk-align-backend-r3.json`，报告=`test-reports/T07.rk-align-backend-r3-*.md`。本包 G0局部/G1/G2 成立；G3—G5 未做（板测单列 T07.rk-align-board），父 T07 不置 done。

## 历史（保留）

T03.rk-align-freeze round0 三维 PASS（0 修复轮，manifest `9662167a…77c5`）；首包 backup/references/contract/artifacts/evidence 原字节保留。原规划 ID=`/root/fpga_planner_rk_align` 跨会话失效，恢复实例 `ses_eba025958ffenOiSFeq1XsVCQQ` 完成恢复派发与本次收尾。用户反馈02=原话重发+“codex 执行一半”，无新增技术约束。

## 角色实例替换（合规核对：均同冻结输入、登记映射、不假称 resume）

- planner：`/root/fpga_planner_rk_align` → `ses_eba025958ffenOiSFeq1XsVCQQ`（恢复；本收尾）；G2 决策轮由临时新规划实例 `ses_eb95ca92affe8TZf3ltDvcPlCX` 出具（未改速率/前提，范围合规，见 dev-plan『T07修复轮记账与G2决策』）。
- developer：T07 原开发 `ses_eb9ff4ea6ffe2uONmThm2oHkpZ`（r0–r2）→ r3 修复实例 `ses_eb90ba403ffeEhY8R2zrp9EfS8`（原实例上游超限；同任务/输入/范围；change-report §10.5 交接补记）。
- functional：`ses_eb98c6b72ffe70wHKEufdQxSnH`（r0；r2 上游超限失效）→ `ses_eb9332494ffe5exD82MjCJkFQi`（r2/r3）。
- engineering：`ses_eb98c6b6fffejyDEOTshsrXu0t`（r0；r2 上游超限失效）→ `ses_eb92ce12affe6hBhfgoIavFtMK`（r2/r3）。
- system：`ses_eb98c6b6dffeBUTgOKZCRRe0yX`（r0/r2/r3 全程）。
以上以 main-log.md 为准；未发现越权、范围变化或跨任务复用。

## 遗留与待条件（不影响已判 PASS）

- F5-r3：`backend/g2/README.md` §6 仍写“三维复测绑定 round2 manifest”；文档残留，下次触碰该文件时改绑 `68f9f4d0…4275`（本次收尾不改 backend 冻结包）。
- functional r2 §6.1 的 `I_enable` 包尾撤销覆盖缺口（仅诊断计数级）→ 已列入 T11.rk-align-raw 增补用例。
- `rtl/checked/csi_rx_packet_integrity.v` 头注释陈旧（随下次触碰）；`backend/g1/crc16_upd4.generated.v` 中间产物已就地标注；仓库根未跟踪 `run2.do`（19B，非候选输入）与 `R:` subst 残留映射（指向 `test-reports/T07-functional-r2/neg-shadow`）由用户/后续按需清理（本 run 不删除、不触碰）。
- RK 编译/安装 not_run（缺 KDIR/交叉工具链/cargo）；板层 G3—G5 条件：JTAG/BW 入口与独占窗口、RK 可达（BDF/内核/PAGE_SIZE/MPS/IOMMU）+已打 RKA1 补丁的驱动。
- 时序节制：相机字节域余量仅 +0.107 ns（54% 布线）；任何 RTL/约束改动必须重跑 G2 并以“该域 setup≥0”为回归门槛。`tools/pcie_integration/*.ps1` 的 UTF-8 BOM 是功能性要求（编辑必须保留）。

## 下一入口

已派发 T11.rk-align-raw（dispatch.json：spawn_agent/developer，`task-T11.rk-align-raw.md`；新输出 `run/raw/`）。顺序建议：T11.rk-align-raw（正式 RAW10→R10F 通路+RK 严格解析工具）→ T07.rk-align-board（system 独占板测，先查条件）→ T11.rk-align-release（用户可审阅组合版）。父 T03/T07/T11 均不置 done。

## FPGA 侧基础夯实子轨（2026-10-17，user-feedback-03）

用户要求先推进 FPGA 侧（环境配置合理化、基础任务达标、逻辑冗余寻找、逻辑优化）。T11.rk-align-raw r0：system/engineering 已 PASS，functional 在途（冻结输入 `raw/candidate-manifest.json` AAB0CC08…6975，bit 14b32037…5686b）。排序（详见 dev-plan『FPGA侧基础夯实与优化子轨』）：

- **T11.rk-align-base**（已派发；新开发+三测试）：环境清单/env_check/环境手册/板测环境清单 + 逻辑冗余/优化只读勘察。只写新目录 `tools/env/`、run `env/`、test-reports 本包文件；与在途 functional 不冲突。
- **T11.rk-align-opt**（排队，未派发）：按勘察清单实施逻辑优化（新候选+G1/G2，相机字节域 setup≥0 回归门槛）。**必须等 T11.rk-align-raw r0 functional 判定登记且 T11 收束后**；在此之前集成树与 `tools/pcie_integration/`、`raw/` 冻结输入不得被修改。
- **T07.rk-align-board**（排队）：条件=JTAG/BW 窗口 + RK 侧事实（BDF/内核/PAGE_SIZE/MPS/IOMMU）+ 已打 T07/T11 补丁的驱动。
- 板测接线答复（已写入 user-summary.md）：FPGA 单板基础观测不需要 RK；PCIe 链路需主机；端到端实收需 FPGA 插在 RK 上+补丁驱动。
- 冗余/优化属 T14 域，本轮按用户要求提前在集成线执行；不改变 T14 全局状态与退出条件。

## 基础任务扩展（2026-10-17，user-feedback-04）

- 用户补充“基础任务还有例如3种算法和压缩，压缩选一个就行”：3种算法=T09（灰度/高斯/CDF-min前帧HE）；压缩=T10，**已选单方案=Bayer同色预测+有界Rice+RAW回退（BPR1）**，与 T04 既有用户决策一致，**无需澄清**；不复活 LZ77/LZSS、不默认 JPEG；真实RAW图集/规则接受口径风险保留。
- 新增排队子包：**T09.rk-align-algo** → **T10.rk-align-codec**（新目录 `fpga/csi2/src/img/`、`fpga/csi2/src/codec/` + run `algo/`、`codec/`；只读引入 Bayer 工作树资产并补缺项；G0局部/G1/G2；板测留后续）。
- 总队列（batch=1，不并行）：T11.rk-align-base（在途）→ T09 → T10 → T11.rk-align-opt（须 T11.rk-align-raw 判定与收束）→ T07.rk-align-board（条件）→ T11.rk-align-release。
- 详细范围/验收/G层见 dev-plan『基础任务扩展』节；task 文件在派发时由规划写入。

## 比赛要求对齐与 T11.rk-align-raw 收束（2026-10-17，user-feedback-05）

- T11.rk-align-raw round0 三维同候选全部 PASS（0 修复轮；manifest AAB0CC08…6975、bit 14b32037…5686b；矩阵/报告见 run）；该子包收束；T11.rk-align-opt 解禁（排 T09/T10 后）。
- 复读比赛要求（R1–R6）逐项对齐见 dev-plan『比赛要求对齐』节：R3 风险项=原文要求 JPEG/LZ77，BPR1 替代接受口径未定 → 已写 question-01.md 请用户确认（T10 派发前必须答复）；R4 压缩帧传输新增 `T11.rk-align-compress-int` 排队；R2 验收强调硬件并行证据；R5/R6 分属 RK 队友与板测/发布汇总。
- 总队列：T11.rk-align-base（在途）→ T09 → T10（待用户）→ T11.rk-align-opt → T11.rk-align-compress-int → T07.rk-align-board → T11.rk-align-release。

## R3 压缩路线已定（2026-10-17，user-feedback-06）

- 采用 **LZ77 基线 + Bayer 自有优化**（单编码器：LZ77 熵编码 + 相位重排/同色预测前端（可开关 A/B）+ 块级 RAW 回退；输出优先 DEFLATE/GZIP 兼容或自描述格式+自研解码）；BPR1 转拓展/可选第二模式；组织方字面合规满足（保留可选创新表述确认，非阻塞）。
- T10 范围据此更新、不再等待；队列：T11.rk-align-base（在途）→ T09 → T10（新范围）→ T11.rk-align-opt → T11.rk-align-compress-int → T07.rk-align-board → T11.rk-align-release。
- 风险登记：单核吞吐可能低于双路 155.52MB/s 预算、资源/时序须实测、无既有 LZ77 资产需新做（许可注意）、真实 RAW 图集仍缺。

## 终点调整（2026-10-17，user-feedback-07）

- 本轮最终目标=**双路同步成功**（T08：双路真实数据/曝光同步证据/失锁恢复）；**RK 深度/NPU 不进行**（T12 相应部分关闭/暂缓、T05 相应部分排除，均不置 done）。
- 队列不变：T09 → T10（LZ77+Bayer）→ T11.rk-align-opt → T11.rk-align-compress-int → T07.rk-align-board → T11.rk-align-release；双路同步验收包在硬件条件（T02/T06/板窗口/双相机）具备时优先排入；未验不置 done。
- tasks.json T04/T05/T08/T12/T13/T14 已按事实记录（T04 追加压缩路线变更；T08 新增终点注记）。

## T11.rk-align-base 收束与 T09 派发（2026-10-17）

- T11.rk-align-base：round0（functional FAIL/system FAIL/engineering PASS）→修复①（functional 新缺陷 F1-r1）→修复②（r2 三维同候选全部PASS，实际修复2轮；manifest `env/artifacts-manifest.json` FF079FFA…C069，26条自检0不一致）；全部修复为文档/记录级，env_check.ps1/清单/受保护树/既有证据SHA零改动；交付=环境清单/env_check/环境手册/板测环境清单 + 逻辑冗余/优化只读勘察（run `env/`）。
- 跨任务观察处置（规划决定）：T11-raw r0 engineering §6『全库检索无+5.058来源』=无范围绝对断言（实际来源=`final_timing.rpt` tl_clk_user 路径组 L2076-2081）→**仅登记+给出正确来源**，不改写测试者历史判定报告；如需更正须由测试角色最小勘误并保留判定行/绑定+留痕。
- 已派发 T09.rk-align-algo（task-T09.rk-align-algo.md；新开发+新三测试；写 fpga/csi2/src/img/、tools/algo/、run algo/；G0局部/G1/G2）。队列余下：T10.rk-align-codec（LZ77+Bayer）→ T11.rk-align-opt → T11.rk-align-compress-int → T07.rk-align-board（条件）→ T11.rk-align-release。

## 队列暂停（2026-10-17，user-feedback-08）

- T09.rk-align-algo 照常完成开发+三维验收+收束；**收束后暂停队列**：不派发 T10 及后续（T11-opt/compress-int/board/release），等用户统一进度（status_after_t09=await_user_sync）。
- 协调：后续**只开一个对话推进**（避免并行混乱）——恢复由本 run 规划者在本对话链路进行，不再开并行工作链。
- T10 等保持排队但不派发；恢复方式=用户说一声，规划者续接 dispatch 并派发 T10。

## T09 blocked 与修复轮1（2026-10-17）

- T09 round0 返回 blocked：G1（core 16 逐样本 mismatch，多帧 HE/中止段 branch1/2；rate/gray/gauss_frame/负对照未跑）+ G2（小顶 Routed/bit 已存、hold +0.021ns，187.5MHz setup SWNS -3.870/STNS -505.059，365 端点）；已修 8 类真实缺陷；manifest `algo/candidate-manifest.json` d84bb020…4475；未放宽判据。
- 规划处置：派发**修复轮1**（续原开发 `ses_eb6e19aa7…`；最多 3 轮；TD 重建≤2/轮；不放宽 SDC/187.5MHz；2 次重建仍<0 则返回 blocked 附残差与候选供规划决策）。条件清单/路线见 dev-plan『T09 修复轮1（blocked 处置）』。
- 暂停约定不变：T09 收束后队列暂停（T10 及后续不派发）；若修复轮1 仍 blocked，则直接进入暂停并把状态/选项并入用户同步材料；后续只开一个对话推进。

## T09.rk-align-algo 收束与 await_user_sync 生效（2026-10-17）

- T09：round0 blocked（G1 16 mismatch / G2 -3.870ns）→ 修复轮1（流水化+HE/中止语义修复）→ **integrated 综合测试 PASS**（functional/engineering/system 全过；setup SWNS +0.059ns/STNS 0/0 违例、hold +0.020ns、Fmax 189.609MHz；G3/G4 not_run=范围外；G5 未完成；实际修复轮=1；无 retest）；manifest `algo/candidate-manifest.json` 2195641A…A5F8（36/36 无漂移）；报告 `test-reports/T09.rk-align-algo-r1-integrated.md`。
- 观察项：D1=he_samebin 冻结负对照锚点漂移（测试自有适配对照拒绝成立、不影响判定）；D2–D4=文档记账陈旧项（随下次触碰更正）。
- **暂停生效（user-feedback-08）**：T10.rk-align-codec 及后续（T11-opt/compress-int/board/release）不派发；恢复入口=用户说“继续/同步完成”后，主转本 run 规划者，规划者写 T10 task 文件并更新 dispatch（spawn_agent/developer）后派发；恢复时只开一个对话（single_conversation）。
