# 双路并行 30fps 闭合（P0）—— 打包吞吐瓶颈定位与修复

日期：2026-10-28
分支：/tmp/fpga_mclk25（detached 52f04919 + 本轮改动）
上位背景：`fpga/artifacts/arm-mask-20261027/RESULTS.md`（P1 单路闭合、双路未闭合）

---

## 1. 结论摘要

| 项 | 结果 |
|---|---|
| **P0 双路（A+B 同时 30fps）** | **已闭合** |
| 位流 SHA256 | `3d8ad2a7a7c6f051111905a6cf231575dfea8755ba8f584b3bdd4bbf6ef69f90` |
| 大小 / 构建时间 | 5,224,023 B / 2026-10-28 00:45（TD 2026.2 NL） |
| 时序 | Setup WNS **+0.105 ns**，Hold WNS **+0.020 ns**，0 违例 / 20693 endpoints |
| 双路实测（60s） | A 30.1 fps、B 30.1 fps（每 10s 各 +301~302 帧），两路 verdict 每次采样都是 `0x20` |
| 丢组 | `0x1A4`/`0x1C4` = **0**；`0x1B0`/`0x1D0` = **0**；`0x1A0`/`0x1C0` = 518400 |
| A 帧 | `b4cad07733757d3c277f86522f16bc4741f14560dc432070e3b57d17db257162` → `R10F_STRICT_OK` |
| B 帧 | `8dfb1268788b31945a7dedceb30c12057fbf1d1f3229cae926d9cbb636cd3050` → `R10F_STRICT_OK` |
| 两帧差异 | 2,307,334 字节不同（2,592,768 中 89%），证明是两条独立的相机通路 |

---

## 2. 根因：打包器每字节成本 > 双路可用的 clk_ddr 预算

### 2.1 账要先算对：clk_ddr 是 **100MHz**

上一轮把 `0x68`（=0x3E=62）当成 clk_ddr 频率，其实是 `tl_clk_user` 的 62.5MHz。
本轮从 `phy_1/final_timing.rpt` 的时钟表确认：

```
clk0: 100.000  u_ddr3_mc_0/usr_clk   ← dhi_clk，即 cam_r10f_writer 的 clk_ddr
clk1:  62.500  tl_clk_user
clk2: 187.547  cam_a_byte_clk
clk3: 187.547  cam_b_byte_clk
```

### 2.2 旧打包器的每帧事件数

一帧要搬 518,400 组（每 5 字节）→ 81024 拍（每拍 32 字节）。旧代码里
`pay_room=(bcnt<=3)` 与 `word_take=(bcnt>=4)` **天然互斥**，所以每帧的
clk_ddr 事件数 = 518400 次 pop + 648192 次取字 = **1,166,592 拍/路/帧**。
一帧 33.2ms × 100MHz = 3,320,000 拍，两路合计 2,333,184 拍 = **70% 占用**。

单路 35% 富余，双路只剩 30%，再叠加：
- `BURST_GROUPS=410` 恰好等于一笔 64 拍突发（409.6 组）的量 → 每笔突发**发出时基本没有余量**，
  传到帧中部 FIFO 就见底，`beat_vld` 把写口钉住等数据（`axi_busy=1`），这一段
  另一路完全拿不到写口；
- 两路相位一旦撞上，先发的那路把口占住，另一路 FIFO 只增不减。

FIFO 深度 1024 组 ≈ 2.1 行，扛不住这种量级的抱死，于是溢出丢组。

### 2.3 「gcnt 偏短但 p_bad=0」这个矛盾的真正解释

上一轮以为「FIFO 溢出会置 `line_bad_seen` → `p_bad=1`」，**这个推断是错的**：

```verilog
if (in_win && frame_armed) win_grp <= win_grp + 16'd1;   // 只数窗口内像素
```

`win_grp` 与 `wfull` **无关**，所以 wfull 丢组不会让行组数变短，也就不会置
`line_bad_seen`/`eof_bad`。丢组的唯一痕迹只有 `drop_cnt`/`ovf_cnt`（且是 16 位、
只有 `rst_cam_all` 清）——这就是以前怎么都判不出来的原因。
本轮把「每帧实际入队组数 / 因满丢掉组数」锁存到 `0x1A0`/`0x1A4`，矛盾立刻消失。

---

## 3. A/B 对照实验（决定性证据）

同一套诊断寄存器、同一套驱动/主机流程，只把打包器节拍换回旧逻辑（`pay_room=bcnt<=3`、
`hdr_room=bcnt<=4`、插入仍要求 `~word_take`），重出一版位流：

| | 旧节拍（对照位流 `ad7897bb…`，00:37） | 新节拍（`3d8ad2a7…`，00:45） |
|---|---|---|
| 模式 | `0x6C=3`、`CTRL=0x21` | 同左 |
| A `0xA0` 发布序号 | **恒 0**（40s 内不涨） | 30.1 fps |
| B `0xE0` 发布序号 | **恒 0** | 30.1 fps |
| A verdict `0xF4` | `0x4`（只有组数不符） | `0x20`（好） |
| B verdict `0x184` | `0x4` | `0x20` |
| A 每帧 push / drop | 359,227 / **159,173** | 518,400 / **0** |
| B 每帧 push / drop | 183,302 / **335,290** | 518,400 / **0** |
| A/B 丢标记 `0x1B0/0x1D0` | 0 / 0 | 0 / 0 |
| A/B flags `0x1BC/0x1DC` | `0x2`（p_eof=1, p_bad=0, tmo=0, eof_bad=0） | `0x2` |
| 打包占用 `0x1B4` / `0x1D4` | 4,208,399 / 5,030,119（**>1 帧周期**） | ≈3,335,3xx / 3,335,3xx（≈1 帧周期） |

读法：
1. `push + drop = 518,400` 严格成立 → 相机侧一帧的组数是对的，**丢在 FIFO 满**；
2. `0x1B4 > 3,320,000` → 这一路写完一帧要花超过一个帧周期，**打包器追不上帧率**；
3. `p_bad=0`、`ovf=0` → EOF 标记没丢，坏的不是标记而是数据 —— 与 §2.3 一致；
4. 两路丢的比例不同（A 31%、B 65%），但**合计只保住了 52%**，正是两路抢同一个写口
   各拿一半的结果。

---

## 4. 修复：让「取字」和「插入」同拍进行（16 字节缓冲）

`cam_r10f_writer.v`：

| 改动 | 旧 | 新 |
|---|---|---|
| 字节缓冲 `breg` | 64 bit | **128 bit** |
| 占用计数 `bcnt` | 4 bit | **5 bit** |
| `pay_room` | `bcnt <= 3` | `bcnt <= 10` |
| `hdr_room` | `bcnt <= 4` | `bcnt <= 11` |
| `pay_app/hdr_app/tail_app` | 要求 `~word_take` | 去掉该限制 |
| 插入偏移 | `bcnt*8` | `bcnt_base*8`，`bcnt_base = word_take ? bcnt-4 : bcnt` |
| 同拍写回 | `breg \| ins` | `breg_base \| ins`，`breg_base = word_take ? breg>>32 : breg` |

效果：每拍从「1 pop + 1 取字 = 2 个事件」变成「1 拍内同时做 pop 和取字」，
每帧事件数从 1,166,592 降到 **648,192**（取字数成为唯一瓶颈），
两路合计 1,296,384 拍 = 一帧的 **39%**，余量 61%。

> 为什么不是「把 `BURST_GROUPS` 调大」：820 组会让帧尾永远凑不够门槛 →
> 写者停发 → 相机写满 FIFO 丢 EOF → 超时收口补零（上一轮已实测到 B 单路
> `wcnt` 从 `0xE900` 掉到 `0xD304`）。要调大就必须同时解决「帧尾没到门槛也继续发」，
> 属于改流控；本轮改为提高打包速度，不动流控，风险面小得多。

---

## 5. 新增诊断寄存器（本轮加，长期保留）

每路 8 个字，帧收口（`frame_close`）时锁存：

| A 路 | B 路 | 内容 |
|---|---|---|
| 0x1A0 | 0x1C0 | 相机侧本帧**实际入队**像素组数（应为 518400） |
| 0x1A4 | 0x1C4 | 相机侧本帧**因 wfull 丢掉**的像素组数 |
| 0x1A8 | 0x1C8 | `{frame_lines[15:0], y_cnt[15:0]}`（EOF 时刻，实测 2192 / 2191） |
| 0x1AC | 0x1CC | `{16'd0, max_grp_per_line}`（实测 966 = 240 哑组 + 480 窗口组 + ...） |
| 0x1B0 | 0x1D0 | 因 wfull 丢掉的**标记**数（SOF/EOF） |
| 0x1B4 | 0x1D4 | 本帧「打包占用」clk_ddr 拍数（不含 S_SYNC / S_WAIT） |
| 0x1B8 | 0x1D8 | 收口时刻的 `gcnt` |
| 0x1BC | 0x1DC | `{27'd0, tmo_seen, p_bad, p_eof_seen, eof_bad}` |

判读速查：
- `0x1A0=518400 且 0x1A4=0` → 相机侧满帧、无溢出（健康）；
- `0x1A0+0x1A4=518400 但 0x1A4>0` → **FIFO 溢出丢组**（本轮故障态）；
- `0x1A0<518400 且 0x1A4=0` → 像素根本没进来（camera/arm 问题）；
- `0x1B4` 明显大于 3,320,000 → 打包器追不上帧率；
- `0x1BC` bit1(`p_bad`)=0 而 `0x1B8` 偏短 → 一定是溢出丢组，不是标记坏。

---

## 6. 另一处改动：推帧源在 ARM 之后再改 CTRL[8] 会永久空转

板测现象：`CTRL=0x61` 抓一帧、改成 `0x161` 再抓，两次文件**逐字节相同**。
排查结论（结合 RTL 与驱动/工具行为）：

- `ddr_frame_pusher.v` 的 `claim_desc_ok` 原来带 `(cam_sel_live == lat_cam)`，
  而 `lat_cam` 只在 **ARM 那一拍**锁存。ARM 之后再改 `CTRL[8]`，每帧 claim 都判
  `E_SRC=9`、`g_st` 原地停在 `G_ARMED`，**一个字节都不推**，主机 dump 到的还是上一块缓冲。
- 本机 `ep_bar_win` 的 `tx_block_cfg` 只挡 0x100/0x104，**不挡 0x44**，所以这个改动不会被拒。

最小修复（`ddr_frame_pusher.v`，2 处）：
1. `claim_desc_ok` 去掉 `(cam_sel_live == lat_cam)`（保留 `src_sel`/`frame_bytes` 的一致性检查）；
2. claim 时同步 `lat_cam <= cam_sel_live`，让 CTRL[8] 从本帧起生效。

回归风险：正常流程里两者本来就相等，判定逐拍不变；`base_lat` 本就取现场 `ddr_base`，
`claimed_cam` 也在 claim 时锁存，帧内不会被改 bit8 撕裂。

**尚未完全验证**：主机侧 one-shot ARM 的状态机还挡在前面 ——
一次成功推帧后 FPGA 进 HELD，之后 `CONFIGURE/ARM` 会被
`tx_block_cfg=(g_st!=G_IDLE)` 拒掉，`rka1_smoke --arm` 返回 `errno=22`，
`0xC0` 不涨（可据此判「这次根本没推」）。可靠抓帧流程见 §7。

---

## 7. 复跑 / 抓帧命令

### 7.1 双路 30fps（60s）
```sh
# 上板后（位流下载 + 重启），默认 CTRL=0x61、0x6C=0 → 双路 arm
pci_bar 0 0x44 0x0 ; sleep 1
pci_bar 0 0x6c 0x3          # 1=A 2=B 3=AB
pci_bar 0 0x44 0x21         # bit0 en + bit5 ddr_en，不推帧
# 每 10s 读 0xA0(A 发布序号) / 0xE0(B 发布序号)，6 次
```
判据：每 10s 两路都 +300~302；`0xF4=0x184=0x20`；`0x1A4=0x1C4=0`。

### 7.2 抓一帧做严格校验
```sh
pci_bar 0 0x44 0x0 ; sleep 1
pci_bar 0 0x6c 0x3          # 或 0x1 只开 A / 0x2 只开 B
pci_bar 0 0x44 0x61         # A 路：bit6 push_en, bit8=0
#   B 路：pci_bar 0 0x44 0x161
sleep 3
rka1_smoke --arm --baseline 0 --timeout 4000 --out /tmp/x.dma
# 主机侧：
python3 fpga/tools/pcie_integration/r10f_strict.py check /tmp/x.dma
```
**注意**：一次成功推帧后 FPGA 进 HELD，**第二次 ARM 会被拒**。要抓另一路请
「重启后先抓目标路」，或者把另一路 arm 掩码关掉再抓（本轮 B 帧就是这么拿到的）。

### 7.3 判据：`0xC0`（PUSH_DONE）必须 +1
`0xC0` 不涨 = 这次根本没推，落盘的必然是上一次的旧缓冲 ——
不看 `0xC0` 就会被「两次文件逐字节相同」误导。`0xC8=5` 是 `E_NOT_ARM`
（未 ARM 期间有新帧发布），正常；`0xC8=9` 是 `E_SRC`（源与 ARM 锁存不一致）。

---

## 8. 改动文件

| 文件 | 改动 |
|---|---|
| `rtl/ep_side/ddr/cam_r10f_writer.v` | 128bit 打包缓冲、取字/插入同拍；每帧 push/drop/占用统计与新端口 `dbg_frame`；`BTL_CW<8` 的重复次数钳位（小几何仿真可编译） |
| `rtl/ep_side/ddr/ddr_frame_pusher.v` | claim 不再用 ARM 锁存的 `cam_sel` 硬比对；claim 时刷新 `lat_cam` |
| `rtl/ep_side/img/ep_bar_win.v` | 新增 `dbg_frame_a/b` 输入；只读窗口 0x1A0~0x1DC |
| `rtl/ep_side/pcie_ep_engine.v` | `dbg_frame_a/b` 过路端口 |
| `rtl/ep_side/ph1p_pcie_ep_top.v` | 两路写者 `dbg_frame` 连线；`0x6C` 作运行时 arm 掩码（上一轮已加） |

补丁：`fpga/artifacts/dual-pack-20261028/dual_pack.patch`
（`git diff -- rtl`，SHA256 `c7cff700f21e1a6383d329d2be73b48beb5a83d3110a01ba41244600656d533d`）

---

## 9. 遗留问题（已知、未在本轮关闭）

1. **推帧 one-shot ARM 状态机**：成功推一帧后必须 ACK 释放再重新 CONFIGURE+ARM，
   否则第二次 ARM 被拒（`errno=22`）。属主机侧流程，建议在 `rka1_smoke` 里
   先 `CANCEL`→等 IDLE→CONFIGURE→ARM，并在推帧后校验 `0xC0` 增量。
2. **`mid_frame` 期间冻结超时会让某一路永久卡在 `S_PAY`**：相机中途停（关 arm / 掉流）后
   帧尾组数永远到不了 `BURST_GROUPS=410`，`mid_frame` 永久挂 1、`tmo` 不计数。
   板测可复现（关掉 A 路后 `0x170` 长期停在 `s_state=S_PAY`）。修法要单开一个
   「`mid_frame` 长看门狗」，别再动通用 `tmo` 判据（上一轮试过，会让小几何仿真 P6/P7 红）。
3. **AXI 4KiB 边界**：帧首 128 字节之后每笔 64 拍（2048B）突发起点页内偏移恒为 128，
   会跨 4KiB 边界，属 AXI4 形式违规。实测数据没错（整帧 CRC 读回通过、30fps 稳），
   但建议按「第二笔截到页尾 3968B」钳位一次，零额外突发、零吞吐代价。
4. **P2 27MHz MCLK 质量**：仍是 62.5MHz 分频（最小脉宽 16ns），50% 占空比的 PLL 方案未做。
5. 仿真 TB `tb_cam_r10f_writer` 的 P1~P3 在 `BURST_GROUPS=410` 下是**已知红**
   （小几何帧只有 8 组，永远到不了 410 组门槛）；P10 1080p 的字节级项
   （头 128B / 抽拍 / 尾零 / 头 CRC / 载荷 CRC）**本轮全过**，
   红的 4 项（burst 计数 / 4KiB / 地址序列 / rewrite strb）经复核是 TB 判据问题
   （把帧首 4 拍头突发和末笔 124 拍当成重写笔），不是数据面错误。

---

## 10. 2026-10-28 追加：图像质量（增益）与"能稳定抓到 A/B 两帧"的流程

### 10.1 先看图：旧增益下 1080p ROI 只有 7% 灰阶

用 `driver/tools/r10f_view.py` 把帧解回 PNG 后发现画面"有内容但几乎全黑"：

| 帧 | 均值/1023 | 中位 | p99 | p99.9 |
|---|---|---|---|---|
| 改之前（`GAIN_PGC_0=0x10`，4.8 dB） | 70.9（7%） | 62 | 150 | 177 |
| 改之后（`0x40`，19.2 dB） | **144.7（14%）** | 100 | **562** | 680 |

曝光侧已经没有余量：`SHR0=0x008`、`VMAX=2250`（4K 全像素 30 fps），
积分时间 ≈ 整帧 \(33\ \mathrm{ms}\)，再长就会掉帧率。所以只能提模拟增益：

```verilog
// rtl/ep_side/cam/ui_imx415_reg.v:51
- 51: REG_DATA = (MODE==2'd1) ? {16'h3090, 8'h10} : {16'h3090, 8'h20};
+ 51: REG_DATA = (MODE==2'd1) ? {16'h3090, 8'h40} : {16'h3090, 8'h40};
```

`GAIN_PGC_0` 是 0.3 dB/LSB：`0x40`=64 → 19.2 dB ≈ 5.25×。
**注意**：这是固定增益，白天必须回调（`0x10`~0x20 量级）；真正该做的是 AEC/AGC —— 见遗留项。

### 10.2 相机被倒装：查看器加 `--flip 180`

板子上相机因空间限制**上下颠倒安装**，所以抓下来的图是 180° 旋转的（"Lenovo"标倒着、
桌面在上方）。给 `driver/tools/r10f_view.py` 加了方向修正，convert / snapshot 都支持：

```sh
python3 driver/tools/r10f_view.py convert /tmp/a.dma -o /tmp/a.png --flip 180
python3 driver/tools/r10f_view.py snapshot -o /tmp/s.png --flip 180 --last-seq N
```

RTL 侧**不做**翻转：帧按传感器原生朝向落盘（R10F 是原始数据交付格式），
朝向属于显示层的事，交给主机。

### 10.3 抓帧流程：ARM 必须幂等，且必须看 `0xC0`

复现到两个真问题（都已修）：

1. **驱动 ARM 不幂等**：上一次推完没 ACK / 没 CANCEL 时，`TX_STATUS` 停在
   HELD/ARMED，`anlogic_pci_rka1_arm_one_shot()` 直接 `-EBUSY` 硬拒，
   于是"第二次抓帧"永远失败，而驱动/工具都不报错，落盘的还是上一块缓冲（表现为两次
   文件逐字节相同）。
   修法：新增 `rka1_quiesce_to_idle()`（HELD→用 `0xC0` 当 ack_seq 自动 ACK；
   ARMED/BUSY/DRAIN→CANCEL），并用"读状态→动作→再读"的 60 ms 轮询，
   因为板上实测存在"读到 HELD、几微秒后已是 ARMED"的竞态。
2. **ACK 不幂等**：非 HELD 直接 `-EINVAL`，把"这一帧根本没推"伪装成"ACK 失败"，
   工具只能报 `errno=22`。改成：还在 ARMED 就 CANCEL 收回并返回成功，
   其余情况视为已释放；成败交给 `0xC0` 增量判定。

新的稳定抓帧脚本（`/root/cap.sh`，已随板）：

```sh
PB=/root/tools/pci_bar
if [ "$1" = "b" ]; then CTRL=0x161; else CTRL=0x61; fi   # bit6 push_en + bit8 选路
# 1) 释放残留 HELD：0x110=session, 0x10C=0xC0, 0x108=0x2
# 2) 选路：0x44=$CTRL
# 3) ARM：0x108=0x1
# 4) 轮询 0xC0 必须 +1（唯一硬判据；不涨就是没推，落盘必是旧缓冲）
# 5) dump：python3 /root/r10f_view.py snapshot -o out.png --last-seq <旧0xC0> --flip 180
# 6) ACK：0x110=session, 0x10C=0xC0, 0x108=0x2
```

实测（同一轮、不重启、连着抓）：A 帧 `0xC0: 6→7`、B 帧 `0xC0: 7→8`，
两张图内容不同（A 是桌面全景、B 是另一台相机对着暗处显示器），
说明选路 + ACK + 重 ARM 这条链现在是对的。

### 10.4 本轮位流

| 项 | 值 |
|---|---|
| SHA256 | `29fb08694802d54ee78c494cf1655e6d8e2716400fb1d8784b7e2092ed1d2042` |
| 构建 | 2026-10-28 01:00（TD 2026.2 NL） |
| 时序 | Setup WNS **+0.100 ns**、Hold WNS **+0.020 ns**，0 违例 / 20734 endpoints |
| 与上一版的差异 | 只有 `ui_imx415_reg.v` 的增益常量（逻辑零改动） |
| 双路复核 | 30.1 fps × 2，verdict 全程 `0x20`，`0x1A4/0x1C4`=0 |

证据图：`frame_vA_960x540.png`（A 路）、`frame_vB_960x540.png`（B 路，已 180° 翻转）。
驱动补丁：`driver_arm_idempotent.patch`（`src/anlogic_pci_rka1.c` + `tools/r10f_view.py`，
SHA256 `5c870a642c606165a164a111c7ccbdfcd58b487816592d9f449fdd9c2462d6bb`）。

> 驱动模块是主机侧 **交叉编译** 出来的（板上的 `/lib/modules/*/build` 指向宿主机路径，
> 在板端不可用）：
> ```sh
> cd driver && make -C <bsp>/third_party/linux M=$PWD ARCH=arm64 \
>      CROSS_COMPILE=aarch64-linux-gnu- modules -j8
> scp anlogic_pci.ko root@<board>:/root/ && ssh root@<board> 'rmmod anlogic_pci; insmod /root/anlogic_pci.ko'
> ```
> 换模块不会动 FPGA 位流（SRAM 里那份照旧跑），probing 时也不会打断相机采集。


### 10.5 提增益后仍然严格合规

新位流 + 新驱动下抓 A 路原始槽（snapshot --raw，2592768 字节）：

| 项 | 值 |
|---|---|
| SHA256 | 37788ce986524c322191e5a7c14f6d756daf8d1e229a8e288d360603f20f2974 |
| r10f_strict | **R10F_STRICT_OK** |
| 0xC0 | 10 → 11（确实推了新帧，不是旧缓冲） |

r10f_view.py snapshot 新增 --raw <file>：一次抓帧同时产出 PNG 与可给 r10f_strict.py 用的原始槽，
省掉「再跑一次 rka1_smoke」这一步（那条路还会多消耗一次 ARM 额度）。

### 10.6 下一个该做的：AEC / AGC

固定增益是权宜之计：19.2 dB 在夜里刚好看得见，白天会直接过曝。
正解是在 RTL 里做帧统计 + I2C 回写（ui_i2c.v 已经在），按帧均值/分位数调整
0x3090 与 SHR0，把曝光优先顶满、再补增益。