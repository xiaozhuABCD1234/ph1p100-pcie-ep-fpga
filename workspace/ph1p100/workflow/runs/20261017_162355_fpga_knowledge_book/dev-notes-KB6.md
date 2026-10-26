# dev-notes-KB6 — 开发过程记录（run 20261017_162355_fpga_knowledge_book）

- 角色：fpga-dev（本任务全新会话）；任务：KB6（收敛第 2 包，传输与系统篇第 21–26 章，轻量档）；日期：2026-10-17。
- 本文件记录：范围与合规、实际读入、写作组织、链接核验过程、项目事实对核、自检、边界与复测影响；精确逐文件哈希/行数/字节以 `manifests/KB6-manifest.json` 为准。

## 1. 任务与写范围

- 依据：`dev-plan.md` §13（收敛权威表：KB6=21–26 章、语义步骤 5、轻量档）、§3 章边界、§5.2 增量约束；`dispatch`（本任务提示元数据）。
- 产物（新建，8 个文件）：`docs/知识书/21_PCIe基础.md`、`22_DMA与完成语义.md`、`23_R10F帧协议.md`、`24_双路与同步.md`、`25_HDMI调试出口.md`、`26_工程方法与证据判读.md`；本 run `dev-notes-KB6.md`、`link-check-KB6.json`、`manifests/KB6-manifest.json`。
- **保护范围合规**：`docs/知识书/` 既有 01–20 章与 README/`_写作规范.md`/`_全书大纲.md` **只读未动**（"已生成的先不改"）；未触碰 `workflow/tasks.json`、`fpga/`、`tools/`、`parallel/`、D 盘工程、其它 run、`main-log.md`；无 TD/硬件/下载/发布/外部消息；未删除任何文件；未派生任何代理。
- 本包**无修复轮**（尚未进入测试）；未使用 `pre-rev/`。

## 2. 实际读入（关键文件与用途，只读）

| 路径 | 用途 |
|---|---|
| run `dev-plan.md`、`input-index.md`、`fpga-design-guide.md`、`requirement.md`、`closeout-KB4.md`、`closeout-KB5.md` | 收敛规则/章边界/事实基线/写范围 |
| `docs/知识书/README.md`、`_写作规范.md`、`第 20 章` | 进度表（不改）、模板 10 节细则、风格基准 |
| `workflow/runs/20261017_161109_decisions_compare_freeze/decision-register.md` | M2a–M2e、M3、M4、M5.3/M5.5/M5.7/M5.8 现值 |
| `workflow/runs/20261016_2110_pcie_unified_path/pcie-unified-path-assessment.md` | 21/22/23 章主体事实（RC/EP、BAR、MWr、4KiB、L0–L6） |
| `workflow/runs/20261017-011744-rk-fpga-align/backend/rk-change-list.md` | 22/23 章 one-shot/ACK/CANCEL、CTRL 0x61/0x161、槽头 128B |
| `parallel/docs/帧与元数据接口合同_2026-10-15.md` | 23 章 R10F 字段/三层 CRC/向量锚点 |
| `workflow/README.md` | 26 章 G0–G5、§5/§5.1 |
| `docs/HDMI彩点_换线换屏后与速率规格核对_2026-10-13.md` | 25 章数字与审计结论 |
| `docs/当前硬件_引脚电气与同步证据.md` | 24 章共享网络/寄存器/时序/最小证据 |
| `.agents/skills/fpga-orchestrator/references/{report,relay}-contract.md`、`fpga-dev/SKILL.md`、`work-limits.md` | 26 章报告约定＋本角色边界 |
| `manifests/KB5-manifest.json` | 上游冻结值对照与清单 schema |

（其余被引用但未通读的项目文件只做 `Test-Path` 存在性核验，见 §6。）

## 3. 写作组织与冻结前修正（PFC）

- 六章统一按模板 10 节；语义步骤 5：21、22、23、24＋25、26（与 §13 一致）；篇幅取轻量档。
- 章间引用只写"见第 N 章"（N∈{01,02,03,04,07,12,16–20,22,23,26,27}），未写"（待写）"标记；README 进度表未触碰（KB7 统一刷新，§13）。
- 关键落点：21=RC/EP→枚举/BAR→TLP/4KiB/DW-valid 坑→M2-A 统一路径；22=授权→held→ACK 三段＋RKA1/CANCEL/错误码；23=R10F 五组字段总览＋四种长度＋三层 CRC＋640B 来源＋adapter 缺口；24=共享 XHS/XVS 主从候选＋SOF≠曝光＋配对撤销；25=TMDS/换算/手册对照/审计边界/4Kp30；26=G0–G5＋§5.1＋fail-closed/负对照+5 分钟判读清单。
- **PFC（冻结前定点修正，非修复轮）**：
  - PFC-1：`22_DMA与完成语义.md` 版本记录 "CANcel"→"CANCEL"（打字残留，替换计数=1，残留检查=0）。
  - PFC-2：`25_HDMI调试出口.md` 自测题 6 答案残留片段 "不可行-space" 改写为规范表述（替换计数=1，残留检查=0）。
  - PFC-3：`21_PCIe基础.md` 引注修正——原引 `../PCIe固定块C2H_接口核对与下一步_2026-10-15.md` 经 Test-Path 与 docs 目录核对**当前未在 `docs/` 检出**（不引用不存在路径）；改为引用 `pcie-unified-path-assessment.md` §1.3 引注的接口核对记录（替换计数=2，该事实原文亦载于评估 §1.3）。
  - PFC-4：`22_DMA与完成语义.md` 决策卡 `closeout-T03-r0.md` 改为完整项目相对路径 `../../workflow/runs/20261017-011744-rk-fpga-align/closeout-T03-r0.md`（替换计数=1）。
  - PFC-5：`22_DMA与完成语义.md` 两处内容补充——误区增补第 6 条（错误码用途）＋数字速查块增补门铃行（目标=phys+mb_off+32，LastDWBE=0）；轻量档下限校准并增加判读价值（替换计数=2）。

## 4. 外部链接核验（过程与结果）

- 方法：会话联网工具对每条候选 URL 发起真实请求并核对返回标题；结果写入 `link-check-KB6.json`（24 条）。
- 过程（如实记录）：①第一次小规模试抓因**调用参数缺失**被工具拒绝（调用方错误，非链接失效）；②修正参数后批量抓取遇**间歇性网络错误**（socket closed / 访问令牌），12 条未获返回；③按"同一失败命令首次＋1 次有据重试"串行重试 12 条——**全部通过**。
- 结果：24/24 `在线核验通过 2026-10-17`；0 降级、0 未采用；3 条落地标题注记（MMIO 全名、TMDS 重定向、zh DMA 消歧义页）已在章内与 link-check 中标注。
- 视频行：对 B 站等平台的 5 条检索返回**关键词建议文本、无可提取的视频 URL**；按"不虚构 URL/标题/时长"纪律，未列视频行，精确检索词写入各章"备用检索词"列（`link-check-KB6.json.searches`）。

## 5. 项目事实对核清单（写作时逐条核对来源）

1. RC/EP、数据面=EP 主动 MWr、BAR 仅控制 —— `pcie-unified-path-assessment.md` §4.1。
2. BAR0 键值：0x40 MAGIC=0x50434946、0xB0/0xB4 目标、0xB8/0xBC 门铃、0xC0–0xCC 计数/状态/错误 —— 同文 §4.2。
3. 128B/笔、20,256（或 20,251）笔/帧、双路≈1.22M 笔/s、门铃单 DW —— 同文 §4.5。
4. 4KiB 跨界（+16B）与 128B 对齐修法；BDF 写死 01:00.0；MPS 128B 保守 —— 同文 §5 R1/R4/R5。
5. 槽头 16B＋112B pad=128B、`dst=phys+128`、门铃 `phys+mb_off+32`、cap≥2,592,768、slot 4KiB 倍数 —— `rk-change-list.md` §1 #2/#5。
6. one-shot/held/ACK/CANCEL 语义与"默认不发" —— 同文 §2；CTRL 0x61/0x161、bit4 保留 —— 同文 §1 #1；RKA1 探针 0x118/0x11C fail-closed —— 同文 §1 #3、§5。
7. 补丁**未编译/未加载**、依赖 RK 环境 —— 同文 §4；M2d/M2e 联调前确认 —— decision-register M2d/M2e。
8. R10F 128B 头字段/偏移/小端 —— `帧与元数据接口合同_2026-10-15.md` §3；三层 CRC 与 0xCBF43926、`crc_byte` 一致性 —— 同文 §7。
9. 2,592,768=633×4096、payload=2,592,000、尾 640B、driver `frame_slot_bytes` —— decision-register M2c；pusher"整 4KB"约束 —— assessment §3.3 C3-A。
10. 严格解析清单（含尾零全 0/session 匹配）与坏帧不进下游 —— `rk-change-list.md` §1 #6/#7；flags —— 合同 §5。
11. 共享 XHS/XVS 网络 R147/R148 100Ω、HS/VS 不引 FEP —— `当前硬件_引脚电气与同步证据.md` §5.1。
12. 主从寄存器 0x3003/0x3002/0x30C0/0x30C1/0x30CC-CD 及待机期配置纪律 —— 同文 §5.2。
13. 24ms/前 8 帧/≥4 INCK/≤5ns —— 同文 §5.3；XHS 不标记像素位置、SOF 为辅助 —— 同文 §5.4。
14. 最小证据 6 条 —— 同文 §6；T08=终点、不以同帧号替代 —— decision-register M5.3；B 路未验收 —— input-index §3.11 基线。
15. 148.5/742.5MHz、1485Mbps、LVDS33_E/DDRX5、2200×1125 —— `HDMI彩点_换线换屏后与速率规格核对_2026-10-13.md`。
16. 手册 650MHz/332Mbps/1250Mbps、差≈14.2% —— 同文（DS1300 v1.2.1 表 3-44/3-52）。
17. 并行路径审计 68 条无违例＋覆盖率 96.40%＋"不证明串行" —— 同文；`docs/evidence/hdmi_routed_audit_20261013.json`（存在性核验）。
18. 4Kp30 ≈297MHz/2.97Gbps、HDMI1.4 340MHz、DDR≈0.5GB/s、未排期 —— decision-register §3.4（rev1）。
19. G0–G5 与边界清单、§5/§5.1 —— `workflow/README.md` §4/§5/§5.1。
20. 报告首行唯一判定/返回元数据 —— `report-contract.md`/`relay-contract.md`；fail-closed 实例（RKA1、构建门禁、0.300 gate） —— 第 22 章/M4/M5.5。

## 6. 自检（对应 `_写作规范.md` §8 清单）

- 模板 10 节：六章均含全部节名（速读卡/问题/正文/对应表/决策卡/误区/自测＋折叠答案/延伸资源/术语增量/版本记录）。
- 篇幅：轻量档（§13 目标 120–220 行/章）；精确行数/字节/哈希见 manifest `outputs`（自检脚本复算）。
- 编码/换行：脚本复算（UTF-8 无 BOM、CR=0 纯 LF；含 link-check、dev-notes；manifest 由脚本复算外由 write 工具落盘后同法复核）。
- 交叉引用与用语：无"（待写）"串；"见第 N 章"均在 01–27 规划内；未把候选/登记写成已实测；组织方口径未写已批准；外部引用单处≤2 句、项目文档只做路径引用。
- 路径存在性：六章引用的项目相对路径（唯一值）逐条 `Test-Path`；全部通过后方冻结（结果与精确清单见自检脚本输出与 manifest 引用路径清单；1 条无效引注已按 PFC-3 修正）。
- 具名修正：PFC-1—PFC-5 已执行并复核（§3）；修订后文件哈希由 manifest 重新冻结。

## 7. 边界与未决（如实标注，不替他人拍板）

- R10F 合同=**提案**（待双方冻结）；23 章 adapter 缺口=**未决**（M2c 触发①）。
- 24 章同步路径=**设计候选/待验证**（内部连接、波形、B 路、T08 均未验）。
- 25 章速率资格=**未决**（官方问题单未发）；彩点根因未证实。
- 21/22 章联调=**未执行**（RK 环境/驱动未编译加载）；L1–L6 未做。
- 本包**未使用 DeepSeek 委派**；未跑 TD/构建/硬件；无外部消息。

## 8. 冻结与复测影响清单（供综合测试）

- `input_status`：**new**（KB6 首轮清单；相对 KB5 冻结：新增 6 章与三个 run 文件；**未变更任何既有文件**——"已生成先不改"直接证据=01–20 章与中央三文件哈希与 KB5 冻结一致）。
- 必测重点：
  - functional：六章要点覆盖与递进顺序；关键数字对核（20,256、2,592,768=633×4096、640B、0xCBF43926、24ms/8 帧/≥4 INCK/≤5ns、148.5/742.5/1485、297MHz/2.97Gbps、14.2%）；22/23 章语义（one-shot/ACK/CANCEL、三层 CRC/四长度）；24 章"SOF≠曝光、同帧号不成立"推理链；26 章 G0–G5 与边界引述一致性。
  - engineering：模板 10 节；UTF-8/无 BOM/LF；24 条资源行核验状态与字段格式化；manifest 哈希一致性；PFC-1/2 替换与残留检查；写范围零越界（与 KB5 冻结清单对核中央三文件与 16–20 章未变）。
  - system：路径存在性抽样；README 进度表"16 起未写"=KB7 预期；与 decision-register M2/M3/M5.3/M5.5、workflow/README、两条 contracts 表述一致。
- 证据复用：无（本包全部新判定）；main-log/任务板/decision-register 若再有并行线更新，按 R1/R15 滚动语义处理。

## 9. 执行工具与预算说明（如实）

- 本任务实际工具调用约 40 次（含：管理性读取 ~15、ML 素材读取 ~7、链接核验 4（其中 2 次因工具/网络错误重试）、写作 6、编辑 2、记录 3、哈希/自检 2），超默认 30 次上限的成因为：dispatch 强制输入清单本身约 15 次读取＋外部链接核验的"首次＋1 次有据重试"及一次参数纠正。
- 未派生任何代理；未使用 DeepSeek；等待/核验命令均设 60s 级超时。

## 10. 结论与下一动作

- 六章＋三记录完成，冻结待测：`manifests/KB6-manifest.json`；本包无修复轮。
- 由原规划者收束并派发**一个综合测试者**（同一冻结输入；integrated 报告）；KB7（27＋附录＋README 终版）待 KB6 收束后派发。
