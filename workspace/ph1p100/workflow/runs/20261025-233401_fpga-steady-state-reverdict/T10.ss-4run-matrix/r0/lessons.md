# lessons — `T10.ss-4run-matrix`（P4）

只记可复用的根因/触发/修正/验证入口，不重复报告数字。

## 1. 新 TB 的可信度用“同内容同配置逐值复现”锚定

- 触发：从 P3 TB 派生 P4 TB 后，4 个 run 的 G0 结论都依赖新 TB 的行为等价性。
- 做法：R4 完全复用 P3 R3 的 `CONTENT=1 / slot-free / SINK=1 / CAPTURE=0 / FRAMES=4` 与同一 `comp_raw.hex`/`comp_vec.hex`；把 `S_ss`、`exp_bytes`、`cycles`、`SS_VEC_MATCH`、header CRC 同时作为对照。
- 结果：`S_ss` delta 0 cycles、`exp_bytes`/`cycles` 与 P3 `r3_frozen.stats` 完全相同。
- 复用：派生 TB 的 trust anchor 应选“同内容 + 同模式 + 同 sink”的已有冻结 run，并把 ±0.5% 门槛之外再加 stats 逐值比较；只比 `S_ss` 会漏掉内容/计数映射错误。

## 2. `SINK=1` 的 2 GHz 请求不等于 187.5/200 MB/s

- 触发：P3/P4 的 `SINK=1` 用 2 GHz `clk_uart`，易被误读为“200 MB/s 已达成”。
- 根因：`a1_uart_export` 的 holding-register 交接是 **2 `clk_a1`/B**，与 `clk_uart` 无关；a1 域上限 = 187.5/2 = **93.75 MB/s**。
- 验证入口：`measured_export_MBps = payload_per_frame / (min(tail, S_ss)/187.5e6)`；四 run 均 93.70–93.75，R3 为 93.748。
- 复用：报告必须写“实测导出率”，不能写“请求 2 GHz/200 MB/s”；生产 sink 需求另列。

## 3. `tail > S_ss` 可能是 2 CMP 槽流水，不是负 tail

- 触发：R3 `export_tail_mean=5,700,448` > `S_ss=5,189,503`（109.85%）。
- 根因：`tail(k)=t_exp(k)-t_enc(k)`；当 sink 饱和且有两个 CMP 槽时，`t_enc(k)` 早于 `t_exp(k-1)`，tail 包含等待上一帧导出的时间。
- 正确口径：sink 饱和时用 `S_ss`（或 `min(tail,S_ss)`）算导出率，并同时报 tail 比例与 `sink_limited`；不要用 `S_ss - tail`（会得到负数）。
- 复用：`sink_limited` 判据（tail ≥50% `S_ss`）仍成立，但解释必须区分“导出串行时间”与“流水等待”。

## 4. 内容锚点差 1 个数量级，G0 结论不能跨内容外推

- 触发：C1 全帧 raw 高度可压缩（81,707 B/帧，31.7:1）→ `S_ss=4.678M`；comp proxy（848,864 B/帧，3.05:1）→ `5.928M`（+26.7%）；C2 stored（2,594,706 B/帧）→ sink 支配。
- 根因：链级 `S_ss` 由 core 工作与导出/tail 共同决定；压缩率改变 payload 与 core 行为。
- 复用：一个 content anchor 的 G0 margin 只能用于该内容 scope；报告必须并列 `full_frame_raw_synthetic`/`proxy_not_worst`，禁止写“全内容/自然图像”。

## 5. strict-serial 的代价含相机串行化，是上界

- 触发：R2−R1 = 1,771,435 cycles（37.865%），约等于相机帧驱动 1.607M + 164k。
- 根因：strict-serial 在上一帧 `st_exported` 后才开始下一帧驱动，代价不只是 tail，还包括相机/驱动的串行化。
- 复用：R2−R1 只能标为 pacing penalty 的**上界**；纯 tail 成本需另设“只延后 export、不延后采集”的实验。

## 6. raw40 映射的强证据是 DUT header CRC，不是 TB 自己比自己

- 触发：`SS_RAW_MATCH` 从 `tap_pix` 重建再与 `raw_mem` 比较，数学上是恒等，不能单独证明源文件/映射正确。
- 有效证据链：
  1. Python `raw.bin → raw40.hex → 解码回 bytes` mismatch 0；
  2. TB `SS_RAW_MATCH` 证明位序/ROI 索引/40-bit 无截断、`checked=518400`；
  3. DUT 导出帧头 `raw_len=2,592,000`、`raw_crc=zlib.crc32(raw.bin)`、`xform_crc=crc32(transform_frame(raw.bin))` 逐值相等。
- 复用：以后做 raw/像素注入，优先让 DUT 自己算 CRC 并与 Python 期望比；TB 自检只作辅助。

## 7. 算术过线不等于 G0：sink-limited 的 `S_ss` 是服务率

- 触发：R3 `S_ss=5,189,503 < 6,250,000`，若只看算术会误判 G0 过。
- 根因：该 `S_ss` 等于 2,594,706 B × 2 `clk_a1`/B 的导出时间（5,189,412 cycles），是 sink 的服务间隔，不是 DUT 服务能力。
- 复用：先判 `sink_limited`（tail ≥50% `S_ss`），再判 G0；sink-limited 值只能给 `G0_not_proven`，并单列生产 sink 需求。

## 8. 预算与工具

- 4 个全尺寸 4 帧 run 墙钟 79.0 min（940/1088/1384/1330 s）；单次 2700 s 足够，R3（stored 大 payload）最慢。
- 预检（FRAMES=1、2M cycles）86 s 能在投入 4×20 min 前抓出 `+RAW40`/自检/编译错误；建议保留这一步。
- ModelSim 的 21 条 warning 全部来自冻结 DUT 的未连接可选状态口（P1/P3 相同），不是新 TB 引入；不要把它们当成本轮回归。
