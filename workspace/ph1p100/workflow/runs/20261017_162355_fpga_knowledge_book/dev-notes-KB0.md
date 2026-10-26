# dev-notes-KB0 — 知识书骨架与样章

- 任务：KB0（run `20261017_162355_fpga_knowledge_book`）；角色：fpga-dev；日期：2026-10-17。
- 状态：r0 内容冻结后，本文件按 r1 修复轮更新（记录见 §8/§9）；书目录 4 个文件中仅 README 修复 1 处路径。测试输入清单：r0 见 `manifests/KB0-manifest.json`，r1（当前）见 `manifests/KB0-manifest-r1.json`。
- 写范围遵从 dispatch：仅新建 `docs/知识书/` 下 4 个文件与本 run 目录内笔记/清单；未修改任何既有文件。

## 1. 实际读入（写作依据）

**冻结输入（dispatch 必读，全文读取）**

1. `workflow/runs/20261017_162355_fpga_knowledge_book/requirement.md`
2. `workflow/runs/20261017_162355_fpga_knowledge_book/dev-plan.md`（重点 §3 大纲与 §5.1 KB0 详述）
3. `workflow/runs/20261017_162355_fpga_knowledge_book/input-index.md`
4. `workflow/runs/20261017_162355_fpga_knowledge_book/fpga-design-guide.md`

**同 run 状态文件（读取，未修改）**：`dispatch.json`、`open-questions.md`、`main-log.md`。

**相关材料（按 dev-plan §3 第 01 章"建议引用材料"读取，用于样章事实对核）**

1. `workflow/README.md`（§2 文件职责、§4 G0–G5、§5/§5.1 冻结与必检、§6 故障处理；顶部状态摘要）
2. `当前必读/01_FPGA主线学习手册_由浅入深.md`（§1–§2.3；阶段表与流水线直觉）
3. `docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md`（§1 现状口径、§2 工作全景、§6 吞吐预算）
4. 技能与合同（核对交付格式）：`.agents/skills/fpga-dev/SKILL.md`、`.agents/skills/fpga-design-guide/SKILL.md`、`.agents/skills/fpga-orchestrator/references/report-contract.md`、`.agents/skills/fpga-orchestrator/references/relay-contract.md`

## 2. 实际产出（6 个新文件 + manifest）

| 文件 | 说明 |
|---|---|
| `docs/知识书/README.md` | 书首页：目的/读者、双阅读路线、目录与进度表、维护规则、与旧教材关系、事实分级承诺 |
| `docs/知识书/_写作规范.md` | fpga-design-guide §1–§5 的可执行展开：命名/模板 10 节/事实标记/链接核验规程/文风/禁止写法/流程与自检清单 |
| `docs/知识书/_全书大纲.md` | dev-plan §3 的 27 章＋3 附录转录（章号/标题/Part 未增删改；章末补"前置/后续"） |
| `docs/知识书/01_从代码到电路.md` | 完整样章：模板 10 节全写；286 行 |
| `workflow/runs/20261017_162355_fpga_knowledge_book/link-check-KB0.json` | 链接核验记录（10 次实际请求：8 通过、2 失败/不可核验；本章采用 7 条） |
| `workflow/runs/20261017_162355_fpga_knowledge_book/dev-notes-KB0.md` | 本文件 |
| `workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB0-manifest.json` | r0 冻结输入清单：读入与产出文件的 SHA256（不含 manifest 自身，自引用说明见该文件；保留不改写） |
| `workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB0-manifest-r1.json` | r1 修复轮冻结清单（新版本；见 §8/§9） |

## 3. 停止条件与合规检查（实际执行）

- 开工前 `Test-Path docs\知识书` = False，`Test-Path docs\知识书\README.md` = False → 目录**不存在**，按计划新建；无同名书目录冲突；未触发停止条件。
- 全部产出均为**新建路径**；未覆盖/修改/删除任何既有文件（范围外零写操作）。
- 越界证明：对本任务两个写范围执行 `git status --porcelain`，仅显示新增（`?? docs/知识书/`、`?? workflow/runs/20261017_162355_fpga_knowledge_book/`）；范围外已存在的 M 条目（`tools/td/`、`workflow/tasks.json` 等）为本任务开始前其他并行任务的改动，本次会话未触碰。
- 文件规范实测：4 个书文件均 UTF-8（无 BOM）、纯 LF；样章 286 行、README 114 行、规范 102 行、大纲 205 行（均在约定范围）。

## 4. 联网工具可用性实测（dev-plan §5.1 必须实测项）

- 工具可用：本次共发起 **10** 次实际页面请求，**8** 次成功返回且页面标题与登记一致，**2** 次失败（1 个超时、1 个为 JS 应用壳无法核验标题）。
- 明细（URL/返回标题/日期）全部写入 `link-check-KB0.json`；第 01 章资源表 7 条全部为"在线核验通过 2026-10-17"。
- 失败项处理：AMD 大学计划页与 docs.amd.com 均**未列入**章节资源表，按规则如实记录，未虚构"已核验"。

## 5. 三维自检（对照 KB0 验收细则与 `_写作规范.md` §8）

- **functional**：大纲与 dev-plan §3 逐章一致（机器可比：章号/标题/Part 未改）；README/规范/样章无相互矛盾；样章模板 10 节齐全；自测题 6 条且答案可验算；项目事实对核 ≥10 处（样章"与本项目方案的对应"12 行＋3 个实例）；G0–G5 表述与 `workflow/README.md` §4 一致。
- **engineering**：命名/编码/LF 合规（见 §3 实测）；无越界写；manifest 将含 6 个产出文件＋14 个读入文件的 SHA256；资源行核验状态全覆盖；样章引用项目文档均改写且单处 ≤2 句。
- **system**：README 目录与文件名一致（当前仅 01 章文件提供链接，其余标注"待创建"）；书内引用的项目路径在 r1 已完成**全书逐条扫描**：可点击链接 5/5、代码跨度路径 91 处（逐处计，含 3 组通配符）全部解析通过、错误单层前缀 0 处（r0 缺陷与更正过程见 §8）；样章可独立回答"为什么仿真通过≠上板通过"（七站表＋误区 1＋自测题 2）。

> 说明：以上为开发自检，不替代三个独立测试者的判定。
>
> 更正（r1）：r0 版本本节曾写"含大纲建议材料抽样，共 14 条 `Test-Path` 全部通过"——该抽样未覆盖 README L106 的代码跨度路径（system 维度 r0 发现，属自检覆盖不足）；r1 已修复并改为全书逐条扫描，详见 §8。

## 6. 未测与边界

- 链接核验是 **2026-10-17 时间点快照**；B 站/维基页面内容与标题可能随时间变化。
- 样章中的项目事实引用到本 run 冻结时的口径；若后续任务推进（如 T01/E2、板测结果更新），相关表述按"版本记录"走下一轮修订，不在本包内改。
- 未创建第 02 章及以后文件（按批次规划）；README 进度表中它们的"未写"状态即为当前事实。

## 7. Lessons（可复用）

- **L1**：官方文档站（如 docs.amd.com）为 JS 单页应用，联网抓取只能得到加载壳或超时，**不宜**列入"可在线核验"资源表；资源优先选页面可直接读取标题的载体（B 站视频页、维基、博客园等）。
- **L2**：B 站视频页可直接读出标题、UP 主与分集时长，适合登记"标题/作者/体量"三字段；登记时把"看哪几集、各多长"写进推荐理由，比只给整个系列链接有用。
- **L3**：`AMD` 类超时属传输层问题，重试一次即可判定，但**不得**凭搜索结果里的标题当作"在线核验通过"。
- **L4**：写"书名—目录—进度"类首页时，未创建的章节一律"待创建"占位，避免 README 导航出现死链。
- **L5（r1）**：路径自检须覆盖**两类引用**——可点击链接（`](…)`）与**代码跨度路径**（反引号包裹的路径），范围应是"全书逐条扫描"而非抽样；扫描实现要做围栏感知（跳过 ``` 代码块），否则三反引号围栏会错位配对出假 token。r0 因只做 14 条抽样＋可点击链接扫描，漏检 README L106 的 `../` 前缀（D1）。

## 8. r1 修复轮记录（2026-10-17）

- 触发：system 维度 r0 判定 **FAIL**（单点低危 D1，报告 `test-reports/KB0-r0-system.md`）；functional/engineering r0 为 PASS（观察项处置见下）。
- 缺陷：`docs/知识书/README.md` 第 106 行把旧教材写成 `../当前必读/01_FPGA主线学习手册_由浅入深.md`，从 `docs/知识书/` 解析到不存在的 `docs/当前必读/…`。
- 根因：该行属"与既有教材的关系"说明，前缀与全书其余 `../../当前必读/…` 不一致；r0 自检的 14 条 `Test-Path` 抽样与可点击链接扫描均未覆盖该**代码跨度路径**（自检覆盖不足，对应 lesson L5）。
- 修复（最小面）：仅将该行前缀改为 `../../当前必读/`，其余字节不动。
  - 修复前 SHA256 `75b2a8921b3c91204ac16bb7e310003271e93b329a0d0a6d58c5d84cac1d1bfb`（6318B）→ 修复后 `06593d95700a263361e732cf76aa37e594efd094da8a2411d966130166625636`（6321B；行数 114 不变）。
- 回归验证（2026-10-17，工作目录=项目根，PowerShell 5.1；命令均为只读）：
  1. D1 复现命令：旧前缀解析 `Test-Path`=**False**；修复后 `..\..\当前必读\…`=**True**；
  2. 全书单层错误前缀（`../<根目录>/` 模式）= **0 处**；双层规范前缀 `../../…` 共 55 处；
  3. 可点击链接（4 文件 `](…)` 共 5 条）解析 **5/5 通过、0 断链**；
  4. 代码跨度路径（围栏感知逐行扫描）：**91 处全部解析通过**（含通配符 3 组：`../RAW10稳定档位_*`=1 命中、`../evidence/ddr1333_*`=6 命中、`…/pcie_unified_path/*`=8 命中）；跳过 5 条（90/91/92 计划文件 ×4、模板示例 ×1）；
  5. README 修复后复核：UTF-8（无 BOM）、纯 LF、114 行/6321B。
- 范围外零写：本轮仅改 `docs/知识书/README.md` 一行、更新本文件、新建 `manifests/KB0-manifest-r1.json`；未覆盖/删除任何其他文件（r0 manifest、测试报告、link-check 等原样保留）。
- 输入漂移（run_state，r0 遗留）：`main-log.md` 为主代理滚动日志，r0 两维测试者已登记并评估为流程固有、良性。r1 manifest 对其记录**冻结时点快照**并附语义说明；若原规划者希望改为"仅存在性/不纳入严格冻结面"，请在后续派发前裁定（不阻塞本次复测）。
- 功能性观察 O1–O4 处置（`test-reports/KB0-r0-functional.md` §7，均标注不阻塞）：为保持 r0 functional/engineering PASS 证据的最大可复用性，本轮**未改**任何内容文件以满足这些观察，交原规划者裁定；建议口径：
  - O1（样章"（待写）"标记）：与 dev-plan §5.2（其为 KB1–KB8 增量约束）对照；样章是否补标由规划者统一裁定（建议 KB1 起执行、样章不动）。
  - O2（样章脚注未逐条列 docs.amd.com）：link-check 已有完整失败记录、无虚构；如需补列建议随下一次自然修订。
  - O3（1 处归因略宽）：实质正确；可将依据改为手册 §2.2 与工作流 §5.1 并列，建议随下一次自然修订。
  - O4（"理论×桂冠值"疑似上游笔误）：系对 dev-plan §3 的忠实转录；**交规划者在 KB3 派发前确认词义**，不在本包改大纲。

## 9. r1 复测影响清单（供主转发原测试者）

- required_dimensions：**["system"]**（r0 FAIL 维度；修复对象即 README 路径引用）。
- report_paths：`test-reports/KB0-r0-system.md`（失败报告）；本文件 §8（修复与回归证据）。
- input_status：**changed**（对照 r0 manifest：`docs/知识书/README.md`、`dev-notes-KB0.md` 变更；新增 `manifests/KB0-manifest-r1.json`；`main-log.md` 属滚动日志漂移；其余 17 个条目哈希一致）。
- 证据复用（由原测试者按规则裁定并绑定 r1 manifest 出具复用依据）：
  - system：r0 中除"README 路径引用/哈希"与 manifest 绑定外的证据（大纲/样章路径与锚点、导航结构、G 层）可复用；README 全部路径引用与哈希、r1 manifest 一致性必须重验。
  - functional / engineering（r0 PASS）：变更仅 README 一行前缀修正＋本笔记修订；规范/大纲/样章/link-check/外部链接未变；是否复用由原测试者裁定（建议复用除 README 哈希/路径相关与 manifest 完整性条目外的证据，并按 r1 manifest 重核读数）。
- 预期复测重点：① README L106 前缀解析；② 全书单层错误前缀=0；③ 可点击链接与代码跨度路径抽查；④ r1 manifest 哈希一致性（`run_state` 滚动日志按语义说明处理）。
- 新 manifest：`workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB0-manifest-r1.json`（本文件生成先于该 manifest；其自身 SHA256 由测试者现场重算核对）。
