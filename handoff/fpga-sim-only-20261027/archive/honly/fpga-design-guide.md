# fpga-design-guide — T10.ah-a-plus-h-r2 / T10.ah-honly-td

本指南只冻结本 run 两条线所需的工程语义；未列项沿用被引用文件的原文，不另起冲突标准。规划不把预算值、模型值或历史值写成当前实测。

适用角色：Line A 开发/测试者、Line B 开发/测试者。第 3 包由原规划在收尾时执行，只引用本指南。

---

## 1. 像素/帧（两条线共同，均**不改**）

| 项 | 冻结值 | 来源 |
|---|---|---|
| 输入 | packed RAW10，40 bit = 4 px/beat，`[7:0]=b0 … [39:32]=b4`，`b4[1:0]=P0` | `T10.ah-honly/r0/changed-src/a1_frame_top.v` 文件头 |
| 几何 | W=1920、H=1080，2 行对 = 1 block，540 blocks/帧；transform 字节 2,592,000/帧 | 同上 + coregap 常数 |
| Bayer | 声明 RGGB phase-0 2×2 平面重排（`prep_en`），旁路模式 `prep_en=0` 时 xform 与 raw 逐字节相同 | 同上 |
| 帧裁决 | `in_sof` 采样 `prep_en/pred_en`；`abort` 立即终止不 commit；仅完整有效帧发布 `frame_commit` | 同上 |
| 输出字流 | 32-bit 小端字，`out_keep[3:0]` 为**外部流契约**，`out_last` 仅末字节 | 同上 + r1 lessons §1 |
| A1U1 头 | 44 B（魔数 `41 31 55 31`），`stream_len/raw_crc/xform_crc/stream_crc/header_crc` 语义不变 | b11/P1 冻结 |
| UART 导出 | 字节序、44 B 头、载荷顺序不变 | `a1_uart_export.v` 冻结 |

**红线**：任何角色不得改几何、Bayer 相位/方向、block 大小、A1U1 头布局、CRC 覆盖范围、UART 打包或 `out_keep/out_last` 语义。

---

## 2. Line A：A+H 的算法语义（本任务新增，唯一允许的实现改动）

### 2.1 A 的精确定义（冻结）

在 H-only r1 候选的**独立副本**上增加：

1. **2-position literal 扫描**：每周期对相邻两个输入位置各算一次 hash/命中判定（双端口 htab 读 + 双命中比较），
   仅当**两个位置都确定为 literal** 时同拍提交 2 个 literal 符号；否则退回单位置处理。
2. **双符号 packer**：同一周期最多打包 2 个符号，**且仅当两者码长之和 ≤16 bit**；超过 16 bit 时按原顺序分拍打包。
   因此输出端口仍为 H 的 `OUT_BYTES=2`（≤2 B/周期），**不得**把输出口加宽到 32 bit 或更多。
3. 不得引入：scheme B/C/D/E/F/G、动态 Huffman、跨块引用、多候选匹配、更大 hash 表、更大 MAX_DIST、block 大小变化、
   算法替换、时钟/复位变化。A 只是**调度**改动。

### 2.2 必须成立的等价性不变量（失败即 kill，不允许放宽）

- **token 流逐字节等价**：A+H 的 zlib 输出必须与 H-only r1 完全相同的字节序列（同长度、同 CRC、同 `out_last`）。
  即：hash、候选选择、代价、stored/fixed 决策、block 边界、literal abort guard、Adler、trailer 全部不变；只有"每周期提交几个符号"可以变。
- **bit 顺序**：两个符号同拍打包时，低位符号先、位序与逐符号追加完全一致；不允许位序反转、延迟或补零差异。
- **块边界分割**：当第 1 个 literal 恰好结束当前 block（literal abort guard / 块满）时，第 2 个位置**不得**写入旧 block，
  必须保留到 `S_EOB/S_BHDR` 之后作为新 block 的首个 literal 重新判定。这是本任务最高风险的语义点，必须定向验证。
- **匹配不得被投机吞掉**：若第 1 位置是 literal 而第 2 位置是 match 起点，只提交 1 个 literal，第 2 位置下一拍按 match 路径重新处理；
  允许复用已算出的 hash/命中结果，但前提是状态可证明相同。
- **计数器语义**：`stat_literals / stat_matches / stat_fixed / stat_stored / stat_cand_aborts / stat_blocks /
  stat_max_match / stat_max_dist` 的**含义与数值**必须与逐符号参考一致（数值可因路径不同而仅在 abort 计数上出现已被解释的差异；
  任何差异必须写明根因并证明不影响输出字节）。
- **无 stall**：`SS_STALL / SS_STALL_COLD / B11_FULL_TIMEOUT` 不得出现（1 帧 probe 的"export 后 timeout 伪影"沿用 H-only r1 的既定解释，
  且必须在报告中按 §2.6 显式标注为伪影而非通过项）。

### 2.3 接口冻结（H 已建立，A 不得改）

| 信号 | 冻结 |
|---|---|
| core → frame_top | `out_data[15:0]`（`OUT_BYTES=2`）、`out_keep`、`out_valid/out_ready`、`out_last` |
| `out_keep` 语义 | `keep=1` 表示两字节同拍被接收，**不接受部分接收**；`keep=0` 恒为 8-bit 模式 |
| frame_top → core | `core_out_ready = !svalid && !pend_valid`（pending byte 优先） |
| frame_top → 外部 | `sdata[31:0]`、`skeep[3:0]`、`slast`、`frame_commit/abort`、`st_*` 观测总线 |
| `dbg[31:0]` | H-only 候选新增的只读观测口；A 可原样透传，**不得**用于功能 |

### 2.4 缓存/缓冲（A 可触碰的边界）

- `cmem`：H 为 2048×32 b（65,536 bit 总量不变）；A 不得再改容量/位宽，除非能证明 `ERAM` 与逐字节等价同时成立并写明理由。
- 输出 FIFO：16 项 × {last, keep, byte1, byte0}；skid FIFO 4 项 × {last, nbits1, nbits0, byte1, byte0}。
  A 若新增"待提交第 2 符号"寄存器，必须给出复位值、abort 清除路径与满/空判定，且不得改变外部可见顺序。
- packer 累积器：H 为 24 b `oacc` + `obits`；A 若扩宽必须 ≤32 b 并证明满 2 B/周期时无溢出、无丢 bit。

### 2.5 时序/时钟/复位（两条线一致）

| 项 | 冻结 |
|---|---|
| 时钟 | 单时钟 `clk` = 187.5 MHz（5.333 ns）；仿真用 TB 既有周期，不改 |
| 复位 | 异步低有效 `rst_n`；abort 撤销 pending（`pend_valid`）逻辑沿用 r1 |
| 域 | 无新增 CDC、无异步 FIFO；`clk_uart` 仅为导出域，A 不得跨界 |
| bitgen/板卡 | **0**（Line A 与 Line B 本轮均无 bitgen/CWC/下载/Flash/上板） |

### 2.6 Line A 证据约定

| 证据 | 冻结要求 |
|---|---|
| 编译 | 每个 build 目录独立 `work/`，复制安装 `modelsim.ini`（r1 lessons §4）；`vlog -sv +define+SIMULATION`，Errors 0；Warnings 必须与 H-only r1 的 21 条同源（`camera_a1_uart_top.v:543`），新增告警必须解释 |
| 命令簿记 | 全部 `vlib/vlog/vsim` 写入 `sim/commands-r0.jsonl`：argv、cwd、rc、timed_out、seconds、timeout_s、log、stdout |
| b6 bench | 8-bit（`OUT_BYTES=1` 默认）与 16-bit（`OUT_BYTES=2`）各跑 comp/rand，`+BP=0 +GAP=0 +TIMEOUT=2000000`；比对冻结 SHA/长度（§input-index §1），并用 Python `zlib.decompress` 独立解码还原输入 |
| 1 帧 probe（N） | `FRAMES=1 CONTENT=2 PACING=0 SINK=1 CAPTURE=0 MAX_CYCLES=13300000`；必须打印 `CORE_STAGE`；`core_interval = t_enc(1) − t_pub(1)`；cycles/B = core_interval / 2,592,000 |
| 4 帧（N、L） | `FRAMES=4 CONTENT=2 PACING=0 SINK=1 CAPTURE=0 MAX_CYCLES=60000000`；`S_ss=(S_23+S_34)/2`，保留半周期精确值；4 帧 header/CRC/length/last byte 与 §input-index §1 基准逐字节比较（整文件 SHA） |
| adapter | `tb_adapter_directed` 原样（SHA `56066e70…`），12/12；`force/release` 只允许内部网，DUT 不改 |
| 资源 | 只写 `estimate`，标注为估算；**不得**出现任何 TD/综合/时序数字 |
| 4 帧计数器 | 4 帧 TB 无 core counter tap（r1 OBS-10）；如需 per-frame 计数器，只能在**新增 TB 副本**里加只读 hierarchical tap，并在改动前记录 SHA |

**明确不证明**：A+H 的 TD/时序/资源、板级、自然传感器 RAW、生产 sink、双路、G0 整机闭合。

---

## 3. Line B：TD 工程语义（本任务只读 DUT）

### 3.1 repo binding（冻结）

- DUT 用 **H-only r1 冻结候选**的绝对只读路径（§input-index §1），**不使用** `D:/fpga/repos/ph1p100-pcie-ep-fpga` 的同名文件替代（diff 未迁移）。
- 不 commit/push/fork/改 `main`；新仓本轮 0 写入。
- TD 工程只落在本 run 自己的任务目录；不得引用、不得写入其它 run 的 TD 目录。

### 3.2 顶层与约束（冻结）

- 顶层：本任务新建的 **build-only 包装** `a1_ah_eng_top`（非候选 RTL、不得进入 manifest 的 candidate 列表），
  原样例化 `a1_frame_top #(W=1920,H=1080)`，把 7 路 status 折成 1 路 XOR（同 b11 `a1_eng_top.v` 做法），
  并**必须连接** H-only 新增的 `dbg[31:0]`（可并入 XOR 或引到未使用输出，不得悬空致综合报 undriven）。
- 端口：`clk, rst_n, in_pix[39:0], in_valid, in_ready, in_sof, prep_en, pred_en, abort,
  out_data[31:0], out_valid, out_ready, out_keep[3:0], out_last, frame_commit, frame_abort, st_dbg[31:0]`。
- 约束：单一 `create_clock -name clk -period 5.333 -waveform {0.000 2.667} [get_ports clk]`；
  **禁止** false_path / multicycle / clock group 例外 / IO 约束造假；块级 IO 不加约束是**已知缺口**，必须写入报告（沿用 b11/r10 口径）。
- 器件：`PH1P100SBG484`，`-speed 3`，family `PH1`；工程目录 `create_project <prj> ./ -family PH1 -device PH1P100SBG484 -speed 3 -force`。

### 3.3 流程与配额（冻结）

| 项 | 值 |
|---|---|
| 综合 | **1 次**（187.5 MHz，5.333 ns） |
| 布线 | **≤2 次**（第 2 次仅在第 1 次失败时，且必须写明具体参数差异；不做 seed 扫描） |
| 209.6 MHz | **analysis-only**：同一 routed DB，仅把时钟收紧到 `4.777 ns` 重新 `update_timing`/`report_timing`。**不是** 209.6 布线结果，报告必须如此标注 |
| bitgen / CWC / 下载 / Flash / 板卡 / COM / JTAG / RK / 网络 | **0 / 0 / 0 / 0 / 0 / 0 / 0 / 0 / 0** |
| 工程位置 | `workflow/runs/20261027-055621_fpga-honly-td-and-ah/T10.ah-honly-td/r0/td/**` |
| CLI | `D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe ./<script>.tcl`，cwd = 该 td 目录 |
| 盘符 | 需要 `T:` 时只允许 `td_env.ps1 -TdDir <本任务 td>`（**禁止 `-Force`**）；`T:` 被他人占用即记冲突、不抢占；tcl 一律用绝对路径因此 `T:`/`Y:` 非必需 |

### 3.4 判定门槛（Line B，冻结）

| 项 | 门槛 |
|---|---|
| 综合报告完整性 | `flow.status` 的 `NUM_FEPS`（Viol Endpoints）+ WNS/TNS + hold；area 的 `#slice*/#reg/#eram/#fifo20k`；STA coverage；缺任一 → 视为证据不完整 |
| 实现资格 | routed DB 上 **WNS ≥ 0 且 hold ≥ 0 且 0 violated endpoints**，且 `ERAM+CWC ≤ 300`、`LUT6(slice) ≤ 71,680`、`IO ≤ 286` |
| 不通过的处理 | 保留真实数字，写 `not_eligible`，**不得**用放宽时钟/加例外/换 seed 掩盖；如 187.5 失败，给出 209.6 analysis 数字并注明其性质 |
| 关键路径归因 | 必须列出 routed 报告最差 ≥10 条路径的起点/终点/层级，并特别回答：最差路径是否落在 `a1_frame_top` 的双 CRC32 链、`a1_deflate_core` 的 replay/emit 锥、或 scan 锥 |
| CDC | 单时钟设计：`report_cdc` 与 `check_timing -verbose` 必须执行并附报告；任何未约束路径/生成时钟/loop 必须列出，不得静默 |
| 工具/版本 | 记录 `td_commands_prompt` 版本行（Build number）与 run 日志名；license 缺失（RUN-8008）→ `blocked=TOOL_UNAVAILABLE` |

### 3.5 TD 独占与租约（冻结）

1. 开 TD 前必须做一次只读 preflight：无 `pnmain/td/td_commands_prompt/run` 进程；`20261026-2138_fpga-integrated-delivery/INT.P4/td/**` 与其 `INT.P4/r3/**` 在最近 **20 min** 无写入。
2. `INT.P4-r3-manifest.json` **不存在**即视为该 run 的 TD 窗口仍然开启 → **不得**开 TD。
3. **本轮（r0）明确不执行任何 TD 调用**：本轮只做 TD-free 准备与一次 `vlog` 端口绑定检查。TD 执行属于恢复后的轮次（见 dev-plan §8）。
4. 不得 kill 他人的 vsim/TD 进程；不得共享工程/库/日志/盘符；不得用 `-Force` 改 `T:`。
5. 恢复轮同样一次只做一串 TD 会话（synth，必要时 route），不并行开第二个 TD 会话。

### 3.6 Line B 证据约定

- 报告族：`r0/reports/synth-187.5.md`、`r0/reports/routed-sta.md`（若布线）、`r0/reports/analysis-209.6.md`（若做）、
  `r0/reports/critical-path-attribution.md`、`r0/reports/resources.md`、`r0/reports/cdc-and-check-timing.md`。
- 每个 TD run 独立子目录（`r0/td/syn_run1/`、`r0/td/route_run1/`…），日志、`.timing/.area/flow.status` 原样保留，不复制覆盖。
- `manifest-r0.json`：DUT 2 文件 SHA、wrapper/SDC/tcl SHA、每个 TD run 的目录与关键产物、命令 argv/rc/seconds、`stopped_modifying=true`、`active_commands=0`。
- 报告必须把"已连接 / 已验证 / 未运行"分开，禁止把综合当布线、把 analysis-only 当布线、把 block-level 当整机。

---

## 4. 工作目录与构建入口（冻结）

| 角色 | 工作目录 | 允许写 | 禁止写 |
|---|---|---|---|
| Line A 开发 | `D:/fpga/ph1p100`（cwd 不限） | `workflow/runs/20261027-055621_fpga-honly-td-and-ah/T10.ah-a-plus-h-r2/**`；`%TEMP%/opencode/ah-a/**` | 其他 run、`fpga/csi2/src/**`、`docs`、`tasks.json`、`.agents`、`D:/TD`、repos、板卡 |
| Line A 测试者 | 同项目根 | `.../20261027-055621.../test-reports/T10.ah-a-plus-h-r2/**` | 同上 + 候选目录 |
| Line B 开发 | 项目根 | `.../T10.ah-honly-td/**`（本轮仅 `r0/prepared/`、`r0/manifest-inputs-r0.json`、`r0/result-blocked-r0.md`、`r0/lessons-r0.md`、`r0/lint/**`） | 其他 run、所有 TD 产物（本轮 0 次）、生产源、`T:` 抢占 |
| Line B 测试者 | 项目根 | `.../test-reports/T10.ah-honly-td/**` | 同上 |

- 仿真工具：ModelSim Intel FPGA Edition 10.5b，`D:/intelFPGA/18.1/modelsim_ase/win32aloem`；Python 3.11.5 用于哈希/解析/zlib 独立解码。
- Line A 的候选与 TB **全部复制**到自己的 `r0/changed-src/`、`r0/src/`（引用 `src/` 中的冻结 12 DUT 时用只读绝对路径，不得改写）。
- 盘符：仿真用 `P:`（项目根）/`W:`（run 目录）可选；**Line A 不得使用 `T:`**；`X:` 保留给 TD，任何角色不得映射到项目根。

---

## 5. 已冻结 / 待确认 / 不适用

**已冻结**：DUT（H-only r1 core/frame_top + SHA）、A 的语义与等价性不变量、输出口宽度 ≤2 B/周期、187.5 MHz/5.333 ns、单时钟无 CDC、TD 配额（1 syn + ≤2 route + 0 bitgen）、block-level IO 不约束的已知缺口、209.6 为 analysis-only、TD 本轮 0 调用、两线写范围与保护范围、证据与 manifest 约定。

**待确认（不阻塞本轮）**：
1. TD license 实际路径与可用性（以真实启动日志为准，缺失即 blocked）。
2. A+H 若使 1 帧 probe 的 `stat_*` 出现语义差异——只允许"已解释且不影响输出字节"的差异，最终由测试者按 §2.2 判。
3. Line B 恢复轮的具体日期取决于 integrated delivery round3 何时冻结。

**不适用（附理由，后续不得临场改判）**：
- Line A：G2（综合/时序/资源实测）**not_applicable**——用户明确 0 TD/综合/布线，实质只是离线 RTL/仿真包；G3（bitgen/CWC/下载）**not_applicable**；G4（板卡）**not_applicable**；G0 只作 "prototype 4-frame S_ss gate"，**不声称整机闭合**。
- Line B（本轮 r0 准备轮）：functional 仅到"端口绑定编译通过 + 输入哈希一致"，**不声称 DUT 功能**；G1 = 输入/准备产物哈希；G2 = **not_run（TD 租约被占）**；G3/G4 = not_applicable（0 bitgen/0 板卡）。
- Line B（恢复轮）：G2 = 真实 TD 综合/布线/STA；G3/G4 仍 not_applicable。
- 第 3 包：G0–G4 全部 not_applicable（0 sim、0 TD、纯文档合并）。

**能力边界**：Line A 的 PASS 只证明"prototype 4 帧 S_ss ≤6.25M 且逐字节等价"，Line B 的 PASS 只证明"该冻结候选在 TD 187.5 MHz 的实现资格"，两者都不等于 G0 整机闭合、不等于板级、不等于生产 sink 或双路。
