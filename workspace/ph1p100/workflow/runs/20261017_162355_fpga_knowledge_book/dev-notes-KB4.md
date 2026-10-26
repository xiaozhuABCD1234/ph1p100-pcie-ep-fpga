# dev-notes-KB4 — 知识书第 13–15 章 + F8 有界修订 + R6

- 任务：KB4（run `20261017_162355_fpga_knowledge_book`）；角色：fpga-dev；日期：2026-10-17。
- 状态：**首轮完成并冻结（ready_for_test）**。冻结清单：`manifests/KB4-manifest.json`（唯一测试输入）。
- 写范围遵从 dispatch：新建 `docs/知识书/13–15` 三章；F8 仅 `10_速度等级与1600、1333、800E.md`（3 处＋版本行）；R6 仅 README 第 13–15 章行与"当前快照"句；本 run 内新建 `dev-notes-KB4.md`、`manifests/KB4-manifest.json`、`link-check-KB4.json`。未触碰任何其他既有文件。
- 顺序遵从 dispatch：**先应用 F8 修订，再据其写作新章**（F8 完成于写作前，见 §3）。

## 1. 实际读入（写作与修订依据）

**冻结输入（dispatch 必读）**

1. `workflow/runs/.../dispatch.json`（KB4 派发版）、`requirement.md`、`dev-plan.md`（重点 §3、§5.2、§11 含 KB3 收束段）、`input-index.md`、`fpga-design-guide.md`
2. `closeout-KB0.md`、`closeout-KB1.md`、`closeout-KB2.md`、`closeout-KB3.md`（§2–§4：R16–R19、F8 清单、R18 pre-rev 程序、命名与板测转述纪律）
3. `manifests/KB3-manifest-r1.json`；`dev-notes-KB3.md`；`link-check-KB3.json`（schema 参照）
4. `docs/知识书/README.md`（R6 前值 `315237fb…`）、`_写作规范.md`、`_全书大纲.md`、`01_从代码到电路.md`、`08_Bayer与颜色.md`、`09/11/12 章`、`10 章`（F8 前值逐字节复算 `c6b3283c…` 与 KB3-r1 冻结一致）、`link-check-KB3.json`
5. 技能与积木：`.agents/skills/fpga-dev/SKILL.md`（skill 工具加载）

**本章材料（全文/摘录；哈希见 manifest）**

- `docs/DeepSeek独立检测与现行方案整合_2026-10-16.md`（§2 M03/M04、§3.3、§3.4 摘读）
- `docs/双目首版_整链路方案与团队交付.md`（§2/§3/§7 摘读：算法工程定义、行缓存量级、执行纪律）
- `docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md`（§5 F4、§6、影响与停止条件摘读）
- `parallel/algorithms/image_algorithms_ref.py`（全文：去马赛克/边界/half-up/Y8/高斯/4bank 直方图/CDF-min LUT/HeLut 与自检）
- `workflow/tasks.json`（T09 与相关任务状态快照）
- `workflow/runs/20261017-011744-rk-fpga-align/algo/`：`dev-result.json`（round0 blocked）、`change-report.md`（语义冻结、修复记录、G1/G2、吞吐预算）、`source-provenance.json`（工作树候选引入清单）
- `fpga/csi2/src/img/`：`bayer_raw10_demosaic4.v`、`rgb8_gray_stream.v`、`gray8_gaussian3x3_stream.v`、`gray8_he_cdfmin_frame.v`、`algo_rowwin3.v`、`img_algo_parallel_top.v`（头注与关键实现处摘读）
- `workflow/runs/20261017_182621_T01_board_and_tmst7700/dev-notes-F.md`（**F8 来源核对**：§9 执行记录 19:03–19:12、run2 首成功下载 19:11:44、19:16:40 1600ctl 下载）
- `docs/evidence/td2026_ddr1333_accept_20261017.json`、`docs/evidence/td2026_b_run2_20261017.json`（**F8 来源核对**：70 引脚 golden 71→生成 70、0 失配；两轮 64 文件闭包）
- `workflow/runs/20261017_161109_decisions_compare_freeze/decision-register.md`（M5.5/M5.7 现值核对）

## 2. 实际产出（3 新章 + F8 + R6 + 3 个 KB4 run 文件）

| 文件 | 说明 | 字节 | 行 | SHA256（前16） |
|---|---|---|---|---|
| `docs/知识书/13_灰度.md` | 新建。模板 10 节；Bayer→双线性→Y8 流水线；保奇偶边界、half-up/截断两套规则、77/150/29 推导与手算例；4px/beat 前端与逐样本验证方法 | 23888 | 232 | `d57044a8c5def498` |
| `docs/知识书/14_高斯与3×3卷积.md` | 新建。卷积/核/归一化；`(sum+8)>>4` 单次舍入；普通复制边界（与去马赛克两套规则）；行缓存+窗口寄存器；常量/冲激/能量守恒例 | 20880 | 200 | `abe828c3bd176907` |
| `docs/知识书/15_前帧均衡与三算法.md` | 新建。直方图/CDF/LUT；前帧 HE 边界（首帧/坏帧/常量帧/帧边界原子发布/4bank 同 bin）；三算法真并行组织与证据要求；左右不得各自 HE | 24037 | 227 | `247a9ecf04f598fa` |
| `docs/知识书/10_速度等级与1600、1333、800E.md` | **F8**：3 处内容修订 + r2 版本行 | 28338 | 282 | `f0c6b7084ff630da` |
| `docs/知识书/README.md` | **R6 有界更新**：13–15 目录/进度行＋"当前快照"句（4 行） | 7384 | 114 | `ee5e93e3218751eb` |
| `workflow/runs/.../link-check-KB4.json` | 本包链接核验记录（17 条：入表 15＋未采用 2） | 11642 | 41 | `6c02f582fc428d38` |
| `workflow/runs/.../dev-notes-KB4.md` | 本文件 | 见 manifest | — | 见 manifest |
| `workflow/runs/.../manifests/KB4-manifest.json` | 冻结清单（不含自身哈希） | 见文件自身 | — | 由测试者现场重算 |

## 3. F8 修订前后对照（逐处最小面；先核 T01-F/证据文件）

**来源核对（改前逐一打开）**：

- `dev-notes-F.md` §9：上板执行记录窗口 **2026-10-17 19:03–19:12**；run1（19:05:12）失败；**run2（19:11:44）首成功下载**；§6 完成注记=19:03；1600ctl 下载=19:16:40。
- `td2026_ddr1333_accept_20261017.json` `pins_70`：golden 71 → 生成 70、matched 70、mismatched []、排除项 `ddr_addr[14]`（ADR_WIDTH=14）；`td2026_b_run2_20261017.json` `run2_pincompare`：golden 71/generated 70/matched 70/mismatched 0。两文件 `Test-Path`=True。
- `decision-register.md` 现值：**M5.5=0.300ns 口径/优化窗口观察点**；**M5.7=TMST-7700（rev4 已关闭）**。

**逐处对照（行号为修订前→修订后；均为单行内修改）**：

| # | 处 | 修订前 | 修订后 | 依据 |
|---|---|---|---|---|
| ① | L152 | `（2026-10-17 19:11 起）` | `（2026-10-17 19:03 起；首成功下载 19:11:44）` | dev-notes-F §9（执行记录窗口 19:03–19:12；run2 首成功 19:11:44） |
| ② | L162 ④ 的配套引注（L165 括注） | `（…旧 CWL 编码与 MR2 路径见 …§2。）` | `（…§2；70 引脚逐项核对（golden 71→生成 70、0 失配）见 ../evidence/td2026_ddr1333_accept_20261017.json、../evidence/td2026_b_run2_20261017.json。）` | 两证据文件 pins_70/run2_pincompare（Test-Path 已核） |
| ③ | L178 | `"两候选共同未达 0.300"列为优化窗口观察项（同上 M5.5/M5.7）。` | `…列为优化窗口观察项（decision-register M5.5）。` | 拆分：TMST 关闭=M5.7（同句前段已指）；0.300 观察项=M5.5 |
| ④ | 版本记录 | （281 行结束） | 新增 `修订 r2（KB4 轮：时间标记/引注精度）` 一行（→282 行） | closeout-KB3 §3 第 4 条 |

- **file-level before/after**：`10_速度等级与1600、1333、800E.md`：`c6b3283ce798e1ec73fd85a474123820f7e7f1af3ae69842428b911b13e7982c`（27755B/281 行；KB3-r1 冻结值，开工前逐字节复算一致）→ `f0c6b7084ff630da8ec7703dcfad033118dd353f772d19379c31de4d15f998d4`（28338B/282 行）。
- 未改任何事实、数字与结论；"19:11 起"零残留（grep=0）；合并引注"同上 M5.5/M5.7"仅存在于 r2 版本行的**变更描述**中（非正文引注）。未触碰 ch10 其余字节。

## 4. 停止条件与合规检查

- 开工前核对写范围：13–15 章 `Test-Path`=False（新建）；ch10/README 逐字节复算与 KB3-r1 冻结值一致后才动手。
- 越界与保护检查：写操作限于 §2 表列文件；未覆盖/修改/删除任何其他既有文件（含 01–09、11、12 章、`当前必读/`、`docs/` 旧文档、`workflow/tasks.json`、`fpga/` 其它文件、`tools/`、`parallel/`、D 盘工程、其它 run、KB3/KB2/KB1/KB0 的清单与报告）。**未删除任何文件**。
- 编码/换行实测：本包产出的书文件与 JSON 全部 UTF-8（无 BOM）、纯 LF（CR=0）；文件名符合命名澄清（`14_高斯与3×3卷积.md`、`15_前帧均衡与三算法.md`）。
- 工程零触碰：未运行任何 TD/构建/下载/板卡动作；未写 D 盘；未发外部消息；`main-log.md` 未触碰（R1）。
- R18 说明：本包为**round0 首轮**，未发生修复轮，故未使用 `pre-rev/`；如后续 KB4 测试 FAIL 引发修复轮，第一次修改章节文件前将按 R18 存 `pre-rev/`（命名含轮次）。

## 5. 外部链接核验（dev-plan §5.2 自检项②：每章 3–8 个、逐一核验）

- 三章资源表共 **15 行**（13=5、14=5、15=5），全部带核验状态字段；明细见 `link-check-KB4.json`（17 条=入表 15＋未采用 2）。
- 结果：入表 15 = **15 条在线核验通过**——8 条维基页面直取（Grayscale/灰度图像/Luma/Gaussian blur/高斯模糊/卷积/Histogram equalization/直方图均衡化）＋2 条 OpenCV 文档直取（docs.opencv.org 4.13.0 英文教程；opencv.org.cn 2.3.2 中文旧版）＋1 条博客园直取＋4 条 B 站（页面直取成功＋公开 API 复核标题/UP 主/分段时长：BV1Rg411j7D7、BV15Z4y1A7Gq、BV1YA411K7pp、BV1cE411n7yG）。
- 未采用 2：网易公开课（黑马程序员 HE 分节）与 CSDN 个人笔记——页面直取成功、同主题重复/条目上限而未入表，记录备查。
- 诚实边界：① 核验是 **2026-10-17 时间点快照**；② OpenCV 中文文档为 2.3.2 版旧翻译（已在资源表注明"旧版"）；③ B 站条目本会话页面级直取成功（与部分历史会话的降级情形不同，环境差异已记录在 `bilibili_method_note`）。

## 6. 三维自检（对照 dev-plan §4 KB4 行与 `_写作规范.md` §8）

- **functional**：三章模板 10 节齐全（速读卡/问题/正文/对应/决策点/误区/自测题/资源/术语/版本；自测题各 6 条含 `<details>` 答案）；要点覆盖 dev-plan §3 各章边界且未越章；正文按"直觉→原理→数字/公式→硬件视角→本项目实例"渐进。
  - **算术/语义与整合 §3.3 一致**：去马赛克 3×3 双线性+保 CFA 奇偶边界+half-up；RAW10 每分量 `>>2`（截断）；`Y8=(77R+150G+29B+128)>>8`；高斯 `[1 2 1;2 4 2;1 2 1]`+`(sum+8)>>4`+复制边界；HE CDF-min 前帧 LUT（首帧恒等/坏帧不发布/常量帧恒等/4bank 同 bin 全计数/帧边界原子发布）。
  - **逐像素核验方法讲清**：独立 oracle＋冻结向量＋逐样本比对＋负对照（突变必须被拒绝），并给出参考自检条目与 run 记录出处。
  - **项目事实对核（≥8 处/章；路径已逐条 Test-Path）**：
    - **第 13 章**：`parallel/algorithms/image_algorithms_ref.py`；`fpga/csi2/src/img/bayer_raw10_demosaic4.v`、`rgb8_gray_stream.v`、`img_algo_parallel_top.v`、`algo_rowwin3.v`；`workflow/runs/20261017-011744-rk-fpga-align/algo/{dev-result.json,change-report.md}`；`workflow/tasks.json`（T09）；`docs/DeepSeek独立检测与现行方案整合_2026-10-16.md`（§3.3/§2 M03）；`docs/双目首版_整链路方案与团队交付.md`（§3）；`docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md`（§5 F4）；`tools/algo/{oracle_algo.py,run_g1.py}`。
    - **第 14 章**：同上参考模型（`gaussian3x3`/自检）；`gray8_gaussian3x3_stream.v`、`algo_rowwin3.v`、`algo_rowwin_reader.v`、`img_algo_parallel_top.v`、`gray8_gaussian3x3_frame.v`；`algo/{source-provenance.json,change-report.md,dev-result.json}`；整合 §3.3；双目首版 §3/§7；策略 §5 F4/§6；tasks.json（T09）。
    - **第 15 章**：参考模型（`banks4_histogram`/`banks4_histogram_buggy`/`cdf_min_lut`/`HeLut`/自检）；`gray8_he_cdfmin_frame.v`、`img_algo_parallel_top.v`；`algo/{change-report.md,dev-result.json,vectors/}`；整合 §3.3；双目首版 §3；策略 §5 F4/§6；tasks.json（T09）。
  - 决策卡：13=灰度路线（假灰度/双线性+Y8/高级 ISP）；14=高斯实现与语义边界（单次舍入/可分离/换核）；15=三算法组织与"真并行"自证。均含四要素。
- **engineering**：命名/编码/LF 合规（实测 CR=0、UTF-8 无 BOM）；篇幅 232/200/227 行（规范区间 120–350）；交叉引用 N∈{3,8,13,14,15,16} 全在规划内、全库无"（待写）"；无禁止写法（未把候选写成已实测；T09 状态一律"截至本包撰写时点"＋归属任务板/run 记录；组织方口径未写"已批准"；修复结果不预判）；F8 逐处最小面；README 仅动 3 行＋1 句（共 4 行，+146B）；manifest 覆盖新章＋F8 修订面＋核验记录。
  - 路径扫描（行内反引号内 `../` 提取）：三章合计 **22 个唯一 token 全部可解析**（含新建的 `link-check-KB4.json`）；无断链、无通配占位。
- **system**：README 目录 13–15 行与文件名逐字一致、状态=已交付；"当前快照"句与事实一致（第 16 章起未写）；三章可独立阅读且前后衔接（08→13→14→15→16 链）；引用项目路径实测存在；与冻结登记不冲突（第 10 章 F8 只动引注/精度；T09 表述按 tasks.json 快照；未与 decision-register/整合冲突）。

## 7. 未测与边界

- 链接核验是 **2026-10-17 时间点快照**；外部页面可能随时间变化（历史经验：JEDEC 旧链接 404、B 站环境差异）。
- 三章内引用的并行线状态（T09.rk-align-algo round0 blocked、修复轮已派发、候选 RTL 在 `fpga/csi2/src/img/`）绑定**本包撰写时点**（2026-10-17 晚）：修复轮的完成情况以该 run 的 `dev-result.json`/`change-report.md` 与 `workflow/tasks.json` 为最新状态源；若后续状态变化（G1/G2 结论、G3/G4 板测），按下一次修订轮更新。
- 本包不含任何新增硬件证据：三章为【通用原理】＋【本项目事实】（指向既有文件/记录）；"逐像素正确/真并行"均限离线与仿真级，不等价于任何板级结论。
- B 站页面在其它会话可能抓取失败；测试复现失败时先核 `link-check-KB4.json` 的登记说明再判定。
- **并行线漂移（本包冻结期间观测）**：T09.rk-align-algo 修复轮在本包撰写/冻结期间持续修改其资产——候选 RTL（`rgb8_gray_stream.v` 改为两级流水、算术不变；`gray8_he_cdfmin_frame.v`；`img_algo_parallel_top.v` 共享流条件重构为 `y8_stream_ready`/`y8_xfer` 两级线网）与三份 run 记录（`change-report.md`、`source-provenance.json`、`dev-result.json`——后者已更新为修复后版本，记录 G1/G2 pass、状态 ready_for_test）在本清单冻结前后被外部 run 更新。本包对这些资产**只引用可复核的语义**（算术公式、共享流"全接收或全停顿"属性、旧候选未并入原因）并在正文保留"实现细节/状态以 run 记录为准"的余量；manifest 内哈希为**读取时点快照**（新观测值已在条目 note 内登记），后续漂移按 R1/R15 同类语义处理（归因外部 run，不判本包失败）；定点复核请以 manifest 快照＋本节说明对核。

## 8. Lessons（可复用）

- **L16**：并行线的候选 RTL 与记录可能"半同步"（示例：高斯分支头注仍描述保奇偶边界、实例化参数却是 `PARITY_CLAMP(0)`）。引用时以**参考模型/冻结记录**为准，RTL 头注只作辅助；对易漂移的 in-flight 细节，采用"语义＋状态带时点"的写法，不把未定稿数字固化成章内结论。
- **L17**："进行中状态"必须带时点＋归属＋不预判（T01-F 纪律可推广到一切并行任务）：写成"截至本包撰写时点，round0 返回 blocked、修复轮已派发；以该 run 记录为准"，比"修复中/已修复"更稳。
- **L18**：章节里的可手算例子（Y8=141、[0,85,170,255]、常量/冲激响应）应与参考自检条目一一对应并在思维上可复推——测试者能据此做定点复核，负对照类自检条目也顺带被讲清。

## 9. 自检证据（实测命令与锚点）

1. 编码/LF/行数（逐字节统计 0x0A/0x0D）：13=232/23888/CR0；14=200/20880/CR0；15=227/24037/CR0；ch10=282/28338/CR0；README=114/7384/CR0；link-check=41/11642/CR0（UTF-8 无 BOM）。
2. `link-check-KB4.json`：显式 UTF-8 读取后 `ConvertFrom-Json` 通过、17 条目；summary 与逐条一致（入表 15 全通过/未采用 2）。
3. 路径扫描（行内反引号内 `../` token）：三章 22 个唯一 token 全部 `Test-Path` 可解析；无断链、无根相对混用残留（另外扫 `(workflow|tools|algo|fpga|docs|parallel)/` 反引号 token=0）。
4. 关键锚点抽查（读取回显）：ch13 含"77 + 150 + 29 = 256/36128 >> 8/141/demosaic_coloronly_exact_all/4px/beat/T09.rk-align-algo"；ch14 含"1600 + 8/4 + 4×2 + 4×1 = 16/3.75KiB/PARITY_CLAMP(0)"；ch15 含"n − cdf_min/[0, 85, 170, 255]/3.3–3.4k/mode_id/y8_stream_ready"——逐条命中。
5. 交叉引用扫描：`见第 N 章`/`第 N 章` 引用 N∈{03,08,13,14,15,16}，均在 27 章规划内；全库无"（待写）"；三章 `<details>` 各 6 条。
6. F8 定点复核：ch10"19:11 起"零残留；"同上 M5.5/M5.7"仅存于 r2 版本行的变更描述；新增引注两证据文件 `Test-Path`=True；版本行 +r2 命中。
7. README 定点复核：第 13–15 行链接指向真实文件（`Test-Path`）且状态"已交付"；快照句=「第 01–15 章已交付…第 16 章起未写」；其余行未动（与 KB3 冻结值 diff 仅 4 行：1 句＋3 章节行，+146B）。
8. 并行线漂移观测（本包冻结期间）：`rgb8_gray_stream.v`（21:01/1956B）、`gray8_he_cdfmin_frame.v`（21:00/22792B）、`img_algo_parallel_top.v`（21:01/10414B）、`change-report.md`（21:06/14408B）、`source-provenance.json`（21:04/2771B）、`dev-result.json`（观测 7443B，记录 G1/G2 pass、状态 ready_for_test）被外部 run 更新；语义复核仍成立（常量乘法与 `>>8` 取位；24bit 计数/乒乓/≤~3.3k；`y8_stream_ready`/`y8_xfer`；run 记录的 § 结构未变），正文已按"语义＋时点"表述，详见 §7 漂移说明。

## 10. 复测影响清单（供主转发测试者；绑定 KB4 清单）

- **冻结清单**：`workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB4-manifest.json`（唯一测试输入）。
- **新增/变更文件（相对 KB3-r1 冻结）**：`docs/知识书/13_灰度.md`、`14_高斯与3×3卷积.md`、`15_前帧均衡与三算法.md`（新）；`docs/知识书/10_速度等级与1600、1333、800E.md`（F8）；`docs/知识书/README.md`（R6）；`link-check-KB4.json`、`dev-notes-KB4.md`（新）。
- **未变文件**：`_全书大纲.md`、`_写作规范.md`、`01–09 章`、`11/12 章`（哈希与 KB3-r1 冻结一致，已复核）。
- **required_dimensions（开发侧建议，最终复用/重验由测试者按各自报告裁定）**：
  1. **functional 必测**：三章要点覆盖与递进顺序；关键算术对核（77/150/29 和=256、Y8 例、`>>2` 截断 vs half-up；高斯核权重 16、常量/冲激/能量守恒；HE 公式与 `[0,85,170,255]` 例、den=0 恒等、前帧语义）；语义与整合 §3.3 一致；逐像素核验方法完整（oracle/向量/逐样本/负对照）；F8 三处内容与 T01-F §9/两证据文件一致；T09 状态表述与 tasks.json 快照一致且不预判。
  2. **engineering 必测**：模板 10 节与篇幅；编码/LF；F8 逐处最小面复测（3 处内容＋版本行；before/after 哈希与字节数）；R6 改动面（3 行＋1 句、+146B）；资源表核验状态与检索词；路径/交叉引用扫描；"（待写）"零残留；manifest 输出哈希一致性。
  3. **system 必测**：README 13–15 行链接/状态/快照句；项目路径存在性抽样（13–15 各 ≥2 条）；与 `tasks.json`/decision-register/整合声明不冲突；链接可用性抽样复现（优先维基/OpenCV/博客园；B 站按环境提示）。
- **证据复用**：`_全书大纲.md`、`_写作规范.md`、`01–09 章`、`11/12 章` 哈希未变，其此前结论在各自测试者裁定下可复用；**KB3 的 r1 判定继续绑定 `KB3-manifest-r1.json` 快照**（F8 后 ch10 由 KB4 清单重新冻结，定点复核归 KB4 测试）；KB2/KB1/KB0 结论绑定各自清单。
- **环境提示**（重申，不对判定施压）：B 站条目本会话已直取核验成功，但其它会话可能抓取失败——属环境差异，已按规则登记；核验为 2026-10-17 快照；OpenCV 中文文档为 2.3.2 旧版页面（内容可用但版本旧，已在资源表注明）。
