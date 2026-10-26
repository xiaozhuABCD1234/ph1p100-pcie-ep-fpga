# T10.b17-paxi-native — fpga-design-guide（冻结，2026-10-26）

只冻结本任务需要、且开发/综合测试必须按同一口径引用的数据、接口、参数、时序/缓冲、构建入口与证据约定。与 `dev-plan.md` 冲突时以 dev-plan 为准。

## 1. 原生 PAXI 合同（本包核心）

### 1.1 地址单位

| 层 | 单位 | 值/规则 |
|---|---|---|
| store / arb / camera top / shell | **256-bit 字下标** | 每个 256-bit 字 `+1`；最大合法字下标 `424313` |
| bridge 内部 FIFO | 27-bit 字下标 | `wf_rdata[282:256]` / `af_rdata[26:0]` |
| **唯一 PAXI 边界（bridge 输出）** | **原生地址** | `{word_index[23:0], 3'b000}`；字 0/1/2 → 0/8/16 |
| 模型 | 原生地址 | `word = addr[26:3]`；`addr[2:0]` 必须为 0 |

- AW/AR 都转换；不得只在读或只在写转换。
- 合法范围 `0..424313`；范围检查见 §1.4。
- 不允许在 store/arb/camera top/shell 重复乘 8；内部槽保持字单位。

### 1.2 写 mask

| 项 | 冻结值/语义 |
|---|---|
| `paxi_wstrb` | **`32'h0000_0000`**（写整字） |
| 原生语义 | bit=0 使能该字节；bit=1 保持原字节；全 0 = 全字写，全 1 = 不写 |
| 生成 wrapper | 只做位重排，不替 bridge 取反 |
| 模型 | 必须按上述语义逐字节合并；不得忽略 mask |
| 正常板级 | `wstrb_nonzero_seen=0`；模型 `n_mask_nonzero=0` |

### 1.3 命令接纳

| 项 | 冻结 |
|---|---|
| 默认 | `ALLOW_CONCURRENT=0`：AW/W 与 AR **互斥**；同一拍不得同时 `aw_hs` 与 `ar_hs`，也不得同时 `w_hs` 与 `ar_hs` |
| 组合仲裁 | `wr_start_req = wf_rvalid && !wf_pop && ddr_rdy && !ar_busy`；`rd_req = af_rvalid && !ar_busy && rf_path_empty && ddr_rdy && !rd_hold && (wstate==W_IDLE)`；`paxi_arvalid = rd_req && !wr_start_req`（写优先）；`W_IDLE→W_RUN` 按 `wr_start_req`。该条专门消除“写启动与 AR 同拍”的边界 |
| 写命令 | AW/W 可同拍握手（单拍写，`wlast=1`）；作为**一个**写命令 |
| 读命令 | 单笔 AR，`ar_busy` 到 `rlast`；b15 的 R1–R5 保留 |
| 对照 | `ALLOW_CONCURRENT=1` 仅用于后续吞吐/合同对照，**不得**进入本包 bitgen/板级 |
| 模型 | `awready`/`arready` 不得同拍为 1；`n_same_hs` 必须 0；`n_same_req` 用于检测 DUT 同拍请求 |

### 1.4 范围/低 3 位检查

- 组合：`aw_idx_oob = wf_rdata[282:256] > 24'd424313`；`ar_idx_oob = af_rdata > 24'd424313`。
- sticky：`oob_addr_seen`（v6 `diag_flags[3]`）；`low3_nonzero_seen`（`diag_flags[4]`）；只在 `rst_n && wf_rvalid/af_rvalid` 时评估，避免空 FIFO/复位垃圾误置位。
- 仿真：越界地址被发出时 `$fatal`（`ifndef SYNTHESIS` 或等价）；综合路径不新增死锁分支。
- 模型：硬检查；坏地址不得别名，写拍消费并计数，读拍返回 poison 且 `rlast=1`（不挂死）。

## 2. 状态包 v6（冻结）

### 2.1 包结构

| 项 | 值 |
|---|---|
| 总长 | **273 B** |
| 头部 | `A5 5A 11 06` |
| 字段 | **67 × u32 LE**（v5 #1..#59 不变；追加 #60..#67） |
| 校验 | XOR8 over bytes 0..271，放在 byte 272 |
| 版本/长度 | `VER=6`、`LEN=273`（低字节 `0x11`） |
| 快照 | 单边沿、整包一致；不得在帧传输途中插入 |

### 2.2 字段 #60..#67

| # | 名称 | 位宽/来源 |
|---:|---|---|
| 60 | `last_issued_ar_addr` | 27-bit 原生 AR 地址，零扩展 u32 |
| 61 | `last_issued_ar_low3` | `last_issued_ar_addr[2:0]` |
| 62 | `timeout_ar_addr` | `purge_evt` 时若 `ar_busy`，锁存最近 AR 地址 |
| 63 | `timeout_ar_low3` | 上述低 3 位 |
| 64 | `same_aw_ar_cnt` | AW+AR 同拍握手计数 |
| 65 | `same_w_ar_cnt` | W+AR 同拍握手计数 |
| 66 | `inflight_state` | `[0] ar_busy [1] aw_seen [2] w_seen [3] wstate [4] ddr_rdy [5] rd_hold [6] rf_path_empty [7] paxi_arvalid` |
| 67 | `diag_flags` | `[0] timeout_ar_valid [1] same_aw_ar_seen [2] same_w_ar_seen [3] oob_addr_seen [4] low3_nonzero_seen [5] wstrb_nonzero_seen` |

- `timeout_ar_valid` 在成功 `rlast` 或复位清除；`timeout_ar_addr` 保持最后失败值。
- `same_*_seen` / `oob_addr_seen` / `low3_nonzero_seen` / `wstrb_nonzero_seen` 为 sticky，复位清除。
- 正常健康板级：`diag_flags` bit1..bit5 = 0；bit0 = 0（无超时）。

### 2.3 诊断总线打包（bridge `dbg_a1` 512 bit）

旧 256 bit `[255:0]` 布局保持不变：

```text
[255:224] purge_cnt
[223:192] stale_guard_cnt
[191:160] stale_r_cnt
[159:128] rlast_cnt
[127:96]  r_cnt
[95:64]   ar_block_cnt
[63:32]   ar_cnt
[31:0]    br0
```

新 256 bit `[511:256]`，从高到低：

```text
[511:480] diag_flags
[479:448] inflight_state
[447:416] same_w_ar_cnt
[415:384] same_aw_ar_cnt
[383:352] timeout_ar_low3
[351:320] timeout_ar_addr
[319:288] last_issued_ar_low3
[287:256] last_issued_ar_addr
```

- `dbg_a1` 512 bit；`cam_diag_mailbox` 实例 `W=512`；模块本体不变。
- `camera_a1_uart_top.i_dbg_bridge` 512 bit；`sts_ext_bus` 768 bit；`a1_uart_export.sts_ext` 768 bit；`extsnap` 768 bit；`allsnap` 2144 bit。
- v5 #44..#59 的位序/来源不变；v6 #60..#67 追加在高位。

### 2.4 包构造常量

```verilog
localparam [8:0] STS_LAST = 9'd272;  // XOR byte
localparam [8:0] STS_LEN  = 9'd273;  // 4 + 67*4 + 1
localparam [7:0] STS_VER  = 8'd6;
// sidx / sbyte_i 9 bit; allsnap = {extsnap(768), rawsnap(640), camsnap(480), ssnap(256)} = 2144 bit
// sbyte_i = sidx - 4; byte index into allsnap: {sbyte_i,3'b000} +: 8
```

- `p[2] = 8'h11`、`p[3] = 8'h06`；parser 同时接受 `VER=5/LEN=241/59` 与 `VER=6/LEN=273/67`。

## 3. 帧格式（冻结，不动）

| 项 | 值 |
|---|---|
| 帧头 | 44 B；`A1U1`，ver=1，header_len=44 |
| 四 CRC | header/stream/xform/raw |
| 压缩 | deflate/zlib；严格 EOF、无 trailing |
| RAW | 2,592,000 B |
| crop | `CAM_W=3864, CAM_H=2192, ROI_X=972, ROI_Y=556, W=1920, H=1080` |
| 槽 | 四槽 DDR（raw pair + cmp pair）；最大字下标 424313 |
| UART | `UART_DIV=1628`、`HB_DIV` 不变 |

## 4. 时序/缓冲/复位（冻结）

| 参数 | 值 | 说明 |
|---|---|---|
| `MAX_OS` | 1 | 一笔 AR 在途；b15 规则保留 |
| `ar_busy` 清除 | `rvalid && rready && rlast` | purge/guard 强清保留 |
| `paxi_rready` | 恒 1 | 不靠背压保数据 |
| `TIMEOUT` | 8192 clk_a1 | b13 值 |
| `RETRY_MAX` | 2 | b13 值 |
| `A1_GUARD_N` / `BRIDGE_GUARD_N` / `A1_PURGE_N` / `DDR_PURGE_N` | 70000 / 65536 / 4 / 4 | b13 值 |
| `clk_a1` / 像素时钟 | 111.375 MHz / 187.5 MHz | 不改频率/PLL |
| RF | `WIDTH=256, ADDR_BITS=4`（16 深） | `L_max=1` 已证；不改深度 |
| CDC | 既有 toggle+2FF / Gray FIFO | 不新增时钟域；不直接跨域采样多 bit |
| SDC | 不改 | `p2_board.sdc` diff 必须为空 |

## 5. 工作目录与构建入口

| 项 | 路径 |
|---|---|
| 任务目录 | `D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b17-paxi-native` |
| 源副本 | `<task>/r0/changed-src/`（11 文件，复制自 b15 r0） |
| 仿真 | `<task>/r0/sim/`（`W:`=该目录，`P:`=项目根） |
| TD | `<task>/r0/td/`（`T:`=该目录，`Y:`=项目根；`X:` 不映射项目根） |
| 构建 | `r0/td/01_build.tcl` → `02_bitgen.tcl` → `03_cwc.tcl` |
| 板级 | `<task>/r0/board/`（`dl_b17.tcl`、`run_board_b17.ps1`、`capture_com8.py`、`parse_status_v6.py`、`check_b17_board.py`） |

- 打开 TD 前先运行 `tools/td/open_td.ps1` 或 `tools/td/td_env.ps1`（见 `tools/td/PATH_CONTRACT.md`）。
- 临时 ModelSim work 库/INI/日志只写 `%TEMP%\opencode\T10.b17-paxi-native\`；不写项目根或其他 run。
- 不改 `D:/TD/work/csi2/**`，不写 Flash。
- 构建模板 `T10.b15-ddr-pace/r0/td/**`；只改 `01_build.tcl`/`a1_board.al` 的 `changed-src` 路径，流程/参数/seed 不变。

## 6. 证据约定

- 每个门槛都要有机器可判的落盘证据：sim 日志/JSON、TD 报告摘要/STA、板级原始 bin + v6 解析文本 + gate JSON。
- 权威来源唯一：result 引用准确文件名，不写“见日志”。
- 哈希：`r0/artifact-hashes.txt` 覆盖 11 个 changed-src、bit、CWC、BID、`cw/compiled.*`；manifest 自洽。
- 板级失败必须落：`last_issued_ar_addr` 首/末、`last_issued_ar_low3`、`timeout_ar_addr`、`timeout_ar_low3`、`timeout_ar_valid`、`same_aw_ar_cnt`、`same_w_ar_cnt`、`inflight_state`、`diag_flags`、`ar/r/rlast/stale_guard/stale_r` 首末差分、失败帧号/尝试号。
- 所有 v6 地址字段均为**原生 PAXI 地址**，不是 256-bit 字下标；字下标 = `addr >> 3`（调试时换算，不写入包）。

## 7. 基线哈希（只读引用）

| 文件 | SHA256 |
|---|---|
| b15 `p2_ddr_bridge.v` | `EB9DF41F9404E40CD31DBF12BC65F29ED965A9FC6C2E604F027AA9AD158954E3` |
| b15 `camera_a1_uart_top.v` | `ACC1EFF329AA295D01B16123581FEE48EF49D444EFDCE3B7FE62214555517405` |
| b15 `p2_a1_board_top.v` | `48881D574352FD2C61F7587D3687F215BB11EA18D5B5D0B4772820A938DE561B` |
| b15 `a1_uart_export.v` | `F8F9E4E354B5BDBCCE56321CACB22981F1283565EC6C40479A90D0625CE76B61` |
| b15 `f9p_camera_display_core.v` | `C9DE0D9C176E830DF35833EFF7E91B811D954FB5480BC13E1FB122EF23305089` |
| b15 `a1_ddr_slot_store.v` | `6C619CF90E54385D667F1EC0F63CC87EE58AADD3C42143330AC4945EB47DEFE9` |
| b15 `a1_ddr_arb2.v` | `B84019BDA057AFE82FF558E0848D6171FA12732BD8CDB7C6239CB71B3F81D6BA` |
| b15 `a1_frame_top.v` | `0064607ACEB20AE3EF14133F0AAF5F8B3F489943011A66A1DDC005350DBA7109` |
| b15 `a1_deflate_core.v` | `A91C2ED82FBEF654C4E065B64AE1CC268CA232FEAA26FDD313C58D8740F81B3E` |
| b15 `a1_raw_crop.v` | `33A6FEE77FD1AA67A31CACF26DD5530E5E2EA474EE655CBD5F1D98D887C5D72D` |
| b15 `cam_diag_mailbox.v` | `352AF7C85094EA99B575E99DA952AF8D33871352140E4C6EFDDFF9E6C2407278` |

P1 黄金 caps：`micro8x2.dec` `FA513A2B5A7F268BE9F29D62AEA6C44AAAB796D0F23256B0E1049F50ACCEEDEF`；`mid64x8.dec` `EE61E6200D9ABCA66C5A74A0CBBD9DDE982F1D4652647F8B0D67E5964F3E9789`；`full_grad.dec` `B992A8AD74063545CFEBB67E59EFC83B4136133A0C19479A18C05C343D48ADA9`。
