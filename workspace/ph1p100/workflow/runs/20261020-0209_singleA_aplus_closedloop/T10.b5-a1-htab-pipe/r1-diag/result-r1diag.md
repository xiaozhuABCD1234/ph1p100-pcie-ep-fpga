# T10.b5-a1-htab-pipe r1-diag -- 状态包诊断结果（单次 SRAM 下载）

日期：2026-10-24 22:13–22:15。开发角色单会话（fpga-dev 代理不可用，general 代行）。
本轮**只做诊断**：把空闲心跳 `0x55` 换成 `A5 5A` + 8 个 32-bit 计数器状态包，
重建 r0 候选、1 次 SRAM 下载、COM8 115200 采 60 s，定位卡在哪一级。

## 1. 结论（一句话）

**8 个计数器在 60 s 内全部为 0**：`cap_frames=0` 说明 `a1_raw_crop` 从未收到一个完整 ROI 帧，
故障在**相机前端（IMX415/MIPI RX → f9p tap → crop）**，不在 raw 发布、A+ 读/压缩、压缩发布或导出。
状态包本身 61/61 全对（XOR 0 错误），证明 FPGA 已配置、`clk_a1` 正常、`a1_rst_n` 已释放、
DDR ready、UART TX 完好。

| 计数器 | 值（16 进制 / 10 进制） |
|---|---|
| cap_frames | `0x00000000` / 0 |
| raw_pub | `0x00000000` / 0 |
| enc_frames | `0x00000000` / 0 |
| exported | `0x00000000` / 0 |
| raw_drop | `0x00000000` / 0 |
| cmp_drop | `0x00000000` / 0 |
| errors | `0x00000000` / 0 |
| read_words | `0x00000000` / 0 |

首包与末包完全相同，delta 全 0（`captures/status_60s.txt`）。

## 2. 已确认的输入事实（未重复排查）

- UART 物理通路正常（回环 bit 验证）；r5 bit 的 `0x55` 心跳能被 PC 收到；
  但 A+ 压缩帧没有产出，串口 240 s 只有心跳。
- LED1（`dbg_exported != 0`）不可信：本次 `exported=0` 且 LED1 判断的是"非零锁存"，
  与"是否出帧"无稳定对应关系，后续不要再用它判定。

## 3. 变更（仅 2 个文件，包内副本）

`r1-diag/changed-src/a1_uart_export.v`（`ae3c6eef…b1c8`）、
`r1-diag/changed-src/camera_a1_uart_top.v`（`8eb47a57…b171`）。
**仓库源文件未改动**（仍为 r4 冻结哈希 `3dad065f…` / `b1041676…`），
TD 工程把这两个文件重定向到包内副本（`01_build.tcl` 唯一的两处路径改动）。

状态包（35 B，每 187,500,000 个 `clk_a1` 周期 ≈ 1.000 s，仅在完全空闲时发）：

```
A5 5A | cap_frames u32 | raw_pub u32 | enc_frames u32 | exported u32 |
        raw_drop u32 | cmp_drop u32 | errors u32 | read_words u32 | XOR(byte0..33)
```

- 全部小端；8 个计数器在包开始时**一次性锁存**，包内自洽。
- 互斥：只有 `estate==E_IDLE && dq_cnt==0 && !desc_push && !tx_valid_r && tx_ready` 才启动；
  包在线上时 `E_IDLE` 不允许开新帧；帧进行中绝不会插包。
- 计数器来源与 `o_st_*` 完全相同的表达式（`errors = raw_st_err+cmp_st_err+exp_err`）。
- 旧 `0x55` 心跳在 `STS_DIV>0` 时禁用（`hb_en = HB_DIV>0 && STS_DIV==0`），
  冻结顶层里的 `HB_DIV=4194304` 因此失效——这是本轮**唯一**的线上格式变化。
- 未改：core、frame、CRC、帧头/字节序/长度、DDR 布局、SDC、引脚、`UART_DIV=1628`；
  无 false path / multicycle / 改 seed / 降频；ERAM 仍 101。

## 4. 局部仿真（下线前自证）

`sim/tb_status_pkt.v`（只例化 `a1_uart_export`，`UART_DIV=1`、`STS_DIV=2048`，
8 个计数器置 0x11111111…0x88888888），`vlog 0/0`：

```
TB_STATUS bytes=210 stop_err=0 busy=0
TB_STATUS_PACKETS 6
# Errors: 0, Warnings: 0
```

`parse_status.py` 解出 6 包、`bad_xor=0`，8 个字段按小端逐一复现常量
（`sim/status_bytes.txt` sha256 `ea1af0ec…d155`，`sim/status_parse.txt`）。
→ 包格式、字节序、XOR、空闲门控在 RTL 层已证。

## 5. 工程（重建 r0 候选，1 次综合 + 1 次布线）

| 项 | 值 |
|---|---|
| 综合 syn_1（第 1 次） | **SWNS +0.431 ns / STNS 0.000**，0 违例端点 |
| 资源（综合） | slice 16,874 / reg 16,307 / ERAM 71 |
| 布线 phy_1（第 1 次） | **WNS +0.173 ns / TNS 0.000 / 0 违例端点 / 20,288 端点** |
| fast corner | WNS 0.000 / TNS 0.000 / 0 |
| Hold | **WNS +0.020 ns / TNS 0** |
| Period Check WNS | +2.200 ns |
| 组合环 / 无时钟网络 | 0 / 0 |
| 资源（布线） | LUT6 18,902 / reg 25,427 / **ERAM 101**/300 / slice 23,109（32.24%） |
| 最差路径 | `clk_a1→clk_a1` 0.173 ns，终点 `u_a1/u_raw_store/st_dup_words_reg[16]_syn_2.cea`（统计计数器时钟使能，与本包改动无关） |
| r4 的 23 个 `htab_p3v→bm_b.addrb` 端点 | 本版 `routed_timing_summary.rpt` 中 **0 次出现** |

- 门槛：Routed 0 违例 ✔；WNS +0.173 ≥ +0.05 ✔；低于首选 +0.2 → **caveat**
  （+0.173，已写入 manifest）。
- 综合 +0.431 高于 r0 的 +0.222，最差路径也从 core 的 `len_r→cand_bits` 换成了
  `u_raw_store/st_dup_words` 的统计计数器 CE，说明新增状态机**不在**关键路径上；
  但**不据此宣称 r0 的 +0.222 已被修好**（r0 的 gate 门限与本轮不同口径，本包也不同 RTL）。
  （`syn_gate_timing.rpt` 内另有按域统计的 `Max : SWNS 0.575ns` 行；上表统一取 flow
  汇总值 0.431，与 `build_console_r1diag.log` 的 `P2_SYN_SWNS` 一致。）
- 证据：`td/syn_gate_timing.rpt`、`td/syn_gate_area.rpt`、`td/routed_timing_summary.rpt`、
  `td/routed_area.rpt`、`td/routed_check_timing.rpt`、`td/build_console_r1diag.log`。

## 6. bit / CWC（各 1 次，fail-closed 放行）

`02_bitgen.tcl`：`setup 0.173/0.000 hold 0.020/0.000 period 2.200`，
`candidate_abnormal.rpt` 0 端点 → 出 bit。

| 产物 | SHA256 | 字节 |
|---|---|---|
| `td/a1_board.bit` | `da858e62e8d6e8c3fca879a6152e0e565a14942cf87ab80266b05480885d3bd8` | 5,224,022 |
| `td/a1_board.cwc` | `cb7dae992a5e27bb5dcb656a89d6a64a8bab1ca3584b93605e12b834a978e595` | 110,168 |
| `td/a1_board_inst.bid` | `99f298cac51e177b8f55729428da8a2d13da662a82ebac74edddcff709567c81` | 95,905 |
| `td/cw/compiled.bit` | 同 `a1_board.bit`（逐字节相同） | 5,224,022 |
| `td/cw/compiled.cwc` | 同 `a1_board.cwc`（逐字节相同） | 110,168 |

## 7. 板级（**唯一 1 次 SRAM 下载已用，1/1**）

- 预检：`ping_cable.tcl` → `R1D_PING_DEVICE=PH1P100`。
- `download_sram_r1diag.tcl`：`R1D_DL_DEVICE=PH1P100`，
  `PRG-2014 : Chip validation success: PH1P100`，`R1D_DL_OK mode=jtag(sram)`，
  33.8 s。日志里有一行 `Error @ mpsse.cpp:90 : usb_open() failed`（hwserver 首次打开通道的
  探测），随后芯片校验成功、下载命令 Tcl 无错，**按 PRG-2014 判定为已下载**；不写 Flash。
- 采集：COM8 115200 8N1，60.3 s，`bytes=2135`，`magic_a1u1=0`，`byte_0x55=0`。
- 解析：**61 个状态包，`bad_xor=0`**；2135 = 61 × 35，无半包、无丢字节；
  包间隔 ≈ 1.01 s，与 `STS_DIV=187500000 @187.5 MHz` 一致（顺带证明 `clk_a1` 频点正确）。
- 证据：`board/download_r1diag.log`、`captures/com8_60s.bin|.dec|.stats`、
  `captures/status_60s.txt`。

## 8. 判定：卡在相机前端，不在 A1 链路

按 `board/README-r1diag-board.md` 的判定矩阵：

| 观测 | 本轮 | 含义 |
|---|---|---|
| 完全无字节 | 否 | TX/引脚/时钟正常 |
| 有包且 `cap_frames=0` | **是** | **相机 tap / crop / 进 A1 的 CDC 是阻塞点** |
| `cap>0, raw_pub=0` | 否 | — |
| `raw_pub>0, enc=0` | 否 | — |
| `enc>0, exported=0` | 否 | — |

- `cap_frames=0` 是"完整 ROI 帧计数"（`a1_raw_crop` 在最后一个 group 才 +1），
  因此"camera 在流但 tap/line/frame 语义不对"也会是 0；两种情形都落在**相机前端**，
  与 A+ core、raw store、压缩 store、exporter 无关。
- 由此：**本轮的 all-zero 结果不能证明 A+ core 在硅上正确，也不能证明它错误**；
  它只把"无压缩帧"的根因上移到了相机前端。core 的硅上行为仍未被触达。
- 支持该结论的旁证：状态包能持续发出 → `a1_rst_n` 已释放（`lock_a1 && ddr_rdy_sync`），
  即 PLL 与 DDR PHY 都 ready；若 `clk_cam` 无活动，crop 侧不会产生任何帧计数。

## 9. 边界与未测

- 未做 P1 三例逐字节回归：本轮 `STS_DIV>0` 只影响空闲期，帧路径逐字节未变；
  但**没有重跑** `tb_camera_a1_uart_top.v`（不在本任务门槛内，且预算优先给板级）。
  任何把本轮 RTL 提升为生产候选的后续轮必须补跑 P1 三例。
- `resync_decode.py`（r4 原文件）**不再适用**于本轮线上格式：它只跳过单字节 `0x55`，
  遇到 `A5 5A` 会当成帧头扫描失败。本轮改用 `parse_status.py`；
  若后续保留状态包，P3 的解码入口必须先剥离状态包。
- 相机前端（IMX415 配置、MIPI RX、f9p tap 的 `I_cam_mode=1`、`w_a_rst_out`）本轮未排查，
  也不在本包允许改动范围内。
- LED1 不可作为出帧判据。

## 10. 复测清单

- `required_dimensions`: integrated / functional / engineering / system
- `required_checks`:
  1. 哈希：`changed-src` 两文件 `ae3c6eef…` / `8eb47a57…`；仓库源未改
     （`3dad065f…` / `b1041676…`）；core `29b1e3e1…`；见 `artifact-hashes.txt`。
  2. 仿真：重跑 `sim/tb_status_pkt.v`，要求 6 包、`bad_xor=0`、字段等于常量。
  3. 工程：syn +0.431 / phy 0 违例 +0.173（caveat）/ hold +0.020 / ERAM 101 /
     0 组合环 / 0 无时钟；确认 `bm_b` 端点为 0。
  4. bit/CWC/BID 哈希与 `compiled.bit` 一致性（§6）。
  5. 系统：**已用掉 1/1 SRAM 下载**；重放判定只需
     `python parse_status.py --in captures/com8_60s.bin`，应得 61 包全 0。
     不得再下载第二次来"复现"。
- `input_status`: changed（两个包内 changed-src 文件 + 新增 TD 脚本/板级脚本），其余同 r0。
