# MCLK 高频扫描与 DDR 双路结论（2026-10-27）

> **后续进展（2026-10-27 深夜，见 [arm-mask-20261027/RESULTS.md](../arm-mask-20261027/RESULTS.md)）**：
> A 单路在本轮的 27MHz 位流上已验证为 30.0–30.1 fps + strict OK（此前从未真正测过，
> `SINGLE_B_TEST=1` 把 A 的 arm 硬接成 0）；双路**仍未闭合**，但停滞计数器证明
> "AW 卡住/仲裁死锁"不成立（w_max=16、b_max=23、aw_max=0 拍），
> 且 `0x180`/`0xF0` 的 wcnt 只有 16 位，旧文中的"1022 组"可能是截断读数。
> 另外把 `BURST_GROUPS` 从 410 提到 820 会打坏单路（帧尾没到门槛就停发 → 丢 EOF）。

## 1. 结论

| MCLK | 4K 寄存器表 | 时钟源 | 链路 | sensor VSYNC | B writer | R10F |
|---:|---|---|---|---:|---:|---|
| 12.5 MHz | 24 MHz/1440 Mbps | 62.5/5 | lock | 15.6 fps | 15.6 fps（单路） | 基线 OK |
| 15.625 MHz | 24 MHz/1440 Mbps | 62.5/4 | lock | 19.6 fps | 19.5 fps | status 0x1B |
| 20.833 MHz | 24 MHz/1440 Mbps | 62.5/3 | lock | 26.1 fps | 0（只写 1022~26745/518400 组） | 失败 |
| 25 MHz | 27 MHz/891 Mbps | 50/2 干净 25 MHz | lock | 27.9 fps | 27.9 fps | **R10F_STRICT_OK** |
| **27 MHz** | **27 MHz/891 Mbps** | **62.5 分数分频 27 MHz** | **lock** | **30.1 fps** | **30.1 fps** | **R10F_STRICT_OK** |
| 25 MHz 双路 | 27 MHz/891 Mbps | 50/2 | lock | 28.2 fps | A/B 都 0 | 失败（FIFO 满/仲裁死锁） |

- **单路可用最高：27 MHz + 891/27 表 = 30.1 fps 全帧 1080p R10F**，帧 SHA256
  `bcd798eb3bd27d6cd3bfdfde47ea8776e3ddce8c7cabb9b58d1f2382cbc7cb75`，
  `r10f_strict.py check` → `R10F_STRICT_OK`。位流
  `mclk27_891_singleB.bit`，SHA256
  `0fb889dcaa5a68b740c796bf403a09fe4e8a3d428bf4be92c869eaf42678ff93`，
  时序 Setup WNS **+124 ps**、Hold +20 ps、0 违例。
- 25 MHz/891 也可用：27.9 fps，帧 SHA256
  `10641f18fde83ebc9c09050ab85a415d96d837abdbf1280b3c026b01697e27eb`，
  strict OK；位流 SHA256 `5690278888ddafcfc09e288c7ed6bee39971c86d940b34ce11372fd98ea89c05`，
  时序 Setup WNS **-51 ps**（8 个端点，窄裕量）。
- **20.833 MHz 不是 writer 参数问题**：sensor/CSI 已锁到 26.1 fps，但 writer 的 FIFO
  只进 1022 组就满，AXI 拍数 81024 走完、ROI 组数远不够，verdict=0x4（字数不符）。
  64 拍突发（410 组）和 4 KB 突发（500 组）都试过，结果一样；根因在 writer 的
  取数/AXI 握手与“提前收口”，不是单纯的 BURST_GROUPS。
- **25 MHz 双路仍不可用**：两片 writer 同时 arm 时 FIFO 都满在 1022 组，A/B 都 0 帧，
  0x178=0x7（grant=1、busy_a=busy_b=1）。这不是 DDR 带宽不够（两路满帧 144 MB/s，
  约 3.2 GB/s 的 4.5%），而是单 AXI 口 2→1 仲裁/写者 FSM 的并发死锁。

## 2. 27 MHz 配置（本次最高）

位流：`mclk27_891_singleB.bit`，5224023 B，SHA256
`0fb889dcaa5a68b740c796bf403a09fe4e8a3d428bf4be92c869eaf42678ff93`。
时序：Setup WNS **+124 ps**、Hold +20 ps、0 违例。

改动：
1. `rtl/ep_side/ph1p_pcie_ep_top.v`
   - 新增 `MCLK_SEL`（0=12.5、1=15.625、2=20.833、3=25 分数、4=31.25、5=25 干净、6=27 分数）。
   - 25 干净源：`sys_clk`(50 MHz) 先过 `PH1P_LOGIC_BUFG`，再二分频，50% 占空。
   - 27 MHz：62.5 MHz Bresenham 分数分频，INC=56623，
     平均翻转率 62.5×56623/65536=54.0 MHz ⇒ 27.0 MHz；最小脉宽 16 ns。
   - `SINGLE_B_TEST=1`（只 arm B）/ `DUAL_TEST=0`（两路同时 arm）。
   - 两路 CSI 的 `I_ref_clk` 由 `tl_clk_user`(62.5 MHz) 改为
     `w_sys_clk_bufg`(50 MHz)。25/27 MHz 时 byte clock 分别为 187.5/202.5 MHz，
     与 62.5 MHz 的整数比会混叠；50 MHz ref 下不混叠。
2. `rtl/ep_side/cam/ui_imx415_reg.v`：MODE=1 的 4K 分支从 24 MHz/1440 Mbps 组
   改为 27 MHz/891 Mbps 组（22 个值：HMAX=1100、VMAX=2250、SYS_MODE=0x05、
   INCKSEL3/4=C6/E7、INCKSEL6=0、INCKSEL7=1、TXCLKESC=0x06C0、
   TCLKPOST/PREPARE/TRAIL/ZERO、THSPREPARE/HSZERO/HSTRAIL/HSEXIT/TLPX）。
   脚本见 `apply_891_table.py`。
3. `rtl/ep_side/ddr/cam_r10f_writer.v`：`BURST_GROUPS 500 → 410`；
   顶层两片 writer `BURST_BEATS 128 → 64`（64 拍 = 409.6 组，攒满再发，避免
   mid-burst 等数据）。这是 25/27 MHz 单路能跑满帧率的必要条件之一。

## 3. 扫频过程

- 12.5 MHz：原基线，B 单路 15.6 fps；双路定时轮转每路 7.8 fps。
- 15.625 MHz：链路锁，sensor 19.6 fps，B writer 19.5 fps 全帧，status 0x1B。
- 20.833 MHz：链路锁（0x84=0xcfee15bf，lane_valid=0xf，bclk=1），sensor VSYNC
  26.1 fps；但 writer 的 FIFO 满在 1022 组，0x180=`0x3c80_03fe`/部分帧
  `0x3c80_6879`，0x184=0x4。64 拍修复位流 SHA256 `3f075185...`，同样失败。
  ⇒ 当前 writer 的上限在 19.5~26.1 fps 之间；不是相机/PHY 没锁。
- 25 MHz + 891/27 表：byte clock 103.1 MHz，clock lane 412.5 MHz，链路锁；
  sensor 27.9 fps，B writer 27.9 fps，0x180=`0x3c80_e900`、0x184=0x20，
  status 0x1B。严格 R10F 校验通过。
- 27 MHz + 891/27 表：byte clock 111.4 MHz，clock lane 445.5 MHz，链路锁；
  sensor 30.1 fps，B writer 30.1 fps，0x180=`0x3c80_e900`、0x184=0x20，
  status 0x1B。严格 R10F 校验通过。
- 25 MHz 双路：两片同时 arm，A/B 都 0 帧，0x180/0x184 都是 `...03fe`/0x4，
  0x178=0x7。需要重做 AXI 2→1 仲裁（按 ID/事务边界）或 writer 取数 FSM；
  “DDR 分两片”不是解。

## 4. DDR 能不能“分两片写”

硬件：PH1P100 的 `ddr3_mc_0` 只生成 **1 个 AXI4 slave 口**；`paxi_*` 是 MC 原生
用户口，与 AXI 是同一端口的两种包装（互斥 ifdef），不是第二个口。板载单 rank、
单 CS、32 bit 一组颗粒，没有第二通道。IP 参数没有“端口数”选项，重新生成也做不出
双 AXI 口。地址分区（A=1/9 MB、B=17/25 MB）已经在做，只是放数据的位置，不产生
第二条路径；bank 位在加密 MC 核内按地址生成，外部改不了“每路占一个 bank”。

因此：
- **“分两片/分两个口”在现有 IP 上不可行**；
- 两路满帧 2×72 MB/s=144 MB/s，只有 3.2 GB/s 的 4.5%，带宽不是瓶颈；
- 7.8 fps 是定时轮转的算术结果，不是 DDR 容量；
- 真正要修的是 **单口 2→1 的 AXI 事务/ID 仲裁与 writer 取数 FSM**；在修好之前，
  单路 27 MHz/30.1 fps 是可用上限。

## 5. 复跑

```sh
# 1) 建工作树并应用改动（基于 fpga HEAD 52f04919）
git -C fpga worktree add /tmp/fpga_mclk25 HEAD
cd /tmp/fpga_mclk25
git apply <本目录>/mclk25_top_writer.patch
python3 <本目录>/apply_891_table.py rtl/ep_side/cam/ui_imx415_reg.v

# 2) 选频率：27MHz 用 MCLK_SEL=6（默认）；25MHz 改 5
#    构建（输出 ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit）
/opt/anlogic/TD_Release_2026.2_NL/bin/td.sh build.tcl

# 3) 烧录（本机 JTAG，SRAM）后重启 RK
#    bw.sh 用临时 tcl 指向该 bit；必须看到 PRG-2014，且无 PRG-1000/9507
# 4) 板上：只 arm B，先不推帧，量 0xE0/0x8C
/root/tools/pci_bar 0 0x44 0x21
#    期望：0x8C 约 30.1/s，0xE0 约 30.1/s，0xE8=0x1B
# 5) 取一帧严格校验
/root/tools/pci_bar 0 0x44 0x161
/home/orangepi/newdrv/rka1_smoke --arm --baseline 0 --timeout 4000 --out /tmp/rka1_27.dma
python3 driver/tools/pcie_integration/r10f_strict.py check /tmp/rka1_27.dma --width 1920 --height 1080
#    期望：R10F_STRICT_OK
```

## 6. 未闭合

1. 双路 25/27 MHz 仍死锁；需要 AXI ID/事务级仲裁或 writer 取数 FSM 重构。
2. A 路单独跑 25/27 MHz 未测；历史 A 路 R10F 行计数 bug 仍在（A=1144/2192 行）。
3. 27 MHz 目前是 62.5 MHz 分数分频（平均 27.0 MHz、最小脉宽 16 ns）。若要严格
   50% 占空/零周期抖动，需参考工程那路 27 MHz PLL。
4. 25 MHz 单路位流 setup WNS -51 ps（8 个端点）；27 MHz 位流 +124 ps，0 违例。
5. `display-stream` 的 4K JPEG 仍是主机侧瓶颈，与本扫频无关。