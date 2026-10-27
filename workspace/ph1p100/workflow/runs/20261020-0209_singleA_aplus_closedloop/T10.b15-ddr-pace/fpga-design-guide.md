# T10.b15-ddr-pace — fpga-design-guide（冻结，2026-10-26）

只冻结本任务需要、且开发/综合测试必须按同一口径引用的数据、接口、参数、时序/缓冲、构建入口与证据约定。与 `dev-plan.md` 冲突时以 dev-plan 为准。

## 1. 数据格式（冻结，不做任何扩展）

### 1.1 状态包 v5（**逐字节不变**）

| 项 | 值 |
|---|---|
| 总长 | **241 B** = magic(4) + 59×u32(236) + XOR8(1) |
| 字段数 | **59**（`ST_FIELDS=59`，`parse_status_v5.py` 已一致） |
| 版本 | `VER=5`，`LEN=241` |
| 校验 | 对偏移 0..239 做 XOR8 |
| 快照 | 单边沿、整包一致；**不得在帧传输途中插入** |
| 本包新增字段 | **无** |

- 读通路证据只用既有字段：`ar_cnt`(#?)、`r_cnt`、`rlast_cnt`、`stale_r_cnt`、`stale_guard_cnt`、`rd_wait_cycles`、`timeout_cnt`、`retry_cnt`、`giveup_cnt`。
- `parse_status_v5.py` 允许的唯一改动：在行打印中补 `rlast=%d`（读 `s["rlast_cnt"]`）。**禁止**改 `ST_FIELDS`、`NAMES` 顺序、包长判定、CRC/XOR 判定。
- 板上判 outstanding：`outstanding = ar_cnt - rlast_cnt`（静止期望 ≤1）、`lost = ar_cnt - r_cnt`（在途上限 `L_max-1`）。

### 1.2 帧格式（冻结，不动）

44 B 帧头 + 四 CRC（header/stream/xform/raw）+ deflate/zlib 流；RAW 帧 2,592,000 B；crop 几何 `CAM_W=3864, CAM_H=2192, ROI_X=972, ROI_Y=556, W=1920, H=1080`；四槽 DDR 布局、UART_DIV=1628、HB_DIV 不变。

## 2. 接口（本包唯一改动面：`p2_ddr_bridge.v` 读通路）

### 2.1 PAXI 读端口（只读理解，不改协议）

| 信号 | 方向 | 冻结语义 |
|---|---|---|
| `paxi_araddr[26:0]` | out | 来自 AF（地址 FIFO） |
| `paxi_arvalid/arready` | out/in | 一笔 AR 的握手；本包要求**严格单笔在途** |
| `paxi_rvalid/rready` | in/out | 本包要求 `rready` **在整笔 burst 与 purge/guard 窗口内恒 1** |
| `paxi_rdata[255:0]` | in | 每拍 32 B |
| `paxi_rlast` | in | **唯一**允许关闭一笔 AR 的条件 |

- `L_max`（每笔 AR 的 burst 拍数）必须由开发在 W1 从 IP 端口/参数或波形取证后写入 `r0/diag/paxi-read-facts.md`；**不得假设**。若 `L_max` 不可取证，按最保守值取 `L_max = RF_DEPTH`。
- 不得新增/删除 PAXI 端口，不得改 `paxi_aw*`/`paxi_w*`/`paxi_b*` 写通路。

### 2.2 A1 侧读接口（`s_araddr/s_arvalid/s_arready`、`s_rdata/s_rvalid/s_rready`）

保持不变；`s_arready = af_wready && !a1_purge_act && !a1_ar_hold_act` 的门控语义保留。

## 3. 时序与并发（冻结）

| 参数 | 值 | 说明 |
|---|---|---|
| `MAX_OS` | **1**（默认） | 未完成 AR 上限；2 仅在 §R6 条件下且书面批准 |
| `ar_busy` 清除 | 仅 `rvalid && rready && rlast` | 禁止首拍清 |
| `paxi_rready` | **恒 1** | 不靠背压保数据 |
| `TIMEOUT` | 8192 clk_a1 | b13 值，保留为兜底 |
| `RETRY_MAX` | 2 | b13 值 |
| `A1_GUARD_N` / `BRIDGE_GUARD_N` / `A1_PURGE_N` / `DDR_PURGE_N` | 70000 / 65536 / 4 / 4 | b13 值，不改 |
| `clk_a1` / `clk_ddr` / 像素时钟 | 111.375 MHz / 既有 / 187.5 MHz | 不改频率、不改 PLL |
| 吞吐下限 | ≥77.76 MB/s（持续） | 1 笔 AR 方案必须满足，否则按 R6 评估 2 笔 |

## 4. 缓冲（冻结 + 唯一允许的参数调整）

| 缓冲 | 现状 | 本包规则 |
|---|---|---|
| AF（地址 FIFO） | `capture_async_fifo` 27 bit，clk_a1→clk_ddr | 结构不变；只在 AR 握手时弹 |
| RF（读数据 FIFO） | `WIDTH=256, ADDR_BITS=4`（16 深，4096 bit） | 结构不变；**若 `L_max > 16`** 允许把实例参数改 `ADDR_BITS=5`（32 深），须记资源代价；不得改模块本体 |
| skid（`s_rdata_r`） | 1 深 | 不变 |
| 写入侧 WF | 不变 | 不动 |

- 溢出安全由 **发 AR 前置条件**（`rf_path_empty` 或 `rf_level ≤ DEPTH - L_max`）保证，**不得**用 `rready=0` 背压兜底。

## 5. 复位/CDC（冻结）

- 单 `rst_n` 域交叉沿用既有 toggle+2FF 风格（`rd_abort` 已如此）。新增的 `rf_level` 递减必须用 **toggle 跨域 + 2FF**（clk_a1 pop 计数 → clk_ddr），不得直接跨域采样多 bit 计数器。
- 不得新增时钟域、不得新增 generated clock、不得改 `p2_board.sdc`（SDC diff 必须为空）。

## 6. 工作目录与构建入口（冻结）

| 项 | 路径 |
|---|---|
| 任务目录 | `D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b15-ddr-pace` |
| 源副本 | `<task>/r0/changed-src/`（11 文件，复制自 b13 r1） |
| 仿真 | `<task>/r0/sim/`（`W:` = 该目录，`P:` = 项目根） |
| TD | `<task>/r0/td/`（`T:` = 该目录，`Y:` = 项目根；`X:` 不映射项目根） |
| 构建入口 | `r0/td/01_build.tcl`（综合/布线）→ `02_bitgen.tcl` → `03_cwc.tcl` |
| 板级 | `<task>/r0/board/`（`dl_b15.tcl`、`run_board_r0.ps1`、`capture_com8.py`、`parse_status_v5.py`） |

- 打开 TD 前先运行 `tools/td/open_td.ps1` 或 `tools/td/td_env.ps1`（见 `tools/td/PATH_CONTRACT.md`）。
- 不改 `D:/TD/work/csi2/**`，不写 Flash。

## 7. 证据约定

- 每个门槛都要有**机器可判**的落盘证据：sim 日志/JSON（`r0/sim/*.json`）、TD 报告摘要（`r0/td/*.log` + `final STA` 文本）、板级原始 bin + 解析文本（`r0/board/captures/*`）。
- 同一结论只允许一个权威来源路径；result 里引用准确文件名，不写“见日志”。
- 哈希：`r0/artifact-hashes.txt` 列 `changed-src` 全部 11 文件、bit、CWC、BID、`cw/compiled.*`；manifest 自洽。
- 板级失败时（§7.4）必须落：`ar/r/rlast/stale_guard/stale_r` 首末差分、失败帧号/尝试号、`L_max`、以及仿真 `last_ar_addr` 的对应记录。
