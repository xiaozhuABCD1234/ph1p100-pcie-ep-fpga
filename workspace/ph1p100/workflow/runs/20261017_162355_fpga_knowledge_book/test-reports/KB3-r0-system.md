# KB3 round0 — system（可用性与项目衔接）测试报告

### 判定：FAIL

- task_id：KB3；dimension：system；round：0（首轮验收，新任务）
- 工作树/候选：文档工作树 `docs/知识书/`（KB3 交付 09–12 章、F7 修订 05/06/07、README R6）；run 目录 `workflow/runs/20261017_162355_fpga_knowledge_book/`。本维度无硬件候选。
- 冻结输入 manifest：`workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB3-manifest.json`
  - 现场复算 SHA256=`87b767fd73600750a63bec2135d1aaab33a2326d3021fb90f73efefd34d131af`（与派发给定值一致），bytes=26141，mtime=2026-10-17 19:48:49。
- 工具版本：PowerShell（Windows）文件哈希/正则/路径检查；联网工具 webfetch（用于链接抽样复现）。无 TD/板卡/仪器参与。
- 范围（规划者冻结，勿越界）：可用性与项目衔接——README 09–12 行/快照句/维护规则；09–12 可独立阅读与前后衔接；与"当前 FPGA 实际方案"（DDR 选型与 M1a 现状、控制器接口、帧缓存/队列实际用途）对应成立；第 10 章用户示例问题（DDR1600/1333/800E）章内"五步判读"可用性（可读性/自洽性视角；数值正确性归 functional）；后续写作恢复入口（README→run 记录→dev-plan 下一包行）；全章项目路径与交叉引用可解析、无悬空。上板/接口/长稳类 N/A：无硬件候选、纯文档任务（规划冻结理由）。

## 一、门槛与 G 层记录（依据 fpga-design-guide §6/§8）

- 必需 G 层：**G0**（规范/接口冻结：本指南+大纲+模板+本 manifest）＋**G1**（静态/离线核验：内容抽样、链接核验、事实溯源、引用检查）。**G2–G5 不适用**（无综合/STA、无位流/板测、无长稳、无端到端集成对象；理由=纯文档交付）。
- 逐层结果：
  - G0：**pass**——manifest 自身可复算；指南/大纲/模板冻结面在本次范围内未见被 KB3 越权改写（README/09–12 属 R6/F7 允许面，见 manifest compliance）。
  - G1：**fail**——本维度预置判据"章节结论不与决策冻结登记冲突 / 与当前 FPGA 实际方案对应成立"存在 2 处实际不一致（F1、F2，下详）；其余静态项（哈希、链接、路径、交叉引用、恢复入口、第 10 章可用性）全部通过。
- 不适用层引用规划理由：见上"上板/接口/长稳类 N/A"；本人未运行任何板测、下载、Flash、发布或外部消息动作。

## 二、实际执行的核验（只读）与结果

> 说明：命令均在 `PROJECT_ROOT=C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道` 下执行；环境不返回逐条退出码，以下以"非空预期输出 + 无错误记录"判定成功。一次复合 shell 调用被环境权限拒绝，拆分为小命令后全部重试成功。

1. **manifest 与全量哈希复算**（PowerShell Get-FileHash/ConvertFrom-Json）：
   - manifest 自哈希 ✓ `87b767fd…`。
   - `inputs` 五个分区（dispatch_required/run_state/materials_read/referenced_project_paths/skill_and_contracts）共 68 条：**63 条与磁盘逐字节一致**；5 条"不一致"全部有 manifest 自身声明的语义：
     - `README/05/06/07` 4 条登记的是**修订前（KB2 冻结）基线值**，磁盘值=修订后值，且与 `outputs`/`modified_chapters.after_sha256` 一致；before 值经我独立复核等于 `manifests/KB2-manifest.json` 内的 KB2 冻结值（4/4 命中）。→ 预期内，非缺陷。
     - `main-log.md`：冻结快照 14029B → 现 15010B，属 R1 滚动追加（尾部含 KB2 收尾/KB3 派发/完成记录，为追加型新增）；manifest 已声明该语义。→ 预期内，非缺陷。
   - `outputs` 10 条（09–12、05/06/07 after、README after、link-check-KB3.json、dev-notes-KB3.md）：**10/10 哈希与字节数逐项一致** ✓。
2. **09–12 章路径 token 解析**（反引号扫描 + Test-Path，以 `docs/知识书/` 为基准）：40 个唯一 token 中 22 个为限定相对路径（`../`、`../../`）**全部可解析**；其余 18 个为标识符/端口名/表达式（如 `paxi_aw*/w*/ar*/r*`、`frame_id/slot_id`、`usr_ref_type=2'b00/usr_ref_req=1'b0`），非路径引用，逐一人工归置后补验其指代对象：
   - `ddr_frame_store.v`、`ddr_frame_probe.v`、`ddr_capture_check.v`、`camera_ddr_capture.v` → 存在于 `fpga/csi2/src/mem/` ✓；
   - `camera_ddr_display_top.v` → `fpga/csi2/prj/camera_ddr_display/`（及历史证据目录多份）✓；
   - `ph1p_ddrphy_dram_init.v`、`al_ip/ddr3_mc_0` → `fpga/csi2/…/vendor/ip/ddrmc_x32/…`、`fpga/csi2/pcie_integration/al_ip/ddr3_mc_0/` ✓；
   - `fpga/csi2/_scratch/` 存在 ✓；`src/adc/ddrmc_x32.adc`、`src/sdc/ddrmc_x32.sdc` 为 TD 工程内相对路径（工程在 D 盘、不在本仓），来源=T01 run dev-plan §1.2/§1.4 与 E3 §2 的原文（已核对该两处来源确有这些写法与"53 行""逐字节相同"陈述）→ 判定为"来源可溯、非仓内可解析"，不算悬空。
3. **README 本地链接解析**：README 内 14 个本地 Markdown 链接（01–12 章、`_全书大纲.md`、`_写作规范.md`）**0 缺失**；反引号引用的 `../../workflow/tasks.json`、`../../workflow/runs/20261017_162355_fpga_knowledge_book/`、`../../当前必读/01_FPGA主线学习手册_由浅入深.md` 均存在 ✓。
4. **阅读/衔接/恢复入口检查**：README §"目录与进度"09–12 行=文件链接+`已交付`，与磁盘文件名逐字一致；"当前快照"句"第 01–12 章已交付（…09–12 随 KB3）；第 13 章起未写"与磁盘事实一致（`docs/知识书/` 实有 01–12、README、`_写作规范.md`、`_全书大纲.md`，**无 13 起任何章/90–92 附录**）✓；维护规则（各写作包有界更新本包章节行+快照句；KBZ 终版）可执行且与 F7/R6 实操一致 ✓；恢复入口链：README→run 目录（README §维护规则指向）→`dev-plan.md` §4 KB3 行=**ready（本次派发）**、KB4 行=**blocked（待 KB3 PASS）**、§11"下一动作：派发 KB3…"，链条完整可循 ✓。
5. **交叉引用**：09→10/11/12、10→09/11、11→05/10/12、12→09/11/23 等"见第 N 章"均落在冻结大纲章题内（如第 23 章=R10F 帧协议、第 05 章含 delay 训练——已抽读 05 章确认有 delay 训练内容）✓。
6. **与 decision-register/E3/fpga-design-guide 对核**：M1a（维持 1333、1600 回退、用户追认未定）、E 系列数据（0.230/0.128/+0.102、0.300 accepted=false、bit 5,224,029B、53 行/64 文件/156 项、666.6667MHz/166.650MHz、TMST 数字 1/4/4）在章内与来源一致；fpga-design-guide §3 数字基准（E=6/5、J=10/7、K=11/8 且关联 speed bin 表述与"以颗粒/控制器为准"注、CK 666.67/800/400MHz 等）在章内成立。**但 TMST-7700 状态与板级状态两处与冻结输入/实际状态不一致——F1、F2。**
7. **链接可用性抽样复现**（webfetch，2026-10-17 本次测试会话）：见下表 5/5 复现成功（优先清单 4/4 + B站 API 加验 1）。
8. **RTL 抽样**：`fpga/csi2/src/mem/ddr_frame_store.v`（SHA256=`e9e95f97…` 与 manifest 一致）含"Single DDR-user-clock domain"、三槽/READY/READING/围栏/`write_turn` 结构，与第 12 章描述相符 ✓（实现语义细核归 functional/engineering）。

链接抽样复现表：

| # | 条目（章） | URL | 本次复现结果 | 与登记对照 |
|---|---|---|---|---|
| 1 | JEDEC JESD79-3F 标准页（10） | https://www.jedec.org/standards-documents/docs/jesd-79-3d | 直取成功：DDR3 SDRAM STANDARD / JESD79-3F / Published: Jul 2012 / $247 | 一致（"全文付费"登记属实） |
| 2 | DDR3 SDRAM 英文维基（10） | https://en.wikipedia.org/wiki/DDR3_SDRAM | 直取成功；速度等级表含 800-E 6-6-6、1333-J\* 10-10-10、1600-K 11-11-11；"用 MHz 描述传输率技术上不正确"原文 | 一致；并外证第 10 章 E/J/K 示例值 |
| 3 | Micron DDR3/DDR4 页（09） | https://tw.micron.com/products/memory/dram-components/ddr3-to-ddr4 | 页面加载成功，标题"DDR3 與 DDR4 記憶體 | Micron Technology Inc."；登录弹窗存在（与登记注一致） | 可达、标题相符 |
| 4 | Arm AMBA Specifications（11） | https://www.arm.com/architecture/system-architectures/amba/amba-specifications | 页面加载成功，标题"AMBA Specifications – Arm®" | 一致 |
| 5 | B站视频 BV1vP411c7pt（09） | https://api.bilibili.com/x/web-interface/view?bvid=BV1vP411c7pt | 公开 API 返回 code=0；UP=BranchEducation；duration=**2133s**（≈35.6 分钟） | 与 link-check-KB3.json 的"API 时长≈2133s"及章内"约 35 分钟"一致 |

> 抽样覆盖规划指定优先项（JEDEC/维基/Micron/Arm）4/4；其余 15 条入表条目本轮未逐条复取（抽样要求已满足）。

## 三、失败项（本维度判 FAIL 的依据）

### F1（主要）——TMST-7700 状态与冻结的决策登记（rev4 已关闭）直接冲突

- **期望**：09–12 章公开结论与**同一冻结 manifest 绑定的** decision-register 内容一致（该文件 SHA256=`1a408aa10acdab130c8dd7c020b5f23d9357f17226cc592cd58548556fb8133a`，mtime=2026-10-17 19:30:07，等于 manifest `materials_read` 登记值）。
- **实际**：该冻结文件已在 **rev4** 明确"TMST-7700 明细枚举完成（4 条 HIGH=3×clock definition→local clocks+1×PLL 取整；no_clock/组合环等=0）⇒ **M5.7 关闭（无实质约束缺口、不触发升级）**；§1.4 重开触发①中 TMST 条款随之失效"（见该文件 §10 rev4、§1.4、§5 M5.7、§7 产物锚）。而章节（写于 19:39–19:48，**晚于** rev4 的 19:30）仍按 rev2/rev3 口径写"未决"：
  - `10_速度等级与1600、1333、800E.md` L151："**TMST-7700 未决**：…明细未生成、影响待查（登记为未决、不阻塞 M1a）"；
  - 同章 L178："**未决项**：TMST-7700（6.2.3 route DRC 提示）待最小受控调查"；
  - 同章 L193（对应表边界行）："…**TMST-7700 未决**；板测进行中"；
  - 同章 L208（何时应重开①）："…或 **TMST-7700 调查证实影响**"（登记已把该条款标"失效"）；
  - 同章 L247（自测题 6）："① 1333 板测暴露问题或 **TMST-7700 影响被证实**"；
  - `11_DDR控制器与接口.md` L123："**未决**：TMST-7700（…**明细未生成**）——登记为未决、不阻塞，**不得宣称'无影响/已修复'**"；
  - 同章 L137（对应表）："**TMST-7700 未决**（…明细未生成）"。
- **证据链/时间线**：register mtime 19:30:07（rev4）＜ ch09 19:39:29 ＜ ch12 19:41:03 ＜ ch11 19:44:06 ＜ ch10 19:47:58 ＜ dev-notes-KB3 19:48:28 ＜ manifest 19:48:49。另注：`KB3-manifest.json` 对 decision-register 的注记写"含 rev2/rev3…"，与该文件实际已含 rev4 不符——显示开发在 19:30 前读取、冻结时未复核内容（dev-notes-KB3 L84 亦自述"与 rev2/rev3 一致"）。
- **影响范围**：第 10 章（5 处）与第 11 章（2 处）涉及用户可见"未决项/改判触发"的表述；第 10 章"何时应重开"与自测题 6 的答案随之偏旧。未影响 09/12 章与本维度其余项。
- **可复现性**：以上行号与文本、register rev4 段（§1.4/§5 M5.7/§10）均在冻结文件内可逐条复核。

### F2（次要，同源）——"bit 未下载、未上板 / 板测尚未覆盖"与冻结当日实际状态不符

- **期望**：与"当前 FPGA 实际方案"对应成立；且与冻结 register §1.5（rev3）"上板验证已授权**并启动**（进行中）"不冲突。
- **实际**：章节多处以现在时写"未下载、未上板/未覆盖"，但并行工作包 F（`workflow/runs/20261017_182621_T01_board_and_tmst7700/`，`dev-notes-F.md`，mtime 19:48:53）显示，**在 KB3 manifest 冻结（19:48:49）之前**：
  - 1333 主候选 bit（`B7EF91CF…`，5,224,029B，下载前 SHA 复核一致）：**19:11:44–19:12 SRAM 下载成功**（rc=0、满进度、`T01F_1333_SRAM_DOWNLOAD_END result=ok`，全程 `-mode jtag`、未触 Flash/EFUSE/OTP），随后用户 HDMI 目视=黑屏；
  - 1600ctl 对照 bit（`1447B243…`）：**19:16:40 SRAM 下载成功**（rc=0），用户目视=黑屏；
  - 环境对照 140836：19:2x 下载后**出图**（环境验证通过）；002820 本体：19:3x 下载后黑屏（新签名 D37/D38/D39 全灭，指向 DDR PHY 未就绪；调查进行中）。
  - 关联行：`10_…md` L150"两候选 bit 已条件生成…但**未下载、未上板**；1333 与 1600 的**板级行为差异未被测量**"；L203"B. 1333J/PAXI…代价=**板测尚未覆盖该档**"；同章 R6 速读卡句"bit 已条件生成**未下载**"；`11_…md` L122"两候选 bit 已条件生成、**未下载未上板**"、L138"板级 DDR 校准与长稳未验证（**bit 未下载**）"。同时第 10 章 L152 又写"上板验证已由用户授权并启动（rev3，进行中）"——**章内自相矛盾**（"进行中"与"未下载未上板"并存）。
- **边界与减责说明**：上述行文的直接来源是 E3 报告 §7 的时点口径（E3 冻结时确实未下载）；KB3 dev-notes L89 亦预留了"1333 上板结果…按下一次修订轮更新"的立场。但以本任务冻结时点（19:48:49）衡量，"未下载、未上板/尚未覆盖"已不成立，且与冻结输入 register §1.5"已启动"的口径张力未做时点限定。
- **影响范围**：第 10 章（L10 速读卡、L150、L203）、第 11 章（L122、L138）的"现状角色/边界"表述；对"1333 板测尚未覆盖"的读者结论误导性较强（实际两候选均已上板观察，且出现黑屏等重大中间事实——具体板测结论归属 T01-F 工作包，本报告不做判定）。

## 四、新旧输入差异、证据复用与其他维度影响

- 本任务为 KB3 首轮冻结（round0），无旧 system 报告可复用；KB0–KB2 的 system 报告不适用于本包输入（未引用作为证据）。
- KB3 的 F7（ch05/06/07 文字订正）与 R6（README）不涉及本维度除 README 外的对象；README R6 已核通过；F7 三章不在本维度验收面，无影响。
- 我的 F1/F2 均为**文本级口径更新**需求，改变后只影响 09–12 章文字与自测题答案，不涉及数字/结构；对 functional 的数字对核结论无回归风险（但 functional 若同样引用 rev4 口径，可能提出同一处）；engineering 可关注 manifest 注记"含 rev2/rev3"与文件实含 rev4 的登记一致性（本次由 system 报告记录，供其自行取舍）。
- 复测所需：修复后需在同一 manifest 语义下重新冻结（新 manifest）并由我（system）复测受影响面：ch10 L10/L150/L152/L176-178/L193/L203/L208/L247、ch11 L122-123/L137-138 与 register rev4/F 记录的口径一致性；其余已通过项如无触碰可引用本轮证据（路径/链接/README/恢复入口不再逐项重做，但需确认未被改动）。

## 五、硬件观察者、未测项与下一动作

- **上板层**：本任务 G2–G5 不适用（规划冻结理由：纯文档交付，无位流/板测/长稳对象）。本人未执行任何板测、下载、Flash、发布或外部消息；报告内引用的板级事实**均来自既有记录**（`20261017_182621_T01_board_and_tmst7700` 的 dev-notes-F；用户 HDMI 目视时间 2026-10-17 19:1x–19:3x；本测试者非观察者，不为其结论背书）。
- **未测项**：其余 15 条外部链接未逐条复取（抽查已覆盖优先项）；ch05/06/07 的 F7 修订面归 functional/engineering；板测结论与 TMST 调查报告内容本身不在本维度验收面。
- **下一动作（交原规划者裁决）**：F1/F2 修复（建议：TMST-7700 改为 rev4 口径"已调查关闭、无实质缺口；`mipi_a_byte_clk` local 观察点转入 M5.5"；"未下载/未覆盖"改为带时点的表述并登记 rev3 上板验证已启动+候选已 SRAM 下载/观察的事实边界，明确板测结论以 T01-F/登记为准、本包不预判）→ 重冻 → 本维度 round1 复测。
- **回退**：无硬件回退对象；文本回退即上一冻结版本（KB3 manifest 前 `outputs` 无变更）。
- **阻塞**：无（本维度检查条件齐备，已出判定；F1/F2 属可修复缺陷而非条件缺失）。
