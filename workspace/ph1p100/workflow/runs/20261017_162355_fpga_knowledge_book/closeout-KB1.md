# closeout-KB1 — KB1 收束记录（run 20261017_162355_fpga_knowledge_book）

- 角色：fpga-planner（原规划者续接）；日期：2026-10-17；性质：中间收束（KB1 任务关闭 → 派发 KB2）。
- 依据：主 Agent 交回的 KB1 三维矩阵与报告路径/轮数；规划者已读取 r0-engineering/r0 简报、r1 三份报告、dev-notes-KB1、KB1-manifest-r1.json 与 `docs/知识书/` 现场文本（F1–F4 落地核验：大纲 L65=`理论峰值…`、规范 L22/L81/L100、README L99/L102 均已生效）。本文件为本轮收束的**权威裁定与交接记录**；dev-plan §11「KB1 收束」为其摘要。

## 1. 结果与证据

| 轮 | functional | engineering | system | 冻结输入 |
|---|---|---|---|---|
| r0 首次验收 | **FAIL**（`test-reports/KB1-r0-functional.md`，SHA=`ecfd48e4…`：ch02 计数反证、ch03 枚举不全） | **FAIL**（`KB1-r0-engineering.md`，SHA=`5c4c1c1f…`：D1 阻断=FIFO URL 落会计条目；D2–D6 其余） | PASS（`KB1-r0-system.md`，SHA=`2d6f14d7…`；O1–O5 非门槛） | `manifests/KB1-manifest.json`（SHA=`b1e1dbdd…44a2a8`） |
| 实际修复 1 轮 | — | — | 定点修复 D1–D6＋system 观察 O1/O2/O4 并入（O3 随 D2/D3 联动，O5 留规划层） | 新清单 `manifests/KB1-manifest-r1.json`（SHA256=`21759d7056119faeee5e1b8ee2fc46b3ba621cc60b3ebdf696950bee15190e5e`，21638B） |
| r1 复测/复用 | PASS（`KB1-r1-functional.md`，SHA=`9110d8fc…`；D1/D2 定点＋受影响重验＋实抓 1 条） | PASS（`KB1-r1-engineering.md`，SHA=`d9b0523e…`；D1 实抓复现、D2–D6 全过、写范围干净） | PASS（`KB1-r1-system.md`，SHA=`00cc29a9…`；复用裁定＋修复面全量重验 38/38 路径） | 同一 r1 清单（三维绑定一致） |

- r0 清单与 r0 三份报告原样保留；无覆盖/删除；写范围合规（README/规范/大纲/01 未在 r1 被触碰；r1 变更面=02/03/04＋link-check＋dev-notes）。
- 轮次统计（收尾口径）：首次三维同候选通过=0；**修复 1 轮通过=KB1**（累计 2 包：KB0、KB1）；修复 2/3 轮=0；⚠未通过=0；blocked=0。
- KB1 交付：第 02–04 章（238/242/268 行、UTF-8/LF、模板全节）＋F1–F4 有界修订（已在 KB1 内完成并被三维覆盖）；README 01–04 行/快照句已按 R6 更新（README 6321B→6814B）。

## 2. 裁定（R7–R11）

- **R7（O-r1-1，记录计数笔误）＝需修**：`link-check-KB1.json` `summary.entries_note` 与 `dev-notes-KB1.md` §8-5/§8 自检第 6 条的散文计数（"17＋1""3 条未采用""17/2/1/3"）与正确口径不符。**正确口径：23 条＝已入表 18（16 条在线核验通过＋2 条 B 站降级）＋未入表 1（Asynchronous circuit）＋未采用 4（cnblogs 404、B站 BV1yf4y1R7gH、知乎 p/95670435、知乎 p/21191014）**；机器字段（`proposed_states_used` 等）、章节资源表、manifest notes 均已正确。→ KB2 执行 **F6**（含 e11 标题注记并入）。
- **R8（system O5，规范 §6×R6 张力）＝需修**：`_写作规范.md` L82 仍写"不修改 README/规范/大纲（仅 KBZ 可终版）"，与 R6/F4 已生效的"各包有界更新 README 本包行"张力。→ KB2 执行 **F5**。
- **R9（functional O-r1-3）＝接受延后**：ch03 L34 示例数字的【本项目事实】标注粒度、L156"（D）"指代歧义——非门槛、可延后；本轮不设必须修订（KBZ 不触碰既有章；留未来自然修订）。
- **R10（"77%"口径）＝确认保留**：按来源（RGB565 文档）表述，直算 76.00% 已由开发登记；不修。
- **R11（B 站 2 条降级）＝确认允许**（环境限制＋精确检索词规则）；ch02 版本记录裸文件名＝工程维度判"记录性简写可接受"，不修。

## 3. KB2 有界修订清单（F5–F6；纳入 KB2 write scope 与 manifest/三维测试）

- **F5** `docs/知识书/_写作规范.md` §6（第 82 行，单处）：「不修改 `README.md`、`_写作规范.md`、`_全书大纲.md`（仅 KBZ 可终版）；不改其他包的章节文件。」→「不修改 `README.md`、`_写作规范.md`、`_全书大纲.md` 与其他包的章节文件；**唯一例外＝规划者授权的有界修订**（如 README 中本包章节的目录/进度行与"当前快照"句，见 `README.md`"维护规则"；终版复核归 KBZ）。」其余字节不动。
- **F6** 记录级（两文件，逐处最小面）：
  - (a) `workflow/runs/.../link-check-KB1.json` `summary.entries_note`：按"23＝入表 18（16 通过＋2 B 站降级）＋未入表 1＋未采用 4"改写；删除把 BV12y4y1v7V3 当额外降级项的重复叙述；改后须与 `proposed_states_used`（16/2/1/4）、`distinct_urls_used_in_tables`（18）、`shared_rows_note` 自洽，并 JSON 解析自检。
  - (b) 同文件 e11 `title_returned`：加"（重定向至先进先出演算法）"注记（同 e6 样式；依据 engineering r1 §3.1/R3、functional O-r1-4）。
  - (c) `workflow/runs/.../dev-notes-KB1.md`：§8-5"（17 通过＋1 降级）"→"（16＋2）"；§8 自检第 6 条"（17/2/1/3）"→"（16/2/1/4）"；相关"3 条未采用"→4；并在 §8 加一行「更正（KB2 轮，2026-10-17）：计数笔误已修，权威口径=本 run `KB1-r1-functional.md` §7 与 `KB1-r1-engineering.md` §4」。
- **影响声明**：F5/F6 均为文字/记录级；章节内容、资源行状态与用户面不受影响。KB1 的 r1 判定**继续绑定 `KB1-manifest-r1.json` 快照**；修订后的两文件由 KB2 manifest 重新冻结并登记为"修订 KB1 记录文件"（今后审计若复算 KB1-r1 清单，见本 drift 说明）。
- **命名澄清（供 KB2 及后续包）**：第 05–08 章题含空格（如"MIPI 与 CSI2 入门"）；按 `_写作规范.md` §1"不含空格"细则，文件名去空格：`05_MIPI与CSI2入门.md`、`06_相机配置与模式.md`、`07_CSI包与帧完整性.md`、`08_Bayer与颜色.md`；README 目录行链接须与实际文件名逐字一致（本澄清已知会 KB2 派发与测试）。

## 4. 输入漂移登记（供 KB2 与测试者对核）

- `dev-plan.md`：规划者本轮更新（§0/§4/§8/§11：KB1 done、KB2 ready、R7–R11、F5/F6）→ 新 SHA256(前16)=`834C60FEE1628E5A`（KB1-manifest-r1 内旧值不再代表现行文本；KB2 以新值为输入冻结）。
- `docs/知识书/`：01–04 章＋README/规范/大纲＝KB1 r1 冻结值（README/规范 F5 将变化）；05 起无文件。
- KB1 run 记录：`link-check-KB1.json`、`dev-notes-KB1.md` 将因 F6 变化（KB2 登记·见 §3）；`main-log.md` 滚动（R1）。
- 并行线快照：decision-register rev2、T01 dev-plan 新快照、tasks.json 新快照（KB1 r1 已按新值冻结，无冲突）。

## 5. 任务板与用户侧

- `workflow/tasks.json`：无本流条目（已核）；按 open-questions Q4 默认**不登记、未修改**。
- open-questions 4 项维持默认（节奏=全量顺序推进 → 派发 KB2；用户无新增原话）。

## 6. 下一动作

- **派发 KB2**（见 `dispatch.json`）：写作第 05–08 章 + 执行 F5/F6 有界修订 + README 05–08 行/快照句有界更新；输入含本文件、closeout-KB0、dev-plan（含 §11）、KB1 r1 资产与 KB1 笔记；主按固定分支新建 KB2 开发与三新测试。
- KB3–KBZ 状态不变（blocked，待前包 PASS 后逐包派发）。
