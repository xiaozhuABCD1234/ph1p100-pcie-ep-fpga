# FPGA 设计冻结：双路 A+ 双核/服务率可行性（离线模型）

- run：`20261025-195604_fpga-dual-aplus-core-feasibility`
- 角色：fpga-planner；本文件由开发/测试按任务读取，不新增常驻角色
- 日期：2026-10-25
- 适用任务：`T10.dual-core-resource-baseline`（P1）、`T10.dual-aplus-service-verdict`（P2）、`T10.dual-core-synth-probe`（P3，blocked）
- 本文件只冻结**离线可行性模型的工程语义、输入口径、公式、判定规则和证据边界**；不写生产 RTL，不替代 TD/板测。

## 0. 目标与非目标

### 0.1 目标

在 PH1P100（300 ERAM20K / 129,024 LUT4 / 143,360 DFF / 220 DSP / 12 PLL）上，离线回答：

1. 双路 1920×1080@30 RAW10 的 A+ 压缩，单核/双核在**资源、时序、DDR 带宽、调度服务率**上是否可行；
2. 若不可行，给出**单核降帧**或**降分辨率**的量化结论（per-stream fps / 16:9 分辨率档 / 所需时钟 / 所需服务率）；
3. 给出一个**主推荐**和最多两个备选，并给出“什么会改变结论”的可测阈值。

### 0.2 非目标

- 不接 RK，不做 RK 软件/驱动/深度/NPU；不写 PCIe/RK 传输。
- 不做板卡/COM/JTAG/下载/Flash；不声称任何板级吞吐、恢复、曝光同步。
- 不改 `fpga/csi2/src/**`、`upstream/**`、`D:/TD/work/csi2/**`、`D:/fpga_work/**`。
- 不改 b11/T08/T10 目录、候选、报告、tester；不改 `workflow/tasks.json`。
- P1/P2 不跑 TD；P3 只做一次隔离综合，不布线、不 bitgen、不 CWC、不下载。
- 不做新的 A+ 算法/RTL 优化；本 run 只给架构可行性结论，优化另开包。

## 1. 冻结的系统定义

| 项 | 冻结值 | 说明 |
|---|---|---|
| 传感器/路数 | 2 路 IMX415，A/B 独立 | 双路同步目标；本 run 只做压缩服务率，不做曝光同步 |
| 分辨率 | 1920×1080 | 16:9；降分辨率档见 §6.4 |
| 像素格式 | RAW10 packed，Bayer | 5 B / 4 px；不按 RAW12/RAW16 算 |
| 帧率目标 | 30.000 fps per stream | 双路各自 30 fps；不是 aggregate 60 fps |
| 帧周期 | 33.333 ms | 30 fps 的倒数 |
| A+ core | b6 冻结 core `6797db05…35bb` | 不改算法/参数；b9/b10/b11 同 core |
| 压缩 profile | 固定向量 comp / stored rand / full_grad | 只用于服务率与内容敏感性；不声称所有自然图像 |
| 输出 | A1U1 压缩流（44 B 头）到 CMP 槽 | 8 MiB/slot；不接 RK |
| DDR 路径 | 相机写 RAW 槽 → A+ 读 RAW → 写 CMP 槽 → UART/PCIe 读 CMP = 2R+2S | 若实际实现不同，报告必须给变体 |
| DDR 端口 | 共享 256-bit PAXI，单 DDR MC | 不假设第二端口/更宽桥 |
| 主时钟 | 187.5 MHz | b6/b10 实测/约束值；150/175/200 仅敏感性 |
| 设计裕量 | 25%（容量 ≥1.25×需求） | 项目现行设计门槛；0% 只作算术对照 |

## 2. 冻结常量与字节账

### 2.1 帧与槽

| 量 | 公式 | 1920×1080 值 | 说明 |
|---|---|---:|---|
| 像素数 `P` | `W×H` | 2,073,600 px | W/H 可被 4 整除；否则末组填充另记 |
| RAW10 packed `B_raw` | `P×10/8` | 2,592,000 B | 有效像素载荷 |
| 4-px 组 `G` | `P/4` | 518,400 groups | 每 group 40 bit = 5 B |
| RAW 槽 `B_raw_slot` | `ceil(G/4)×32` | 4,147,200 B | 20 B 有效 / 32 B DDR 字；1.6× 膨胀 |
| DDR 字 `W_raw` | `B_raw_slot/32` | 129,600 words | 256-bit 字 |
| 内容长度 `B_content` | `B_raw + 128` | 2,592,128 B | T10/20261025 冻结合同；含 128 B 内容头 |
| DMA 对齐 `B_dma` | `ceil(B_raw/4096)×4096` | 2,592,768 B | 4 KiB 对齐；不是 CMP 长度 |
| CMP 最坏载荷 `B_cmp_payload` | `B_raw + 5×ceil(H/2) + 6` | 2,594,706 B | stored zlib 上界 |
| CMP 最坏总长 `B_cmp_total` | `B_cmp_payload + 44` | 2,594,750 B | 含 A1U1 44 B 头 |
| CMP 槽 | 固定 | 8 MiB | 容量足够；本 run 只做字节/速率，不做地址 |
| 帧头/CRC | 不建模 | — | 只按字节上界计；不声称编码/解码正确 |

**禁止**：把 `B_raw`（2,592,000）当 RAW 槽写/读字节；把 `B_dma` 当 CMP 长度；把 RAW12 的 3,110,400 B 或 622/777 MB/s 2R+2S 混入本 run。

### 2.2 器件

| 资源 | 总量 | 来源 |
|---|---:|---|
| ERAM20K | 300 | 双目方案 p11 表 1-1（DS1300_1.2.1） |
| LUT4 | 129,024 | 同上 |
| DFF | 143,360 | 同上 |
| DSP | 220 | 同上 |
| PLL | 12 | 同上 |
| slice | 71,680 | TD `routed_area.rpt` 行名；LUT4/slice 关系按 TD 报告，不混称 LUT6 |

**LUT 口径**：TD 的 `#lut6 ... out of 71,680` 分母是 LUT6 站点，不是 129,024 LUT4。报告必须用 `#lut6/71,680` 表示 TD 利用率，另列 LUT4 129,024 为器件手册口径；不得把 19,695/129,024 当 TD 利用率，也不得把两者相加。

### 2.3 单核权威基线（只读，P1 复算）

| 项 | 值 | 来源 | 标签 |
|---|---:|---|---|
| comp cycles / bytes | 355,261 / 153,600 B | b6 独立报告 | measured |
| comp 速率 @187.5 | 81.067159 MB/s | `B/cycles×f` | derived |
| rand cycles / bytes | 161,479 / 153,600 B | b6 manifest | measured |
| rand 速率 @187.5 | 178.351365 MB/s | `B/cycles×f` | derived |
| comp cycles/B | 2.31289714 cycles/B | `355,261/153,600` | derived |
| 1080p core-only cycles | 5,995,029.4 cycles | `2,592,000×2.31289714` | derived |
| 1080p core-only fps @187.5 | 31.276 fps | `187.5e6/5,995,029.4` | derived |
| full_grad 全帧 cycles | 6,421,414 cycles | b6 P1 STAT | measured（链级锚点） |
| full_grad 全帧 fps @187.5 | 29.199 fps | `187.5e6/6,421,414` | derived |
| 1080p 链级 overhead | 426,384.6 cycles | `6,421,414−5,995,029.4` | **assumed**；只在 full_grad 内容上成立，见 §4.3 |
| Routed WNS / hold | +0.119 / +0.020 ns | b6 报告 | measured |
| Routed 违例 / 端点 | 0 / 19,779 | b6 报告 | measured |
| 整机 b10 Routed WNS / hold | +0.103 / +0.020 ns | b10 r1 | measured |
| 整机 b10 资源 | 102 ERAM + 85 DRAMHARDCON = 187；LUT6 19,695；REG 28,004；slice 24,368；DSP 0；PLL 4 | b10 r1 | measured（routed） |
| u_core 层次 | 23 ERAM；1,399 logic LUT；783 ripple；1,175 seq；32 DRAM LUT | b6 `routed_area.rpt` | measured（层次列；不是 LUT6 精确增量，报告须保留列名） |
| u_bridge / u_mcu_core | 15 / 28 ERAM | b6/b10 `routed_area.rpt` | measured（共享/可复用需判定） |

**标签纪律**：`measured`（原报告/STAT）、`derived`（公式复算）、`assumed`（模型假设）、`unproven`（无当前证据）。报告不得把 `derived` 写成 `measured`，不得把 core-only 写成系统吞吐。

## 3. 资源模型

### 3.1 资源表（P1 产出）

`resource-table.csv` 每行至少：

```text
source_id, top, stage, ERAM_logic, DRAM_HARDCON, DRAM_LUT, ERAM_total,
LUT6, REG, SLICE, DSP, PLL, WNS_ns, HOLD_ns,
viol_ep, total_ep, clock_mhz, notes
```

`DRAM_LUT` 是 LUT 实现的分布式 RAM（b6 顶层 680），不计入 `ERAM_total`；`DRAM_HARDCON` 是 DDR 硬核块（b10/b11 85），按报告口径计入 300。两者不得混为一项。

规则：

1. **只用 Routed** 做资源拟合；synth 行只作检查点，必须标 `stage=synth`，不得与 routed 相加。
2. `ERAM_total = ERAM_logic + DRAM_HARDCON`，但必须在 `notes` 写清该报告的 `#eram` 是否已含硬核；b10 的“102+85=187”是采用口径，P1 要引用报告行/构建日志复核。
3. b6 小顶、b10 整机、b11 整机分别列；b11 只作并行交叉核对，不作为本 run 候选。
4. b6 synth ERAM 72 与 routed 102 的差异必须在报告中解释为工具映射差异，不得取平均或择小。
5. `u_core` 的 23 ERAM / ~1.4k logic LUT + 783 ripple / ~1.2k seq / 32 DRAM LUT 是**层次归属**，用作第二核边际成本的证据；不是“第二核精确增量”，报告必须保留原列名。

### 3.2 双核资源表（P1 产出）

`dual-core-budget.csv` 至少两栏：

| 栏 | 定义 | 用途 |
|---|---|---|
| `marginal` | 整机单链基线 + 第二核（按 `u_core` 层次列：23 ERAM、~1.4k logic LUT + 783 ripple、~1.2k seq、32 DRAM LUT）+ 第二路 bridge（15 ERAM）+ 第二路 camera/writer/fabric（按 b6/b10 层次行估算；层次显示 0 ERAM，但 FIFO/缓冲若映射 ERAM 必须按实际/上限另加并标注）+ 共享 MCU/DDR PHY 不复制 | 期望值；用于判断“是否明显装不下” |
| `conservative` | 整机单链基线 + 完整第二链（顶层 102 ERAM 等价复制）+ 85 DRAMHARDCON 只算一次 | 上界；用于“能否保证装得下” |

每栏必须给：

- `ERAM_total`、`ERAM_headroom = 300 − ERAM_total`、`headroom_pct`；
- `ERAM_logic`、`logic_headroom_210 = 210 − ERAM_logic`（项目初步逻辑 ERAM 额度）；
- `LUT_total`、`REG_total`、`SLICE_total`、`DSP`、`PLL` 与器件总量；`LUT_total` 必须注明是 TD LUT6（分母 71,680）还是 LUT4（分母 129,024），两者不得混算；
- `fit_300`、`fit_210_logic`（pass/fail/conditional）；
- `notes`：哪些模块复制、哪些共享、哪些是 assumed。

**判定规则**：

- `conservative ≤ 270/300` 且 `marginal ≤ 270`：资源“有 10% 余量”，可支持 `feasible`（仍需时序/服务率满足）。
- `marginal ≤ 300` 但 `conservative > 300`：资源“仅在边际口径成立”，最多 `conditional`，必须由 P3 隔离综合确认；不得直接判 feasible。
- `marginal > 300`：资源 `infeasible`，停止双核该路线，转降帧/降分辨率/单核。
- 210 逻辑 ERAM 额度是初步上限，不是器件硬限；超过 210 但总 ERAM ≤300 时，报告要写“超出项目初步额度”，不能静默通过。
- 270 = 300×0.9，留 10% 给布线/时钟/FIFO/未列共享逻辑；它是本 run 的**判定阈值**，不是器件硬限。若 conservative 栏落在 271–300，报告必须写“资源仅边际成立，需 P3/后续综合确认”，不得直接判 feasible。
- **共享假设**：第二路不复制 DDR MC/PHY，85 `DRAMHARDCON` 只算一次。若实际需要第二 DDR 端口/控制器，另加 85 → conservative 约 374/300，直接 `infeasible`；报告必须单列该变体，不得默认两端口/两控制器。

### 3.3 时序模型

- 单核：b6 Routed WNS +0.119、hold +0.020、0 违例；b10 整机 +0.103/+0.020/0。两者都是**薄余量**，报告必须保留 caveat。
- 双核：**没有双核 Routed 数据**。第二核是核心内部路径的复制，理论上不改变单核关键路径；但布局、时钟树、拥塞、共享桥可能改变。报告只能写 `unproven`。
- P3 只做综合：synth WNS 是**检查点**，不是 Routed 时序签核；b6 synth +0.280 → routed +0.119、area-map synth +0.104 → routed −1.115 已证明 synth 会乐观，禁止用 synth WNS 判双核时序 PASS。
- 时钟敏感性：150/175 MHz 低于已验证的 187.5，按同一设计可视为“由 187.5 通过推导”；200 MHz 及以上为 `unproven`；不得把 200 MHz 当默认方案。

## 4. 服务率模型

### 4.1 定义

| 量 | 公式 | 说明 |
|---|---|---|
| 核级容量 `C_core` | `B_raw / cycles_core × f` | 只含 A+ core 的输入→输出；不含 DDR/槽/UART/PCIe |
| 链级容量 `C_chain` | `B_raw / cycles_chain × f` | 含采集后读槽、core、导出/槽管理；边界由 P1/P2 核实 |
| per-stream 需求 `D_s` | `B_raw × fps` | 单路 1080p30 = 77.76 MB/s |
| 总需求 `D_total` | `D_s × streams` | 双路 1080p30 = 155.52 MB/s |
| 服务裕量 `M` | `C/D_s − 1` | **per-stream**；不是 `C_total/D_total` |
| 25% 门槛 | `C ≥ 1.25×D_s` | 项目设计门槛 |
| 所需时钟 `f_req` | `f_ref × D_s×(1+0.25)/C_ref` | 同 cycles/B 下满足 25% 的时钟 |
| 分辨率当量 | `area_max = C / (fps × (1+margin) × 1.25 B/px)` | `B/px` 为 RAW10 的 1.25；margin=0.25；得到像素面积后吸附到档位 |

`MB` 一律十进制 10^6 B；`MiB` 用 2^20 B；报告必须标单位。

### 4.2 单核 vs 双核、per-stream vs aggregate

必须同时给四种组合：

| cores | streams | per-stream 容量 | 说明 |
|---:|---:|---|---|
| 1 | 1 | `C` | 单路独占；用于单路 30 fps 基准 |
| 1 | 2 | `C/2` | 单核分时；两路各一半 |
| 2 | 1 | `C` | 第二核空闲；不推荐 |
| 2 | 2 | `C` | 每核一路；per-stream 仍是单核容量，不是 `2C` |

**硬规则**：双路 30 fps 的判定看 `C/2`（单核）或 `C`（双核）是否 ≥ `1.25×77.76`；**不得**用 `2C ≥ 155.52` 判 feasible。聚合带宽只用于 DDR/总服务量说明，不用于 per-stream 帧率判定。

### 4.3 core-only 与 full-chain

- `core-only` 是乐观上界：忽略 DDR 读、槽管理、导出、仲裁、帧边界。
- `full-chain` 是系统口径：至少包含“读 RAW 槽 → core → 写/导出 CMP”的串行链。b6 P1 full_grad 的 6,421,414 cycles 是当前唯一全帧锚点，但只有一个内容类，且边界需核实。
- 若无法从 STAT/TB 分解链级 overhead：
  - 1080p 直接用 `6,421,414 cycles` 作 measured 链级锚点；
  - 其他分辨率用 `cycles_chain(W,H) = cycles_core(W,H) + overhead`，`overhead ∈ {0, 426,385, 1,000,000}` 三档敏感性；`0` 是 core-only，`426,385` 是 1080p 锚点差，`1,000,000` 是保守档；
  - 报告必须写 `overhead` 是 assumed，并说明为什么该档合理；不得把 426,385 当所有内容的精确 overhead。
- 若 P2 能取得更细的 stage 计数（需开发只读检查 b6 STAT/TB，不重跑），可用实测分解替换假设；仍要保留 core-only 与 serial 两栏。

### 4.4 内容敏感性

至少三类：

| 类 | 速率 | 说明 |
|---|---|---|
| comp | 81.067 MB/s | 高匹配、fixed-Huffman；当前最慢核级向量 |
| rand | 178.351 MB/s | stored 回退；最快；不作为最坏 |
| full_grad | 29.199 fps 链级 | 全帧梯度；唯一全帧锚点 |

报告必须写：自然图像/低照/噪声未测；comp 不是所有内容的严格上界；若要把结论称为“保证”，需要更多内容类或 worst-case 证明。没有时用 `unproven`，不得用平均值。

### 4.5 调度/缓冲服务率

假设（与 T08/T10 合同一致；若实际实现不同，报告必须单列）：

- 每路 2 个 RAW 槽、2 个 CMP 槽；帧级公平选择；一个编码器一次处理一帧，不抢占。
- 新帧到来时无空闲 RAW 槽 → 丢整帧并记 capture_seq 缺口；CMP 满 → 持有 RAW 槽，不覆盖未发送内容。
- 双核：每核固定服务一路，per-stream 容量 = `C`，无跨路调度。
- 单核双路：帧级轮转，长期每路 50%，per-stream 容量 = `C/2`；最坏等待约 1 帧 + 当前帧编码时间，2 槽可吸收约 1 帧等待，超过则丢整帧。

稳态丢帧下界（无限 backlog、work-conserving、槽数不改变长期均值）：

```text
drop_rate_lb = max(0, 1 − C_service / D_s)
```

- `C_service` 用 per-stream 的 `C_core` 或 `C_chain`（报告必须标是哪一个）。
- `drop_rate_lb=0` 只表示算术上不积压，不表示满足 25% 设计裕量；`gate_25` 必须另列，不能互相替代。
- 若 `C_service ≥ 1.25×D_s`，2 槽下无持续丢帧；若 `C_service < D_s`，任何队列深度都不能消除积压，只能改变丢帧位置。
- 不得把“平均带宽够”当“无丢帧”；不得把 2 槽当无限缓冲；实际仲裁/空窗可能比 `drop_rate_lb` 更差，必须标 `lower_bound`。
- 本 run 只做**帧级**服务率/缓冲下界，不做周期级调度器、one-outstanding reader、PAXI 仲裁的时序仿真；后者需 T10 scheduler 或 RTL 仿真。帧级下界只用于可行性筛查，不能替代周期级调度验证。

## 5. DDR 2R+2S 模型

### 5.1 公式

```text
R_w = D_total × 32/20                 # RAW 槽写，1.6×
R_r = R_w                             # A+ 读 RAW 槽，1.6×
S_w = B_cmp_total × fps × streams / 1e6   # CMP 写，worst stored
S_r = S_w                             # UART/PCIe 读 CMP
DDR_total = R_w + R_r + S_w + S_r
DDR_gate  = DDR_total × 1.25
eff_req   = DDR_total / 6400          # 相对 ×32 1600 MT/s 理论峰值
```

### 5.2 口径

- `D_total` 用 `B_raw×fps×streams`，不是 `B_raw_slot` 的像素率；`1.6×` 已在 `R_w/R_r` 中体现，不得重复乘。
- `S_w/S_r` 用 `B_cmp_total`（含 44 B 头）的最坏 stored；不得用平均压缩比。
- 6.4 GB/s 是 ×32 1600 MT/s 理论峰值，未扣刷新、行切换、读写互转、仲裁、跨 4 KiB、命令开销；**不是实测**。
- 必须给“所需效率” `eff_req`，而不是只说“6.4 GB/s 够”。若 `eff_req` 很低（例如 <20%），说明平均带宽不是瓶颈，但桥的 latency/outstanding/单拍效率仍未证明。
- 若实际路径不写/读 CMP DDR（例如直接 UART 流式），给 `S_w=S_r=0` 的变体；不得把变体当主路径。
- 预览/显示读取、诊断 RAW 保留、元数据、ECC、刷新另计；若加入，必须单列，不得塞进“其他”。

### 5.3 结论措辞

- `DDR_total ≤ 6400/1.25` 只能写“平均带宽在理论峰值内，所需效率 X%”；不能写“DDR 已满足”。
- 若 `DDR_total > 6400/1.25`，写“理论峰值不足”，并给降帧/降分辨率/减流量方案。
- 任何“实测 DDR 带宽”必须来自板级计数；本 run 没有，统一 `not_run/unproven`。

## 6. 判定规则与场景网格

### 6.1 判定值

| 条件 | `verdict` | 说明 |
|---|---|---|
| per-stream 30 fps full-chain 裕量 ≥25%，conservative ERAM ≤270/300，且该架构时序已证明 | `feasible` | 单核可用 b6/b10 Routed；双核必须有 Routed 或明确接受 `conditional` |
| per-stream 30 fps 裕量 0–25%，或 marginal ERAM 271–300，或 conservative >300 但 marginal ≤300，或双核时序 `unproven` | `conditional` | 可实时但低于项目门槛，或实现/资源上界未证明；P3 可解 |
| per-stream 30 fps 裕量 <0%（链级不能维持 30 fps），或 **marginal** ERAM >300，或实测 Routed >300 | `infeasible` | 该场景/该资源口径不成立；conservative 上界超 300 不单独判 infeasible |
| 全网格没有任何 30 fps@0% 行 | `not_viable` | 系统级结论；给最近档与差距 |

`gate_status` 另列：`meets_25` / `below_25` / `fails_30`。`conditional` 不等于 PASS；报告首行/摘要必须写清。

### 6.2 决策网格（P2 必须完整生成）

- `cores ∈ {1,2}`，`streams ∈ {1,2}`。
- 30 fps 几何档：`1920×1080, 1728×972, 1600×900, 1440×810, 1280×720, 1152×648, 960×540`（16:9，宽高可被 4 整除）。
- 1080p 帧率档（`streams=2`，`cores∈{1,2}`）：`30, 25, 24, 20, 15`。
- 1080p30 双核时钟档：`150, 175, 187.5, 200` MHz。
- 每行两列速率：`C_core_comp`、`C_chain`（1080p 用 full_grad 锚点；其他档用 §4.3 的 affine 三档，报告取 `overhead=426,385` 为主、另两档作敏感性）。
- 预计 39 行左右；CSV 必须可枚举，不得只给“代表性”几行。

### 6.3 判定顺序（推荐回退）

1. 先排除 per-stream 30 fps 不成立的行（`fails_30`）。
2. 在 30 fps 行中，先看 full-chain 25% 门槛；没有则看 core-only 25%（标 `conditional`，说明是乐观口径）；再没有则看 0% 实时（标 `below_gate`）。
3. 若有 30 fps@25% 行：先按 per-stream 像素数从大到小；像素相同再优先**单核**（复用 b6，风险低），再比 ERAM/时钟。若最大像素行是双核，标 `conditional`（双核时序未证明），并把最佳单核 30 fps@25% 行列为低风险备选。
4. 若没有 30 fps@25% 行：给 1080p 下满足 25% 的最大 fps（单核/双核各一），再给 30 fps 下满足 25% 的最大 16:9 档（单核/双核各一）。
5. 主推荐只能有一个；备选最多两个；每个都要写 `verdict`、per-stream 裕量、所需时钟、资源口径、未证明项。

### 6.4 分辨率/帧率当量

- 连续当量只用于解释，不直接当推荐档；推荐必须吸附到 §6.2 的 16:9 档，避免“1753×986”这类不可落地分辨率。
- 16:9 档的像素数：1920×1080=2,073,600；1728×972=1,679,616；1600×900=1,440,000；1440×810=1,166,400；1280×720=921,600；1152×648=746,496；960×540=518,400。
- 所有档 W/H 可被 4 整除；若未来加入不可整除档，必须按 group 向上取整并单列填充字节。

## 7. 输出合同

### 7.1 P1 产物

```text
T10.dual-core-resource-baseline/r0/
  input-verified.json          # 每个输入的 path/bytes/sha256，0 mismatch
  resource-table.csv           # §3.1
  dual-core-budget.csv         # §3.2
  resource-baseline.md         # 结论、方法、边界、标签
  result-r0.md                 # 开发自述、命令、未测
  lessons.md
  manifest-r0.json             # 唯一冻结 manifest；stopped_modifying=true, active_commands=0
```

### 7.2 P2 产物

```text
T10.dual-aplus-service-verdict/r0/
  input-verified.json
  model/calc.py                # 纯函数；无硬编码结果
  model/rules.json             # 判定规则/门槛/档位
  model/test_calc.py           # 已知值/边界/负对照
  inputs/frozen-inputs.json    # 所有常量、SHA、标签
  out/scenarios.csv            # §6.2 全网格
  out/content-sensitivity.csv  # comp/rand/full_grad
  out/ddr-budget.csv           # §5
  out/frontier.csv             # 1080p fps + 30fps 分辨率前沿
  feasibility-report.md        # 主报告
  result-r0.md
  lessons.md
  manifest-r0.json
```

### 7.3 CSV 最小列

`scenarios.csv`：

```text
scenario_id, cores, streams, W, H, fps, clock_mhz,
cycles_core_per_frame, cycles_chain_per_frame, overhead_assumption,
capacity_core_MBps, capacity_chain_MBps, demand_per_stream_MBps,
margin_core_pct, margin_chain_pct, gate_25_core, gate_25_chain,
drop_rate_lb_pct, eram_bound, eram_total, eram_headroom, verdict, gate_status, notes
```

`capacity_core_MBps` 固定用 comp 内容；`capacity_chain_MBps` 的 1080p 用 full_grad 实测锚点，其他档用 §4.3 的 affine 三档并写 `overhead_assumption`。comp/rand/full_grad 的横向对比放 `content-sensitivity.csv`，不混入本表。

`ddr-budget.csv`：

```text
case_id, streams, fps, raw_write_MBps, raw_read_MBps,
cmp_write_MBps, cmp_read_MBps, ddr_total_MBps, ddr_gate_25_MBps,
required_eff_pct, peak_GBps, includes_cmp_ddr, notes
```

`frontier.csv`：

```text
family, cores, streams, W, H, fps, capacity_basis,
margin_pct, gate_25, is_recommended, notes
```

### 7.4 报告最小章节

1. 结论摘要（一句话 + 3 个关键数字 + `feasible/conditional/infeasible`）。
2. 范围与冻结输入（SHA/工具/标签）。
3. 单核资源/时序基线（routed，含 caveat）。
4. 双核资源表（marginal/conservative/器件余量/210 额度）。
5. 服务率（core-only vs chain；1/2 核；per-stream vs aggregate）。
6. DDR 2R+2S（含所需效率/排除项）。
7. 调度/缓冲服务率与丢帧下界（2 槽假设、drop_rate_lb、槽满丢整帧）。
8. 判定表（39 行摘要 + CSV 路径）。
9. Pareto 前沿与推荐（1 主 + ≤2 备选）。
10. 什么会改变结论（可测阈值）。
11. 风险/未测/G 层/复现命令。

## 8. 测试与证据

### 8.1 独立复现（tester 必做）

- P1：tester 自己解析同一 `routed_area.rpt`/`routed_timing.rpt`，复算顶层与层次资源、WNS/hold/端点；不得只读开发 CSV。至少一项不同判据：从报告原文提取 `#eram/#lut6/#reg/#slice` 与层次行，和开发表逐项比对。
- P2：tester 用独立脚本/手算复算至少 5 个场景（覆盖 1 核/2 核、1080p/低分辨率、core-only/chain），不得 import `calc.py` 作为唯一判据；核对 CSV 与报告、判定规则、前沿极大性、推荐确定性。
- 负对照至少三项：
  1. 把 RAW 槽当 1.0×（或 RAW12）→ 必须被 packing/2R+2S 检查拒绝；
  2. 用 aggregate `2C ≥ 155.52` 判双路 feasible → 必须被 per-stream 检查拒绝；
  3. 把 synth 资源/时序混入 routed 拟合 → 必须被 stage 检查拒绝。
- 输入漂移：测试前后 manifest/关键报告 SHA 必须一致；b11/T08/T10 并行文件不作为本 run 输入，若被引用必须记录快照时间与 SHA。

### 8.2 G 层

| 任务 | G0 | G1 | G2 | G3 | G4 |
|---|---|---|---|---|---|
| P1 | 输入 SHA/字节/manifest | 资源表可复算、层次和=顶层、双核两栏 | `not_applicable`（未综合/未实现） | `not_applicable` | `not_applicable` |
| P2 | 输入 SHA/常量 | 模型/CSV/报告可复现、负对照命中 | `not_applicable`（无 RTL） | `not_applicable` | `not_applicable` |
| P3 | 源副本/SDC SHA | 综合资源/时序检查点 | **仅 G2-syn**（不布线；不是完整 G2） | `not_run` | `not_run` |

**理由**：P1/P2 是只读报告解析与模型/表格，不产生 RTL/bit/板测；不能用无关硬件流程充数。P3 只有综合，不能写“G2 PASS”或“时序签核”。

### 8.3 停止/blocked

- 输入缺失、SHA 漂移、报告行无法解释、DRAMHARDCON 归属矛盾 → `blocked`，problem 写 `INPUT_CONFLICT`/`SCOPE_CLARIFICATION`，不得猜数。
- P2 无法建立链级边界且 core-only/chain 差距会改变结论 → 标 `unproven`，给两栏，不得单选有利值。
- P3 TD 忙/b11 在重建/无放行 → `blocked`，`TOOL_UNAVAILABLE`/`PERMISSION_MISSING`；不排队空转。
- 连续 2 次无新证据/无实质产物/无有效验证 → 主动停止；到调用/时间预算 → 停止。

## 9. 工作目录、工具与构建入口

- 项目根：`D:/fpga/ph1p100`；本 run：`.../20261025-195604_fpga-dual-aplus-core-feasibility`。
- P1/P2 只写各自任务目录；tester 只写 `test-reports/<task_id>/**`。
- Python 3.11.5；无网络依赖；所有命令记录 argv/cwd/exit/timeout/日志。
- TD（仅 P3）：`tools/td/td_env.ps1`，`T:`=任务 `td/`，`Y:`=项目根；`td_commands_prompt.exe`；只综合，不 place/route/bitgen/CWC/download。
- 无 ModelSim 需求；若后续需要，独占 `modelsim.ini`/work/logs，短路径避免 128 字符 TB 限制。
- 禁止 shell 循环绕调用/重试次数；禁止批量删除；失败日志保留。

## 10. 预算（派发前冻结）

| 任务 | 开发 | 综合测试 | TD | 说明 |
|---|---|---|---|---|
| P1 | ≤30 calls / 45 min | ≤30 calls / 45 min | 0 | 只读报告 + CSV + 短报告 |
| P2 | ≤45 calls / 75 min | ≤40 calls / 60 min | 0 | 模型 + 39 行网格 + 测试 + 报告；较默认放宽理由：网格/负对照/报告需额外调用，无长构建 |
| P3 | ≤20 calls / 40 min + 1 次综合 ≤30 min | ≤30 calls / 45 min | 1 session / 1 synth | 仅解阻后；不布线/bitgen/CWC/下载 |

通用：读/搜 60 s；Python 120 s；同失败命令最多首次+1 次有新证据重试；单问题 ≤3 轮搜索/读取；最多 3 轮实际修复；无监控/轮询；不自动扩预算。

## 11. 已冻结 / 待确认 / 不适用

### 11.1 已冻结

- 双路 1920×1080@30 RAW10，per-stream 30 fps，25% 设计门槛。
- 帧/组/槽/内容/DMA/CMP 字节账（§2.1）；20 B/32 B，不用 RAW12/1.0×。
- b6 core SHA、comp/rand/full_grad 锚点、187.5 MHz、单核 Routed 基线。
- 器件总量、routed 资源口径、双核 marginal/conservative 两栏。
- 判定值/顺序、场景网格、CSV/报告 schema、G 层。
- 写范围/保护路径/预算/停止条件。

### 11.2 待确认（由 P1/P2 在任务内核实，不需用户）

- b6 P1 full_grad 的 6,421,414 cycles 边界（是否含 UART、DDR 读/写、槽管理）。
- b10/b11 `#DRAMHARDCON=85` 是否已含在 `#eram` 或另计 300；以报告/构建日志行复核。
- 第二路 camera/writer/bridge 的精确边际资源；marginal 表按层次行估算，conservative 表按整链复制。
- 自然图像/低照内容的最坏服务率；无数据时标 `unproven`。
- 双核共享 256-bit PAXI 的仲裁/延迟；本 run 只做平均带宽，不做桥级 service model。

### 11.3 不适用

- RTL 功能/CDC/STA 签核、bitgen/CWC、下载/Flash、板级吞吐/恢复/曝光同步、PCIe/RK。
- 周期级调度器/one-outstanding reader/PAXI 仲裁时序仿真；本 run 只有帧级服务率/缓冲下界，不能替代 T10/RTL 调度验证。
- G2（P1/P2）、G3/G4（全部）；P3 只有 G2-syn。
- 1080p60、4K、RAW12、三算法共存、深度/NPU。

## 12. 与其他任务/run 的边界

- b11：板卡/COM/JTAG/下载/Flash 归其所有；本 run 只读其报告，不抢 tester/不重建其候选；TD 若冲突 b11 优先。
- T08/T10（20261025-180900）：只读其双路/调度合同与结果；不修改目录、不把本需求加入该 run、不复用其 tester。
- 本 run P3 的综合是**隔离综合**，只写本 run 目录，不改生产 top/源/约束/bit；即使综合通过也不代表生产候选/G2/板级。
- 离线子包完成不把父 T10 或双路目标置 done；`workflow/tasks.json` 不改。
