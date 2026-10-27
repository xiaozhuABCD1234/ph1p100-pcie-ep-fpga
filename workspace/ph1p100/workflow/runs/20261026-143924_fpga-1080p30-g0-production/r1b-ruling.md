# P1 r1b 收口与后续包重排裁决 — `T10.ss-g0-prod-content` / core gap

- run：`20261026-143924_fpga-1080p30-g0-production`；日期：2026-10-26
- 依据：P1 r1 综合报告 `test-reports/T10.ss-g0-prod-content-r1-integrated.md`（FAIL 仅 A3 `dup=0`；A3 其余 8 子句、engineering、system PASS；G0=`not_proven`、G1=PASS）
- 适用：P1 r1b gate correction（原 tester，0 重跑）；P2 coregap / P3 sink / P4 verdict 的重排与预算
- 本裁决不改 DUT、不改内容、不改 G0 门槛、不做 TD/板卡、不新增第 5 包。

## 1. 事实认定

| 项 | 认定 |
|---|---|
| r1 实测 | N `S_ss=7,475,240`（25.083 fps / 65.015 MB/s / G0 **−16.3906%**，`sink_limited=false`）；L `S_ss=6,986,952`（26.836 fps / 69.558 MB/s / G0 **−10.5475%**，`tail_frac=61.7249%`） |
| 4 帧完整性 | N/L 均 `t_exp(1..4)` 非空、`cap=enc=exported=4`、`read=518,400`、有 `SS_STATS`、`raw_drop=cmp_drop=geom=err=wd=0`、`bad=0 checked=518400`、header CRC ok；N 由 tester 自有库全尺寸重跑逐字节复现 |
| 唯一 FAIL | A3 的 `dup=0` 字面（N 3,896 / L 568）；**不是**缺帧、丢帧、CRC 或数据完整性错误 |
| 瓶颈 | 两类均 `core_interval` 主导（N 2.23× export、L 1.62×）；sink 不是主约束 |
| G0 | N=`G0_not_closed`、L=`G0_not_proven`（`sink_limited` 冻结规则），headline=`G0_not_proven`；G25 仅参考 |

## 2. 裁决 A：`dup` 只记录，不作为完整性门槛

**采 A（不采 B/C）**，理由：

1. `st_dup_words` 的源码（`a1_ddr_slot_store.v:280-284`）在每次有效读字时 +1，比较的是**相邻 256-bit 载荷是否逐位相同**；无地址比较、无重发计数、无 CRC/ID 校验。它是**内容统计量**（等价于相邻 16 px packed RAW10 相同），不是「重复读/重传」。
2. 测试者用冻结 `raw_*.bin` 按 20 B 载荷切片**精确预测** N 974×4=3,896、L 142×4=568，帧边界交叉项 0；`read=518,400`（无多余读）、`ar=r`、`raw_crc`/`header_crc`/`raw_bad` 全部干净。没有任何残余可归因于重复读。
3. 该子句只在合成梯度/随机内容上恒成立；把它留作门槛会让**任何自然内容必然失败**，属「门槛假设与内容不兼容」，与 r0 的 12M 看门狗同类，**不是 DUT 缺陷**。
4. 采 B（保留 `dup=0`）会使 P1 永远无法 PASS 且 P2 同样被卡；采 C（从 `ss_pass` 移除）需要新 TB + 白名单 + 另计 harness 预算，**不必要**：`ss_pass` 只是 TB 便利旗标，验收以显式子句为准。

**门槛改写（已落地）**：

- dev-plan A3：`raw_drop=cmp_drop=geom=err=wd=0`；`dup` 只记录，不参与判定。
- guide §3：G0 完整性行去掉 `dup`；新增 `dup` 语义段与 `ss_pass` 说明（自然内容 `ss_pass=0` **不是失败**）。
- 任何后续包（P2/P3/P4）不得把 `dup=0` 或 `ss_pass=1` 当验收门槛。
- **例外**：若 `dup` 异常升高且伴随 `read>518,400`、`ar≠r`、CRC/自检失败，则按数据完整性问题单独调查，不适用本豁免。

## 3. P1 r1b 收口（0 重跑，转 PASS）

- 由**原 P1 综合测试者**（同一会话）在 `manifest-r1.json`（SHA `e306ed42…`）上重评 A1–A5：A3 按改写后的 9 子句（8 项 + `dup` 记录）全部成立；engineering/system 复用 r1 结论；G0 头保持 `G0_not_proven`（N `not_closed`、L `not_proven`）。
- 产出 `test-reports/T10.ss-g0-prod-content-r1b-integrated.md`，首行 `### 判定：PASS`；必须写清「gate correction，不是新修复轮；0 全尺寸重跑；证据复用 r1 报告 + 原始 caps」。
- 预算：≤10 calls、≤20 min、0 全尺寸、0 TD/板卡；不改 manifest-r1/候选/内容。
- **不占修复轮**：P1 的 r0（看门狗）与 r1（dup 门槛）都是 harness/门槛缺陷，不是 DUT 实现缺陷；`repair_round` 保持 1。若 r1b 发现 8 项中任何一项实际不成立，则不得 PASS，回到真实修复轮。

## 4. 实质结论（不改写、不降档）

- 在自然场景派生内容（`proxy_not_natural_raw`，非传感器 RAW）上，4 帧 slot-free + 93.75 MB/s TB sink 的 1080p30 G0 **不成立**：N −16.39%、L −10.55%，**core 吞吐是主瓶颈**；把 sink 提到 103.79 不会改变该结论。
- **本轮边界内的明确结论**：当前 b11 core + 187.5 MHz **不能**闭合 G0（N 需 1.196×、L 需 1.118×；b11 Routed WNS +0.015 ns 只剩约 188 MHz 的时钟余量，209.6/224.3 MHz 不在当前时序能力内）。因此本 run 的 headline 为 **`G0_not_closed`**；P2 只决定「是否值得为结构性改核投入专门实现 + TD」，不是在本轮把 G0 打开。
- 用户坚持 1080p30、不得降档；本裁决不提出降档，只把「换核/提时钟/接受 not_closed」作为用户决策项。

## 5. P2 重排：`T10.ss-g0-prod-coregap`（替换退役的 slotfree 包）

**为什么替换**：P1 已实测 core 是主约束（N core 7.475M vs export 3.355M；L 6.987M vs 4.313M）。生产 slot-free 只能在此之上再加惩罚，不是当前瓶颈；先做它会在已知非主约束上花 1 个包。生产 slot-free/pacing 降为后续主题。

**包定义**：量化在 187.5 MHz、单核、ERAM ≤300/LUT6 ≤71,680 内闭合 N −16.39%、L −10.55% 的方案；给 `closable_at_187_5 = yes/conditional/no` 与 go/no-go；**不实施 RTL、不跑 TD/板卡**。

**关键实验**：1 帧 stage probe（N/L 各 1 次，约 700–750 s/次），只读层次 tap `dut.u_a1.u_core.stat_{blocks,fixed,stored,literals,matches,cand_aborts,stall,max_match,max_dist}`；探针周期须与 r1 帧 1 的 `t_enc(1)-t_pub(1)`（N 7,476,245 / L 6,979,811）在 ±2% 内。模型须对 N/L/C1/comp 四点残差 ≤5%。方案矩阵 ≥6 行（2-symbol/更宽扫描、htab 1024→4096/8192、窗口 2048→8192、深流水、仅时钟、双核、换算法），每行给 cycles/B、闭合比例、资源/时序风险、置信度、是否单独足够。

**规划先验（须证实/推翻）**：

- comp 锚点 355,261 cycles/153,600 B = **2.313 cycles/B**（81.067 MB/s），说明 G0 的 2.411 cycles/B 不是结构性不可达；自然内容 2.884 cycles/B 的差值来自内容相关的符号/扫描开销。
- b11 Routed `WNS=+0.015 ns @187.5`（关键路径约 5.318 ns ≈188.0 MHz）⇒ **仅提时钟到 209.6/224.3 MHz 不可信**；必须先做结构性流水。
- 双核不提高 per-stream（P2 可行性报告），且 ERAM 231–289/300、双核时序 `unproven` ⇒ F 行预期 no。
- 因此先验倾向 `conditional`/`no`：需要结构性 core 改造 + 专门实现 + TD，当前 core 的参数/时钟微调不足以闭合 16.39%。P2 负责用计数器与模型证实或推翻。

**验收**：E1 DUT 0 改/只读 tap；E2 probe 有效（±2%）；E3 模型残差 ≤5%；E4 矩阵可决策；E5 go/no-go 明确。E3 不达标 → `blocked`，不得用猜测矩阵。**结论为 no 不算 FAIL**。

**`closable_at_187_5` 判定规则（机械，避免主观）**：

- `yes`：存在单方案或组合，估算 N `cycles/B ≤2.411`（L 自动满足），ERAM ≤300、LUT6 ≤71,680，**不需提时钟**，模型不确定度 ≤10%；
- `conditional`：只有叠加 ≥200 MHz（需重流水）或资源 >270 ERAM 才达到，或不确定度 >10%；需原型 + TD；
- `no`：即使 224.3 MHz + 最优资源也达不到 2.411，或必须换核/换算法。

**预算**：开发 ≤40 calls / ≤110 min / 1 帧全尺寸 ≤2 / vsim ≤45 min / 单次 1500 s；测试 ≤35 calls / ≤60 min / probe 重跑 ≤1 / vsim ≤20 min。**新开发 + 新测试者，不复用 P1。**

## 6. P3 重排：`T10.ss-g0-prod-sink` 缩为 0-sim headroom 模型

- 实测 comp 流：N 1,677,336 B/帧（1.5453:1）、L 2,156,300 B/帧（1.2021:1）；sink 需求 33.33 ms → 50.32/64.69 MB/s；25.0 ms → 67.09/86.25 MB/s；**均 <93.75** ⇒ 冻结 sink 对实测 comp 路径有余量，sink 不是 P1 的瓶颈。
- raw band 2,594,706 B/帧：93.75 下 5,189,412 cycles（83.03%，满足 33.33 ms）；103.79 下 4,687,500 cycles（75.0%，25 ms）；**≥103.79 生产 sink 仍未实现/未证**，且只对 RAW fallback 有意义。
- P3 只做账/模型/边界（0 vsim、0 TD、0 板卡），不再做原计划的 4 帧 sink run；不改变 G0。
- 预算：开发 ≤20 calls / ≤25 min；测试 ≤20 min / 0 sim。

## 7. P4 判定与用户决策

- 合并 P1 r1b + P2 + P3；预期 `G0_not_closed`（N/L 均 >6.25M；L 的 `sink_limited` 按冻结规则使该类 `not_proven`，headline 取较弱者）。
- 不得用 P3/P4 合成 C1 的 `G0_feasible_for_scope` 覆盖自然内容结论；不得用 G25 降档。
- 用户决策项（P2 给量化依据）：① 换核/改算法；② 提时钟（需重流水 + TD/STA，当前 WNS 只够 ~188 MHz）；③ 接受 `G0_not_closed`。**降档需用户明确，本轮不主推。**

## 8. 预算/轮数/依赖

| 包 | 全尺寸/探针 | 墙钟 | 备注 |
|---|---|---|---|
| P1 r1b | 0 | ≤20 min | 原 tester，0 重跑，不占修复轮 |
| P2 coregap 开发 | 2×1 帧 | ≤110 min | 新 dev，1500 s/次 |
| P2 coregap 测试 | ≤1×1 帧 | ≤60 min | 新 tester |
| P3 sink 开发/测试 | 0 | ≤25 / ≤20 min | 0 sim |
| P4 verdict 开发/测试 | 0 | ≤45 / ≤25 min | 只读合并 |

- P1 累计：全尺寸 4/6、vsim 86.1/200 min；不再重跑。
- 依赖：P1 r1b PASS → P2；P1 PASS → P3（可与 P2 顺序执行，默认不并行）；P1–P3 PASS → P4。每包 PASS 后由原规划更新 dispatch。
- 退役：`T10.ss-g0-prod-slotfree` 不在本轮 4 包内（替换为 coregap），作为后续主题；不新增第 5 包。
