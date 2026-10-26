# T10.ss-g0-prod-sink — r0 结果（0-sim sink / transport headroom 模型）

- task_id：`T10.ss-g0-prod-sink`；round：**0（首次）**；新开发会话（未复用 P1/P2）
- 状态：**ready_for_test**（开发侧完成，待独立综合测试 round0；本文件不宣称 PASS）
- 证据：**0 sim / 0 TD / 0 板卡 / 0 网络**；纯算术 + P1 r1b 实测字节
- 候选目录：`.../T10.ss-g0-prod-sink/r0`；复算入口 `model/sink_headroom.py`，账本 `out/sink-headroom.json`
- 上游绑定（只读，逐文件 SHA256）：P1 `manifest-r1.json` `e306ed42…`、`content-verdict-r1.json` `b92f84b5…`、P1 r1b 报告 `4cae5fc4…`、P2 r0 报告 `eb4e9bd4…`、`p2-obs-ruling.md` `ee9dd20f…`、`fpga-design-guide.md` `bb9bf405…`、`dev-plan.md` `f64586da…`
- **一句话结论**：冻结 **93.75 MB/s** sink 对 P1 实测 comp 流在 **33.3333 ms 和 25.0 ms 两档都还有余量（最紧 L 为 +8.69%）**，且两类的 `core_interval` 都大于导出时间 → **sink 不是 P1 的瓶颈**；**raw band ≥103.788 MB/s 生产 sink 未实现/未证**，它**只对 RAW fallback（全 stored）路径有意义**，在 25.0 ms 预算下 93.75 短 **10.7075% / 2.676864 ms**。

## 1. 口径与冻结常量（先分清速率轴与帧节拍轴）

| 项 | 冻结值 | 说明 |
|---|---|---|
| `clk_a1` | 187.5 MHz（5.333 ns） | 与 P1 一致 |
| G0 窗口 | 6,250,000 cycles = 33.3333 ms | 30 fps；**不得截断成 33.33 ms** |
| 25.0 ms 窗口 | 4,687,500 cycles | 40 fps / 25% 余量轴 |
| `SINK=1` 冻结 TB 代理 | 93.75 MB/s = 2 clk_a1/B = 0.5 B/clk | **TB 代理上限，不是生产 sink** |
| raw band | 2,594,706 B/帧（payload 2,592,000 + 2,706 B framing） | 全 stored / RAW fallback 最坏带 |
| raw band @25.0 ms | **103.78824 MB/s**（精确）；取整 103.79 → 4,687,421 cycles 等价值 | guide §3 勘误：冻结 4,687,500 cycles / 75.0% |
| N comp 稳态 | 1,677,336 B/帧（帧 2–4；帧 1 为 1,677,912） | P1 `exp_bytes` 实测 |
| L comp 稳态 | 2,156,300 B/帧（帧 2–4；帧 1 为 2,156,868） | P1 `exp_bytes` 实测 |

> 速率轴（sink 每秒能搬多少字节）与帧节拍轴（33.3333 ms vs 25.0 ms 内要搬完一帧）必须分开算；本包所有表都显式标了所用节拍。

## 2. comp 流需求账（C1/C2：P1 实测字节，不用 P4 comp 代理）

| 类 | 稳态 B/帧 | 压缩比 | 33.3333 ms → MB/s | 占 93.75 | 25.0 ms → MB/s | 占 93.75 | 93.75 余量（30 fps / 25 ms） | 导出 cycles | 导出 ms | %G0 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| N | 1,677,336 | 1.5453:1 | **50.32008** | 53.67% | **67.09344** | 71.57% | +86.31% / **+39.73%** | 3,354,672 | 17.8916 | 53.67% |
| L | 2,156,300 | 1.2021:1 | **64.68900** | 69.00% | **86.25200** | 92.00% | +44.92% / **+8.69%** | 4,312,600 | 23.0005 | 69.00% |

- 四档需求 **全部 < 93.75 MB/s** → 冻结 sink 对实测 comp 路径**有余量**；最紧点是 L 在 25.0 ms（86.252 vs 93.75，余量 8.69%）。
- `export_cycles = 2 × bytes` 是 93.75 MB/s 在 187.5 MHz 下的恒等式，因此 comp 导出与 P1 的 `tail` 可直接互校（见 §4）。
- 若按 P1 **实测** `S_ss` 折算，comp 流实际只需 N **42.0723**、L **57.8659 MB/s**（`S_ss` 被 core 拉长），距 93.75 更远。

## 3. 三档账 + raw band 单列（C1/C2/C7）

### 3.1 三档 sink 账

| 档 | MB/s | B/clk_a1 | raw band cycles | raw ms | raw %G0 | N comp cycles / ms | L comp cycles / ms | 性质 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 冻结 TB 代理 | **93.75** | 0.5 | **5,189,412** | **27.676864** | **83.0306%** | 3,354,672 / 17.8916 | 4,312,600 / 23.0005 | TB `SINK=1` 上限；**非生产** |
| raw band @25 ms | **103.78824**（取整 103.79） | 0.553537 | **4,687,500** | **25.000000** | **75.0000%** | 3,030,213 / 16.1611 | 3,895,492 / 20.7760 | 目标需求；**生产 sink 未实现/未证** |
| 原生参考 | 187.5 | 1.0 | **2,594,706** | **13.838432** | **41.5153%** | 1,677,336 / 8.9458 | 2,156,300 / 11.5003 | 1 B/clk 参考轴，非已定义 sink |

- 取整口径：103.79 MB/s 等价值 **4,687,421 cycles**（与冻结 4,687,500 差 79 cycles，占比 0.0017%；百分比仍 75.0%，不改变任何结论）。本包主表一律用**精确** 103.78824，未混用两种口径。
- 三档的 `%G0` 分别为 **83.0306% / 75.0000% / 41.5153%**，与 dev-plan §3、guide §3 冻结值逐值一致。

### 3.2 raw band 单列（C7：只对 RAW fallback / 全 stored）

| 项 | 值 | 判读 |
|---|---:|---|
| 30 fps 需求 | **77.84118 MB/s** | 93.75 **可满足**；占用 27.676864 ms / 33.3333 ms，余 5.656469 ms（16.97%） |
| 25.0 ms 需求 | **103.78824 MB/s** | 93.75 **不足**：5,189,412 vs 4,687,500 cycles = **+10.7075%（+501,912 cycles）/ +2.676864 ms** |
| 187.5 档 | 2,594,706 cycles / 13.838432 ms | 41.5153% G0，仅作参照 |

- **适用性**：raw band 只在「整帧必须以 RAW 字节过 sink」时成立（不可压内容 → 全 stored fallback）。实测 comp 流本身已包含 stored 块字节：N stored 398,400 B（占 1,677,336 的 23.75%）、L 1,008,000 B（占 2,156,300 的 46.75%）（来源 P2 r0 探针计数器，同一 P1 N/L 内容，**仅作上下文、不参与任何 C1–C7 计算**）。
- 因此 **不得**把 raw band 需求套到 comp 流：comp 实际字节只有 raw band 的 N 64.65% / L 83.10%。

## 4. 与 P1 的交叉核对（证明模型不是自说自话）

| 核对 | N | L | 结论 |
|---|---|---|---|
| 模型 `export_time/S_ss` | 0.448771 | 0.617236 | 与 P1 原始 evt 复算的 `tail_frac` **0.448783 / 0.617249** 差 −1.2e−5 / −1.3e−5（<0.01%） |
| `export_time` vs `core_interval` | 3,354,672 vs 7,475,238（**0.449×**） | 4,312,600 vs 6,986,951（**0.617×**） | 两类均 `bottleneck_primary=core_interval`（P1 A3b 同值） |
| P1 `sink_limited` | false | **true**（tail_frac 61.72% ≥ 50%） | L 的 true 是**比值门槛旗标**，不是「sink 约束」的资源证明 |

- **`sink_limited` 语义必须写清**：L 因 `tail_frac=61.72%≥50%` 被冻结规则标成 `sink_limited=true`，但导出 4,312,600 **仍小于** core 间隔 6,986,951（1.62×）。若只看 61.72% 就断言「L 被 sink 卡住」是错的——这正是负对照 `SINK_LIMITED_AS_SINK_BOUND` 要挡的误读。
- **C5：不改变 G0**。P1 数值原样引用、未重算、未改档：N `G0_not_closed` −16.3906%（`S_ss` 7,475,240）、L `G0_not_proven` −10.5475%（`S_ss` 6,986,952）、headline `G0_not_proven`。本包只增加「sink 有余量」这一条**非 G0** 证据，不产生任何新的 G0 证据；把 sink 提到 103.79 **也不会**让 N/L 闭合，因为两者 core_interval 单独就已 > 6.25M。

## 5. 三级边界（模型 / 生产实现 / 板级）

| 层 | 本包结论 | 依据 | 不得声称 |
|---|---|---|---|
| **模型层** | 93.75 对实测 comp 两档均有余量；raw band 25 ms 需 103.788、93.75 短 10.71%；三档账可复算 | 本包算术 + P1 实测字节（0 sim） | 不是 RTL 行为、不是时序、不是吞吐实测 |
| **生产实现层** | 生产 sink **未实现、未证**；93.75 只是 TB 代理。b11 生产 top 现有导出为 `a1_uart_export` + 115200 UART ≈ **11.52 kB/s**（guide §2 冻结值，本包未复测），比 N comp 30 fps 需求低约 4,368× | guide §2；P1/P2 冻结件 | 不得称生产 sink 已实现 / 已证 ≥103.79 / 已满足 1080p30 |
| **板级层** | `not_run`：无 DDR/PAXI sustained、无 PCIe/UART 实测、无稳定性、无最坏内容 | 0 板卡 / 0 网络 | 不得把模型或 TB 结果外推为板级带宽 |

- 生产层还有一个常被忽略的事实：**即使 sink 无限快，P1 的 N/L 仍不达 G0**（core 7.475M / 6.987M > 6.25M）。sink 是本轮**非瓶颈**项，生产 transport 是**未实现**项，两者不能混为一谈。

## 6. 负对照（4 条，含机制、反例数值与拒绝方式）

| id | 陷阱 | 反例数值（本包如何暴露） | 拒绝机制 |
|---|---|---|---|
| `93_75_SINK_AS_103_79` | 把冻结 93.75 当成 103.79（或反之） | 93.75 → 5,189,412 cyc / 27.676864 ms / 83.0306%；103.78824 → 4,687,500 / 25.0 / 75.0%。替换会少算 **501,912 cycles（G0 的 9.67%）** 并抹掉 10.71% 缺口 | 每档速率单独成行、字段名带速率；断言 5,189,412 ≠ 4,687,500 |
| `RAW_BAND_AS_COMP_STREAM` | 把 raw band 2,594,706 B 套到 comp 流 | comp 实为 1,677,336 B（64.65%）/ 2,156,300 B（83.10%）；替换后 N 需求 50.32 → 77.84 MB/s（+54.69%），并在 25 ms 凭空造出 103.79>93.75 的「comp 不足」 | comp 行只用 `exp_bytes`；raw band 只出现在 `raw_band` 段且标 fallback |
| `MODEL_AS_RTL` | 把算术模型当成已实现/已证的生产 sink | 0 sim / 0 TD / 0 板卡；无 RTL、无综合、无 DDR/PCIe 模型 | JSON `production_sink_implemented=false`、`model_only=true`、scope 冻结 |
| `SINK_LIMITED_AS_SINK_BOUND` | 因 L `sink_limited=true` 就称 sink 是 L 的瓶颈 | L 导出 4,312,600 < core 6,986,951（1.62×）；N 0.449× | C5 用两个不等式绑定，`bottleneck_primary=core_interval` 取自 P1 |

## 7. 复现、命令与预算

```text
cd .../T10.ss-g0-prod-sink/r0
python model/sink_headroom.py            # rc=0；重写 out/sink-headroom.json（确定性，无时间戳）
python model/sink_headroom.py --manifest # rc=0；校验 JSON 逐字节等于本次输出后冻结 manifest-r0.json
```

- Python 3.11.5，仅标准库；所有断言（C1–C7 + 4 条负对照自检）失败即 `RuntimeError` 非零退出，不产出「半套账」。
- 预算：**0 次 vsim / 0 TD / 0 板卡 / 0 网络**；调用与墙钟见 `manifest-r0.json.budget`（上限 20 calls / 25 min）。
- 复算一致性：`--manifest` 模式要求重算文本与已冻结 JSON **逐字节相同**，否则 rc=2 拒绝冻结。

## 8. 未测 / 不可外推

- 任何生产 sink 实现（含 ≥103.79 MB/s）、生产 UART/PCIe sustained、真实 DDR/PAXI sustained、板级 sink 行为与稳定性、硬件上的 raw band 时序、以及「提高 sink 能闭合 G0」——**均未测、未证**。
- 内容仍是 P1 的 `natural_scene_image` / `low_light_natural_scene` 派生 Bayer（`proxy_not_natural_raw`、`not_sensor_raw`、`proxy_not_worst`），不是传感器 RAW；pacing 是 TB `wait_slot_free`，不是生产自由跑；DDR 是行为级 256-bit PAXI。

## 9. 给 P4 的可引用结论（逐条带证据）

1. **sink 不是 P1 的瓶颈**：comp 导出 0.449×/0.617× core_interval，P1 归因 `core_interval`；G0 缺口只能由 core 侧解决（C5）。
2. **93.75 对实测 comp 有余量**：33.3333 ms 需 50.32/64.69 MB/s，25.0 ms 需 67.09/86.25 MB/s，全部 <93.75；最紧 L 余量 8.69%（C1/C2）。
3. **raw band 单列**：25.0 ms 需 103.788 MB/s，93.75 短 10.7075%/2.676864 ms；30 fps 需 77.841，93.75 可满足（C2/C7）。
4. **≥103.79 MB/s 生产 sink 未实现/未证**，只对 RAW fallback（全 stored）有意义；**不得把 93.75 写成 103.79**，**不得把 raw band 需求套到 comp 流**（C3/C7）。
5. **G0 不变**：N `G0_not_closed` −16.3906%、L `G0_not_proven` −10.5475%、headline `G0_not_proven`；本包不新增 G0 证据（C5）。
