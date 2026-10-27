# P2 r0 OBS 裁决与 P3/P4 放行 — `T10.ss-g0-prod-coregap`

- run：`20261026-143924_fpga-1080p30-g0-production`；日期：2026-10-26
- 依据：P2 r0 综合报告 `test-reports/T10.ss-g0-prod-coregap-r0-integrated.md`（PASS；7 项非阻断 OBS；`closable_at_187_5=conditional`；headline `G0_not_closed`）
- 适用：P2 文档重冻（同一 P2 开发/测试者，manifest-r1）；P3 sink 模型；P4 verdict
- 本裁决不改 P1/P2 候选算术、不改 G0 门槛、不做 TD/板卡、不新增第 5 包。

## 1. P2 r0 结论（接受，不改写）

| 项 | 值 |
|---|---|
| 探针 | N `core_interval=7,476,245`、L `6,979,811`，与 P1 r1 帧 1 **0.000%**；9 个 core 计数器有值；测试者独立库重跑逐字节一致 |
| 模型 | r=1.900712、k=293.6313、c_ab=1,108.98；LOO `{N,comp}→L +2.4203%`、`{L,comp}→N −3.2523%`、`{N,L}→comp −3.5619%…−1.9085%`，均 ≤5% |
| 矩阵 | 8 行；唯一 187.5 MHz 算术闭合 **A+H = 6,008,078（2.3179 c/B，+4.027%）**；包络 hi/lo = 7,223,675/3,970,580 → **45.034%**；单 H 6,260,648（−0.170%）仍差 0.17% |
| 时钟 | 209.6 MHz 允许 6,986,667（−6.548% 差）；224.3 MHz 允许 7,476,667（**+0.0056%**，仅 0.006% 余量）；b11 Routed WNS +0.015 ns @187.5（≈188.0 MHz），仅提时钟不可信 |
| 双核 | per-stream 不变（7,476,245），ERAM 231–289/300、时序 unproven |
| 判定 | `conditional`（唯一闭合路径是未实现的 A+H，包络 45% ≫ 10%）；headline **`G0_not_closed`** |

## 2. 裁决：要求 P2 0-sim 文档重冻（同一 P2 开发/测试者，manifest-r1）

**不采「OBS 全交 P4 记录」**。理由：OBS-1 是审计链缺口（冻结的逐行 diff 不描述实际 TB），OBS-4 会把 C1 核级界夸大一倍，OBS-2/3/6 会让 P4 引用到与模型矛盾的注释/系数；P4 是合并包，不应替上游修证据。重冻**不改模型算术、不改矩阵数字、不改 `conditional`、不改 G0**，只改文档/注释/标签/参照物，**0 sim、0 新证据**。

### 重冻清单（只允许这些改动）

| # | 对象 | 修正 |
|---|---|---|
| R1 | `src/DIFF-probe.raw`、`src/DIFF-probe.md` | 按**最终** `tb_ss_4run_wd_probe.v` 重新生成 `git diff --no-index --unified=2`（测试者实测 54 行，SHA `189ebf24…`）；`.md` 的 hunk/行数/白名单条目 1/4 与实际一致（8 拍事件式 dump）。**TB 本体不改**。若因路径头导致 SHA 不同，测试者按 hunk 内容/行数（4 hunk、+17 行）裁定，不因路径字符串误判 |
| R2 | `out/coregap-model.json` 行 H `note` | 删除 "6.63M / 6.2% short"，改为与 `6,260,648 / −0.17%` 一致；H 仍"单独不够" |
| R3 | `model/assumptions.json` | 增列 `c_ab=1,109`（fitted/assumed，附三点联立说明）；把 `fitted` 明确映射到冻结词汇 `measured/derived/assumed`（如 `assumed(fitted)`）；写明 in-sample=0 是构造性、不是验证 |
| R4 | `out/coregap-model.json → residuals.C1`、`result-r0.md` C1 段 | 用物理系数重写：**2,905,862～3,042,041（估计 2,956,095 = 链级 63.19%）**；删除 1,441,559～1,577,737（33.7%）及其非物理 k=−2418 依据；结论 `not_applicable_core_level` 保留 |
| R5 | `out/coregap-model.json` 行 B/C | `delta_scan=-0.02×scan` 标 `assumed`；保留 "matcher 未验证、offline matcher hbits 10→12/13 <0.1%、窗口 2048→4800 仅 0.54%/0.20% literals"；B/C 仍"否" |
| R6 | `out/coregap-model.json → anchors.{N,L}.probe_vs_p1_pct` | 统一参照物为**帧 1 core_interval**（0.000%）；若保留 4 帧 `S_ss` 对照，另列并注明口径不同 |
| R7 | `result-r1.md` / manifest notes | 登记 OBS-5：P2 r0 dev 工具调用 ≈49 > 40（无仿真增量、无门禁影响）；本重冻不追溯改判 |
| R8 | 新 `manifest-r1.json` | `repair_round=1`、`previous_manifest=manifest-r0.json`（`97d7b195…`）、全 artifact 覆盖、`stopped_modifying=true`、`active_commands=0`、`evidence_rounds` 全 0 sim |
| R9 | P2 测试者 r1 报告 | 文档级重绑：核 R1–R8、确认无重跑、P1 manifest-r1 为 **70 artifacts**（r0 报告 §0 误写 40，属报告笔误，须在 r1 更正）；给 `### 判定：PASS`，绑定 manifest-r1；不改 r0 报告 |

**禁止**：改探针 TB/DUT/内容、改 r/k/c_ab/矩阵数字/包络/`conditional`/G0、重跑探针、TD/板卡、改写 r0 报告或 manifest-r0。若重冻发现某项不是文档问题而是数字错误 → 停止，按真实修复轮处理，不得静默改数。

**预算**：P2 dev ≤15 calls / ≤30 min / 0 sim；P2 tester ≤10 calls / ≤20 min / 0 sim。P2 累计（r0 已用 49 calls / ≈70 min / 3 探针 34.93 min）上限放宽为 **≤70 calls / ≤130 min / 探针 ≤3**，理由：r0 超出 40 calls 属已披露的过程偏差、无仿真增量，重冻不再计新探针。

## 3. P3 放行：`T10.ss-g0-prod-sink`（0-sim headroom 模型）

**为什么仍要做**：回答原需求第 3 条的 sink 问题，且 P1 实测已给出足够字节；不需要 4 帧 sink run，也不需要新 sink RTL。

**包定义**：0 sim、0 TD、0 板卡；新开发 + 新测试者；只读 P1 r1b/`content-verdict-r1` 与 P2 r0 报告。产出三档账、comp/raw band 分离、模型/生产/板级三级边界。

**关键数（P1 实测）**：

- comp 流 N 1,677,336 B/帧（1.5453:1）、L 2,156,300 B/帧（1.2021:1）。
- 33.33 ms：N 50.32、L 64.69 MB/s；25.0 ms：N 67.09、L 86.25 MB/s —— **均 <93.75**，冻结 sink 对实测 comp 路径有余量。
- raw band 2,594,706 B/帧：93.75 → 5,189,412 cycles/27.677 ms/83.03%；103.79 → 4,687,500/25.0 ms/75.0%；187.5 → 2,594,706/13.84 ms/41.5%。
- **≥103.79 MB/s 生产 sink 未实现/未证**，且只对 RAW fallback（stored）有意义；不得把 93.75 说成 103.79。

**验收**：C1 三档账可复算；C2 93.75 对 comp 有余量、对 raw band 25 ms 不足；C3 不声称生产 sink 已实现/已证；C4 0 sim/0 TD/0 板卡；C5 不改变 G0；C6 只用 P1 实测字节（不用 P4 comp 代理冒充本内容）；C7 raw band 只对 fallback。预算：dev ≤20 calls / ≤25 min；tester ≤20 calls / ≤20 min。

## 4. P4 放行（条件）：`T10.ss-g0-prod-verdict`

P4 **已解除规划层阻塞**，但依赖 **P3 PASS + P2 文档重冻 r1 PASS**；两者齐备后由原规划派新开发/新测试者（0 sim）。不得在 P3/P2-r1 完成前启动，避免拼贴。

**P4 必须写清（用户点名的六条）**：

1. 当前 core + 187.5 MHz **不能**闭合自然内容：N −16.3906%（7,475,240 vs 6,250,000）、L −10.5475%（6,986,952；`sink_limited=true` 但 core-bound）。
2. A+H 是**唯一 187.5 MHz 算术闭合**（6,008,078，2.3179 c/B，+4.027%），但包络 **45.034%** → `conditional`，**不是 G0 闭合**；P4 不得写 "feasible"。
3. 仅提时钟 209.6/224.3 MHz 不在 b11 时序能力内（WNS +0.015 ns @187.5 ≈188.0 MHz；224.3 仅 0.006% 算术余量）。
4. 双核不提高 per-stream（同 7,476,245；ERAM 231–289/300、时序 unproven）。
5. P3：93.75 对实测 comp 有余量；raw band ≥103.79 未证。
6. 用户坚持 1080p30、不降档；需要决定：投入 core 结构改版（A+H，原型 + TD + 板级）／换核或换算法／接受其他边界（`G0_not_closed`）。**降档需用户明确，P4 不主推。**

**P4 判定**：headline `G0_not_closed`；scope tuple = {content: 自然场景派生 Bayer（非传感器 RAW）；pacing: TB `wait_slot_free`；sink: 93.75 TB 代理；DDR: 行为 256-bit PAXI；core/clock: 单核 187.5 MHz；stream: 单路}；G25 仅参考；剩余缺口与恢复入口。D1–D8（含 P2-r1 绑定、无 "G0 closed"）。

**预算**：dev ≤25 calls / ≤45 min / 0 sim；tester ≤25 calls / ≤25 min / 0 sim。新开发/新测试者。

## 5. 顺序与预算

| 步骤 | 角色 | 0 sim | 预算 | 依赖 |
|---|---|---|---|---|
| 1. P3 dev → tester | 新 | 是 | 20/25 + 20/20 min | P1 r1b PASS |
| 2. P2 文档重冻 dev → tester | 原 P2 | 是 | 15/30 + 10/20 min | P2 r0 PASS |
| 3. P4 dev → tester | 新 | 是 | 25/45 + 25/25 min | P3 PASS + P2-r1 PASS |

- 顺序选择：先 P3（独立、0 sim），再 P2-r1（只影响 P4 绑定），最后 P4。P2-r1 必须在 P4 开始前完成；P3 不绑定 P2 候选件，只引用其 `conditional` 结论。
- 每步 PASS 后由原规划更新 dispatch；不预 spawn 多个。
- OBS-5 为**过程偏差**登记：不返工、不追改判；P2 累计预算按 §2 放宽并封顶。
