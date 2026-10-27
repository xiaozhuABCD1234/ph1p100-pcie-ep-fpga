# 决策矩阵 — 20261026-2138_fpga-integrated-delivery（收尾冻结 2026-10-27 06:50）

## 0. 结论

- 本轮唯一主目标（**同一候选集成交付**）**未达成**。4 个正式包中 INT.P1/P2/P3 PASS（各有既有限定），**INT.P4 记为 ⚠ 未通过**（不写 PASS）。
- **未产出** route / bitgen / CWC / 下载 / Flash；**整机未交付**，P4 不是整机、不是上板、不是真实 PCIe 传输。
- **不得**把 r2 的功能证据与 r3 的时序数字拼成 PASS（不同输入；报告合同禁止拼接）。
- 板级后续：**选择 (a) 在 ⚠ 下继续开板级集成新 run**（见 §5 D4）。理由是用户明确"以推进度为先"、期限 2026-10-27，且板级顶层本来必须用自己的真实时钟/IO 重新签核；P4 的 G2 失败不会被新顶层继承为通过，也不会因等待而消失。**新 run 需用户显式调用**（不自动继承本 run 的授权、预算、TD/板卡计数）。

## 1. 任务/包判定矩阵

| 任务 | 主要产物 | 首轮 | 实际修复 | 最终判定 | 判定范围与限定 | 证据 |
|---|---|---|---|---|---|---|
| INT.P1 | RAW10 打包修正、好帧发布/取消、三算法与选路、独立像素参考 | r0 FAIL | 1（r1） | **PASS** | 仿真功能/工程通过；system not_run（G3/G4 awaiting_hardware）；G5 partial；G2 为隔离综合 | `test-reports/INT.P1-r0-integrated.md`、`INT.P1-r1-integrated.md`、`INT.P1-r1-manifest.json`（`D6C524F6…`） |
| INT.P2 | A+ 输出槽→PCIe 发送后端：描述符/长度/尾拍/完成/释放；A1U1 vs R10F；RAW 入口保留 | r0 PASS | 0 | **PASS** | functional/engineering/system pass；board G3/G4 not_run；G5 partial；**RK 真实 PCIe 传输待联调**（接口仿真不等于真实传输） | `INT.P2-r0-integrated.md`、`INT.P2-r0-manifest.json`（`B5073D55…`） |
| INT.P3 | 双路 A/B 采集、身份、必要调度、防串帧/混路/覆盖 | r0 FAIL | 1（r1） | **PASS** | functional pass（D1 关闭）；engineering partial（G2 由 P4 承接）；system not_run（G3/G4）；**A 路真实 b20 结果 pending、仍门控** | `INT.P3-r0-integrated.md`、`INT.P3-r1-integrated.md`、`INT.P3-r1-manifest.json`（`9D0DEA08…`） |
| INT.P4 | 同候选集成交付：P1+P2+P3+A+核同 manifest、回归、隔离综合、交付包 | r0 FAIL | 3（r1/r2/r3 用尽） | **⚠ 未通过** | functional/engineering/system 在 r0–r3 间互有摆动，**无同一候选三项同时通过**；route/bit/CWC/下载/Flash=0 | `test-reports/INT.P4-r0..r3-integrated.md`、`INT.P4-r3-manifest.json`（`43EBFF3D…`） |

统计：正式包 4；综合测试轮次 9（2+1+2+4）；实际修复 5（1+0+1+3）；PASS 3、⚠ 1。P4 修复额度 3/3 已用尽，本 run 不再派第 4 轮。

## 2. INT.P4 候选矩阵（同任务不同分支，互不可拼）

| 候选 | manifest SHA256 | functional | engineering（G2） | system（G5） | 用途 |
|---|---|---|---|---|---|
| r0 | `31A3BBF2…C3F983` | fail（S5 反压 beat760/768 死锁 >200k 拍，仍提交 raw_len=3840/stream_len=3927 损坏帧，自第 55 字节起 3305 B 不符） | fail（TD MapIO IO=2813 > 286；无 WNS/TNS/资源） | fail（5 项文档未绑哈希等） | 仅历史 |
| r1 | `CFFCF54D…AE15E0` | pass（T1–T6 65/65、S1–S5、oracle+负对照、样例同哈希） | fail（330 违例端点 / WNS −1.549ns / TNS −271.427ns；harness DDR 未驱动；3 次综合超 2 次分配；TCL 端点数误计） | fail（D5a–D5e） | 仅历史 |
| r2 | `DFAB7F9D…B32E` | **pass**（dev TB MODE4/1 默认+EXTRA 65/0、S1–S5、三 seed 派生等价 PASS（HE 停顿敏感性记为既存差距）、A1U1 oracle+负对照、样例哈希 `79E35F28/1357408F/76D88910`） | fail（**112 端点/16770、WNS −0.637ns、TNS −69.776ns**；hold 0；IO 42/286；ERAM+CWC 39/300；reg 5832/slice 10761/DSP 14；STA 覆盖 95.76%；无 HDL-5314） | **pass**（G5 D5a–D5e 已修；E5a–E5c 卫生项遗留） | **功能基线**（板级集成起点） |
| r3 | `43EBFF3D…526F1` | **fail**（派生变体等价破坏：y8 383/317/3、gau 1368/1154/10、he 1116/980/44；always-ready 仍 13 处 gray/gau；bayer 单元 TB 769 vs 783；rowwin 45/45 err=3；控制 TB 证明不能归因固定延迟/既有 HE 敏感性） | pass（限定：**0 端点/17220、WNS +0.072ns、TNS 0、hold 0**；IO 42/286；ERAM+CWC 39/300；reg 6004/slice 10691/lut 12943/DSP 14；STA 95.63%） | fail（protocol r3 段"不丢不重"与证据矛盾；build-entry"候选 8"vs 实列 10；r2 残留 PASS 断言未标注） | **仅作"该网表在 187.5MHz 内部路径收敛"的时序参考；禁止作功能输入/板级功能基线** |

过程偏差：r3 的 `r3_run1` 综合在"同源集等价仿真先通过"前置未满足时执行（开发已如实记录，测试者已复核）。该次综合数字真实有效，但**不能**升级为交付时序通过；synth 终身计数 7/9（本 run 分配上限 9），剩余 2 次不转移、不继承。

## 3. G 层终态矩阵

| G 层 | 终态 | 依据/限定 |
|---|---|---|
| G0 接口/单位/时钟/复位 | **pass** | 单 `clk` 187.5MHz（5.333ns）、异步低有效 `rst_n`；无第二时钟/异步 FIFO；A1U1 vs R10F、RAW vs Y8 分离；派生变体端口集合与基础模块逐一相同（24/23/26/43 项） |
| G1 模型/仿真/回归 | **fail（因 r3）** | P1/P2/P3 回归、集成 TB、A1U1 oracle+负对照、样例哈希均过；但 r3 派生变体 token 等价不成立，且失败面超出"固定延迟/既有 HE 敏感性" |
| G2 综合/STA/资源 | **pass（仅 r3 限定）/ fail（r2）** | r3：0 违例、WNS +0.072、TNS 0、hold 0、IO 42/286、ERAM+CWC 39/300、资源在器件内、无未驱动 DUT 输入、单时钟、无 false_path/multicycle、route=not_run（harness 42 IO 无引脚约束）。r2：112 端点、WNS −0.637。**两者不可互换** |
| G3 上板功能 | **not_run + awaiting_hardware** | 无集成 bit、无板窗；未伪造 |
| G4 长稳/性能/恢复 | **not_run（后置）** | 仅记差距（用户明确本轮后置） |
| G5 集成/发布一致性 | **fail（r3）** | r2 时通过；r3 文档与自有证据矛盾（协议"不丢不重"、候选计数 8 vs 10、r2 残留断言） |

## 4. 已接通 / 已验证 / 未验证 / 阻塞

- **已接通（同一候选内，仿真）**：RAW10 打包→好帧发布/取消→三算法与选路（RAW 旁路保留）→A+ 压缩（b20 r0 只读核）→A+ 槽存储→PCIe 发送后端描述符面→A/B 身份与调度；集成顶层单 `clk` 无 CDC。
- **已验证（只证明仿真）**：P1/P2/P3 既有 TB 与 Python 工具；集成 TB MODE4/1 默认与 EXTRA；A1U1 真实样例解码 + 独立 oracle + 坏 header/坏 payload 负对照；样例哈希与冻结值逐字节一致；64×48 缩尺帧。
- **未验证**：1920×1080 全尺寸与真实帧率；真实相机/ADC；真实 DDR 器件时序；真实 PCIe 链路与 RK 传输（待联调）；A 路真实 b20 板级有效结果；HE 停顿敏感性（既存差距）；板级 IO 约束下的时序。
- **阻塞/未做**：G3/G4、route/bit/CWC/下载/Flash；无整机 bit；P4 无同一候选三项同过。

## 5. 决策记录

| ID | 决策 | 依据 |
|---|---|---|
| D1 | INT.P4 记 **⚠ 未通过**，任何文档不得写 PASS | r0–r3 无同一候选三项同过；§3.8(1) |
| D2 | **不合并** r2 功能证据与 r3 时序数字 | 不同输入；relay/report 合同；r3 functional fail |
| D3 | 本 run **不再派第 4 轮修复**、不复测、不扩 synth；TD synth 终身停在 7/9 | 三轮实际修复用尽；dispatch stop_conditions |
| D4 | 板级线**在 ⚠ 下继续**，作为**新 run**（选 a） | 用户"推进度为先"+期限 2026-10-27；板级顶层必须自有真实时钟/IO STA；§3.8(3) 诚实标注条件 |
| D5 | 新 run 的**功能基线 = r2 候选**（`DFAB7F9D…`），时序在**板级顶层**解决 | r2 是唯一 functional+system 同过候选；r3 语义已坏 |
| D6 | **禁止**以 r3 派生变体（`algo_rowwin3_p4`、`gray8_gaussian3x3_stream_p4`）作功能输入或板级基线；r3 仅可作时序参考 | r3 G1 失败（gray/gau 逐像素差、停顿多发 token） |
| D7 | 新 run **不自动继承**本 run 的"5 倍额度"与 TD/板卡/下载计数 | 用户原话限定"这次任务"（`request.md` 机械登记）；新 run 需用户重新授权 |
| D8 | 新 run 的 TD/板卡窗口独立冻结；b18/b19/b20 只读、计数不动 | §3.8(3e)、AGENTS 与 dev-plan §6/§7 |
| D9 | 本 run **不** commit/push/fork 到权威两仓，不写 `D:/fpga/repos/**` | AGENTS 2026-10-27；本 run 授权只到工作区 |
| D10 | 保留 b18 回退件与全部历史候选/manifest；不批量删除 | 项目删除禁令；b18 是 B 路功能回退 |

## 6. 证据索引（收尾引用）

- 计划/边界：`request.md`、`dev-plan.md`（§3 INT.P4、§3.6–§3.8、§5–§9）、`fpga-design-guide.md`、`input-index.md`
- 候选/manifest：`INT.P1-r1-manifest.json`、`INT.P2-r0-manifest.json`、`INT.P3-r1-manifest.json`、`INT.P4-r0..r3-manifest.json`
- 综合验收：`test-reports/INT.P{1,2,3}-r*-integrated.md`、`test-reports/INT.P4-r0..r3-integrated.md`
- 开发结果/教训：`INT.P4/result-r0..r3.md`、`INT.P4-lessons.md`、`INT.P{1,2,3}-lessons.md`
- TD：`INT.P4/td/**`（r2 权威 `syn_r2_run2/`、r3 权威 `r3_run1/`；`run.log` 为 r1 旧日志已加注）
- 交付包：`INT.P4-protocol.md`、`INT.P4-build-entry.md`、`INT.P4-shortest-steps.md`、`tools/integrated_delivery/{a1u1_decode.py,evidence/**}`
- 板级承接：`handoff.md`、`follow-on-run-request.md`、`user-question.md`、`user-summary.md`
