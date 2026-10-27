# T10.ss-g0-prod-sink — lessons r0

只记可复用的根因 / 触发条件 / 修法与验证入口，不记过程流水。

## L1 速率轴 ≠ 帧节拍轴；30 fps 必须用 1/30 s

- **触发**：把 33.33 ms 当精确值算需求，N 会得 50.33 而非冻结的 50.32 MB/s；或把「93.75 够不够」只算一档节拍。
- **根因**：sink 速率（B/s）与帧节拍（每帧在多少 ms 内搬完）是两个独立轴；30 fps = 33.3333 ms，25.0 ms 是 40 fps 轴（=G0 的 0.75 倍预算）。
- **修法**：`need = bytes / period`，period 显式写成 `1000/30 ms` 与 `25.0 ms`；表头标节拍。
- **验证入口**：`model/sink_headroom.py` 断言 `rate30 ∈ 50.32±0.005 / 64.69±0.005`、`rate25 ∈ 67.09±0.005 / 86.25±0.005`；改 period 立即失败。

## L2 93.75 MB/s 在 187.5 MHz 下就是 2 clk/B，`export_cycles=2×bytes` 可当交叉校验

- **触发**：sink 侧只有「MB/s」一个数，容易和 P1 的 evt/`tail_frac` 脱节，无法证明模型没写错。
- **根因**：93.75 MB/s = 187.5e6/2 B/s，所以 `export_time = 2×bytes` 是恒等式；P1 的 `tail = t_exp-t_enc` 正是导出时间。
- **修法**：用 `export_time/S_ss` 复算 `tail_frac`，与 P1 原始 evt 值比；本包 N 0.448771 vs 0.448783、L 0.617236 vs 0.617249（均 <0.01%）。
- **验证入口**：`cross_check.export_over_S_ss` 与 `p1_tail_frac` 并列落 JSON，脚本断言差 <5e−4。

## L3 `sink_limited=true` 是比值旗标，不是「sink 是瓶颈」的资源证明

- **触发**：L 的 `tail_frac=61.72%≥50%` → 冻结规则标 `sink_limited=true`，极易直接写成「L 被 sink 卡住」。
- **根因**：该旗标 = `tail_mean/S_ss ≥ 0.5`，只说明导出占稳态间隔的比例大；导出的**绝对值**仍小于 core 间隔（4,312,600 vs 6,986,951，1.62×）。
- **修法**：任何 sink 结论都要同时给「导出 vs core_interval」两个绝对拍数；只有导出 ≥ core 间隔时才能说 sink 约束。
- **验证入口**：C5 断言 N/L `export_cycles < mean_core_interval` 且 `bottleneck_primary=core_interval`；负对照 `SINK_LIMITED_AS_SINK_BOUND`。

## L4 raw band 只对「全 stored / RAW fallback」成立；comp 流已含 stored 块

- **触发**：拿 2,594,706 B 去算 comp 需求，N 会从 50.32 虚增到 77.84 MB/s（+54.69%），在 25 ms 档还会伪造出 103.79>93.75 的「comp 不足」。
- **根因**：comp 流的 stored 块字节已经计入 `exp_bytes`；raw band 是「整帧不可压、全部按 RAW 过 sink」的上界，实测 comp 只有 raw band 的 64.65%（N）/83.10%（L）。
- **修法**：JSON 分 `comp_stream` 与 `raw_band` 两段，raw band 段写死 `applied_to_comp_stream=false`；stored 字节只作上下文并标来源。
- **验证入口**：负对照 `RAW_BAND_AS_COMP_STREAM` 自检 `comp bytes != RAW_BAND_BYTES`，comp 行只读 `per_frame.exp_bytes`。

## L5 93.75 与 103.79 是两档不同速率，勘误后仍有两个等价值

- **触发**：把 93.75 写成 103.79（或混用 4,687,500 与 4,687,421），会少算 raw band 501,912 cycles（G0 的 9.67%）并抹掉 25 ms 的 10.71% 缺口。
- **根因**：103.79 是 2,594,706 B/25.0 ms 的取整；精确值 103.78824 → 恰好 4,687,500 cycles；用取整速率反算得 4,687,421 cycles。两者差 79 cycles（0.0017%），百分比同为 75%。
- **修法**：主表用精确速率 + 冻结 4,687,500，另列取整等价值并注明差异；速率名写进字段名（`93.75_TB_SINK` / `103.79_RAW_25ms`）。
- **验证入口**：断言 `cycles_for(raw,93.75)=5,189,412`、`=4,687,500 @103.78824`、`≈4,687,421 @103.79`；负对照 `93_75_SINK_AS_103_79`。

## L6 93.75 是 TB 代理，生产 sink 仍是未实现项（且现有 UART 差 4 个数量级）

- **触发**：P1 在 `SINK=1` 下跑出干净 4 帧，容易把「93.75 够用」误读成「生产 sink 已解决」。
- **根因**：93.75 是 TB 里 `clk_uart=2 GHz/UART_DIV=1` 的代理上限；b11 生产 top 现有导出是 115200 UART ≈11.52 kB/s（guide §2），比 N comp 30 fps 需求低约 4,368×。
- **修法**：报告分「模型 / 生产实现 / 板级」三层，生产层只写 `not implemented / not proven`，不因模型有余量而升级生产结论。
- **验证入口**：JSON `production_sink_implemented=false`、`model_only=true`、`evidence_rounds={vsim:0,td:0,board:0,network:0}`；负对照 `MODEL_AS_RTL`。

## L7 0-sim 模型也要「可复算 + 失败即停」，否则无法被独立测试

- **触发**：纯算术包若只交一张表，测试者只能读数字，不能复现；改一个输入也无人发现。
- **根因**：模型的价值在「输入字节 → 结论」的确定映射，而不是结论本身。
- **修法**：脚本内 `check()` 断言全部冻结值与 C1–C7 + 负对照自检；`--manifest` 模式要求重算文本与已冻结 JSON 逐字节相同才允许冻结（否则 rc=2）。
- **验证入口**：`python model/sink_headroom.py`（重写 JSON）→ `--manifest`（比对后冻结）；任何数字漂移都会在比对/断言处失败。
