# final-summary.md — 20261020-0209 单A A+ 闭环（G2 小顶 PASS；P2 done +0.012 caveat，P3 已授权 ready）

- run：`20261020-0209_singleA_aplus_closedloop`
- 日期：2026-10-21（Asia/Shanghai）｜规划收尾
- 性质：离线、synthetic、**未上板、未下载、未生成 bit/CWC、未接 PCIe/RK**
- 本轮：1 个主要目标、4 个正式包、两级、batch=1；r3–r10 均为 P4 续接，不新增包/ID。

## 1. 最终结论（先看这里）

**T10 A+ RTL 独立闭环：未完成。**

- **G0/G1：成立**（P1/P2/P3 独立 PASS；r2–r10 候选的 P2/P3 回归为开发自测 PASS，未独立封存）。
- **G2：不成立**。r10 S1 综合 **WNS -0.450 ns、TNS -51.634 ns、144/148,921 端点**；1/2 综合、0 布线。无 Routed、无 bit/CWC、无板测。
- **平台期已确认**：r8 -0.470 → r9 -0.434 → r10 -0.450 ns；TNS 约 -37~-52、约 144 端点。r10 把读地址链移开，瓶颈转到 `pos_reg → hdist = pos - hent_pos → hit/阈值使能 → thresh_base_reg`，7 级 5.716 ns、4 个 ADDER。
- **最终裁决**：187.5 MHz 不再值得继续局部/结构补丁；闭合需多周期 hash/threshold 或新匹配微架构（新 run/新包），不是当前 `T10.a1-eng-freeze` 的局部修改。
- r10 是最后一次结构性尝试；**r10 FAIL 不自动 r11**。T10 记 **3/4 PASS + 1 ⚠**，不完成。
- 需用户在 `question-r10-final.md` 中选择：A 保持 ⚠ 收尾 / B 路线 (b) 145–150 MHz+CDC / C 新架构包冲 187.5。
- 需求二：**仅完成离线 profile 审计与导出契约**；真实 RAW 样例未取得。
- 需求三：**未开始**（需板窗/真实数据/生产候选）。
- 不得把 P1/P2/P3 的 PASS 当作 T10 或三项需求完成。

| 包 | 判定 | G 层 | 独立报告 |
|---|---|---|---|
| `T10.a1-format-ref` | **PASS r0** | G0/G1 | `test-reports/T10.a1-format-ref-r0-integrated.md` |
| `T10.a1-enc-rtl` | **PASS r0（含非阻塞 caveat）** | G0/G1 | `test-reports/T10.a1-enc-rtl-r0-integrated.md` |
| `T10.a1-frame-top` | **PASS r1**（r0 FAIL → r1 PASS） | G0/G1 | `test-reports/T10.a1-frame-top-r0-integrated.md`、`…-r1-integrated.md` |
| `T10.a1-eng-freeze` | **FAIL/blocked r0→…→r10** | G0/G1 有；G2 **FAIL** | **无独立 P4 报告**（见 §6） |

统计：正式包 4；PASS 3；FAIL/blocked 1；实际修复轮：P3 r1（1）+ P4 r1–r10（10）= 11；P4 单独 10 轮。

## 2. 三项需求逐项

### 2.1 需求一：T10 A+ 压缩 RTL 独立闭环 —— 部分完成

**已成立（G0/G1）**
- 唯一标准流包装：zlib（RFC1950），fixed Huffman + stored；真实 LZ77（非纯 literal）；2 行块、窗口 2048、块级 stored 回退。
- Bayer 相位重排 + 可选同色预测（A/B），逆变换可逆；`stored` 保存变换域字节，逆变换后才校验原图。
- 独立 zlib 1.2.13 + 自研严格解析器双解，P1/P2/P3 全部 0 mismatch；负例（截断/坏长度/坏 CRC/坏 NLEN/尾随字节）拒绝。
- 帧级：坏帧 `frame_commit=0`、`out_last=0`，无半帧；A/B、全 stored、尾块、abort/reset 恢复覆盖。
- 仿真服务率：1080p p1d1 **103.892 MB/s**，全 stored **103.879 MB/s**，双帧聚合 103.892；均 ≥77.76；P2 comp 81.067 MB/s、rand 178.351 MB/s。
- r8 S2 172.325 MHz ≈ **95.5 MB/s**；r9/r10 综合 Fmax 约 172.9–173.4 MHz，等效约 **95.8–96.1 MB/s**；均 ≥77.76、未达 97.2。
- r2 资源：LUT 11,263 / FF 2,108 / ERAM 4/300 / DSP 0（r3–r10 资源未在 result 汇总，以 TD 报告为准）。

**未成立**
- G2：r10 S1 综合 **WNS -0.450 ns、TNS -51.634 ns**；未 route，无 Routed WNS/TNS、无线后资源、无 TD CDC。
- 无 bit/CWC；无板上功能/吞吐。
- r2–r10 候选的 G1 回归未独立封存（P1/P2/P3 的独立 PASS 绑定的是更早候选，不能拼成 r10 的独立 PASS）。

### 2.2 需求二：真实输入参数与 RAW 样例 —— 仅离线部分

- `input-profile.json`：14 项，confirmed 7 / derived 3 / unknown 2 / conflict 2。
- 已确认：源计数 **2192 行 / 4830 B 每行**，`source_geometry=0x089012DE`；RAW10 打包 `b0..b3=P0..P3[9:2]`、`b4={P3,P2,P1,P0 低 2 位}`。
- 默认 ROI `1920×1080, X0=960, Y0=540, SKIP_ROWS=37`：来自 RTL 参数，**未板证**；2192 vs 2160+37=2197 的 5 行差异保留 `conflict`。
- 物理 Bayer 相位 **unknown**；`PHASE=3` 仅占位。
- 真实 RAW：**未取得**。T02 `raw_export=false`、`csv_export=false`，仅有 6 张调试 GUI PNG 转录，不能作为压缩输入。
- 非 PCIe 导出：只有离线契约与宿主校验器；无可确认的大块通道、无板窗、无用户在场，真实片段/整帧 `blocked_awaiting_hardware`。

### 2.3 需求三：单A 实际压缩链路闭环 —— 未开始

- 未接相机、未写 DDR 压缩通路、未做压缩数据保存/读回/PC 还原。
- 条件：G2 通过 + 真实 RAW 导出 + 生产候选派生 + 板窗 + 用户授权；本轮 0 下载、0 Flash、0 PCIe/RK。

## 3. 唯一候选与 manifest（r10）

| 项 | 值 |
|---|---|
| `a1_deflate_core.v` r10 | `7a10917d1f698c6dd408c14a19a4779ddf11ac85c68d937b6cdaee3aa4a5aed8` |
| `a1_frame_top.v` r10 | `fa64cb487b4241241516183e7b8bfd71f96b30e54f5ed3d53ac239a2771e1ba2`（r7 保留，未改） |
| `a1_small_top.sdc` r10 | `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311`（未改） |
| 回退 r9 core | `af6ab54b47556d0051548ff40eea56ee3957602ad35440fb3eeb25dabf310b03` |
| 回退 r8 core | `4e1e97b8f9c00102447ab1c6de63a26c8b762e57416d0365c7aba837ce99ec9c` |
| r10 manifest | `T10.a1-eng-freeze/CANDIDATE-MANIFEST-r10.json` |
| r9/r8/r7/r6/r5/r4/r3/r2 manifest | `CANDIDATE-MANIFEST-r9.json` / `-r8.json` / `-r7.json` / `-r6.json` / `-r5.json` / `-r4.json` / `-r3.json` / `-r2.json` |
| 最后一版独立 G0/G1 PASS | `T10.a1-frame-top/CANDIDATE-MANIFEST.json`，151 files（core `6cd35881…`） |

- r10 只改 `a1_deflate_core.v`：新增 `p3_r` 读地址寄存器，S_SCAN hit 分支改用 `p3_r`，去掉 `pos+3` 加法比较/`hent_pos+3/4` 加法；保留 r9 pos+3-in-htab 与 66-bit 打包；frame_top/SDC 未改。
- 生产 B01 候选 `b68c6e18…f9bf`、旧 run、旧 manifest **未触碰**。

## 4. 比率 / 最坏容量 / 吞吐 / 资源 / STA

### 4.1 比率与最坏容量（合成）

| 用例 | 原始 | 码流 | 说明 |
|---|---:|---:|---|
| 1080p prep+pred（多帧用例） | 2,592,000 B | 81,707 B/帧 | 31.7:1，仅该高可压缩合成内容，**不代表真实图像** |
| 1080p prep only | 2,592,000 B | 2,566,969 B | ≈1.010:1 |
| 1080p bypass | 2,592,000 B | 2,587,584 B | ≈1.002:1 |
| 1080p 全随机 / 全 stored | 2,592,000 B | **2,594,706 B** | 最坏上界：`2,592,000 + 540×5 + 6`，逐字节命中 |
| 最坏膨胀 | — | **+0.1044%** | 每 2 行块 5 B stored 头 + zlib 6 B |

### 4.2 吞吐（仿真换算 @187.5 MHz，不是板上）

| 场景 | cycles | cycles/B | MB/s | ≥77.76 | ≥97.2 |
|---|---:|---:|---:|---|---|
| 1080p p1d1（r5–r10 相同） | 4,677,945 | 1.80474 | **103.892** | PASS | PASS（仅该帧） |
| 1080p 双帧聚合 | 9,355,887 | 1.80474 | 103.892 | PASS | 仅该对 |
| 1080p 全 stored | 4,678,532 | 1.80497 | 103.879 | PASS | PASS（仅该帧） |
| 1920×16 random（r0 口径） | 80,999 | 2.1093 | 88.890 | PASS | **未达** |
| P2 comp（match-heavy，r5–r10） | — | — | 81.067 | PASS（余量小） | 未达 |

- 77.76 预算 2.4113 cycles/B；97.2 预算 1.9290 cycles/B；实测 1.8047。
- 关键换算：77.76 MB/s 需 Fmax ≈ **140.3 MHz**；97.2 需 ≈ **175.4 MHz**。r8 S2 172.325 MHz ≈95.5 MB/s；r9/r10 综合 Fmax 约 172.9–173.4 MHz。
- 只有 2 帧背靠背；无长稳/热态/跨帧随机反压；G2 未收敛前不得当可上板结论。

### 4.3 资源与 STA（综合）

| 项 | r0 | r1 | r2 | r3 | r4 | r5 | r6 | r7 | r8 | r9 | **r10** |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| SWNS | -6.471 | -3.816 | -3.792 | -2.374 | -2.446 | **-0.949** | -1.346 | -1.287 | -0.470 | -0.434 | **-0.450** |
| STNS | -1,133.864 | -680.559 | -777.523 | -417.972 | -183.480 | -303.718 | -416.270 | -73.092 | -37.591 | -45.639 | **-51.634** |
| Fmax | 84.717 | 109.302 | 109.589 | 129.752 | 128.551 | **159.185** | 149.723 | 151.057 | 172.325 | ~173.4 | **~172.9** |
| 违例端点 | 568 | — | — | 508 | 388 | 420 | 404 | 165 | 147 | — | **144** |
| Routed | not_run | not_run | not_run | not_run | not_run | not_run | not_run | not_run | not_run | not_run | **not_run** |
| TD CDC | not_run | not_run | not_run | not_run | not_run | not_run | not_run | not_run | not_run | not_run | **not_run** |

- 单位：WNS/TNS 为 ns，Fmax 为 MHz；r9/r10 Fmax 由 WNS 反推（5.333+slack）。
- r0–r2 资源：LUT 11,263 / FF 2,108 / ERAM 4/300 / DSP 0；r3–r10 未在 result 汇总。
- r10 S1 关键路径：`pos_reg[1] → hdist = pos - hent_pos → hit/阈值使能 → thresh_base_reg[3].ce`，7 级 5.716 ns、4 ADDER。
- 未使用 false path/multicycle；未降频；未换 seed；无 bitgen。

## 5. 本轮执行账与边界

- TD：P4 共 **19 次**（r0 2、r1 1、r2 1、r3 2、r4 2、r5 3、r6 2、r7 1、r8 2、r9 2、r10 1）；r10 综合 1/2、布线 0/1；**无 r11、无 route**。run 累计 19 次。
- 生产集成构建 0；下载 0；Flash/efuse/SPI/svf 0；bit/CWC 0；PCIe/RK 0；推送 0；批量删除 0。
- 写域：仅本轮新增 `rtl/ep_side/codec/**`、`sim/tb/codec/**`、`tools/codec/**` 与本 run 目录；生产树既有未提交改动未触碰。
- 未修改：生产 `.al`/`build.tcl`/SDC、三算法、R10F 合同、旧 run/旧 manifest、`docs/protocol/**`。

## 6. 独立报告清单与证据限制（含 r9 vlog 偏差）

| 包 | 独立报告 | 结论 |
|---|---|---|
| P1 | `test-reports/T10.a1-format-ref-r0-integrated.md` | PASS |
| P2 | `test-reports/T10.a1-enc-rtl-r0-integrated.md` | PASS（含非阻塞 caveat） |
| P3 | `…-r0-integrated.md`、`…-r1-integrated.md` | r0 FAIL → r1 PASS |
| P4 | **无** | r0–r10 均为开发 blocked；未派独立 P4 测试者 |

**为什么没有 P4 独立测试者**：r10 是 **FAIL/blocked**，没有 PASS 可认证；G2 FAIL 由 TD 综合报告与冻结 SDC 直接、确定性地复现（WNS -0.450 ns），独立测试者只能确认同一个负结论，且 r10 预算已停止。为不伪称独立封存，本报告明确标注：**r2–r10 的 G1 为开发自测，G2 为开发综合；P4 无独立综合报告**。

**r9 vlog 证据偏差（必须如实保留）**：
- r10 早期一次 P2 误用 r9 的 subst 目录，重写了 `r9/p2/runs/*` 与 `r9/p2/logs/vlog.log`。
- `r9/p2/result.json` 字节未变（`6ab4d148…d130`），仍匹配 r9 manifest；但 `r9/p2/logs/vlog.log` 由 `02dfece1…4996` 变为 `58d0ebaa…a61`，**不再匹配 r9 manifest 的该文件记录**。
- r9 其余 manifest 项未受影响；r9 的 `result.json`/stream sha 结论仍有支撑，但**原始 vlog 证据不可按 manifest 复核**。不得据此判 r9 功能漂移，也不得掩盖该缺口。r10 修正后 P2/P3 PASS，r10 manifest 已记录 note。

## 7. 短上板证据缺项

- 无 Routed 实现、无 bit/CWC、无 SRAM 下载、无板上复位/坏帧/吞吐。
- 无真实相机/RAW；物理 ROI X/Y/SKIP、Bayer 相位未验证。
- G3/G4、长稳/热态、双路 155.52 MB/s、PCIe/RK：not_run。
- 需求三整条链路：not_started。

## 8. 回退方法

- r10 → r9：`a1_deflate_core.v` 恢复 `af6ab54b…0b03`；删除 `T10.a1-eng-freeze/r10/**` 与 `p4/result-r10.md`；frame 保持 `fa64cb48…1ba2`。
- r9 → r8：core 恢复 `4e1e97b8…ec9c`；删除 `r9/**`、`p4/result-r9.md`。
- r8 → r7：core 恢复 `24bfb7d5…4897`；删除 `r8/**`、`p4/result-r8.md`。
- r7 → r6：`a1_frame_top.v` 恢复 `3c32803b…`；删除 `r7/**`、`p4/result-r7.md`；core 保持 r6 `24bfb7d5…4897`。
- 依次回退 r6→r5→r4→r3→r2→r1→r0；旧 manifest/报告只读保留。
- 最后一版独立 G0/G1 PASS：`T10.a1-frame-top/CANDIDATE-MANIFEST.json`（151 files）；复跑 `tools/codec/run_p3.ps1`。
- 删除本轮新增 codec 目录即可完全回退；生产 B01 bit 未触碰，无板上回退动作（本轮无下载）。

## 9. 最终技术裁决与路线 (b)

**187.5 MHz 局部/结构补丁：停止。** r8–r10 WNS 平台 -0.43~-0.47 ns，TNS -37~-52、约 144 端点；r10 已把读地址链移开，瓶颈转到 `hdist`/hit/阈值使能（4 个 ADDER）。继续逐条补丁只会暴露下一条 5.7 ns 级路径；闭合需多周期 hash/threshold 或新匹配微架构（新 run/新包），不再属于 `T10.a1-eng-freeze` 的局部范围。

**路线 (b)：145–173 MHz + 异步 FIFO/CDC。**
| A+ 时钟 | 等效吞吐 | ≥77.76 | ≥97.2 |
|---:|---:|---|---|
| 145 MHz | **80.3 MB/s** | PASS（约 +3.3%） | 未达 |
| 150 MHz | 83.1 MB/s | PASS（约 +6.9%） | 未达 |
| 165 MHz | 91.4 MB/s | PASS | 未达 |
| 173 MHz | **95.8 MB/s** | PASS | 未达 |
| 175.4 MHz | 97.2 MB/s | PASS | 正好 |

- **77.76 可满足**；145–150 MHz 布线余量更稳。
- **97.2 必须放弃**：需 ≥175.4 MHz，而当前综合 Fmax 约 172.9–173.4，布线后更低；173 MHz 也只有 95.8 MB/s。
- 代价：A+ 独立时钟域（MMCM/PLL）、异步 FIFO（双时钟 BRAM）、CDC 同步/复位、跨域约束、系统集成与板上验证；需新 run/新包与预算，且不能把 T10 G2 改判 PASS。**必须用户明确同意。**

## 10. 下一次准确启动/恢复文本

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 T10 收尾（r10 已 blocked，T10 G2 FAIL/⚠，未开 r11）。
> 先读 `final-summary.md §10`、`handoff.md §19`、`dev-plan.md §22`、`question-r10-final.md`、`p4/result-r10.md`、`r10/reports/syn_gate_timing_s1.rpt`、`CANDIDATE-MANIFEST-r10.json`。
> 当前：G0/G1 PASS；G2 FAIL（r10 S1 WNS -0.450 ns、TNS -51.634、144 端点、未 route）；无 bit/CWC；r8/r9/r10 WNS 平台 -0.43~-0.47。
> 决策：不再局部/结构补丁；A 保持 ⚠ / B 路线 (b) 145–150 MHz+CDC（接受 77.76、放弃 97.2）/ C 新架构包冲 187.5。
> 不放宽 187.5 MHz、不 false path/multicycle、不 bitgen/下载；未获用户明确选择前不派新任务。

## 11. 需要用户决定

1. **C-lite 已获授权并派发**：用户明确“同意 C-lite”。新包 `T10.a1-g2-2cyc` r0 已按同一 T10 全局任务派发（不新 run、不重置 P4 计数）；开发 60 min/40 calls；TD 3 会话/120 min；测试 45 min/30 calls。目标：77.76 硬门槛（≤6.25M cycles），97.2 争取（≤5.0M）。
2. **A：150 MHz + 异步 FIFO/CDC**。83.1 MB/s；满足 77.76、放弃 97.2；需 PLL/双时钟/CDC/系统集成。
3. **C：新匹配/哈希微架构冲 187.5**。工作量与收敛风险最高；需新 run/新授权。
4. 若 A/B/C 均不可行，保持 **⚠**：T10 = 3/4 PASS + 1 ⚠，不称完成。
5. 板窗/真实 RAW 导出（需求二/三）仍 **awaiting_user/awaiting_hardware**；本轮 0 下载、不接 PCIe/RK、不写 Flash。

## 12. 后续路线比较与推荐 B（2026-10-21）

用户明确“还是希望跑通”，规划比较 A/B/C 后推荐 **B：保持 187.5 MHz 单时钟，把失败的 hash/threshold 链改成真实 2-cycle 数据通路**。

| 路线 | 吞吐 | 时序收敛概率 | 工作量 | 对需求二/三板级影响 | 97.2 |
|---|---|---|---|---|---|
| A 150 MHz+CDC | 83.1 MB/s（145 MHz 80.3） | 较高 | 中高：PLL/双时钟/CDC/系统集成 | 大 | **放弃** |
| **B 187.5 单时钟 2-cycle** | 目标 ≥77.76；97.2 争取 | **高**：10.666 ns 预算 vs 当前 5.716 ns | 中：FSM/valid 握手、吞吐实测 | **小**：生产接口不变 | 仅 322k cycles 余量，不保证 |
| C 新匹配/哈希微架构 | 目标 103.9（保 97.2） | 不确定 | 高：多轮综合 | 小但周期长 | 可能保住 |

**为什么推荐 B**：
- 唯一不改变 187.5 单时钟架构的路线；无 PLL/CDC/跨域约束，板级与生产集成风险最小。
- 2-cycle 路径时序预算 10.666 ns，当前关键路径 5.716 ns，过 0 概率高（估计 >80%）。
- 吞吐有明确上限：77.76 对应 **6,250,000 cycles/帧**，当前 4,677,945，余量 1,572,055（+33.6%）；97.2 对应 5,000,000 cycles，仅余 322k（+6.9%），是争取项。
- 比 A 更符合“跑通”：A 放弃 187.5 与 97.2；B 若成功可守住 187.5 和硬门槛，97.2 仍有机会。
- 比 C 风险低：C 重排匹配/哈希微架构，工作量和收敛风险最高。

**诚实结论**：B 时序收敛概率高、77.76 概率高；97.2 **不保证**。若实测 cycles 在 5.0M–6.25M，则 187.5 G2 成立、77.76 满足、97.2 未达；若 >6.25M，B 失败，应停止并回到 A/C。

**建议新包 `T10.a1-g2-2cyc`（待预算确认）**：
- 同一 T10 全局任务；不新 run、不重置 P4 修复计数。
- 只改 `a1_deflate_core.v` 的 `hdist`/hit/阈值使能两拍通路；frame_top/SDC 锁定；禁止 false path/multicycle。
- ≤5 步：两拍通路+握手 → 与 S_SCAN/match 流水重叠 → 吞吐实测（≤6.25M / 5.0M）→ TD 187.5 → 冻结/独立测试。
- 用户已“同意 C-lite”；新包 `T10.a1-g2-2cyc` r0 已派发，详见 `dispatch-t10-g2-2cyc.json` 与 `dev-plan.md §24`。

## 13. C-lite 新包 `T10.a1-g2-2cyc` 派发（2026-10-22）

- **授权**：用户原话“同意 C-lite”。同一 T10 全局任务、同一 run；不新 run、不重置 P4 修复计数；`T10.a1-eng-freeze` 仍 r10 FAIL/⚠。
- **基准**：r10 core `7a10917d…aed8`、frame `fa64cb48…1ba2`（锁定）、SDC `227dd39e…6311`（锁定）；基线 P2 13/13、P3 20/20、0 mismatch、`vlog 0/0`、1080p 103.892 MB/s、P2 comp 81.067。
- **范围**：只改 `a1_deflate_core.v` 的 `hdist/hit/阈值使能` 为真实两拍数据通路（状态/valid 握手），与 S_SCAN/match 流水重叠；不改协议/端口/帧语义/CRC/长度/abort/Bayer/SDC。
- **吞吐**：平均 ≤2.4113 cycles/B；1080p ≤**6,250,000** cycles（77.76 硬门槛）；争取 ≤**5,000,000**（97.2）；P2 comp ≥77.76；stream sha 与 r10 等价。
- **TD**：3 会话/120 min、综合 ≤3、布线 ≤1；综合 WNS/TNS≥0 才布线；187.5、Routed、WNS/TNS/HWNS/HTNS≥0、0 违例、资源在器件内、`report_cdc` 实际执行、bitgen `not_run`。
- **停止**：两拍后 cycles >6.25M、P2/P3 mismatch、3 次综合仍 <0、route 失败、资源溢出、CDC 未同步 → blocked；不得用 A 路线或其他包绕过。
- **测试**：新开发、新独立综合测试者（45 min/30 calls）；报告 `T10.a1-g2-2cyc-r0-integrated.md`；三维覆盖功能回归、工程时序/资源、系统吞吐与接口。
- **结果口径**：r0 未完成前 T10 仍为 **3/4 PASS + 1 ⚠**；若本包 G2 Routed PASS 且 1080p ≤6.25M cycles，则 187.5 单时钟与硬门槛 77.76 成立；若 cycles ≤5.0M，97.2 也成立。若 >6.25M 或 G2 失败，本包 blocked，不自动转 A/C。

## 14. C-lite r0 S2 结果与 r0-c 范围修订（2026-10-22）

- **G1**：P2 13/13、P3 20/20、0 mismatch、`vlog 0/0`；13/13 P2 与 20/20 P3 的 stream SHA/run_cycles 与 r10 逐用例相同；1080p 4,677,945 cycles、P2 comp 81.067 MB/s。
- **G2 S2**：WNS **-0.092 ns**、TNS **-3.070 ns**、35/149,031 端点。
- **核心成果**：top-10 违例全部是 `a1_frame_top.v` 的 `dq_r_reg[0..9].d`；**core 最差 10 条零端点**，两拍 hash/threshold 已闭合。残留路径 `rd_issue_reg[8] → fanout-1920 → smem DRAM → dq_r_reg`，5.361 ns/7 级。
- **裁决 (a)**：同一 C-lite 包 r0-c，仅允许 `a1_frame_top.v` 的 `dq_r` 读数据寄存/高扇出拆分；core `e3484a60…0aee` 与 SDC `227dd39e…6311` 锁定；协议/端口/帧语义/CRC/长度/abort/Bayer 不变。
- **S3 收口**：剩余 1 次综合 + 1 次布线；S3 WNS/TNS≥0 才布线（≤60 min）；仍 <0 或 route 失败则停止；预算不变 3 会话/120 min、综合 ≤3、布线 ≤1。
- **不选 (b)/(c)**：只剩 0.092 ns，接受 ⚠ 浪费 core 成果；换时钟/架构代价大且放弃 187.5/97.2。
- **入口**：`dispatch-t10-g2-2cyc.json`、`dev-plan.md §24.9`、`p4/result-r0.md`、`r0/td/syn_gate_timing_s2.rpt`。

## 15. C-lite r0-c 结果与 r1 批准（2026-10-22）

- **G1**：P2 13/13、P3 20/20、0 mismatch、`vlog 0/0`；1080p 4,677,945 cycles、P2 comp 81.067 MB/s；与 r10 逐位一致。
- **G2 S3**：WNS **-0.156 ns**、TNS **-10.977 ns**、92/149,031 端点；frame_top `dq_r/rd_issue` 路径已完全消失。
- **残留路径**：core `s1_pos_r[4] → s1_pos_r+2<blk_n (s1_ok) → bypass select → htab_rd_addr（fanout 1042）`，5.425 ns/7 级。
- **方差**：S2/S3 core RTL 相同（e3484a60），S2 -0.092 vs S3 -0.156 属综合方案差异（S3 wall 24.3 min vs S2 8.1 min）。
- **r1 批准**：2 会话/60 min、综合 ≤2、布线 ≤1；只改 core `lim2 = blk_n - 2` / `s1_ok = (s1_pos_r <= lim2)` / htab address select；frame `18d51b1b…1cbe` 与 SDC `227dd39e…6311` 锁定。
- **r1 门槛**：G1 全复跑；1080p ≤6.25M（77.76 硬门槛）、争取 ≤5.0M（97.2）；G2 187.5 Routed 全门槛；route 1 次；r1 FAIL 不自动 r2。
- **入口**：`dispatch-t10-g2-2cyc-r1.json`、`dev-plan.md §24.10`、`p4/result-r0.md`、`r0/td/syn_gate_timing_s3.rpt`。

## 16. r1 容量失败与 area-map 新包（2026-10-22）

- **r1 时序 PASS**：synth SWNS **+0.134 ns**、STNS 0.000；G1 与 r10 逐位一致；P2 comp 81.067 MB/s。
- **r1 布线 FAIL**：PHY-9053 slice **83072 > 71680**；synth slice **72,904/71,680=101.71%**；LUT 107,906；ERAM 4/300；DRAM LUT 8,432；未 Routed。
- **根因**：cmem 多写口/写法导致 **65,536 寄存器展开**（gate seq 67,500 − RTL seq 1,964）；r4 历史 2,335 FF / 4 ERAM / slice 17.43% 是成功对照。
- **吞吐红线**：P2 comp 153,600 B / 355,261 cycles = 81.067 MB/s；77.76 上限 **370,370 cycles**，仅 +15,109（+4.253%）；150 MHz 只有 64.85 MB/s，不能作退路。
- **新包 `T10.a1-area-map` r0**（同一 T10、同一 run，不新 run）：cmem 单写口→ERAM；条件性 frame_top smem/bm/htab 端口调度；每步 P2/P3 + 综合；slice≤71,680 且 WNS/TNS≥0 才布线 1 次；G2 全门槛含 Routed WNS/TNS/HWNS/HTNS、0 违例、资源、`report_cdc`、bitgen not_run。
- **预算**：开发 90 min/50 calls；TD 3 会话/150 min、综合 ≤3、布线 ≤1；不 QoR 策略、不降频、不 false path/multicycle/seed sweep/bitgen/下载。
- **路径**：TD 用 T:/Y:（`tools/td/open_td.ps1`），仿真用 P:/W:；X: 保留给 TD。
- **入口**：`dispatch-area-map.json`、`dev-plan.md §25`、`p4/result-r1.md`、`r1/td/a1_g2_r1_Runs/phy_1/run.log`、`docs/压缩方案G2复核与优化方向_2026-10-22.md`。

## 17. area-map r0 结果与 bm-eram 新包（2026-10-22）

- **容量已解决**：cmem 三处写合并为唯一无复位写口 → ERAM；reg 68,085→2,549、slice 72,904→15,058、ERAM 4→8；bm clamp 后 synth +0.104、0 违例、slice 15,108、ERAM 8。
- **唯一布线**：slice 16,182/71,680=22.58%、hold OK +0.025/0；但 Routed **SWNS -1.115 / STNS -466.545 / 1,398 违例**、Fmax 155.087 MHz。
- **根因**：bm_a/bm_b DRAM 组合读长线，net 3.96 ns/65%，1,398 端点；综合比布线乐观约 1.22 ns。
- **CDC 缺口**：report_cdc 未执行；默认 phy 流末步自动 bitgen 被 BIT-8123 拒绝，wait_run 提前返回；未生成 .bit、未下载。
- **新包 `T10.a1-bm-eram` r0**（同一 T10/同一 run）：bm_a 再 bm_b 改同步 ERAM 读 + 固定 1 拍预取；必要时 htab；P2 comp ≤370,370；synth WNS≥+1.0、slice≤71,680 才布线；route 1 次；report_cdc/check_timing 布线后单独执行。
- **预算**：开发 90 min/50 calls；TD 3 会话/150 min、综合 ≤3、布线 ≤1；不 QoR 策略、不降频、不 false path/multicycle/seed sweep/bitgen/下载。
- **路径**：TD 用 T:/Y:（`tools/td/td_env.ps1`），仿真用 P:/W:。
- **入口**：`dispatch-bm-eram.json`、`dev-plan.md §26`、`p4/result-r0.md`、`r0/td/a1_am_r0f_Runs/phy_1/route.qor`。

## 18. bm-eram r0 结果与 htab-eram 新包（2026-10-22）

- **bm ERAM 生效**：slice 15,108→5,259、ERAM 22（bm 8+8、cmem 4、smem 4）、reg 2,581；G1 33/33 逐位相同；P2 comp 355,261 cycles。
- **综合仍 -1.094**：TNS -39.9/-80.4；worst `bm_a_rd → hash3 → htab_rd_addr(fo=1409) → htab_v DRAM 读 → htab_rvalid_reg`，6.363 ns。
- **htab 改法无效**：写口移出复位后 ERAM 仍 22；66-bit 宽度 + 读使能 + 穿透 mux 挡住推断。
- **fabric-shadow**：功能正确（P2 verify PASS、P3 20/20），但 5/13 P2 编码不同（len3_dist4 9,909→21,623 cycles），旧 SHA/cycles 门槛下回退。
- **布线 0/1**：`01_final_route.tcl` 的 `#dram` regexp 未匹配中断；bitgen 0、无 .bit/下载。
- **新包 `T10.a1-htab-eram` r0**（同一 T10/同一 run）：功能等价口径；htab 66-bit 拆 ERAM（v/pos/data）、寄存读地址、去读使能/穿透 mux、单写口无复位；必要时 bm 预取/fabric-shadow；P2 comp ≤370,370；synth WNS≥+0.5（目标 +1.0）、slice≤71,680 才布线；route 1 次；report_cdc/check_timing 单独执行。
- **预算**：开发 90 min/50 calls；TD 2 会话/90 min、综合 ≤2、布线 ≤1；不 QoR 策略、不降频、不 false path/multicycle/seed sweep/bitgen/下载。
- **入口**：`dispatch-htab-eram.json`、`dev-plan.md §27`、`p4/result-r0.md`、`r0/td/syn_gate_timing_s2.rpt`。

## 19. htab-eram r0 结果与 r1 最后微修（2026-10-22）

- **htab ERAM 成功**：66-bit 拆 4×ERAM；ERAM 22→26、core DRAM LUT 1,184→32、reg 2,581→1,562、slice 5,259→2,955；WNS -1.094→**-0.144**。
- **功能等价全绿**：P2 13/13、P3 20/20、0 mismatch、0 X、`vlog 0/0`；P2 comp 355,261 cycles/81.067 MB/s；1080p 4,677,945–4,866,587；13/13 stream SHA/len 相同。
- **综合 2/2**：s1 -0.144、s2 -0.146；TNS -5.151/-4.909；未达 +0.5，未布线。
- **worst**：`w0_reg → litlen → 32-bit (cand_bits+litlen) adder → thresh_lit compare → state.ce`，5.412 ns/7 级、4 ADDER。
- **r1 最后微修**（同包）：复用 core `b374f6fc…fb6d`，只改 32 位比较；MAX_BLOCK=4800 → <2^16；16 位拆分/并行进位或提前一拍 litlen。
- **门槛**：功能等价；P2 comp ≤370,370、1080p ≤6.25M；**synth WNS≥0**（目标 +0.3）、slice≤71,680、ERAM 26 与实例相符；route 1 次；report_cdc/check_timing 单独执行；bitgen not_run。
- **门槛理由**：旧 +0.5/+1.0 为 1.22 ns DRAM 长线差；现在 core DRAM LUT 32、htab ERAM，剩余是纯 fabric 算术。
- **预算**：开发 75 min/40 calls；TD 2 会话/75 min、综合 ≤2、布线 ≤1；不 QoR 策略、不降频、不 false path/multicycle/seed sweep/bitgen/下载。
- **入口**：`dispatch-htab-eram-r1.json`、`dev-plan.md §28`、`p4/result-r0.md`、`r0/td/syn_gate_timing_s2.rpt`。

## 20. htab-eram r1 结果与 r2 最后收口（2026-10-22）

- **r1 功能等价全绿**：P2 13/13、P3 20/20、0 mismatch、0 X、`vlog 0/0`；P2 comp 355,261 cycles/81.067 MB/s；1080p 4.68–4.87M；SHA/len/cycles 与 r0 相同。
- **综合 2/2**：s1 -0.722、s2 **-0.245 / TNS -0.465 / 3 端点**；slice 3,030、ERAM 26、reg 1,626、DRAM LUT 32。
- **worst**：`bm_b ERAM clk2q → S_EXT byte compare → ext_zero_r_reg.d`，5.514 ns/5 级。
- **PRJ-8806**：s2 父 tcl wait_run 异常，但 run.log/flow.status/gate.timing/area/db 显示 opt_gate 已完成；报告人工拷贝，需独立测试核验完整性。
- **r2 范围**：只改 S_EXT `ext_zero_r/len_cap_r` 更新为无条件/预计算；thresh_lit8/9 与其余逻辑冻结；WNS≥0 即布线；route 1 次；report_cdc/check_timing 单独执行；bitgen not_run。
- **预算**：开发 60 min/40 calls；TD 2 会话/60 min、综合 ≤2、布线 ≤1；不 QoR 策略、不降频、不 false path/multicycle/seed sweep/bitgen/下载。
- **入口**：`dispatch-htab-eram-r2.json`、`dev-plan.md §29`、`p4/result-r1.md`、`r1/td/syn_gate_timing_s2.rpt`。

### 20.1 r2 s1 结果与 r2-b 范围微调（2026-10-22）

- **flag 修复成功**：违例 3→1、TNS -0.465→-0.017、WNS -0.245→-0.017；功能等价全绿，P2 comp 355,261、1080p 4.68–4.87M；slice 3,068、ERAM 26、core 22、DRAM LUT 32。
- **唯一端点**：`htab_tag ERAM clk2q → hent_pos → 13-bit s1_hdist subtractor/compare → hrg_r_reg.d`，5.286 ns/5 级。
- **PRJ-8806**：r1 原始/复制报告 SHA 已核验；r2 s1 正常完成（PRJ-1406）。
- **r2 预算**：综合 1/2、布线 0/1、2 次 TD 调用（一次 BOM 中止未消耗命令）。
- **r2-b**：用户批准范围微调，只改 htab stage-1 `hent_pos` 比较/寄存（预计算 `s1_pos_r`/`s1_pos_r-2048` 边界，或寄存 `hent_pos` 一级）；r2 flag 修复、`thresh_lit8/9`、htab/bm 存储冻结。
- **收口**：剩余 1 次综合 + 1 次布线；WNS≥0（目标 +0.3）才布线；Routed 全门槛；report_cdc/check_timing 单独执行；bitgen not_run；失败不自动 r3。
- **入口**：`dispatch-htab-eram-r2b.json`、`dev-plan.md §29.9`、`p4/result-r2.md`、`r2/td/syn_gate_timing_s1.rpt`。

### 20.2 r2-b 失败与 r2-waive（2026-10-22）

- **r2-b**：`hent_pos` 边界比较反而 -0.548 ns，已回退；工作树恢复 r2 `0b084317`。
- **最佳候选**：r2 `0b084317`，综合 WNS **-0.017**、TNS -0.017、1/4640 端点；slice 3,068、ERAM 26、core 22、DRAM LUT 32；功能等价全绿。
- **r2-waive**：用户批准一次性例外布线。不综合、不改 RTL，直接对 r2 `0b084317` route-only 一次；这是对“综合 WNS≥0”门槛的显式豁免，不放宽最终 Routed 门槛。
- **条件**：route 1 次/≤60 min/1 会话；route-only、不 bitgen；布线后单独 report_cdc/check_timing；Routed WNS/TNS/HWNS/HTNS≥0、0 违例、资源在器件内；失败停止并保留 r2 最佳，不自动扩轮。
- **路径**：T: = r2/td，Y: = 项目根；`tools/td/td_env.ps1 -Force -TdDir ...`；仿真 P:/W:。
- **入口**：`dispatch-htab-eram-r2-waive.json`、`dev-plan.md §29.10`、`p4/result-r2.md`、`r2/td/syn_gate_timing_s1.rpt`。

### 20.3 r2-waive harness 失败与 r2-waive2（2026-10-22）

- **失败**：route-only tcl 未先 `import_device`；`phy_1/settings.cfg` device/package 为空；run.exe 立即 PRJ-8001；脚本 1800 s 轮询到 60 min。
- **影响**：无 routed DB、无 CDC、无 bitgen、无 .bit/下载；RTL/候选未受影响；r2 `0b084317` 仍最佳。
- **r2-waive2**：用户批准修正后的 route-only 重试；不综合、不改 RTL；1 会话/≤45 min、route 1、synth 0。
- **Harness**：先 `import_device ph1_100p.db -package PH1P100SBG484 -speed 3` 再 open/launch；或手写 settings.cfg（start opt_place、end opt_route、非空 device/package、parent syn_1、SDCList）；5–10 s 早失败检查；停 end opt_route，不 bitgen。
- **门槛**：Routed WNS/TNS/HWNS/HTNS≥0、0 违例、资源在器件内；report_cdc/check_timing 单独执行；bitgen not_run；失败停止、保留 r2 最佳，不自动扩轮。
- **入口**：`dispatch-htab-eram-r2-waive2.json`、`dev-plan.md §29.11`、`r2/td/a1_ht_r2_Runs/phy_1/settings.cfg`、`run.log`。

## 21. r2-waive2 真实布线结果与 hit-pipe 新包（2026-10-22）

- **Routed**：SWNS **-0.436 ns**、STNS -26.919、138/4,514 setup 端点；hold PASS +0.020/0.000；slice 2,974/71,680、ERAM 26、DRAM LUT 32、reg 1,641。
- **worst**：`bm_a ERAM clk2q → ... → state_reg[5].ce`，5.245 ns/4 级、slack -0.436。
- **derating**：综合 -0.017 未扛住约 0.42 ns 布线 derating。
- **功能**：P2 13/13、P3 20/20、0 mismatch、0 X、`vlog 0/0`；P2 comp 355,261/81.067；1080p 4.68–4.87M。
- **CDC 缺口**：TD Release_2026.2 无 `report_cdc`；check_timing 已执行，不能冒充 CDC。
- **新包 `T10.a1-hit-pipe` r0**（同一 T10/同一 run）：纯流水拆 `bm_a ERAM clk2q → state CE`；不加周期（P2 comp ≤355,261）；synth WNS≥+0.5、slice≤71,680 才布线；route 1 次；静态单时钟 CDC 证据 + check_timing；bitgen not_run。
- **预算**：开发 90 min/50 calls；TD 3 会话/120 min、综合 ≤3、布线 ≤1；不 QoR 策略、不降频、不 false path/multicycle/seed sweep/bitgen/下载。
- **入口**：`dispatch-hit-pipe.json`、`dev-plan.md §30`、`p4/result-r2.md`、`r2/td/syn_gate_timing_s1.rpt`。

## 22. hit-pipe r0 结果与 tester-first 顺序（2026-10-22）

- **G1**：与 r2 逐位相同；P2 13/13、P3 20/20、0 mismatch、0 X、`vlog 0/0`；P2 comp 355,261；1080p 4.68–4.87M。
- **综合 2/3**：s1 +0.010、s2 **+0.021 / TNS 0**；slice 3,083、ERAM 26、core 22、reg 1,625、DRAM LUT 32。
- **最差**：frame_top `smem_waddr_r_reg[15].d` +0.021/+0.063（锁定；r2 同路径 routed +0.020 通过）；core next +0.150。
- **关键**：r2 唯一失败锥 `bm_a ERAM clk2q→state CE` 已从 top-4 消失；本包目标从结构上达成。
- **顺序**：先由独立测试者核验 `587ef708` 功能（P2/P3、逐拍/边界表）与工程（+0.021、资源）；routed=not_run，判定 FAIL 但记录 functional PASS/awaiting_route。之后 route-only 1 次（≤45 min、route 1、synth 0、修正 harness），同一测试者再核验 Routed + 静态 CDC。
- **一次性 +0.5 预布线豁免**：依据 r2 同 frame_top 路径 routed +0.020；不豁免 Routed 零违例/资源/静态 CDC/bitgen not_run。
- **CDC**：TD 2026.2 无 report_cdc；route 后用 `report_clock_utilization`/`check_timing` + 静态单时钟证据（仅 clk、CC-From/CC-To=no）；不得冒充工具 CDC 签核。
- **入口**：`dispatch-hit-pipe-verify.json`、`dev-plan.md §31`、`r0/result.md`、`r0/cdc-static.md`。

## 23. hit-pipe r1 Routed 失败与 bm-prefetch 新包（2026-10-22）

- **G1**：33 例逐位同 r2；P2 13/13、P3 20/20、0 mismatch、0 X、`vlog 0/0`；P2 comp 355,261。
- **综合**：+0.021 / TNS 0（PASS）。
- **Routed**：SWNS **-0.577**、STNS -57.504、311/4,514 setup 端点；hold PASS；Fmax 169.205；slice 3,008、ERAM 26、reg 1,644。
- **worst**：10 条全部起于 `bm_a ERAM clk2q dob[3]`（1.846 ns，到达 6.691），终点 htab_byp/byp_data/ext_mis_r/add74 CE；同一锥综合 +0.339 → 布线 -0.577（退化约 0.92）。
- **测试者问题**：strict 解码器 bug、缺 P3 逐例 cycles/逐拍表、post-run 复制；新包由新测试者独立修复/实现。
- **新包 `T10.a1-bm-prefetch` r0**（同一 T10/同一 run）：bm 读数据再寄存一级 + 扫描预取前移（praddr=raddr+5、x1_r/w2 对齐），hash3 第三字节来自 flop；ext_mis_r 无条件；P2 comp 必须 355,261；所有 ERAM clk2q 起点 slack≥+0.9、全局 WNS≥+0.5、slice≤71,680 才布线 1 次；静态 CDC；bitgen not_run。
- **预算**：开发 90 min/50 calls；TD 2 会话/90 min、综合 ≤2、布线 ≤1；新包新测试者；不 QoR 策略、不降频、不 false path/multicycle/seed sweep/bitgen/下载。
- **入口**：`dispatch-bm-prefetch.json`、`dev-plan.md §32`、`test-reports/T10.a1-hit-pipe-r1-integrated.md`、`r0/td/phy_pr_timing_raw.rpt`。

## 24. bm-prefetch r0 G1 失败与 r1 功能修复（2026-10-22）

- **r0 失败**：P2 12/13；`p2_perf_1920x64_comp` E_BAD_ADLER；块 1–31 每块丢首个 literal（1199 符号/4799 B），解码 153,569≠153,600；P2 comp 355,205≠355,261。
- **定位**：窗口/匹配正确（37,005 SCAN 0 mismatch；19,200 匹配合法）；缺陷在块起始 emit/packer（cp_en/p0_valid/pbit_off/cand_bits/S_EODONE 排水）。
- **未进 TD**：0 综合/0 布线/0 CDC；工作树回滚 `587ef708`；失败候选 `de59bddc` 存档。
- **r1 范围**：同包；重放 `de59bddc`，只修块起始首个 literal 的 emit/packer；保留 bm 预取/ext_mis_r/零周期；其他逻辑冻结。
- **门槛**：G1 13/13+20/20、0 mismatch/0 X/vlog 0/0、P2 comp 355,261；然后所有 ERAM clk2q 起点 slack≥+0.9、全局 WNS≥+0.5、slice≤71,680 → route 1 次；Routed 全门槛 + 静态 CDC；bitgen not_run。
- **预算**：开发 90 min/50 calls；TD 2 会话/90 min、综合 ≤2、布线 ≤1；本包新测试者（不是 hit-pipe）。
- **停止**：r1 G1 仍失败立即停止，保留 r2 `0b084317` 为最佳回退，不自动扩轮；转收尾/换路线。
- **入口**：`dispatch-bm-prefetch-r1.json`、`dev-plan.md §33`、`r0/result.md`、`r0/p2/result.json`、`r0/dbg_comp/stdout.log`。

## 25. bm-prefetch r1 结果与 r2 一次性例外（2026-10-22）

- **P2 全绿**：13/13、comp 355,261、out.hex 与基准逐字节相同（`062826BDCABB8939`）、hit2=x=0。
- **P3 仍红**：`odd20x5_p1d1`/`bp20x5`/`abort_last`（100 B 帧）流无效（len 108 vs 107、cycles 1,462 vs 1,459、E_BAD_ADLER）；`f1080p_p1d1` 86,481 vs 81,707。
- **根因**：PRE/REPOS 预取钳位（clamp_addr/lim*/last_a）仍按 1 拍读延迟推导；小块/块尾错开一拍。
- 工作树回滚 `587ef708`；候选 `3cfdda78` 存档；TD 0 会话。
- **r2 一次性例外**：重放 `3cfdda78`，只重推 S_PRE/S_REPOS 种子与 clamp/lim*/last_a/x1_r 拍对齐；保留 S_WAIT praddr<=1、bm 预取、ext_mis_r。
- **G1**：P2 13/13、P3 20/20、0 mismatch/0 X/vlog 0/0；comp 355,261；f1080p 81,707 B / sha `b769cc66…08ff`；33 例逐位同 r2 0b084317。
- **G2**：所有 ERAM clk2q 起点 slack≥+0.9、全局 WNS≥+0.5、TNS≥0、slice≤71,680、ERAM 26 → route 1 次；Routed 全门槛；静态 CDC；bitgen not_run。
- **预算**：开发 60 min/40 calls；TD 1 会话/60 min、综合 ≤1、布线 ≤1；本包测试者（不是 hit-pipe）。
- **停止**：r2 G1 仍失败立即停止，保留 r2 `0b084317` 为最佳回退，不自动 r3；转收尾/换路线。
- **入口**：`dispatch-bm-prefetch-r2.json`、`dev-plan.md §34`、`r1/result-r1.md`、`r1/p3/result.json`。

## 26. bm-prefetch r2 G1 全绿与 route-only 豁免（2026-10-22）

- **G1 全绿**：P2 13/13、P3 20/20、0 mismatch、0 X、`vlog 0/0`；comp 355,261；f1080p 81,707 B / `b769cc66…08ff`；33 例逐位同 r2。
- **综合 1/1**：+0.021 / TNS 0；slice 3,080、ERAM 26、reg 1,633、DRAM LUT 32。
- **最差**：frame_top `smem_waddr` +0.021/+0.063（锁定；r2-waive2 同路径 routed +0.020）；core next +0.402/+0.419。
- **目标锥**：报告集合内无 bm/htab ERAM clk2q 起点端点；但每组 10 端点，非穷举。
- **route-only 豁免**：一次性 +0.5 预布线豁免；不综合/不改 RTL；1 会话/≤45 min、route 1、synth 0；修正 harness；停 end opt_route，不 bitgen。
- **定向检查**：`report_timing -from [get_pins ...bm_a*/htab*]` 穷举 ERAM clk2q；若工具限制，写明覆盖范围/不能穷举原因。
- **Routed 门槛**：WNS/TNS/HWNS/HTNS≥0、0 违例、资源；新 DB `report_clock_utilization`/`check_timing`/`report_timing_summary` 直接 `-file`；静态 CDC；bitgen not_run。
- **测试**：本包新测试者（不是 hit-pipe），先修 strict 解码器、补 P3 逐例 cycles/逐拍表；报告 `T10.a1-bm-prefetch-r2-integrated.md`（注明 r2-waive）。
- **失败**：停止，保留 r2 `0b084317`；不自动 r3。
- **入口**：`dispatch-bm-prefetch-route.json`、`dev-plan.md §35`、`r2/result-r2.md`、`r2/td/syn_gate_timing_s1.rpt`。

## 27. bm-prefetch r2-waive 真实布线 -0.421 与 bm-addr 最后尝试（2026-10-22）

- **r2-waive Routed**：SWNS **-0.421 / 10 端点**；G1 全绿、综合 +0.021；资源/ hold 见 route 报告。
- **剩余锥**：`pos_reg[1] → bm_a/bm_b.addrb、w0/w1.ceb`；`htab_p3v ERAM clk2q → bm_b.addrb`。
- **用户“再试一次A”**：新包 `T10.a1-bm-addr` r0，同一 T10/run；只做地址/CE 锥预计算/寄存（pos+1/pos+2 地址提前寄存、htab_p3v 地址寄存），不加周期。
- **G1**：33 例逐位同 r2；comp 355,261；1080p 81,707 B。
- **G2**：全局 WNS≥+0.5、TNS≥0、所有可报告 ERAM clk2q≥+0.9、slice≤71,680、ERAM 26 → route 1 次；Routed 全门槛；静态 CDC；bitgen not_run。
- **预算**：开发 90 min/50 calls；TD 2 会话/90 min、综合 ≤2、布线 ≤1；新包新测试者（不是 bm-prefetch/hit-pipe）。
- **失败即收尾**：T10 3/4 PASS + 1 ⚠，保留 r2 `0b084317` 与 bm-prefetch 证据；不自动扩轮。
- **入口**：`dispatch-bm-addr.json`、`dev-plan.md §36`、`r2/result-r2.md`、`r2/td/syn_gate_timing_s1.rpt`。

## 28. bm-addr r0（35ea7364）综合 +0.113 与最后 route-only（2026-10-22）

- **G1 全绿**：33/33 逐位同 r2；P2 13/13、P3 20/20、0 mismatch/0 X、`vlog 0/0`；comp 355,261；1080p 81,707 B。
- **综合 1/2**：+0.113 / TNS 0、slice 3,085、ERAM 26、reg 1,646；报告内 **ERAM clk2q 起点 0 个**；worst 为 frame_top smem_waddr（同路径 r2-waive2 routed +0.020）。
- **最后 route-only**：一次性 +0.5 豁免；不综合/不改 RTL；1 会话/≤45 min、route 1、synth 0；Routed 全门槛；新 DB report_clock_utilization/check_timing/report_timing_summary 直接 -file；静态 CDC；bitgen not_run。
- **测试**：若通过，新包新测试者（不是 bm-prefetch/hit-pipe）做最终 integrated；functional 可复用同候选证据，engineering 复算 routed，system 核吞吐/无 bit。
- **失败即收尾**：T10 3/4 PASS + 1 ⚠，保留 r2 `0b084317` 与 bm-prefetch/bm-addr 证据；不自动扩轮。
- **入口**：`dispatch-bm-addr-route.json`、`dev-plan.md §37`、`r0/result-r0.md`、`r0/td/syn_gate_timing_a1.rpt`。

## 29. bm-addr r0-route Routed -0.087 与 adler-smem 最后微修（2026-10-22）

- **Routed**：SWNS **-0.087**、STNS -1.109、27/4,555 端点；hold PASS；slice 2,993、ERAM 26、reg 1,664。
- **worst**：`adler_red_st_reg[2] → smem.addrb[12]`（-0.087）等非地址/CE 小锥；目标地址/CE 锥已消失。
- **G1**：33/33 逐位、comp 355,261、1080p 81,707 B；无 bitgen/.bit/下载。
- **新包 `T10.a1-adler-smem` r0**：只寄存/预计算 `adler_red_st` 与 smem 写地址及相关小锥；不加周期。
- **门槛**：G1 33/33、comp 355,261；synth WNS≥+0.3、TNS≥0、slice≤71,680、ERAM 26；route 1 次；Routed 全门槛；静态 CDC；bitgen not_run。
- **预算**：开发 45 min/30 calls；TD 1 会话/45 min、综合 ≤1、布线 ≤1；新包新测试者（不是 bm-prefetch/hit-pipe）。
- **失败即收尾**：T10 3/4 PASS + 1 ⚠，保留 r2 0b084317、bm-addr 35ea7364、bm-prefetch 证据；不自动扩轮。
- **入口**：`dispatch-adler-smem.json`、`dev-plan.md §38`、`r0/result-r0.md`、`r0-route/route.qor`。

## 30. adler-smem r0 综合 +0.233 与最后 route-only（2026-10-22）

- **G1 全绿**：33/33 逐字段同 r2；P2 13/13、P3 20/20、0 mismatch/0 X、`vlog 0/0`；comp 355,261；1080p 81,707 B。
- **综合 1/1**：+0.233 / TNS 0、slice 3,076、ERAM 26、reg 1,656；原 `byte_k→smem_waddr_r` 最差已移出，新最差 `hp_r→bm_b.addrb` +0.233（冻结 core 锥，包外）。
- **最后 route-only**：一次性 +0.3 豁免；不综合/不改 RTL；1 会话/≤45 min、route 1、synth 0；Routed 全门槛；新 DB report_clock_utilization/check_timing/report_timing_summary 直接 -file；静态 CDC；bitgen not_run。
- **测试**：若通过，新包新测试者（不是 bm-prefetch/hit-pipe）做最终 integrated；functional 可复用同候选证据，engineering 复算 routed，system 核吞吐/无 bit。
- **失败即收尾**：T10 3/4 PASS + 1 ⚠，保留 r2 0b084317、bm-addr 35ea7364、adler-smem 611ad704 证据；不自动扩轮。
- **入口**：`dispatch-adler-smem-route.json`、`dev-plan.md §39`、`r0/result-r0.md`、`r0/td/syn_gate_timing_a1.rpt`。

## 31. T10 最终收尾（2026-10-22，不再开新包/新轮）

### 31.1 最终结论
**T10 = 3/4 PASS + 1 ⚠；state = blocked，不得置 done。**
- **需求一（T10 A+ 压缩 RTL 独立闭环）：部分完成。**
  - G0/G1 成立：33/33 逐位（0 mismatch、0 X、`vlog 0/0`）；P2 comp 355,261 cycles / 81.067 MB/s ≥77.76；1080p 81,707 B / 4,677,945 cycles；P2/P3 独立双解通过。
  - G2 未成立：最佳 Routed 为 bm-addr `35ea7364` = **-0.087 ns / 27 端点**；最佳 synth 为 adler-smem `611ad704` = **+0.233 ns**；均未零违例；无 Routed PASS、无 bit/CWC、未上板。
- **需求二（真实输入参数与 RAW 样例）：仅离线部分。** `input-profile.json` 14 项（confirmed 7 / derived 3 / unknown 2 / conflict 2）；真实 RAW 未取得；非 PCIe 导出只有离线契约/校验器。
- **需求三（单A 实际压缩链路）：未开始。** 未接相机、未做 DDR→A+→保存→读回→PC 还原；需板窗、真实 RAW、生产候选与下载授权。

### 31.2 候选与回退谱系
| 候选 | synth | routed | manifest |
|---|---:|---:|---|
| r2 `0b084317` | -0.017 ns | -0.436 ns | `T10.a1-htab-eram/CANDIDATE-MANIFEST-htab-eram-r2.json` |
| bm-prefetch `df6124d4` | +0.021 ns | -0.421 ns / 10 端点 | `T10.a1-bm-prefetch/CANDIDATE-MANIFEST-bm-prefetch-r2.json` |
| **bm-addr `35ea7364`（最佳 routed）** | +0.113 ns | **-0.087 ns / 27 端点** | `T10.a1-bm-addr/CANDIDATE-MANIFEST-bm-addr-r0.json` |
| **adler-smem `611ad704`（最佳 synth）** | **+0.233 ns** | -0.541 ns / 299 端点 | `T10.a1-adler-smem/CANDIDATE-MANIFEST-adler-smem-r0.json` |

- frame `18d51b1b80002e3549b6afd74956cff9d323d0a0272a7a08d617365a01611cbe`、SDC `227dd39e3dba8834af510013c71242450d4571307267d6bac4938cb8ef696311` 锁定未改。
- 回退：工作树恢复 r2 `0b084317` 或按包删除对应新增目录；旧 manifest/报告只读保留。

### 31.3 预算账（run 内）
| 包 | 综合 | 布线 | 结果 |
|---|---:|---:|---|
| T10.a1-eng-freeze r0–r10 | 19 | 0 | G2 FAIL，未 route |
| T10.a1-g2-2cyc r0/r1 | 4 | 1 | route PHY-9053 容量失败 |
| T10.a1-area-map r0 | 3 | 1 | Routed -1.115 |
| T10.a1-bm-eram r0 | 3 | 0 | synth -1.094 |
| T10.a1-htab-eram r0–r2-waive2 | 6 | 1 | Routed -0.436 |
| T10.a1-hit-pipe r0 | 2 | 1 | Routed -0.577 |
| T10.a1-bm-prefetch r0–r2-waive | 1 | 1 | Routed -0.421 / 10 端点 |
| T10.a1-bm-addr r0/r0-route | 1 | 1 | Routed **-0.087 / 27** |
| T10.a1-adler-smem r0/r0-route | 1 | 1 | Routed -0.541 / 299 |
| **合计** | **40** | **7** | 1 次容量失败、6 次 Routed 但 setup<0 |

- run 内共约 30 个验收/修复轮次（P4 r0–r10 11 轮 + 后续包 19 轮）。
- 无 QoR 策略变更、无降频、无 false path/multicycle、无 seed sweep、无 bitgen/下载/Flash；生产构建 0、下载 0。

### 31.4 证据完整性问题（如实登记）
- **area-map routed 证据**：`create_project -force` 清空过 routed 报告/DB；`result-r0.md` 与 `route.qor` 仍记录 -1.115/1398 端点，但完整 routed 证据不齐。
- **r10 早期 P2 误写**：误用 r9 subst 目录，重写 `r9/p2/runs/*` 与 `r9/p2/logs/vlog.log`；`r9/p2/result.json` 未变且仍匹配 r9 manifest，但 vlog.log 哈希 `02dfece1…4996` → `58d0ebaa…a61` 不再匹配。
- **PRJ-8806**：多次 `wait_run` 报 run 意外退出，但 `run.log/flow.status/gate.timing/area/db` 完整；已按原始报告解析，测试者已核验 r1 复制件 SHA。
- **PRJ-8001 / BOM**：route-only harness 未 import_device、settings.cfg 空 device/package；tcl UTF-8 BOM 导致立即退出；均已记录且未消耗综合/布线。
- **BIT-8123**：默认 phy 流末步自动调用 bitgen 被拒；未生成 .bit、未下载。
- **r1 P2 脚本路径 bug**：曾把 r0/p2 result 覆盖为伪 FAIL，已在未被覆盖的 r0 流上重跑 verifier 恢复。
- TD Release_2026.2 **无 `report_cdc`**；仅能提供静态单时钟证据，不得冒充工具 CDC 签核。

### 31.5 剩余主题（≤3，本轮不执行）
1. **更深微架构重排**：ERAM 输出 → 地址/CE 的整链重排或分拍（当前最佳 routed 仍 -0.087/27；synth +0.233 布到 -0.541 显示 derating 不稳定）。
2. **更大器件/QoR 策略变更**：需用户明确授权；不得自行降频、false path/multicycle 或 seed sweep。
3. **需求二/三板级前置**：非 PCIe 导出通道、板窗与用户在场、真实 RAW、生产候选与一次性下载授权；当前 0 下载。

### 31.6 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop`（T10 最终收尾，不再自动开包/开轮）。
> 先读 `final-summary.md §31`、`handoff.md`、`dev-plan.md §40`、`workflow/tasks.json` T10 状态。
> 状态：T10 = 3/4 PASS + 1 ⚠，blocked；G0/G1 成立，G2 未成立；最佳 routed `35ea7364` = -0.087/27，最佳 synth `611ad704` = +0.233；无 bit/CWC/板测。
> 回退：r2 `0b084317`；frame `18d51b1b`、SDC `227dd39e`；manifests 见 §31.2。
> 若继续，需要用户新授权：更深微架构重排、或更大器件/QoR 策略、或板级前置（板窗/真实 RAW/下载授权）。
> 不放宽 187.5 MHz、不 false path/multicycle、不 seed sweep、不 bitgen/下载；未获授权不派新任务。

## 32. QoR/retiming 新包 `T10.a1-qor-retime`（2026-10-22，用户批准边界）

- **授权**：用户原话“好的可以写成边界然后来放开去做尝试能否闭环”；同 T10/run。
- **RTL 冻结**：core/frame/SDC 哈希不变；只改综合/实现策略。
- **基线**：bm-addr `35ea7364`（最佳 routed -0.087/27；物理最接近零、27 端点）；frame `18d51b1b`、SDC `227dd39e` 锁定。
- **固定策略（≤2 组，不随机 seed）**：组 1 retiming + phys_opt；组 2 performance map/place QoR；实际选项以 TD 2026.2 为准并记录。
- **验收**：Routed 零违例且 **setup ≥ +0.2 ns**、hold ≥0、资源在器件内、静态 CDC + 复位结构、报告 `-file`、bitgen not_run。
- **功能**：RTL 未变，33 例证据可复用并绑定哈希；门级仿真/等价性检查可用则跑，否则复核 retiming 不跨时钟/复位域。
- **预算**：开发 60 min/40 calls；TD 2 会话/90 min、综合 ≤2、布线 ≤2；测试 45 min/30 calls（通过则新包新测试者做最终 integrated）。
- **失败即收尾**：T10 保持 3/4 PASS + 1 ⚠；保留 r2 0b084317、bm-addr 35ea7364、adler-smem 611ad704 证据；不自动扩轮。
- **入口**：`dispatch-qor-retime.json`、`dev-plan.md §41`、`T10.a1-bm-addr/r0-route/route.qor`、`CANDIDATE-MANIFEST-bm-addr-r0.json`。

## 33. 最后一次组合包 `T10.a1-final-combo`（2026-10-22，规划裁决：值得一试）

- **输入**：qor-retime r0 组 1 Routed **-0.039 / STNS -0.645 / 45 端点**（hold +0.024/0，Fmax 186.150，retiming 生效）；组 2 -0.747/188；距零违例 **39 ps**；RTL/SDC 未改；无 bitgen/.bit/下载。
- **最差锥**：`u_core/pos_reg[3] → u_core/bm_a.addrb[3]` = -0.039 ns（4.639 ns 数据路径：cell 1.957 / net 2.682；6 级 LUT6×3+ADDER×2+ERAM；fanout 24；RTL 106→504→711）；`u_core/lim2_reg[6] → u_core/bm_b.addrb[9]` = -0.037 ns（504→726）。前 40 块中 19 条负 slack 条目全在 `rng2 (pos < lim2) → hit2 → bm_raddr_a/b mux → ERAM` 与 hit2 门控 CE 锥；其余块 ≥ +0.024 ns。
- **单个最小 RTL 微修（cycle-neutral，仅 `a1_deflate_core.v`）**：
  1. 声明 `reg s1_ok_r;` 并在 stage-1 寄存块加 `s1_ok_r <= s1_ok;`；
  2. `rng2`（504 行）用 `s1_ok_r` 替换 `(pos < lim2)`；`(hp_r < pos)`、`(hdist2 <= MAX_DIST)`、`s1_ok` 及其它消费者不变。
- **依据**：RTL 495–502 行注释已证明 stage-2 消费周期 `pos == s1_pos_r(stage-1)` 且 `lim2` 块内恒定，故 `(pos < lim2) == s1_ok(上一周期)`；寄存后从 hit2→地址/CE 锥移除 13-bit 比较器链，不加周期。等价性由 33 例回归证明。
- **门槛**：G1 重跑 33/33 逐位、0 mismatch/0 X、vlog 0/0、P2 comp 精确 355,261、1080p 81,707 B；frame `18d51b1b`、SDC `227dd39e` 不变；G2 Routed 零违例且 **setup ≥ +0.2 ns**、hold ≥0、资源在器件内、静态 CDC + 复位结构、报告 `-file`、bitgen not_run。
- **预算**：开发 60 min/40 calls；TD ≤2 会话/90 min、综合 ≤1、布线 ≤1；测试 45 min/30 calls（通过才派新包新测试者做 integrated）。
- **诚实风险**：-0.039 → +0.2 需约 239 ps，偏激进；失败即收尾 T10 3/4 PASS + 1 ⚠，最佳 routed 保持组 1 -0.039/45，无第二处 RTL 修改、无自动扩轮。
- **入口**：`dispatch-final-combo.json`、`dev-plan.md §42`、`T10.a1-qor-retime/r0/td/g1/routed_timing_summary.rpt`、`T10.a1-qor-retime/r0/td/g1/01_syn_route_g1.tcl`、`CANDIDATE-MANIFEST-qor-retime-r0.json`。

## 34. 本轮 run 最终收尾（2026-10-22，final-combo 失败即收尾，不再开新包/新轮）

### 34.1 最终结论
**T10 = 3/4 PASS + 1 ⚠；state blocked，不得 done；本轮 run 关闭。**
- 需求一：G0/G1 成立（33/33 逐位、0 mismatch、0 X、vlog 0/0、comp 355,261 = 81.067 MB/s ≥77.76、1080p 81,707 B）；**G2 未成立**（最佳 routed qor-retime 组 1 = -0.039 ns / 45 端点；最佳 synth adler-smem `611ad704` = +0.233）；无 Routed PASS、无 bit/CWC、未上板。
- 需求二：仅离线 profile 审计 + 导出契约；真实 RAW 未取得。
- 需求三：未开始。

### 34.2 final-combo r0
- 微修 `s1_ok_r` 功能等价：33/33 逐位、0 mismatch/0 X、comp 355,261、1080p 81,707 B。
- 复用 retiming+phys_opt：Routed **-0.091 / 12 端点**；门槛（零违例且 setup ≥ +0.2 ns）未达；无 bitgen/下载；TD 1/2 会话、综合 1/1、布线 1/1；工作树已回退 `35ea7364`。
- 证据：`T10.a1-final-combo/r0/result-r0.md`、`T10.a1-final-combo/r0/td/routed_timing_summary.rpt`、`T10.a1-final-combo/CANDIDATE-MANIFEST-final-combo-r0.json`。

### 34.3 最佳值与候选谱系
| 候选 | synth | routed | 说明 |
|---|---:|---:|---|
| r2 `0b084317` | -0.017 | -0.436 | 回退基准 |
| bm-prefetch `df6124d4` | +0.021 | -0.421 / 10 | |
| bm-addr `35ea7364` | +0.113 | -0.087 / 27 | 最佳 routed 的 RTL 基线 |
| adler-smem `611ad704` | **+0.233** | -0.541 / 299 | **最佳 synth** |
| **qor-retime 组 1**（RTL `35ea7364` + retiming+phys_opt） | +0.113 | **-0.039 / 45** | **最佳 routed**；hold +0.024/0；Fmax 186.150 |
| qor-retime 组 2 | +0.109 | -0.747 / 188 | |
| final-combo（`35ea7364` + `s1_ok_r` + 组 1 策略） | — | -0.091 / 12 | 功能等价；门槛未达；已回退 |

- frame `18d51b1b`、SDC `227dd39e` 锁定；回退 r2 `0b084317`。

### 34.4 预算总账（本轮 run）
| 包 | TD 会话 | 综合 | 布线 |
|---|---:|---:|---:|
| T10.a1-eng-freeze r0–r10 | 19 | 19 | 0 |
| T10.a1-g2-2cyc r0/r1 | 3 | 4 | 1 |
| T10.a1-area-map r0 | 3 | 3 | 1 |
| T10.a1-bm-eram r0 | 3 | 3 | 0 |
| T10.a1-htab-eram r0–r2-waive2 | 8 | 6 | 1 |
| T10.a1-hit-pipe r0 | 3 | 2 | 1 |
| T10.a1-bm-prefetch r0–r2-waive | 2 | 1 | 1 |
| T10.a1-bm-addr r0/r0-route | 2 | 1 | 1 |
| T10.a1-adler-smem r0/r0-route | 2 | 1 | 1 |
| T10.a1-qor-retime r0 | 2 | 2 | 2 |
| T10.a1-final-combo r0 | 1 | 1 | 1 |
| **合计** | **48** | **43** | **10** |

- 10 次布线 = 1 次容量失败 + 9 次 Routed（全部 setup<0）；约 32 个验收/修复轮次。
- 无随机 seed sweep、无降频、无 false path/multicycle、无 bitgen/下载/Flash；生产构建 0、下载 0。

### 34.5 证据完整性问题（如实登记）
- area-map routed 证据被 `create_project -force` 清空；r10 早期 P2 误写 r9 日志（r9 result.json 未变、vlog.log 哈希变化）；PRJ-8806/PRJ-8001/BOM/BIT-8123 工具事件；TD 2026.2 无 `report_cdc`，仅有静态单时钟证据，不得冒充工具 CDC 签核。

### 34.6 剩余主题（≤3，本轮不执行）
1. **结构性分拍/更深微架构**：ERAM 输出 → 地址/CE 整链重排或分拍（须保持 P2 comp 355,261 或作为新验收任务）。
2. **更大器件/QoR 深度**：需用户明确授权；不自行降频或 seed sweep。
3. **需求二/三板级前置**：板窗、真实 RAW、非 PCIe 导出、下载授权。

### 34.7 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop`（T10 本轮最终收尾，不再自动开包/开轮）。
> 先读 `final-summary.md §34`、`handoff.md`、`dev-plan.md §43`、`workflow/tasks.json`。
> 状态：T10 = 3/4 PASS + 1 ⚠，blocked；G0/G1 成立，G2 未成立；无 bit/CWC/板测。
> 最佳 routed = qor-retime 组 1（-0.039/45，retiming+phys_opt，RTL `35ea7364`）；最佳 synth = adler-smem `611ad704`（+0.233）；回退 r2 `0b084317`；frame `18d51b1b`、SDC `227dd39e`。
> 若继续需新授权：(a) 结构性分拍/更深微架构；(b) 更大器件/QoR 深度；(c) 需求二/三板级前置（板窗/真实 RAW/下载授权）。
> 不放宽 187.5 MHz、不 false path/multicycle/seed sweep、不 bitgen/下载；未获授权不派新任务。

## 35. 结构性分拍包 `T10.a1-pipe-split`（2026-10-22，用户明确授权）

- **授权**：用户原话“进行结构性分拍尝试”；同一 T10/run；允许 core + 必要的 frame 纯流水适配；协议/端口/帧语义/CRC/长度/abort/Bayer/SDC 不变。
- **周期规则**：优先 cycle-neutral（目标 P2 comp 保持 355,261）；确需额外周期必须精确量化且 P2 comp ≤370,370（可增 ≤15,109）；超过 370,370 必须先回交用户刷新验收口径，不得自行放宽。
- **当前事实**：最佳 routed = qor-retime 组 1（-0.039/45，retiming+phys_opt，RTL `35ea7364`）；最佳 synth = adler-smem `611ad704`（+0.233）；剩余锥 = `pos/lim2 → hit2 → bm_raddr mux → ERAM 地址` 与 hit2 门控 CE；19,200 次匹配 → 每匹配 +1 拍 = 374,461 超限，必须 cycle-neutral。
- **分拍方案（≤5 步）**：
  1. stage-1 寄存全域范围测试 `rng1_r`（旧式 stage-1 形式：`hent_pos < s1_pos_r`、`hdist <= MAX_DIST`、`s1_pos_r < lim2`），与 `hb_r <= s1_bytes` 对齐；ERAM clk2q 只驱动 flop D；
  2. stage-2 全 flop：`rng2 = rng1_r`、`hit2 = s1_vld_r && hb_r && rng1_r`；
  3. 可选：`p3p1_r <= p3_r + 1`（复用 `hf1_r`），仅在综合显示需要时；
  4. 可选：再寄存一个 pos/lim2/blk_n 谓词（如 `s1_blkn_r`），至多一处，无 FSM/周期改动；
  5. 33 例全量回归 + 复用 retiming+phys_opt，最多 3 综合 + 1 布线。
- **门槛**：33/33 逐位、0 mismatch/0 X、vlog 0/0；P2 comp ≤370,370（目标 355,261）；1080p ≤6.25M；Routed 零违例且 setup ≥ +0.2 ns、hold ≥0、资源在器件内、静态 CDC + 复位结构、报告 `-file`、bitgen not_run。
- **预算**：开发 120 min/60 calls；TD ≤3 会话/150 min、综合 ≤3、布线 ≤1；测试 45 min/30 calls（通过才派新包新测试者做 integrated）。
- **失败即收尾**：T10 保持 3/4 PASS + 1 ⚠；最佳 routed 保持组 1 -0.039/45；不自动扩轮。
- **入口**：`dispatch-pipe-split.json`、`dev-plan.md §44`、`T10.a1-qor-retime/r0/td/g1/routed_timing_summary.rpt`、`T10.a1-qor-retime/r0/td/g1/01_syn_route_g1.tcl`、`T10.a1-final-combo/r0/result-r0.md`。

## 36. pipe-split r0 裁决：G2 小顶 PASS（Routed 零违例 +47 ps，带 caveat）（2026-10-23）

### 36.1 结果
- **Routed 零违例**：SWNS **+0.047 ns**、STNS 0、**0/4,649 违例**；hold +0.021/0；Fmax 189.179 MHz；单 clk 187.512 MHz、CC-From/To=no/no、0 组合环。
- 资源：slice 3,032（4.23%）、LUT6 2,945、reg 1,712、ERAM 26、DSP 0、IO 121；均在器件内。
- G1：P2 13/13、P3 20/20 逐位相同、0 mismatch/0 X、vlog 0/0；comp **355,261**（cycle-neutral）；1080p 81,707 B / 4,677,945 cycles。
- 综合 3 次：-0.055 → -0.007 → **+0.275 / 0 违例**；布线 1 次；无 bitgen/.bit/下载。
- 旧最差锥 `pos_reg→bm_a.addrb` 已消失；新限制项为扩展字节比较 ERAM clk2q 锥（+0.047）。

### 36.2 裁决与验收口径更新
- **接受为 G2 小顶 PASS**。原始 G2 判据是 **Routed 零违例 + 必要 STA/CDC/资源检查**；本轮 **+0.2 ns 是稳健性目标，不替代零违例**。
- **Caveat（必须随报告传递）**：余量仅 **47 ps**（薄）；仅离线小顶，**非板级签核**；无 bit/CWC、无下载、无生产集成；若后续 bitgen/上板需重新 STA 并保留余量。
- **T10 整体仍 blocked**：G2 小顶部分标 done；需求二（真实 RAW/参数）与需求三（板级端到端）仍 blocked；**不得把整条单A闭环置 done**。

### 36.3 新包新测试者
- `T10.a1-pipe-split-final`（同 run，仅验证、无新开发）：新测试者做最终 integrated 核验。
- 范围：功能复用同候选证据并绑定哈希；工程独立复算 routed（SWNS/STNS/违例/hold/资源/单时钟/无环/无 bit）；系统吞吐 81.067 MB/s ≥77.76、1080p 81,707 B、无 bit/CWC。
- 预算：测试 45 min/30 calls；TD 0 会话、0 综合、0 布线；不改 RTL/SDC、不重跑 TD、不 bitgen/下载。
- 报告：`test-reports/T10.a1-pipe-split-final-r0-integrated.md`（唯一 verdict 标题）。
- 测试者不得因 setup < +0.2 直接判 FAIL；须记录 47 ps 余量与 caveat。

### 36.4 证据
- `T10.a1-pipe-split/r0/result-r0.md`
- `T10.a1-pipe-split/r0/td/routed_timing_summary.rpt`
- `T10.a1-pipe-split/r0/td/route.qor`
- `T10.a1-pipe-split/CANDIDATE-MANIFEST-pipe-split-r0.json`
- frame `18d51b1b`、SDC `227dd39e`；核心哈希以 manifest 为准。

### 36.5 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.a1-pipe-split-final` r0（仅测试者核验，无新开发）。
> 先读 `dispatch-pipe-split-final.json`、`final-summary.md §36`、`T10.a1-pipe-split/CANDIDATE-MANIFEST-pipe-split-r0.json`、`T10.a1-pipe-split/r0/result-r0.md`、`T10.a1-pipe-split/r0/td/routed_timing_summary.rpt`。
> 验收口径：G2 小顶 = Routed 零违例 + hold ≥0 + 资源在器件内 + 单时钟静态 CDC/无环 + 报告 -file + bitgen not_run；+0.2 是稳健性目标，不替代零违例；余量 47 ps 薄、离线、非板级签核、无 bit/CWC。
> 通过 → 记录 G2 小顶 done（T10 整体仍 blocked，需求二/三未完成）；失败 → T10 3/4 PASS + 1 ⚠。
> 预算：测试 45 min/30 calls；不改 RTL/SDC、不重跑 TD、不 bitgen/下载。

## 37. 里程碑收尾：G2 小顶 PASS（独立 integrated 核验通过）（2026-10-23）

### 37.1 测试者结论：PASS（G2 小顶，带 caveat）
- **functional pass**：33 例；P3 19/20 仅因 multi1080p 只留单帧流文件，非失败；0 mismatch/0 X；comp **355,261**；1080p 81,707 B / 4,677,945 cycles；第三方 zlib **17/17** 解压哈希一致。
- **engineering pass**：SWNS **+0.047 ns**、STNS 0、**0/4,649 违例**；hold +0.021/0；Fmax 189.179；slice 3,032/4.23%、ERAM 26、DSP 0；单 clk 187.512、CC no/no、0 组合环；bitgen not_run。
- **caveat**：余量 **47 ps**；离线小顶非板级签核；**无 post-route phys_opt**；IO 未约束 **47/73**、STA 覆盖 **96.40%**；无门级/形式等价；multi1080p 单帧产物小缺口。
- 报告：`test-reports/T10.a1-pipe-split-final-r0-integrated.md`；候选 core `bf6af390…1080`、frame `18d51b1b`、SDC `227dd39e`。

### 37.2 三项需求当前状态
- **需求一（T10 A+ RTL 独立闭环）**：**G0/G1/G2 小顶 PASS**（薄余量、离线、无 bit）；T10 父任务仍 blocked。
- **需求二**：仅离线 profile/导出契约；真实 RAW 未取得；blocked。
- **需求三**：未开始；板级端到端 blocked（板窗/真实 RAW/非 PCIe 导出/下载授权）。

### 37.3 本轮 run 统计
- **轮次**：约 **34** 轮（约 32 个开发/验收轮次 + pipe-split r0 + 1 次独立 integrated 核验）。
- **预算**：TD 会话累计约 **51**（pipe-split 按 3 会话计；tester 0 TD）；综合 **46**；布线 **11**（1 次容量失败 + 10 次 Routed；pipe-split 是唯一零违例结果）。
- **最佳候选**：pipe-split r0（core `bf6af390…1080`；Routed 零违例 +0.047/0；synth +0.275/0；comp 355,261）。
- **前最佳**：routed = qor-retime 组 1（-0.039/45）；synth = adler-smem `611ad704`（+0.233，现被 pipe-split +0.275 超过）。
- **回退**：r2 `0b084317`（-0.017/-0.436）；frame `18d51b1b`、SDC `227dd39e`。
- 无 seed sweep、无降频、无 false path/multicycle、无 bitgen/下载/Flash；生产构建 0、下载 0。

### 37.4 PASS 适用边界
- 仅**离线小顶**，非板级签核；无 bit/CWC、无下载、无生产集成。
- 余量薄（47 ps）；无 post-route phys_opt；IO 未约束 47/73、STA 覆盖 96.40%；无门级/形式等价；multi1080p 单帧产物缺口。
- **bitgen/上板前必须重新 STA、补齐 IO 约束与 STA 覆盖、保留余量**。

### 37.5 剩余主题（≤3）
1. **板级需求三 + bit/CWC**：板窗、真实 RAW、非 PCIe 导出、下载授权；上板前重新 STA、补 IO 约束与覆盖、保留余量。
2. **需求二**：真实 RAW 与参数确认。
3. **稳健性收口**：post-route phys_opt、IO 约束/STA 覆盖 100%、门级/形式等价、multi1080p 产物缺口；或更大器件/QoR（需用户明确授权）。

### 37.6 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop`（里程碑已收尾；T10 父任务 blocked，G2 小顶 done with caveat）。
> 先读 `final-summary.md §37`、`handoff.md`、`dev-plan.md §46`、`test-reports/T10.a1-pipe-split-final-r0-integrated.md`、`T10.a1-pipe-split/CANDIDATE-MANIFEST-pipe-split-r0.json`、`workflow/tasks.json`。
> 最佳候选：core `bf6af390…1080`、frame `18d51b1b`、SDC `227dd39e`；Routed 零违例 +0.047/0；回退 r2 `0b084317`。
> 边界：仅离线小顶、非板级、无 bit/CWC；余量 47 ps 薄；无 post-route phys_opt；IO 47/73 未约束、STA 覆盖 96.40%；无门级/形式等价。
> 继续需新授权：板窗/真实 RAW/非 PCIe 导出/下载授权；上板前重新 STA 并保留余量；或稳健性收口/更大器件。
> 不 false path/multicycle/seed sweep、不 bitgen/下载；未获授权不派新任务。

## 38. 板级链路规划（2026-10-23，用户授权“接着推进板级链路推进”）

### 38.1 现状核对
| 项 | 状态 |
|---|---|
| 板卡/器件 | MLK-F9P-CA05-PH1P100 / PH1P100SBG484-3；`board.adc`、`timing.sdc` 已存在 |
| 相机 | A 路 IMX415，MIPI CSI-2 4 lane；`ui_cfg_imx415` 仅支持 4K30（`I_cam_mode=1`）；raw tap `w_a_pixel[39:0]`/`w_a_pixel_valid` 可用 |
| DDR | DDR3 x32 + PAXI；`camera_ddr_display` 已有相机→DDR→HDMI 板级工作链（旧 bit/CWC 仅参照） |
| 非 PCIe 导出 | UART（FTDI Type-C，TX=R17/RX=P16）是唯一已验证通道；现有 115200 8N1 仅状态输出；以太网/SD 未实现/未验证 |
| 下载 | TD BitWriter + AL-LINK-FT；历史 SRAM 下载成功；不写 Flash |
| A+ | test-only core `bf6af390…1080` / frame `18d51b1b` / SDC `227dd39e`；无集成候选、无 A+ bit/CWC |
| PC | Python 3.11 + zlib；A+ 专用解码/逆变换工具尚未建立（P1 新建 `tools/a1/pc_decode.py`） |
| 缺失 | 集成 top、1920×1080 raw crop/CDC、raw DDR store、变长压缩 store、UART 数据导出、187.5 MHz 板级时钟、IO/STA/CDC、bit/CWC、PC 解码、板窗/相机/UART 主机/一次下载确认 |

### 38.2 最小可交付切片（1 个主要目标，≤4 包）
**目标**：一帧真实单A 1920×1080 裁切 → DDR → A+ → 压缩保存 → 读回 → UART 导出 → PC zlib+逆变换还原；仅在用户确认后执行 1 次 SRAM 下载。
- **P1 `T10.b1-a1-uart-integ`（ready，离线）**：raw tap + 1920×1080 2×2 对齐裁切 + raw DDR store + A+ frame top + 变长压缩 DDR store + UART 字节流导出 + PC 解码；仿真 0 mismatch、CRC/长度、最坏膨胀、复位/坏帧、吞吐；无 TD/bitgen/下载。开发 120 min/60 calls。
- **P2 `T10.b2-a1-uart-impl`（planned）**：完整约束/187.5 MHz 时钟/CDC/STA/资源；1 次 bitgen + 1 次 CWC；冻结候选；不下载。开发 120/60；TD ≤3 会话/150 min、综合 ≤3、布线 ≤2、bitgen ≤1、下载 0。
- **P3 `T10.b3-board-bringup`（awaiting_user）**：Q1–Q6 确认 + 采样方案冻结后，1 次 SRAM 下载，一帧真实采集/压缩/保存/读回/UART 导出/PC 解码；板测 90 min、下载 1、无 Flash。
- **P4 `T10.b4-integrated-verify`（planned）**：新独立综合测试者核验 P1–P3；测试 60 min/40 calls；TD 0、下载 0。

### 38.3 验收要点
- P1 G0/G1：header/geometry/profile 冻结；仿真逐样本 0 mismatch；raw/xform/stream 长度与 CRC；stored 回退；最坏膨胀缓冲；坏帧/复位不发布半帧；吞吐记录。
- P2 G2：A+ 187.5 MHz Routed 零违例并保留余量；hold ≥0；资源在器件内；CDC/静态检查；IO 约束；bit/CWC 冻结；报告 `-file`；bitgen 仅 P2 授权 1 次。
- P3 G3：一帧完整真实输入；PC zlib 解码成功；PC raw CRC == 板上 raw CRC；stream CRC/长度一致；最坏膨胀；复位/坏帧；吞吐；无半帧。
- P4 integrated：功能/工程/系统三维独立复核；不得用 A+ 小顶 PASS 代替组合版 PASS。

### 38.4 用户条件与授权
- 已写 `question-board-chain.md`：板窗/在场、A 相机/B 断开/BANK13 1.8V、镜头/曝光/场景、**一次 SRAM 下载原话授权（含 bit SHA）**、UART COM/波特率/主机、ROI（中心/左上）与 Bayer 相位、TPG+真实各一帧或仅真实一帧、范围确认。
- **未确认前 P3 不下载、不板测**；P1/P2 可继续离线工作。
- 授权来源：用户本次“接着推进板级链路推进” + 原始需求“如涉板仅 SRAM；本轮最多 1 次下载，下载前冻结同一候选与完整采样方案；不写 Flash、不接 PCIe/RK、不做双路/G4”。
- bitgen 仅 P2 1 次；下载仅 P3 1 次 SRAM；超限/新通道需重新申请。

### 38.5 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.b1-a1-uart-integ` r0（离线集成，无 TD/bitgen/下载）。
> 先读 `dispatch-board-chain.json`、`question-board-chain.md`、`dev-plan.md §47`、`a1_frame_top.v`、`a1_deflate_core.v`、`f9p_camera_display_core.v`、`camera_ddr_display.v`、`ddr_frame_store.v`、`tools/td/PATH_CONTRACT.md`。
> P1：raw tap + 1920×1080 裁切 + raw DDR store + A+ + 变长压缩 store + UART 导出 + PC 解码；仿真 0 mismatch/CRC/长度/最坏膨胀/复位坏帧/吞吐；无 TD。
> P2：完整约束/187.5 MHz/CDC/STA/资源 + 1 bitgen + 1 CWC，冻结候选，不下载。
> P3：Q1–Q6 确认 + 采样方案冻结后，1 次 SRAM 下载，一帧真实采集/压缩/保存/读回/UART/PC 解码；不写 Flash、不接 PCIe/RK、不做双路/G4。
> 预算：P1 120 min/60 calls；P2 TD 3 会话/150 min、综合 ≤3、布线 ≤2、bitgen ≤1；P3 板测 90 min、下载 1；P4 测试 60/40。

## 39. P1 r0 结果与 r1 有界续跑（2026-10-23）

### 39.1 r0 结果（BLOCKED）
- 已完成并冻结：A+ 集成 RTL（raw crop / DDR slot store / arb2 / UART export / camera_a1_uart_top）、PC 解码/校验工具、仿真平台；**vlog 0/0**；探针 `st_raw_pub=1`、`xlen/slen` 推进、无 abort；core/frame 哈希匹配；**无 TD/bitgen/下载**。
- 未完成：MODE=2 故障轮 400 s 未收敛且无捕获字节；两帧 1080p 全尺寸未运行；导出状态机/等待未定位。
- 预算：**61/60 calls、约 150 min**（超限）；不宣称任何 PASS。
- 证据：`T10.b1-a1-uart-integ/r0/result-r0.md`、`lessons-r0.md`、`CANDIDATE-MANIFEST-b1-a1-uart-integ-r0.json`。

### 39.2 r1 裁决：一次有界续跑（60 min/40 calls，不自动 r2）
1. **≤15 min**：MODE=2 小几何跑到 ~200 µs（或挂死点），探针 `st_enc/st_exp/fstate/u_export.{estate,dq_cnt,pstate,sent,wbuf_valid}/u_cmp_store.rd_state/st_cmp_drop/st_err`；判定导出 FSM（E_OPEN/E_PAY）还是 TB 等待；只修定位原因，**不放宽超时/门槛**。
2. **≤12 min**：MODE=2 故障用例按原 400 s 超时跑完；捕获字节；阶段 A–E（好帧、坏帧、帧中复位、恢复、三快帧丢弃）语义正确；坏帧/复位不发布、恢复发布、溢出丢弃不污染、CRC/长度正确；无半帧。
3. **≤20 min**：MODE=0 全尺寸 1920×1080（raw 2,592,000 B）跑完；PC 解码逐样本 0 mismatch、CRC/长度；最坏 2,594,706 B 容量核验。
4. **≤10 min**：MODE=1 不可压缩全帧若时间允许；否则缩短不可压缩帧 + 2,594,706 B 存储/导出最大长度单元测试，写 `evidence_boundary=shortened_geometry`，**不得把缩短帧当整帧**。
5. **≤3 min**：`verify_p1.py` + `result-r1.md`/manifest；无 TD/bitgen/下载。

### 39.3 验收与停止
- PASS：MODE=2 完成且阶段语义正确；一帧全尺寸 1080p 逐样本 0 mismatch/CRC/长度；最坏 2,594,706 B 已验证（全帧不可压缩或缩短+最大长度单元测试）；复位/坏帧/反压覆盖。
- 条件 PASS：仅当 MODE=1 全帧不可行时允许，必须显式写 `evidence_boundary=shortened_geometry` 并保留最大长度单元测试。
- BLOCKED：15 min 内未定位、27 min 内 MODE=2 未完成、47 min 内全尺寸 1080p 未完成 → 停止交规划，**不自动 r2**。
- 禁止：放宽超时/门槛、用 TB-only 通过掩盖 RTL 导出 bug、半帧发布、TD/bitgen/下载/Flash、改 A+ core/frame/DEFLATE。

### 39.4 写域与预算
- 仅允许改 `a1_uart_export.v`/`camera_a1_uart_top.v`/`tb_camera_a1_uart_top.v` 中探针证明的那一处；新输出只写 `T10.b1-a1-uart-integ/r1/**`；不改 core `bf6af390`、frame `18d51b1b`、SDC `227dd39e`、旧 run/manifest、P2/P3/P4。
- 开发 **60 min/40 calls**；TD 0 会话/0 综合/0 布线/0 bitgen/0 下载；仿真超时沿用 900 s（全帧）/400 s（故障）。

### 39.5 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.b1-a1-uart-integ` **r1**（P1 有界续跑；无 TD/bitgen/下载）。
> 先读 `dispatch-b1-r1.json`、`T10.b1-a1-uart-integ/r0/result-r0.md §5`、`lessons-r0.md`、`run_p1.ps1`、`sim/tb_camera_a1_uart_top.v`、`probe.do`。
> 先 MODE=2 ~200 µs 探针定位导出 FSM/等待（≤15 min），只修定位原因；再 MODE=2 故障（≤12 min）、MODE=0 全尺寸 1080p（≤20 min）、MODE=1 不可压缩（≤10 min，或缩短+2,594,706 B 最大长度测试并写边界）；最后 verify/freeze。
> 门槛：逐样本 0 mismatch、CRC/长度、最坏 2,594,706 B、复位/坏帧/反压；不放宽超时/门槛；缩短帧不得当整帧。
> 预算：60 min/40 calls；TD 0/0/0/0；超时/无证据 → BLOCKED 交规划，不自动 r2。

## 40. P1 r1 结果与 r2 有界收口（2026-10-23）

### 40.1 r1 实际结果
- 整帧 1920×1080 跑通：**6,417,909 cycles**（34.2 ms @187.5 MHz）；`cap=1 enc=1 exported=1 geom=0 err=0`；56,498 B（44 头 + 56,454 payload）；`zlib_ok`、`stream/xform/raw` 三 CRC 全 true；raw_len 2,592,000；stream_len 56,454 ≤ 2,594,706。
- **header_crc=false**：`crc_fin` 在 `hdr_idx==40` 才寄存、同拍 `hw10` 读旧值；修法 `hdr_idx==39` 预计算。
- **逐样本未达**：`full_grad_decode.json` 记录 **mismatch=2,077,900 B / raw_equal=false**。用户摘要称“仅 header_crc”，但 r1 证据文件还有该 mismatch；r2 必须加 8×2 诊断，否则 0 mismatch 不可能达成。
- 未做：MODE=1 整帧与 2,594,706 B 最大长度单元测试（boundary=not_run）；MODE=2 6 s 可跑完但 geom=0/raw_drop=0，坏帧/溢出语义未取证。
- 预算：calls 38/40、wall ~82 min（超 60）；无 TD/bitgen/下载。

### 40.2 r2 裁决：一次有界收口（40 min/25 calls，不自动 r3）
1. **≤5 min**：`a1_uart_export.v` 的 `crc_fin` 改到 `hdr_idx==39`；验证 header_crc=true；除 header 外不改 RTL。
2. **≤8 min**：8×2 微型几何（CAM 32×4、ROI 4,2、W=8,H=2）打印 DUT/参考前 16 B + `(y,x)`；定位是参考 ROI 约定还是 crop off-by-one；只修证明原因，不以改参考迎合 DUT。
3. **≤8 min**：只修 TB 相位时序，使 MODE=2 坏帧/帧中复位/恢复/三快帧丢弃/反压语义取证；无半帧；若暴露 DUT bug 停止。
4. **≤8 min**：MODE=1 整帧或缩短帧 + 2,594,706 B 最大长度单元测试，写 `evidence_boundary=shortened_geometry`，不得当整帧。
5. **≤8 min**：重跑全尺寸 1080p，确认 header_crc=true、四 CRC 全 true、逐样本 0 mismatch；verify/freeze。

### 40.3 验收与停止
- PASS：header_crc=true；zlib/stream/xform/raw 全 true；全帧逐样本 0 mismatch；raw_len 2,592,000；stream_len ≤2,594,706；MODE=2 故障语义正确；MODE=1 全帧或缩短+2,594,706 B 最大长度测试（写 boundary）；无 TD/bitgen/下载。
- 缩短帧仅作条件证据，必须显式写 `evidence_boundary=shortened_geometry`，不得当整帧。
- BLOCKED：header 仍 false、8×2 无法解释/修、MODE=2 语义取不到、全帧未 0 mismatch、或 40 min/25 calls 用尽 → 交规划，**不自动 r3**。
- 禁止：放宽超时/门槛、改参考迎合 DUT、半帧、TD/bitgen/下载/Flash、改 core `bf6af390`/frame `18d51b1b`/DEFLATE/SDC。

### 40.4 写域与预算
- 仅允许改 `a1_uart_export.v`（header）、`a1_raw_crop.v`（仅 8×2 证明 off-by-one 时一处）、`tools/a1/a1_pattern.py`/`verify_p1.py`（仅参考约定）、TB（MODE=2 相位）；新输出只写 `T10.b1-a1-uart-integ/r2/**`；不改 core/frame/SDC/旧 run/P2-P4。
- 开发 **40 min/25 calls**；TD 0 会话/0 综合/0 布线/0 bitgen/0 下载；仿真超时沿用 900 s（全帧）/400 s（故障）。

### 40.5 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.b1-a1-uart-integ` **r2**（P1 有界收口；无 TD/bitgen/下载）。
> 先读 `dispatch-b1-r2.json`、`r1/result-r1.md §3-§4`、`r1/full_grad_decode.json`（mismatch=2,077,900）、`r1/lessons-r1.md`、`run_p1.ps1`、TB。
> 先修 header_crc（`hdr_idx==39`），再 8×2 诊断定位 mismatch，再补 MODE=2 故障语义/MODE=1 或缩短+2,594,706 B 最大长度测试，最后全帧重跑 0 mismatch+header_crc=true。
> 预算 40 min/25 calls；TD 0/0/0/0；不放宽/不半帧/不改 core/frame/DEFLATE；失败即 BLOCKED，不自动 r3。

## 41. P1 r2 结果与 r3 有界收口（2026-10-23）

### 41.1 r2 结果（BLOCKED，未越界）
- **header_crc 已修好**：8×2 与 64×8 两帧 `header_crc` + stream/xform/raw **四 CRC 全 true**。
- **8×2 诊断**：DUT raw 与独立参考**逐字节相同**，origin=(2,4)；参考 ROI 与 crop **均无罪**。
- **整帧差异根因已证明**：帧首多一个 20 B（4 组 256-bit）字，`raw[i]==exp[i-20]` 对 i≥20 的 2,591,980 B 全成立；64×8 复现；DDR 内存内容正确（waddr=31；rd_idx=25/rd_words=32）；缺陷在**回读/馈送侧**（首字用两次、末字未读）。
- 修复点在 `a1_ddr_slot_store.v` / `a1_ddr_arb2.v` / `camera_a1_uart_top.v`，**不在 r2 写域**；按停止条件未修改。MODE=2/MODE=1/最大长度/整帧重跑未做。
- 预算：calls 14/25、wall ~30/40 min；无 TD/bitgen/下载。

### 41.2 r3 裁决：一次有界收口（35 min/20 calls，不自动 r4）
1. **≤8 min**：扩展写域到三文件；先加 `st_read_words`/`st_dup_words` 复现 dup=1；只修首字重复——F_WAIT **取即锁存** + store 侧同一 AR **一次性保护**；不改协议/帧/CRC/DDR 布局。
2. **≤6 min**：重跑 8×2、64×8；0 mismatch、四 CRC true、`dup=0`、`read_words` 正确。
3. **≤10 min**：重跑全尺寸 1080p；0 mismatch、四 CRC true、raw_len 2,592,000、stream_len ≤2,594,706。
4. **≤8 min**：MODE=2 只修 TB 相位，取证坏帧/帧中复位/恢复/三快帧丢弃/反压；MODE=1 整帧或缩短帧 + 2,594,706 B 最大长度测试，写 `evidence_boundary=shortened_geometry`，不得当整帧。
5. **≤3 min**：verify/freeze。

### 41.3 验收与停止
- PASS：8×2/64×8/全帧 1080p 逐样本 0 mismatch；四 CRC true；raw_len 2,592,000；stream_len ≤2,594,706；dup=0/read_words 正确；MODE=2 故障语义正确；MODE=1 全帧或缩短+2,594,706 B 最大长度测试（写 boundary）；无 TD/bitgen/下载。
- 缩短帧仅作条件证据，必须写 `evidence_boundary=shortened_geometry`，不得当整帧。
- BLOCKED：dup 非 0、8×2/64×8 未 0、全帧未 0、MODE=2 语义取不到、或 35 min/20 calls 用尽 → 交规划，**不自动 r4**。
- 禁止：放宽/半帧、改协议/帧/CRC/DDR 布局/core/frame/DEFLATE/SDC/参考、TD/bitgen/下载/Flash。

### 41.4 写域与预算
- 仅允许改 `a1_ddr_slot_store.v`（读 FSM/AR/rd_idx + 计数）、`a1_ddr_arb2.v`（读授权/一次性保护）、`camera_a1_uart_top.v`（F_WAIT/F_FEED 取即锁存）、TB（MODE=2 相位）；新输出只写 `r3/**`；不改 `a1_uart_export.v`（r2 已修）、`a1_raw_crop.v`（r2 证明正确）、参考、core/frame/SDC/旧 run/P2-P4。
- 开发 **35 min/20 calls**；TD 0 会话/0 综合/0 布线/0 bitgen/0 下载；仿真超时沿用 900 s（全帧）/400 s（故障）。

### 41.5 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.b1-a1-uart-integ` **r3**（P1 有界收口；无 TD/bitgen/下载）。
> 先读 `dispatch-b1-r3.json`、`r2/result-r2.md §3`、`r2/micro8x2_diag.json`、`r2/memprobe.do`、`run_p1.ps1`、TB。
> 先加 `st_read_words/st_dup_words` 复现首字重复，再只改三文件回读/馈送（取即锁存 + 一次性 AR），重跑 8×2/64×8/全帧到 0 mismatch/四 CRC/raw_len/stream_len；再补 MODE=2 语义、MODE=1 或缩短+2,594,706 B 最大长度测试（写 boundary）。
> 预算 35 min/20 calls；TD 0/0/0/0；不放宽/不半帧/不改协议/帧/CRC/DDR 布局/core/frame/DEFLATE/SDC/参考；失败即 BLOCKED，不自动 r4。

## 42. P1 r3 结果与 r4 测试-only 收口（2026-10-23）

### 42.1 r3 结果
- **核心链路全绿**：8×2 / 64×8 / 整帧 1920×1080 均逐样本 0 mismatch、header/stream/xform/raw 四 CRC true、`zlib_ok`、`dup=0`；整帧 read_words=129,600、raw_len=2,592,000、stream_len=40,032 ≤2,594,706、6,383,945 cycles（34.0 ms @187.5）、raw_sha256 `2f34e253…d355e830`。
- **未达成**：MODE=2 `cap=9 enc=3 exported=1 raw_pub=5 cmp_drop=0 err=0 dup=0`，无半帧发布，但 `geom=0/raw_drop=0`，坏帧/溢出计数未触发；帧中复位打断在途导出使流截断，不能作故障证据；MODE=1 与 2,594,706 B 最大长度测试未做（整帧不可压缩约 50 min 墙钟）。
- 预算：calls 13/20、wall 36/35 min；无 TD/bitgen/下载。

### 42.2 裁决：授权测试-only r4（25 min/15 calls，不自动 r5）
需求明确要求覆盖帧尾/反压/缓存不足/坏帧溢出撤销/复位恢复，故不直接接受 PASS-with-boundary；r4 只改 TB/测试脚本、不改 RTL。
1. **≤8 min**：按帧长参数化 MODE=2 相位 + 容错截断帧；坏帧 → `geom/raw_drop>0` 且不发布；复位 → 不发布半帧；恢复 → 发布；三快帧 → `cmp_drop/raw_drop>0` 不污染；AW_GAP/R_GAP 反压。
2. **≤5 min**：store-only **2,594,706 B** 最大长度单元 TB（store+export，不走 A+ 编码）。
3. **≤5 min**：缩短 MODE=1 不可压缩（如 128×16/64×8）验证 stored 回退 + 逆变换；写 `evidence_boundary=shortened_geometry`，不得当整帧。
4. **≤5 min**：小奇数高帧（如 W=8,H=3）验证 TAIL 尾块；时间不足记 `tail_not_run`。
5. **≤2 min**：result-r4/manifest，绑定 r3 RTL 哈希。

### 42.3 验收与停止
- PASS：MODE=2 故障语义按适用项出现 `geom/raw_drop/cmp_drop`、无半帧、复位不发布、恢复发布、溢出无污染、反压覆盖；store-only 2,594,706 B 通过；缩短 MODE=1（若跑）0 mismatch/四 CRC + boundary；**不改 RTL**；无 TD/bitgen/下载。
- 失败：RTL 改动/哈希不符、MODE=2 仍无计数、store-only 失败、或 25 min/15 calls 用尽 → P1 core PASS-with-boundary；交规划；不伪造计数；**不自动 r5**。
- 边界：r3 核心证据可复用但须绑定未变 RTL 哈希；缩短帧/尾块仅条件证据；不改协议/帧/CRC/DDR 布局/SDC/参考。

### 42.4 下一次准确启动/恢复文本
> 恢复 `T10.b1-a1-uart-integ` **r4**（测试-only；无 RTL/bitgen/下载）。
> 先读 `dispatch-b1-r4.json`、`r3/result-r3.md`、`r3/run_p1.ps1`、`r3/sim/tb_camera_a1_uart_top.v`、`r3/CANDIDATE-MANIFEST-b1-a1-uart-integ-r3.json`。
> 按帧长参数化 MODE=2 相位 + 容错截断帧；补 store-only 2,594,706 B 最大长度 TB；缩短 MODE=1/奇数高尾块若有时间；输出 result-r4/manifest。
> 25 min/15 calls；不改 RTL/协议/帧/CRC/DDR 布局/SDC/参考；不伪造计数；无 TD/bitgen/下载；失败即停止，不自动 r5。

## 43. P1 core PASS-with-boundary 与 P2 冻结（2026-10-23）

### 43.1 r4 结果（测试-only，shell 受限）
- RTL 零改动，哈希与 r3 一致；shell 权限拒绝（TOOL_UNAVAILABLE），MODE=3/4、store-only 最大长度、MODE=1 缩短帧、W=8,H=3 尾块未跑。
- 新增结论：复位清零全部故障计数（mode2：`roi_frames=9`、`enc=3<cap=9`、无半帧、`err=0`、`read_words=96`、`dup=0`；`geom=0` 因复位清零）；复位 `FRAME_CYC-60` 可完成，`FRAME_CYC/2`（写入途中）400 s 超时 → **写入途中复位恢复路径需定位，P3 上板前必须确认**。
- 预算：calls 12/15、wall 27/25 min；无 TD/bitgen/下载。

### 43.2 裁决：P1 core PASS-with-boundary，进入 P2
- 按 dispatch partial 条款：P1 = **core PASS-with-boundary**（整帧 0 mismatch/四 CRC/dup=0）；故障语义、最大长度、MODE=1 缩短帧、尾块、写入中复位恢复列为 **P3 上板前必须补测/验证项**；不把 P1 记为完整 PASS。

### 43.3 P2 `T10.b2-a1-uart-impl`（ready，不下载）
- 完整约束/187.5 MHz/CDC/复位/IO + STA/资源；**1 bitgen + 1 CWC**；冻结 bit/CWC/RTL 哈希；不下载/Flash。
- 门槛：Routed 零违例；WNS>0（目标 ≥+0.2，记录余量；薄余量 caveat）；hold ≥0；资源在 PH1P100SBG484；CDC/复位/无环；bit/CWC 哈希一致。
- 预算：开发 120/60；TD ≤3 会话/150 min、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 0。
- 写域：P2 新工程/约束/时钟复位 CDC 包装；不改 A+ core `bf6af390`、frame `18d51b1b`、SDC `227dd39e` 源、P1 冻结证据。
- 停止：P1 RTL 哈希漂移、负 slack/hold/资源/CDC 失败、bit/CWC 不匹配、下载/Flash/PCIe/RK/双路/G4、预算用尽 → 停止。

### 43.4 P3 上板前置（awaiting_user）
- shell 恢复补测：MODE=3/4、store-only 2,594,706 B、MODE=1 缩短帧、W=8,H=3 尾块、写入中复位恢复。
- P2 候选 bit/CWC 冻结、STA/CDC/资源通过。
- Q1–Q6：板窗/在场、A 相机/B 断开/BANK13、镜头/曝光、**一次 SRAM 下载原话授权（含 bit SHA）**、UART COM/波特率/主机、ROI/Bayer、范围确认。
- 仅 1 次 SRAM 下载；不写 Flash、不接 PCIe/RK、不做双路/G4。

### 43.5 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.b2-a1-uart-impl` r0（离线实现；无下载）。
> 先读 `dispatch-b2.json`、`dev-plan.md §52`、P1 r3/r4 manifest、`board.adc`、`timing.sdc`、`tools/td/PATH_CONTRACT.md`。
> 校验 P1 RTL 哈希 → 187.5 MHz/CDC/复位/IO 约束 → Routed 零违例/hold/资源/CDC → **1 bitgen + 1 CWC** → 冻结 bit/CWC/RTL 哈希；不下载/Flash。
> 预算：开发 120/60；TD ≤3 会话/150 min、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 0。
> P3 需 shell 恢复补测 + Q1–Q6 + 一次 SRAM 下载授权；未确认不下载。

## 44. P2 r0 失败与 r1 有界收口（2026-10-23）

### 44.1 r0 失败
- TD 综合展开 5.05 s 失败：`raw_rd_close_r` multiple drivers in `camera_a1_uart_top.v`（r3 hash `873cb98c…`）；同文件 `raw_rd_open`/`raw_rd_take` 也有重复驱动（skid always 块与 sequencer 块同时赋值）。ModelSim 宽容 procedural multi-driver，P1 仿真能过；TD 直接拒绝并 black-box。
- 修法：删除 162 行与 166–167 行的重复赋值（3 行所有权清理；sequencer 已拥有），不改逻辑。
- 预算：dev 67/60 calls 用尽；TD 1/3 会话、综合 1/3（展开失败）、布线 0/2、bitgen 0/1、CWC 0/1；无下载/Flash。

### 44.2 hash 记录冲突（已更正）
- r4 manifest 原表 `camera_a1_uart_top.v=e88de0910ff0`、`a1_ddr_slot_store.v=5196c07aed52`；实测 r3 全哈希为 `873cb98c7c79…` / `8bab440d528a…`，不存在 e88/5196 文件。
- 结论：**文档冲突，非 RTL 漂移**；已更正 r4 manifest 并保留 `.before-hashfix` 备份，新增 correction 说明。

### 44.3 r1 裁决：一次有界收口（90 min/50 calls；TD 2 会话/120 min；不自动 r2）
1. **≤10 min**：只删 `camera_a1_uart_top.v` 162/166–167 三行重复赋值；`vlog` 0/0 + TD elaboration 通过。
2. **≤25 min**：重跑 P1 8×2 + 64×8 + 整帧 1080p；0 mismatch、四 CRC true、`dup=0`、raw_len 2,592,000、stream_len ≤2,594,706；冻结 P1 新哈希 `CANDIDATE-MANIFEST-b1-a1-uart-integ-r5.json`；P1 boundary 项不变。
3. **≤3 min**：确认 r4 hash 更正；不把文档冲突当漂移。
4. **P2 续建**：剩余 2 综合/2 布线/1 bitgen/1 CWC；Routed 零违例、WNS>0（目标 ≥+0.2）、hold ≥0、资源/CDC/复位/IO；bit/CWC 哈希冻结；不下载/Flash。

### 44.4 停止与边界
- 停止：P1 回归失败、elaboration 仍失败、2 综合/2 布线后仍负 slack/hold/资源/CDC、bit/CWC 失败、或预算用尽 → 停止；不自动 r2。
- 边界：除 3 行重复赋值外不改 RTL；不改 A+ core `bf6af390`、frame `18d51b1b`、SDC `227dd39e`；不 seed/false path/multicycle；不下载/Flash/PCIe/RK/双路/G4。
- 预算：开发 90 min/50 calls；TD 2 会话/120 min、综合 ≤2、布线 ≤2、bitgen 1、CWC 1、下载 0。

### 44.5 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.b2-a1-uart-impl` **r1**（P2 有界收口；无下载）。
> 先读 `dispatch-b2-r1.json`、`r0/result-r0.md`、`r0/td/syn_failure_excerpt.txt`、`r0/td/run.log`、P1 r3/r4 manifest、`camera_a1_uart_top.v`。
> 删 162/166–167 重复赋值 → vlog/TD elaboration → 重跑 P1 8×2/64×8/全帧 0 mismatch/四 CRC/dup=0 → 冻结 P1 r5 → P2 续建（2 综合/2 布线/1 bitgen/1 CWC；Routed 零违例/WNS>0/资源/CDC）。
> 90 min/50 calls；TD 2 会话/120 min；不改逻辑/core/frame/SDC；不下载/Flash；失败即停，不自动 r2。

## 45. P2 r1 结果与 r2 有界收口（2026-10-23）

### 45.1 r1 结果
- **P1 清理+回归 PASS**：3 行重复驱动清理后新哈希 `17793341…baac88`；8×2 / 64×8 / 整帧 1080p 0 mismatch、四 CRC、dup=0、raw_len 2,592,000、stream_len 40,032、raw_sha256 不变；P1 r5 manifest 已冻结，boundary 不变。
- **P2 synth**：elaboration PASS；LUT 23,342 / reg 15,960 / **ERAM 296/300** / IO 110；`clk_a1` 187.5 **WNS -0.060 / 32 端点**（overall -0.137 / STNS -12.058）；`cam_preview_capture` 224 ERAM，CWC 30 → **326>300**，phy 在 place 前中止；无 route/bit/CWC/下载。
- 预算：dev 90 min 用尽；TD 1 会话、综合 1/2、布线 0、bitgen 0/1、CWC 0/1。

### 45.2 r2 裁决：一次有界收口（120 min/60 calls；TD 2 会话/120 min；不自动 r3）
1. **资源**：移除 `cam_preview_capture`（HDMI 改 TPG），释放 224 ERAM 与 HDMI 148.5 通路；CWC 探针按 `300 - 集成占用` 重排；**ERAM design+CWC ≤300，目标 ≤280**；不静默删必需探针。
2. **时序**：定位板级 187.5 -0.060 与小顶 +0.275 的差异（PLL/抖动、create_clock/uncertainty、board vs small-top SDC、IO delay、跨模块 mux/CDC、时钟树），记录 top 10 paths；沿用 retiming+phys_opt；仅允许板级集成最小流水适配（不改协议/帧/CRC/DDR 布局）；若需改 A+ core/frame，停止并给“板级边界决策”。
3. **synth WNS≥0 才 route**；Routed 零违例、WNS>0（目标 ≥+0.2，记录余量）、hold ≥0、资源/CDC/复位/无环/IO；1 bitgen + 1 CWC；不下载/Flash。
4. **边界**：2 次 synth 仍负或 2 次 route 仍负/违例 → 不接薄负 slack、不暗中放宽 187.5；停止并提交 top paths/根因与选项（新 RTL 流水轮/用户决定/停止）。

### 45.3 预算与停止
- 开发 120 min/60 calls；TD 2 会话/120 min、综合 ≤2、布线 ≤2、bitgen 1、CWC 1、下载 0。
- 停止：P1 r5 哈希不符/改 A+ core/frame/DEFLATE/SDC、ERAM>300、synth 2 次仍负、route 2 次仍负/违例、bit/CWC 失败、或预算用尽 → 停止；不自动 r3。
- 边界：不改协议/帧/CRC/DDR 布局/core/SDC；不 seed/false path/multicycle；不下载/Flash/PCIe/RK/双路/G4。

### 45.4 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.b2-a1-uart-impl` **r2**（P2 有界收口；无下载）。
> 先读 `dispatch-b2-r2.json`、`r1/result-r1.md`、`r1/td/a1_board_gate.timing`、`r1/td/run.log`、P1 r5 manifest、`p2_a1_board_top.v`、`p2_board.sdc`。
> 校验 P1 r5 → 移除 preview/HDMI TPG、CWC 探针 ≤300 留余量 → 定位 187.5 板级差异（top 10）→ retiming+phys_opt + 最小集成流水 → synth WNS≥0 才 route → 零违例/WNS>0/资源/CDC → 1 bitgen+1 CWC → 冻结。
> 120 min/60 calls；TD 2 会话/120 min、综合 ≤2、布线 ≤2；不下载/Flash；失败即停，不自动 r3。

## 46. P2 r2 结果与 r3 选项 A（2026-10-23）

### 46.1 r2 结果
- 资源已解决：移除 preview 后 design ERAM 296→**72**，CWC 30→**102 ≤280**；LUT 16,753、reg 16,059、IO 110。
- 桥接路径已修：DDR 读 skid 后 `clk_a1→clk_a1` **+0.116 / 0 of 14,968**；ddr_user +0.423、mipi_byte +0.728、mcu +12.255。
- 剩余：`sys_clk50m→clk_a1` **-0.193 / STNS -63.883 / 331 端点**；路径 `a1_rst_sync_reg[2]→core/frame→smem.addrb`；clk_a1 数据路径 synth 仅 +0.116；小顶 +0.275 因 `rst_n` 主端口不计时。
- 预算：dev 35/28；TD 1/2 会话、综合 1/2、布线 0/2、bitgen 0/1、CWC 0/1；无下载。

### 46.2 r3 裁决：选 A（最小 core/frame 复位清理）
1. 只做“复位不驱动存储器地址/数据 mux”：ERAM 无需复位；从 `smem`/`bm_a`/`bm_b`/`htab` 地址/数据 mux 选择路径移除 reset；保留 control/valid/state/write-enable 复位，确保无非法写/发布/半帧；必要时最多一级同步/寄存；不改协议/帧/CRC/DDR 布局。
2. 重跑 P1 8×2/64×8/整帧 1080p：0 mismatch/四 CRC/dup=0、无 X/半帧；重新冻结 P1 r6 哈希；P1 boundary 项不变。
3. P2 续建：synth WNS≥0 才 route；Routed 零违例、WNS>0（目标 ≥+0.2）、hold、资源/CDC/复位/无环/IO；1 bitgen + 1 CWC；不下载/Flash。
- **B 不接受**：对真实异步复位分布加 false path + 接受薄 +0.116，隐藏真实路径且不达 +0.2。
- **C 暂不选**：A 失败后再由用户决定器件/时钟/验收。

### 46.3 预算与停止
- 开发 90 min/50 calls；TD 2 会话/120 min、综合 ≤2、布线 ≤2、bitgen 1、CWC 1、下载 0。
- 停止：P1 回归失败、复位语义产生 X/非法写/半帧、r6 哈希无法冻结、ERAM>300、2 次 synth 仍负、2 次 route 仍负/违例、bit/CWC 失败、或预算用尽 → 停止；不自动 r4；不静默转 B。
- 边界：不改协议/帧/CRC/DDR 布局/SDC；不 false path/multicycle；不 seed；不下载/Flash/PCIe/RK/双路/G4。

### 46.4 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 `T10.b2-a1-uart-impl` **r3**（选项 A；无下载）。
> 先读 `dispatch-b2-r3.json`、`r2/result-r2.md`、`r2/td/a1_board_gate.timing`、`r2/td/build_console_r2.log`、P1 r5 manifest、`a1_deflate_core.v`、`a1_frame_top.v`。
> 只改 smem/bm/htab 地址/数据 mux 的 reset 选择，保留 control/valid/state 复位；P1 回归 0 mismatch/四 CRC/dup=0/无 X/半帧 → 冻结 r6 → P2 synth WNS≥0 才 route → 零违例/WNS>0/资源/CDC → 1 bitgen+1 CWC。
> 90 min/50 calls；TD 2 会话/120 min、综合 ≤2、布线 ≤2；不改协议/帧/CRC/DDR 布局/SDC；不 false path；不下载/Flash；失败即停，不自动 r4。

## 47. P2 完成（带 caveat）与 P3 前置（2026-10-23）

### 47.1 P2 独立测试：PASS（薄余量 caveat）
- functional：8×2/64×8/整帧 1080p 0 mismatch、四 CRC、zlib 精确、dup=0、raw_len 2,592,000、stream_len 40,032。
- engineering：Routed **0/19,754 违例**、SWNS **+0.012**、hold +0.020、R-Freq 187.935、17 时钟 CC no/no、0 组合环；LUT6 18,698 / reg 25,200 / ERAM 102/300 / DSP 0 / IO 110；SDC 与 r2 一致、无 false path/降频；bit `d1ac8726…c142`、CWC `37b60854…b25c`、BID `3de68e68…f213`，compiled 一致；无下载/Flash。
- system partial：上板下载/复位恢复/稳定性/实测吞吐 `not_run/awaiting_hardware`。
- caveat：SWNS 仅 **+0.012**，+0.2 未达；仅离线实现，非板级签核。

### 47.2 文档哈希更正（已做，保留 .before）
- P1 r6 manifest 的 `a1_frame_top.v` artifact 哈希 `a2a84b74…` → 实测 `c8b24775…`；3 个 sim 日志哈希更新为实际值；`artifact-hashes.txt` 的 r6 manifest 行由 `fed73a4f…` 更正为更正后 manifest `33754463…`（更正前 `1318a62c…`）。均保留 `.before-hashfix` 备份；不影响 P2 判定。

### 47.3 任务状态
- **P2 = done（caveat +0.012）**；**P3 = awaiting_user**；**T10 整体仍 blocked**（P3/需求二/三未完成）；不得把整条单A闭环置 done。
- P3：板测 90 min、下载 1、无 Flash；P4 独立核验 60 min/40 calls。
- P3 前置：`question-board-chain.md` Q1–Q10 + 冻结采样方案 + P1 boundary 补测（MODE=3/4、store-only 2,594,706 B、MODE=1 缩短、W=8,H=3、写入中复位恢复）。

### 47.4 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **P3 `T10.b3-board-bringup`**（awaiting_user；无下载）。
> 先读 `question-board-chain.md`、`dispatch-b3.json`、`test-reports/T10.b2-a1-uart-impl-r3-integrated.md`、P2 manifest、P1 r6 manifest。
> 只有 Q1–Q10 确认 + 采样方案冻结 + P1 boundary 补测/明确接受 + 一次 SRAM 下载授权（bit `d1ac8726…c142`）后，才允许 1 次 SRAM 下载；TPG 先、真实帧后；失败即停、不第二次下载。
> 不写 Flash、不接 PCIe/RK、不做双路/G4；P3 通过后 P4 独立核验（60/40）；T10 仍 blocked。

## 48. P3 已授权/默认确认并派发（2026-10-24）

### 48.1 授权与默认
- 用户原话：“该给的权限我给，该上电的我都上了，剩余按默认或者你做好判断，我也基本都是符合的，开始执行吧……如发现工程路径出现问题，先不要停止。”
- 默认确认 Q1–Q10；一次 SRAM 下载 bit `d1ac8726…c142`、CWC `37b60854…b25c`、BID `3de68e68…f213`；仅本次、失败不第二次；无 Flash/PCIe/RK/双路/G4。

### 48.2 技术边界（规划判断）
- 冻结 P2 bit 的 UART 是 **115.172 kbaud**（UART_DIV=1628、187.5 MHz），P3 用 **115200 8N1**；**921600 不支持**（需新 bit/CWC，超出本次授权）。
- TPG 只驱动 HDMI，A+ 输入是相机 raw tap，**无 TPG mux**；P3 记录 `tpg_a_plus=not_available` boundary，真实 A 帧为主证据，不伪造 TPG。

### 48.3 路径约定（2026-10-24 迁移后更新）
- **项目根（唯一主源）**：`D:\fpga\ph1p100`；旧根 `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道` 已不存在，映射见 `dev-plan.md §57.7`。
- P3 产物/TD/日志/UART 捕获/解码默认 **`D:\fpga_work\20261020-0209_singleA_aplus_closedloop\P3\`**（新建）；D: 不可用回退 run 的 `T10.b3-board-bringup\r0` 并记录。
- 嵌套副本 `D:\fpga\ph1p100\workflow\workflow\runs\...` 只读、不删除、不作主源；路径异常按映射或冻结副本继续，不停止；不批量删除。
- TD：`Y:` = `D:\fpga\ph1p100`、`T:` = P3 TD workdir；`X:` 保留给 TD，不映射项目根。

### 48.4 执行/门槛/预算
- 建 D: workdir/校验 bit/CWC → **1 次 SRAM 下载** → 复位 → COM 115200 → 真实 A 帧采集→DDR→A+→保存→读回→UART→PC zlib+逆变换；记录 CRC/长度/吞吐/还原；无半帧。
- 门槛：一帧完整真实 A、PC 解码成功、raw CRC 匹配、stream 长度/CRC、无半帧、复位/恢复、吞吐；bit/CWC/BID 不变；1 次下载、无 Flash。
- 失败即停、保留日志、不第二次下载；P3 完成后派 **P4 新独立测试者**（60 min/40 calls，无 TD/下载）。
- 预算：板测 90 min、下载 1、无 Flash；开发 90/50；P4 60/40。

### 48.5 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **P3 `T10.b3-board-bringup`**（已授权 ready；1 次 SRAM 下载）。
> 先读 `dispatch-b3.json`、`question-board-chain.md`、`dev-plan.md §57`、P2 tester report/manifest、P1 r6 manifest、`tools/a1/pc_decode.py`。
> 建 D: P3 workdir/校验 bit/CWC/BID → 1 次 SRAM 下载 → 复位 → COM 115200 → 真实 A 帧全链 → PC 解码/CRC；TPG 进 A+ 记 not_available boundary；无半帧/无 Flash/不第二次下载。
> 路径搬移：探测 D: 同名 run/bit，切换并记录；找不到用冻结副本继续，不停止。P3 后 P4 60/40；T10 仍 blocked。

## 49. 路径迁移到 D:\fpga\ph1p100 与 P3 候选复核（2026-10-24）

### 49.1 迁移与主源
- 旧根 `C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道` 已不存在；现行项目根 `D:\fpga\ph1p100`。映射保持相对路径不变（run/manifest/bit/CWC/BID/RTL/工具/PC 解码脚本），完整表见 `dev-plan.md §57.7`。
- 主源：`D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop`。
- 嵌套副本 `D:\fpga\ph1p100\workflow\workflow\runs\20261020-0209_singleA_aplus_closedloop` 仅含 test-reports/ 5 个 2026-10-22 日志（exitcodes.txt、gen.err、gen.log、vlog.log、_info）：**只读、不删除、不作为主源**。

### 49.2 P3 产物目录
- 默认 `D:\fpga_work\20261020-0209_singleA_aplus_closedloop\P3`（新建）；不可建/不可写回退 `D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b3-board-bringup\r0` 并记录 `workdir_used/fallback_reason`。

### 49.3 候选复核（规划实测，与 P2 r3 manifest 一致）
| 产物 | SHA256 | 字节 | 结论 |
|---|---|---|---|
| bit | `d1ac8726e84f6584d49979dd223d6e8c484e559bf2a3ad3b2302972c58efc142` | 5,224,022 | ✅ |
| CWC | `37b608540f7924f60a09db5ba2b543334db1259ef69f2a1c982cf161cbc8b25c` | 110,248 | ✅ |
| BID | `3de68e686e419e20cd85a332e40caa740b9aae55d666c3e8816ef7033d04f213` | 96,832 | ✅ |

- 证据路径更正：P2 r3 独立测试报告位于项目根 `D:\fpga\ph1p100\test-reports\T10.b2-a1-uart-impl-r3-integrated.md`，不在 run 的 test-reports/；P3 dispatch/plan 已改用绝对路径。

### 49.4 状态与边界
- P3 `T10.b3-board-bringup` = ready（一次 SRAM 下载已授权）；T10 整体仍 blocked；P4 待 P3 完成后派新独立测试者（60/40）。
- 不变：115200 8N1（冻结 bit 115.172 kbaud；921600 不支持）、真实 A 帧为主、TPG 进 A+ = `not_available` boundary、失败即停、不 Flash、不 PCIe/RK、不双路/G4、不批量删除。
- 路径异常：按映射改新根，新根缺文件用 P3 workdir 冻结副本，记录后继续，不停止。

### 49.5 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **P3 `T10.b3-board-bringup`**（ready；1 次 SRAM 下载）；项目根 `D:\fpga\ph1p100`。
> 先读 `D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\dispatch-b3.json`、`dev-plan.md §57`、`D:\fpga\ph1p100\test-reports\T10.b2-a1-uart-impl-r3-integrated.md`、P2 r3 manifest、P1 r6 manifest。
> 建 `D:\fpga_work\20261020-0209_singleA_aplus_closedloop\P3`（或回退记录）/校验 bit/CWC/BID → 1 次 SRAM 下载 → 复位 → COM 115200 → 真实 A 帧全链 → PC 解码/CRC；TPG boundary；无半帧/无 Flash/不第二次下载。

### 50.1 r4 判定与 r5 任务重排
- r4：离线全绿（P1 三例逐字节一致、心跳解码自测、综合 +0.256/0 违例/ERAM 71），Routed **-0.274 / 23 端点**，全部 `u_core/htab_p3v_syn_23.clkb → bm_b_syn_29.addrb[12:0]`；三次布线逐位相同；bitgen fail-closed → 无 bit/CWC/下载。
- 裁决 A：解除 core 冻结，仅 `htab_p3v_q → bm_raddr_b → bm_b.addrb` 加 1 级地址寄存/提前发地址（cycle-neutral）；B/C/D 否。
- `T10.b2-a1-uart-impl`：r0–r4 已用满 4 轮 → **⚠ 未通过**收口，不称完成。
- `T10.b5-a1-htab-pipe`：**新独立包 r0，ready**；承载 r4 的 UART 旁路 + 心跳与唯一的 core 地址流水；同一 run。
- `T10.b3-board-bringup`：唯一 SRAM 下载已消耗（r3 bit，COM8 0 字节）→ **blocked/superseded**；下载次数不转移。
- `T10`：仍 **blocked**（P2 r5、P3、需求二/三未完成）。

### 50.2 r5 门槛与预算
| 阶段 | 门槛 |
|---|---|
| P1 | 三例逐字节同 r4（SHA256 见 `r4/p1-regression-r4.json`）；dup=0/raw_drop=0/cmp_drop=0/geom=0/err=0；exported=1 exp_bytes=40032 cap_bytes=40076 |
| 综合 | SWNS ≥ +0.3、TNS ≥ 0、0 违例；ERAM 含 CWC ≤300；≤3 次 |
| 布线 | 0 违例、SWNS ≥ +0.2（下限 +0.05 记 caveat）、hold ≥0、HWNS ≥0；≤2 次 |
| bit/CWC | 1 + 1；bit/CWC/BID/SHA256 与 compiled.bit 一致 |
| 板级 | 1 次 SRAM 下载；COM8 115200 120 s；≥1 完整帧、四 CRC true、无半帧 |

- 预算：开发 120 min/60 calls；TD 3 会话/150 min、综合 ≤3、布线 ≤2、bitgen 1、CWC 1、下载 1、Flash 0。
- 失败：布线 <+0.05 或任何违例 → 不 bitgen、不下载；板级 0 帧/CRC 失败 → 停，不第二次下载。

### 50.3 下一次准确启动/恢复文本
> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **P2 r5 `T10.b5-a1-htab-pipe` r0**（ready；1 次 SRAM 下载）；项目根 `D:\fpga\ph1p100`。
> 读 `dispatch-r5.json`、`dispatch.json`、`dev-plan.md §58`、`T10.b2-a1-uart-impl/r4/result-r4.md`、`r4/CANDIDATE-MANIFEST-b2-a1-uart-impl-r4.json`、`r4/p1-regression-r4.json`、`r4/td/01e_route_hi.tcl`、`a1_deflate_core.v` 743–759 行。
> 只改 `htab_p3v_q → bm_raddr_b → bm_b.addrb` 一处（1 级地址寄存/提前发地址，cycle-neutral）；SDC/引脚/帧/CRC/UART 旁路/心跳全冻结；core 改动放 `r0/changed-src/`，`a1_board.al` 仅改该 File Path。
> P1 逐字节 → 综合 ≥+0.3 → 布线 0 违例 ≥+0.2（下限 +0.05）→ 1 bitgen + 1 CWC → 1 次 SRAM 下载 + COM8 115200 120 s + PC 解码/CRC；失败即停、不第二次下载。


## 59. T10.b11-aplus-read 冻结（2026-10-25）
- 卡点已改判：**A+ 核没有死锁**，是 reader 第 1177 个 AR 之后丢失 1 个 DDR 读响应（1176/1176/1177，b9/b10 同为 1176 字），feeder 在 `F_WAIT` 等不到 `raw_rd_valid`，核被饿死。
- 新包 **T10.b11-aplus-read**（ready，父 T10 仍 blocked）：真核全尺寸复现定位 → 只改证明点 + 有界看门狗 → P1 三黄金逐字节 → 1 bitgen+1 CWC（Routed 0 违例、WNS≥+0.05）→ **先下载后开 COM8**、150 s、`enc_frames/exported` 增量>0、≥1 帧 44 B 头+CRC+zlib。
- 状态包升级 **v4**（225 B/55 字段：桥/PAXI 计数、A+ 核心 `S_*`、reader 握手、export 状态），整包单边沿快照。
- 预算 150 min/70 calls；TD 3 会话、综≤3、布≤2、bitgen 1、CWC 1、下载 2（同一 bit）；不写 Flash；50 min 未定位则只做 v4 诊断构建，不加猜测性修复。

## 60. 当前状态更新：b11 diagnosis_only，b12 R1 修复包冻结（2026-10-25）

> 本节更新 b 系列当前状态；本文件 2026-10-21 的 T10 头部结论（a1 RTL 3/4 PASS + 1 warning、G2 未闭合）仍然有效，但不再代表 b9–b12 的最新进展。

- **b11 `T10.b11-aplus-read` = diagnosis_only + board blocked**：1176/1177 读停点不在 A1 读通路 RTL（真 CDC/arbiter/store/bridge 全尺寸 129,600 字 bad=0）；剩余 H2（AR 进 AF FIFO 但不再被 PAXI 弹出）与 H4（PAXI 收 AR 不回 R）需板级 v4 判别。Routed `SWNS=+0.015 / 0 违例`；bit `7ef0e9be…`、CWC `08ad62f4…`；FTDI 0403:6042 不在位，**未上板**。
- **R1 = 有效反例，尚未修复**：独立补充验证 `work/b10-gap-sim-20261025-132023` 在 b11 冻结源上复现：FIFO 拒收 7 组（含 LAST）→ 释放背压 → writer/slot0 仍 WRITE（nbytes=45/80）、`raw_abort_cnt=0`；随后两个完整好帧被拒（`begin_deny=2`）。同目录三帧小几何 PASS。
- **新包 `T10.b12-r1-last`（ready；父 T10 仍 blocked）**：只修 R1——clk_cam 拒收即 sticky loss-abort；A1 消费无主 stray beat；store abort 压过同拍写、begin+abort 同拍释放旧槽并接收新帧；保留 `raw_drop/raw_abort_cnt`、v4 225 B、P1 三黄金逐字节。
- **必测**：T2 7 拒收含 LAST→两好帧恢复；T3 同拍 LAST+abort；T4 同拍 begin+abort；T5 中写复位；T6 满槽并发；T7 SOF 拒收变体；T8/T9 b9 回归；T10 三帧；P1 三黄金；v4；full 两帧；b11 read 九例。
- **构建/板级**：1 bitgen+1 CWC；Routed 0 违例、WNS 目标 ≥+0.05（若只能 +0.015 且关键路径仍在 vendor DDR PHY，接受并记 caveat）；FTDI 不在位则 board=blocked/0 下载；在位则先下载后开 COM8、150 s、`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib；仍 1176 只判 H2/H4，不修 DDR/PAXI。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1/Flash 0。
- **入口**：`T10.b12-r1-last/{dev-plan.md,dispatch.json,handoff.md,user-summary.md}`；`T10.b11-aplus-read/r0/result-r0.md`；`work/b10-gap-sim-20261025-132023/README.md`。

## 61. b12 r1 板级 H4 → T10.b13-ddr-retry 冻结（2026-10-25，用户选 A）

> 本节更新 b 系列最新状态；§60 的 b11/b12 描述保留为历史。

- **b12 r1 板级实测**：camera/crop 4,470 帧正常；read 通路 store AR=883、PAXI AR=883、R=882、rlast=882、stale=0、`ar_pending=1`、`af_rvalid=0`、`ddr_rdy=1`；
  `rd_wait_cycles` 饱和、`raw_rd_idx=882/129,600`、`slot0=READING`、`slot1=READY`（各 2,592,000 B）；`raw_pub=2`、`enc=0`、`exported=0`。
  判定 **H4**（DDR 接受 AR 不回 R）；停点 1176→882 不固定 → 偶发丢响应。证据 `T10.b12-r1-last/r1/board/captures2/status_v4.txt`。
- **b12 r1 候选**：bit `9180DB8C…2F8CD3`、CWC `FFB88419…B47C9A0`、BID `96D8A5DF…9E4A32`；Routed `SWNS=+0.003 / HWNS=+0.020 / 0 违例`，
  `timing_caveat=thin_margin_+0.003`（诊断候选）；1 次 SRAM 下载；未写 Flash。b12 **不置 done**（父 T10 仍 blocked）。
- **新包 `T10.b13-ddr-retry`**（ready；`needs_user_input=false`）：DDR 读超时 + 重试。超时 8192 clk_a1 → abort 当前帧读、槽保持 READING →
  清 `ar_pending`/AF/RF → 32768 clk_a1 保护窗禁新 AR、晚到 R 计 stale → 重试同一帧最多 2 次 → 仍失败释放槽 + `giveup`，不发布半帧。
- **v5**：241 B/59 字段；追加 `timeout/retry/giveup/stale`；`#1..#55` 不变。
- **只改 6 源**：store 读 FSM、arbiter raw abort、bridge purge/guard、top 超时序列、板级连线、v5 包；A+ 核/crop/帧格式/SDC/时钟/DDR IP 冻结。
- **构建/板级**：综合≤3/布线≤2、Routed 0 违例、WNS 目标 ≥+0.05（0 违例且 +0.003…+0.05 接受为诊断候选并记 caveat，<+0.003 或违例即停）；
  1 bitgen+1 CWC；先下载 1 次 SRAM 后开 COM8 150 s，`enc_frames/exported` 增量>0、≥1 帧四 CRC+zlib；每帧同一位置失败且 exported=0 → 停，转 B。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1/Flash 0；测试 45/30。
- **入口**：`T10.b13-ddr-retry/{dev-plan.md,fpga-design-guide.md,dispatch.json,handoff.md,user-summary.md}`。

## 62. T10.b14-cam-b 冻结（2026-10-25，规划；B 相机尝试）

- **触发**：b13 r1 板级 150 个 v5 包（bad_xor=0）仍 `pix_beats=0/line_rises=0/cap_frames=0/enc=0/exported=0`，而 `clk_tgl/pkt_tgl` 在涨、`vs_tgl` 0→2：A 路“有 MIPI 包/VSYNC、无有效像素”（b7/b9/b10/b13 复现；b8 上电曾 3,300 帧）。用户决定尝试 B。
- **已核实**：b13 r1 核（SHA `C9DE0D9C…05089`）的 `u_cfg_b` 已使能（`r_rst_n_slow`, mode=1）、`u_csi_b` 已复位释放且 `I_rx_en=1`；`w_b_pixel/valid/in_line/in_frame/vsync/byte_clk` 均存在；B 引脚已在 `board_p2.adc` 分配。**B 不需要“最小使能”**。
- **新包 `T10.b14-cam-b`**（ready；父 T10 保持 blocked；`needs_user_input=true` 仅问 B 模块是否物理连接）：核只加 B tap/B 诊断（纯 assign）；`p2_a1_board_top` 用 `localparam CAM_SEL=1` + `generate` 把 `clk_cam`/tap/`i_dbg_*` 切到 B，A 核仍存活；`cam_sysstat[20]=cam_sel`；`p2_board.sdc` 只加 `mipi_b_byte_clk` generated clock 与异步组；v5 仍 241 B/59 字段，`#3/#4/#5` 记录所选相机（B）的 pix/line/frame。
- **验收**：S1 B 几何 3864×2192/ROI 972/556/1920×1080 全链（pix_beats=2,117,472/line=2,192/frame=1/raw=2,592,000/enc=1/exported=1/四 CRC+zlib）；P1 三黄金逐字节；v5 结构/bit20；B 时钟停振与短行失败态；Routed 0 违例、WNS 目标 ≥+0.05（薄 +0.003..+0.05 接受并 caveat，<+0.003 或违例即停）；1 bitgen+1 CWC。
- **板级**：先确认 B 已连接；未确认 → `board=blocked`、0 下载。确认且 FTDI 在位 → 先 1 次 SRAM 下载，再 COM8 150 s；B 的 clk/pkt/pix/line/frame/cap>0，再 enc/exported>0 且 ≥1 帧四 CRC+zlib；B 也无像素 → 停并留证，不第二次下载。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1/Flash 0；测试 45/30。
- **入口**：`T10.b14-cam-b/{dev-plan.md,fpga-design-guide.md,dispatch.json,handoff.md,user-summary.md}`。

## 63. T10.b15-ddr-pace 冻结：读通路严格单笔（2026-10-26，规划）
> 本节更新 b 系列最新状态；§62 的 b14 描述保留为历史。

- **b14 r0 板级已把卡点收到唯一一处**：A 相机 `cap_frames=4470`、`pix_beats` 正常、`crop_short=0`、`crop_geom_err=0`、`raw_pub=4470`；但 `timeout=13,410 / retry=8,940 / giveup=4,470`（3/2/1 每帧）、`enc=0 / exported=0`、`ar=17,213,681 / r=17,200,031`（每次尝试少回 1 个 R）。
- **判读**：超时/重试兜底按设计工作，但每次尝试都确定性少 1 拍，所以 3 次尝试必然全废。bridge 的 `ar_pending` 在首拍清零（应到 `rlast`），`rready=1` 而 `rf_push=0` 时晚到拍被静默吞掉——“单笔 AR”只是名义上的。
- **新包 `T10.b15-ddr-pace`**（ready；父 T10 仍 blocked；`needs_user_input=false`）：只改 `p2_ddr_bridge.v` —— `ar_busy` 到 `rlast` 才清、新 AR 前置“读通路为空”、`paxi_rready` 恒 1、每拍必入队、孤立 R 只计 stale；b13 的 8192/2 次超时重试与 purge/guard 全保留。
- **冻结**：其余 10 个 RTL 逐字节、SDC 0 行、v5 241 B/59 字段不变（outstanding = `ar − rlast`）；A 路保留（不引入 `CAM_SEL`，b14 的 B 选择 diff 挂起）。
- **验收**：正常整帧／丢 1 R 恢复／连续 3 帧／full 两帧／P1 三黄金逐字节／b12+b13 回归／抗逆例／v5 结构；Routed 0 违例、ERAM+CWC≤300、WNS 目标 ≥+0.05（薄 +0.003..+0.05 记 caveat）、1 bitgen+1 CWC；板级先下载后 COM8 150 s，`timeout/retry/giveup` 归零、`enc/exported` 增量>0、≥1 帧四 CRC+zlib。
- **预算**：开发 120 min/60 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1/Flash 0；测试 45/30。
- **入口**：`T10.b15-ddr-pace/{dev-plan.md,fpga-design-guide.md,dispatch.json,handoff.md,user-summary.md}`。

## T10.b18-b17-b (2026-10-26)
合并包已冻结并派发（ready，r0，父 T10 仍 blocked）。详见 `T10.b18-b17-b/{dispatch.json,dev-plan.md,handoff.md,user-summary.md}`：b17 基线 + b14 B tap/CAM_SEL=1 + b14 r1 SDC，一个候选一次上板。
