# 最终汇总 — 20261026-2138_fpga-integrated-delivery（收尾 2026-10-27 06:55）

> 唯一判定口径：本 run 的包 PASS 只代表"该包冻结候选在该包门槛下通过"，**不**代表整机、bit、上板或真实 PCIe 传输通过。

## 1. 目标与总体结论

- 用户目标：2026-10-27 前交付**同一套可构建、可验证的 FPGA 集成候选**（采集→DDR→三算法→A+压缩/RAW回退→PCIe 发送后端），B 路优先、A 路在 b20 有效结果后接入，不得把不同分支局部 PASS 拼成整机完成。
- 拆分：1 个主要可验收目标、4 个正式包（INT.P1–P4）、两级、每包 ≤5 项语义步骤、BATCH_SIZE=1。
- **总体结论：主目标未达成。** P1/P2/P3 各自的冻结候选 PASS；**INT.P4（同候选集成交付）记为 ⚠ 未通过**。无 route/bit/CWC/下载/Flash，无整机交付，无真实 PCIe 传输，无 A 路上板结果。

## 2. 逐包统计（首轮/修复轮）

| 包 | 首轮 | 修复轮 | 最终 | 关键限定 |
|---|---|---|---|---|
| INT.P1 真实输入与处理 | r0 **FAIL** | r1 **PASS**（1 轮） | **PASS** | 仿真 64×48；system not_run（G3/G4）；G5 partial |
| INT.P2 压缩到 PCIe | r0 **PASS** | —（0 轮） | **PASS** | 后端接口/描述符/释放通过；**RK 真实传输待联调**；board not_run |
| INT.P3 双路接入 | r0 **FAIL** | r1 **PASS**（1 轮） | **PASS** | functional pass；G2 由 P4 承接；A 路真实 b20 结果 pending、仍门控 |
| INT.P4 同候选集成交付 | r0 **FAIL** | r1/r2/r3 全 **FAIL**（3 轮用尽） | **⚠ 未通过** | 无同一候选三项同过；route/bit/CWC/下载/Flash=0 |

合计：综合测试 9 轮（2+1+2+4）；实际修复 5 轮（1+0+1+3）；PASS 3 包、⚠ 1 包。P4 修复额度 3/3 已耗尽（本 run 不派第 4 轮）。

## 3. INT.P4 四轮轨迹（真实数字）

| 轮 | functional | engineering（G2） | system（G5） |
|---|---|---|---|
| r0 | fail（反压死锁 + 损坏帧） | fail（MapIO IO=2813>286） | fail |
| r1 | pass | fail：**330 端点 / WNS −1.549ns / TNS −271.427ns** | fail（D5a–D5e） |
| r2 | pass | fail：**112 端点 / WNS −0.637ns / TNS −69.776ns** | **pass** |
| r3 | **fail**（派生变体等价破坏） | **pass（限定）：0 端点 / WNS +0.072ns / TNS 0 / hold 0** | fail（文档与证据矛盾） |

- r2 最差路径：`u_obuf_gau/count_reg[0] → pipe_en → evt_en → ra0 → 320 深 LUT RAM 读 mux → u_gau/u_row/rb0_reg[0].d`（5.906ns；`u_front` 有同构副本）。
- r3 的核心修复（`algo_rowwin3_p4` 读地址/使能寄存器化 + 固定延迟对齐）把时序压到 0 端点，但**破坏了 gray/高斯逐像素等价**：y8 383/317/3、gau 1368/1154/10、he 1116/980/44（SEEDMODE 0/1/2）；always-ready 仍 13 处 gray/gau；bayer 单元 TB `+STALL` 769 vs 783（多发 14 token）。测试者控制 TB（同 RTL 仅 ready 相位 +1 拍）证明 gray/gau 差异**不能**归因固定延迟或既有 HE 敏感性。
- 结论：**r2 = 功能正确 / 时序不收敛**；**r3 = 网表在该 RTL 上收敛 / 语义不成立**。两者不可拼接，INT.P4 不能 PASS。

## 4. 候选与交付物（唯一引用）

| 项 | 路径 | 状态/用法 |
|---|---|---|
| 功能基线候选 | `INT.P4-r2-manifest.json`（SHA256 `DFAB7F9D7FF7B7F8FB1D9B4401844F3D76102064C99FC4338192FB8A0C59B32E`） | **板级集成起点**；G2 已知违例 112 端点 / −0.637ns |
| 时序参考候选 | `INT.P4-r3-manifest.json`（SHA256 `43EBFF3D110234A225DD2A449804BC863F47EC5D7FAE89966C970B5EA9526F1`） | 仅"该网表在 187.5MHz 内部路径收敛"的证据；**禁止作功能输入** |
| P1/P2/P3 冻结 | `INT.P1-r1-manifest.json`（`D6C524F6…`）、`INT.P2-r0-manifest.json`（`B5073D55…`）、`INT.P3-r1-manifest.json`（`9D0DEA08…`） | P4 已逐项复核绑定；板级线只读复用 |
| 协议/构建/步骤 | `INT.P4-protocol.md`、`INT.P4-build-entry.md`、`INT.P4-shortest-steps.md` | **注意**：r2 段"CHECK_REF_NEW PASS/不丢不重"等断言在 r3 已不成立，只读接收方须以本汇总与 r3 报告为准 |
| 解码工具/样例 | `tools/integrated_delivery/a1u1_decode.py`、`tools/integrated_delivery/evidence/{integrated_sample.a1u1,integrated_sample.raw,integrated_sample.json}` | 样例哈希 `79e35f28…/1357408f…/76d88910…`（A1U1 4009B / RAW 3840B / JSON 825B），独立 oracle 与负对照均过 |
| 综合证据 | `INT.P4/td/r3_run1/**`（r3 权威）、`INT.P4/td/syn_r2_run2/**`（r2 权威） | 端点数取自 `flow.status`，非打印条数 |
| bit | — | **not_run**；b20 `a1_board.bit` 是独立历史候选，**不是**本集成交付 bit |

## 5. 已接通 / 已验证 / 阻塞 / 下一最短动作

**已接通（同一候选、仿真）**：RAW10 打包 → 好帧发布/取消（晚 CRC/FE 裁决、abort/重 SOF 同拍 commit）→ 三算法（Bayer→Y8 / 高斯 / 前帧 HE）与选路（RAW 旁路保留）→ A+ 压缩核（b20 r0 只读）→ A+ 槽存储 → PCIe 发送后端描述符面（有效长度/尾拍/完成/释放）→ A/B 身份与调度（B 优先、轮转、A disabled 不阻塞 B）。

**已验证（只证明仿真）**：P1/P2/P3 既有 TB 与 Python 工具；集成 TB MODE=4/1 默认与 `+EXTRA`（T1–T6，65/0）；测试者 S1–S5（反压无死锁、身份、释放）；A1U1 真实样例解码 + 独立 oracle + 坏 header/坏 payload 负对照；样例哈希逐字节一致。全部为 64×48 缩尺帧。

**阻塞/未验证**：
1. 功能基线的 187.5MHz setup 未收敛（r2：112 端点、WNS −0.637ns、TNS −69.776ns）。
2. G3/G4 not_run：无整机 bit、无板窗、无长稳/吞吐；1080p30 未实测（计算预算 155.52MB/s 双路 / 77.76MB/s 单路，非实测）。
3. 真实 PCIe/RK 传输待联调（文件回放/接口仿真不等于真实传输）。
4. A 路真实相机与 b20 板级有效结果 pending（b20 已 routed 0 违例、SWNS +0.012ns 薄裕量、bit+CWC 存在、board=blocked；其目录与计数只读）。
5. 综合 harness 无引脚/IO 约束（42 IO 未约束），不是板级顶层。
6. HE 停顿敏感性（既存差距，98/99/48）未修。
7. r3 派生变体不可用于功能；rowwin 帧起始/停顿对齐修复需新任务。

**下一最短动作（本 run 边界内已无）**：启动板级集成新 run，以 r2 为功能基线、B 路优先，先做板级顶层 + 真实时钟/IO 约束下的 STA，再下载取 B 路真实单帧压缩帧 PCIe 导出。启动文本见 `user-question.md` / `follow-on-run-request.md`。

## 6. 资源与额度记账

- r3（限定通过）资源：IO 42/286；ERAM+CWC 39/300；reg 6004；slice 10691/71680；lut 12943；DSP 14；STA 覆盖 95.63%。
- TD 计数（INT.P4 终身）：synth **7/9**（r0/r1 3 + r2 3 + r3 1；r3 分配 3 只用 1）；route 0/1；bitgen 0；CWC 0；下载 0；Flash 0。**剩余不转移、不继承**。
- 全局未用额度（route≤2、bitgen≤1、CWC≤1、download≤1）不在新 run 自动生效。
- 过程偏差：r3 综合在"同源集等价先通过"前置未满足时执行（已如实记录，数字有效但效力受限）。

## 7. 板级后续决策（选 a：⚠ 下继续，新 run）

- 决策与理由见 `decision-matrix.md` §5 D4；完整请求、范围、门槛、预算与启动条件见 `follow-on-run-request.md`。
- 技术起点：**功能基线 r2**（`DFAB7F9D…`）→ 板级顶层（真实相机 B、DDR、P4 核、PCIe EP、时钟复位/CDC、引脚约束、构建入口）→ 整机 bit → **先 B 后 A** 的真实单路压缩帧 PCIe 完整导出；长稳与非阻塞优化后置。
- 明令禁止：用 r3 派生变体作功能基线；用 r3 的 G2 数字配 r2 的功能证据；用 P4 综合数字代表板级时序；把 b20 bit 当本交付 bit；用文件回放/仿真冒充真实 PCIe 传输。
- 新 run **不继承**本 run 的"5 倍额度"（用户原话限定"这次任务"）。若用户不再授权，按默认有界预算执行；缺板窗/主机端即 blocked/awaiting_hardware，不空转。

## 8. 剩余主题（3 条，保留原需求路径 `request.md`）

1. **板级整机与 B→A 单路压缩帧 PCIe 导出**（本收尾已备 `follow-on-run-request.md`；本轮不派发）。
2. **RK/真实 PCIe 联调**（RK 在队友处；需真实驱动与主机端，禁止文件回放冒充）。
3. **长稳/吞吐优化/非阻塞告警整理 + rowwin 帧起始与停顿对齐的离线修复**（用户已明确后置）。

## 9. 诚实声明

- INT.P4 是 **⚠**，不是 PASS；本 run 没有整机 bit、没有上板、没有真实 PCIe 传输、没有 A 路板级通过、没有长稳/性能达标。
- r2 与 r3 是两个不同输入的不同结论，**不合并**；任何"时序已收敛所以整机可用"或"功能已过所以可以出 bit"的读法都不成立。
- 所有数字来自测试者独立复核的冻结证据；证据路径见 `decision-matrix.md` §6。P4 文档中的 r2 残留断言以 r3 报告与本源汇总为准。
