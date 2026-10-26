# 用户小结：1080p30 G0 收口 + 四轮矩阵（`20261025-233401_fpga-steady-state-reverdict`，finished）

## 一句话

按你的边界——**G0（1080p30 per-stream 77.76 MB/s / 6.25M cycles）是硬门槛，25% 只作参考、不降档**——本轮先证明了 b6 的 6.421M 是冷启动延迟（4 帧稳态 4.677M），再用 **4 个不同条件的全尺寸 4 帧矩阵**把 G0 收窄到可以负责的范围：**C1 全帧合成 raw 在 slot-free 下 G0 +33.6%，comp 代理 slot-free +5.43%**；**strict-serial 掉到 −3.09%**（slot-free 是必要条件）；**不可压缩 raw band 被 93.75 MB/s 仿真 sink 限速，G0 不能判**。自然图像/全内容/双路/板级仍未证。

## 四个包做了什么

1. **P1**：同一冻结 RTL/TB 下跑 4 帧，证明 6.421M 是**冷启动单帧**；梯度稳态 `S_ss=4,677,535` → 103.9009 MB/s。
2. **P2**：上一轮“1080p30 infeasible”撤回/降级为 `not_proven`；0%/25% 分列；A1/A2/A3、DDR 5,332/6,400、UART、双核 per-stream。
3. **P3**：只看 G0，comp 代理 slot-free `5,928,286` → 81.98 MB/s、+5.43%；经历 r0 FAIL→r1 metadata FAIL→**r2 PASS**（实际修复 2 轮）。
4. **P4**：4 个不同条件的全尺寸 4 帧矩阵（R1 C1 slot-free、R2 C1 strict、R3 C2 rand slot-free、R4 comp 对照）；r0 **PASS**。

## 四轮矩阵（P4，全部实测）

| run | 内容 | 流水 | `S_ss` | 结果 |
|---|---|---|---:|---|
| **R1** | C1 `f1080p_p1d1` 全帧合成 raw（81,707 B/帧） | slot-free | **4,677,970** | 40.0815 fps / 103.891 MB/s / **G0 +33.605%** → 过（scope 内） |
| **R2** | C1 同 R1 | strict-serial | **6,449,405** | 29.0724 fps / 75.356 MB/s / **G0 −3.092%** → 不过 |
| **R3** | C2 `f1080p_rand` 全帧 raw（2,594,706 B/帧） | slot-free | 5,189,503 | tail 109.85% → **sink_limited** → **`G0_not_proven`**（算术 +20.4% 是 sink 服务率，不是容量） |
| **R4** | comp 代理（848,864 B/帧） | slot-free | **5,928,286** | 31.628 fps / 81.980 MB/s / **G0 +5.427%** → 过（复现 P3，Δ=0） |

- **R2−R1 = 1,771,435 cycles（37.87%）**：strict-serial 的代价（含相机串行化，是上界）；**slot-free 是 G0 的必要条件**。
- **R3**：冻结 TB 的 sink 上限 **93.75 MB/s**（2 clk/B）；raw band 每帧 2,594,706 B 的导出时间几乎等于 `S_ss`，所以 tail 109.85%、`sink_limited=true`，**不能判 G0**。生产 sink 需求：**≥77.84 MB/s（G0）/ ≥103.79 MB/s（25 ms）**，目前 `not_proven`。
- **R4** 与 P3 R3 逐值相同（Δ=0 cycles；测试者独立重跑 1,234 s 也 Δ=0），说明新 TB 可信。
- 预算：4 次全尺寸共 **79.0 min ≤120**；0 TD/板卡；P4 manifest `d353c61a…`，68 artifacts。

## 最终 headline 与 scope（已收窄）

**`G0_feasible_for_scope`**，范围是：

- 内容：**C1 全帧合成 packed RAW10**（`f1080p_p1d1`）或 **P3 comp 代理**；C2 rand raw band **`G0_not_proven`**；全是 `full_frame_raw_synthetic` / `proxy_not_natural` / `proxy_not_worst`。
- 流水：**slot-free / overlapped**；strict-serial 只作保守视图（R2 不过）。
- sink：**实测 93.75 MB/s 冻结仿真 sink**；对 C1/comp 不限速；raw band 生产需求 ≥77.84/103.79 MB/s 仍 `not_proven`；93.75 不能写成 ≥103.79。
- DDR：行为 256-bit PAXI；单核单路、**187.5 MHz**、per-stream；无 TD/板级。

## 能说 / 不能说

**能说**

- C1 全帧合成 raw slot-free：**G0 +33.605%**；comp 代理 slot-free：**G0 +5.427%**（R4 复现 P3）。
- **slot-free 是必要条件**：strict-serial R2 **−3.092%**，R2−R1 **1,771,435**。
- **sink 是第二约束**：R3 `sink_limited` → `G0_not_proven`；生产 sink 需 ≥77.84（G0）/ ≥103.79（25 ms）。
- P1 的 6.421M 是冷启动；P2 的 infeasible 口径已撤回/降级。

**不能说**

- 不能说自然图像/全内容/最坏 1080p30 已过（内容全是合成/代理）。
- 不能说 strict-serial C1/comp 过 G0（R2 不过；P3 comp serial 只是 assumed）。
- 不能说 C2 rand raw band G0 过（R3 是 sink 限速，算术 +20.4% 不算）。
- 不能说双路 1080p30 已过（`c2s2=C` 只是假设，共享 PAXI/时序未证）。
- 不能说 93.75 MB/s 对 raw band 足够 / 生产 sink ≥103.79 已实现 / 板级、真实 DDR、PCIe、RK 已通。

## 还差什么

1. **真实自然/低照/噪声/最坏内容 4 帧**（最高优先）：现在只有合成 C1/C2 与 comp 代理，A2 仍是外推。
2. **生产 slot-free 实现**：R1/R4 是 TB slot-free，真实 CMP 槽所有权/pacing 还没做；R2 只是上界。
3. **生产 sink ≥103.79 MB/s**：冻结 TB 上限 93.75；raw band tail 27.7 ms（83%）；PCIe 未做。
4. **双核共享 PAXI/资源/时序**：231/289、4 客户仲裁、Routed 未证。
5. **b11 1176 读停点/板级**：H2/H4 未定，本 run 不碰板卡。
6. **真实 DDR sustained/刷新/仲裁/RK**：行为模型，0 TD/板卡/RK。

## 下一步怎么开始

**只读回看本 run**：

```text
使用 fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict；本轮目标：读取 P4 manifest-r0 与 r0 integrated 报告，确认 G0_feasible_for_scope 的收窄 scope 与剩余风险；不重跑、不改 P1/P2/P3/P4 冻结件。
```

**建议的新一轮（真实/最坏内容 + 生产 sink）**：

```text
执行：在 run 20261025-233401_fpga-steady-state-reverdict 的 P4 基础上，用真实/自然图集或全帧不可压缩内容做 1080p 4 帧链级稳态锚点（同 b11 几何/冻结 RTL/slot-free；sink 用可证明 ≥103.79 MB/s 的 fast sink 或记录 raw-band tail），替换/校准 A2/C2，并按 G0 硬门槛（77.76 MB/s / 6.25M cycles）重判 1080p30；只做 FPGA 侧离线仿真/模型，TD/综合/布线/bitgen/下载/Flash/板卡/COM/JTAG=0；先给范围、冻结输入与有界仿真预算。
```

## 边界与过程

- 本 run 0 次 TD/综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/PCIe；没有上板、没有真实 DDR/RK。
- 未改 `workflow/tasks.json`；T10 仍 active/blocked，不置 done；P1/P2/P3/P4 冻结件未改。
- 过程：P4 r0 一轮 PASS；P3 实际修复 2 轮；P2 开发/测试调用超预算（约 58/50 vs 35/30）；P4 测试者约 45 calls（墙钟 55 min，调用超 35，已披露）；P4 另有 4 条非阻断披露（预检 pass=0、TEMP 调试脚本、xform_crc 未独立重实现、raw band 2,594,750 vs 2,594,706）。
