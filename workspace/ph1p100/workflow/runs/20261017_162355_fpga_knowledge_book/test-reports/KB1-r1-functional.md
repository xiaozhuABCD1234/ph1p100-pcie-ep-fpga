### 判定：PASS

## 基本信息

| 项 | 值 |
|---|---|
| task_id / dimension / round | KB1 / functional / 1（复测轮） |
| 测试日期 | 2026-10-17 |
| 测试者 | fpga-tester-functional（原 r0 测试者会话续接；只读核验，未修改任何输入/既有文件；本报告为唯一写入） |
| 项目根（工作树） | `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道` |
| 冻结清单（唯一依据） | `workflow/runs/20261017_162355_fpga_knowledge_book/manifests/KB1-manifest-r1.json`；测试者现场复算 SHA256=`21759d7056119faeee5e1b8ee2fc46b3ba621cc60b3ebdf696950bee15190e5e`（与声明一致）；r0 清单保留未改写（复算 SHA256 不变） |
| 工具版本 | PowerShell 5.1 `Get-FileHash`（SHA256）；会话联网工具（1 次 Wikipedia 实抓抽样）；文本读取/检索。Python 复跑未重执行（`parallel/frame/frame_contract.py` 哈希与 r0 相同，按复用处置）。未使用 TD/构建/下载/上板工具（不适用） |

## 1. 复测范围（按 r0 报告 §7 裁定）

- 必测：functional r0 **D1**（ch02 guard/nominal 计数表述）与 **D2**（ch03 drop_count 枚举）定点复测；受影响再验项全部重验。
- 复用：未变文件与未触及行按 r0 §3 通过与复用规则重核读数并**绑定 r1 清单**（见 §6）；无旧维度证据跨输入拼接。
- 阈值：G0+G1 适用、G2–G5 不适用（纯文档，规划理由同 r0）；D1/D2 修正与证据一致、无新增事实性错误 → 本维度门槛满足。

## 2. 清单核验（G0）

- r1 清单自哈希复算一致；**45 组登记条目逐项复算**：44 组与磁盘一致（含 3 章修订后哈希/字节、link-check/dev-notes 修订后哈希/字节、新增登记 `docs/evidence/camera_rgb565_timing_20261015_114913.json` 与三份 r0 报告、三处中央文件 after 值与 r0 相同）；`main-log.md` 磁盘 9286B ≠ 清单时点快照 8536B，首行未变、含 KB1/r1 追加内容，按 R1 滚动语义处置，**不判 FAIL**。
- 变更面与 dispatch 转述一致：`02/03/04 三章 + link-check-KB1.json + dev-notes-KB1.md`（相对 r0）；`README/_写作规范/_全书大纲/01 章` 未变（哈希= r0）；另含并行线漂移登记（decision-register=rev2 快照、T01 dev-plan、tasks.json——清单已注明"观测漂移"）与 r1 新增读入（114913 证据 JSON、r0 三报告），均如实登记。
- 本包产出未见清单外未声明变更（`docs/知识书/` 与 run 目录为未跟踪新增，与写范围一致）。
- G0 结论：**pass**。

## 3. D1 定点复测（r0 失败项 1）——**PASS**

- 复测对象：`docs/知识书/02_时钟复位与余量.md` "为什么'零违例'只是起点"节（r1=L115-122）。
- 期望（冻结来源）：guard 与 nominal 的违例端点计数应为 guard=116、nominal=13，**均非零**，且注明为报告条目数。
- 实际（r1 文本，L120）：
  > "114913 的 guard 与 nominal 两份报告对同一物理实现给出不同的违例计数——guard（实现期预留 0.300ns）为 116 个违例端点计数、nominal（恢复名义口径）为 13 个（`docs/evidence/camera_rgb565_timing_20261015_114913.json`）；两者都不是"零违例"。**这些计数是报告条目数**（同一物理端点可能出现在多个报告组）……"
- 逐项核对：
  1. guard=116、nominal=13 与证据 JSON 一致（`implementation_guard.guard.violating_endpoints=116`、`…nominal.violating_endpoints=13`、`objective.accepted=false`）；与 `docs/RGB565时序裕量优化_2026-10-15.md` L52（"nominal …13 个报告违例端点计数"、guard=−0.477）一致。
  2. "报告条目数≠唯一物理端点"与来源 L52 括注（"不同报告组可能重叠，不能称 13 个唯一物理端点"）一致。
  3. 无自相矛盾：与本章 L88 表格（114913 nominal −0.177）、L93（"nominal 是负的…没有通过"）不再冲突；两报告均为负 → "都不是零违例"成立。
  4. 新增 002820 正例（L119）："66 组统计的违例端点均为 0（'零违例'成立），但 setup 只有 0.000ns（'薄'）且未达到 0.300ns 的优化目标"——与 RGB565 文档 L31/L60 一致（原 r0 报告建议的替换正例已采纳）。
  5. 引用的证据文件路径已登记进 r1 清单且磁盘哈希一致（`e34e5b67…`，61800B）；根相对写法属 F3/R5 允许的"来源署名/定位说明"。
- 结论：D1 **已正确修复**；r0 的 FAIL 依据消除。

## 4. D2 定点复测（r0 失败项 2）——**PASS**

- 复测对象：`docs/知识书/03_流水线与交接.md` L117"丢帧账"。
- 实际（r1）："`drop_count` 只在"ready 丢失且确有活动写入"、"围栏校验失败（坏帧）"或"主动 abort/写长度不符"时 +1"——排他枚举已补第三类。
- 与 RTL `fpga/csi2/src/mem/ddr_frame_store.v`（哈希未变）逐处对照：L66-70（ready 丢失 + 有活动写入）、L81-84（主动 abort）、L87-89（写长度不符）、L105-110（围栏校验失败同时计 `error_count/drop_count`）——三类枚举覆盖全部 +1 路径，无遗漏、无多余。
- 结论：D2 **已正确修复**。

## 5. 其余修复面与受影响项重验（全部通过）

| # | 项 | 复验结果 |
|---|---|---|
| 1 | ch02 指针"延伸资源第 5 条"（L28） | 第 5 条=Synchronous circuit，与"异步电路（少用）"对照语义相符；link-check e5 note 已同步说明 |
| 2 | ch02 `ph1p_ddrphy_dram_init.v:232` 全路径（L126） | 路径解析成立（`fpga/csi2/prj/ddr_frame_probe/vendor/ip/ddrmc_x32/src/rtl/init/ph1p_ddrphy_dram_init.v`，9204B、236 行）；L232=`assign done = (state_cnt[3:0] == S_DONE);` 为组合译码，与"init 状态译码是一个组合信号"相符；仓库内三份副本：PCIe 侧两份同哈希 `8e737b35…`、本副本 `97c98e01…` 独立不混用（"002820 同源"为开发侧定位声明，仓库内不可再证，边界已注明） |
| 3 | ch03 正文"两组同步器各打两级"（L85） | 残字已修；`rafter` 仅存于版本记录对旧笔误的引述（L242），属合法留痕 |
| 4 | ch03/ch04 资源表 URL `…/wiki/先进先出算法`（ch03 L211 / ch04 L240） | 两章已同步更新；旧 URL `…/wiki/先进先出)` 全书 0 残留；**本维度独立实抓**：新 URL 实抓成功，最终条目为计算机排程算法条目（页内注明"关于财务术语，请见先进先出会计法"），不再落到会计条目——engineering r0 D1 的阻断问题确认消除 |
| 5 | ch03/ch04 章末脚注"知乎专栏"（L218/L243） | 与 link-check e17/e23（知乎两条超时）一致 |
| 6 | 三章"版本记录"r1 行（ch02 L238、ch03 L242、ch04 L268） | 均按 `_写作规范.md` §6 留痕，描述与实改一致 |
| 7 | `link-check-KB1.json`（r1，12030B） | JSON 可解析、23 条目；`distinct_urls_used_in_tables=18`、`table_rows=21`、`shared_rows_note`（3 条共享重复计入）正确；`proposed_states_used`=16+2+1+4=23 正确；e11/e14/e17/e23 均按修复项更新；B 站两行仍为"无法在线核验（原因）+精确检索词"，无虚构、无状态字段缺失（按 environment_note 不判 FAIL） |
| 8 | 被引外部来源新快照（decision-register=rev2、T01 dev-plan） | 章节引用的 M1/M2c/M3/M5.5 与 §1.4/§1.7/§1.8/§1.11 内容仍在且核心数字未变（96.40%、2,592,768、666.67MHz、0.300 口径、显式组数）；三章未写 E2 结果结论，rev2（M1a 维持 1333、TMST-7700 未决）与章节表述**无冲突**；如后续需按 E2 结果更新书籍，属下一修订轮范围，不在 r1 验收面 |
| 9 | 三章 LF/行数/字节 | 02=238 行/29228B、03=242 行/25709B、04=268 行/23636B，与清单一致；未发现"（待写）"复现或禁止写法新增 |

## 6. 复用裁定（全部绑定 `KB1-manifest-r1.json`）

- **未变文件复用**：`README.md`、`_写作规范.md`、`_全书大纲.md`、`01_从代码到电路.md` 哈希与 r0 一致 → r0 对 F1–F4 与第 01 章的核验结论**复用**（r1 未再触碰）。
- **未变来源/材料/技能锚复用**：RGB565 文档、帧合同与 `frame_contract.py`、策略文档、手册、两份 RTL、T02 task、`check_timing_margin.py`、workflow/README、任务板等哈希与 r0 一致 → r0 §3 对应核验结论（含 `frame_contract --selftest`/8×4 向量复跑记录）**复用**，不重新执行。
- **变更章未触及内容**：02/03/04 的修订仅限 §3–§5 所列行/节（g01 L28/L115-122/L126/L238；g02 L85/L117/L211/L218/L242；g03 L240/L243/L268），其余全文重读未见改动；r0 §3 中与修订行无交集的条目（含 #25 B 站降级处置）继续有效并绑定 r1 清单。
- **受影响条目**：全部按 §3–§5 重验通过，未发现因修复引入的新事实性错误或新的内部矛盾。

## 7. 残留观察（非阻塞；不构成本维度 FAIL 依据）

- **O-r1-1（记录级组成句，建议最小修复）**：`link-check-KB1.json` `summary.entries_note` 文本与逐条实际组成不符——"18 条已入章节资源表（17 条在线核验通过 + 1 条 B 站降级）…+ 3 条未采用（…知乎超时）+ 1 条 B 站降级复测（BV12y4y1v7V3）"。正确组成：**已入表 18 条=16 条在线核验通过+2 条 B 站降级；未入表 1 条（Asynchronous circuit）；未采用 4 条（cnblogs 404、B站 BV1yf4y1R7gH、知乎 p/95670435、知乎 p/21191014）**。同源表述见 `dev-notes-KB1.md` §8.5 与 §8 自检第 6 条（"（17/2/1/3）"应为 proposed 口径 16/2/1/4）。注：同文件的机器字段（`proposed_states_used`、`distinct_urls_used_in_tables`、`shared_rows_note`）与 r1 清单 `link_check.notes` 均已正确；此残留属 r0 O3 的部分未清，引擎上不影响任何章节行/状态字段。交 engineering/规划裁定是否随下轮最小面修正。
- **O-r1-2（已裁定，接受）**：ch02"77%"口径保留（与来源 RGB565 文档 L9 一致；直算 76.00%）——dev-notes §8"不改项及理由"登记完备，与 r0 functional 处置一致。
- **O-r1-3（沿留 r0 O1/O2，供后续自然修订）**：ch03 L34"8×4…三层流水…14 拍"整段示例数字仍以【本项目事实】覆盖但无来源（r0 已提，非阻塞）；ch03 L156"（D）"指代仍歧义。r1 未在其修复清单内，属可延后项。
- **O-r1-4（交 engineering 口径）**：e11 `title_returned` 记「先进先出算法 - 维基百科…」，实抓最终条目 H1 为「先進先出演算法 - 维基百科…」（简繁/重定向差异，note 已注明 redirects to 先进先出演算法）；信息实质正确、无虚构，标题一致性口径由 engineering 维度裁定。

## 8. 未测与边界

- 不含任何硬件/构建/时序动作（G2–G5 不适用，理由同 r0）。
- 外部链接仅独立实抓 1 条（修正后的先进先出算法条目）；其余链接状态核验与抽样复现仍属 engineering 维度。
- Python 自检未重复执行（文件未变，按复用处置）；B 站环境限制按规则处置。

## 9. 实际执行的命令与证据（节选）

1. r1 清单自哈希 + 45 项逐项复算（PowerShell 只读）：自哈希 `21759d70…0e5e`；44 项 OK；`main-log.md` 按 R1 语义处置（9286B vs 快照 8536B，首行不变）。
2. 三章修订后全文重读并与 r0 文本逐区对照（本报告 §3–§5 所列差异，之外未见改动）。
3. 副本核验：`Get-ChildItem fpga -Recurse -Filter ph1p_ddrphy_dram_init.v` 三份哈希比对（见 §5 #2）。
4. `link-check-KB1.json` JSON 解析 + 逐条计数复算（23=17 ok+2 unverifiable+1 dead+1 mismatch+2 timeout；18=16+2 入表）。
5. 实抓 1 条：`https://zh.wikipedia.org/wiki/先进先出算法` → 「先進先出演算法…」计算机条目（见 §5 #4）。
6. 残留扫描：全书 `rafter`/旧 URL 仅存版本记录引述；`my r0 报告` SHA256=`ecfd48e4…` 与 r1 清单登记一致（r0 失败证据原样保留）。

## 10. 下一动作

- 本维度 **PASS**，绑定 `KB1-manifest-r1.json`；不要求本维度继续修复。
- 残留 O-r1-1 若被规划/engineering 判定需修，只涉及 `link-check-KB1.json` 与 `dev-notes-KB1.md` 的记录文本；本 PASS 的有效性在相关文件再次变化时，按变更面由原测试者定点复核（章节文件不变则章节结论不受影响）。
