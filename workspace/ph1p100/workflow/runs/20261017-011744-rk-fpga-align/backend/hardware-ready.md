# hardware-ready.md — T07.rk-align-backend 硬件就绪状态（本包不操作硬件）

## 1. 本包交付的位流候选

* 唯一候选位流：`backend/candidate/prj/ph1p_pcie_integration_Runs/phy_1/...`（`save_best_bits` 输出，
  真实路径与 SHA256 见 `candidate-manifest.json` 的 `build_artifacts`）。
  round2 冻结候选：SHA256 `0943cb36feeb873decc6ea5aae1c2777b3ab4881ebe2954b43bee040ceb38b0a`（5,224,023 B，
  与 `best_result/` 同 SHA）；G2 判据达标（setup SWNS +0.107 ns / STNS 0.000 / 0 违例端点、hold +0.020 ns、
  资源在器件内、`Routed` 同一最终 DB），见 `g2/README.md` §3.5/§4。
* 同一实现数据库/时序报告：`.../phy_1/*`（TD 工程内的最终 DB 与 STA 报告）；
  综合阶段报告在 `.../syn_1/*`。**G2 身份 = 这些文件 + 清单里的 SHA**；三测试必须用同一 manifest。
* 本包**没有**下载位流、没有写 Flash、没有连接 RK；SRAM 板测留给后续 system 独占包。

## 2. 与旧候选/回退的关系

* 旧主线、peer 参考库、`D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820` 与其它 run **未被修改**：
  回退 = 继续用 002820 的既有 bit（不覆盖、不重置、不清理）。
* 新候选只出现在 `fpga/csi2/pcie_integration/` + 本 run `backend/`；整目录替换即可进退。
* 板载 DDR 容量授权：`DDR_CAP_BYTES = 0x1000_0000`（256MB），依据匹配生成 IP 的
  `al_ip/ddr3_mc_0/.params_ddr3_mc_0.txt`（DDR3 x16 / 2048Mb / 1 CS）——**不是** 29 位 AXI 地址宽。

## 3. 板测前必须由操作者确认/采集的条件（本包未做）

1. RK 侧真实设备 BDF、内核/驱动提交、`uname`、`getconf PAGE_SIZE`、PCIe MPS 协商值、DMA mask/IOMMU 状态。
2. 板卡 JTAG/UART 通道与独占窗口；当前 run 内只做过 PnP 枚举（FTDI VID1604/PID6042），**未** JTAG 扫描。
3. 主机侧收帧内存由**打过 RKA1 补丁**的驱动分配（新 ABI：hdr_bytes=128、dma_bytes=2592768、单槽）。
   **未打补丁的旧驱动不能驱动本候选**（fail closed 是设计，不是故障）。

## 4. 板上诊断入口（给板测用）

| 入口 | 用途 |
|---|---|
| 0x118/0x11C | EXT_MAGIC/EXT_VERSION：判断 FPGA 是否带 RKA1 扩展（旧读 DEAD_BEEF） |
| 0x114 | TX_STATUS：armed/busy/held/rejected/draining |
| 0xC0/0xC4/0xC8/0xCC | 已推帧数 / 推帧状态 / 最近错误码（0..4 旧码 + 5..11 新码）/ 最近帧 MWr 数 |
| 0x100/0x104 | 授权容量 / 会话号（staging；活动期写会被拒并置错误码 10） |
| 0x120/0x124、0x128/0x12C | checked CSI A/B 路：{good,bad,hdr_err,crc_err} 低 8 位 + {last_lines,last_wc}（只读诊断） |
| 0x44 bit6/bit7/bit8 | 推帧模式 / 源选择（0 DDR）/ 相机 A/B |
| 0x80..0x98 | 原相机状态字（lane_valid、cfg_done、in_frame/in_line、tap 等） |

## 5. 已知限制 / 未验证（如实列出）

0. **G2 时序已达（round2）**：round2 冻结候选（checked 包层本域重构后重建）实测
   setup **SWNS +0.107 ns / STNS 0.000（0 违例端点）**、hold ✓ +0.020 ns、资源 ✓
   （LUT6 19.13%、ERAM 134/300）、`Routed` 且位流与同次 DB/报告同源
   （`0943CB36…8B0A`）；经 187.5 MHz 相机字节域的最差路径余量只有 **+0.107 ns**（如实登记，
   见 `g2/README.md` §3.6）——上板测试本身**不**验证该余量，但后续任何 RTL/约束改动都必须重跑 G2
   （把"相机字节域 setup ≥ 0"当回归门槛）。行为等价由差分 oracle 证明（`change-report.md` §8.2）；
   本包**未放宽** SDC/判据、未改前提。
1. 相机真实几何与相位、RAW10 打包、R10F 头与三段 CRC 未在本包实现（T11）；本包推帧源是
   DDR 诊断帧或 ERAM 合成帧，**不声称真实相机 RAW10 通路已跑通**。
2. 仿真只到包层输入（serdes PHY 由 `MIPI_PHY_SIM_STUB` 旁路）；PHY/对齐原语的实现正确性由
   TD 综合/STA 与后续板测覆盖。
3. MPS 固定 128B 载荷；链路未起（link_up=0）时 ARM 被拒是**有意的**（不假定协商结果）。
4. peer `pcie_ep_engine.v` 的既有 `x3` 断言（原文件 630 行附近）在 CANCEL 深排空时可能触发，
   表现为对 `tl_tx_*` 的 $display；该断言不改行为，但板测/仿真看到它属**已知现象**。
5. 诊断计数跨域用 2FF 采样（只读、人看），瞬时可能出现不一致值；不参与任何控制。
6. `push_done`（0xC0）只在「数据 + 门铃都发出」时 +1；timeout/CANCEL/错误一律不加（板上勿把它当“发过就好”）。

## 6. 建议的板测顺序（后续 system 包）

1. 枚举 + BAR0 MAGIC + 0x118/0x11C 确认 RKA1；
2. 驱动配置 CAP/SESSION + dst/db（授权窗口内）→ ARM → 等 held → 用户态严格解析（framework: rka1.rs::r10f）
   → 匹配 ACK → 再 ARM 下一帧；
3. 反例：错误 ACK / CANCEL / 链路拔插后旧门铃不认；UART/JTAG 侧读 0xC8 与 0x114 复核；
4. 记录 100 帧实收 + 10min 短稳（G3/G4 留给对应任务，不在本包声称）。
