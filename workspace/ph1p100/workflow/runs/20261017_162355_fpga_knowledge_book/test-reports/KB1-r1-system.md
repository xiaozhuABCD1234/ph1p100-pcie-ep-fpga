### 判定：PASS

# KB1 系统维度测试报告（round 1 复测）— 可用性与项目衔接

- task_id：KB1 ｜ dimension：system ｜ round：1（r0 PASS 后的修复轮复测；由 r0 原测试者会话续接裁定复用/重验）
- project_root：`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道`
- 实际工作树/候选：PROJECT_ROOT 现场文本（只读核验；无 worktree、无构建/硬件候选）
- 唯一冻结依据：`workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB1-manifest-r1.json`
  - 现场重算自身 SHA256 = `21759d7056119faeee5e1b8ee2fc46b3ba621cc60b3ebdf696950bee15190e5e`（21638B）＝派发给定值 ✓；JSON 解析正常（round=1、status=ready_for_test）
  - r0 旧证据保留复核：`KB1-manifest.json` 现场 = `b1e1dbdd…`✓；`KB1-r0-system.md` 现场 = `2d6f14d7a05ff15efbb66dd9922f8cdd77be167bec51ab0bd9f302568a3920d6` ✓（为 r1 run_state 登记值，未被改写）
- 测试日期：2026-10-17 ｜ 测试者：system 维度原会话续接（不派生代理）
- 工具/版本：OpenCode read/grep/webfetch；Windows PowerShell 5.1（Get-FileHash/Test-Path/正则只读扫描）；git 未用。未用 TD/板卡；未下载、未发布、未发外部消息。
- 范围与 G 层（维持规划冻结）：system＝可用性与项目衔接（README 入口、三章可独立阅读与衔接、与"当前 FPGA 实际方案"对应、恢复入口、项目路径可解析）；**G0＋G1 适用；G2–G5 N/A**（fpga-design-guide §6/§8：纯文档）；**上板/接口/长稳类 N/A**。
- 写范围合规：仅新建本报告；未修改/覆盖/删除任何输入、章节或既有文件。

## 1. 结论与复用裁定

**PASS**。r1 清单 45 条目 44/44 一致（唯一漂移＝main-log.md 追加型滚动，按 R1 语义非缺陷）；自 r0 起的变更面（02/03/04 三章、link-check、dev-notes）已按"受影响项定点重验＋未变项复用"完成：

- **重验（受影响项）**：O1（ch02 指针全路径化）已落地且解析通过；O2（"rafter"残字）正文已修正；O4（ch02"延伸资源第 4 条"）已改指第 5 条（Synchronous circuit，语义匹配）；O3 对应的 e14 口径与结构化汇总已修正（残留散文句计数问题见 §8 r1-O1，非门槛）；三章全量路径重扫 **38/38 可解析、0 悬空**；交叉引用重扫全部落在冻结 1–27/附录；模板 10 节/自测 6 条/版本记录 r1 行齐备；对外部材料漂移（decision-register rev2、T01 dev-plan 新快照）复核后**新文本无冲突**（三章无任何 E2/待裁定类陈述）。
- **复用（未变项，绑定 `KB1-manifest-r1.json`）**：`README.md`（`3ae45f02…`）、`_写作规范.md`（`bbec84fd…`）、`_全书大纲.md`（`bd266a6c…`）、`01_从代码到电路.md`（`f1651187…`）哈希与 r0 完全一致 → **r0 §3（README 入口可用性整节）、r0 §4 的恢复入口/资源表汇总性结论、r0 §6 对未变更外部链接的抽样结论**在 r1 绑定下继续有效；背景材料哈希不变者（workflow/README、RGB565 文档、策略、整合、手册、合同、frame_contract、两份 RTL 等）r0 §5 对应锚点按 r1 重核读数后维持。
- **不复用**：r0 对 02/03/04 章节正文与 link-check 的旧结论一律不以 r0 文本为准，本报告全部改用 r1 文本重验（§3/§5/§6）。
- **本维度无待复测项**（required_dimensions=[]）。

## 2. 冻结绑定与哈希核对（G1 基础）

方法：现场重算 r1 清单全部条目（45 条＝dispatch_required 12＋run_state 6＋materials_read 18＋skill_and_contracts 4＋outputs 8）；`README/_写作规范/_全书大纲` 按 `modified_central_files.after_sha256` 核对。

| 分组 | 结果 |
|---|---|
| manifest-r1 自身 | ✓ `21759d70…`（21638B，与派发给定一致） |
| dispatch_required（12） | ✓ 12/12 一致（含 KB0 资产、01 章 `f1651187…`、3 条基线→修订后映射） |
| run_state（6） | ✓ 5/5 一致（dispatch/open-questions、三份 KB1-r0 报告、**r0 system 报告 `2d6f14d7…` 未被改写**）；`main-log.md` 追加型漂移见下 |
| materials_read（18） | ✓ 18/18 一致（含新增 `docs/evidence/camera_rgb565_timing_20261015_114913.json` `e34e5b67…`；decision-register `7b5a828c…`、T01 dev-plan `60ab21bd…`、tasks.json `e2ce3b36…` 为 r1 时点快照） |
| skill_and_contracts（4） | ✓ 4/4 一致 |
| outputs（8） | ✓ 8/8 一致（02 `a4191191…`/29228B、03 `1223ee9e…`/25709B、04 `5e793790…`/23636B、大纲/规范/README＝r0 后未变、dev-notes `57345cfd…`/20204B、link-check `e4f52bdf…`/12030B） |

- **唯一漂移**：`main-log.md`（现 `42585a1a…`/9286B；r1 快照 `00ad19e5…`/8536B）——滚动日志追加（R1 语义），**不判 FAIL**。
- 三章现场字节/编码复核：02=29228B、03=25709B、04=23636B，CR 计数=0（纯 LF），与清单/自检声明一致；行数按清单 238/242/268（哈希一致背书）。

## 3. 修复面逐项核验（本轮重验项）

| 项 | 位置 | r0 问题 | r1 现状（现场核验） | 结果 |
|---|---|---|---|---|
| O1 | ch02 L126 | 裸文件名 `ph1p_ddrphy_dram_init.v:232` 不可按 F3 形式解析 | 已改为项目根相对全路径 `fpga/csi2/prj/ddr_frame_probe/vendor/ip/ddrmc_x32/src/rtl/init/ph1p_ddrphy_dram_init.v:232`；`Test-Path` ✓；行 232 邻域实读 = `assign done = (state_cnt[3:0] == S_DONE);`（组合译码，与"init 状态译码"表述相符）；旧裸写法全库 0 残留 | ✓ 闭环 |
| O2 | ch03 L85 | "两组 rafter 两级同步"残字 | 正文改为"分别用两组同步器各打两级"；全库"rafter"仅剩 ch03 L242 **版本记录引述旧笔误**（合理留痕，非缺陷） | ✓ 闭环 |
| O4 | ch02 L28 | "（见 延伸资源 第 4 条）"指向 CDC 条目 | 改为"第 5 条"；现第 5 条＝同步电路（Synchronous circuit，英文）"时钟/寄存器模型与异步电路的边界讨论"——与"异步电路…工程上少用"语义匹配 | ✓ 闭环 |
| O3 | link-check + ch02 | e14"第 02/03 章共用"与章节表不符；summary 算式不成立 | e14 口径改为"未入表（核验通过，保留待自然修订）"✓；`summary.table_rows_by_chapter` 02/03/04=8/7/6、`distinct_urls_used_in_tables`=18、`shared_rows_note`"21=18+3"✓；`proposed_states_used` 16/2/1/4 合计 23 ✓；manifest `link_check.notes` 同账 ✓；ch02 指针随 O4 修正。**残留**：`summary.entries_note` 散文句仍称已入表"（17 条在线核验通过＋1 条 B 站降级）"（应 16＋2），且"3 条未采用"（应 4）并重复列出 BV12——见 §8 r1-O1 | ✓ 主要闭环＋1 条残留观察 |
| 联动核验（非本维度门槛，仅确认不影响 system） | ch02 L120 / ch03 L117 / ch03 L211 / ch04 L240 / 三章版本记录 | functional D1/D2、engineering D1/D4 修复面 | guard 116/nominal 13 句已按证据表述并引 `docs/evidence/camera_rgb565_timing_20261015_114913.json`（存在 ✓）；ch03 `drop_count` 三类枚举（含"围栏校验失败（坏帧）"）✓；ch03/ch04 资源表 URL 均为 `/wiki/先进先出算法` ✓；ch03/ch04 脚注归属改"知乎专栏"✓；三章各含"修订 r1"版本行 ✓ | ✓ 不影响 system |

## 4. 重验：路径、导航与模板（绑定 r1）

- **全量路径重扫**（README＋02/03/04；`../` 书目录基准＋项目根相对）：README 10/10（含同目录链接 6/6 目录相对命中）、ch02 11/11、ch03 10/10、ch04 7/7，共 **38/38 唯一路径记号可解析，0 悬空**。其中 ch02 新增两处均为根相对来源定位（F3 允许）：O1 全路径、证据 JSON `docs/evidence/camera_rgb565_timing_20261015_114913.json`（`Test-Path` ✓）。说明：`…init.v:232` 记号按"路径＋行号定位"语义核验（去掉 `:232` 后缀后文件存在；行号邻域实读见 §3）。
- **交叉引用重扫**：ch02 → {01, 02, 03, 09–11, 10}；ch03 → {01–02（脚注）, 02, 03, 12, 14, 15}；ch04 → {02, 03, 04, 07, 16–20, 18, 23}——全部落在冻结大纲 1–27/附录 90–92 内，修复面未引入越界编号。
- **模板与留痕**：三章各 14 个 `##` 级标题（9 个固定节＋5 个正文渐进节）、`<details>` 自测各 6 条、版本记录各 2 行（初稿 r0＋修订 r1）。
- **README 快照仍真实**：书目录 7 文件（01–04＋README/规范/大纲），05 起（含 90–92）无文件；README 未变 → r0 §3 结论复用成立。

## 5. 与"当前 FPGA 实际方案"对应复核（材料漂移后，r1 快照）

| # | 抽样项（章节陈述） | r1 时点来源现状 | 结果 |
|---|---|---|---|
| 1 | ch02 四轮余量账/77%/guard−0.477/nominal−0.177/差+0.300 | `docs/RGB565时序裕量优化_2026-10-15.md`（哈希未变） | 一致（r0 复用） |
| 2 | ch02 0.300=探索线、如实评定；对比主口径=nominal | decision-register **rev2** M1a L60（gate accepted=false、非强制门槛、不阻塞采纳）+ M5.5 L181（"1333/1600 对比口径=nominal"） | 一致（新快照下仍成立） |
| 3 | ch02 66/68 组人工复核；1600ctl 隔离工具版本；§1.4 PLL 3/80/2→666.67 | T01 dev-plan **新快照** `60ab21bd…` §1.11/§1.8/§1.4 对应锚点全部在场 | 一致 |
| 4 | ch02 M3 覆盖率 96.40%（route 97.75% 未解） | decision-register rev2 M3 行仍含 `96.40` | 一致 |
| 5 | ch02 白平衡 233658：setup −1.849/TNS −24.474 | `workflow/README.md`（哈希未变） | 一致（r0 复用） |
| 6 | ch03 帧槽四态/围栏/READING 保护/drop_count 三类 | `fpga/csi2/src/mem/ddr_frame_store.v`（哈希未变；三类枚举含围栏失败分支与 RTL L89 一致） | 一致 |
| 7 | ch03 异步 FIFO 258bit/属性/预取；手册 §10 与策略 §3/§8 引用 | RTL 与策略/手册（哈希未变） | 一致（r0 复用） |
| 8 | ch04 2,592,768=633×4096、payload 2,592,000、尾 640B | decision-register rev2 M2c L99 | 一致 |
| 9 | ch04 压缩 adapter 缺口/严格拒收/R10F 未冻结 | 整合文档、合同 §9/§10（哈希未变） | 一致（r0 复用） |
| 10 | （负例）三章是否预判 E2/频点结果 | 全章 grep「E2」＝**0 命中**；grep「裁定」＝0 命中 | 无冲突；未预判 |

- **修正 URL 实测（联网只读）**：`https://zh.wikipedia.org/wiki/先进先出算法` → 在线 ✓，落到计算机科学条目"先進先出演算法"（非会计条目），与 e11 登记及 ch03/ch04 资源表一致。
- 说明：本轮 decision-register（rev2）与 T01 dev-plan 为新快照属**并行线观测漂移**，r1 清单已按新值冻结；上表按 r1 值复核，未发现章节结论与 rev2 裁定冲突。

## 6. G 层记录（G0＋G1 适用；G2–G5 N/A）

| 层 | 结果 | 说明 |
|---|---|---|
| G0 任务/接口 | **pass** | 规范/大纲/模板冻结件与 r1 交付一致；修复面未越出授权面（最小面由 engineering 另验） |
| G1 静态核验 | **pass** | 清单 44/44 哈希一致（main-log 按 R1 语义）；路径 38/38；交叉引用全在范围内；O1–O4 定点闭环；对应复核无冲突 |
| G2 构建/实现 | not_applicable | 无综合/STA/构建对象（fpga-design-guide §6/§8） |
| G3 上板功能 | not_applicable | 无硬件候选、无位流、无板测对象 |
| G4 长稳/性能 | not_applicable | 无长稳对象 |
| G5 集成/发布 | not_applicable | 纯文档、无端到端集成、不涉及发布 |
| blocked | 无 | 未缺任何工具/设备/输入 |
| not_run | 无 | 本维度无"应跑未跑"项 |

## 7. 实际执行与原始证据（代表性；全部结论来自成功执行的命令）

工作目录＝PROJECT_ROOT；命令块退出码 0；本报告为唯一非空产物；执行时点 2026-10-17。

1. r1 manifest 自哈希＋45 条目全量重算（PowerShell `Get-FileHash`/JSON 驱动）→ §2 表（44/44 一致；main-log 追加型漂移 1/1）。
2. r0 资产保留复核：r0 manifest＝`b1e1dbdd…`、r0 system 报告＝`2d6f14d7…`（未被改写）。
3. 定点 grep：O1 全路径/旧裸写法 0 残留、行 232 邻域实读；ch03"同步器各打两级"、全库"rafter"仅版本记录 1 处；ch02"第 5 条"；ch03/ch04 新 URL 与脚注；三章"修订 r1"版本行；三章「E2/裁定」0 命中。
4. 路径重扫（README＋3 章，含目录相对兜底）→ 38/38；README 同目录链接 6/6。
5. 交叉引用重扫、模板节/`<details>`/版本行计数 → §4。
6. 书目录枚举 → 7 文件、05 起无文件；三章字节/CR 复核（29228/25709/23636；CR=0）。
7. 材料漂移复核：decision-register rev2（M1/M1a/M2c/M3/M5.5、96.40、nominal 口径）grep＋定点读；T01 dev-plan 新快照锚点 grep；新增证据 JSON `Test-Path`。
8. `webfetch` ×1（修正后 URL）→ 在线、条目正确（§5）。
9. 报告写入 `workflow/runs/20261017_162355_fpga_knowledge_book/test-reports/KB1-r1-system.md`（唯一写入）。
- 执行说明：其中一条组合命令因本环境权限被拒（未产生输出、无副作用），已改写为两条等价简化命令并成功执行；未列任何建议命令为"已执行"。

## 8. 观察项（非门槛；交原规划者分派）

- **r1-O1（新增，低危，记录级）**：`link-check-KB1.json` `summary.entries_note` 散文句仍与自身结构化字段不一致——句称已入表"（17 条在线核验通过＋1 条 B 站降级）"，正确应为"16 通过＋2 降级"（与 `proposed_states_used` 16/2/1/4 对照）；句称"3 条未采用"实为 4（cnblogs、B站 mismatch、2 条知乎），并以末项重复列出 BV12y4y1v7V3 使合计表面成立；`dev-notes-KB1.md` §8 第 5 项括注同样写作"17 通过＋1 降级"。**影响**：结构化字段、章节正文、manifest `link_check.notes` 均正确，章节资源表与用户侧不受影响；建议 engineering 在其复测中顺带最小面修正散文或明示"以 entries/结构化字段为准"。不构成 system FAIL。
- **O5（r0 遗留，维持）**：`_写作规范.md` §6 与 F4/R6 措辞张力——未改，dev-notes §8 已登记为规划层裁定项；本维度无新增要求。
- r0 O1–O4 全部闭环（§3）；r0 §8 其余结论由本报告取代（r0 报告原文保留）。

## 9. 未测项、下一动作与回退

- 未测（不适用/超范围）：真实用户点击行为（以结构检查＋路径解析等价覆盖）；外部链接长期稳定性（2026-10-17 时点；正式抽样归 engineering，本轮修正 URL 已由本维度实测）；B 站 2 条降级行（规则允许的降级，不判 FAIL 依据）；上板/接口/长稳（N/A，理由见 §6）。
- 硬件观察者/时间/位流身份：不适用——无硬件操作，本报告不含任何上板声明。
- 下一动作：system r1=PASS（本报告）→ 由主回原规划者登记；待 functional/engineering 于同一 r1 清单出裁定后，由规划者收尾（更新状态、按 R6 机制派发 KB2）；r1-O1 交 engineering 复测口径内处置，O5 由规划者裁定。
- 回退：未改任何文件；r0 清单/r0 三报告/r1 清单均保留；若任一输入再变，按新清单重新判定。

## 10. 复测元数据（供规划/主登记）

- required_dimensions：**[]**（本维度 r1 PASS，无待复测项；KB1 其余两维由各自 r0 测试者独立裁定）
- report_paths：本文件（`KB1-r1-system.md`）；关联 `KB1-r0-system.md`（r0 PASS 与 O1–O5 原记录，保留）
- input_status：**changed_vs_r0**（02/03/04 修订＋link-check/dev-notes 更新；README/规范/大纲/01 未变）——绑定 `KB1-manifest-r1.json`
- 复用裁定（一行）：README/规范/大纲/01 未变（哈希同 r0）→ r0 入口与恢复结论整节复用；三章与 link-check 修复面全部按 r1 文本定点重验＋全量路径/导航复扫，不复用 r0 章节正文结论
- blocked：无
