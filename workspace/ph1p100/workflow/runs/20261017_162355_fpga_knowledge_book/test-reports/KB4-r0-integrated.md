### 判定：PASS

# KB4 综合测试报告（round 0 首次验收 · integrated）

## 0. 元数据与输入身份

- task_id：KB4；round：0（首次验收）；dimension：integrated（functional/engineering/system 为同一综合测试者的检查清单，非三个代理）。
- run_id：`20261017_162355_fpga_knowledge_book`；cwd：`C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道`（全部命令以项目根为基准；本轮未修改/删除任何输入与既有文件；本报告为唯一新建文件）。
- 冻结清单：`workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB4-manifest.json`；现场复算 SHA256 = `d5e8d6e8224caf88084f9fbbc43d0d5ac649e28354f51837114cb9b198e52b2b`（与派发登记值一致）。
- 工具：Windows PowerShell（`Get-FileHash` SHA256、`[IO.File]` 字节级读、`ConvertFrom-Json`）；内容检索＝grep 工具（ripgrep）；链接抽样＝Code Mode fetch（HTTP GET，只读）。
- 退出码：本次调用层未返回独立退出码字段，故如实不虚报；全部命令正常返回完整输出、无错误记录，判据均取实测输出值（哈希/字节数/行数/匹配计数）。
- 被验候选（同一冻结输入）：新建 `docs/知识书/13_灰度.md`、`14_高斯与3×3卷积.md`、`15_前帧均衡与三算法.md`；F8 修订 `docs/知识书/10_速度等级与1600、1333、800E.md`；R6 更新 `docs/知识书/README.md`；本 run 的 `link-check-KB4.json`、`dev-notes-KB4.md`。

## 1. 冻结与输入漂移处置（判定先决）

- 逐条复算清单全部条目：`dispatch_required` 21 条、`materials_read` 17 条、`referenced_project_paths` 6 条、`run_state` 1 条、`skill_and_contracts` 1 条 —— 除下列已登记漂移外 hash/bytes 全部一致（含 `tasks.json`、`decision-register.md`、`dev-notes-F.md`、两份 evidence JSON 等现值与清单登记值一致）。
- 已登记漂移（预期，归因外部 run T09.rk-align-algo 修复轮；按 R1/R15 同类语义处置，不判本包失败）：3 个候选 RTL ＋ 3 份 run 记录：
  - `algo/dev-result.json`：清单快照 4100B/`43fc1997…`；清单 note 观测 7443B/`66517b99…`；本次实测 **7492B/`d98786dc…`**（外部继续更新，晚于 note 观测时点）。
  - `algo/change-report.md`：快照 14057B/`d97b7a30…`；note 观测 14408B/`e8e6818d…`；实测 **16092B/`b9dbe3fa…`**。
  - `algo/source-provenance.json`：实测 **2771B/`785f0abd…`**（与 note 观测一致）。
  - `fpga/csi2/src/img/rgb8_gray_stream.v`：实测 **1956B/`1a64fa21…`**（一致）。
  - `fpga/csi2/src/img/gray8_he_cdfmin_frame.v`：实测 **22792B/`df84b8a4…`**（一致）。
  - `fpga/csi2/src/img/img_algo_parallel_top.v`：实测 **10414B/`7f1e0544…`**（一致）。
- R1（滚动日志）：`main-log.md` 快照 19363B/`55ba1630…`，实测 20832B/`d9d075ff…`；**前 19363 字节 SHA256 逐字节复算 = `55ba1630…`（与冻结值一致）→ 追加型新增成立**，按 R1 不否定本清单。
- 非登记漂移：无。`docs/知识书` 未列出文件（01–07 等）的完好性由 KB3-r1 基线比对覆盖（见 E-3）。
- 工作树：`docs/知识书` 文件在 git 中未跟踪（`git status --porcelain`＝`?? docs/知识书/10_速度等级与1600、1333、800E.md` 等），无提交历史可充当修订前副本；F8 字节最小性采用与 KB3 相同合围法并增加“增量对账”不变量（见 E-4），与 R18 裁定文本认可的 KB3 方法一致。

## 2. 独立审阅与最终复核（同一测试者依次承担）

- 独立于开发者（本轮全新会话、单一综合测试者、未派生代理、只读）。
- 先审阅需求/来源侧：`dev-plan.md` §3 边界、§5.2、§11（KB3 收束段）、`closeout-KB3.md` §2–§4（R16–R19/F8/R18）、`fpga-design-guide.md`、`_写作规范.md` §2/§3/§4/§8、`_全书大纲.md` 的 13–15 边界表述。
- 再审阅最终实际文件、实测哈希与数字复算（§3–§5）；结论：三章与 F8/R6 修订面符合规划边界与来源记录，未发现越章、越范围写入、事实错误或与冻结登记冲突；发现 2 条非阻断观察＋3 条记录性提示（§7）。

## 3. functional（适用：G0/G1）

规划要求/阈值（dev-plan §4 KB4 行、清单 `retest.expected_focus`）：要点覆盖 §3 各章边界且按“直觉→原理→数字/硬件→实例”递进；关键算术/数字正确、与来源一致；F8 三处内容与 T01-F §9 及两份证据一致；边界/故障拒绝正确；T09 状态与 `tasks.json` 快照一致且不预判。

结果：**PASS**。

**F-1 模板与边界覆盖（逐章）**
- 13：覆盖“Bayer→双线性 RGB→Y8、`Y=(77R+150G+29B+128)>>8`、half-up/边界/相位保持、直接取高 8bit 为何不算、4px/beat 流水线、逐像素核验”，未越章；正文顺序＝直觉→原理一/二→数字→硬件视角→本项目实例 ✓。
- 14：覆盖“卷积/邻域直觉、核与归一化、`(sum+8)>>4`、复制边界（与去马赛克两套规则）、行缓存＋窗口寄存器、‘看起来更模糊’不算验证” ✓。
- 15：覆盖“直方图/CDF/LUT、CDF-min 前帧 HE、首帧恒等/坏帧不更新/常量帧恒等/4bank 同 bin/帧末原子发布、三算法真并行组织与证据要求、左右不得各自 HE”，Part 3 收束章定位与“见第 16 章”衔接正确 ✓。

**F-2 算术与数字对核（独立复算，全部通过）**
- 权重：77+150+29=256 ✓；0.299/0.587/0.114 ×256 → 77/150/29 ✓。
- Y8 例 (100,150,200)：7700+22500+5800+128=36128，`>>8`=141 ✓；自测 (0,128,255)：26723`>>8`=104 ✓；极端 R=G=B=1023→(256×255+128)>>8=255 ✓、全 0→0 ✓；RAW10→8bit 为 `>>2` 截断（无 +2），与 half-up 分开冻结 ✓。
- 高斯：核和 16 ✓；常量 100→(1600+8)>>4=100 ✓；自测 90→(1440+8)>>4=90 ✓；冲激 64/32/16→4/2/1 ✓、能量 4+4×2+4×1=16 ✓；中间和上限 255×16=4080<4095（12bit 可装）✓；输出尺寸不变 ✓。
- HE：例 [10,20,30,40]→[0,85,170,255] ✓；自测 [0,0,100,255]→0/128/255（127.5 半进位）✓；1080p=2,073,600 ✓；22bit（双目首版 §3 现值）与候选 24bit（≤2048×2048=4,194,304，RTL 头注）✓；den=0→恒等 ✓。
- 吞吐预算（章内标注“设计值，非实测”）：4px/beat×187.5MHz=750Mpx/s ✓；1080p30=62.2Mpx/s≈8.3% ✓；双路 124.4Mpx/s≈16.6% ✓；双路 60fps 248.8Mpx/s≈33% ✓（记录实测口径 ≈748Mpx/s，差异属设计/实测口径区分，章内已声明）。
- 名称微差（记录备查，见 O-3）：章内 `sum[15:8]` 对应 RTL 实网名 `sum2[15:8]`，语义一致。

**F-3 参考模型符号/自检逐条命中（`parallel/algorithms/image_algorithms_ref.py`）**
`demosaic_bilinear`(8 处)、`_clamp_color`、`left_green_direction_phase1`、`border_color_aware_corner`、`demosaic_coloronly_exact_all`、`y8_weights_sum_256`、`y8_white_255_raw10`、`y8_black_0`、`gaussian3x3`、`gaussian_constant_identity`、`gaussian_impulse_kernel`、`gaussian_impulse_energy_conserved`、`cdf_min_lut`、`HeLut`、`banks4_histogram`/`banks4_histogram_buggy`、`banks4_buggy_detected`、`cdf_min_denominator_zero_identity`、`he_bad_frame_keeps_lut`、`banks4_no_lost_counts`、`banks4_distinct_bins`、`lut_source_seq` 全部存在；文件头注 L17/L18/L20（`(sum+n//2)//n`、`>> (BITS-8)`“截断不是四舍五入”、`clamp(round((cdf−cdf_min)*255/den))`）与三章引述逐字对应 ✓。

**F-4 与整合 §3.3 一致（`docs/DeepSeek独立检测与现行方案整合_2026-10-16.md`）**
- L69：“保持CFA奇偶的边界夹取；half-up；RAW10 每分量 `>>2`；Y=(77R+150G+29B+128)>>8；高斯 [1 2 1;2 4 2;1 2 1]+(sum+8)>>4+复制边界；HE 前帧 CDF-min/首帧恒等/常量帧恒等/坏帧不更新/换帧锁定” ✓ 与三章一致。
- L71：“工作树已有灰度 RTL 只接 RGB8，不是完整 Bayer 去马赛克 RTL”“三算法演示支路不能使左右匹配图各自 HE 而改变亮度对应关系”逐字命中 ✓；§2 M03（L25）“不要用 RGB565 预览采样器代替正式全分辨率路径”✓。

**F-5 RTL 语义核对（按 R1/R15 漂移语义：当前观测版本＋清单快照语义）**
- `bayer_raw10_demosaic4.v` 头注：4 样本/拍、lane 0＝最左列、保奇偶复制边界（0→1 / W-1→W-2 / 0→1 / H-1→H-2）、`(a+b+1)>>1`、`(s+2)>>2`、`>>2` 截断、无 AWB/CCM、中止帧不产 eof ✓；支持范围 W%4==0、8≤W≤MAX_WORDS×4(=2048)、2≤H≤2048，W=4/H=1 仅软件参考 ✓；`lane 0 = bit[9:0]` 打包细则在 change-report §1 逐字命中（L15）✓。
- `rgb8_gray_stream.v`：L2 头注 `Y = (77*R + 150*G + 29*B + 128) >> 8`；L45–47 常乘 77/150/29；L29 `+18'd128`；L62 `m_y <= sum2[15:8]`（取高 8 位）✓；round1 两级流水/算术不变的说明与清单漂移登记一致 ✓。
- `algo_rowwin3.v` 参数 `PARITY_CLAMP` ✓；`gray8_gaussian3x3_stream.v` L85 `.PARITY_CLAMP(0)` ✓（高斯＝普通复制，去马赛克＝保奇偶，参数区分）。
- `gray8_he_cdfmin_frame.v` 头注：前帧 LUT/首帧恒等/坏帧不发布/4 bank 同 bin 全计数/帧末 combine+256 项除法+原子发布（乒乓）/den=0 恒等/24bit 计数/中止传播 ✓；L21–22 帧末有界停顿“<= ~3.3k”（与 ch15 表述一致，另见 O-2）；L49–50 监视读口 `lut_rd_addr/lut_rd_data`。
- `img_algo_parallel_top.v`（当前观测版本）：L85–86 端口 `he_lut_addr/he_lut_data`；L132 `wire y8_stream_ready = y8_fifo_ready && gau_s_ready && he_s_ready;`；L133 `wire y8_xfer = g0_valid && y8_stream_ready;`；L244 `.lut_rd_addr(he_lut_addr)` ✓ —— 与 ch15 引式逐字一致；change-report §3 接口冻结表（L77）含 `he_lut_addr/he_lut_data`（1 拍延迟只读监视口）✓。
- `source-provenance.json` L22：旧候选 `gray8_gaussian3x3_frame.v`“retained candidate (not wired into the parallel top; its phased load/output organisation cannot serve 4px/beat continuously)” ✓ 与 ch14 表述一致；该文件 SHA 与 KB4 清单一致（未随外部修复轮变化）。

**F-6 F8 修订正确性（逐处，含来源核对）**
- L152 → `（2026-10-17 19:03 起；首成功下载 19:11:44）` ✓；来源 `dev-notes-F.md`：`19:03`(2 处)、`19:11:44`、`19:16:40`、run1 失败 `19:05:12` 均命中，执行窗口 19:03–19:12 一致。
- L165 括注 → 补 `70 引脚逐项核对（golden 71→生成 70、0 失配）见 ../evidence/td2026_ddr1333_accept_20261017.json、../evidence/td2026_b_run2_20261017.json` ✓；证据文件实测：`pins_70`＝golden 71/generated 70/matched 70/mismatched []，排除项 `ddr_addr[14]`（ADR_WIDTH=14）；`run2_pincompare`＝golden 71/generated 70/matched 70/mismatched 0 ✓；两路径 Test-Path=True ✓。
- L178 → `"两候选共同未达 0.300"列为优化窗口观察项（decision-register M5.5）。` ✓；decision-register 现值：M5.5＝0.300 口径/优化窗口、M5.7＝TMST-7700（rev4 已关闭）✓。
- L282 → 新增 `修订 r2（KB4 轮：时间标记/引注精度）` 版本行 ✓（closeout-KB3 §3 第 4 条）。
- 旧短语零残留：`19:11 起` 全章 0 处；`同上 M5.5/M5.7` 仅存在于 r2 版本行的**变更描述**中（L282；属登记的变更描述行为，dev-notes §3 已声明）✓。

**F-7 T09 状态表述（不预判；tasks.json 自冻结起未漂移）**
- `tasks.json` T09：state=active；status_note 含“round0 返回 blocked：G1 core 16 逐样本 mismatch（多帧 HE/中止段 branch1/2；branch0 同段正确）；G2 187.5MHz setup SWNS −3.870/STNS −505.059、hold +0.021、部分用例未跑完；修复轮 1 已派发；T09 收束后队列暂停（fb-08）；顺序 T11.rk-align-base→T09→T10→T11.rk-align-opt、batch=1”，R2 原文“验收须展示真实并行硬件结构与资源/吞吐证据，不得只串行或软件模拟”逐字命中 ✓。
- ch13 L129、ch14 L97、ch15 L116–L125 均为“截至本包撰写时点”式转述，不预判修复结果，并指向 run 记录为最新状态源 ✓；与漂移后 run 记录（G1/G2 pass、ready_for_test）不冲突（章内显式声明“以该 run 记录为准”）。

**F-8 边界与故障拒绝**
- ch13：W=4/H=1 仅软件参考、RTL 拒绝并置 `cfg_error` ✓（RTL 头注＋change-report L32/L204）；`s_eol/s_eof` 精确、`s_abort`/活动期 `s_sof`/错位 sideband/超长帧 → 中止帧不产 eof ✓。
- ch14：高斯普通复制 vs 去马赛克保奇偶“不是一回事”，混用是真实缺陷类型（change-report L125–127 记录 `gray_clamp` 锚点随修复漂移已同步）✓。
- ch15：首帧恒等/坏帧不更新（`he_bad_frame_keeps_lut`、`st_rejected`）/常量帧 den=0 恒等/同拍同 bin 全计数（`banks4_*`）/帧边界原子发布 ✓；负对照 4 变异体（`gray_round`、`gray_clamp`、`gau_round`、`he_samebin`）在 change-report L147–150 均为“PASS（负对照成立）→拒绝” ✓。

**F-9 漂移引用复核**：change-report（当前版本）§1 打包 lane0=bit[9:0]（L15）＋“打包方向”缺陷记录（L87）、§3 接口冻结表（L77）、§5/§6 负对照（L125–L156）、§8 吞吐（L195–L200）均存在且语义与三章表述一致 ✓；dev-result/source-provenance 的新旧状态差属外部 run 演进，本包正文以“语义＋时点”表述，不构成事实错误。

## 4. engineering（适用：G0/G1）

结果：**PASS**。

**E-1 清单自洽与哈希一致性（先决）**
- manifest 自身 SHA256＝`d5e8d6e8…e52b2b` ✓。
- outputs 6 条全部一致：13＝`d57044a8…`/23888B/232 行；14＝`abe828c3…`/20880B/200 行；15＝`247a9ecf…`/24037B/227 行；ch10＝`f0c6b708…`/28338B/282 行；README＝`ee5e93e3…`/7384B/114 行；link-check-KB4＝`6c02f582…`/11642B/41 行 ✓。
- 前后哈希绑定（KB3-r1 为基线）：ch10 before＝`c6b3283c…`/27755B（=KB3-r1 登记值，逐字节一致）✓；README before＝`315237fb…`/7238B 一致 ✓。

**E-2 格式与编码（字节级实测）**
- 13/14/15、ch10、README、link-check-KB4.json、dev-notes-KB4.md：BOM=False、CR=0、纯 LF、末字节=0x0A；行数 232/200/227/282/114/41/128 与清单一致 ✓（三章在 120–350 区间 ✓）。
- 文件名符合命名澄清（`14_高斯与3×3卷积.md` 去空格；`10_速度等级与1600、1333、800E.md` 用“、”）✓；README 表格标题/链接与实际文件名逐字一致（markdown 链接全部 Test-Path 通过）✓。

**E-3 写范围合规（零越界）**
- 以 KB3-r1 清单 outputs 为基线逐条复算：仅 ch10（F8）与 README（R6）变化；`09`/`11`/`12`、`05`–`07`、`link-check-KB3.json`、`dev-notes-KB3.md` 等全部一致 ✓ —— 即 KB4 未触碰 01–09、11、12 章、`_写作规范.md`、`_全书大纲.md` 与 KB3 记录。
- 磁盘清点：`docs/知识书/` 现为 01–15＋README＋`_写作规范.md`＋`_全书大纲.md`，第 16 章起不存在 ✓（与 README“第 16 章起未写”一致）；未见其它新增/删除（本包产出面＝13/14/15＋ch10＋README＋3 个 run 文件）。
- KB3-r1 输入侧漂移（`dev-plan.md`、`decision-register.md`、`dev-notes-F.md`、`board_verify_ddr1333_…json`、`DDR1333集成与1333vs1600对比…md`、`tasks.json`、技能/合同文件）均为规划者/并行线更新，非本包写操作；其现值与 KB4 清单登记值一致（除 §1 的 6 条在途）✓。

**E-4 F8 逐处最小面（合围＋增量对账）**
- 跨清单哈希绑定（before＝KB3-r1 登记值）＋声明点全命中（三处 after 文本与登记逐字一致）＋**增量完全对账：文件级 +583B ＝ ① +27 ＋ ② +159 ＋ ③ +6 ＋ 版本行 +391，四项相加恰为 583，零残差**＋旧短语零残留（`19:11 起`=0）＋结构不变量（281→282 行，唯一新增行＝版本行；三处内容均为行内替换）✓。
- 边界（如实）：round0 无 `pre-rev/` 副本（R18 自修复轮生效）、git 未跟踪该文件，故无法做字节级 pre/post diff；上述合围＋增量零残差不能从原理上排除“等长互相抵消”的隐藏改动，但该风险判为可忽略（与 KB3 案例被 R18 裁定接受的方法同族且更强）。
- R6 改动面：README +146B（7238→7384）、行数 114 不变；13/14/15 三行为“链接＋已交付”、进度表“当前快照”句＝“第 01–15 章已交付（01 随 KB0、02–04 随 KB1、05–08 随 KB2、09–12 随 KB3、13–15 随 KB4）；第 16 章起未写”✓；16–27 与附录行均为“待创建/未写”，维护规则与既有裁定一致，未见过度改写迹象。

**E-5 路径与交叉引用**
- 13/14/15＋README 中 `../` 相对 token 共 **24 个唯一值全部 Test-Path 通过**（含新建 `link-check-KB4.json`）✓；markdown 链接无失效 ✓；三章反引号内根相对前缀（workflow|tools|algo|fpga|docs|parallel）/ 命中数＝0（无混用残留）✓。
- 交叉引用“第 N 章/见第 N 章”N∈{03,08,13,14,15,16}（各章 3–5 处）均在 27 章规划内 ✓；13–15 正文无“（待写）”（另见 O-5 记录性说明）。

**E-6 link-check-KB4 记录可信与计数自洽**
- 显式 UTF-8 读取后 `ConvertFrom-Json` 通过；entries=17＝入表 15（13=5/14=5/15=5）＋unused 2；summary：attempted 17、verified_pass 17、failed_or_unverifiable 0、distinct_urls 15、table_rows 15 —— 与逐条一致 ✓；字段 schema（chapter/url/title_expected/title_returned/status/checked_at/proposed_state/note）齐备 ✓。
- **独立抽样在线复现（本轮实际 HTTP GET）4/15 条**（en.wikipedia Histogram_equalization、docs.opencv.org 4.x Smoothing Images、zh.wikipedia 高斯模糊、cnblogs 15656881）：全部 **HTTP 200**，标题与登记一致（“Histogram equalization - Wikipedia”“OpenCV: Smoothing Images”“高斯模糊 - 维基百科，自由的百科全书”“OpenCV-Python系列之直方图均衡 - qiaokuankuan - 博客园”）✓；B 站 4 条按规划环境提示未复现；记录口径（“在线核验通过 2026-10-17”、未采用 2 条备查、OpenCV 中文 2.3.2 旧版注记、`bilibili_method_note`）与独立观测不矛盾 ✓。

## 5. system（适用：G0/G1）

结果：**PASS**。

- **S-1 README 13–15 导航与快照句**：三行标题/文件名链接/状态“已交付”与磁盘三章逐字一致 ✓；“当前快照”句与磁盘事实（01–15 存在、16 起不存在）一致 ✓；Part 4–6 与附录“未写”正确 ✓。
- **S-2 章间衔接与项目实际方案**：08→13→14→15→16 阅读链成立（13 前置 08 相位/03 握手；14 输入＝13 的 Y8；15 收束 Part 3 并指向 16 章压缩接口）✓；三章均明确“候选 RTL/软件参考为仿真级、G3/G4 未做、逐像素正确仅限离线向量范围”，与 tasks.json/整合声明一致，未把候选写成已实测、未预判修复结果 ✓。
- **S-3 路径存在性抽样（远超每章 ≥2 条）**：13 章＝`image_algorithms_ref.py`、`bayer_raw10_demosaic4.v`、`rgb8_gray_stream.v`、`img_algo_parallel_top.v`、`oracle_algo.py`、`run_g1.py`、`algo_core.vec` 等 ✓；14 章＝`gray8_gaussian3x3_stream.v`、`gray8_gaussian3x3_frame.v`、`algo_rowwin3.v`、`algo_rowwin_reader.v`、`source-provenance.json`，行缓存量级 3.75KiB/18.75KiB 与双目首版 §7 行逐字一致 ✓；15 章＝`gray8_he_cdfmin_frame.v`、`img_algo_parallel_top.v`、`algo_core.lut.hex`、`change-report.md`、`tasks.json`，HE 口径（22bit/`lut_source_seq`/不做左右各自 HE）与双目首版 §3/§7 一致 ✓。
- **S-4 恢复入口与回退**：同任务若 FAIL 则续本ID→原开发修复（R18 起修复轮先存 `pre-rev/`）；本轮 PASS，KB3 r1 判定继续绑定 `KB3-manifest-r1.json` 快照（F8 后 ch10 由 KB4 清单重新冻结），无需回退动作；下一包 KB5 由原规划按 dev-plan 顺序派发。
- **S-5 硬件层**：纯离线文档任务，无 TD/构建/下载/Flash/GUI/板卡/外部消息动作（与清单 `zero_hardware` 一致）；无位流 SHA/电源/连接/负载/计数需要，硬件类检查整体 N/A。

## 6. G 层状态与适用性（按报告约定）

| G 层 | 状态 | 说明/规划理由 |
|---|---|---|
| G0（规范/大纲冻结） | pass | `_写作规范.md`/`_全书大纲.md`/dev-plan §3 边界一致且未触碰（哈希与 KB3-r1 基线一致） |
| G1（静态核验） | pass | 语义/数字/来源复算、编码/格式、哈希/manifest、路径/交叉引用、链接在线抽样（4/15） |
| G2（构建/时序） | not_applicable | dev-plan §6：纯文档交付，无构建/时序对象 |
| G3/G4/G5 | not_applicable | 同上；无硬件候选、长稳、集成对象（本书不替代 T01–T14） |

## 7. 非阻断观察与记录性提示（交原规划决定处置）

| # | 位置 | 观察（触发→期望/实际→复现） | 影响与建议 |
|---|---|---|---|
| O-1 | `14_高斯与3×3卷积.md` L112（“与本项目方案的对应”表） | 引句“不能用‘接口可1拍1样本’代替服务率”的辅助引注标为“策略 §5”；**该引句逐字存在于 `docs/DeepSeek独立检测与现行方案整合_2026-10-16.md` §3.4（L97）**；策略文档全篇检索无“服务率/1拍1样本/每拍/接口宽度/不能代替/代替”任何一词（§6 有同旨纪律 L159/L161，故该行结论实质成立） | 引注定位错标（同 KB2 r0 O1–O3→R12/F7 一类）。建议下一自然修订轮授权 ch14 单处订正（“策略 §5”→“整合 §3.4”）或由规划明确接受不改；不阻断本轮 |
| O-2 | `15_前帧均衡与三算法.md` L89、L106 | L89“帧末合计约 3.3–3.4k 拍”与 HE RTL 头注 L21–22“<= ~3.3k”一致（章内据实引注）；但 change-report 现值 §2/§8 已为“≤~4.2k/约 4.1k”（外部修复轮漂移）。L106“占比 <0.02%”为 §8 逐字转述；按 §8 自身数字直算（≈4.1k 拍 ÷ 33.3ms@187.5MHz≈6.19M 拍）≈0.066%，即**源数字本身偏乐观** | 属外部 run（T09）记录内部口径问题＋章内“以 run 记录为准”时点余量（R1/R15），不计 KB4 缺陷；建议转告 T09 run 责任方并在下一修订轮按新值更新 |
| O-3 | `13_灰度.md` L111 | 引用 `sum[15:8]`；RTL 实网名为 `sum2[15:8]`（`rgb8_gray_stream.v` L62） | 语义正确、名称微差；可随自然修订对齐，不建议单独开轮 |
| O-4 | `15_前帧均衡与三算法.md` L90 | 监视口 bullet 的“同上 RTL 头注”指认略松：`he_lut_addr/he_lut_data` 为顶层端口（top L85–86/L244；change-report §3 冻结表 L77），HE 模块内部名为 `lut_rd_addr/lut_rd_data` | 事实成立，仅指认精度；记录备查 |
| O-5 | manifest `self_check`（记录性） | “全库无（待写）”字面不严格：该字串存在于**未触碰**的 `_写作规范.md` L81（禁止写法条文自身）；13–15 及各章正文实测 0 处 | KB0 先例（R2/R3）同类表述判“记录性”；建议文字理解为“章节正文无”，无需动作 |

## 8. 未执行项（明确标建议，均不影响本轮门槛）

- 未执行：B 站 4 条链接的本轮在线复现（规划环境提示；登记方法与 API 复核记录已在 link-check-KB4）；link-check 全量 15 条复现（本轮抽 4 条＝26.7%，覆盖维基/官方文档/博客园三类）。
- 未执行（材料不支持）：ch10 F8 的字节级 pre/post diff（round0 无 `pre-rev/`、git 未跟踪）；如需字节级审计，建议自 KB4 修复轮起按 R18 留 `pre-rev/` 由下一轮测试者执行。
- 未执行：ch10 L1–139 逐行重读（本轮读 L140–282 并做全篇残余/结构/增量扫描；前段完好性由 before/after 哈希绑定＋增量零残差间接覆盖）。

## 9. 本轮判定与绑定

- 三维适用项全部满足；G0/G1＝pass，G2–G5＝not_applicable（规划理由）；无阻断、无必需门槛缺失；**总体 PASS**。
- 判定绑定：`manifests/KB4-manifest.json`（SHA256＝`d5e8d6e8224caf88084f9fbbc43d0d5ac649e28354f51837114cb9b198e52b2b`）＋本报告；不拼合其它输入，不外推 RTL/板测/整机结论（本书 PASS 仅覆盖语义/格式/交接层）。
- 受影响输入的复用依据：6 条外部在途漂移（3 RTL＋3 run 记录）归因外部 run（R1/R15），本包引用按“语义复核＋时点余量”成立、无需本任务复测；`main-log.md` 追加型新增（前缀哈希一致）不否定本清单。
- 下一步（供原规划）：读取 §7 决定 O-1/O-2 处置（F 项或接受），更新 dev-plan §11 KB4 收束并派发 KB5；回退入口＝KB3-r1 快照（ch10/README 如需回退以 KB3-r1 值与 KB3-r1 报告为准）。
