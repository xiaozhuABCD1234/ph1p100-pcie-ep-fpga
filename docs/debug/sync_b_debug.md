# B 路不出 SOF 的根因分析（2026-10-29）

> 角色：FPGA 调试子智能体。未上板、未改 RTL，只读代码/仿真/查 IMX415 数据手册。
> 结论分「证据」与「推测」，最后给最小补丁与板上验证点。

## 0. 一句话结论

**B 的 14 笔同步角色写全部被 ACK（所以 error=5 而不是 2），B 的 I2C/配置是活的；但 B 在 slave 角色下
根本没有把一帧 CSI-2 发出来。故障在「B 传感器 → B 的 MIPI/CSI」这一段，位于 sync_offline 数字逻辑
之前。** 最可能的是 B 切到 slave 后拿不到可用的 A XVS/XHS（板上飞线/电平/时序），
其次是 B 的 4K 891 Mbps MIPI 在 B 路没有锁上。二者用 0x84/0x128 一次性区分。

**step4 把 B 的 0x3002 从 1 改成 0 不是回归点**：数据手册明确 0x3002 XMSTA 的 1=master stop、
0=master start；B 作为 slave 必须让它为 0（1080p 同一序列已锁 9 对）。当前 14 步的先后顺序也
符合手册的 slave/master 上电流程（下面有逐条对照）。

---

## 1. 先纠正一个会误导判断的寄存器

父级说「0x120 是 CSI 包计数诊断，值在 0x17010000 / 0x08000000 / 0x14000000 之间跳」。
**0x120 只是 A 路**：

| 偏移 | 含义 | 代码 |
|---|---|---|
| 0x120 | CSI_DIAG_A = {A good, A bad, A hdr_err, A crc_err} | `ep_bar_win.v:657` |
| 0x124 | CSI_DIAG_A2 = {A last_lines, A last_wc} | `ep_bar_win.v:658` |
| **0x128** | **CSI_DIAG_B** = {B good, B bad, B hdr_err, B crc_err} | `ep_bar_win.v:659` |
| 0x12C | CSI_DIAG_B2 = {B last_lines, B last_wc} | `ep_bar_win.v:660` |

所以 0x120 的跳变只能证明 **A 在出帧**，对 B 没有任何证明力。
另外 0x17010000 这种值按 8 位拆是 good=0x17(23 帧)、bad=0x01、hdr=0、crc=0，
正好是 0.8 s × 30 fps 的量级，是 A 的整帧计数，不是「B 的包统计在变」。

---

## 2. 证据链

### E1. B 的 I2C 是活的，14 笔角色写全部成功（高置信）

- `sync_start_ctrl.v:105` 的 error=5 只在 **WARM/RUN 等 pair_event 超时** 时置位；
  任何一笔角色写 NACK 会走 error=2（`sync_start_ctrl.v:79`），I2C 超时会走 error=3。
- 实测 0x1E4=0x00000510：bit4 stopped=1，[11:8]=5，确实走到了 WARM 之后。
- `prereq_ok = w_a_cfg_done && w_b_cfg_done && w_ddrphy_rdy`（`ph1p_pcie_ep_top.v:1458`），
  能 start 就说明 **B 的 201 项初始化表全部 ACK、w_b_cfg_done=1**。
- cleanup 的 6 笔也全 ACK，所以 stopped_confirmed=1（bit4）。B 在 cleanup 时仍在应答 I2C。

结论：B 的供电、XCLR、MCLK、I2C 地址、201 项初始化都正常；不是「B 不在线」。
注意 ACK 只证明「写被接收」，不证明寄存器值一定生效（没有回读通路）；但 0x3000/0x3002/0x3003
这三笔如果写错，表现正好就是 B 不出帧，所以它们是待查项而不是已排除项。

### E2. B 的 SOF 来源只有 B 自己的 CSI，不是 XVS 引脚（高置信）

- `ph1p_pcie_ep_top.v:1460`：`.sof_b(w_b_vsync)`。
- `w_b_vsync` 是 `u_csi_b` 的 `O_vsync`（`ph1p_pcie_ep_top.v:1415`），即
  `csi_rx_packet_integrity` 收到 B 的 **FS 包**那一拍（`mipi_csi2_rx_ph1p_checked.v:201`）。
- FPGA 顶层只有 `cam_a_mclk / cam_a_xclr_n / cam_a_scl / cam_a_sda`
  和 B 的对应 4 根（`ph1p_pcie_ep_top.v:55-62`）；约束里也只有这 8 根
  （`constraints/ph1p_pcie_case_ep.adc:54-61`）。**XVS/XHS 根本没有进 FPGA**。
- 因此 XVS/XHS 断了、只接了一根、电平不匹配，在 FPGA 里的表现都只能是
  「B 一帧都不出、B 没有 SOF」——和现在完全一致。

### E3. miss_a=0 + miss_b 增长，说明 B 的 SOF 是「完全没有」，不是「窗口外」（高置信）

`sync_sof_pair.v` 的超时分支：
- A 先到、窗口内等不到 B：`miss_b++`（line 33/36）。
- B 先到、窗口内等不到 A：`miss_a++`（line 34/40）。

如果 B 只是比 A 晚 >PAIR_WINDOW（100000 tick @62.5MHz = 1.6 ms）但仍在出帧，那么
B 迟到后会占住 have_b，下一帧 A 来之前它先超时 → **miss_a 也会涨**。
实测 miss_a=0、miss_b 每帧 +1，只能是 B 的 b_valid 从来没到过 pairer。
0.8 s 内 A 约 24 帧，miss_b 0x17→0x2e 正好 +23，和「A 每来一帧就记一次 B 缺失」吻合。

### E4. 14 步序列本身是对的，step4 不是回归（高置信）

IMX415 数据手册（IMX415-AAQR-C Technical Datasheet E Rev0.4）：
- 0x3002 XMSTA：**0 = Master mode operation start；1 = stop**（p39 寄存器表）。
- 0x3003 XMASTER：**0 = Master；1 = Slave**（p39）。
- 0x30C0：bit[1:0] XVSOUTSEL=2 输出 VSYNC，bit[3:2] XHSOUTSEL=2 输出 HSYNC，
  bit[5:4] 固定 2 ⇒ 0x2A 正确。
- 0x30C1：bit[1:0] XVS_DRV，0=output、3=HiZ；bit[3:2] XHS_DRV，0=output、3=HiZ
  ⇒ A=0x00 输出、B=0x0F Hi-Z 正确。
- Slave 流程（p87）：先写寄存器（含 XMASTER=1）→ STANDBY=0 → **等 24 ms** →
  外部 XVS/XHS 输入开始 → 等 8 帧稳定。
- Master 流程（p88）：STANDBY=0 → **等 24 ms** → XMSTA=0 → XVS/XHS 输出开始。

对照 `sync_start_ctrl.v`：
- step11 B 3000=0 → WAIT_B 24 ms（line 84/95）；
- step12 A 3000=0 → WAIT_A 24 ms（line 85/95）；
- step13 A 3002=0（master start）→ WARM。
即 B 释放后至少 48 ms 才看到 A 的 XVS，A 也是释放满 24 ms 后才 XMSTA=0。**顺序符合手册。**
step4 写 B XMSTA=0 是正确的，改成 1 反而会让 B 停住（与 10-28 的 1080p 实测一致）。

### E5. 数字通路仿真通过（高置信，但只证明 RTL 自洽）

`fpga/sim/tb/tb_sync_offline.sv` 用 iverilog -g2012 编译运行通过：
`SYNC_OFFLINE_PASS ... scenarios=prereq,hold,busy,order,wait,warmup,nack,timeout,missing,abort,reset,relock,overrun,wrap`。
TB 对 14 笔写的顺序/地址/数据、WAIT_B/WAIT_A 边界、warmup=8、单 B 缺失、abort cleanup、
NACK cleanup、timeout、复位恢复都做了断言。**在 B 有 SOF 的前提下，这套 RTL 能锁。**
（注意 TB 的 expected() 表已经把 step4 写成 0，所以它证明的是「当前实现与预期一致」，
不能证明传感器行为。）

---

## 3. 根因判断

### 主因假设（中高置信，需 0x84 一锤定音）

**B 被切成 slave 后没有收到可用的 A XVS/XHS，因此 B 的传感器状态机不启动，一帧 CSI-2 都不发。**
A 仍在出帧（0x80 的 lane_valid=F、in_frame=1、pv_seen=1），所以 A 的 master 侧和 MIPI 正常；
B 的 I2C 也正常。断点正好落在「A 的 XVS/XHS 引脚 → 板上飞线 → B 的 XVS/XHS 引脚」这段，
FPGA 既看不到也驱动不了。

可能的子原因，按可能性排序：
1. 飞线只接了 XVS，没接 XHS。手册 slave 模式**同时需要 XVS 和 XHS**（p65），
   且对两信号的相对沿有 tHFDLY/tVRDLY ≥ 1/fINCK 的要求（p18）。只接一根时，
   B 可能靠 XMSTA=0 的内部 H 时序撑过 1080p，但 4K30 全像素（HMAX=1100、891 Mbps）
   对 XHS 的依赖/容差不同，不能再靠内部时序兜底。
2. 飞线接触/电平问题：B 的 OVDD 与 A 的 XVS 驱动电平不匹配（手册特别写
   “Slave mode: XVS and XHS must not be over OVDD”，p81）。
3. A 的 XVS/XHS 在当前 4K 表下没有真正输出。注意一个时间线：10-28 20:08 的
   成功同步测试用的是 20:06 的位流，而 `ui_imx415_reg.v` 在 **20:16** 又被改过
   （4K 行/帧时序从 0x215/0x1197 改成 0x44C/0x8CA，SYS_MODE 改 0x05）。
   当前表对 A 的 MIPI 是好的，但不能排除它对 A 的 XVS/XHS 输出时序有副作用；
   这是「同一套 14 步、10-28 能锁、现在不锁」的一个可疑差异点。

### 备选假设（中置信）

**B 的 4K 891 Mbps MIPI 在 B 路没有锁上**（B 路 tap/PCB 信号完整性），B 没有 byte clock/FS 包。
A 同表能锁不等于 B 能锁；B 的 tap 默认也是 46（`ep_bar_win.v:311-312`），但 A/B 走线不同。
如果 0x84 显示 lane_valid=0 / bclk_seen=0，就是这一支。

### 明确排除

- **不是** sync_sof_pair 的 enable/clear 提前清掉：pairer 在 WARM 才 enable，B 若在出帧会持续产生
  SOF；且 miss_a=0 已排除「B 在窗口外」。
- **不是** sync_frame_gate：pairer 用的是 gate 之前的原始 `w_b_vsync`，gate 只影响下游 writer。
- **不是** 引脚约束漏了 XVS/XHS：这两根根本没进 FPGA，不存在约束可加。
- **不是** step4 的 XMSTA 回归。

---

## 4. 一锤定音的板上读法（不上板也能给主机端照做）

在**当前 sync 失败后、下一次 start 之前**，或在 **SYNC_ENABLE=0 的正常 4K 取帧**下读：

| 寄存器 | 看什么 | 判读 |
|---|---|---|
| 0x84 | B 状态字 | bit0=bclk_seen，[4:1]=lane_valid，bit5=cfg_done，bit8=in_frame，bit10=pv_seen，bit15=B I2C 曾 NACK |
| 0x128 | B CSI 包计数 {good,bad,hdr,crc} | good 是否以 ~30/s 增长 |
| 0x12C | B CSI 几何 {last_lines,last_wc} | 是否有 2160/3840 量级 |
| 0xE0/0xE4 | B writer seq/status | 是否曾发布过整帧 |
| 0x1E4 | 同步状态 | 成功应到 0x0008000D（warmup=8, locked=1, busy=1, ready=1） |

分支判读：

- **0x84 的 bit0=1、[4:1]=0xF、bit8=1、bit10=1**（和 A 的 0x80 同型）：
  B 其实在出帧！那问题才回到数字侧，重点查 B 的 mailbox（`clk_b=w_b_byte_clk`、
  `reset_b` 是否在 B 时钟起来前一直复位）和 0x128 的 good 计数。
  这种情况下把 0x84/0x128 原值发我，我再定位。
- **0x84 的 bit0=0 或 [4:1]=0**：
  B 没有 MIPI。先在 **SYNC_ENABLE=0** 的 4K 位流下确认 B 是否能出帧：
  - 能出 → B 的传感器/CSI 没问题，故障就是 slave 的 XVS/XHS 链路；
  - 不能出 → B 的 4K MIPI 本身没锁，先调 B 的 tap（0xD4）或查 B 的 lane，和同步无关。
- **0x84 的 bit5=0**：B 的初始化没完成（和 error=5 矛盾，基本可排除）。

---

## 5. 最小补丁

### 补丁 A（推荐先做，2 行；把 B 的 XMASTER 建立在 XMSTA 启动之前）

现状 `fpga/rtl/ep_side/cam/sync_offline/sync_start_ctrl.v:40-43`：

```verilog
3: begin camera_id=1;reg_addr=16'h3000;reg_data=1;end
4: begin camera_id=1;reg_addr=16'h3002;reg_data=MASTER_B;end // B slave=0 / B master=1
5: begin camera_id=1;reg_addr=16'h30c1;reg_data=8'h0f;end
6: begin camera_id=S;reg_addr=16'h3003;reg_data=1;end
```

改成（先 XMASTER=slave，再 XMSTA=0；手册要求 XMASTER 在取消复位/开始运行前建立）：

```verilog
3: begin camera_id=1;reg_addr=16'h3000;reg_data=1;end
4: begin camera_id=S;reg_addr=16'h3003;reg_data=1;end // XMASTER=slave first
5: begin camera_id=1;reg_addr=16'h30c1;reg_data=8'h0f;end
6: begin camera_id=1;reg_addr=16'h3002;reg_data=MASTER_B;end // then XMSTA=0
```

同时把 `fpga/sim/tb/tb_sync_offline.sv:25-26` 的 expected(4)/(6) 对调，否则 TB 会报 order fail。
这个补丁消除「B 在 XMASTER 还是 master 时就被 XMSTA=0 武装、两条写之后再切 slave」的瞬态；
如果 B 的 slave 锁死是这个瞬态造成的，这一改就能好。**它不改变 A 的 master 流程，也不改变
24 ms 等待，风险很低。**

### 补丁 B（若 A 无效，用来区分「B 传感器坏」还是「同步链路坏」）

给 `sync_start_ctrl` 加 `parameter B_FREERUN=0`；置 1 时把 B 配成自由运行的 master：
`3003=0、3002=0、30c1=0x00`，**同时把 A 的 30c1 写成 0x0f（Hi-Z）**，避免 A/B 同时驱动共享
XVS/XHS 打架。这样：
- B 出 SOF / 0x84 lane_valid=F / 0x128 good 增长 ⇒ B 传感器与 4K CSI 都正常，
  根因就是 slave 的 XVS/XHS 链路（查飞线、XHS 是否接、电平是否 ≤ B 的 OVDD）；
- B 仍不出 ⇒ 问题在 B 的 4K MIPI/PHY，和同步无关，转去调 B 的 tap/走线。
这是诊断补丁，不是最终同步方案；确认后应改回 A 主/B 从。

### 真正的硬件修复方向（若确认链路）

- 确认 A.XVS→B.XVS、A.XHS→B.XHS **两根都接**，且 B 端电平不超过 B 的 OVDD；
- 用示波器在 B 的引脚上量：XVS 30 Hz、1H 宽；XHS 约 67.5 kHz（4K30、HMAX=1100）；
  两信号相对沿满足 ≥1/27 MHz≈37 ns；
- 若沿关系不满足，可试改 A 的 `0x30CC XVSLNG`（1H/2H/4H/8H）和 `0x30CD XHSLNG`
  （16/32/64/128 clock），这两个寄存器当前表里都是 0，RTL 14 步也没写。

---

## 6. 给主机端的最短行动清单

1. 先读 **0x84**（B 状态）和 **0x128**（B CSI 计数），别再拿 0x120 当 B。
2. 如果 B 在 SYNC_ENABLE=0 的 4K 位流下 0x84 正常 → 应用补丁 A 重试 sync start；
   仍失败则按补丁 B 做 A/B 隔离，基本可判定为飞线/XHS/电平问题。
3. 判成功只看：0x1E4 到 0x0008000D、0x1FC 不再增长、0x1F8=0、0x84 的 lane_valid=F 且
   in_frame/pv_seen 置位、0xE0/0xE4 的 B 帧序号增长。

---

### 附：本次未做的事

- 未上板、未 ssh、未烧写、未运行 pci_bar/link_ctl。
- 未改任何 RTL/约束/文档；本文件是唯一新增产物。
- 本地无 ModelSim，仿真用 iverilog -g2012 跑 `tb_sync_offline`，通过。
