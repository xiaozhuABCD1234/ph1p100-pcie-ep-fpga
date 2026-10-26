### 判定：PASS

- task_id：KB2；dimension：system（上板与系统，本包收敛为"可用性与项目衔接"）；round：r0（首轮）。
- 被验对象/工作树：项目根 `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道`（git HEAD=`ba0fca5`；`docs/知识书/` 与本次 run 目录均未跟踪，无提交差异可引用，一律按冻结哈希核验）。
- 冻结输入清单：`workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB2-manifest.json`；测试者现场重算 SHA256=`b8595734be7c0bb5f62383080e6134c53e8b683e2057d07ce3745bdd9a48cbe2`（与派发给定值逐字符一致）。
- 工具版本：OpenCode 会话联网工具（webfetch 直取页面/JSON，含 B 站公开 API）；PowerShell 5.1.26100.9711（Get-FileHash / ConvertFrom-Json / Invoke-WebRequest -Method Head）；文件系统只读扫描与正则提取为本机脚本。
- 本报告是本次测试中唯一写入的文件；未修改任何被验输入或既有文件。

## 1. 本任务范围、必需 G 层与通过阈值

- 规划者限定范围（勿越界）：以用户视角核验——① README 更新后入口与 05–08 导航可用；② "当前快照"句与磁盘事实一致（01–08 存在、09 起未写）；③ 维护规则可执行；④ 05–08 章可独立阅读、章节间与前后包衔接、与"当前 FPGA 实际方案"对应成立；⑤ 后续写作恢复入口清晰（README→run 记录→dev-plan 下一包行）；⑥ 全章项目路径与交叉引用可解析、无悬空。
- 必要 G 层：**G0+G1 适用**；**G2–G5 不适用**（理由=纯文档交付：无综合/STA、无位流/板测、无长稳、无端到端集成对象；见 run `fpga-design-guide.md` §8 与 §6 之 system 行）。
- 通过阈值：上述①–⑥全部满足。悬空路径、导航错误、快照句与事实不符均为门槛性缺陷。上板/接口/长稳类整体 N/A（无硬件候选、无位流、无长稳对象），不启动板测或无关工具。

## 2. 实测命令与结果（工作目录＝项目根；退出码均 0，除非另注）

### 2.1 冻结界面校验（G1，现场重算）

| 对象 | 清单登记值 | 现场重算 | 结论 |
|---|---|---|---|
| KB2-manifest.json 自身 | 派发给定 `b8595734…48cbe2`（清单不自含） | `b8595734be7c0bb5f62383080e6134c53e8b683e2057d07ce3745bdd9a48cbe2` | 一致 |
| 05–08 四章 | `bba84c1e…` / `cb47ad5c…` / `0fd840cb…` / `cd5e1902…` | 逐字节一致（21644/23907/21108/20737 B） | 一致 |
| README.md（R6 后） | `4e779f62…`（判 7018B） | 一致；修订前基线 `3ae45f02…`（6814B）与清单 before 值一致 | 一致 |
| _写作规范.md（F5 后） | `d66e99ca…`（8906B） | 一致；before `bbec84fd…`（8757B）与 KB1-r1 值一致 | 一致 |
| link-check-KB1.json（F6a/b） | `1a262273…`（12023B） | 一致；JSON 可解析、23 条；entries_note=「入表 18（16 通过＋2 降级）＋未入表 1＋未采用 4」；e11 标题含「（重定向至先进先出算法）」 | 一致 |
| dev-notes-KB1.md（F6c） | `e724235e…`（20406B） | 一致；含「更正（KB2 轮，2026-10-17）」行与「16/2/1/4」计数 | 一致 |
| link-check-KB2.json / dev-notes-KB2.md | `15abd6ed…` / `5d66fada…` | 一致 | 一致 |
| 未变文件 `_全书大纲.md`、01–04 章 | KB1-r1 冻结值 | 逐字节一致（after=before） | 一致 |

另核实：requirement.md、dev-plan.md、input-index.md、fpga-design-guide.md、closeout-KB0/1.md、KB0/KB1-manifest-r1.json 均与清单登记一致。

### 2.2 README 入口与 05–08 导航（G1）

- 提取 README 全部 Markdown 链接（11 个）逐一 `Test-Path`：01–08 章、_全书大纲.md、_写作规范.md 全部存在；05–08 行链接目标与实际文件名逐字一致（`05_MIPI与CSI2入门.md` 等），状态列＝"已交付"。
- README 中 3 条反引号路径引用（`../../workflow/tasks.json`、`../../workflow/runs/20261017_162355_fpga_knowledge_book/`、`../../当前必读/01_FPGA主线学习手册_由浅入深.md`）均可从 `docs/知识书/` 解析。
- 结论：入口与 05–08 导航可用。

### 2.3 "当前快照"句与磁盘事实（G1）

- README 第 22 行：`当前快照：第 01–08 章已交付（01 随 KB0、02–04 随 KB1、05–08 随 KB2）；第 09 章起未写。`
- 磁盘实测：`docs/知识书/` 仅含 README、规范、大纲与 01–08 章；抽查 `09_DDR基础.md`、`27_如何做出自己的判决.md`、`90_决策索引.md` 均不存在 → 与快照句一致。
- 包归属（01/KB0、02–04/KB1、05–08/KB2）与 dev-plan §0/§4 记录一致。

### 2.4 维护规则可执行性与恢复入口（G1）

- README"维护规则"（行 96–102）：各写作包可有界更新本包章节行＋"当前快照"句、其余不得修改、KBZ 终版复核、冻结后按下一次修订轮留痕、进度快照以 run 内记录为准——与 `_写作规范.md` §6（F5 修订后：唯一例外＝规划者授权的有界修订，指向 README"维护规则"）互洽，无矛盾。
- 恢复入口可用：README 行 5/102 指向本 run 目录 → 该目录含 `dev-plan.md`（§4 KB3 行状态 blocked、"下一动作=待 KB2 PASS"；§3 含 09–12 章大纲行）→ 后续包 KB3 写作入口清楚。
- 结论：维护规则可执行、恢复入口清晰。

### 2.5 全章项目路径与交叉引用（G1）

- 对 05–08 四章做相对路径提取（`../` 系），共 26 个唯一 token（含 1 个目录引用与 link-check-KB2.json）：逐个 `Test-Path` 全部可解析；`fpga/csi2/prj/…/mipi_csi_2/` 目录及其三个对齐模块、camera_startup.v、ui_i2c.v、bayer565/332_capture.v、csi_rx_packet_integrity.v、gray_frame_pack_guarded.v、ddr_frame_store.v 全部存在。**无悬空路径**。
- 交叉引用扫描："第 N 章"式引用 N∈{04,05,06,07,08,12,13,25,26}（含 05–07、13–15、07/08 等区间写法），全部在 27 章规划内且语义与 `_全书大纲.md` 对应章题一致（如"见第 12 章"对应帧缓存与队列、"第 26 章方法论"对应工程方法与证据判读）；四章均无"（待写）"标记（符合收束裁定 R2）。
- 四章 H1 章题与 README/大纲三处一致（05 MIPI 与 CSI2 入门 / 06 相机配置与模式 / 07 CSI 包与帧完整性 / 08 Bayer 与颜色）。

### 2.6 与"当前 FPGA 实际方案"对应（抽样，G1）

以用户视角抽查每章核心"本项目"陈述与其引用源一致性：

- 05 章：软 PHY 路线与"无硬 D-PHY 证据"链——F9P 核验的 `TVS*1` 对比 `MIPI DPHY*2`（PH1P35/PH1P50MEG324A）、DS1300_1.2.1 表 1-1 "－"、I/O `286(137)/0/0/0`、VID006 目标器件 DR1M90GEG400、HR IDELAY 8bit/256 step/5–13ps/不支持级联、≤1250Mbps＋IBIS 前置——与 `docs/F9P_PH1P100_硬D-PHY例程专项核验_2026-10-10.md`、`docs/PH1P100_接收路线证据.md` 逐项一致。
- 06 章：现役档位=全像素 RAW10/4 lane/891Mbps/27MHz/30fps（用户已批准）、HMAX/VMAX 三档实算、300B=0xA0、SHR0=0x66、PLL 首检 74.166667/370.833333/26.969697 拒绝接入、RAW12 封存——与 `docs/RAW10稳定档位_PLL生成与接入交接.md`、`docs/IMX415_首版模式与寄存器差异.md`、`docs/RAW10_PLL生成首次检查_2026-10-10.md`、`workflow/records/T02/task.md` 一致。
- 07 章：CRC16 init 0xFFFF/反射多项式 0x8408/无最终异或、"4 发布/7 ABORT/8 丢帧"不可相加、`IMAGE_WC=0` 宽松几何、222159 出图与 T02 边界——与 `docs/CSI帧完整性_实现与验证_2026-10-12.md` §2/§3/§4、`docs/CSI前端尾拍误判修复_2026-10-12.md` 一致；`workflow/tasks.json` 中 T02 state=`awaiting_hardware`、status_note 与章节表述一致。
- 08 章：相位 3（GBRG）统计支持（0.0723%、1.256504/0.917100）、Q10 2400/2062、黑电平 50 标称、002820 STA 与 G3 未测——与 `docs/RGB565白平衡闭环_2026-10-14.md`、`docs/RGB565玫红返工_接收Bayer相位核对_2026-10-14.md` 一致；正式 ROI 表述与 `docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md` §3（禁止预览插值冒充 1080p）一致。
- 结论：四章主题（MIPI/CSI-2 链路、相机模式、帧完整性、Bayer 颜色）与项目实际方案对应成立；未发现与 T02/策略文档/冻结登记的冲突。

### 2.7 链接可用性抽样复现（G1，本会话实际请求）

优先项（Wikipedia/MIPI/Sony/pedestrian/B 站）复现结果均与 `link-check-KB2.json` 登记一致：

| URL | 复现结果 | 登记值比对 |
|---|---|---|
| mipi.org/specifications/csi-2 | 返回标题 `Camera Serial Interface 2 (MIPI CSI-2) \| MIPI` | 一致 |
| en.wikipedia.org/wiki/MIPI_Alliance | `MIPI Alliance - Wikipedia` | 一致 |
| sony-semicon.com/…/security/security.html | `Security Camera Image Sensor [Product] \| …` | 一致 |
| pedestrian.com.cn/embedded/video/mipi_csi.html | `8.8.3. MIPI CSI传输协议解析 — ywg_dev_doc 0.1 文档` | 一致 |
| api.bilibili.com/x/web-interface/view?bvid=BV188411o7bL | 标题="MIPI CSI-2 协议学习以及FPGA开源代码介绍（视频提到的工程和文档都开源）"、UP=想摸鱼的皮卡丘、时长 1910s≈31:50 | 与登记的 API 实抓一致 |
| Sony Flyer PDF、Radxa 手册镜像（HEAD） | HTTP 200 + `application/pdf` | 与登记"可达（工具不解析正文）"一致 |

- B 站 3 条按规则降级（环境限制＋精确检索词，身份经 API 实抓）符合 `fpga-design-guide.md` §5 与清单 environment_note，**不因未在线核验判 FAIL**；本轮混样复现其中 1 条亦成功。
- 其余条目按抽样规则未逐条复现；全部 34 条记录（含 11 条未入表/未采用）在 `link-check-KB2.json` 可查、字段齐。

## 3. G 层逐层记录

| 层 | 结果 | 依据 |
|---|---|---|
| G0（规范/大纲/模板冻结=接口） | **pass** | 章题/Part 归属与 `_全书大纲.md`、README、dev-plan §3 三处一致；F5 修订面＝规范 §6 单处且引用 README 维护规则 |
| G1（静态/离线核验） | **pass** | 2.1–2.7：哈希、导航、快照、维护规则/恢复入口、路径、交叉引用、链接抽样全部通过 |
| G2（综合） | not_applicable | 纯文档交付，无 RTL/构建对象（规划者先前限定） |
| G3（STA/时序） | not_applicable | 同上；本包无位流、无时序对象 |
| G4（板测/长稳） | not_applicable | 无硬件候选、无位流、无长稳对象；未启动板测 |
| G5（端到端系统） | not_applicable | 纯文档交付，无整机集成对象 |

## 4. 观察项（非门槛，不影响判定）

- O1（措辞）：07 章行 101 标注"（项目根相对路径）"，实际写法为 `../../fpga/…`（书目录相对，符合 `_写作规范` §1 与 R5 的"`../` 规则"）；路径可解析，仅标签与写法不完全对应。
- O2（风格）：05 章行 182 交叉引用写作"（第 26 章方法论）"未带"见"字，与 §8 自检"只写'见第 N 章'"的字面略有出入；指向章号在规划内、语义正确。
- O3（时点性）：外部链接与 Sony 页面结构属 2026-10-17 快照；本轮复现正常，未来失效按维护规则走下一次修订轮。
- 以上均非悬空/误导性缺陷，不构成修复要求。

## 5. 新旧输入差异、证据复用与对其他维度的影响

- 相对 KB1-r1 冻结：新增 05–08 四章；README 有界修订（R6：4 行章节行＋1 快照句，+204B，行数不变）；`_写作规范.md` F5 单处；`link-check-KB1.json`/`dev-notes-KB1.md` F6 记录级；本 run 新增 KB2 三个文件。`_全书大纲.md` 与 01–04 章哈希未变（after=before），其 KB1-r1 结论继续绑定 `KB1-manifest-r1.json`，本维度不重新裁定其内容。
- 证据复用：本报告全部结论绑定 KB2 清单现场重算哈希；未复用 KB1 报告结论来替代本包核验（仅将"未变文件哈希一致"用作其结论仍有效的依据）。
- 共享面影响：README 为跨包共享文件，R6 更新改变后续包（KB3–KBZ）进度刷新方式——与本报告 2.4 一致；F5 改变未来包对"有界修订"规范的引用口径。对 functional/engineering 维度无接口性影响（两者分别覆盖内容与结构/来源面）；若其判定 FAIL 触发修复轮，凡触及 README/规范/章节文本，本维度按复测清单重验对应项。

## 6. 上板类说明、未测项、下一动作与回退

- 本包无任何硬件证据、无候选位流、无真实硬件观察者与时间戳（纯离线文档任务）；G2–G5 按规划不适用，未启动板测、未使用 TD/下载/Flash/外部消息。
- 未测项：本维度范围外（内容正确性、编码/LF、模板十节、F5/F6 逐字节最小面）由 functional/engineering 维度裁定；全书级判读示例问题（DDR1600/1333/800E）需待第 09–10 章（KB3）与附录 90（KBZ）后成立，不构成本包门槛。
- 下一动作：三维同候选 PASS → 交原规划者收束并派发 KB3；若本维度之外有 FAIL，修复轮由授权测试者续测，本报告保留现状、其结论仅绑定本清单。
- 回退：本包为文档资产；如需回退按"下一次修订轮＋版本记录留痕"执行，不修改既有 01–04 章与 KB1-r1 资产。
