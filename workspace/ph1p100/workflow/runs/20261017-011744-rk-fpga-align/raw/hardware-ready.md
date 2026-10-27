# hardware-ready.md — T11.rk-align-raw 硬件就绪状态（本包不操作硬件）

## 1. 本包交付的位流候选

* 候选根：`workflow/runs/20261017-011744-rk-fpga-align/raw/candidate/prj`
  （TD 6.2.3 单会话 `00_all`：syn_1 + phy_1 + bit；G2 判据与具体 SHA 以
  `raw/candidate-manifest.json` 的 `build_artifacts` 与 `raw/g2/README.md` 为准）。
* 基线：T07 r3 候选（manifest `68f9f4d0…4275` / bit `0943cb36…8b0a`）的同交付树；
  T11 在其上新增正式 RAW10→R10F 通路（写者 + 顶层换接），**未放宽任何 SDC**。
* 本包**没有**下载位流、没有写 Flash、没有连接 RK；SRAM 板测留给 system 独占包
  （`T07.rk-align-board`）。

## 2. 与旧候选/回退的关系

* 旧主线、peer 参考库、`D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820` 与其它 run
  **未被修改**：回退 = 继续用 002820 既有 bit 或 T07 r3 候选 bit `0943cb36…8b0a`。
* 本包改动只出现在 `fpga/csi2/pcie_integration/`（写者/顶层/仿真）、`tools/pcie_integration/`
  与 `raw/`；整目录替换即可进退。`fpga/csi2/src/csi` 原源未动（差分参照仍在）。

## 3. 板测前必须由操作者确认/采集的条件（本包未做）

1. RK 侧真实设备 BDF、内核/驱动提交、`uname`、`getconf PAGE_SIZE`、PCIe MPS 协商值、
   DMA mask/IOMMU 状态。
2. 板卡 JTAG/UART 通道与独占窗口（本 run 只做过 PnP 枚举，未 JTAG 扫描）。
3. 主机收帧内存由**打过 RKA1 + T11 增量补丁**的驱动分配
   （`hdr_bytes=128`、`dma_bytes=2592768`、单槽；旧驱动/未打 T11 增量的解析会拒帧，
   fail closed 是设计）。

## 4. 板上诊断入口（与 T07 相同寄存器面 + T11 帧语义）

| 入口 | 用途 |
|---|---|
| 0x118/0x11C | EXT_MAGIC/EXT_VERSION：判断 FPGA 带 RKA1 扩展（旧读 DEAD_BEEF） |
| 0x114 | TX_STATUS：armed/busy/held/rejected/draining |
| 0xC0/0xC4/0xC8/0xCC | 已推帧数 / 推帧状态 / 最近错误码（0..4 旧码 + 5..11 新码）/ 最近帧 MWr 数 |
| 0x100/0x104 | 授权容量 / 会话号（staging；活动期写被拒并置错误码 10） |
| 0x120/0x124、0x128/0x12C | checked CSI A/B 路：{good,bad,hdr_err,crc_err} 低 8 位 + {last_lines,last_wc}（只读诊断） |
| 0x44 bit6/bit7/bit8 | 推帧模式 / 源选择（0 DDR）/ 相机 A/B |
| 0xA0~0xAC、0xE0~0xEC | 相机 A/B 的 R10F 写者发布握手：seq / base / status / **len（=dma_bytes=2,592,768）** |

**帧内容核对（RK 先用严格解析跑一遍，再谈像素）**：
`hdr_bytes=128` 起、`dma_bytes=2,592,768` 字节；头 128B 中 magic "R10F"、version 1.0、
format/codec=0、valid_bits=10、packing=0、width=1920/height=1080/stride=2400、
raw=payload=2,592,000、**flags=2（ROI 裁减）**、session=授权值、seq=门铃值；
三层 CRC（raw==payload 覆盖 packed 载荷；header 清 0x58..0x5B 后覆盖 128B）；
尾 640B 全 0。工具：`tools/pcie_integration/r10f_strict.py`（PC 侧）/ `r10f_check`
（RK 侧二进制，见 `raw/rk-change-list.md`）。

## 5. 已知限制 / 未验证（如实列出）

1. **几何与相位未板证**：W=1920/H=1080/X0=960/Y0=540、SKIP_ROWS=37、
   `SRC_BAYER_PHASE=0`（顶层默认）都是「按源实际 WC/行数标定后写进参数」的**占位**，
   未经本板实收证明；本包一切帧内容按 **synthetic/diagnostic** 对待，
   不得当真实相机几何/颜色证据。板测需读 0x120..0x12C 与 0xA0..0xAC 复核
   （实际 WC/行数/丢组），并据此回填参数后重跑 G1/G2。
2. **RAW10 打包正确性**：由 G1 真实 RTL TB（冻结向量 + 1080p 边界 + 负对照）证明；
   仿真只到包层输入（serdes PHY 由 `MIPI_PHY_SIM_STUB` 旁路）。
3. **时序余量薄**（沿用 T07）：相机字节域 setup 余量很小；**任何** RTL/约束改动都必须
   重跑 G2 并以「该域 setup ≥ 0」为回归门槛（本包 G2 结果见 `raw/g2/README.md`）。
4. 链路未起（link_up=0）时 ARM 被拒是**有意行为**；MPS 固定 128B。
5. `push_done`(0xC0) 只在「数据 + 门铃都发出」时 +1；timeout/CANCEL/错误一律不加。
6. 诊断计数跨域 2FF 采样（只读、人看）；`I_enable` 包尾撤销角落会少计 1 个
   crc_errors（T11 已补回归用例 `raw/g1/msim/p3_enable`，控制路径不受影响）。

## 6. 建议的板测顺序（后续 system 包）

1. 枚举 + BAR0 MAGIC + 0x118/0x11C 确认 RKA1；读 0xA0..0xAC/0xE0..0xEC 确认写者
   发布（seq>0、base 双缓冲交替、len=2,592,768、status 无 err 位）。
2. 驱动配置 CAP/SESSION + dst/db → ARM → 等 held（0x114.bit2）→
   `r10f_check`/严格解析（session/seq/三层 CRC/尾零）→ 匹配 ACK → 再 ARM。
3. 反例：错误 ACK / CANCEL / held 期间拔插；UART/JTAG 侧读 0xC8/0x114 复核。
4. 记录 100 帧实收 + 10min 短稳（G3/G4 留给对应任务；本包不声称）。
5. 用实收的 WC/行数与 0x120..0x12C 计数**复核/修正**几何参数；修正后重跑 G1/G2
   再作为正式发布候选。
