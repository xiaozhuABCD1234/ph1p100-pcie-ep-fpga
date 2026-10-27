### 判定：FAIL

## 基本信息

| 项 | 值 |
|---|---|
| task_id / dimension / round | KB1 / functional / 0 |
| 测试日期 | 2026-10-17 |
| 测试者 | fpga-tester-functional（全新会话独立第三方；只读核验，未修改任何输入/既有文件；本报告为唯一写入） |
| 项目根（工作树） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道` |
| 冻结清单 | `workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB1-manifest.json`；测试者现场复算 SHA256=`b1e1dbdd3efe7b7f9a3df95053b6cd9f594c39130fa11aba8e012110ca44a2a8`（与冻结声明一致） |
| 工具版本 | PowerShell 5.1 `Get-FileHash`（SHA256）；Python 3.11.5（`parallel/frame/frame_contract.py` 只读复跑）；文本读取/检索。未使用 TD/构建/下载/上板工具（不适用） |

## 1. 本维度范围与通过阈值（按规划）

- 范围（规划者已冻结）：**内容正确与覆盖**——02–04 章与 dev-plan §3 边界、`_写作规范.md` 模板一致；事实、术语、来源真实相符；F1–F4 修订符合 closeout-KB0 §3；边界与故障拒绝表述合理。不检查构建/时序/上板。
- G 层：**G0+G1 适用**；G2–G5 不适用（规划理由：纯文档交付，无综合/STA、位流/板测、长稳、端到端对象——`fpga-design-guide.md` §6/§8）。上板/时序类 N/A，未启动无关工具。
- 通过阈值：抽样对核通过、事实可溯源且与来源一致、模板 10 节与决策卡四要素齐备、F1–F4 逐项符合。任一事实性错误未澄清即 FAIL。

## 2. 逐层结果

- G0：**pass** — manifest 自哈希复算一致；41 组登记条目逐一复算：40 组与清单一致（含 3 处修订文件 before=KB0-r1 登记值、after=冻结值、字节数与声明一致；三章输出字节数 28253/25384/23476 与声明一致）；`main-log.md` 相对快照增长（6076→7033B、首行未变、含 KB1 追加内容），按 R1 滚动语义处置，不判 FAIL。
- G1：**fail** — 1 项事实性错误（D1）+ 1 项次要事实不完整（D2）；其余抽样对核通过（见 §3）。
- G2/G3/G4/G5：**not_applicable**（规划理由同上）。

## 3. 抽样对核（通过项摘要）

| # | 检查项 | 章节 | 实际核验结果与证据 |
|---|---|---|---|
| 1 | 0.000 账目展开 `5.000−4.559−0.267−0.064−0.110=0.000` | 02 | 复算=0.000；与 `docs/RGB565时序裕量优化_2026-10-15.md` L9 一致 |
| 2 | 四轮表 4.747/0.001、4.887/≈0.290/−0.177、0.001/0.008 | 02 | 与 RGB565 文档 L32/L38/L54 一致；5.000−4.747−0.252=0.001、5.000−4.887−0.290=−0.177 复算成立 |
| 3 | guard−nominal=−0.477−(−0.177)=+0.300 | 02 | 复算=+0.300；RGB565 文档 L52 一致 |
| 4 | 114913 nominal 负值=未通过、无位流 | 02 | 证据 JSON `docs/evidence/camera_rgb565_timing_20261015_114913.json` `objective.accepted=false`、无 bit（L694-L718） |
| 5 | PLL 配方 50×80÷3÷2≈666.67MHz；1333 用户域≈166.7MHz/≈6ns | 02 | T01 run `dev-plan.md` §1.4（L22）逐项一致 |
| 6 | 66/68 组 + 显式组数规则（禁自证完整） | 02 | T01 §1.11（L29）+ RGB565 文档 L40 一致 |
| 7 | HDMI 覆盖 96.40%（route 97.75% 未解） | 02 | decision-register M3（L107）一致 |
| 8 | 白平衡 233658：setup −1.849/TNS −24.474 | 02 | `workflow/README.md` L3 一致 |
| 9 | `--min-setup-ns 0.3` 与组数/违例端点门禁 | 02 | 工具源码实读（`tools/td/check_timing_margin.py` L27-36/L43/L53-56）；002820 66 组均 0、未达目标→exit1（RGB565 L31） |
| 10 | 异步 FIFO：WIDTH=258、格雷码+两级同步、`async_reg`/`dont_touch`、读预取保持、"SWUG106 §4.3.6" | 02/03 | `fpga/csi2/src/mem/capture_async_fifo.v` 实读（参数 L4、注释 L2-3/L13-15、prefetch L19-23/L34） |
| 11 | 帧槽四态/围栏 256bit 回读/注释原文/"ready 丢失清槽+仅活动写入计 drop" | 03 | `fpga/csi2/src/mem/ddr_frame_store.v` 实读（L20、L96-99、L105-114、L5、L66-70） |
| 12 | 策略 §3"停顿必须保持 data 与全部 sideband" | 03 | 策略文档 L53 一致 |
| 13 | 手册 §10.1 valid 互等引句、§10.2 缓存满策略引句 | 03 | `当前必读/01_…` L270/L276 一致（转述精确） |
| 14 | 整合 M09 五段所有权、§3.4 drop_count 修正 | 03 | 整合文档 L31/L75 一致 |
| 15 | 148.5MHz/124.416 Mpix/s（需求预算） | 03 | 复算 2×1920×1080×30=124,416,000；策略 §6（L155）一致；148.5MHz 见 M3/工程注释 |
| 16 | 2,592,768=128+2,592,000+640=633×4096 | 04 | 复算成立；decision-register M2c（L91）一致 |
| 17 | 2400B/行、u16 3840B/行、155.520/194.400MB/s | 04 | 复算成立；合同 §4、策略 §6（L156）一致 |
| 18 | 合同 §2/§3/§7：全字段小端、128B、`header_bytes` 自描述、三条 CRC 覆盖、CRC32 四要素+检查值 0xCBF43926、清零 0x58 | 04 | `parallel/docs/帧与元数据接口合同_2026-10-15.md` §2/§3/§7 逐项一致 |
| 19 | 参考实现自检与 8×4 向量（只读复跑） | 04 | `python parallel/frame/frame_contract.py --selftest` → 9/9 True、`FRAME_CONTRACT PASS`、exit 0（含 6 组样本 zlib≡RTL 复刻断言、width%4/未知 format 拒绝、篡改检出）；`--verify …frame_8x4_packed.bin` → `FRAME_VERIFY PASS`、exit 0，raw/payload/header CRC=0x2D7DD2E6/0x4200962E/0x257C5986 与合同 §8 数值一致；章节端序示例 `E6 D2 7D 2D`→0x2D7DD2E6 与该向量字节一致 |
| 20 | 774→800B 缺 adapter 实证、`raw_bytes>payload_bytes` 报错；`codec_id=99`/`FLAG_BAD`/`bayer_phase=99` 三例 CRC 通过仍放行 | 04 | 整合文档 §3.1（L49-L53）/§3.2（L57）一致 |
| 21 | F1：大纲 09 行新措辞 | 大纲 | `_全书大纲.md` L65="…理论峰值（数据率×位宽；×32 例：1600Mbps→6.4GB/s）"，与 closeout §3 F1 一致；字节 +50B 与声明一致 |
| 22 | F2/F3：规范 §6/§8 退役"（待写）"、§1 追加根相对句 | 规范 | L81/L100/L22 与 F2/F3 一致；全库扫描"待写"仅在该规范退役说明中出现 2 处（预期保留），其余 6 文件 0 处 |
| 23 | F4：README 01–04 行/链接/状态、快照句、维护规则有界更新 | README | L22/L28-31/L99/L102 与 F4/R6 一致 |
| 24 | 决策卡四要素齐备；模板 10 节；自测 6 条/章（含答案）；误区 ≥3；对应表含证据边界行 | 02–04 | 逐章核读成立（02×1、03×2、04×1 决策卡均含 选项/权衡/当前选择/重开触发） |
| 25 | B 站两条降级处置（环境限制） | 02 | 两行均含"无法在线核验（原因）"+精确检索词，无虚构标题；符合 `fpga-design-guide.md` §5 与 manifest `retest.environment_note`，**不作为 FAIL 依据** |

## 4. 缺陷

### D1（FAIL 依据，必须修复）ch02 L119：guard/nominal 违例计数与"零违例"表述与来源及证据相反

- 位置：`docs/知识书/02_时钟复位与余量.md` L119（"为什么'零违例'只是起点"节）。
- 触发条件：阅读 ch02 L117-119，并与 RGB565 文档 L52 及 114913 证据 JSON 对照。
- 章节原文（摘）："【本项目事实】114913 的 guard 报告 stats 合计 13 个违例端点计数、nominal 反而"零违例"——同一个物理实现，两种账面。"
- 期望（冻结来源口径）：
  - `docs/RGB565时序裕量优化_2026-10-15.md` L52："nominal setup TNS−1.694 ns，68组统计合计13个报告违例端点计数"；guard=−0.477（L52/L63）。
  - `docs/evidence/camera_rgb565_timing_20261015_114913.json` L728-749（实读）：guard setup=−0.477、`violating_endpoints=**116**`；nominal setup=−0.177、`violating_endpoints=**13**`；`objective.accepted=false`（L717-718）。
  - 即：**13 个违例端点是 nominal 的账面；guard 是 116；两个报告都不是"零违例"**。
- 实际（章节）：把 13 记到 guard、并把 nominal 说成"零违例"——双层错误；且与本章 L88 表格（114913 nominal −0.177）与 L93（"nominal 是负的……没有通过"）自相矛盾。
- 影响：该句是"零违例≠够余量"教学论点的论据；论点本身成立（002820：66 组违例端点均 0 但未达 0.3 目标，RGB565 L31），但例句教反了事实，会把负时序候选描述成零违例，直接误导读者对该案例的判断。
- 建议修复方向（供开发）：改为按证据表述，如"114913：guard 报告 116 个违例端点计数 / nominal 报告 13 个（setup −0.177，均非零）——同一物理实现两种账面"；或将该例替换为 002820 的"零违例但 0.000ns"。修复需按 `_写作规范.md` §6 更新版本记录，并重冻结新 manifest。

### D2（次要，建议同轮修复）ch03 L117：drop_count 计数枚举与 RTL 不完全一致

- 章节原文（摘）："`drop_count` 只在'ready 丢失且确有活动写入'或'主动 abort/写长度不符'时 +1"。
- RTL 实读（`fpga/csi2/src/mem/ddr_frame_store.v`）：除上述情形外，L108-109 在栅栏（fence）校验失败（`fence_rlast!==1'b1||fence_match!==8'hff`）时同样 `drop_count<=drop_count+1'b1`（并计 `error_count`）。章节以"只在……或……"作排他枚举，与 RTL 不符。
- 影响：低（该句主旨"不是每次 ready 抖动都记一笔、也不是逐帧完整账本"与整合 §3.4 一致）；建议补"或围栏校验失败（坏帧）"。

## 5. 观察项（不构成本轮 FAIL 依据）

- O1 ch03 L34："一个 8×4 的合成帧经过三层流水，延迟多 2 拍……14 拍就可能致命"整段带【本项目事实】标记，但"三层流水/+2 拍/14 拍"无可溯来源（8×4 合成帧本身有向量来源 `parallel/evidence/frame_contract_20261015/`）。建议改标【通用原理】或例示句式。
- O2 ch03 L156 决策卡"当前选择"中"DDR/传输侧按帧粒度所有权管理（D）"的"（D）"指代歧义（选项 D=加更深 FIFO，与前后文冲突）；建议改"（帧粒度队列，见第 12 章）"。
- O3 `link-check-KB1.json` `summary.used_note`："21 = 16 条不重复 URL + 1 条重复计入"计数不成立——三章资源表 21 行=18 条不重复 URL+3 条重复计入（跨时钟域、Clock_domain_crossing、先进先出各重复 1 次）；且仅列 1 条共享 URL。另 `Asynchronous_circuit` 条目 note 称"第 02/03 章延伸资源共用"，但两章资源表均未列入（属未采用候选项）。建议交 engineering/规划决定是否同轮修复。
- O4 ch02 L92 "77% 是布线 Net"：直接复算 3.465/4.559=76.00%；"77%"沿用来源（RGB565 文档 L9）口径。非 KB1 新增错误；供后续自然修订参考。
- O5（规划层）`_写作规范.md` §6 仍写"不修改 `README.md`…（仅 KBZ 可终版）"，与 R6/F4 后的 README"各写作包可有界更新本包章节行"存在文字张力；F2 按 closeout §3 逐处执行无误，是否在下轮一并澄清由规划者裁定。

## 6. 实际执行的命令与证据（节选）

1. 清单自哈希与 41 项复算（PowerShell，只读；工作目录=项目根）：`MANIFEST_SELF=b1e1dbdd…a2a8`；逐项输出 OK/DIFF（40 OK + `main-log.md` DIFF，按 R1 滚动语义处置）；三处修订文件 before 值对 KB0-r1 复算一致、after 值对清单一致。
2. `python parallel/frame/frame_contract.py --selftest` → 9 项全 True、`FRAME_CONTRACT PASS`、exit 0。
3. `python parallel/frame/frame_contract.py --verify parallel/evidence/frame_contract_20261015/frame_8x4_packed.bin` → `FRAME_VERIFY PASS`、exit 0；CRC 十进制 763220710/1107334702/628906374 = 0x2D7DD2E6/0x4200962E/0x257C5986。
4. 算术复算：2,592,000+128+640=2,592,768、÷4096=633；2400×1080=2,592,000；guard−nominal=+0.300；展开式=0.000；2×1920×1080×30=124,416,000 pix/s；155.52MB/s。
5. 全库"（待写）"扫描：仅 `_写作规范.md` 退役说明 2 处（预期保留），其余 6 文件 0 处。
6. 上述复跑均不写文件（`git status` 复核：`docs/知识书/` 仍为新增未跟踪目录，无额外修改）。外部链接未由本维度重新抓取（链接字段规范与抽样复现属 engineering 维度）。

## 7. 输入漂移与复用

- 本轮=round0 首次验收，无旧证据复用。
- 测试期间未发现输入漂移：除 R1 语义的 `main-log.md` 滚动增长（清单已声明）外，全部登记输入/输出哈希与清单一致。
- 其他维度影响：D1 修复将只改 ch02 文本→产生新 manifest；functional 复测 D1/D2 定点 + 本报告 §3 中与修改行无交集的通过项可按清单申请复用；engineering 需重绑 ch02 哈希/编码；system 的 README/导航核对预期不受直接影响（链接与状态行不变）。

## 8. 未测与边界

- 不含任何硬件/构建/时序动作（不适用；无位流身份、观察者、时间可记）；G2–G5 不适用理由见 §1。
- 外部资源未重新抓取；B 站降级按允许规则处置（§3 #25）。
- 未修改任何生产文件；本报告为唯一写入。

## 9. 下一动作

- 原 KB1 开发修复 D1（必须；同轮建议 D2/O1/O2），更新章节"版本记录"并重冻结 manifest → round1 由原 functional 测试者对 D1/D2 定点复测 + 影响面复测；engineering/system 按其各自报告的判定与影响清单独立判断复测/复用。
