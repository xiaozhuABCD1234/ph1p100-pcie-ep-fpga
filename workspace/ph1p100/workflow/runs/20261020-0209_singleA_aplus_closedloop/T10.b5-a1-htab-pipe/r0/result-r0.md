# T10.b5-a1-htab-pipe r0 -- 单一地址流水（htab_p3v → bm_b.addrb）结果

日期：2026-10-24。开发角色单会话。只改一处锥；UART 旁路 + 心跳保留；
**离线候选已冻结，板级（1 次 SRAM 下载 + COM8 120 s）因板卡不在位未执行，下载额度未使用（0/1）。**

## 1. 输入事实（未重复排查）

- r4：UART 旁路离线全绿，但 Routed `-0.274 / 23 端点`，全部是
  `u_core/htab_p3v_syn_23.clkb → u_core/bm_b_syn_29.addrb[12:0]`；三次布线逐位相同。
- 冻结输入实测哈希复核通过：core `d4b79961…`、frame `c8b24775…`、store `8bab440d…`、
  crop `ca2f5d16…`、arb `6513ad83…`、fifo `59dd6dcb…`、uart export `3dad065f…`、
  camera top `b1041676…`、SDC `928498…`、引脚 `1cb303…`、r4 顶层副本 `b782dd0c…`。

## 2. 变更（唯一一处）

`r0/changed-src/a1_deflate_core.v`（`29b1e3e1…c9828`，79,788 B），差异见
`r0/rtl-diff-r0.patch`。相对 upstream `d4b79961…` 共 1 个新 flop + 一段 mux + S_EXT 一个等待拍：

```verilog
reg [12:0] bm_b_spec_q;
always @(posedge clk) if (s1_en)
    bm_b_spec_q <= htab_byp ? htab_byp_data[49:37] : htab_q[49:37];
wire [12:0] bm_raddr_b = s1_en            ? bm_b_spec_q
                       : (state == S_EXT) ? ext_faddr
                       :                    raddr;
```

- **打断的同拍关系**：原 `bm_raddr_b` 在 `s1_en` 拍直接取 `htab_q[49:37]`（htab ERAM 的
  clk2q 输出）驱动 bm_b 的 ERAM 地址；现在该地址一律来自 fabric flop `bm_b_spec_q`
  （写优先旁路时取 `htab_byp_data[49:37]`，同样是 flop）。热路径变成
  `htab_p3v_q → bm_b_spec_q`（ERAM clk2q → 普通寄存器），不再有 ERAM→ERAM 同拍。
- **为什么不是方案 1/2**：①“htab 读地址提前一拍”需要 position pos+3 的三个 hash 字节，
  第三个正是 `bm_a_rd`（bm_a 的 ERAM clk2q 输出，r0 bm-prefetch 刚把它从地址锥里拿掉）
  —— 那只是把同一个违例搬到 htab 地址上；要合法实现必须再加一级 bm_a 预取（bm 预取语义，越界）。
  ②“只寄存 htab_p3v_q 而不移动消费端”不改变同拍依赖。故采用获批的方案 ③ 变体：
  给 bm_b 读数据/消费加一级，命中消费整体后移一拍。
- **消费端对齐**（保证压缩字节不变）：命中拍 H 寄存 `cq_r = bm[pos+3]`；S_EXT 第一个
  等待拍 (a) 把 k=0 比较 `cq_r vs bm[ref+3]` 寄存进 `ext_mis_r`，(b) 同时把
  `ext_raddr/ext_faddr` 推进到 contig 的 pos+4/ref+4；从第一个判决拍起，
  比较流/地址流与原来逐拍一致，只有判决（进而 `len_r`）晚一拍。
  等待拍内 `ext_zero_r/len_cap_r` 保持命中拍装载值，循环停止序列与原来完全相同。
- 未改：htab 编码/尺寸/`enc_bank`、bm 预取深度与窗口链、match/threshold、候选打包、
  stored 回退、帧/CRC/字节序/长度/DDR 布局、SDC/引脚/时钟/复位；无 false path、
  无 multicycle、无改 seed、无降频、无新增 ERAM（101，与 r4 相同）。

## 3. P1 字节级回归（ModelSim 10.5b，`UART_DIV=1`，`HB_DIV=0`）

TB 沿用冻结的 `T10.b1-a1-uart-integ/r0/sim/tb_camera_a1_uart_top.v`（未改），
核心用本包 `r0/changed-src`。`vlog 0 errors / 0 warnings`（`sim/logs/vlog_r0.log`）。

| case | r4 字节 | r0 字节 | 逐字节一致 | r0 SHA256(.dec) | r4 cycles | r0 cycles | Δ% |
|---|---|---|---|---|---|---|---|
| micro8x2 (8×2) | 63 | 63 | 是 | `fa513a2b…edef` | 3809 | 3809 | 0.000 |
| mid64x8 (64×8) | 150 | 150 | 是 | `ee61e620…9789` | 5172 | 5178 | +0.116 |
| full_grad (1920×1080) | 40,076 | 40,076 | 是 | `b992a8ad…ada9` | 6,421,414 | 6,421,438 | +0.0004 |

`full_grad` stat：`exported=1 exp_bytes=40032 cap_bytes=40076 raw_pub=1 raw_drop=0
cmp_drop=0 geom=0 err=0 dup_words=0`（44 B 帧头 + 40,032 payload）。三例无 X/半帧。
汇总 `r0/p1-regression-r0.json`，抓包 `sim/captures/*.dec|*.stats`。

### 3.1 第一次实现差一字节（已定位并修正，留作证据）

首版只在 S_EXT 等待拍里“不动地址”，结果 micro8x2 18 B（应 19 B）、mid64x8 104 B（应 106 B）。
用 `A1_TRACE_EXT` 探针（`sim/dbgsrc/`、`sim/logs/tr_*.log`）对比 upstream/本包：
命中后 k=1 的对被比较了两次（等待拍没有推进 `ext_raddr/ext_faddr`），
循环多走一个“匹配字节”，`len` 多 1（8→9）。修正=等待拍同时 `+1` 推进地址，
P1 三例立即逐字节一致。**这是本包唯一的返工。**

## 4. 综合（syn_1，第 1 次，TD Release_2026.2 / PH1P100SBG484 -3）

| 项 | 值 |
|---|---|
| SWNS / STNS | **+0.222 ns / 0.000 ns** |
| 违例端点 | 0 / 15,062（coverage 95.36%） |
| 资源 | #lut 22,575（lut6 8,437）/ #reg 16,026 / **ERAM 71** / #slice* 16,719（23.32%） |

- **综合门 `SWNS ≥ +0.3` 未达（+0.222）**。新的综合关键路径是
  `u_core/len_r_reg[2] → u_core/cand_bits_reg[31].d`（6 级，data path 5.047 ns），
  属于 match-length / candidate-bit 计数链，**不在本包获批的唯一锥内**；
  htab→bm_b 锥在 gate 级也已不再是最差路径。
- 未再消耗第 2/3 次综合：同一 netlist 的 TD 综合是确定性的，脚本里没有非 seed 的合法旋钮；
  要提高只能改第二处 RTL（越界）。因此按“不静默放宽”交规划裁决，不自行改阈值。
  （事实参照：r4 自己的综合是 +0.256，同样 < +0.3，仍进入了布线。）
- 证据：`td/syn_gate_timing.rpt`、`td/syn_gate_area.rpt`、`td/build_console_r0.log`。

## 5. 布线（phy_1，第 1 次）

| 项 | 值 |
|---|---|
| Setup（slow） | **WNS +0.100 ns / TNS 0.000 / 0 违例端点 / 19,659** |
| Setup（fast/min corner） | WNS 0.000 / TNS 0.000 / 0 |
| Hold | **WNS +0.020 ns / TNS 0 / 0** |
| Period Check WNS | +2.200 ns |
| 组合环 / 无时钟网络 | 0 / 0 |
| LUT6 / reg / ERAM / slice | 18,751 / 25,122 / **101**/300（71 + CWC 30）/ 22,516（31.41%） |
| STA coverage | 96.87% |

- **Routed 0 违例 = 门槛通过；WNS +0.100 高于 +0.05 下限、低于首选 +0.2 → 带 caveat**
  （已写入 manifest）。
- r4 的 23 个 `htab_p3v → bm_b.addrb` 端点在本版 `routed_timing.rpt` 中**不再出现**；
  新的最差路径是 `u_core/sdata_ptr_reg[10] → praddr_b2[*]/pbit_off_b3[*]` 时钟使能（+0.100）。
- 第 2 次布线未用：r4 已证明 TD 布局确定性（三次逐位相同，且 hi 档
  `postrt_opt_loc 40 / extra_round 12` 与默认档逐位相同），而第 1 次已 0 违例并越过下限。
  本次实际生效的布线策略 = `post_route_opt ultra` + `postrt_opt_loc 20` + `postrt_opt_extra_round 4`
  （`01_build.tcl` 里的冻结组；`td/a1_board.al` 的 Runs/UserParams 与 `params_after.tcl` 可核对）。
- 证据：`td/routed_timing.rpt`、`td/routed_qor.rpt`、`td/routed_area.rpt`、
  `td/routed_check_timing.rpt`、`td/route_flow.status`、`td/build_console_r0.log`。

## 6. bit / CWC（各 1 次，fail-closed 放行）

- `02_bitgen.tcl` 释放判定：`setup 0.100/0.000 hold 0.020/0.000 period 2.200`，
  `candidate_abnormal.rpt` 0 端点 → 生成 bit。
- `a1_board.bit`：**`e00c5f06655c71e4038a962b8cf8dff590ff05e89ddd752722fda843f7fd2ad5`**（5,224,022 B）
- `a1_board.cwc`：`e2269eeda20507b72488960eb3d381e039491abb886f262b1c5eedc48ba5393a`（110,168 B）
- `a1_board_inst.bid`：`12daf16819d7915cb1ac94da5ebc592d8a6e4109ebb8bb378f898e273045a8ba`（95,905 B）
- `cw/compiled.bit` 与 `a1_board.bit` **逐字节相同**（同 sha256），`cw/compiled.cwc` 同 cwc。

## 7. 板级：blocked（板卡不在位，下载额度 0/1 未用）

只读探针 `r0/board/ping_cable.tcl`（连一次、读 ID、关闭，不下载）：

```
connect_cable -host_name 127.0.0.1:5555   (无报错)
read_device_id                            → PRG-8000 ERROR: transfer failed
```

环境事实（本次实测）：

- `[System.IO.Ports.SerialPort]::GetPortNames()` = **COM3,COM4**（**没有 COM8**）；
- PnP 中无任何 FTDI/USB-Serial 设备（只有主板蓝牙串口与普通 USB 设备）；
- `hwserver` 进程已不存在（r4 记录的 PID 77088 已消失）。

→ 无法执行唯一的 1 次 SRAM 下载，也无法做 COM8 120 s 采集/解码。按规则**不重试、不写 Flash、
不第二次下载、不为了拿数据绕过 fail-closed**。`r0/board/` 内脚本已就绪，板卡恢复后按
`README-r0-board.md` 一次跑完（ping → download → capture 120 s → resync_decode）。

## 8. 边界与未测

- 未改 `upstream/**`（只读取复制）；未改 r3/r4 证据与 P1 r6 manifest；未改 `workflow/tasks.json`。
- 未做：板级下载/采集/解码（设备缺失）；CDC 专项报告（TD 该版本无 `report_cdc`）。
- 潜在风险：S_EXT 每命中多 1 拍；本仿真里被相机喂数节流吸收（+0.0004%），
  真实 1080p 连续块流下若命中率极高，吞吐影响仍应 ≤ 0.1%（按每命中 1 拍 / 每 3~4 拍 1 字节估计，
  需 P3 实测确认）。
- 综合门 +0.222（< +0.3）是**已知偏离**，见 §4，需规划/独立测试者判定。
- `resync_decode.py` 仍为 r4 原文件（未改），其本身仍是待验对象。

## 9. 复测清单

- `required_dimensions`: integrated / functional / engineering / system
- `required_checks`:
  1. 复核 `r0/changed-src` 核心哈希 `29b1e3e1…c9828` 与 `rtl-diff-r0.patch`；
     其余 artifact 见 `r0/artifact-hashes.txt`；确认只有 1 处 RTL 变化。
  2. 重跑 P1 三例（HB_DIV=0），要求 SHA256 与 r4 一致（§3 表），stats/vlog 同表。
  3. 工程：syn_1 +0.222（门未达，见 §4）、phy_1 0 违例 +0.100（caveat）、hold +0.020、
     ERAM 101/300、0 组合环/无时钟；确认 r4 的 htab→bm_b 端点组已消失。
  4. bit/CWC/BID 哈希与 `compiled.bit` 一致性（§6）。
  5. 系统：**未执行**（板卡缺失）→ 需在板卡恢复后按 `r0/board/README-r0-board.md`
     用**仍未使用的** 1 次 SRAM 下载 + COM8 120 s 完成；判定矩阵同文件。
- `input_status`: changed（`r0/changed-src/a1_deflate_core.v`），其余同 r4。

## 10. 板卡恢复后的唯一续跑入口（不重新出 bit）

```
cd <r0>\board
td_commands_prompt.exe ./ping_cable.tcl          # 期望 R5_PING_DEVICE=...
td_commands_prompt.exe ./download_sram_r0.tcl    # 唯一一次 SRAM（-mode jtag）
python capture_com8.py --port COM8 --baud 115200 --secs 120 --outdir <r0>\captures
python resync_decode.py <r0>\captures\com8_120s.bin <r0>\decode
```
