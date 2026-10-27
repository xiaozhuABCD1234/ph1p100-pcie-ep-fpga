### 判定：PASS

# KB2 — 时序与工程维度测试报告（round0）

- task_id：KB2；dimension：engineering（结构与来源可核验）；round：0（首次验收）。
- 实际工作树/候选：项目根工作树现场只读核验（`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道`）；被验对象＝冻结文件集本身，无独立构建目录。
- 冻结输入 manifest：`workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB2-manifest.json`；现场重算 SHA256=`b8595734be7c0bb5f62383080e6134c53e8b683e2057d07ce3745bdd9a48cbe2`，与派发值一致。
- 工具/版本：Windows PowerShell 5.1.26100.9711（`Get-FileHash` SHA256、.NET `[IO.File]` 逐字节统计、`ConvertFrom-Json`）；会话联网工具（webfetch/google_search 直取，仅用于链接状态抽样）。日期：2026-10-17。
- 测试者说明：全新会话独立第三方；只读核验，未修改任何输入与既有文件；本文件为本次唯一写入。

## 1. 本维度范围、必需 G 层与通过阈值

- 范围（规划者冻结，勿越界）：① KB2 manifest 自洽与文件哈希一致性（10/10 输出复核）；② F5/F6/README 修订面合规（仅允许处、前后哈希匹配、逐处最小面）；③ 写范围合规（除写范围外零写）；④ 书目录文件集与命名（05–08 与 README 链接逐字一致）；⑤ 格式（UTF-8 无 BOM/纯 LF/模板 10 节）；⑥ `link-check-KB2.json` 记录可信与计数自洽；⑦ 链接核验可复现性抽样。
- 依据：`dev-plan.md` §4 KB2 行（允许写路径/engineering 验收列）、`fpga-design-guide.md` §5–§8、规划者派发范围。
- G 层逐层：**G0＝pass**（规范/大纲/模板冻结，manifest 绑定）；**G1＝pass**（静态/离线核验已执行，见 §2）；**G2/G3/G4/G5＝not_applicable**（纯文档交付：无综合/STA、无位流/板测、无长稳、无端到端集成对象；引用 `fpga-design-guide.md` §8 与 §6 表"时序/CDC/资源类检查=不适用"）。本维度 STA/CDC/资源/构建类检查不适用，未启动 TD 或任何工程工具、未提供替代命令（规划已冻结 N/A，无"建议执行"项）。
- 通过阈值：manifest 哈希全一致且无未声明漂移；F5/F6/R6 修订面可逐处复算且最小；写范围零越界；目录/命名/格式/记录自洽；`在线核验通过`行抽样可复现、`无法在线核验`行有精确检索词。

## 2. 检查结果明细（实测）

以下均为只读命令，退出码 0；无失败项。

### 2.1 manifest 自洽与文件哈希一致性

- manifest 自身：现场重算=b8595734…cbe2 ✓（且=派发值）。
- 清单内全部 64 条（inputs 54＋outputs 10）逐条复算：**61 条一致、0 缺失、3 条 DIFF 且均为清单已声明语义**：
  - `docs/知识书/README.md`：磁盘=4e779f62…（=清单声明的 R6 after 值；inputs 登记的是修订前基线 3ae45f02…，符合 `baseline_note`）；
  - `docs/知识书/_写作规范.md`：磁盘=d66e99ca…（=声明的 F5 after 值；inputs 登记修订前 bbec84fd…，符合 `baseline_note`）；
  - `main-log.md`：冻结时点 11079B/888968ec…；现场 12149B/d3e66196…，**前 11079 字节 SHA256=888968ec…与冻结值逐字节一致 → 追加型滚动**（R1 语义满足）。
- **10/10 输出哈希复核全部通过**（四章、规范、README、link-check-KB1、dev-notes-KB1、link-check-KB2、dev-notes-KB2），字节数亦逐条一致。
- 清单自洽：`modified_central_files`（4 项）after 值 ∈ outputs；`retest.changed_entries`（10 项）与 outputs 集合一致；`unchanged_entries`（大纲＋01–04）哈希现场复算均未变；`manifest.link_check.summary` 与 `link-check-KB2.json` 的 summary 逐字段一致（attempted/pass/distinct/分章/unused）。
- `self_check` 声明抽验均命中：行数 218/235/214/216、自测题 `<details>` 各 6 条、编码/LF 见 §2.5、路径扫描见 §2.7。

### 2.2 F5（`_写作规范.md` §6 单处）

- 修订前/后哈希：before=`bbec84fd…`（＝KB1-manifest-r1.json 登记的 r1 冻结值，∈ 该清单 46 路径集合）✓；after=d66e99ca…＝磁盘＝KB2 清单 ✓。
- 最小面逐处复算：closeout-KB1 §3 引文的旧文=122B、新文=271B，**Δ=+149B**；文件字节差 8906−8757=**+149B**，完全吻合 → 仅该单处改写。
- 第 82 行现场文本 = `- ` + 新文（全等）；旧文全文件 **0 残留**；行数 103 不变 ✓。

### 2.3 R6（README 05–08 行＋"当前快照"句）

- before=`3ae45f02…`（∈ KB1-r1 登记）✓；after=4e779f62…＝磁盘＝清单 ✓。
- 最小面重构：4 行章节行（现为文件链接＋`已交付`）Δ=44+52+52+38=**186B**；快照句 before→after（清单引文）Δ=**+18B**；合计 **+204B**=文件字节差 7018−6814=**+204B**，完全吻合。
- 快照句新文在文件内命中、旧文 0 残留（`**` 标记剥离后比较）；行数 114 不变 ✓。

### 2.4 F6（记录级，两文件三处）

- F6a/F6b `link-check-KB1.json`：before=e4f52bdf…（∈ KB1-r1 登记）✓；after=1a262273…＝磁盘＝清单（12030→12023B，**净 −7B**，与"entries_note 改写缩句＋e11 注记加长"组合一致；旧文本未另存，无法逐字节重构净差，以哈希绑定＋下述内容核验为据）。JSON 可解析、**23 条**、8 字段 **0 缺失**；`summary.entries_note` 现文="23 条=入表 18（16 条在线核验通过+2 条 B 站降级；表行 21=18 条不重复 URL+3 条跨章共享）＋未入表 1＋未采用 4"，与 `proposed_states_used`=16/2/1/4、`distinct_urls_used_in_tables`=18、`shared_rows_note`=21=18+3 **全部自洽**；重复降级叙述中的 `BV12…` 已从 entries_note 清除。e11 `title_returned` 含"（重定向至先进先出演算法）"，与 e6 款式一致；且为"在线核验通过"状态，非降级项。
- F6c `dev-notes-KB1.md`：before=57345cfd…（∈ KB1-r1 登记）✓；after=e724235e…＝磁盘＝清单（20204→20406B）；**新增"更正（KB2 轮）"行 201B＋LF=+202B=声明字节差**，完全吻合 → 两处计数更正为等长替换。现场核验：§8-5 显示"（16 通过＋2 降级）"与"＋4 条未采用"、§8 自检第 6 条"（16/2/1/4）"；旧计数模式（"17 通过"、"（17＋1）"、"（17/2/1/3）"、"3 条未采用"）在两文件 **0 残留**；行数 140（+1）✓。

### 2.5 写范围合规（除写范围外零写）

- 对 `KB1-manifest-r1.json` 全部 46 个唯一路径现场复算：37 一致；9 差异中 **7 个为本包声明面**（F5、R6、F6ab、F6c、dev-plan 规划者本轮更新、dispatch KB2 派发版、main-log 追加型），**2 个为并行线文件**（`workflow/runs/20261017_153201_T01_ddr1333_integration/dev-plan.md`、`workflow/runs/20261017_161109_decisions_compare_freeze/decision-register.md`）。
- 并行线两点归因（只读证据下的合理推断，不作为本包违规）：两文件不在 KB2 允许写路径/清单内；mtime 分别为 18:19:22、18:28:41，同期其**自身 run 目录**活跃（T01 run main-log 18:19:32；decisions run main-log 18:27:21、user-summary 18:28:49；另一并行板卡 run 18:26–18:50）；closeout-KB1 §4 已登记"并行线快照"漂移且 KB1 判定绑定 KB1-manifest-r1 快照。
- 目录清单核对：`docs/知识书/` 恰好 11 个文件（预期集），`run` 目录递归清单与"既有文件＋本包新文件"完全吻合；无隐藏/临时/备份残留（.tmp/.bak/.ps1 等 0）；r0 旧清单与 KB0/KB1 报告未被删除。
- `git status` 辅助：仓库内被跟踪文件的全部修改均属并行 TD/T01 线（20261016_185639_td_cli_iptool、T01、tasks.json 等，mtime 14:47–18:01 或并行 run 自身窗口），无任何与 KB2 声明写面相关的跟踪文件改动；`docs/知识书/` 与本公司 run 均为未跟踪新目录（提交历史不可分帧，故以哈希绑定＋清单核对为准）。
- `workflow/tasks.json`：现场哈希=清单登记值（未变）；KB2 声明"只读"，一致。

### 2.6 书目录文件集与命名；格式与模板

- 四新章文件名：`05_MIPI与CSI2入门.md`、`06_相机配置与模式.md`、`07_CSI包与帧完整性.md`、`08_Bayer与颜色.md`——符合 `_写作规范.md` §1（NN_中文短标题、无空格）与 closeout-KB1 §3 命名澄清。
- README 表格 05–08 行链接与文件名**逐字一致**，链接目标 `Test-Path=True`（4/4）。
- 10 个 KB2 输出：UTF-8 **无 BOM**、**CR=0 纯 LF**、末行 LF；行数/字节与清单登记一致（05=218/21644、06=235/23907、07=214/21108、08=216/20737、规范=103/8906、README=114/7018、lcK1=51/12023、dnK1=140/20406、lcK2=61/18186、dnK2=117/18555）。
- 模板 10 节：四章均为 14 个 `##` 节＝9 个固定节＋5 个正文小节；正文顺序 直觉→原理→数字/公式→硬件实现视角→本项目实例 未颠倒；固定节名齐全（10 分钟速读卡/本章要回答的问题/与本项目方案的对应/决策点与判决框架/常见误区/自测题/延伸资源/术语增量/版本记录）；`<details>` 开合各 6/6/6/6。
- "（待写）"标记：四章 **0**；仅规则/笔记文本中有元提及（`_写作规范.md`×2、dev-notes-KB1×2、dev-notes-KB2×3，均为规则或自检叙述，非章节标记）。
- 交叉引用"见第 N 章"：N∈{4,6,7}/{5,7}/{5,12}/∅（逐章），均在 27 章规划内，无悬空编号。

### 2.7 link-check-KB2 记录可信与计数自洽；路径扫描

- `link-check-KB2.json`：可解析、**34 条**、8 字段 0 缺失、status 取值合法（ok=20、unverifiable=3、mismatch=7、dead=4）；分章 05:6/06:5/07:5/08:7/unused:11＝34；summary 与逐条一致（入表 23=20 通过＋3 B 站降级；未入表 3；未采用 8，20+3+3+8=34）。
- 表↔记录 1:1 交叉对核（按 URL 归一化比对）：05=6/6、06=5/5、07=5/5、08=7/7，**两侧对称差集均为 0**；表行合计 23=清单声明 `total_rows`。
- 3 条 B 站降级行均含核验状态"无法在线核验（联网抓取结果不稳定）"与**精确检索词**（据此可复现），符合 `fpga-design-guide.md` §5 降级规则；不以"未在线核验"本身判劣。
- 路径 token 补充扫描（fence 感知）：四章反引号内含"/"的 token 共 32 个唯一值，其中 6 个为非路径表达式（如 `CNA/CNB`、`frame_open/…`、`SENSOR_RSTN/CLK`、`286(137)/0/0/0`、`(R+2G+B)/4`、`IMAGE_WC=0 / …`）；其余全部可解析（项目根/本 run 目录/书目录）——**无断链**（与清单 `path_scan` 声明方向一致；计数口径差异见 §3-O1）。

### 2.8 链接核验可复现性抽样（会话联网工具，2026-10-17）

抽样 6 条（覆盖 MIPI/维基/Sony/pedestrian/B 站/源码），**6/6 与登记状态一致**：

1. `mipi.org/specifications/csi-2` → 返回标题"Camera Serial Interface 2 (MIPI CSI-2) | MIPI" ✓（登记一致）。
2. `en.wikipedia.org/wiki/MIPI_Alliance` → "MIPI Alliance - Wikipedia" ✓。
3. `sony-semicon.com/.../security/security.html` → "Security Camera Image Sensor [Product] | … | Sony Semiconductor Solutions Group" ✓（替换后的产品线页仍可达，未再 404）。
4. `pedestrian.com.cn/embedded/video/mipi_csi.html` → "8.8.3. MIPI CSI传输协议解析 — ywg_dev_doc 0.1 文档" ✓（内容含 LP/HS、SoT、长短包、CRC/ECC）。
5. B 站公开 API `view?bvid=BV188411o7bL` → code=0，title 与登记一致、UP=想摸鱼的皮卡丘、时长 1910s（≈31:50）✓（降级条目的身份核验方式可复现）。
6. `github.com/torvalds/linux/blob/v6.12/drivers/media/i2c/imx415.c` → 标题一致 ✓（且页内可见 891Mbps/4lane 的 VMAX=0x08CA、HMAX=0x044C、LANEMODE=3，佐证记录 note）。
- 未直取两条 PDF（清单已注明"可达但不解析正文"，属预期；不重复下载）；B 站仅做 API 身份复核（页面级不稳定为已登记环境限制）。

### 2.9 补充观察（禁止写法关键词扫描，本维度非门槛）

- 关键词（已批准/已实测/已通过/保证跑得动/永远不会/应该没问题/基本满足/大致通过）四章扫描：唯一命中为 ch06"用户已批准"2 处——经回读来源 `docs/RAW10稳定档位_PLL生成与接入交接.md` 顶部确有"用户已批准：IMX415 全像素 RAW10、4 lane、891 Mbps/lane、27 MHz、30 fps…"原文，属**有出处项目事实**、非组织方口径"已批准"，不构成禁止写法问题。
- 标记分布（本项目事实/通用原理/设计候选/待验证/未决）：05=10/6/2/2/1、06=15/4/2/2/1、07=11/5/1/1/1、08=8/5/1/1/1，均有使用。

## 3. 观察（非阻断，无需修复）

- **O1**：清单 `self_check.path_scan` 称"23 个唯一路径 token"，与本报告更宽口径（32 个含"/"token，其中 26 个文件类）存在计数定义差异；两侧均无断链结论，仅口径不同，建议未来统一"路径 token"定义（如：仅含扩展名的文件引用）。
- **O2**：F6ab 净 −7B 与 F6c +202B 只能通过"before 哈希绑定＋声明改动面＋现场内容/行数"间接复算（旧文未另存副本），本次已做到可核验程度：F5/R6 为逐字节级吻合，F6c 为 +202B 精确吻合，F6ab 为组合方向一致＋内容自洽。若审计要求逐字节 diff，需规划者授权保留修订前副本（属流程改进建议）。
- **O3**：并行线（T01/decisions run）在 KB2 窗口内继续更新其自身文件（decision-register 18:28:41 落在 KB2 写窗口内）——仅影响"零写的强归属"，不影响本包清单与判定；后续包建议冻结时同步记录并行线快照时点。

## 4. 未测项与边界；证据复用；对其他维度影响

- 未测：23 条在线核验未逐条复现（抽样 6 条）；两条 PDF 未直取（预期不解析）；B 站页面级抓取未重复尝试（已按规则降级）；四章正文逐句语义/数字正确性属 functional 维度，本报告不以结构检查替代。
- 证据复用：01–04 章与 `_全书大纲.md` 哈希与 KB1-r1 一致（本次复核），其 KB1-r1 结论可继续绑定 `KB1-manifest-r1.json` 快照复用（由各维度原测试者裁定）；F5/F6/README 修订后文件由 KB2 清单重新冻结（drift 说明见 closeout-KB1 §3）；本包为 new_task，无旧证据混拼。
- 对其他维度影响：F5/F6 为文字/记录级，不改变章节内容与资源行状态（functional/system 不受实质影响，但相应文件须按 KB2 清单重核）；R6 影响 README 05–08 显示面（system 维度已另有测试）；main-log 追加属流程固有行为，不否定清单。

## 5. 下一动作与回退

- 本维度判定 PASS；无缺陷、无修复轮触发。交原规划者按三维矩阵（functional/engineering/system）汇总与收束。
- 回退：无需。若另两维度 FAIL 并触发修复轮，开发修复影响的复测清单由开发提供、本测试者独立裁定复用/重测并绑定当前清单（不拼不同输入 PASS）。

---

报告生成：2026-10-17（会话内只读核验；本文件为唯一写入）。运行日志与原始输出保留于本次测试会话；关键命令族：`Get-FileHash -Algorithm SHA256`、`[IO.File]::ReadAllBytes/ReadAllLines` 统计、`ConvertFrom-Json`、会话 webfetch。两次本地脚本转义失败已当场修正重跑（未用于任何判定）。
