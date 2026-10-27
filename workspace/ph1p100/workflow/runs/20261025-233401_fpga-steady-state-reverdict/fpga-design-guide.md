# FPGA 设计冻结：P2 稳态锚点复核（实测锚点 + 双 gate 判定）

- run：`20261025-233401_fpga-steady-state-reverdict`；项目根 `D:/fpga/ph1p100`
- 角色：fpga-planner；本文件供 `T10.ss-steady-anchor`（P1，仿真测量）与 `T10.ss-verdict-r1`（P2，模型/判定）的开发与综合测试读取；不新增常驻角色
- 适用输入见 `input-index.md`；本文件只冻结**测量语义、TB 允许差异、公式、gate 规则、证据边界与预算**，不写生产 RTL、不改旧报告、不做 TD/板级
- 一句话原则：**冷启动单帧完成时间不是稳态吞吐；0% 与 25% 必须分列；平均带宽不是 sustained 带宽；sim-only fast sink 不是生产导出路径。**

## 0. 目标与非目标

### 0.1 目标

1. 用**同一 TB、同一冻结 RTL、同一几何**的 2 帧控制 + 4 帧扩展，实测 `L_cold`（冷启动单帧完成）与 `S_ss`（稳态帧间隔），从而回答 Q1，并把“6,421,414 是否只是 startup”变成可复现的算术。
2. 把 1080p30 per-stream 判定拆成 `G0`（nominal 0%）与 `G25`（≥1.25×需求）两个 gate，按单路/双路/三种内容锚点给结果，回答 Q2。
3. 修正 DDR 峰值（1333 = 5,332 MB/s；1600 = 6,400 MB/s）、UART fast-sink、1080p overhead 三档、双核 per-stream/共享 PAXI 口径，回答 Q3–Q7；输出修正后的 verdict（允许 `conditional`/`not_proven`）。

### 0.2 非目标

- 不接 RK；不做 RK 软件/驱动/深度/NPU；不做 PCIe 传输。
- 不做 TD 综合/布线/bitgen/CWC/下载/Flash/板卡/COM/JTAG；**本轮 0 次**。
- 不改 `fpga/csi2/src/**`、`upstream/**`、`D:/TD/work/csi2/**`、`D:/fpga_work/**`、`workflow/tasks.json`、`docs/**`、`work/**`。
- 不改上一轮 P1/P2 冻结候选/报告、b11/T08/T10 目录/候选/报告；需要其 RTL/TB 时**只在新 run 目录复制**。
- 不做压缩器 RTL 优化、不新增 A+ 算法、不重跑 TD 候选；不声称 1080p60/4K/RAW12。

## 1. 冻结系统定义（测量对象）

| 项 | 冻结值 | 说明 |
|---|---|---|
| 拓扑 | `camera_a1_uart_top`（真 A1 链）+ `p2_ddr_bridge`（真 CDC）+ `p2_paxi_model_b11`（行为级 256-bit PAXI） | 与 b11 `tb_b11_full` 完全相同，不替换 DUT |
| 相机几何 | `CAM_W=3864, CAM_H=2192, ROI_X=972, ROI_Y=556, W=1920, H=1080` | b11 两帧同一几何；不要换回 b6 的 3840/960/540 |
| 相机时序 | `clk_cam=187.5 MHz`（周期 5.333 ns）、`LINE_GAP=16`、`FRAME_GAP=400`、每行 `CG=CAM_W/4=966` 组 | 采集 1 帧 ≈ 1,606,552 cam cycles ≈ 8.57 ms |
| 主时钟 | `clk_a1=187.5 MHz`；`clk_uart=clk_a1`；`clk_ddr=200 MHz`（周期 5 ns） | 与 b11 相同；时钟不参与本轮敏感性 |
| 导出 | `UART_DIV=1`，`clk_uart=clk_a1` → **18.75 MB/s**（10 cycles/B）的 sim-only sink | 不是生产 115200；见 §4.5 |
| DDR 模型 | `p2_paxi_model_b11 #(WORDS=524288, AR_GAP=2, R_GAP=3)`，单拍 256-bit，`rdy=1` | 行为级：不是 DDR MC/刷新/行切换/争用模型 |
| 槽 | 每路 2 RAW 槽（20 B/32 B，129,600 words）+ 2 CMP 槽（8 MiB） | `raw0=0..129599, raw1=129600..259199, cmp0=262144..343228, cmp1=343229..424313` |
| 内容 | TB 内 `smp(x,y)=(x*3+y*5+((x^y)&7)*17)&1023` 平滑图案 | 与 b11 两帧一致；压缩后 ≈40,03x B/帧；**单一内容类** |
| 帧数 | 2 帧控制 + 4 帧稳态 | 4 帧是 Q1 的最小可判定集合 |
| 复位 | `rst_n` 释放前 20 个 `clk_a1`，释放后 40 个 `clk_a1` 再驱动 | 与 b11 一致 |

### 1.1 冻结 RTL 血统说明（必须写进报告）

- b11 的 `a1_deflate_core.v`（80,501 B，`a91c2ed8…`）与 b6 的（80,196 B，`6797db05…35bb`）**功能等价**：unified diff 仅 20 行，新增只读观测口 `dbg_state = state`，无逻辑/协议/输出改动。
- 因此“b6 的 6,421,414”与“b11/本 run 的测量”在 RTL 上可比；差异来自 **TB 几何（CAM 3840 vs 3864、ROI 960/540 vs 972/556）、`LINE_GAP`（40 vs 16）、`clk_uart`（1 GHz vs 187.5 MHz）、帧数（1 vs 多帧）**。报告必须逐项列出，不得隐去。
- 量化预期：相机驱动时长 1,620,000 vs 1,606,552 cam cycles（差 0.86%）；导出串行成本 75,060（b6，a1 当量）vs 400,320 cycles（本 TB），差 **325,260 cycles ≈ 5.1% of 6.42M**，实际取决于重叠，属上界。因此 **`L_cold(new)` 预期落在 6.42M–6.75M**；超出该区间必须给原因（内容/几何/重叠），不得强行对齐 6,421,414，也不得把差值当作吞吐差异。
- 禁止把 `T10.a1-frame-top` 的 `4,678,532 cycles / 103.88 MB/s`（upstream core `6cd35881…`）混入：不同 RTL 血统，**不可比**。

## 2. 测量语义：延迟 vs 稳态（P1 的核心）

### 2.1 事件与时间戳（a1 周期计数，`cycles` 从 time 0 起每个 `posedge clk_a1` 加 1）

| 事件 | 定义 | 来源 |
|---|---|---|
| `t_rst` | `rst_n` 释放时刻的 `cycles` | TB |
| `t_sof(k)` | 第 k 帧 `tap_frame/tap_vs` 拉高的时刻 | TB 驱动 |
| `t_cam_end(k)` | 第 k 帧最后一行驱动的时刻 | TB 驱动 |
| `t_pub(k)` | `st_raw_pub` 第 k 次递增（该帧写入 RAW 槽） | DUT 状态 |
| `t_read(k)` | `st_read_words` 首次 ≥ 129,600×k（该帧 RAW 读完） | DUT 状态 |
| `t_enc(k)` | `st_enc_frames` 第 k 次递增（core 提交该帧） | DUT 状态 |
| `t_exp(k)` | `st_exported` 第 k 次递增（该帧 44 B 头 + 载荷全部交给导出器） | DUT 状态 |

事件必须**同时**以 `SS_EVT t=<cycles> kind=<sof|cam_end|pub|read|enc|exp> frame=<k> n=<计数值>` 打到 stdout（vsim log 保存），并允许另写事件文件；以 vsim log 为权威。若某事件在现有层次不可观测，必须报告“不可观测”，**不得用推断值填充**。

### 2.2 定义（全部为 cycles，除以 187.5e6 得秒）

```text
L_cold      = t_exp(1) - t_rst            # 冷启动单帧完成（与 b6 的 6,421,414 同类）
L_frame     = t_exp(1) - t_sof(1)         # 纯首帧延迟（去掉预驱动）
S_2         = t_exp(2) - t_exp(1)         # 过渡间隔（第 2 帧）
S_23        = t_exp(3) - t_exp(2)
S_34        = t_exp(4) - t_exp(3)
S_ss        = (S_23 + S_34) / 2           # 稳态帧间隔（主口径）
S_avg2      = (t_exp(2) - t_rst) / 2      # 2 帧控制的事件口径平均（不是 S_ss）
S_avg2_stats= 11,445,988 / 2              # 冻结 stats 的 cycles 含导出后 2000-cycle drain；仅作对照
startup     = L_cold - S_ss               # startup/tail 绝对量
startup_pct = 100 * (L_cold / S_ss - 1)   # >15% 即说明“6.421M 当吞吐”实质性错误
```

> `stats` 行的 `cycles` 是在 `st_exp==FRAMES` 后再 `repeat(2000)` 才写入的；事件时间戳比它早约 2,000 cycles（0.017%）。因此 `L_cold + S_2 = t_exp(2) ≈ 11,443,988`，而**不是**直接等于冻结的 11,445,988。报告必须区分 `S_avg2`（事件口径）与 `S_avg2_stats`（含 drain），不得把两者混用。

### 2.3 由 `S_ss` 导出的容量（P1 给算术，P2 给 gate 判定）

```text
C_ss_MBps = 2,592,000 * 187.5e6 / S_ss / 1e6 = 4.86e8 / S_ss        # MB/s（10^6 B）
fps_ss    = 1.875e8 / S_ss
margin_0  = C_ss / 77.76 - 1
margin_25 = C_ss / 97.20 - 1
f_req_0   = 30    * S_ss        # Hz
f_req_25  = 37.5  * S_ss        # Hz
export_tail(k) = t_exp(k) - t_enc(k)                                # 每帧导出尾巴
export_cost    = 40,032 * 10 = 400,320 cycles/frame                 # UART_DIV=1、187.5 MHz 的串行成本
C_excl_export  = 4.86e8 / (S_ss - export_tail)                      # 仅当 sink 成为瓶颈时使用
```

> **尾巴判据**：稳态下 `export_tail(k)` 若是常数（帧间差 ≤1% 且 <0.5·`S_ss`），它在 `S_ss` 的帧间差里**相互抵消**，`C_ss` 不需要扣减，`C_excl_export = C_ss`；只有当 `export_tail` 随 k 增长（积压）或 ≥0.5·`S_ss` 时，才标 `sink_limited=true` 并用 `S_ss − export_tail` 作乐观界。**不得**无条件把 `S_ss` 减去 400,320。
>
> `margin_*` 是小数（0.25 = 25%）；JSON/CSV 一律写 `_pct` 字段并存 ×100 的值，避免 100× 误读。

判别阈值（供核对，不预设结论）：`S_ss = 6,250,000` ↔ 恰好 0%；`S_ss = 5,000,000` ↔ 恰好 25%。1% 的 `S_ss` 差异 ≈ 0.25 个百分点 margin，因此必须报 `S_23`/`S_34` 双值与 band。

### 2.4 有效性判据（任一不满足 → 该次测量不得作为 `S_ss` 结论）

| # | 判据 | 门槛 |
|---|---|---|
| V1 | 4 帧计数完整 | `cap=4 enc=4 exported=4 read=518400` 且 `raw_drop=0 cmp_drop=0 geom=0 err=0 dup_words=0 wd=0` |
| V2 | 2 帧控制精确复现 | `cycles=11445988`、`cap=2 enc=2 exported=2 read=259200`、`exp_bytes=80068`、`cap_bytes=80156`（**逐值相等**，不是近似） |
| V3 | 稳态一致性 | `abs(S_23 - S_34) / S_ss <= 2%`；否则同时报两值并标 `steady_state_status=unstable`，不得单选 |
| V4 | 相机不是限速方 | `t_pub(k+1) < t_exp(k)` 对 k=2,3 成立（下一帧在当前帧导出完成前已入槽）；且 `t_cam_end(k)-t_sof(k) < 0.5*S_ss` |
| V5 | 无早期丢帧 | 第 3/4 帧开始驱动前，对应 RAW 槽已释放（以 `st_read >= 129600*(k-2)` 或等价的 slot-free 指示为证；方法须声明） |
| V6 | 时序单调 | `t_exp(1)<t_exp(2)<t_exp(3)<t_exp(4)`；`t_pub(k) <= t_read(k) <= t_enc(k) <= t_exp(k)` |

若 V3 不成立：报 `S_23`/`S_34` 与 band，`steady_state_status=unstable`，P2 用 band 两端给 margin 范围，不得只说一个数。
若 V4 不成立（出现气泡）：报 `S_ss` 为**容量下界**（帧间隔被相机/槽等待拉长），并给气泡量 `t_pub(k+1)-t_exp(k)`；P2 必须把该情形标 `capacity_is_lower_bound=true`。
导出尾巴单独核对（不作为 V1–V6 的否决项）：逐帧 `export_tail(k)=t_exp(k)-t_enc(k)`；常数且 <0.5·`S_ss` → 正常；随 k 增长或 ≥0.5·`S_ss` → `sink_limited=true` 并说明。

### 2.5 4 帧驱动的 pacing（避免丢帧，同时不引入相机限速）

- 第 1、2 帧：与 b11 完全一致，`drive_frame` 背靠背（第 2 帧在 `FRAME_GAP=400` 后立即开始）。
- 第 3、4 帧：在“目标 RAW 槽已释放”后才开始 `drive_frame`。实现可选：等待 `st_read >= 129600*(k-2)`，或读取 `u_store` 的 slot-free 指示；**方法必须写进 `src/DIFF.md`**，并保证 `raw_drop=0`。
- 禁止为了凑稳态而把 4 帧改成“只驱动 2 帧 + 复制时间戳”，或把 2 帧结果外推冒充实测。

## 3. TB 工程冻结（P1）

### 3.1 冻结副本与哈希

- `src/` 必须包含：§1 的全部 DUT 源（9 个 changed-src + 2 个 repo_deps）、`p2_paxi_model_b11.v`、`a1_ddr_model.v`、`tb_b11_full.v`（作为参照原件，可放 `src/ref/`）。
- **编译清单**只列 b11 `run_b11.py` 的 12 个 DUT/模型源（8 个 changed-src + 2 个 repo_deps + `p2_paxi_model_b11.v` + `a1_ddr_model.v`），再加被测 `tb_ss_anchor.v`；`p2_a1_board_top.v` 只复制/哈希、**不编译**（它是板级 top，缺板级依赖）。
- 每个副本必须与 `input-index.md` §2 的 SHA **逐字节相等**；`input-verified.json` 记录 path/bytes/SHA 与 b11 manifest 的比对结果（0 mismatch 才继续）。
- DUT 源**禁止任何修改**；只允许新增派生 TB。

### 3.2 派生 TB `src/tb_ss_anchor.v` 的允许差异（白名单，超出即视为违规）

以 `tb_b11_full.v` 为基线，只允许：

1. 新增 `parameter integer FRAMES = 4`（控制 run 用 2）；把 `while (st_exp < 2)` 与最终门槛改为 `FRAMES`。
2. 新增 §2.1 的 `SS_EVT` 事件打印（只读状态，不改 DUT）。
3. 新增第 3/4 帧的 slot-free 等待（§2.5）。
4. 新增按帧 watchdog：`st_exp` 超过 8,000,000 cycles 未递增即打印 `SS_STALL frame=<k>` 并 `$finish`（`pass=0`）。
5. `MAX_CYCLES` 改为 `30,000,000`。
6. 路径寄存器加宽：`reg [4095:0] stat_path`（b11 为 `[1023:0]`=128 B，长路径会截断；b6 报告已记录该 TB 限制）。
7. 统计行保持 b11 字段与顺序，行首仍为 `cap=...`，并在末尾追加 ` frames=<FRAMES> ss_pass=<0|1>`（追加字段不得改变前 **16** 个字段的数值：cap/enc/exported/exp_bytes/raw_pub/raw_drop/cmp_drop/geom/err/read/dup/cap_bytes/cycles/wd/ar/r）。
8. `$fopen` 的 dec/stats 目标改为本任务 `sim/caps/` 下的绝对路径，并核对其字节数（`cap_bytes` = 44×FRAMES + 载荷）。

**禁止**：改 DUT 端口/参数/时钟/复位/几何/内容函数、改 `FRAME_GAP`/`LINE_GAP`、改 DDR 模型参数、加 `$deposit`/`force`、改 `st_*` 计数、把 `exported` 用别的信号替代。

### 3.3 `src/DIFF.md`

必须逐条列出 1–8 的 diff（文件、行号、原因），并给出“对 DUT 行为无影响”的论证；综合测试者按此白名单逐条核对，任何白名单外差异 → FAIL。

### 3.4 仿真命令与硬超时

```text
vlib work                                  (独占 %TEMP%\opencode\ss-anchor\work)
vlog -sv -work work +define+SIMULATION <src 列表>     timeout 1200 s
vsim -c -lib work tb_ss_anchor +STAT=... +EVT=... -gFRAMES=2 -do "run -all; quit -f"   timeout 2700 s
vsim -c -lib work tb_ss_anchor +STAT=... +EVT=... -gFRAMES=4 -do "run -all; quit -f"   timeout 2700 s
```

- `MODELSIM` 指向复制到 `%TEMP%\opencode\ss-anchor\modelsim.ini` 的独占副本；若副本因相对路径失效，可回退共享只读 INI，但必须记录偏差。
- 工作库、日志、`transcript` 全部独占；不得与他人共享盘符映射或 work 库。
- 并发 TD/板卡/他人仿真可能拉长墙钟（本规划轮观测到同 run 目录下有 b13 的 TD/COM8 活动）。本任务**只终止自己拥有的 vsim/vlog 进程**；命中 2700 s 即停、保留日志、按 partial 返回，不延长、不杀他人进程、不因等待而反复重试。
- 超时/`SS_STALL`/`MAX_CYCLES` 命中 → 保留日志与已完成帧的事件，按“部分结果”返回；**不得**把 2 帧或 3 帧结果标成 4 帧稳态。

## 4. 模型口径冻结（P2）

### 4.1 两个 gate（必须分列，不得塌缩）

| gate | 条件 | 标签 |
|---|---|---|
| `G0` nominal | per-stream 容量 ≥ `D_s`（1080p30 = 77.76 MB/s） | `meets_nominal` / `misses_nominal` |
| `G25` design margin | per-stream 容量 ≥ `1.25 × D_s`（= 97.20 MB/s） | `meets_25` / `below_25` |

行判定映射（机械）：

| 条件 | `verdict` | 说明 |
|---|---|---|
| `G25` met 且资源/时序/证据满足 | `feasible` | 仅单核 ≤187.5 MHz 可能 |
| `G0` met、`G25` 未 met | `conditional` | **不得写 `infeasible`**；原因 `below_25` |
| `G0` 未 met | `infeasible` | 原因 `misses_nominal` |
| 双核任一行 | 最高 `conditional` | 双核 Routed 时序 + 共享 PAXI 未证；`G0` 未 met 时仍 `infeasible` |
| 内容仅覆盖 measured 一类 | 追加 `claim_status=not_proven_all_content` | 与行 verdict 分列，不互相替代 |

`claim_status` ∈ {`proven_for_measured_content`, `not_proven_all_content`}。

**Headline（claim 级）组合规则**（与行 verdict 分列；1080p30 per-stream 的系统结论必须按此给）：

| 条件 | headline | 说明 |
|---|---|---|
| A1.G0=false 且 A2.G0=false | `infeasible` | 两种内容基都低于 nominal |
| A1.G0 与 A2.G0 不同（内容跨越） | `not_proven` | 实测内容过、保守内容不过（或反之）；不得写成 `infeasible` 或 `feasible` |
| 两者 G0=true 且（G25 有 false 或 资源/时序未证） | `conditional` | nominal 过关，25%/实现边界未过 |
| A1.G0/G25、A2.G25 均 true 且资源/时序满足 | `feasible` | 只有这种情形可说系统可行 |

> P1 实测回填：A1=`103.9009 MB/s`（G0/G25 均过）、A2=`75.6843 MB/s`（G0/G25 均失）→ **A1.G0 与 A2.G0 不同，headline = `not_proven`**；这不是“修不出结论”，而是“nominal 对实测内容成立、对保守内容不成立”的诚实结论；不得为了给单词 verdict 而选有利锚点。
>
> 双核 `2c2s`：per-stream 容量标 `assumed_from_single_core`、共享 PAXI 标 `paaxi_shared_unproven`，因此 headline 只能是 `not_proven`（或明确写 “conditional for nominal on assumed capacity” 并给理由），**永远不得 `feasible`**。

### 4.2 内容锚点（1080p，cycles/frame）

| id | 锚点 | 值 | 标签 | 用途 |
|---|---|---:|---|---|
| A1 | `grad_chain_ss`（P1 r0 实测） | **4,677,535**（band `[4,677,535, 4,677,535]`） | **measured**（真 RTL、单内容梯度、b11 几何、含 DDR 读/槽/18.75 MB/s sim sink；行为 DDR） | 主锚点 |
| A2 | `comp_core_scaled` + primary overhead | 5,995,029.375 + 426,385 = **6,421,414.375**（取整即 b6 的 6,421,414） | **assumed**（1920×64 strip 的 2.312897 cycles/B 按面积外推 + assumed overhead） | 保守内容界（假设） |
| A3 | `rand_core_scaled` + primary overhead | 2,724,961.5 + 426,385 = 3,151,346.5 | **assumed**（1.051297 cycles/B 外推） | 乐观界 |
| A4 | b6 冷启动单帧 | 6,421,414 | **measured 但不是吞吐**（单帧延迟、跨 TB/几何） | 仅作 Q1 的延迟参照与 A2 的**循环依赖警示** |

**强制披露**：A2 与 A4 数值相同是**定义造成的**（overhead := 6,421,414 − 5,995,029.375），不是独立证据；报告不得把 A2 当作“另一个实测也支持 6.42M”。A2 只能标 `assumed`。

### 4.3 overhead 三档与 1080p 参与方式（Q3）

- 三档：`0 / 426,385 / 1,000,000` cycles/frame；primary = 426,385。
- 1080p 不再 `applies=false`。以 A1 为 primary 档锚点，按**档位差**平移：

```text
cycles_chain_1080p(tier) = S_ss + (tier - 426,385)
tier=0      -> S_ss - 426,385
tier=426385 -> S_ss
tier=1e6    -> S_ss + 573,615
```

- 平移量是 `assumed`（固定开销可被削减/增加），但必须给出三档的 margin 与 verdict；推荐必须满足“三档稳健”才可称 robust（沿用 P2 规则）。
- 其它几何仍用 `cycles_core(comp,W,H) + tier` 的 affine 模型，标 `assumed_content_scaling`；不得把该模型的结果写成 measured。
- “0-overhead/流水线隐藏 tail”作为优化路径的判据：`Δ_req = S_ss - 5,000,000`。若 `Δ_req <= 426,385`，则“把每帧固定开销压到 ≤(426,385−Δ_req)”是达到 25% 的**充分**路径；若 `Δ_req > 426,385`，仅靠 overhead 归零不够（还需核级 cycles/B 或时钟）。

### 4.4 DDR 峰值与 required efficiency（Q4）

```text
peak_1333 = 1333e6 * 32/8 / 1e6 = 5,332 MB/s      # 当前主线（DOC-1 §4.3 M1a）
peak_1600 = 1600e6 * 32/8 / 1e6 = 6,400 MB/s      # 回退档（DOC-1）
user_domain_1333 = 166.65e6 * 32 B / 1e6 = 5,333 MB/s   # 256-bit PAXI，与上式一致
R_w = R_r = D_total * 1.6 ;  S_w = S_r = B_cmp_total * fps * streams / 1e6
DDR_total = R_w + R_r + S_w + S_r ;  gate = 1.25 * DDR_total
required_eff = DDR_total / peak ;  gate_eff = gate / peak
```

- 主路径（双路 1080p30，20 B/32 B，含 CMP DDR）冻结核对值：`DDR_total = 809.034 MB/s`、`gate = 1,011.2925 MB/s`。
  - 1333：`required_eff = 15.173%`、`gate_eff = 18.966%`。
  - 1600：`required_eff = 12.641%`、`gate_eff = 15.801%`。
- DOC-1 §8 的“800E≈1.2 / 1333≈2.33 / 1600≈3.4 GB/s”与上述显式公式不自洽，推导不明；P2 必须单列该差异，**不得静默采用**，也不得因该文档值改变 gate。
- 结论措辞：平均带宽在峰值内 ≠ DDR 已满足；PAXI 仲裁/单 outstanding/刷新/行切换仍 `unproven`。

### 4.5 UART / 导出边界（Q5）

| 口径 | 字节率 | 40,032 B/帧 | 2,594,706 B/帧 | 相对 33.333 ms |
|---|---:|---:|---:|---:|
| 真实 115200 8N1 | 11,520 B/s | 3.475 s | 225.235 s | 104.2× / 6,757× |
| b6 TB（`clk_uart`=1 GHz、`UART_DIV=1`） | 100 MB/s | 0.400 ms（75,060 a1 cycles） | 25.95 ms | 1.2% / 77.8% |
| b11/本 run TB（`clk_uart`=187.5 MHz、`UART_DIV=1`） | 18.75 MB/s | 2.135 ms（**400,320 cycles**） | 138.4 ms | 6.4% / 415% |

- `UART_DIV` 的口径是“每字节 10×DIV 个 `clk_uart` 周期”（`a1_uart_export.v` 头注释、`a1_uart_tx #(.CLK_DIV)`）；`DIV=1` 时字节率 = `clk_uart/10`，不是 `clk_uart`。禁止把 187.5 MB/s 当字节率。
- 锚点性质：`S_ss` 覆盖“采集→RAW 槽→DDR 读→core→CMP→**sim-only fast sink**”。本 run 的 sink 每帧理论串行成本 **400,320 cycles**（40,032 B × 10；实测 40,034 B → 400,340，差 20），约 2.1 ms。
- **稳态下**该成本是每帧相同的尾巴：`export_tail(k)=t_exp(k)-t_enc(k)` 若为常数（≤1% 且 <0.5·`S_ss`），会在 `S_ss` 的帧间差中抵消，**不直接降低容量**；它计入的是 `L_cold`（一次性）与 b6/b11 的 `L_cold` 差。开发必须逐帧报 `export_tail`；若它随 k 增长或 ≥0.5·`S_ss`，才标 `sink_limited=true` 并用 `S_ss−export_tail` 作乐观界。
- 因此 P2 必须同时报 `S_ss`（主口径）与 `sink_limited`/`export_tail` 证据；不得无条件扣减 400,320，也不得只报对其一。
- 与 b6 的 `L_cold` 比较：b6 sink 比本 run 快 325,260 cycles/帧，因此 `L_cold(new)` 预期比 6,421,414 高约 0–5%（取决于重叠），见 §1.1。
- 生产路径必须是 PCIe/高速 sink；真实 UART 只能作诊断/取证（与 DOC-2 一致）。任何“1080p30 实时”声明必须限定为“到 CMP 槽/高速 sink 为止”，并单列 `transport=not_proven`。
- 若导出被真实 UART 限速，CMP 槽会反压 core，`S_ss` 不再成立；报告必须写清这一因果，不得用 fast-sink 数字暗示 UART 可实时。

### 4.6 双核 / per-stream / 共享 PAXI（Q6）

- 容量规则不变：`c1s1 = C`、`c1s2 = C/2`、`c2s1 = C`、`c2s2 = C`（每核一路，**不是 2C**）。
- `c2s2` 的 `C` 来自单核实测 `S_ss`；共享 256-bit PAXI / 单 DDR MC 下的双核争用**未测**（b11 的 arb2 只覆盖“写 store + 读 reader”两客户，4 客户仲裁未实现），必须标 `paaxi_shared_unproven=true`、`dual_core_capacity=assumed_from_single_core`。
- 资源：marginal 231/300（余 69）、conservative 289/300（余 11，3.67%）→ 双核最高 `conditional`；Routed 时序 `unproven`；本 run 不重跑 TD。
- 禁止：`2×C_core ≥ 155.52` 或 `2×C_ss ≥ 155.52` 判双路 per-stream；聚合只用于 DDR/总量。

### 4.7 调度/丢帧下界

```text
drop_rate_lb = max(0, 1 - C_service / D_s)     # C_service = per-stream C_ss
```

- 假设每路 2 RAW 槽、帧级公平、一编码器一次一帧、无空闲槽丢整帧（沿用 P2/T08 合同）。
- `drop_rate_lb=0` 只表示算术不积压；`G25` 必须另列。2 槽不能当无限缓冲；仲裁/空窗可能更差，标 `lower_bound`。

### 4.8 禁止的判定塌缩（负对照的语义基准）

1. 用 `L_cold`（6,421,414）当 `S_ss` → `COLD_LATENCY_AS_THROUGHPUT`。
2. 把 `G25` 未过直接写成 `infeasible`（吞掉“nominal 已过”）→ `GATE_COLLAPSE`。
3. 1333 平台用 6,400 峰值且不标口径 → `PEAK_MISMATCH`。
4. 把 fast sink/真实 UART 当生产导出 → `SINK_MISMATCH`。
5. 用 aggregate `2C` 判 per-stream → `AGGREGATE_CAPACITY_FOR_PER_STREAM`（沿用 P2 NEG-02）。
6. 1080p 声称三档稳健却把 tier 标 `applies=false` → `TIER_NOT_APPLIED`。

## 5. 判定与推荐规则（P2）

1. 每行先算 `G0`、`G25`，再按 §4.1 映射 `verdict`；`claim_status` 单列。**同一行只能用一个锚点算 margin**：1080p 行用 A1，其它几何用 `affine_comp+tier`；A2/A3 只出现在 `content-anchors.csv`/`gate-matrix.csv`，不得把 A1 的分子与 A2 的分母混算。
2. 1080p30 的 headline 必须写成三段：`G0=…（margin x%）` / `G25=…（margin y%）` / `content=not_proven_all_content`；不得只给一个词。A1（grad）与 A2（comp）结论不同时必须并列，不得只报有利的一个。
3. 主推荐 = 在 **primary tier** 满足 `G25` 且资源/时序满足的最大 30 fps 几何（单核优先）；若 `G25` 在保守档跌破，必须写 “primary feasible / conservative conditional”。
   - **内容基一致性**：主推荐必须与比较对象用同一内容基。1080p 只有 A1（grad）实测，其它几何是 A2 型 comp 外推；因此 **不得**因 A1 的 1080p30 过 G25 就把 1080p 提为主推荐并压过 comp 基的 1600×900。1080p30 只在 A2 也过 G25 时才可作主推荐；否则单列 “measured-content only / not_proven_all_content”。
4. 备选 ≤2；1080p30 若 `G0` 过而 `G25` 未过，作为 “nominal-only” 单列，不得当主推荐。
5. 推荐必须给：per-stream margin（三档）、所需时钟（`f_req_0`/`f_req_25`）、ERAM、证据标签、未证项。
6. 若 `S_ss` 的 band 跨越 25% 阈值（例如 `S_23` 与 `S_34` 分居 5.0M 两侧），必须写 “knife-edge”，给两侧 margin，不得选有利一侧。

## 6. 输出合同

### 6.1 P1 `T10.ss-steady-anchor/r0/`

```text
input-verified.json          # 副本/输入 path/bytes/sha256；与 b11 manifest 0 mismatch
src/                         # 冻结副本（DUT + 模型 + 参照 TB）
src/tb_ss_anchor.v           # 派生 TB（白名单差异）
src/DIFF.md                  # 逐条 diff + 无影响论证
sim/run_ss.py                # 驱动：compile / control2 / run4；含硬超时与事件解析
sim/modelsim.ini             # 独占副本（或记录回退偏差）
sim/logs/*.log, sim/caps/*.stats, sim/caps/*.dec
out/events-4frame.csv        # 每帧事件时间戳（cycles + ns）
out/steady-state.json        # 见 6.2
out/steady-state.md          # Q1 的简短回答（含 L_cold/S_ss/startup_pct/口径警告）
result-r0.md, lessons.md, manifest-r0.json
```

### 6.2 `out/steady-state.json` 最小字段

```text
clock_hz, frames, source_manifest_sha, tb_sha, copied_src_all_match(bool)
t_rst, t_sof[], t_cam_end[], t_pub[], t_read[], t_enc[], t_exp[]   (cycles)
L_cold, L_frame, S_2, S_23, S_34, S_ss, S_avg2, startup, startup_pct
capacity_MBps, fps, margin_0_pct, margin_25_pct, f_req_0_mhz, f_req_25_mhz
export_tail[], export_cost_cycles, sink_limited(bool), c_excl_export_MBps
validity: {v1_counts, v2_control_exact, v3_stable, v4_no_bubble, v5_slot_free, v6_monotone}
steady_state_status: measured|unstable|partial|not_measured
capacity_is_lower_bound: bool
counters: {cap, enc, exported, exp_bytes, cap_bytes, read, raw_drop, cmp_drop, dup, geom, err, wd}
notes: 内容/几何/sink/DDR 模型边界；b6 对比的几何与 UART 差异
```

### 6.3 P2 `T10.ss-verdict-r1/r0/`

```text
input-verified.json
inputs/frozen-inputs.json     # 含 P1 manifest/steady-state.json 的 SHA、DDR 5333/6400、UART、gate 定义
model/calc.py                 # 纯函数；含 legacy/corrected 两种规则模式
model/rules.json              # 两 gate、verdict 映射、禁止塌缩、负对照
model/test_calc.py            # 已知值/边界/6 个负对照
model/gen_tables.py, check_outputs.py, render_report.py
out/scenarios.csv             # 43 行 × 两 gate + 资源/时序/证据列
out/content-anchors.csv       # A1/A2/A3/A4 × 1080p × gates
out/gate-matrix.csv           # c1s1/c1s2/c2s1/c2s2 × 3 锚点 × 2 gate
out/overhead-sensitivity.csv  # 43×3，1080p 用档位差平移
out/ddr-budget.csv            # 5333 与 6400 两列 + required_eff/gate_eff
out/corrections.csv           # C1..C9：P2 原值/原规则/修正值/影响/证据
verdict-r1.md
result-r0.md, lessons.md, manifest-r0.json
```

`scenarios.csv` 最小列（在 P2 基础上增列）：`scenario_id, cores, streams, W, H, fps, clock_mhz, cycles_core_per_frame, cycles_chain_per_frame, chain_anchor_id, content_label, capacity_chain_MBps, per_stream_capacity_chain_MBps, demand_per_stream_MBps, margin_chain_pct, gate_G0, gate_G25, verdict, claim_status, drop_rate_lb_pct, eram_bound, eram_total, eram_headroom, timing_status, required_clock_0_mhz, required_clock_25_mhz, notes`。

`chain_anchor_id` 每行只能取 `A1_grad_ss`（仅 1080p）或 `affine_comp_tier`（其它几何）；同一行不得混用锚点。A2/A3 的 1080p 结果只放 `content-anchors.csv` 与 `gate-matrix.csv`。

`corrections.csv` 最小列：`id, p2_claim, p2_value, p2_rule, corrected_value, corrected_rule, impact_on_verdict, evidence_path, label`。

## 7. 测试与证据（综合测试者必须做）

### 7.1 P1（独立于开发）

1. **独立重跑 2 帧控制**：用测试者自己的独占 work 库与日志，`FRAMES=2` 必须**逐值复现** `cycles=11445988`、`cap_bytes=80156`、`exp_bytes=80068`、`read=259200`。不重跑 4 帧（预算），但必须用**自写解析器**从 4 帧原始 log 重算 `L_cold/S_23/S_34/S_ss/C_ss`，不得 import 开发的 `run_ss.py`/JSON。
2. 按 §3.2 白名单逐条核对 TB diff；白名单外任何差异 FAIL。
3. 核对 §2.4 V1–V6 全部判据；核对 `S_ss` 与 `S_23/S_34` 的 band 与 `margin` 算术（§2.3 公式，独立手算至少 3 项）。
4. 负对照：把 `S_avg2` 当 `S_ss`、把 `L_cold` 当 `S_ss`、把 3 帧 log 当 4 帧 → 解析器必须拒绝。
5. 输入漂移：副本 SHA 与 b11 manifest 必须一致；b11/b6/P2 目录在本任务期间不得被修改（记录快照）。

### 7.2 P2（独立于开发）

1. 用独立脚本复算至少 6 项：A1 的 `C_ss`/margin、A2/A3 的核级外推、`S=5.0M` 与 `6.25M` 的阈值、1333/1600 的 `required_eff`、UART 的 3.475 s、双路 DDR 809.034。
2. 用 P2 原规则复现旧 `scenarios.csv` 43 行（0 mismatch，允许 ≤1e-6 舍入）→ 证明修正只来自规则/口径，不是算术。
3. 6 个负对照（§4.8）必须全部被拒。
4. 核对 `verdict-r1.md` 的每个结论都有对应 CSV 行/字段；核对 `G0` 与 `G25` 在 1080p30 上确实分列，未把 `below_25` 写成 `infeasible`。
5. 核对 `claim_status=not_proven_all_content` 存在且未被 `G0`/`G25` 覆盖。

### 7.3 G 层

| 任务 | G0 | G1 | G2 | G3 | G4 |
|---|---|---|---|---|---|
| P1 | 副本/输入 SHA 与 b11 manifest 0 mismatch | 2 帧控制逐值复现；4 帧事件/算术可复算；白名单 diff | `not_applicable`（无综合/布线） | `not_applicable` | `not_applicable` |
| P2 | 输入（P1 manifest/steady-state、P2 冻结件）SHA | 模型/CSV/报告可复现；旧 43 行回归 0 mismatch；6 负对照 | `not_applicable` | `not_applicable` | `not_applicable` |

理由：两个包都是离线仿真/模型；没有 RTL 变更、没有 TD 候选、没有 bit/板卡。**不得用无关 TD/板测充数，也不得把仿真 PASS 写成 G2 或系统完成。**

## 8. 工作目录、工具与命令

- 项目根 `D:/fpga/ph1p100`；run 根 `workflow/runs/20261025-233401_fpga-steady-state-reverdict`。
- 每个任务只写自己的任务目录；测试者只写 `test-reports/<task_id>/**`。
- ModelSim：`D:\intelFPGA\18.1\modelsim_ase\win32aloem`；独占 work 库 `%TEMP%\opencode\ss-anchor\work`（测试者 `ss-anchor-test`），独占 `modelsim.ini` 副本与日志。
- Python 3.11；无网络/随机；所有命令记录 argv/cwd/exit/耗时/timeout。
- 禁止 shell 循环绕调用/重试次数；禁止批量删除；失败日志保留。
- `SS_EVT`/`SS_STALL`/`SS_STATS` 为唯一事件协议；新加标记必须写进 `DIFF.md`。

## 9. 预算（派发前冻结，运行角色不得自行扩大）

| 任务 | 开发 | 综合测试 | 全尺寸 vsim 次数 | 依据 |
|---|---|---|---|---|
| P1 `T10.ss-steady-anchor` | ≤40 calls / ≤120 min | ≤35 calls / ≤60 min | 开发 ≤3（2 帧控制 + 4 帧 + 至多 1 次有据重试）；测试者 1（2 帧控制） | 2 帧实测 598.5 s、4 帧预估 20–30 min，加编译/解析/报告；**放宽理由：长仿真必须一次跑完，不能按默认 45 min 截断** |
| P2 `T10.ss-verdict-r1` | ≤35 calls / ≤60 min | ≤30 calls / ≤45 min | 0 | 纯模型/表/报告；无长构建 |

- 单命令超时：读/搜 60 s；Python 120 s；`vlog` 1200 s；每次 `vsim` **2700 s**（硬超时，超时即 kill 本角色进程并保留日志）。
- 总仿真墙钟 ≤100 min（P1 开发 2–3 次 + 测试者 1 次）。超预算 → `partial`/`blocked`，给已完成帧与缺失项；**不得用 2/3 帧冒充 4 帧**。
- 同一失败命令最多首次 +1 次且须有新证据/参数纠正；单问题 ≤3 轮搜索/读取；连续 2 次无进展主动停止。
- 规划可提前冻结的只有上述有限值；运行角色不得扩次数/时长/帧数/几何。

## 10. 已冻结 / 待确认 / 不适用

### 10.1 已冻结

- `L_cold` vs `S_ss` 的定义、事件集、V1–V6 判据、2 帧控制逐值复现门槛。
- TB 白名单差异（FRAMES、事件、slot-free、watchdog、MAX_CYCLES、路径宽度、统计追加字段）。
- 两 gate（77.76 / 97.20 MB/s）、verdict 映射、`claim_status`、禁止塌缩。
- DDR 5,332/6,400、required_eff 核对值、UART 11,520 B/s、overhead 三档与 1080p 档位差平移。
- 内容锚点 A1–A4 与 A2/A4 循环依赖披露；双核 per-stream/共享 PAXI/资源/时序边界。
- 写范围、保护路径、G 层、预算与停止条件。

### 10.2 待确认（任务内核实，不需用户）

- 4 帧 slot-free pacing 的具体可观测量与 `raw_drop=0` 的实际行为。
- `S_23` 与 `S_34` 是否在 2% 内一致（是否已真正稳态）。
- b11 几何下的 `L_cold` 与 b6 的 6,421,414 的差异是否可归因于几何/UART/内容（预期 6.42M–6.75M；导出串行成本差 325,260 cycles 是上界）。
- `comp` strip 是否真是全帧内容的保守上界（预期 `assumed`，无全帧证据）。

### 10.3 不适用

- TD/综合/布线/bitgen/CWC/下载/Flash/COM/JTAG/板卡/RK/PCIe。
- 周期级调度器、PAXI 多客户仲裁、one-outstanding reader 时序仿真；DDR 持续带宽实测。
- G2/G3/G4；1080p60/4K/RAW12；压缩算法或 RTL 优化。

## 11. 与其它 run/任务的边界

- b11：只读 + 复制；b11 与其同 run 的 b12/b13/b14 的板卡/下载/COM/TD 归各自包；本 run 不抢其 tester、不改其候选/报告/统计，也不引用其在飞板级数字。
- b6：只读 + 复制；不改其 TB/统计。
- 上一轮 P1/P2：只读；不改冻结 manifest/报告/CSV。
- T08/T10（20261025-180900）：只读合同；不并入、不改目录。
- `workflow/tasks.json`：只读；本 run 两个包完成也不把 T10 置 done；收尾由原规划在本 run 边界内更新 dispatch/交接。

## 12. P1 测量回填与 P2 硬约束（2026-10-26；不改 P1 测量定义）

### 12.1 绑定

- P1 `T10.ss-steady-anchor` r0 **round0 PASS**；manifest SHA256 `39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a`；报告 `test-reports/T10.ss-steady-anchor-r0-integrated.md`；blocked=null、retest 空。
- P2 必须绑定：`out/steady-state.json` `a0945e1f60d9…`、`manifest-r0.json` `39f3e3d6…9f9a`、`sim/caps/ss4.stats` `29bd31851804…`、`sim/logs/run4.log` `dc215e0b46e4…`；并在 `input-verified.json` 复算。
- **P1 冻结件不得修改**；`T10.ss-steady-anchor/**` 是 P2 的只读输入。

### 12.2 实测（A1，均为 measured）

| 量 | 值 | 备注 |
|---|---:|---|
| `L_cold` / `L_frame` | 6,766,434 / 6,766,393 | 冷启动单帧；比 b6 的 6,421,414 高 5.4%（几何/UART/内容差异，O4） |
| `S_2` / `S_23` / `S_34` | 4,677,535 / 4,677,535 / 4,677,535 | band 0.00%；非 knife-edge |
| `S_ss` | **4,677,535** | `S_avg2=5,721,984.5` 只是两帧平均，不得替代 |
| `C_ss` / `fps` | **103.9009 MB/s / 40.0852** | 单内容梯度锚点 |
| `margin_0` / `margin_25` | **+33.6174% / +6.8939%** | A1 上双 gate 均过 |
| `f_req_0` / `f_req_25` | 140.326 / 175.408 MHz | 25% 所需时钟低于已验证 187.5 MHz |
| `startup_pct` | 44.66% | 6.421M 当吞吐属实质性错误 |
| `export_tail` | 480,930×4 恒定；`sink_limited=false` | `C_excl_export=C_ss`；不得无条件扣 400,320 |
| V1–V6 / counters | 全 true / `cap=4 enc=4 exported=4 read=518400`、drop/dup/geom/err/wd=0 | 4 帧完整、无丢帧、相机不限速 |

### 12.3 P2 硬约束

1. **A1 是单内容/单几何锚点**：`40.0852 fps`、`+33.62%/+6.89%` 只对应 smooth `smp` 梯度 + b11 1920×1080 几何 + 18.75 MB/s sim sink + 行为 DDR；**禁止**外推自然图像/低照/噪声或双路 1080p30。
2. **内容包络 + 双 gate**：P2 必须同时给 A1（grad measured）、A2（comp 外推 assumed）、A3（rand 外推 assumed）的 G0/G25 与 margin；A1.G0 与 A2.G0 跨界 → headline=`not_proven`（不是 `infeasible`，也不是 `feasible`）。
3. **A2 与 A4 同值**：`A2 = 6,421,414.375` 是 `5,995,029.375+426,385` 的定义结果，与 b6 冷延迟 6,421,414 同值；必须披露循环，A2 只能标 `assumed`。
4. **1080p tier**：`tier0=4,251,150`（m25 +17.615%）、`primary=4,677,535`（+6.894%）、`1e6=5,251,150`（**−4.783%**）→ 1080p 25% **非三档稳健**；主推荐/备选必须披露该档依赖。
5. **DDR**：1333 主线 5,332 MB/s（required_eff 15.1732%、gate_eff 18.9665%）；6,400 只作回退列（12.6412%/15.8014%）。
6. **UART/导出**：真实 115200=11,520 B/s（比 sim sink 慢 1,628×，比帧周期慢 104×）；`transport=not_proven`；sim sink 不是生产路径。
7. **双核**：`c2s2=C`、`paaxi_shared_unproven=true`、`dual_core_capacity=assumed_from_single_core`；资源 231/289、Routed 时序 unproven；双核 headline 最高 `not_proven`/`conditional`，永不 `feasible`；aggregate 2C 只用于 DDR/总量。
8. **A4 仅延迟参照**：`6,766,434` 不比 `S_ss`；b6 的 6,421,414 也不是吞吐。

### 12.4 §10.2 待确认项的 P1 结论

- 4 帧 slot-free pacing：**成立**（`raw_drop=0`、V5、`SS_PACE` 记录 slot/read）。
- `S_23` vs `S_34`：**0.00% 一致**（band 单点），已真正稳态。
- `L_cold` 与 b6 差异：**6,766,434 vs 6,421,414**（+5.4%）；导出串行/几何/内容差异已解释（O4/O7），不外推。
- `comp` strip 是否全帧保守上界：**仍未证**（A2 仍 `assumed`）；自然图像仍 `unproven`。
