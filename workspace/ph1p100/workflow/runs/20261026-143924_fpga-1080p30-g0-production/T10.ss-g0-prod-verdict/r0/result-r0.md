# T10.ss-g0-prod-verdict r0 — run 级 G0 合并判定（0 sim / 0 TD / 0 板卡）

- task_id：`T10.ss-g0-prod-verdict`；run：`20261026-143924_fpga-1080p30-g0-production`；round：**0（新开发会话，未复用 P1/P2/P3）**
- 角色：fpga-dev（candidate author，不自判验收）；状态：**ready_for_test**，本文件不宣称 PASS
- **headline：`G0_not_closed`**
- 证据方式：**0 sim / 0 TD / 0 综合 / 0 布线 / 0 bitgen / 0 下载 / 0 Flash / 0 板卡 / 0 COM/JTAG/RK / 0 网络**；只读 P1 r1b、P2 r1、P3 r0 冻结件并复算 SHA
- 不重写任何上游报告：P1/P2/P3 的 `result-*.md`、JSON、manifest 全部保持原字节；本包只新增 `T10.ss-g0-prod-verdict/**`

## 1. 判定

本轮 G0 的 headine 为 **`G0_not_closed`**：在声明 scope 内，自然场景 N 与低照 L 均有**实测**稳态缺口，且两类的主瓶颈都是 `core_interval`（不是 sink）。G0 没有被证明可闭合；本轮也没有任何实现（RTL/TD/板卡）被做出来。

### 1.1 `sink_limited` 澄清（本 run 唯一的口径变化；数值与证据不变）

冻结规则原写 `sink_limited = (tail_frac ≥ 50%)`。P4 放行裁决（`p4-release-ruling.md` §2，guide §3 同步）澄清：

- `tail_frac ≥ 50%` **只是诊断旗标**，必须报告，但它本身**不阻断** G0；
- 作为 `G0_not_proven` 的阻断条件，只用 **sink 忙碌率** `busy = export_time / S_ss ≥ 0.95`（sink 在 ≥95% 的帧间隔内持续服务，才视为实际 gate）；
- 不用 `export_time ≥ core_interval` 作判据（sink 背压会同时拖慢 core 的 `t_enc`，忙碌率能干净分开）。

机械重评（数值全部来自 P1 r1 实测，未改一字节）：

| 类 | `S_ss` | `tail_frac`（旗标） | `export_time` | `busy=export/S_ss` | P1 报告原判定 | **run 级判定** | `margin_G0` |
|---|---:|---:|---:|---:|---|---|---:|
| N | 7,475,240 | 44.8783% | 3,354,672 | **44.8771%** | `G0_not_closed` | **`G0_not_closed`** | **−16.3906%** |
| L | 6,986,952 | **61.7249%** | 4,312,600 | **61.7236%** | `G0_not_proven` | **`G0_not_closed`** | **−10.5475%** |

- L 的 `tail_frac=61.7249%` 超过 50%，但 sink 仍有 38.28% 的帧间隔空闲；帧间隔由 core 的 6,986,951 cycles 决定（export 4,312,600 只占 0.617×）。因此 L 是**可量化的 core 缺口**，按澄清判 `G0_not_closed`（−10.5475%），不是“容量不可证”。
- **报告修正声明（显式）**：P1 r1b 报告/`content-verdict-r1.json` 与 P3 r0 报告的 headline 按当时冻结的 50% 代理写的是 `G0_not_proven`；**run 级 headline 由本澄清修正为 `G0_not_closed`**。P2 的 headline 已是 `G0_not_closed`（其 `headline_detail` 仍复述 P1 旧旗标，run 级以本澄清为准）。**以上修正只改 headline 归类，不改任何数值、证据、门槛或 G0 公式；P1/P2/P3 原报告不得被重写，本包也未重写。**
- **向后兼容**：P4 四轮矩阵 R3（rand）`busy=5,189,412/5,189,503=99.998%` → 仍 `sink_limited=true`/`G0_not_proven`；R1/R2/R4 `busy=3.50%/2.54%/28.64%` → 不受影响。澄清不改变任何历史判定。

### 1.2 逐类合并表（P1 r1b，manifest-r1 `e306ed42…`，70 artifacts）

| 量 | N（自然场景） | L（低照夜景） |
|---|---:|---:|
| `t_exp(1..4)` | 12,440,157 / 19,914,239 / 27,389,479 / 34,864,719 | 12,901,635 / 19,887,447 / 26,874,402 / 33,861,351 |
| `S_ss=(S_23+S_34)/2` | **7,475,240**（spread 0） | **6,986,952**（spread 6） |
| `L_cold=t_exp(1)`（单列，不进 `S_ss`） | 12,440,137（1.9904×G0） | 12,901,615（2.0643×G0） |
| `tail_mean` / `tail_frac` | 3,354,764 / 44.8783% | 4,312,692 / 61.7249% |
| `export_time` 均值 / `core_interval` 均值 | 3,354,672 / 7,475,238 | 4,312,600 / 6,986,951 |
| `bottleneck_attribution` | **core_interval**（2.23× export） | **core_interval**（1.62× export） |
| `C_ss` / `fps` | 65.0146 MB/s / 25.0828 | 69.5582 MB/s / 26.8357 |
| 稳态 comp 字节/帧（压缩比） | 1,677,336 B（1.5453:1） | 2,156,300 B（1.2021:1） |
| `dup`（只记录，不参与门槛） | 3,896 | 568 |
| `margin_G0` / `margin_G25`（G25 仅参考列） | −16.3906% / −33.1125% | −10.5475% / −28.438% |
| **G0（run 级）** | **`G0_not_closed`** | **`G0_not_closed`** |

- A3 完整性（P1 r1b 裁决 A 后）：两类 `cap=enc=exported=4`、`read=518,400`、`raw_drop=cmp_drop=geom=err=wd=0`、`SS_RAW_MATCH bad=0 checked=518400`、header CRC 自洽；`dup=3896/568` 是「相邻 256-bit 读字载荷逐位相同」的**内容统计量**，**只记录**；`ss_pass=0` 是该冻结 TB 表达式含 `st_dup==0` 的后果，**不是任务失败**（guide §3 / 裁决 A）。
- N 的测试者自有库重跑逐字节一致（P1 r1b 报告）。

### 1.3 P2 core gap 合并（P2 r1，manifest-r1 `803d3efb…`，49 artifacts；**只用 r1，不用 r0**）

- 探针：N 7,476,245 / L 6,979,811（与 P1 r1 帧 1 `core_interval` 0.000%）；模型 r=1.9007、k=293.63、c_ab=1109.0，N/L/C1/comp 四点残差 ≤5% + LOO。
- 8 行矩阵（cycles/frame）：A 7,223,675；B/C 7,384,642；D/E/F/G 7,476,245；**H 6,260,648（−0.17%）**。
- 组合：**A+H = 6,008,078（2.3179 cycles/B，+4.027%）** 是**唯一的 187.5 MHz 算术闭合组合**；A+B+H 5,916,475（2.2826，+5.64%）；A_full+H（乐观上界）3,970,580（1.5319）。
- **包络**：3,970,580 – 7,223,675 → **45.034% 不确定度** → **`closable_at_187_5 = conditional`**。这是**未实现结构的估算**，不是 G0 闭合、不是已实现、不是 TD/实测；单 H 6,260,648（−0.17%）仍不够。
- 仅提时钟：b11 Routed `WNS=+0.015 ns @187.5 MHz` → 关键路径 ≈5.318 ns ≈**188.0 MHz**；209.6/224.3 MHz 不在当前时序能力内；224.3 只把 7,476,245 压到约 6,250,x（**0.006% 算术余量**），无工程余量，且必须先重流水 + TD。
- 双核：per-stream 链级 75.684 MB/s 不变（7,476,245 不变）；ERAM 231–289/300、时序 `unproven` → F 行 no。
- P2 r1 采用**原地覆盖 r0 的 7 个文档文件**（OBS-8）：本包只引用 r1，**不声称 r0 文档可复现**。

### 1.4 P3 sink 合并（P3 r0，manifest-r0 `de8a5cff…`，5 artifacts；模型，0 sim）

- comp 流需求（P1 实测字节）：33.3333 ms → N 50.32008 / L 64.68900 MB/s；25.0 ms → N 67.09344 / L **86.25200** MB/s，全部 < 93.75；最紧点 **L@25 ms 占 92.0%，余量 8.69%**。
- raw band（2,594,706 B/帧）：30 fps 需 77.84118 MB/s（93.75 可满足）；25.0 ms 需 **103.78824 MB/s**，93.75 短 **10.7075% / 2.676864 ms**。**≥103.79 MB/s 生产 sink 未实现/未证**，且该需求**只对 RAW fallback（全 stored）路径**有意义；不得套到 comp 流（N/L comp 仅 raw band 的 64.65%/83.10%），不得把 93.75 写成 103.79。
- 生产实现层：现有 b11 导出是 115200 UART（≈11.52 kB/s，guide §2 冻结值，本包未复测），生产 sink/PCIe 未实现；板级 `not_run`。

## 2. 六条强制陈述（逐条带数值与来源）

1. **当前 core + 187.5 MHz 不能闭合自然内容。** N `S_ss=7,475,240` vs G0 6,250,000（**−16.3906%**）、L 6,986,952（**−10.5475%**）；两类 `bottleneck_attribution=core_interval`（N 7,475,238 vs export 3,354,672；L 6,986,951 vs 4,312,600）。来源：`content-verdict-r1.json#/content_classes.{N,L}`、P1 r1b 报告。
2. **A+H 6,008,078 / 2.3179 cycles/B / +4.027% 只是 187.5 MHz 的算术闭合，包络 45.034% → `conditional`；不是 G0 闭合、不是 implemented。** 单 H 6,260,648（−0.17%）仍不够。来源：`coregap-verdict.json#/combinations`、`#/scheme_envelope`、`#/scheme_matrix`、`#/closable_at_187_5`。
3. **仅提时钟 209.6/224.3 MHz 不在 b11 时序能力内。** WNS +0.015 ns @187.5 ≈ 188.0 MHz 上限；224.3 MHz 仅 0.006% 算术余量，D/E 行不是可行路径，必须结构重流水 + TD。来源：`coregap-verdict.json#/scheme_matrix[E]`、P2 r1 报告 §2。
4. **双核不提高 per-stream。** F 行 per-stream 7,476,245 不变（链级 75.684 MB/s），ERAM 231–289/300、时序 `unproven`。来源：`coregap-verdict.json#/scheme_matrix[F]`。
5. **P3：93.75 对实测 comp 有余量（最紧 L@25 ms 86.25，占 92.0%），raw band ≥103.79 未实现/未证，只对 RAW fallback。** 来源：`sink-headroom.json#/comp_stream`、`#/raw_band`、`#/headline`。
6. **用户坚持 1080p30、不降档；需要用户决定：① 投入 core 结构改版（A+H，原型+TD+板级）；② 换核/换算法；③ 接受 `G0_not_closed` 边界。降档需用户明确，本判定不主推。** 来源：P4 放行裁决 §3.1(6)/dev-plan §5（用户指令与规划约束，不是测量）。

## 3. 证据绑定（D1/D7）

三个 manifest 的**全部** artifact 已用本机 Python 3.11 逐文件重算 SHA-256：**P1 70/70、P2 49/49、P3 5/5 全部一致，0 mismatch**（17,204,469 / 494,044 / 60,546 bytes）。明细见 `out/evidence-binding.json`。

| 包 | manifest | SHA-256 | artifacts | 状态 |
|---|---|---|---:|---|
| P1 | `T10.ss-g0-prod-content/r0/manifest-r1.json` | `e306ed42…`（全值见 evidence-binding） | 70 | PASS r1b |
| P2 | `T10.ss-g0-prod-coregap/r0/manifest-r1.json` | `803d3efb…` | 49 | PASS r1 |
| P3 | `T10.ss-g0-prod-sink/r0/manifest-r0.json` | `de8a5cff…` | 5 | PASS r0 |

关键字段的来源指针（逐项）：`S_ss/tail_frac/sink_limited/margin_G0/L_cold` ← `content-verdict-r1.json#/content_classes.{N,L}`；`busy` ← `export_time/S_ss`（同 JSON 的 `export_tail_mean`、`per_frame`）；`A+H/H/包络/conditional` ← `coregap-verdict.json`；`comp/raw band` ← `sink-headroom.json`。P1 r1b 的 4 条负对照（白名单反向重建、`dup` 内容重建、derived/measured 分离、`L_cold` 不进 `S_ss`）见 P1 r1b 报告 §8；P3 的 4 条负对照见其 §6；P2 的负对照见 `out/negative-controls.json`——本包未声称“未做负对照”。

## 4. scope tuple（写死，不外推）

| 维度 | 冻结值 |
|---|---|
| content | P1 自然场景/低照图像派生 Bayer（`natural_scene_image`/`low_light_natural_scene`；`proxy_not_natural_raw`、`not_sensor_raw`、`proxy_not_worst`、`display_referred`）——**非传感器 RAW** |
| pacing | TB `wait_slot_free`（**非生产自由跑**） |
| sink | 93.75 MB/s TB 代理（**非生产 sink**） |
| DDR | 行为级 256-bit PAXI 模型 |
| core/clock | 单核 `a1` @187.5 MHz |
| stream | 单路 |

## 5. 能说 / 不能说

**能说**：在“派生自然内容 + TB slot-free + 93.75 sink”的冻结 scope 内，自然内容 4 帧实测不达 G0，缺口可量化且可复算；core 是主约束，sink 不是；A+H 是有条件（`conditional`）的算术候选；当前 187.5 MHz 单核不能闭合；生产 sink/raw band/DDR/板级仍未实现或未证。

**不能说**：G0 已闭合/`G0_not_closed` 以外的新结论；A+H 已实现或已由 TD/板级证明；自然/全内容/最坏内容通过；真实传感器 RAW、噪声、光学；生产 sink ≥103.79 MB/s；真实 DDR/PAXI/PCIe/UART sustained；板级/bit/Flash；双路；RK/NPU；用 G25 降档；用合成 C1 的旧 `G0_*_for_scope` 覆盖自然内容。

## 6. G25 仅参考

`margin_G25`（N −33.1125%、L −28.438%）只作参考列，**未进 headline、未用于降档**。G25 不是本轮 G0 门槛，也没有改变任何判定。

## 7. 用户决策（不主推降档）

1. **投入 core 结构改版（A+H）**：2-position scan + 2 B/cycle replay 原型；TD/STA @187.5 MHz（209.6 作 fallback，需重流水）；再用 P1 同一 harness/内容做 4 帧 N/L 复测。算术 +4.027%，但包络 45.034%，必须由原型+TD 证明。
2. **换核/换算法**：独立实现任务，自带 TD/板级预算与验收。
3. **接受 `G0_not_closed` 边界**：若产品能接受当前自然内容 25.08/26.84 fps（且仅限声明内容），可冻结该边界。
4. **降档（G25 等）需用户明确授权**；本判定不主推、不预设。

## 8. 剩余风险

- 自然内容仍是图像派生代理：无传感器 RAW、无噪声/光学；L 无噪声注入；最坏/全内容未证。
- A+H 的 45.034% 包络来自**未实现**的 matcher/emit 结构估算；B/C 无 matcher 证据；任何实现需原型 + TD + 4 帧复测。
- 生产 pacing、生产 sink（现有 115200 UART ≈11.52 kB/s）、真实 DDR sustained、板级、双路均未测；本结论只覆盖声明 scope。
- P2 r1 原地覆盖 r0 的 7 个文档（OBS-8）：只能复现 r1，不能声称 r0 文档可复现。
- 本包 0 TD：A+H 的资源/时序、当前 b11 的 WNS 之外的余量均未由本包复核。

## 9. 恢复入口

- Codex：`$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production；本轮目标：<例如：复核 P4 收尾并按用户决定新建 core 改版 run>`
- OpenCode：`/fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production；本轮目标：<同上>`
- 恢复基线：P1 `manifest-r1.json`（`e306ed42…`）、P2 `manifest-r1.json`（`803d3efb…`）、P3 `manifest-r0.json`（`de8a5cff…`）、本包 `manifest-r0.json`。**P2 用 r1，不用 r0**；P1/P2/P3 报告只读、不改写。

## 10. 预算与合规

- 0 次 vsim、0 TD/综合/布线/bitgen/下载/Flash、0 板卡、0 COM/JTAG/RK、0 网络；无批量删除。
- 写范围：仅 `T10.ss-g0-prod-verdict/**`（本包）与 `%TEMP%\opencode\ss-g0-prod-verdict/**`（本次未用）；其余只读。
- 上游候选哈希稳定：三包 manifest 全 artifact 逐文件 SHA 复核 0 mismatch；本包 manifest 冻结后停止修改（`stopped_modifying=true`、`active_commands=0`）。
- 预算：≤25 calls / ≤45 min（实际见 `manifest-r0.json.budget`）；开发不自判 PASS。

## 11. 复现

```powershell
cd D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-verdict\r0
python tools\build_verdict.py verify
# 期望：重算 124 个上游 artifact SHA 0 mismatch；断言六条数值；重写 out/evidence-binding.json、
#       g0-production-verdict.json、commands.jsonl，并重冻 manifest-r0.json（逐字节确定、无时间戳）
```

## 12. D1–D10 自查映射（开发自查，不替代综合测试）

| # | 本包对应 |
|---|---|
| D1 | §3 + `out/evidence-binding.json`：三 manifest 全 artifact SHA 复算、字段级来源指针 |
| D2 | headline=`G0_not_closed`（`g0-production-verdict.json#/headline`） |
| D3 | §2 六条 + JSON `six_statements`（数值/来源逐条） |
| D4 | A+H 只写 `conditional`/算术；`a_plus_h.*` 标记 `implemented=false`、`g0_closure=false` |
| D5 | 时钟/双核/P3 三条边界（§1.3/§1.4/§2-3/4/5） |
| D6 | §4 scope tuple + §5 能说/不能说 + §8 风险 + §9 恢复入口 |
| D7 | P2 绑定 `manifest-r1`（`803d3efb…`），未引用 r0 数值/DIFF |
| D8 | 全文无“G0 已闭合/A+H 已实现”陈述；代理内容不当自然 RAW；未声称板级/真实 DDR/RK |
| D9 | §1.1 `sink_limited` 澄清 + L 重分类 + 原报告不改写声明 |
| D10 | 0 sim/0 TD/0 板卡；写范围仅本包；124 上游 artifact SHA 稳定 + 本包 manifest 冻结 |
