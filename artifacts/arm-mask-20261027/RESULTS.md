# 27MHz 单路收口 + 双路进展（2026-10-27/28）

> **2026-10-28 后续：本文「§4 双路仍未闭合」已被关闭。**
> 根因是 DDR 域打包器每拍只能做一件事（pop 或取字），双路事件数超过时钟预算导致
> FIFO 溢出丢组；把字节缓冲加宽到 128bit、允许同拍 pop+取字后，双路 60s 稳定 30.1fps、
> 丢组恒 0、A/B 帧均 `R10F_STRICT_OK`。本文里「FIFO 溢出会置 `line_bad_seen` →
> `p_bad=1`」这条推断**是错的**（`win_grp` 与 `wfull` 无关），已在新文修正。
> 证据与 A/B 对照实验见
> [dual-pack-20261028/RESULTS.md](../dual-pack-20261028/RESULTS.md)。

本文件记录在 `mclk-sweep-20261027` 之后的一轮硬件实验。全部数据来自实板，
位流为本轮新构建（S2）。**结论先说：A 单路已闭合（30.0–30.1 fps + strict OK）；
双路仍未闭合，但本轮推翻了"AXI 仲裁死锁"这个旧判断，并给出新的证据链。**

## 1. 本轮位流

| 项 | 值 |
|---|---|
| 文件 | `/tmp/fpga_mclk25/ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit` |
| SHA256 | `6120119f64ee99549b62c791dd8fafa928ed2eeeb3b93ae6e140760728cca101` |
| 大小 / 构建完成 | 5224023 B / 2026-10-27 23:50（TD 2026.2 NL） |
| 时序 | **Setup WNS +0.122 ns，Hold WNS +0.020 ns，0 违例**（19500 endpoints） |
| 配置 | MCLK_SEL=6（27MHz 分数分频）、891/27 表、CSI ref=50MHz、BURST_BEATS=64、BURST_GROUPS=410 |

## 2. 本轮 RTL 改动（全部在 /tmp/fpga_mclk25）

1. **写者 arm 掩码运行时可切**（原来 `SINGLE_B_TEST=1` 把 A 的 arm 硬接成 0，
   导致 A 路此前从未被真正测过）：
   - `ep_bar_win.v` 新增 `dbg_scratch` 输出（0x6C SCRATCH 直出），
     经 `pcie_ep_engine.v` 送到顶层；
   - `ph1p_pcie_ep_top.v`：`w_cam_arm_sel = (scratch[1:0]==0) ? CAM_ARM_DEFAULT : scratch[1:0]`，
     `arm_a = ddr_en & sel[0]`、`arm_b = ddr_en & sel[1]`。
   - **用法**：`0x6C` 写 1=只 A、2=只 B、3=双路。
2. **AXI 阶段停滞观测**（每路 16bit 最长连续停滞 + 8bit 计数），寄存器 0x188~0x19C：
   - `0x188 = {w_max, b_max}`：A_W 等 wready、A_B 等 bvalid；
   - `0x18C = {aw_max, rwd_max}`：A_AW 等 awready、A_RWD 等 hdr_ready；
   - `0x190 = {16'd0, rwd_tmo[7:0], burst_done[7:0]}`；B 路在 0x194/0x198/0x19C。
3. **两处安全自愈超时**（只加在"尚未发 W"的点，AXI 语义安全）：
   `A_AW` 等 awready 超过 65535 拍 → 撤 awvalid、判坏、回 A_IDLE；
   `A_RWD` 等 hdr_ready 超过 65535 拍 → 跳过 CRC 头重写、判坏、回 A_IDLE。
   这两处不会留下半截突发，因此不会让 DDR 从机等数据。

## 3. A 单路：已闭合

- 方法：`0x6C=1`（只 arm A）+ `CTRL=0x21`（ddr_en，不推帧）测连续帧率；
  `CTRL=0x61` + `rka1_smoke --arm` 取帧。
- 连续 60s（每 10s 采一次 `0xA0` = A 已发布帧号）：

```
t=10s seq=0x562 delta=300 fps=30.00
t=20s seq=0x68f delta=301 fps=30.10
t=30s seq=0x7bc delta=301 fps=30.10
t=40s seq=0x8e9 delta=301 fps=30.10
t=50s seq=0xa16 delta=301 fps=30.10
t=60s seq=0xb42 delta=300 fps=30.00
```

- 帧判决：`0xF0=0x3c80e900`（beats=81024、ROI 组数 518400）、`0xF4=0x20`（pub_ok）。
- 帧文件 SHA256 `614b9b0d5bfa12af6708e42c1dacda551ae2c42564abd5384fc2d5c8b1a35278`，
  `r10f_strict.py check --width 1920 --height 1080` → **R10F_STRICT_OK**。

> 历史"A 路只数到 1144/2192 行"在本轮 27MHz/891 表下**没有复现**。此前从未真正测过 A：
> `SINGLE_B_TEST=1` 把 A 的 arm 恒置 0，A 的写者从不下帧。A 的 CSI 侧（0x120/0x124）
> 与 B 完全一致（good 递增、bad/crc/hdr=0、last_lines=2192、last_wc=4830）。
> 因此"A 路 bug"更可能是 12.5MHz 时代的 CSI/IDELAY 现象，而不是 writer 几何。

## 4. B 单路：复核通过（同一支位流）

- `0x6C=2` + `CTRL=0x21`，连续 60s（每 10s 采 `0xE0`）：

```
t=10s seq=0x1f1 delta=301 fps=30.10
t=20s seq=0x31d delta=300 fps=30.00
t=30s seq=0x44a delta=301 fps=30.10
t=40s seq=0x577 delta=301 fps=30.10
t=50s seq=0x6a4 delta=301 fps=30.10
t=60s seq=0x7d1 delta=301 fps=30.10
```

- 帧判决：`0x180=0x3c80e900`、`0x184=0x20`（与 A 路同口径）。
- 帧文件 SHA256 `6a229e8acab8a85388a344631aff031792c7671d469024e8ce75c97a04b76b39`，
  → **R10F_STRICT_OK**。
- 该帧与 A 帧 SHA 不同，证明两路数据独立（见 §6 的注意点）。

## 5. 双路：仍未闭合，但旧结论被推翻

### 5.1 实测（`0x6C=3`，`CTRL=0x21`，双路 arm、不推帧）

| 观测 | A | B |
|---|---|---|
| 已发布帧号 10s 内 | 0x1E5 → 0x1E5（不动） | 0x23E → 0x23E（不动） |
| 判决 `0xF4`/`0x184` | 0x4 | 0x4 |
| `0xF0`/`0x180` 拍数 | 0x3c80（整帧 81024 拍） | 0x3c80（整帧） |
| ROI 组数（低 16 位） | 0x7EE4 | 0xCD8F |
| **w_max / b_max / aw_max** | **16 / 23 / 0** | **16 / 23 / 0** |

### 5.2 由此得到的两条硬结论

1. **不是 AXI 端口死锁。** 每路在 A_W/A_B/A_AW 的最长连续停滞分别只有 16/23/0 拍
   （0.16/0.23/0 µs）。若是旧判断的"一路卡住 AW/W 把 grant 压死"，这里必然出现
   接近 65535 的饱和值。旧结论里"0x178=0x7、FIFO 满在 1022 组"不足以支撑死锁：
   **`0x180`/`0xF0` 的 wcnt 只有 16 位**，1022 这类读数可能是 16 位截断后的假象
   （0x3FE 也可能是 459774 的低 16 位）。
2. **每帧都写满 81024 拍，但载荷组数不够，且 EOF 正常到达、无坏行标记**
   （verdict 只有 bit2 = `gcnt != 518400`，`p_bad=0`、`~p_eof_seen=0`）。
   这与"FIFO 溢出丢组"矛盾：真丢组会置 `line_bad_seen` → `eof_bad` → `p_bad=1`。
   所以丢数据发生在"组计数之外的路径"，本轮尚未定位到具体机制。

### 5.3 一个失败实验（避免后来者重复）

`BURST_GROUPS 410 → 820`（想让每笔突发尾部不再缺数）**反而打坏了单路**：
B 单路 `wcnt` 从 0xE900 掉到 0xD304、verdict 0x4、好帧 0。

原因：门槛只能小于"FIFO 深度 − 帧尾剩余量"。帧尾剩不到 820 组时写者停发，
相机继续写满 FIFO（1024 条）丢 EOF 标记 → 超时收口 → 整帧补零。
**所以门槛的可行区间是 [一笔突发的量 ≈410, ≈512]，410 已是可用值，不能靠加大门槛解决双路。**
（源码里已把这条教训写成注释，值回退到 410。）

## 6. 复跑命令

```sh
# 0) 构建（一次只能跑一个 TD）
cd /tmp/fpga_mclk25 && /opt/anlogic/TD_Release_2026.2_NL/bin/td.sh build.tcl
# 产物 ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit

# 1) 烧录 + 重启（SRAM，掉电即失；重启后才会重新枚举 Gen2x2）
/opt/anlogic/TD_Release_2026.2_NL/bin/bw.sh /tmp/fpga_mclk25/dl.tcl
ssh root@192.168.1.101 'sync; reboot'

# 2) 选路（0x6C：1=只A 2=只B 3=双路）
/root/tools/pci_bar 0 0x44 0x0
/root/tools/pci_bar 0 0x6c 0x1
/root/tools/pci_bar 0 0x44 0x21      # ddr_en；0x61 = A+推帧，0x161 = B+推帧

# 3) 帧率（A 看 0xA0，B 看 0xE0；别用 0x8C 判 A，0x8C 是 B 的 vsync 计数）
/root/tools/pci_bar 0 0xa0 ; sleep 10 ; /root/tools/pci_bar 0 0xa0

# 4) 判决（A: 0xF0/0xF4，B: 0x180/0x184；正常 0x3c80e900 / 0x20）
# 5) 取帧
/home/orangepi/newdrv/rka1_smoke --arm --baseline 0 --timeout 4000 --out /tmp/f.dma
python3 driver/tools/pcie_integration/r10f_strict.py check /tmp/f.dma --width 1920 --height 1080
```

## 7. 注意点 / 待查

1. **推帧源选择可疑一次**：在上一电周期里，先取 A 帧再切 B 取帧，两次文件 SHA 完全相同
   （都是 5de36ae9…）。重启后先只跑 B 再取帧，得到独立内容（6a229e8a…），说明 B 缓冲是真的。
   因此怀疑：改切 `CTRL[8]` 后立即 ARM 时，pusher 可能把 A 已发布但未推的帧先推出去。
   取帧流程应"先 `CTRL=0` → 设 `0x6C`/`CTRL` → 等 2s → 再 ARM"，或重启后先只跑目标路。
2. 双路的确切丢失机制仍未定位。下一步建议直接加"帧收口锁存"诊断：
   在 EOF/收口时锁存 `gcnt`、`frame_lines`、`y_cnt`、`drop_cnt`、`ovf_cnt`、
   `self_flush_cnt`、`cam_flush_cnt`，一次上板就能区分"少了行/少了口气/被 flush 掉了"。
   （本轮 16 位 `wcnt` 字段不足以判断缺口大小，是本轮最亏的一点。）
3. `0x80` bit15 / `0x84` bit13 的 anomaly 位是**粘滞**的（只被 `rst_cam_all` 清），
   开机后只要丢过一次就一直是 1，不能用来判断当前帧。
4. 27MHz MCLK 仍是 62.5MHz 分数分频（最小脉宽 16ns），P2 的 50% 占空 PLL 方案未做。
## 8. 交接时板子状态

- 位流：本文件 §1 的 S2（SHA `6120119f…a101`），SRAM，已在板上。
- `0x44=0x21`（B 路 + ddr_en，未推帧）、`0x6C=0x2`（只 arm B）。
- `0xA0=0x390`（A 已发布帧号）、`0xE0=0x9ff`（B 已发布帧号）、
  `0xF4=0x20`、`0x184=0x20` —— 两路判决都是"好帧"，说明只 arm 一路时单路是健康的。
- 改回双路只需 `/root/tools/pci_bar 0 0x6c 0x3`（再 `0x44 0x21`）。
- 主仓 `fpga` 未被改动（用户的 `BURST_GROUPS=500` 原样保留），本轮全部改动都在
  `/tmp/fpga_mclk25`，并已导出成 [arm_mask_stall.patch](arm_mask_stall.patch)
  （SHA256 `5f4d9a678b8d87bb22dff95be8df3396f8ee3b09d4048894bda998dac82aaa1a`）。
