# 板级实测：T07/RKA1 单引擎（PH1P100 + OrangePi 5 Max），2026-10-27

本文件是 `origin/main` 那套 T07/RKA1 单引擎（1080p RAW10 R10F）在**真板**上的第一次
下载与收帧记录 —— 此前 `docs/PROJECT_SYNC_20261027.md` 明确写着 b20 的下载次数为 0。

## 1. 位流与构建

| 项 | 值 |
| --- | --- |
| 源 | 本仓 `main`（含 `fix(rtl)` 两个提交：未选中相机退出发布保护、TL 发送状态补到 6 位） |
| 工程 | `ph1p_pcie_ep_top.al`（`build.tcl` 无头编译，TD Release 2026.2 NL） |
| 位流 | `ph1p_pcie_ep_top.bit`，5224023 B |
| 位流 SHA256 | `af8a749924b58525acd17dbd191cfa89e27ba28153b75ce9e7281bff1fb16df2` |
| 综合 / 布线 | syn 97 s、phy 226 s |
| 时序 | SWNS **+0.108 ns**、HWNS **+0.020 ns**、0 个违例端点（18719 个端点） |
| 下载 | `bw.sh download_sram.tcl`（`-mode jtag`，SRAM，易失）→ `PRG-2014: Chip validation success: PH1P100`，24.5 s |

## 2. 链路

香橙派 5 Max（RK3588）重启后重新枚举：

```
rockchip-dw-pcie a40000000.pcie: PCIe Gen.2 x2 link up
pci 0000:01:00.0: [1edb:abcd] type 00 class 0x050000   BAR0 1 MB
LnkSta: Speed 5GT/s, Width x2
```

RKA1 安全扩展在场：`0x118 = 0x31414B52`（"RKA1"）、`0x11C = 0x00010000`（v1.0）。

## 3. one-shot 收帧实测（相机 B）

驱动侧（probe 里 ARM 一次）+ 用户态 `rka1_smoke`：

```
缓冲: phys=0xffc00000 stride=2596864 slot_bytes=2592768 hdr=128 1920x1080
PROBE      magic=0x31414b52 ver=0x00010000
ARM        tx=0x00000001 armed=1
等帧: ready=1 seq=1 count=1 slot=0
已落盘: 2592768 字节，头四字节=52 31 30 46（"R10F"）
ACK        held=0（释放成功）
```

链路侧计数：`0xC0 pushed=1`、`0xCC tlp=20256`（= 2592768 / 128，与 128B 载荷一致）、
`0xC4=0x1E`（last_ok=1、doorbell_sent=1）、`0xC8=0`。

帧内容校验（`driver/tools/pcie_integration/r10f_strict.py`，严格逐字段）：

```
{"file": "rka1_frame.dma", "size": 2592768, "ok": true, "marker": "R10F_STRICT_OK"}
```

帧 SHA256 `a7063149c4bbb953ce7fdeacfb280fa677097f03c69862cfae9b1e07437e4edb`；
几何 1920x1080、stride 2400、roi (960,540)、三层长度与三段 CRC 全部对齐。
把 packed RAW10 解回 10bit 后得到的是真实场景（吊顶空调、显示器一角、走线），
不是常量图样：[/docs/board-20261027/rka1_frame_gray.png](board-20261027/rka1_frame_gray.png)（灰度）、
[GRBG 直出彩色预览](board-20261027/rka1_frame_grbg_preview.png)（没做 AWB，偏绿是相位/白平衡未处理所致）。

## 4. 板级发现的缺陷：A 路 R10F 写者从不发布

同一次上电、同一份位流、同一份驱动：

| | A 路（`0xA0~0xAC`） | B 路（`0xE0~0xEC`） |
| --- | --- | --- |
| `DDR_FRAME_SEQ` | **0**（从未发布） | 2715 |
| `DDR_STATUS` | `0x0519001E`：valid=0、busy=1、err=1、err_cnt=**1305** | `0x1B`：valid=1、busy=1、err=0 |
| `0xD0`（写者诊断：lines/grp） | lines=**1144**、grp=966 | lines=**2192**、grp=966 |

判据：`cam_r10f_writer` 的发布判决要求「组数 == W*H/4 == 518400」且「DMA 拍数 == DMA_BEATS」，
A 路每帧只数到 1144 行（B 路 2192 行 = 完整 4K30 行数），组数对不上 → 每帧 `pub_err=+1`，
`valid_fb` 永远为 0。1305 ≈ 运行时长 × 帧率，即**每一帧都失败**，不是偶发。
MIPI 侧 A 路的 `CSI_DIAG_A` 只有 37 个 good 包、`CSI_DIAG_A2` 的 last_lines 却也是 2192,
所以问题在 R10F 写者对 A 路行/组的裁剪计数上，不在 CSI 收包。

**因此这次上板验证走的是 B 路**：先把 `CTRL[8]=1`（`cam_ab_sel` 选 B）再 ARM。
`cam_ab_sel` 是在 ARM 那一拍锁存的（claim 时与 `cam_sel_live` 比对），所以顺序不能反：

```bash
# 板子上（root）
/root/tools/pci_bar 0 0x44 0x161        # bit0/5/6 + bit8=选 B
/root/tools/pci_bar 0 0x44              # 回读确认
/home/orangepi/newdrv/rka1_smoke --arm --baseline 0 --timeout 4000
```

A 路这条待修：先在 A 路把 `lines/grp` 的裁剪计数与真实 2192 行 4830 字节/行的流对齐
（`SKIP_ROWS`/`Y0` 与 `GROUP_TOT` 的推导），再用同样的脚本复跑。

## 4b. 重复性：两帧各自独立校验

不用重烧也能连续取帧（每次 ACK 释放后重新 ARM）：

| 帧 | 结果 | SHA256 |
| --- | --- | --- |
| 第 1 帧（probe 那次 ARM） | `R10F_STRICT_OK` | `9937a359b108e099fd5d4b6a112b4d61035c2df6abeed28e1ea0b84e4c7db39f` |
| 第 2 帧（ACK 后重新 ARM） | `R10F_STRICT_OK` | `3515f02f118ef139c6edc829638d584e61d3c1a6f887e503b30da7907609e982` |

两帧 SHA 不同（是活数据，不是常量图），且 `0xC0` 单调 +1（1→2→3→4）。
另外发现并修掉一个驱动侧坑：**上一次没 ACK 就把模块卸掉，FPGA 会停在 held**，
下次 probe 的 CONFIGURE 会被 RTL 以「活动期拒绝改配置」（错误码 10 / 返回 -16）挡回来，
整条初始化就失败。现在 `anlogic_pci_link_arm()` 在 CONFIGURE 之前先看 TX_STATUS，
busy/held/draining 就先 CANCEL 收回 IDLE 再配置（日志形如
`链路：FPGA 还停在 TX_STATUS=0x00000004（上一次没 ACK 就结束了），先 CANCEL 收回 IDLE。`）。

## 5. 复跑要点

- 位流是 SRAM 配置：**一掉电/复位就没了**，重烧后必须重启 RK3588 让它重新枚举；
- 驱动 probe 里会 `CONFIGURE + ARM` 一次，紧接着就等着被 ACK；用户态 `ACK` 时
  `ack_session` 给 0 表示「用驱动自己那份会话号」（`fix(drv): ACK 的 ack_session=0 ...`）；
- 活动期（busy/held/draining）写 `0x100/0x104` 会被 RTL 拒（`cfg_reject`、错误码 10），
  想换会话必须先 CANCEL；
- `csi_rx_10bit_unpack_checked` 在 B 路上位流实测可用（`CSI_DIAG_B` good=38、无 CRC/头错）。
