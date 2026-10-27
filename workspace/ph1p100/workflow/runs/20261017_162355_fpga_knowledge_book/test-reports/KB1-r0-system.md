### 判定：PASS

# KB1 系统维度测试报告（round 0）— 可用性与项目衔接

- task_id：KB1 ｜ dimension：system ｜ round：0（首次验收）
- project_root：`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道`
- 实际工作树/候选：PROJECT_ROOT 现场文本（只读核验；无 worktree、无构建/硬件候选）
- 唯一冻结依据：`workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB1-manifest.json`
  - 现场重算自身 SHA256 = `b1e1dbdd3efe7b7f9a3df95053b6cd9f594c39130fa11aba8e012110ca44a2a8`（15929B）＝派发给定值 ✓；JSON 解析正常（task=KB1、status=ready_for_test、outputs=8）
- 测试日期：2026-10-17 ｜ 测试者：system 维度全新独立会话（KB1-r0 首测；未派生任何子代理）
- 工具/版本：OpenCode read/grep/webfetch 工具；Windows PowerShell 5.1（Get-FileHash/Test-Path/正则只读扫描）；git status（只读）。未用 TD、未触碰板卡/位流、未下载、未发布、未发外部消息。
- 范围与 G 层（规划冻结）：system＝**可用性与项目衔接**——README 更新后作为入口仍可用（01–04 导航、快照句真实、维护规则可执行）；02–04 章可独立阅读理解、章节间衔接与"当前 FPGA 实际方案"对应成立；后续继续写作的恢复入口清晰；全章项目路径可解析。通过阈值（dev-plan §4 KB1 行 system 列）：导航与衔接无悬空、README 本包章节行更新正确、与冻结登记无冲突。**G0＋G1 适用；G2–G5 N/A**（fpga-design-guide §6/§8：纯文档交付，无构建/位流/长稳/集成对象）；**上板/接口/长稳类 N/A**（无硬件候选，纯文档任务）。
- 写范围合规：仅新建本报告；未修改/覆盖/删除任何输入、章节或既有文件。

## 1. 结论

**PASS**。冻结清单 41 条目哈希 40/40 一致（唯一漂移＝main-log.md 追加型滚动，符合 R1 语义，非缺陷）；README 作为书入口在三处 F4 更新后仍可用且快照句与磁盘事实一致；02–04 三章模板 10 节齐备、可独立阅读、章间"见第 N 章"全部落在冻结大纲 1–27/附录 90–92 内（无悬空）；与"当前 FPGA 实际方案"的抽样对核（M1/M2c/M3/M5.5、T02、策略 §3/§8、R10F 提案状态）未发现冲突或预判；项目路径 36/36 可解析；外部链接抽样 4/4 在线且标题一致；恢复入口（README→run 记录→dev-plan §4 KB2 行）清晰。另记录 5 条非门槛观察项（§8），交原规划者分派处理。

## 2. 冻结绑定与哈希核对（G1 基础）

方法：`Get-FileHash -Algorithm SHA256` 对 manifest 列出的全部条目现场重算（41 条＝dispatch_required 11＋run_state 5＋materials_read 17＋skill_and_contracts 4＋outputs 8），并逐条与记录值比对；`README.md`/`_写作规范.md`/`_全书大纲.md` 三条按 `modified_central_files.after_sha256`（修订后）核对（其 dispatch_required 登记值为修订前基线，属清单设计）。

| 分组 | 结果 |
|---|---|
| manifest 自身 | ✓ `b1e1dbdd…`（15929B，与派发给定一致） |
| dispatch_required（11） | ✓ 11/11 一致（含 3 条基线→修订后映射） |
| run_state（5） | ✓ 4/4 一致（dispatch/open-questions/link-check-KB0 及哈希值）；`main-log.md` 追加型漂移见下 |
| materials_read（17） | ✓ 17/17 一致（含 `workflow/tasks.json` `832a4b85…`、T01 证据 `7c633508…` 等） |
| skill_and_contracts（4） | ✓ 4/4 一致 |
| outputs（8） | ✓ 8/8 一致（02 `25ec18bc…`、03 `95d2dece…`、04 `4a895760…`、大纲 `bd266a6c…`、规范 `bbec84fd…`、README `3ae45f02…`、dev-notes `ffc65b0a…`、link-check `15290e00…`） |

- **唯一漂移**：`main-log.md`（现 `85918c8f…`/7033B；清单快照 `4d409c4b…`/6076B）。该条目清单内嵌语义"主代理滚动日志：冻结后继续追加属流程固有行为，复测仅核存在性/追加型新增"（closeout-KB0 R1）——按 R1 处置，**不判 FAIL**。
- 3 个中央文件修订后哈希与 `after_sha256` 及字节数一致（README 6814B／规范 8757B／大纲 15857B）；`01_从代码到电路.md` `f1651187…`＝KB0-r1 值未变。
- 说明：F1–F4 的**最小面/逆向重建差分**属 engineering 维度验收（KB0-r1 先例）；本维度只核"修订后现实与注册一致＋入口可用"，不作最小面断言。

## 3. README 入口可用性（F4 更新后，用户视角）

| 检查项 | 期望 | 实际 | 结果 |
|---|---|---|---|
| 01–04 目录行 | 链接＋状态"已交付" | L28–31 四行均为文件链接＋已交付；`Test-Path` 4/4 命中 | ✓ |
| 01 行口径 | "01 随 KB0"属实 | 01 章哈希＝KB0-r1 冻结值，closeout-KB0 判定 01 随 KB0 交付 | ✓ |
| 仅 01–04 已交付 | 05 起未写 | 书目录枚举：7 文件（01–04＋README＋规范＋大纲），05–27/90–92 均无文件；表内 05 起全部"待创建/未写" | ✓ |
| 当前快照句 | 与事实一致 | L22 "第 01–04 章已交付（01 随 KB0、02–04 随 KB1）；第 05 章起未写"——与上述枚举一致 | ✓ |
| 维护规则可执行 | 有界更新（R6）可执行 | L99/L102 两句均为"本包章节行＋快照句有界刷新、KBZ 终版复核"；与 closeout-KB0 §3 F4②④、dev-plan §11 R6 完全一致；指向的 run 目录存在 | ✓ |
| 两条阅读路线/附录预告 | 不误导 | "判决速查"称先查 `90_决策索引.md`（随收束包交付），附录表该行状态"未写"——未误导 | ✓ |
| 旧教材关系/路径 | 可解析 | `../../当前必读/01_FPGA主线学习手册_由浅入深.md` ✓（KB0 D1 修复保持）；`../../workflow/tasks.json`、`../../workflow/runs/20261017_162355_fpga_knowledge_book/` ✓ | ✓ |

结论：README 作为入口仍可用；本包章节行/快照句为**实时正确**，维护规则与 R6 一致且可执行。

## 4. 三章独立阅读、章间衔接与恢复入口

- **模板 10 节**：02/03/04 各含全部固定节（10 分钟速读卡／本章要回答的问题／与本项目方案的对应／决策点与判决框架／常见误区／自测题／延伸资源／术语增量／版本记录）＋正文 5 个渐进小节（直觉→原理→数字→硬件视角→本项目实例）；自测题各 6 条（折叠答案）。
- **章间衔接引用**（现场正则汇总）：
  - 第 02 章 → 第 01/03/09–11/10 章（`见第 N 章` 及范围式）；第 03 章 → 第 02/12/14/15 章；第 04 章 → 第 02/03/07/16/20/18/23 章。
  - 全部编号落在冻结大纲 1–27 与附录 90–92 内，**无悬空**；"第 01 章已建立'七站'与 G0–G5"经 01 章正文核验属实（L36/L137）。
- **资源/术语表可供 KBZ 汇总**：三章资源表 8/7/6 行、全部带核验状态字段；2 条降级行含精确检索词（ch02 L208/209）；共享条目（跨时钟域/CDC/先进先出）在相关章标注"共用"。
- **恢复入口清晰**：README L5/L98–102 → run 目录（现场存在：dev-plan、closeout-KB0、dispatch.json、open-questions.md、link-check、守护记录）→ `dev-plan.md` §4 KB2 行（blocked，待 KB1 PASS；写路径=05–08 章明确）＋ open-questions（4 项有默认、不阻塞）。后续包按同一模板/规范接续的条件齐备。
- **证据复用边界（相对 KB0-r1）**：README/规范/大纲已按 F1–F4 变更（哈希变），KB0-r1 对三者的旧结论**不复用**；01 章与背景输入哈希未变，其 KB0-r1 结论继续有效（本报告已按现盘点重扫相关引用）。

## 5. 与"当前 FPGA 实际方案"对应（抽样核验）

| # | 章节陈述（抽样） | 现场来源 | 结果 |
|---|---|---|---|
| 1 | ch02 四轮余量账 5.000−4.559−0.267−0.064−0.110=0.000；77% 布线 Net（3.465ns）、扇出 32、三级 LUT | `docs/RGB565时序裕量优化_2026-10-15.md` L9 | 一致 |
| 2 | ch02 114913 guard −0.477／nominal −0.177、差恰 +0.300、无位流 | 同上 L50/L52 | 一致 |
| 3 | ch02 66/68 组＋"禁止按文件现有组数自证完整"＋1600ctl 隔离工具版本＋0.300 为探索线非器件保证 | T01 run `dev-plan.md` §1.7/§1.8/§1.11 | 一致 |
| 4 | ch02 白平衡 233658 最终 STA setup −1.849／TNS −24.474 | `workflow/README.md` L3 | 一致 |
| 5 | ch02 HDMI 并行输入 STA 无违例但覆盖率 96.40%（route 97.75% 未解）；对比主口径=nominal | decision-register M3、M5.5、M1a | 一致 |
| 6 | ch02 PLL 配方 3/80/2→物理 CK ≈666.67MHz；1333 用户域 ≈166.7MHz/≈6ns | T01 run `dev-plan.md` §1.4 | 一致 |
| 7 | ch03 帧槽四态 FREE/WRITING/READY/READING；围栏读回后置 READY；只替换 READY、不覆盖 READING；ready 丢失→清槽+drop_count；无 flush 恢复需 drain/epoch adapter（当前无） | `fpga/csi2/src/mem/ddr_frame_store.v` 头注释/L20/L66–70/L111 | 一致 |
| 8 | ch03 异步 FIFO 数据宽 258bit（data+sideband）、`async_reg`/`dont_touch` 属性、读预取保持反压数据 | `fpga/csi2/src/mem/capture_async_fifo.v` L3/L4/L8/L14 | 一致 |
| 9 | ch03 相机不可反压→整帧无效+计数+新帧边界恢复；valid 不可等待 ready（手册原话）；加 FIFO 不解长期倒挂（策略 §8 停止条件 3） | `当前必读/01…` §10.1/§10.2；策略 L53/L207 | 一致 |
| 10 | ch04 2,592,768B＝633×4096＝128B 头＋2,592,000B 载荷＋640B 尾零；payload_bytes=2,592,000 | decision-register M2c | 一致 |
| 11 | ch04 压缩经 R10F 必须补 adapter（不能只改 codec_id）；严格拒收为接入必补项；CRC 通过≠可发布 | 整合文档 §3.1/§3.2；M2c 重开触发① | 一致 |
| 12 | ch04 R10F 为提案、未与队友冻结（字段/长度口径提案级） | `parallel/docs/帧与元数据接口合同_2026-10-15.md` §9/§10 | 一致 |
| 13 | ch03 证据边界：丢帧率/高水位/恢复行为待板测（T02 awaiting_hardware） | `workflow/records/T02/task.md` L16 | 一致 |

- 覆盖 M1/M2c/M3/M5.5 与 T02/策略/合同冻结登记；**未发现章节结论与冻结登记冲突**；章节未预判 E2 结果与频点终选（ch02 明确"由频点决策走（第 10 章）"）。
- 其余数字（CRC32 标准值 0xCBF43926、36+P/774→800B 等）的逐一复算与决策卡四要素核验归 functional 维度；本维度只核"引用路径存在＋表述与其来源文件当前状态一致"。

## 6. 路径与外部链接核验（系统口径）

- **全章路径扫描**（README＋02/03/04；围栏/反引号与行内引用语义）：共 **36 个唯一路径记号**（`../` 书目录基准 24 个＋根相对 12 个），**36/36 可解析，0 断链**；README 同目录链接 6 条（01–04、大纲、规范）全部命中。示例：`../../workflow/runs/20261017_161109_decisions_compare_freeze/decision-register.md`、`fpga/csi2/src/mem/ddr_frame_store.v`、`../../parallel/docs/帧与元数据接口合同_2026-10-15.md` 等均存在。
- **外部链接抽样（联网只读实测，2026-10-17）**：4/4 在线且标题一致——`zh.wikipedia.org/wiki/静态时序分析`（ch02 第 1 条）、`en.wikipedia.org/wiki/Cyclic_redundancy_check`（ch04 第 4 条）、`runoob.com/w3cnote/verilog-fsm.html`（ch03 第 7 条，返回"6.3 Verilog 状态机"）、`en.wikipedia.org/wiki/Asynchronous_circuit`（link-check 登记项）。正式抽样复现归 engineering；本维度量属规则允许的抽样核验。
- 2 条 B 站降级行按《fpga-design-guide §5》含精确检索词（已现场确认字段存在），未联网复验——按规则不作 FAIL 依据。

## 7. G 层记录（G0＋G1 适用；G2–G5 N/A）

| 层 | 结果 | 说明 |
|---|---|---|
| G0 任务/接口 | **pass** | 规范/大纲/模板冻结件与 KB1 交付一致；F1–F4 修订后哈希与注册一致（§2） |
| G1 静态核验 | **pass** | 清单 40/40 哈希一致（main-log 按 R1 语义）；路径 36/36；链接抽样 4/4；导航/衔接/恢复入口核验通过 |
| G2 构建/实现 | not_applicable | 无综合/STA/构建对象（fpga-design-guide §6/§8 规划理由） |
| G3 上板功能 | not_applicable | 无硬件候选、无位流、无板测对象 |
| G4 长稳/性能 | not_applicable | 无长稳对象 |
| G5 集成/发布 | not_applicable | 纯文档、无端到端集成、不涉及发布 |
| blocked | 无 | 未缺任何工具/设备/输入 |
| not_run | 无 | 本维度无"应跑未跑"项 |

## 8. 观察项（非门槛；交原规划者分派）

| 编号 | 位置 | 事实（可复现） | 影响/建议归属 |
|---|---|---|---|
| O1 | `docs/知识书/02_时钟复位与余量.md` L123 | 厂商 IP 定位说明写作 `` `ph1p_ddrphy_dram_init.v:232` ``＝**裸文件名＋行号**；该文件在项目内存在（如 `fpga/csi2/prj/ddr_frame_probe/vendor/ip/ddrmc_x32/src/rtl/init/ph1p_ddrphy_dram_init.v`），完整路径见被引 RGB565 文档 L11；但该写法不能按 F3 允许形式（根相对/书目录相对）直接解析 | 低危。dev-notes §5 声称"KB1 新增引用全部解析通过（11 处非解析项均为 KB0 基线）"——本条疑似 KB1 新增，建议 engineering 在其路径全量扫描中一并分类核实 |
| O2 | `docs/知识书/03_流水线与交接.md` L85 | "写指针/读指针先转格雷码，分别用**两组 rafter** 两级同步"——"rafter"为无义残字（疑编辑残留），语句主张本身（两组指针各两级同步）与代码一致 | 低危文字缺陷。建议下一次自然修订轮（或 KBZ 复核时）最小面修正；是否计入本包修复由规划者按工程/功能维度结论裁定 |
| O3 | `workflow/runs/…/link-check-KB1.json` 第 36 行条目（Asynchronous circuit） | 该条目 `proposed_state="在线核验通过"`（URL 现场复核 2026-10-17 在线、标题一致），但 note 声称"第 02/03 章延伸资源共用"——该链接**不在任何章节资源表中**（02/03 表各 8/7 行，均无此行）；同文件 summary 句"表行合计 21 = 16 条不重复 URL + 1 条重复计入"算式不成立（现行正确账目：21＝2 条 B 站降级＋16 条核验通过唯一 URL＋3 条共享重复计入〔跨时钟域、CDC、先进先出〕） | 低危记录级不一致；**章节本身与 per-chapter 计数、manifest 摘要一致**。URL 真实无虚构；正式分类（链接记录规范/无虚构）归 engineering、functional 复核 |
| O4 | `docs/知识书/02_时钟复位与余量.md` L28 | "异步电路…存在但工程上少用（见 `延伸资源` 第 4 条）"——现第 4 条为 CDC（英文）条目；与所述最贴合的是第 5 条"同步电路"或 link-check 中登记未入表的 Asynchronous-circuit 条目 | 低危指针疑似陈旧（或与 O3 同源的草稿化变动）；不阻塞理解（第 3–5 条均可提供 CDC/同步-异步背景） |
| O5 | `workflow/runs/…/dev-notes-KB1.md` §2 表 | `link-check-KB1.json` 记为 "10418B"，manifest/实际为 **10604B**（哈希一致） | 低危记录陈旧。建议 KBZ 或下一修订轮对齐；不影响本判定 |

- 以上 5 项均不属本维度规划门槛（导航/衔接/对应/恢复/路径解析），故不构成 FAIL；O1/O3 建议优先交 engineering 在其结论中处置，O2/O4/O5 可并入下一次自然修订。

## 9. 实际执行与原始证据（代表性；全部为实际运行）

工作目录＝PROJECT_ROOT；全部命令块退出码 0；本报告为唯一非空产物；执行时点 2026-10-17。

1. manifest 全量哈希核对（PowerShell `Get-FileHash` 驱动，41 条目）→ §2 表（40/40 一致；main-log 追加型漂移 1/1）。原始输出：逐条 `hash|bytes|path` 列表。
2. 路径提取＋`Test-Path` 扫描（README/02/03/04，围栏语义，书目录基准＋项目根兜底）→ 36/36 命中；同目录链接 6/6。
3. 交叉引用扫描（`见第 N 章`/`第 N–M 章` 正则）→ 编号全部落于 1–27/90–92。
4. 模板节/资源行计数（`^## ` 与资源表行正则）→ 9 固定节齐全×3；资源行 8/7/6；自测 6/6/6。
5. 目录枚举（`Get-ChildItem` 知识书目录/run 目录/test-reports）→ 05 起无文件；run 记录与 6 份 KB0 报告保留。
6. grep 系列（ch01 七站/G0–G5、decision-register M1/M2c/M3/M5.5、T02 task、策略 §3/§8、ddr_frame_store/capture_async_fifo、T01 §1.4/§1.7/§1.8/§1.11、RGB565 数字、合同 §9/§10、O1 文件存在性搜索）→ 逐项命中。
7. `webfetch` ×4（只读 GET）→ 4/4 在线、标题一致（§6）。
8. `git status --porcelain`（只读）→ 全库存在并行线（T01/PCIe 等）独立增改与 `docs/知识书/` 未跟踪目录，属本包范围之外；本报告不据此判越界（越界/最小面判定归 engineering）。
9. 报告写入 `workflow/runs/20261017_162355_fpga_knowledge_book/test-reports/KB1-r0-system.md`（唯一写入）。
- 未运行项：无——本报告未列任何建议命令为"已执行"；板测/构建命令本维度 N/A。

## 10. 未测项、下一动作与回退

- 未测（不适用/超范围）：真实用户点击行为（以结构检查＋路径解析等价覆盖）；外部链接长期稳定性（2026-10-17 时点快照；正式抽样归 engineering）；B 站抓取复验（降级规则允许，不判 FAIL）；上板/接口/长稳（N/A，理由见 §7）。
- 硬件观察者/时间/位流身份：不适用——本任务无硬件操作，本报告不含任何上板声明。
- 下一动作：本报告 system=PASS → 主回原规划者登记；待 functional/engineering 于同一 KB1 清单出判定后，由规划者按 dev-plan 收尾并按 R6 机制更新状态/派发 KB2。观察项 O1–O5 交原规划者分派（O1/O3 建议 engineering 复核；O2/O4/O5 建议并入下一次自然修订）。
- 回退：未改任何文件；全部原始输入保持冻结；若任一输入变化，按新 manifest 重新判定。

## 11. 复测元数据（供规划/主登记）

- required_dimensions：**[]**（本维度 r0 PASS，无需复测；KB1 其余两维由各自测试者独立判定）
- report_paths：本文件（`KB1-r0-system.md`）
- input_status：**initial_freeze_for_KB1**（相对 KB0-r1：新增 02–04 三章＋F1–F4 中央文件修订＋本 run 记录）
- 证据复用依据：KB0-r1 结论仅对未变文件（01 章、背景输入、技能锚）继续有效并借由哈希一致复用；对 F1–F4 变更的三个中央文件不复用旧结论（§2/§4）
- blocked：无
