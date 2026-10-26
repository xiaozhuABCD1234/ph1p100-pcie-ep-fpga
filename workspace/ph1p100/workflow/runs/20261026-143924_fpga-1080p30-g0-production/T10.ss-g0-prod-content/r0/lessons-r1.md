# lessons — T10.ss-g0-prod-content r1（round1，harness 看门狗 + 自然内容实测）

只记可复用的根因/触发/修正/验证入口。

## L1 冻结 TB 的 `WD_LIMIT` 会系统性误杀"难内容"；两段式看门狗是正解

- 根因：`WD_LIMIT` 用 `last_exp_t`（初值 0）作锚，`localparam` 不可 `-g` 覆盖 → 实际语义是"复位后 12M cycles 内必须完成**首帧导出**"，把冷启动和 6.25M 稳态门槛混在一起。
- 修法（本包已验）：`WD_LIMIT_COLD=20,000,000` 锚 `t_sof(1)`（仅 `st_exp==0`）；`WD_LIMIT=12,000,000` 锚 `last_exp_t`（仅 `st_exp>0`）；两者都 `pass=0`/partial。实测 N 首帧导出 12,440,157、L 12,901,635，20M 余量 61%/55%。
- **验证方式**：不要靠人眼看 diff。写一个 `canonical_reconstruct`——取冻结原文，只应用白名单里的字面替换，再与候选文件**逐字节比较**。本包 `whitelist_ok=true`，任何越界改动都会立刻失败。
- 复用：凡是"冻结 harness 的活性守卫/超时/看门狗"与内容难度耦合的，先算 `t_exp(1)` 下界（`t_enc(1)+2×stream_len`）再决定是否要新 TB。

## L2 `st_dup_words` 不是"重复读"，是"相邻 256-bit 原字逐位相同"——`dup=0` 是合成内容才成立的隐含假设

- 源码：`a1_ddr_slot_store.v:281-282`
  `if (rd_prev_v && (ddr_rdata === rd_prev)) st_dup_words <= st_dup_words + 1;`
  它统计的是**数据相等**，不是地址重复、不是重传、不增加流量、不影响正确性。
- 合成 C1（32:1 梯度）/C2（stored rand）永远 `dup=0`；自然图像有大片平坦区 → N 3,896（0.7516%）、L 568（0.1096%）。
- 后果：冻结 TB 的 `ss_pass` 表达式与 A3/guide §3 的有效性子句都含 `dup=0`，于是"内容真实"反而把 run 判成 `pass=0`。
- 复用规则：**做内容类任务前，先逐项审 `ss_pass`/验收表达式里有哪些"只有合成内容才成立"的隐含假设**（本包踩了两个：`last_exp_t` 冷启动、`dup=0`）。这类冲突要走规划裁决（harness 层），不能在开发侧自行豁免或改门槛。

## L3 自然内容的瓶颈是核间隔，不是 sink（实测，不再是推导）

- `S_ss`：N 7,475,240（25.083 fps / 65.015 MB/s）、L 6,986,952（26.836 fps / 69.558 MB/s）→ G0 +19.60% / +11.79%。
- `bottleneck_attribution`：N core_interval 7,475,238 vs export_time 3,354,672（2.23×）；L 6,986,951 vs 4,312,600（1.62×）→ 两类都是 **core-bound**。
- 压缩流自身的 sink 需求只有 50.32/67.09（N）、64.69/86.25（L）MB/s，**都在冻结 93.75 以内**；L 的 `sink_limited=true` 是 4.31M tail 相对 6.99M 间隔造成的，但把 sink 提到 103.79 也只能把 tail 降到 ~3.9M，core_interval 6.99M 仍 > 6.25M。**"提高 sink"不能救自然内容的 G0。**
- 对照：P4 合成 C1 的 `S_ss` 4.678M（1.34× 余量），说明差距来自内容本身（压缩比 1.545/1.202 vs 31.72）。

## L4 4 帧同图 ⇒ `S_23 == S_34`（spread 0–6 cycles），稳态窗口干净但不是时域建模

- 每帧字节 k≥2 完全相同（N 1,677,336 ×3；L 2,156,300 ×3），`S_ss` 无抖动，可逐值复算。
- 但"同图重复"**不代表 30 fps 真实视频**（场景切换、运动、曝光变化都会改变压缩比）。报告必须把"4 帧同图"写成覆盖缺口，不得用它外推全内容。
- 复用：同图重复只适合测"稳态吞吐上限"，不适合测"内容分布/最坏帧"。

## L5 `kind=exp` 加一个 `bytes=st_expb` 就让"逐帧 exp_bytes"可测

- r0 没有 exp 完成事件 → 只能从导出头拿首帧 `stream_len`；r1 在 `SS_EVT kind=exp` 末尾加 `bytes=%0d`（累计值），即可算 `bytes(k)=cum(k)-cum(k-1)`、`compression_ratio(k)`、`export_time(k)=2×bytes(k)`，无需 `CAPTURE=1` 的 MB 级 dump、无需改 stats 格式。
- 这是"最小可观测性改动"的高性价比范例：只加只读字段，不动其它字段/顺序（旧解析正则 `t=.. kind=.. frame=.. n=..` 仍然命中）。

## L6 时间预算实测（用于后续派发估算）

- 速率：12.0M cycles ≈ 711 s（16.9k cycles/s）；34.9M cycles ≈ 1962 s（17.8k cycles/s）；33.9M ≈ 1802 s。
- 自然内容 4 帧 ≈ 33.9–34.9M cycles ≈ **30–33 min/次**（两次 62.7 min）。request 里"单次约 22 min"只适用于 P4 的 ~27M-cycle run；给 95 min vsim 墙钟是对的，2700 s 单次硬超时余量 27%。
- 复用：`-gMAX_CYCLES` 必须 ≥ 4×S_ss + L_cold（本包 60M 足够，实测用 34.9M，未触发 `B11_FULL_TIMEOUT`）。

## L7 回归基线（下次改 harness 后先比这几个数）

两次 run 的 `t_sof/pub/cam_end` 与 r0、P4 **逐周期相同**（61 / 1,607,996 / 1,608,249；1,608,650 / 3,216,585 / 3,216,838）。任何"改了 harness 但采集时序变了"的情况，第一处就会在这里暴露。
