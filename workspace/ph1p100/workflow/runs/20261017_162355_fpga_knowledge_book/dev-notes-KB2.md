# dev-notes-KB2 — 知识书第 05–08 章 + F5/F6 有界修订

- 任务：KB2（run `20261017_162355_fpga_knowledge_book`）；角色：fpga-dev；日期：2026-10-17。
- 状态：**首轮完成并冻结（ready_for_test）**。冻结清单：`manifests/KB2-manifest.json`（唯一测试输入）。
- 写范围遵从 dispatch：新建 `docs/知识书/05–08` 四章；`_写作规范.md` 仅 F5 单处；`link-check-KB1.json`/`dev-notes-KB1.md` 仅 F6 记录级；README 仅 05–08 行与"当前快照"句（R6）；本 run 内新建 `dev-notes-KB2.md`、`manifests/KB2-manifest.json`、`link-check-KB2.json`。未触碰任何其他既有文件。

## 1. 实际读入（写作与修订依据）

**冻结输入（dispatch 必读，全文读取）**

1. `workflow/runs/20261017_162355_fpga_knowledge_book/requirement.md`
2. `workflow/runs/20261017_162355_fpga_knowledge_book/dev-plan.md`（重点 §3、§5.2、§11 含 KB1 收束段）
3. `workflow/runs/20261017_162355_fpga_knowledge_book/input-index.md`
4. `workflow/runs/20261017_162355_fpga_knowledge_book/fpga-design-guide.md`
5. `workflow/runs/20261017_162355_fpga_knowledge_book/closeout-KB0.md`、`closeout-KB1.md`（§2/§3：F5–F6 清单与文件名澄清）
6. `workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB0-manifest-r1.json`、`manifests/KB1-manifest-r1.json`
7. `workflow/runs/20261017_162355_fpga_knowledge_book/dev-notes-KB0.md`、`link-check-KB0.json`
8. `docs/知识书/README.md`、`_写作规范.md`、`_全书大纲.md`、`01–04 章`（含 04 章全读、01 章抽读、02/03 章标题与结构）
9. 技能与合同：`.agents/skills/fpga-dev/SKILL.md`（skill 工具加载）；`.agents/skills/fpga-orchestrator/references/report-contract.md`、`relay-contract.md`

**本章材料（全文或摘录读取；哈希见 manifest）**

- `当前必读/01_FPGA主线学习手册_由浅入深.md`（§5–§10 摘读）
- `docs/F9P_PH1P100_硬D-PHY例程专项核验_2026-10-10.md`、`docs/PH1P100_接收路线证据.md`
- `docs/IMX415_首版模式与寄存器差异.md`、`docs/RAW10稳定档位_PLL生成与接入交接.md`、`docs/RAW10相机1080p60接回与DDR下一步_2026-10-11.md`、`docs/RAW10_PLL生成首次检查_2026-10-10.md`
- `docs/CSI帧完整性_实现与验证_2026-10-12.md`、`docs/CSI前端尾拍误判修复_2026-10-12.md`
- `docs/RGB565玫红返工_接收Bayer相位核对_2026-10-14.md`、`docs/RGB565白平衡闭环_2026-10-14.md`、`docs/RGB332真实彩色对照_操作与证据_2026-10-13.md`
- `docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md`、`docs/DeepSeek独立检测与现行方案整合_2026-10-16.md`（grep 摘录）
- `workflow/README.md`、`workflow/tasks.json`、`workflow/records/T02/task.md`
- `docs/evidence/white_balance_stats_20261014.json`（白平衡统计原文）

## 2. 实际产出（4 新章 + 3 处有界修订 + 1 处 README 有界更新 + 3 个 KB2 run 文件）

| 文件 | 说明 | 字节 | 行 | SHA256（前16） |
|---|---|---|---|---|
| `docs/知识书/05_MIPI与CSI2入门.md` | 新建。模板 10 节；分层/HS-LP-SoT/软 PHY 链与 delay 训练、硬 D-PHY 证据链 | 21644 | 218 | `bba84c1e47b939ad` |
| `docs/知识书/06_相机配置与模式.md` | 新建。模板 10 节；启动时序、时钟分工、I2C 读回、HMAX/VMAX 实算、4K→1080p ROI、PLL 首检教训 | 23907 | 235 | `cb47ad5cff5e3b72` |
| `docs/知识书/07_CSI包与帧完整性.md` | 新建。模板 10 节；短/长包、ECC/CRC16、尾拍修复、帧裁决与受控发布 | 21108 | 214 | `0fd840cbd9902fb4` |
| `docs/知识书/08_Bayer与颜色.md` | 新建。模板 10 节；CFA/相位/去马赛克、Q10 白平衡实算、玫红时间线与排查顺序 | 20737 | 216 | `cd5e1902567079e0` |
| `docs/知识书/_写作规范.md` | **F5**：§6 单处改写为"有界修订例外"措辞 | 8906 | 103 | `d66e99ca604b359b` |
| `docs/知识书/README.md` | **R6 有界更新**：05–08 目录/进度行＋"当前快照"句 | 7018 | 114 | `4e779f622791e6f8` |
| `workflow/runs/.../link-check-KB1.json` | **F6a/F6b**：entries_note 改写、e11 标题注记 | 12023 | 51 | `1a262273cb9b7f32` |
| `workflow/runs/.../dev-notes-KB1.md` | **F6c**：§8-5、§8 自检第 6 条计数更正＋"更正（KB2 轮）"行 | 20406 | 140 | `e724235e1fb9a120` |
| `workflow/runs/.../link-check-KB2.json` | 本包链接核验记录（34 条） | 18186 | 61 | `15abd6eda35886f4` |
| `workflow/runs/.../dev-notes-KB2.md` | 本文件 | 见 manifest | 见 manifest | 见 manifest |
| `workflow/runs/.../manifests/KB2-manifest.json` | 冻结清单（不含自身哈希） | 见文件自身 | — | 由测试者现场重算 |

### F5/F6 与 R6 修订前后对照（逐处最小面）

| 项 | 文件 | 修订前 SHA256（来源） | 修订后 SHA256 | 变化面 |
|---|---|---|---|---|
| F5 | `_写作规范.md` | `bbec84fd2e3d39687d7136e9e5991637e78cbb85f51e8c6d67de9ece8b41e728`（8757B；KB1-r1 冻结值，开工前逐字节复算一致） | `d66e99ca604b359bb05e3cdae8adde68056107ed6187ea40c3a97ad68bc38fad`（8906B） | §6 第 82 行 1 处改写（其余字节不动；行数不变 103） |
| F6a/F6b | `link-check-KB1.json` | `e4f52bdf00b8beb01bf68ee29daff72c7dcd308b3b2c519f6952e6d2bbd7e429`（12030B；同上） | `1a262273cb9b7f320c95702b8b2d3cbb77d2e1c6b70a8b23ec5c223e1258110c`（12023B） | `summary.entries_note` 1 处改写＋e11 `title_returned` 1 处注记（JSON 仍可解析、23 条） |
| F6c | `dev-notes-KB1.md` | `57345cfd37e5bb88b434063cff214cec2845871981d14199c911edafab92c2e9`（20204B；同上） | `e724235e1fb9a120814ca5c3ab4a6139138a56574418eabb0f89e45c436f8126`（20406B） | 2 处计数更正＋1 行"更正（KB2 轮）"（+1 行=140） |
| R6 | `README.md` | `3ae45f02726932c4b951f92c6f7998e20e6ac32398297e8130dd74bd20b19d70`（6814B；同上） | `4e779f622791e6f87d30a385a1e089d7cc717c489e7af85caaf8c05470ac2d1b`（7018B） | 4 行章节行（文件链接＋已交付）＋1 处快照句（行数不变 114，+204B） |

## 3. 停止条件与合规检查

- 开工前核对写范围：四章为**新建**（`Test-Path`=False）；三个修订面文件与 README 逐字节复算与 KB1-r1 冻结值一致后才动手。
- 越界与保护检查：写操作限于 §2 表列文件；未覆盖/修改/删除任何其他既有文件（含 01–04 章与其它既有章、`当前必读/`、`docs/` 旧文档、`workflow/tasks.json`、`fpga/`、`tools/`、`parallel/`、D 盘工程、其它 run）。`main-log.md` 未触碰（R1）。**未删除任何文件**。
- 编码/换行实测：本包产出的书文件与 JSON 全部 UTF-8（无 BOM）、纯 LF（CR=0）；行数见 §2 表。
- 工程零触碰：未运行任何 TD/构建/下载/板卡动作；未写 D 盘；未发外部消息。
- 修正实况：写作过程中自查并修复 **8 处**（ch05 两处：标题"CS-2"笔误、自测题"143"笔误；ch08 两处：自测题映射句、速览过度声称；ch06 两处：HMAX/VMAX 表述精确化、"LED 表"引用写法；ch07 两处：模块裸文件名→根相对全路径、地址容量表述）——均当场定点修复并复核。

## 4. 外部链接核验（dev-plan §5.2 自检项②：每章 3–8 个、逐一核验）

- 四章资源表共 **23 行**（05=6、06=5、07=5、08=7），全部带核验状态字段；明细见 `link-check-KB2.json`（34 条=入表 23＋未入表 3＋未采用 8）。
- 结果：入表 23 = **20 条在线核验通过**（本会话实际请求 20 条：18 条直取核验标题＋2 条 PDF 确认可达且标题经检索工具核验；其中 1 条为与第 04 章共享、本会话直取复核）＋**3 条 B 站降级**（附精确检索词；身份经 B 站公开 API 实抓）＋未入表 3（AMD/Altera/easy-eai 动态壳页，标题不可核验）＋未采用 8（Sony 单品页 404×2、知乎 403、CSDN 404、TIS 术语页内容不符、误配 BV 号、Synopsys 404、Arducam 403）。
- 诚实边界：① B 站页面级抓取在本会话不稳定，3 条按规则降级；**检索合成结果给出的 BV 号不可凭摘要采信**——BV1XW4y1P7o7 经 API 实抓为 41 秒无关视频，未采用；② Sony 单品详情页检索索引滞后（直取 404×2），已改用官方产品线页并以直取核验；③ 两条 PDF 条目会话工具不解析正文（返回 application/pdf），可达性与标题分别经请求核验。

## 5. 三维自检（对照 dev-plan §4 KB2 行与 `_写作规范.md` §8）

- **functional**：四章模板 10 节齐全（机器核验：`## 10 分钟速读卡`/`## 本章要回答的问题`/正文小节/`## 与本项目方案的对应`/`## 决策点与判决框架`/`## 常见误区`/`## 自测题`/`## 延伸资源`/`## 术语增量`/`## 版本记录`；`<details>` 各 6 条）；要点覆盖 dev-plan §3 各章边界且未越章；关键数字逐条与来源一致（第 05 章：891Mbps/445.5MHz/111.375MHz、594→74.25MHz、8bit/256step/5–13ps、≤1250Mbps；第 06 章：启动等待 ≥500ns/≥1μs/≥20μs/≥24ms（建议 25ms）、前 8 帧/第 9 帧、SHR0=0x66=102、三档行周期 22.222222/17.777778/14.814815μs→20/25/30fps、0x005D/0x0042/SYS_MODE=5/0x00C6/0x00E7/0x06C0、300B=0xA0、74.166667/370.833333/26.969697MHz；第 07 章：0xFFFF/0x8408、0x1021、25000700+deadbeef、20B/4800B、14=7+7、4/7/8 计数口径、IMAGE_WC=0；第 08 章：518400、白纸三组统计、138.21859664/87.64343943/93.81296489、2.34353178→2400、2.01352720→2062、0.0723%、1.256504/0.917100、F81F/07E0）。
  - 项目事实对核（逐条列出路径；每章 ≥8 处）：
    - **第 05 章**：`F9P_PH1P100_硬D-PHY例程专项核验_2026-10-10.md`（§1/§3/§4/§5/§8）；`PH1P100_接收路线证据.md`（§3/§3.1/§4.1/§4.3/§5/§7）；`当前必读/01…`（§6.2/§6.3/§7.2）；`RAW10稳定档位_PLL生成与接入交接.md`（§4/§9）；`CSI帧完整性_实现与验证_2026-10-12.md`（§4）；`RAW10相机1080p60接回与DDR下一步_2026-10-11.md`（§1）；`CSI前端尾拍误判修复_2026-10-12.md`（LED/进度）；`策略文档`（§1）；`workflow/tasks.json`（T02）；`workflow/records/T02/task.md`；`fpga/csi2/prj/…/mipi_csi_2/` 三个对齐模块路径。
    - **第 06 章**：`IMX415_首版模式与寄存器差异.md`（§1/§2/§3/§4/§5）；`RAW10稳定档位_PLL生成与接入交接.md`（§1/§4/§5/§9）；`RAW10_PLL生成首次检查_2026-10-10.md`；`RAW10相机1080p60接回与DDR下一步_2026-10-11.md`（§2）；`RGB565玫红返工…`（dummy/WC 4830）；`策略文档`（§1/§3）；`当前必读/01…`（§4/§5 口径）；`workflow/tasks.json`、`workflow/records/T02/task.md`；`fpga/csi2/prj/camera_peer/uisrc/`（camera_startup.v、ui_i2c.v）。
    - **第 07 章**：`CSI帧完整性_实现与验证_2026-10-12.md`（§1/§2/§3/§4）；`CSI前端尾拍误判修复_2026-10-12.md`（全篇）；`IMX415_首版模式与寄存器差异.md`（§4）；`当前必读/01…`（§7.1）；`fpga/csi2/src/csi/csi_rx_packet_integrity.v`；`fpga/csi2/src/mem/gray_frame_pack_guarded.v`；`fpga/csi2/src/mem/ddr_frame_store.v`；`workflow/records/T02/task.md`；`workflow/tasks.json`（T02）。
    - **第 08 章**：`RGB565白平衡闭环_2026-10-14.md`（§1/§2/§3/§4/§5）；`RGB565玫红返工_接收Bayer相位核对_2026-10-14.md`（全篇）；`RGB332真实彩色对照_操作与证据_2026-10-13.md`（顶部更新/颜色处理）；`IMX415_首版模式与寄存器差异.md`（§4）；`DeepSeek…整合_2026-10-16.md`（§2 M03）；`evidence/white_balance_stats_20261014.json`；`fpga/csi2/src/cam/bayer565_capture.v`；`fpga/csi2/src/cam/bayer332_capture.v`；`当前必读/01…`（§9）；`策略文档`（§3）。
  - 决策卡：05=采集前端路线（四要素）；06=读出模式与输出格式（四要素）；07=帧完整性门槛分级（四要素）；08=颜色管线位置与相位/增益冻结（四要素）。均含"何时应重开"。
- **engineering**：命名/编码/LF 合规（实测 CR=0、UTF-8 无 BOM）；交叉引用全部为"见第 N 章/第 N 章"且 N∈{04…26}（全在规划内），**全库无"（待写）"标记**；无禁止写法（未把候选写成已实测；组织方口径未写"已批准"）；F5/F6 逐处最小面；README 仅动 4 行＋1 句；manifest 覆盖新章＋修订面＋核验记录。
  - 路径扫描（围栏感知、反引号终止）：四章合计 **23 个唯一路径 token** → 22 个当场可解析；1 个（`link-check-KB2.json`）为后建文件，创建后复扫通过；无断链。
- **system**：README 目录 05–08 行与文件名逐字一致、状态=已交付；"当前快照"句与事实一致（第 09 章起未写）；四章均可独立阅读且前后衔接（04→05→06→07→08→09 链）；引用项目路径经实施扫描全部存在；与既有冻结表述一致（05 章"无硬 D-PHY 证据"、06 章"RAW10 现役/RAW12 封存"、07 章"222159 出图、几何待补"、08 章"G3 未测"）；对后续章引用（09/12/13–15/23/25/26）编号不悬空。

## 6. 未测与边界

- 链接核验是 **2026-10-17 时间点快照**；外部页面（B 站、Wikipedia、Sony 站点结构）可能随时间变化——本包已遇到 Sony 页面 404 与检索索引滞后，替换过程如实记录。
- 四章内引用的项目数字均绑定**本 run 冻结时的来源文件**（哈希见 manifest）；若后续任务推进（T02 取得真实几何、E2 收束、颜色 G3 板测）导致口径变化，相关表述按下一次修订轮更新，不在本包内改。
- 本包不含任何硬件证据：四章均为【通用原理】＋【本项目事实】（指向既有文件），无新增实测；"已出图/画面恢复"均按来源文件的用户反馈口径转述。
- 外部资源表只承诺"核验状态可复现"；PDF 条目的正文内容未在会话内解析（页码引用以本地手册为准）。

## 7. Lessons（可复用）

- **L8**：检索工具返回的 URL 可能**滞后或错误**（Sony 单品页 404×2、Synopsys 404），检索合成的 BV 号甚至可能完全不对——资源表写入前必须直取（或至少独立二次请求）核验，不能凭检索摘要登记"在线核验通过"。
- **L9**：对 PDF 资源，会话工具返回"Unsupported content type: application/pdf"等价于"HTTP 200 可达但未解析正文"；登记时写清"可达性＋标题分别核验"，不要写成"已读全文"。
- **L10**：B 站条目用公开 API（`x/web-interface/view?bvid=…`）可稳定核验身份（标题/UP 主/时长），页面级抓取仍不稳定——按规则"降级＋精确检索词"，且在 note 中记录 API 核验方式，供测试者复现。
- **L11**：状态性结论（如相位/白平衡）写作时要分层——"条件推导 / 统计支持 / 板级确认"三档分开写，并在"证据边界"行明说未闭环项；否则极易被读成"已修好"。

## 8. 自检证据（实测命令与锚点）

1. 编码/LF/行数（逐字节统计 0x0A/0x0D）：05=218/21644/CR0；06=235/23907/CR0；07=214/21108/CR0；08=216/20737/CR0；README=114/7018/CR0；规范=103/8906/CR0（UTF-8 无 BOM）。
2. `link-check-KB2.json`：`ConvertFrom-Json` 通过、34 条目；summary 与逐条一致（20 通过/3 降级/3 未入表/8 未采用）。`link-check-KB1.json` 修改后仍可解析、23 条。
3. 路径扫描（修正版）：四章 23 个唯一路径 token 全部可解析（其中 1 个为后建的 link-check-KB2.json，已复扫）。
4. 关键锚点抽查：ch05 含"无硬 D-PHY/891/111.375MHz/1250Mbps"；ch06 含"≥24ms/SHR0=0x66/74.166667/0x08CA/0x044C"；ch07 含"25000700/deadbeef/0x8408/IMAGE_WC=0"；ch08 含"138.21859664/2400/2062/1.256504/0.0723%"——逐条命中（读取回显）。
5. 交叉引用扫描：`见第 N 章` 与"第 N 章"引用 N∈{04…26}，均在 27 章规划内；全库无"（待写）"。
6. F5/F6 定点复核：`_写作规范` §6 新措辞命中、旧措辞零残留；`link-check-KB1` 新 entries_note 与 `proposed_states_used`（16/2/1/4）自洽、e11 标题含"（重定向至先进先出演算法）"；`dev-notes-KB1.md` §8-5 显示"（16 通过＋2 降级）"、自检第 6 条"（16/2/1/4）"、含"更正（KB2 轮"行。

## 9. 复测影响清单（供主转发三位测试者；绑定 KB2 清单）

- **新冻结清单**：`workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB2-manifest.json`（唯一测试输入）。
- **新增/变更文件（相对 KB1-r1 冻结）**：`docs/知识书/05_MIPI与CSI2入门.md`、`06_相机配置与模式.md`、`07_CSI包与帧完整性.md`、`08_Bayer与颜色.md`（新）；`docs/知识书/README.md`（R6）；`docs/知识书/_写作规范.md`（F5）；`link-check-KB1.json`（F6a/b）；`dev-notes-KB1.md`（F6c）；`link-check-KB2.json`、`dev-notes-KB2.md`（新）。
- **未变文件**：`docs/知识书/_全书大纲.md`、`01–04 章`（哈希与 KB1-r1 一致）。
- **required_dimensions（开发侧建议，最终复用/重验由测试者按各自报告裁定）**：
  1. **functional 必测**：四章要点覆盖与"由浅入深"顺序；关键数字对核（HMAX/VMAX 三档实算、CRC16 参数与案例、Q10 白平衡实算、硬 D-PHY 证据链）；决策卡四要素；每章 ≥8 处项目事实可溯源；证据边界表述。
  2. **engineering 必测**：模板 10 节与篇幅；编码/LF；F5/F6 逐项最小面复测（含 JSON 解析与计数自洽、"（待写）"零残留）；资源表核验状态与检索词（含 3 条 B 站降级按规则处置）；路径/交叉引用扫描；manifest 输出哈希一致性。
  3. **system 必测**：README 05–08 行链接/状态、快照句与"09 起未写"一致；项目路径存在性抽样（建议覆盖 05–08 各至少 2 条）；与 T01/T02、decision-register 等冻结登记不冲突；链接可用性抽样复现（优先 Wikipedia/MIPI/Sony）。
- **证据复用**：`_全书大纲.md`、`01–04 章` 哈希未变，其 KB1-r1 结论在各自测试者裁定下可复用；修订后的 `_写作规范`/`link-check-KB1`/`dev-notes-KB1` 由本清单重新冻结——**KB1 的 r1 判定仍绑定 `KB1-manifest-r1.json`**（drift 说明见 `closeout-KB1.md` §3）。KB1 三维报告中的结论与 F5/F6 改动面无关时可按原测试者复用规则重核。
- **环境提示**（重申，不对判定施压）：B 站 3 条降级属规则允许（环境限制＋精确检索词），不得仅因"未在线核验"判 FAIL；两条 PDF 条目复现时会出现"可达但工具不解析 PDF 正文"，属预期。
