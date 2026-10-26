# T10.b17-paxi-native — dev-plan（规划冻结，2026-10-26）

- run：`20261020-0209_singleA_aplus_closedloop`（项目根 `D:/fpga/ph1p100`）
- task_id：`T10.b17-paxi-native`
- 父任务：T10（**保持 blocked**；本包完成也不把 T10 置 done）
- 角色：开发 = fpga-dev；冻结后另派 **1 个新的综合测试者**（functional/engineering/system 是同一测试者的检查清单，不拆三个旧 tester）
- 状态：**ready**；`needs_user_input=false`；`BATCH_SIZE=1`；1 个主要可验收目标、1 个正式工作包、5 个语义步骤
- 本包主题：**回到原生 PAXI 边界适配**——地址单位、写 mask、单命令接纳三项合同修正 + 模型真实执行合同 + v6 失败 AR 证据；不动相机/几何/帧格式/时钟/SDC/DDR IP

## 0. 冻结输入、事实与裁定

### 0.1 b15 r0 板级事实（H4，唯一直接板级证据）

`T10.b15-ddr-pace/r0/board/captures/status_v5.txt`（151 个 v5 包，`bad_xor=0`，A 路 `sel=0/bit20=0`）：

| 观测 | 值 | 含义 |
|---|---:|---|
| `cap_frames` / `raw_pub` | +4,500 / +4,500 | A 相机、crop、发布均正常 |
| `crop_short` / `crop_geom_err` | 0 / 0 | 几何无错 |
| `timeout` / `retry` / `giveup` | +13,500 / +9,000 / +4,500 | 恰好 3 / 2 / 1 **每帧** |
| `enc_frames` / `exported` | 0 / 0 | 一帧都没编出来 |
| `ar − r = ar − rlast` | **13,740 = 尝试数** | 每次读尝试恰有 1 个 AR 永不被应答 |
| `stale_r` / `stale_guard` | 0 / 0 | 缺失的 R **从未**到达 PAXI R 通道 |

结论：b15 的“严格单笔 AR + rready 恒 1”没有解决板上缺 R；该失败已把问题从 bridge 的 AR 归属/FIFO 进一步压到 **PAXI 地址/写 mask/命令接纳合同**。

### 0.2 根因审计（`docs/OpenCode_b15根因审计与定位建议_2026-10-26.md`，SHA256 `CF18AACC…37A2BC`）

审计已证实、本包不得重新解释的三项源码差异：

1. **地址单位未适配**：store 的 256-bit 字下标 → arb → camera top → bridge 原样转发；b15 实际发 `0,1,2,3`，同份厂商参考发 `0,8,16,24`（`{word_index,3'b000}`）。链路中没有任何 `×8`。
2. **完整写 mask 相反**：b15 恒发 `32'hFFFF_FFFF`；厂商 `paxi_stg_cmd_gen`/`ph1p_ddrmc_mtest`/既有原生 `ddr_frame_store` 的完整写为 **0**（mask 0 = 写整字）。生成 wrapper 只做位重排，没有取反。
3. **读写命令同拍可握手**：b15 的写引擎/读引擎独立，可同拍提交 AW/W 与 AR；厂商参考用单 `cmd_type` 每拍只选读或写，并用 `awready & arready` 共同判定命令可发。现有模型没有覆盖这一点。

审计的五组小实验：宽松字下标+忽略 mask 读回 0 错；原生地址步长 1 错；mask=1 视为屏蔽 2 错；两者同时启用 2 错；**外部加地址×8、mask=0 的对照 0 错**。这证明接口/数据正确性风险，不证明真实 MC 的缺响应机制。

### 0.3 本包裁定（冻结）

- **先修接口合同，再谈 MC/IP。** 不得用 CRC、压缩核、重试次数、FIRST-R/RLAST 计数或“再下一次下载”绕过本包三项合同。
- **唯一 PAXI 边界**做地址转换；store/arb/camera top/shell 内部继续使用 256-bit 字单位，禁止多点乘 8。
- **写整字用 mask=0**；模型必须真实执行 mask，不得再“无论 wstrb 都写整字”。
- **单命令接纳默认开启**：AW/W 与 AR 互斥；保留参数 `ALLOW_CONCURRENT=0/1`，1 仅用于后续受控对照，不得作为本包板级候选。
- **v6 状态包**只扩诊断字段，不改帧格式；新增失败 AR 地址/低 3 位/同拍握手/在途状态，使“仍缺 R”时能留下可定位证据。

### 0.4 基线源集（逐字节，复制自 b15 r0）

| 文件 | b15 r0 SHA256（完整） | 本包 |
|---|---|---|
| `p2_ddr_bridge.v` | `EB9DF41F9404E40CD31DBF12BC65F29ED965A9FC6C2E604F027AA9AD158954E3` | **功能修改**：地址×8、mask=0、单命令仲裁、v6 诊断；保留 b15 读严格性 |
| `camera_a1_uart_top.v` | `ACC1EFF329AA295D01B16123581FEE48EF49D444EFDCE3B7FE62214555517405` | **诊断修改**：`i_dbg_bridge` 256→512、`sts_ext` 512→768 |
| `p2_a1_board_top.v` | `48881D574352FD2C61F7587D3687F215BB11EA18D5B5D0B4772820A938DE561B` | **诊断修改**：`dbg_bridge` 256→512 |
| `a1_uart_export.v` | `F8F9E4E354B5BDBCCE56321CACB22981F1283565EC6C40479A90D0625CE76B61` | **诊断修改**：v6 273 B/67 字段 |
| `f9p_camera_display_core.v` | `C9DE0D9C176E830DF35833EFF7E91B811D954FB5480BC13E1FB122EF23305089` | 逐字节不变 |
| `a1_ddr_slot_store.v` | `6C619CF90E54385D667F1EC0F63CC87EE58AADD3C42143330AC4945EB47DEFE9` | 逐字节不变 |
| `a1_ddr_arb2.v` | `B84019BDA057AFE82FF558E0848D6171FA12732BD8CDB7C6239CB71B3F81D6BA` | 逐字节不变 |
| `a1_frame_top.v` | `0064607ACEB20AE3EF14133F0AAF5F8B3F489943011A66A1DDC005350DBA7109` | 逐字节不变 |
| `a1_deflate_core.v` | `A91C2ED82FBEF654C4E065B64AE1CC268CA232FEAA26FDD313C58D8740F81B3E` | 逐字节不变 |
| `a1_raw_crop.v` | `33A6FEE77FD1AA67A31CACF26DD5530E5E2EA474EE655CBD5F1D98D887C5D72D` | 逐字节不变 |
| `cam_diag_mailbox.v` | `352AF7C85094EA99B575E99DA952AF8D33871352140E4C6EFDDFF9E6C2407278` | 逐字节不变（实例 W 参数由 256 改 512） |

- 基线目录：`T10.b15-ddr-pace/r0/changed-src/**`；b15 的读严格性（`ar_busy` 到 `rlast`、`rready=1`、`rf_path_empty`、超时/重试/purge）**保留**。
- 构建模板：`T10.b15-ddr-pace/r0/td/**`；仿真模板：`T10.b15-ddr-pace/r0/sim/**`；板级模板：`T10.b15-ddr-pace/r0/board/**`。只读复制，不改 b15 原件。
- 路径合同：`P:`/`Y:` = 项目根，`W:` = `r0/sim`，`T:` = `r0/td`，`X:` 不映射项目根。TD 前先运行 `tools/td/open_td.ps1` 或 `tools/td/td_env.ps1`。
- 临时 ModelSim work 库/INI/日志只写独占目录 `%TEMP%\opencode\T10.b17-paxi-native\`；不写项目根或其他 run。

### 0.5 不可改动（冻结）

- 44 B 帧头、四 CRC、压缩字节、crop 几何/ROI（`CAM_W=3864, CAM_H=2192, ROI_X=972, ROI_Y=556, W=1920, H=1080`）、RAW 2,592,000 B、四槽 DDR 布局、`UART_DIV=1628`、`HB_DIV`、引脚、时钟频率（187.5 MHz / 111.375 MHz）。
- `p2_board.sdc`、`a1_small_top.sdc`、`board_p2.adc`、vendor/`upstream/**`、DDR IP/PAXI 协议、A+ 核、crop、帧格式、UART 帧格式、旧 run/证据/manifest、`workflow/tasks.json`。
- 不写 Flash、不 PCIe/RK、不做双路/G4、不新增时钟域、不 false path/multicycle/改 seed/降频/新增 ERAM 实例。
- 禁止批量删除；一次只能删一个明确路径文件，需批量先问用户。

## 1. 本轮唯一目标与工作包

**目标**：交付一个最小候选，使 PAXI 边界满足原生合同（地址×8、mask=0、单命令接纳），模型能真实拒绝错误合同，v6 能在板级仍失败时留下失败 AR 证据；并完成 1 次重建与 1 次板级 150 s 验证。

| task_id | 问题/产物 | 实际工作树/允许写路径 | 依赖 | functional | engineering | system | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| `T10.b17-paxi-native` | 原生 PAXI 边界适配 + 模型真合同 + v6 诊断 + 重建/板级 | `D:/fpga/ph1p100`；只写 `workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b17-paxi-native/**` | b15 r0 源集/板级证据；审计文档 | 16 字写-停-读回；整帧/两帧/丢 R；P1 三黄金；v6 结构；模型负对照 | Routed 0 违例、WNS≥+0.05（薄余量按 b13 口径）、ERAM+CWC≤300、1 bitgen+1 CWC | 先下载后 COM8 150 s；timeout/retry/giveup 归零、enc/exported 增量>0、≥1 帧四 CRC+zlib；失败保留 v6 AR 证据 | G0/G1 仿真；G2 构建；G3 板级；G4 not_run | **ready** | 派 fpga-dev 执行 |

## 2. 五个语义步骤

| # | 语义步骤 | 预算 | 产物/门槛 |
|---|---|---|---|
| W1 | 冻结基线 + 原生合同取证 | ≤20 min | 复制 11 文件到 `r0/changed-src/`，逐个 SHA256；确认地址单位、mask、命令接纳的源码/端口证据写入 `r0/diag/paxi-native-contract.md`；记录 b15 `L_max=1`、RF 16 深、`TIMEOUT=8192` 等既有事实 |
| W2 | RTL：唯一边界转换 + mask + 单命令 + v6 诊断 | ≤45 min | `p2_ddr_bridge.v`、`camera_a1_uart_top.v`、`p2_a1_board_top.v`、`a1_uart_export.v` 四处按 §3/§4 实现；其余 7 文件逐字节不变；写 `r0/rtl-diff-r0.patch` 与 `r0/diag/v6-fields.md` |
| W3 | 模型与仿真矩阵 | ≤45 min | 新 `p2_paxi_model_b17.v`（地址低3位/越界/mask/单命令/写提交检查）+ `tb_b17_paxi_native.sv`（16 字）+ `tb_b17_chain.sv`；P1 三黄金、整帧、两帧、丢 R、v6 全过；负对照（b15 旧桥）必须失败 |
| W4 | 重建 | TD 内 | 复制 b15 `r0/td/**`；综合≤3、布线≤2、1 bitgen+1 CWC；Routed 0 违例、WNS 按 §6、ERAM+CWC≤300；SDC diff 为空 |
| W5 | 板级 + 冻结 | ≤25 min | FTDI 预检；在位 → 1 次 SRAM 下载成功后再开 COM8 150 s；v6 解析；§7 门槛；失败按 §7.5 留证停止；manifest/result/lessons |

## 3. RTL 规格（冻结语义，允许等价实现）

只允许改四个文件；其他 RTL、SDC、ADC、帧格式、UART 导出帧一律不动。

### 3.1 唯一 PAXI 地址转换（AW/AR 都做）

内部槽地址仍为 **256-bit 字单位**；只在 bridge 的 PAXI 输出做一次转换：

```verilog
// word index is the existing 27-bit bridge address
assign paxi_awaddr = {wf_rdata[279:256], 3'b000};  // wf_rdata[282:256] is the word index
assign paxi_araddr = {af_rdata[23:0],   3'b000};  // af_rdata is the word index
```

- 合法字下标范围：`0 .. 424313`（24 bit 内；当前最大 424313，不得截断）。定义 `localparam [23:0] PAXI_MAX_WORD = 24'd424313`。
- 范围检查：
  - 组合检查 `aw_idx_oob = (wf_rdata[282:256] > PAXI_MAX_WORD)`、`ar_idx_oob = (af_rdata > PAXI_MAX_WORD)`；
  - 置 sticky `oob_addr_seen`（v6 `diag_flags[3]`），不改变正常数据流；**只在 `rst_n && wf_rvalid/af_rvalid` 时评估**，避免 FIFO 空/复位垃圾误置位；
  - 仿真中若越界地址被发出，`$fatal`（`ifndef SYNTHESIS` 或等价）；综合路径不新增死锁分支。
- 低 3 位：转换后 `paxi_awaddr[2:0]==0`、`paxi_araddr[2:0]==0`；置 `low3_nonzero_seen`（`diag_flags[4]`）若观察到非零。
- 禁止在 store/arb/camera top/shell 里再做 `×8`；禁止把内部槽地址改成字节地址。

### 3.2 写 mask

```verilog
assign paxi_wstrb = 32'h0000_0000;  // native contract: mask 0 writes every byte
```

- 不得再发 `32'hFFFF_FFFF`；不得在 wrapper 之外自行取反。
- v6 `diag_flags[5]` = `wstrb_nonzero_seen`，正常板级必须为 0。
- 模型必须按“bit=0 使能该字节、bit=1 保持原值”执行；`32'h0` = 全字写，`32'hFFFF_FFFF` = 不写任何字节。该语义是本包的核心负对照，不允许模型忽略 mask。

### 3.3 单命令接纳（默认受控诊断）

新增模块参数：

```verilog
parameter integer ALLOW_CONCURRENT = 0;  // 0 = native single-command diagnostic default
```

默认 `ALLOW_CONCURRENT=0` 时：

- 定义 `wr_start_req = wf_rvalid && !wf_pop && ddr_rdy && !ar_busy`；`rd_req = af_rvalid && !ar_busy && rf_path_empty && ddr_rdy && !rd_hold && (wstate == W_IDLE)`。
- **组合仲裁（写优先）**：`paxi_arvalid = rd_req && (ALLOW_CONCURRENT || !wr_start_req)`；`W_IDLE → W_RUN` 仍按 `wr_start_req` 发生。这样在“写启动”和“AR 请求”同一拍时，只发写、AR 保持 valid 等下一拍，不会出现同拍 AW/AR。
- 写引擎从 `W_IDLE → W_RUN` 仅在 `wr_start_req` 时发生；
- `paxi_awvalid/paxi_wvalid` 在 `ar_busy` 时不得为 1；`paxi_arvalid` 在 `wstate != W_IDLE` 时不得为 1；
- 同一拍不得同时出现 `aw_hs` 与 `ar_hs`，也不得同时出现 `w_hs` 与 `ar_hs`；
- AW/W 作为**一个写命令**可以同拍握手（保持 b15 的单拍写），但不得与 AR 同拍。
- `ALLOW_CONCURRENT=1` 仅用于后续对照；**本包 bitgen/板级固定为 0**，不得用 1 的结果冒充原生合同。

保留 b15 读规则：`ar_busy` 在 AR 握手置位、只在 `rvalid && rready && rlast` 清零（purge/guard 强清保留）；`paxi_rready=1`；`rf_path_empty` 前置；`TIMEOUT=8192`、`RETRY_MAX=2`、`A1_GUARD_N=70000`、`BRIDGE_GUARD_N=65536`、`DDR_PURGE_N=4`、`A1_PURGE_N=4`、`rd_abort` toggle 同步、`s_arready` 门控逐语义保留。

### 3.4 v6 诊断信号（bridge 内）

在 `clk_ddr` 侧新增/锁存，经既有 `cam_diag_mailbox` 快照到 `clk_a1`；不改变数据流：

| 信号 | 语义 |
|---|---|
| `last_issued_ar_addr[26:0]` | 最近一次 AR 握手时 PAXI 上的**原生地址**（已 ×8） |
| `last_issued_ar_low3[2:0]` | `last_issued_ar_addr[2:0]`，正常恒 0 |
| `timeout_ar_addr[26:0]` | `purge_evt`（b13 `rd_abort` 同步后）时若 `ar_busy=1`，锁存 `last_issued_ar_addr` |
| `timeout_ar_low3[2:0]` | 上述地址低 3 位 |
| `timeout_ar_valid` | 上述锁存有效；成功 `rlast` 或复位清除 |
| `same_aw_ar_cnt[31:0]` | `paxi_awvalid&&paxi_awready&&paxi_arvalid&&paxi_arready` 计数 |
| `same_w_ar_cnt[31:0]` | `paxi_wvalid&&paxi_wready&&paxi_arvalid&&paxi_arready` 计数 |
| `inflight_state[31:0]` | `[0] ar_busy [1] aw_seen [2] w_seen [3] wstate [4] ddr_rdy [5] rd_hold [6] rf_path_empty [7] paxi_arvalid`，其余 0 |
| `diag_flags[31:0]` | `[0] timeout_ar_valid [1] same_aw_ar_seen(sticky) [2] same_w_ar_seen(sticky) [3] oob_addr_seen(sticky) [4] low3_nonzero_seen(sticky) [5] wstrb_nonzero_seen(sticky)`，其余 0 |

- `dbg_a1` 从 256 bit 扩到 **512 bit**；旧 256 bit 布局（`br0/ar_cnt/ar_block_cnt/r_cnt/rlast_cnt/stale_r_cnt/stale_guard_cnt`）保持在 `[255:0]` 不变。
- 新 8 字段放在 `[511:256]`，从高到低：`diag_flags`、`inflight_state`、`same_w_ar_cnt`、`same_aw_ar_cnt`、`timeout_ar_low3`、`timeout_ar_addr`、`last_issued_ar_low3`、`last_issued_ar_addr`。
- `cam_diag_mailbox` 实例 `W` 由 256 改 512；模块本体不变。

## 4. v6 状态包（冻结）

### 4.1 格式

| 项 | 值 |
|---|---|
| 总长 | **273 B** = 4 B magic + 67×u32（268 B）+ XOR8（1 B） |
| 头部 | `A5 5A 11 06`（`LEN=273` 的低字节 `0x11`，`VER=6`） |
| 字段数 | **67**（v5 的 #1..#59 名称/顺序不变；追加 #60..#67） |
| 校验 | 对偏移 0..271 做 XOR8 |
| 快照 | 单边沿、整包一致；不得在帧传输途中插入 |
| 兼容 | 新 parser 同时接受 v5（241 B/59/VER=5）与 v6（273 B/67/VER=6）；旧 v5 采集仍可解析 |

### 4.2 追加字段

| # | 名称 | 来源 |
|---:|---|---|
| 60 | `last_issued_ar_addr` | bridge 原生 AR 地址（27 bit 零扩展） |
| 61 | `last_issued_ar_low3` | 低 3 位 |
| 62 | `timeout_ar_addr` | `rd_abort` 时锁存的 AR 地址 |
| 63 | `timeout_ar_low3` | 低 3 位 |
| 64 | `same_aw_ar_cnt` | AW 与 AR 同拍握手计数 |
| 65 | `same_w_ar_cnt` | W 与 AR 同拍握手计数 |
| 66 | `inflight_state` | 在途状态位图（§3.4） |
| 67 | `diag_flags` | 诊断 sticky 位图（§3.4） |

### 4.3 实现点

- `a1_uart_export.v`：`STS_LEN=9'd273`、`STS_LAST=9'd272`、`STS_VER=6`；`sidx/sbyte_i` 由 8 bit 扩到 9 bit；`extsnap` 512→768；`allsnap` 1888→2144 bit。
- `camera_a1_uart_top.v`：`i_dbg_bridge` 256→512；`sts_ext_bus` 512→768，按 §3.4 顺序拼接；v5 #44..#59 的位序不变。
- `p2_a1_board_top.v`：`dbg_bridge` 256→512；其余连线/参数不变。
- `p2_ddr_bridge.v`：`dbg_a1` 512；`dbg_ddr`/`dbg_mid` 512；mailbox W=512；旧 `[255:0]` 布局不变。
- 状态包不得改变帧头、四 CRC、压缩字节、crop 几何、四槽、UART 帧格式。

## 5. 仿真：模型真合同 + 测试矩阵

### 5.1 新模型 `p2_paxi_model_b17.v`（从 b15 模型复制修改）

必须真实执行以下语义，不得再用“数组字下标 + 忽略 mask”：

1. **地址解码**：`word = addr[26:3]`；`addr[2:0] != 0` → `n_bad_low3++`；`word > 424313` → `n_oob++`；坏地址不得别名写入/读出，写拍要消费并计数，读拍返回 poison 且仍回 `rlast=1`（不挂死）。
2. **mask**：`wstrb[i]==0` 使能第 i 字节，`wstrb[i]==1` 保持旧值；`32'h0` = 全字写；`32'hFFFF_FFFF` = 不写。`n_mask_nonzero` 统计非零 mask。
3. **AW/W 分离**：AW 与 W 可不同拍；分别锁存地址/mask 与数据，二者齐备后提交一次写；`n_write_commit` 统计提交；`n_aw_hs==n_whs==n_write_commit` 在 clean run 成立。
4. **单命令接纳**：模型中 `awready`/`arready` 不得同拍为 1（写优先，AR 等下一拍）；`n_same_hs` 统计同拍握手（必须 0）；`n_same_req` 统计 DUT 同拍请求 AW+AR（用于负对照，clean run 必须 0）。
5. **保留 b13/b15 注入能力**：`DROP_ADDR/DROP_OCC/DROP_FIRST_N/LATE_*` 的参数单位改为**原生地址**；测试中的丢 R 地址必须是 `8*word` 且低 3 位为 0。
6. 输出新增计数：`n_bad_low3`、`n_oob`、`n_mask_nonzero`、`n_same_req`、`n_same_hs`、`n_write_commit`；现有 `n_ar_hs/n_aw_hs/n_whs/n_r_hs` 保留。

### 5.2 16 字小图样（先做，单独证明边界）

`tb_b17_paxi_native.sv`：只实例化 `p2_ddr_bridge` + 新模型 + 两个时钟，不接相机/压缩核。

- 写 16 个**不同**的 256-bit 图样到内部字下标 `0..15`；等待每次 `s_awready/s_wready`；
- 停写 ≥32 个 `clk_ddr` 周期；
- 逐字读回 `0..15`，逐字比较；
- 断言：
  - 模型看到的 AW/AR 地址严格为 `0,8,16,…,120`；
  - 每次 `paxi_wstrb==0`；`n_mask_nonzero=0`；
  - `n_bad_low3=n_oob=n_same_req=n_same_hs=0`；
  - `n_write_commit=16`、`n_ar_hs=16`、`n_r_hs=16`；
  - 读回 16/16 字节完全一致；`last_issued_ar_addr=120`、low3=0。

该用例是“地址单位 + mask + 单命令”三合同的第一道闸；**不过不得进入整帧**。

### 5.3 整帧/两帧/丢 R（复用 b15 chain TB）

从 `T10.b15-ddr-pace/r0/sim/tb_b15_chain.sv` 派生 `tb_b17_chain.sv`，只替换模型/端口/参数与 v6 检查：

| ID | 用例 | 通过判据 |
|---|---|---|
| S1 | 正常整帧（3864×2192 → ROI 972/556 → 1920×1080） | `pix_beats=2,117,472`、`line_rises=2,192`、`frame_rises=1`、`crop_roi_frames=1`、`crop_groups=518,400`、`raw_len=2,592,000`、`enc=1`、`exported=1`、四 CRC+严格 zlib、无半帧、`timeout=retry=giveup=0`、`ar=r=rlast=210,685`、`n_bad_low3=n_oob=n_mask_nonzero=n_same_req=n_same_hs=0` |
| S2 | full 两帧 | `enc=2`、`exported=2`、两帧四 CRC+zlib、`ar=r=rlast=421,370`、`raw_drop=cmp_drop=0`、无半帧、模型计数全 0 |
| S3 | 丢 1 个 R（burst 中部，原生地址注入） | 第一次尝试 `timeout=1`→`retry=1`→第二次整帧成功；`giveup=0`；四 CRC+zlib；晚到 R 只计 stale、不入队；`dup=0`；丢 R 的 AR 地址低 3 位=0 |
| P1 | 三黄金 `micro8x2` / `mid64x8` / `full_grad` | 压缩字节 SHA256 与 b15 `r0/sim/caps/*.dec` **逐字节一致**（`micro8x2` `FA513A2B…EDEF`、`mid64x8` `EE61E620…9789`、`full_grad` `B992A8AD…ADA9`）；四 CRC、`zlib_ok`、`dup=0`、无半帧、`vlog 0/0` |
| S4 | v6 结构 | `packets>=3`、`bad_xor=0`、`len=273`、`ver=6`、`fields=67`；`last_issued_ar_addr` 非零且低3位=0；clean run `timeout_ar_valid=0`、`same_aw_ar_cnt=same_w_ar_cnt=0`；`inflight_state` 静止时 `ar_busy=aw_seen=w_seen=0`；v5 241 B fixture 仍可解析；坏 XOR 被拒 |

### 5.4 负对照（必须让旧合同失败）

1. **b15 旧 bridge 对 b17 模型**：内部字下标直接发 0,1,2 + `wstrb=32'hFFFF_FFFF` → 模型必须报 `n_bad_low3/n_mask_nonzero`、读回不一致；证明测试能抓住真实缺陷。
2. **全 1 mask**：仅改模型输入/写拍为 `32'hFFFF_FFFF`，内存必须保持初值，`n_mask_nonzero>0`；不得写成“全 1 也写整字”。
3. **非零低 3 位地址**：模型报 `n_bad_low3>0`，不得别名到相邻字。
4. **越界字下标**（>424313）：模型报 `n_oob>0`，读回 poison，不挂死。
5. **`ALLOW_CONCURRENT=1` 的 bridge**：模型 `n_same_req/n_same_hs>0`，证明单命令检查有效；该配置不进入 bitgen/板级。

### 5.5 工具与预算

- ModelSim ASE 10.5b（`D:\intelFPGA\18.1\modelsim_ase\win32aloem`）、Python 3.11；无网络；无 TD/硬件（W4 除外）。
- 开发 ≤150 min / ≤70 calls；全尺寸 `vsim` ≤4 次（S1/S2/S3 + 至多 1 次有据重试），单次硬超时 2700 s；16 字小图样/P1/v6 合计 ≤6 次短仿真（单次 ≤900 s）；`vlog` 1200 s；Python 120 s；读/搜 60 s。
- 同一失败命令最多首次 +1 次有新证据的纠正重试；单问题 ≤3 轮搜索/读取；连续 2 次无进展主动停止。
- 禁止 shell 循环绕调用/重试/仿真次数；禁止批量删除；失败日志保留。

## 6. 重建与时序裁决

- 复制 `T10.b15-ddr-pace/r0/td/**` 到 `r0/td/`；`01_build.tcl`/`a1_board.al` 只把 `changed-src` 路径改指 b17 本地副本（流程/参数/seed 不变）；其余 Tcl/ADC/SDC 不变。
- 综合 ≤3 次、布线 ≤2 次、**bitgen 1 次、CWC 1 次**；同参数不 sweep；TD 会话 ≤3。
- 硬门槛：Routed **0 违例端点**、hold ≥0、period 正、**ERAM+CWC ≤300**。
- **WNS 目标 ≥ +0.05 ns**；按 b13 口径：
  - Routed `0 违例` 且 WNS ∈ **+0.003 … +0.05**：接受为诊断候选，`timing_caveat=thin_margin_+0.00x`，result/manifest 明示“非生产签核”；
  - WNS **< +0.003 或任何负 slack/违例**：若最差路径落在新增 v6 诊断/mailbox，允许 1 次“只做寄存器化/等价流水、保留全部 v6 字段”的修正；仍不达标即停，不 bitgen、不下载；
  - **不得**放宽 SDC、改 seed、降频、删 v6 必需字段。
- bit/CWC/BID 与 `cw/compiled.*` 哈希自洽并冻结；1 bitgen+1 CWC 后不再重建。

## 7. 板级（先下载后开 COM8）

### 7.1 前置

1. FTDI 预检（不打开 COM8）：`Get-PnpDevice -PresentOnly` 查 `VID_0403&PID_6042`；记录 `FTDI_PRESENT=0/1` 与原始输出。
2. 不在位 → `board=blocked`、**0 下载、0 COM8、不重试**；`board_blocked_reason=FTDI_0403:6042_absent`。这是合法完成，不是 FAIL，也不问用户。
3. 相机 A 已在位（b15 已证），本轮 `needs_user_input=false`。

### 7.2 采集

1. **先下载**：1 次 SRAM（JTAG，同一冻结 bit），确认 `B17_DL_OK`，结束 hwserver/释放 FTDI。
2. **再开 COM8**，150 s；用 `parse_status_v6.py` 同时解析 v5/v6；用 `check_b17_board.py` 判 gate。

### 7.3 板级门槛（全部满足）

- `status_packets ≥120`、`bad_xor=0`、`resync_bytes=0`；`len=273`、`ver=6`、`fields=67`；`sel=0`、`sysstat bit20=0`。
- `cap_frames` 增量 >0、`raw_pub` 增量 >0；`crop_short=0`、`crop_geom_err=0`。
- **`timeout` / `retry` / `giveup` 增量全部 = 0**（首包到末包差分；下载后计数应从 0 起）。
- **`enc_frames` 增量 >0 且 `exported` 增量 >0**。
- **≥1 帧**：44 B 头 + header/stream/xform/raw **四 CRC** 全过 + **zlib 解压成功** + 长度一致；无半帧。
- `stale_guard` 增量 = 0；静止 `ar − rlast ≤ 1`；`ar − r ≤ 1`。
- v6 诊断：所有 `last_issued_ar_addr[2:0]==0`、`last_issued_ar_low3==0`；`same_aw_ar_cnt=same_w_ar_cnt=0`；`diag_flags` 的 bit1..bit5 全 0（bit0 仅在失败时允许，见 §7.5）；`wstrb_nonzero_seen=0`。

### 7.4 通过判定

`exported>0` 且四 CRC+zlib 且以上门槛全过 → **板级通过**；result 明确记录 v6 地址序列（首/末/失败）、`n_bad` 计数、时序 caveat、是否 thin margin。

### 7.5 失败分支（必须写进 result）

- `timeout/retry/giveup` 仍每帧 3/2/1 且 `exported=0` → **仍每帧丢 R**：立即停止；保留：
  - `last_issued_ar_addr` 首/末值、`last_issued_ar_low3`；
  - `timeout_ar_addr`/`timeout_ar_low3`/`timeout_ar_valid`；
  - `same_aw_ar_cnt`/`same_w_ar_cnt`/`inflight_state`/`diag_flags`；
  - `ar/r/rlast/stale_guard/stale_r` 首末差分、失败帧号/尝试号。
- 判 `PAXI_NATIVE_STILL_UNRESOLVED`；**不第二次下载、不第二个 bitstream、不改板级脚本重试**；交规划决定是否进入 MC/IP 调查。
- `timeout=0` 但 `enc=0` → 读已通、卡在 A+/导出，按 A+ 侧证据交规划（本包不修 A+）。
- `arready` 长期压低 / `ddr_rdy=0` → 记录 DDR 侧就绪条件，交规划。
- 不写 Flash、不 PCIe/RK；下载 ≤1 次；失败不第二次。

## 8. 交付物（缺一不可）

```text
T10.b17-paxi-native/
  input-index.md, fpga-design-guide.md, dev-plan.md, dispatch.json,
  handoff.md, final-summary.md, user-summary.md
  r0/
    changed-src/**              # 11 文件：4 功能/诊断修改 + 7 逐字节不变
    rtl-diff-r0.patch
    diag/paxi-native-contract.md
    diag/v6-fields.md
    sim/p2_paxi_model_b17.v, tb_b17_paxi_native.sv, tb_b17_chain.sv,
        run_b17.py, logs/**, cases/**, sim-results-b17-*.json
    td/**                       # 综合/布线/1 bitgen/1 CWC/bit/CWC/BID/compiled/STA
    board/**                    # FTDI 预检、dl_b17.tcl、run_board_b17.ps1、
                                # capture_com8.py、parse_status_v6.py、check_b17_board.py、
                                # captures/**（bin/dec/stats/status_v6.txt/board_gate.*）
    result-r0.md, lessons-r0.md, artifact-hashes.txt
  CANDIDATE-MANIFEST-b17-paxi-native-r0.json
```

- `result-r0.md` 必须逐项列：三合同是否落地、16 字结果、S1–S4、P1 三黄金、负对照、构建 STA/资源、板级 gate、v6 地址证据、未测/边界、回退。
- `lessons-r0.md` 记录：b15 模型为何漏检、地址/mask/并发各自的证据、若仍失败下一步。
- 板级 blocked 时 result 明确 `board=blocked`、原因、0 下载，不宣称板级通过。

## 9. 验收门槛（综合测试者按同一 manifest 覆盖三维）

| 维度 | 检查 | 门槛/证据 |
|---|---|---|
| functional | 16 字小图样 | 地址严格 0,8,…,120；16/16 数据逐字一致；mask=0；n_bad_low3=n_oob=n_mask_nonzero=n_same_req=n_same_hs=0；last_issued_ar_addr=120、low3=0 |
| functional | 整帧/两帧 | S1/S2 计数逐值、`ar=r=rlast=210,685/421,370`、四 CRC+zlib、无半帧、无 drop/dup/geom/wd |
| functional | 丢 R 恢复 | S3 `timeout=1 retry=1 giveup=0 exported=1`、四 CRC、晚到 R 只计 stale、dup=0 |
| functional | P1 三黄金 | 压缩字节 SHA256 与 b15 caps 逐字节一致；四 CRC/zlib/dup=0/vlog 0/0 |
| functional | v6 | 273 B/67/VER=6/LEN=0x11/XOR 0..271；v5 fixture 兼容；坏 XOR 拒绝；字段语义与 §4 一致 |
| functional | 模型负对照 | b15 旧桥必须失败；全 1 mask 不写；低3位/越界/并发均被计数且不挂死 |
| engineering | 副本/边界 | 7 文件逐字节不变；4 文件 diff 只在 §3/§4 允许面；SDC/ADC diff=0；无新增时钟域/ERAM/PAXI 端口 |
| engineering | 可复现/隔离 | 命令 argv/cwd/exit/耗时/timeout 全记录；work 库/INI/日志独占；写范围外 0 文件；`active_commands=0` |
| engineering | 构建 | 综合≤3/布线≤2/1 bitgen+1 CWC；Routed 0 违例、hold≥0、period 正、ERAM+CWC≤300；WNS 按 §6；bit/CWC/BID/compiled 自洽 |
| engineering | manifest | 覆盖 src/sim/td/board/输入/工具/命令；`stopped_modifying=true`；与 bit/CWC 哈希绑定 |
| system | 板级接口 | 先下载后 COM8 150 s；≥120 v6 包、bad_xor=0；timeout/retry/giveup 增量 0；enc/exported>0；≥1 帧四 CRC+zlib；v6 地址低3位=0、同拍计数=0 |
| system | 声明边界 | 只声明 A 路/单帧/150 s/该 bit；不声明 DDR sustained、双路、PCIe/RK、Flash、生产签核；thin margin 单列 |
| G 层 | G0/G1/G2/G3 | 输入/副本 SHA 0 mismatch；仿真可复算；同一候选综合/布线/bit/CWC；板级真实采集；G4 not_run（无 Flash/长期稳定性） |

**不适用理由**：G4 不适用（本包不写 Flash、不做长期/多板稳定性）；G2/G3 只对同一冻结候选，若 W4/W5 未执行则标 `not_run`，不得用旧 b15 结果代填。

## 10. 预算、停止与回退

- 开发：**150 min / 70 calls**；TD 会话 ≤3、综合≤3、布线≤2、bitgen 1、CWC 1、下载 1、Flash 0。
- 综合测试：45 min / 30 calls（独立复跑至少 16 字小图样 + v6 结构；可加 1 次短 chain 控制）。
- 立即停止（不建/不下载）：
  - 需改 §0.4 四个文件以外任何功能 RTL，或需改 SDC/引脚/时钟/DDR IP/PAXI 协议/帧格式/UART 帧格式；
  - 16 字小图样失败且 1 次有新证据的修正后仍失败；
  - P1 任一黄金非逐字节一致，或帧头/CRC/压缩字节变化；
  - v6 破坏 273 B/67 字段/顺序/帧内边界；
  - S1/S2/S3 无法通过，或模型负对照不能复现 b15 失败；
  - 综合 3 次仍负；布线 2 次仍 <+0.003 或任何违例；ERAM+CWC>300；
  - 需要第二个 bitstream；
  - 板级仍每帧丢 R（按 §7.5 留证停止）。
- 回退：只回退 `T10.b17-paxi-native/**`；b15/b13/生产/旧 manifest 不动；`p2_ddr_bridge.v` 回到 b15 版本即回到“地址未适配”状态（不作为候选）。

## 11. 风险与控制

| 风险 | 影响 | 控制 |
|---|---|---|
| mask 语义理解反了（0=写整字 vs 1=写） | 修成“全 0 反而不写”，板级更差 | 以厂商 mtest/`ddr_frame_store` 原文为准；模型先做“全 1 mask 必须不写”的负对照；clean run `n_mask_nonzero=0` |
| 地址×8 与模型/注入地址单位混淆 | 丢 R 注入落错地址，误判 | 注入参数统一为原生地址；16 字测试先锁 0,8,…；丢 R 地址断言低3位=0 |
| 单命令仲裁降低吞吐 | 一帧导出更慢，150 s 内帧数少 | 本包只要求 ≥1 帧；记录吞吐；`ALLOW_CONCURRENT=1` 仅作后续对照，不混入本包 |
| v6 扩包影响时序/资源 | WNS 变差或 ERAM+CWC 超限 | 只扩寄存器/mailbox；WNS 按 §6；允许 1 次等价流水修正，不删字段；ERAM+CWC≤300 |
| 仍缺 R 但无证据 | 又回到“猜 MC” | v6 锁存 `last_issued_ar_addr`/`timeout_ar_addr`/low3/同拍/在途；失败即留证停止 |
| 板级/FTDI 不在位 | 无法完成 system 维 | `board=blocked` 合法；离线+构建仍有效；不下载、不问用户、不重试 |

## 12. 后续主题（本轮不做，最多 3 条）

1. 若 `PAXI_NATIVE_STILL_UNRESOLVED`：用 v6 失败 AR 地址/低3位/同拍证据进入 DDR MC/IP 读响应侧调查（需另开 run 与授权）。
2. 原生合同确认后，用 `ALLOW_CONCURRENT=1` 做单命令 vs 并发的吞吐对照；不得在合同未证前把并发当默认。
3. A/B 双路、全帧自然内容、DDR sustained/PCIe/RK/Flash 与长期稳定性；均需新 run。

## 13. 下一次准确启动/恢复文本（开发）

> 恢复 `20261020-0209_singleA_aplus_closedloop` 的 **`T10.b17-paxi-native` r0**（ready；1 bitgen+1 CWC；SRAM 下载 ≤1）。
> 先读 `T10.b17-paxi-native/{dev-plan.md,fpga-design-guide.md,handoff.md,dispatch.json}`、审计文档 `docs/OpenCode_b15根因审计与定位建议_2026-10-26.md`、b15 `T10.b15-ddr-pace/r0/changed-src/**`、b15 `r0/td/**`、b15 `r0/sim/**`、b15 `r0/board/**`。
> 目标：只在 bridge 的唯一 PAXI 边界做 `{word_index[23:0],3'b000}`（AW/AR），`paxi_wstrb=0`，AW/W 与 AR 单命令互斥（`ALLOW_CONCURRENT=0`），保留 b15 严格单笔读/超时/重试；v6 273 B/67 字段加失败 AR 证据；模型真实执行低3位/越界/mask/单命令；先 16 字写-停-读回，再整帧/两帧/丢 R/P1 三黄金；重建 Routed 0 违例、WNS 按 §6、1 bitgen+1 CWC；先下载后 COM8 150 s，timeout/retry/giveup 归零、enc/exported 增量>0、≥1 帧四 CRC+zlib；仍缺 R 则留 v6 证据停止，不第二次下载。
> 150 min/70 calls；TD 3 会话/综≤3/布≤2/bitgen 1/CWC 1/下载 1；失败即停，不自扩预算，不批删。
