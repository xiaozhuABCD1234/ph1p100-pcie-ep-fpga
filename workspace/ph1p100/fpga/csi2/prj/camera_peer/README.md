# f9p_ph1p100_imx415x2 — MLK-F9P + FEP-VID006-MIPI + 2× IMX415

米联客 MLK-F9P-CA05-PH1P100 开发板 + FEP-VID006-MIPI 子卡（2 路 MIPI-CSI）+ 2 颗索尼 IMX415。

- 器件：**PH1P100SBG484 / 速度 -3 / Family PH1**
- 工程入口：`fpga_prj.al`，顶层 `f9p_imx415x2_top`
- 工具：Anlogic TD 6.2.3（`td` / `td build.tcl`）
- 路线：**不依赖 TD 的 MIPI D-PHY IP**（它在 PH1P100 上只能走软实现且批处理不产 RTL），
  自己写软 PHY + 复用米联客 AFC03 IMX415 参考设计的 CSI-2 包层

---

## 一、现状（实测数据，2026-10-10）

| 环节 | 状态 |
|---|---|
| 两路 MIPI CSI-2 接收 | ✅ 两颗 IMX415 满速出流（4K@30，1.5Gbps×4 lane，70k 包/s） |
| 两路 I2C 配置 / XCLR / MCLK | ✅ 零 NACK，两路独立配置成功 |
| HDMI 输出链路（PLL+VTC+编码） | ✅ 上板出图（先是测试图，现接摄像头预览） |
| 摄像头实时预览 | ✅ 上板出图（960×540 灰度 ×2 放大到 1920×1080；更低延迟可选 320×180） |

```
编译: td build.tcl → PRJ-1424 : The implemented result of phy_1 is saved as best result.  BUILD DONE
      fpga_prj_Runs/best_result/fpga_prj.bit + fpga_prj_compress.bit
下载: bw.sh download_sram.tcl → PRG-2014 : Chip validation success: PH1P100   （-mode jtag = 只下 SRAM，不动 flash）

上板遥测（UART /dev/ttyUSB1 115200，每 0.5s 一行）：
  CNA =000F8901   A 口：帧事件 15、CSI-2 包 35073  → 30 fps、70146 包/s
  CNB =000F8901   B 口：完全相同（两颗同步出流）
  CKA =CKB =0xB2D  字节时钟均 ~187.5MHz（= clk lane 750MHz ÷ 4，即 1.5Gbps×4 lane）
  LNA = LNB =0xF   4 条 lane 全部字节对齐
  ERA = ERB =0     两路 I2C 零 NACK；cfgA/cfgB=1；tapA=tapB=46
```

30 fps × 2250 行/帧 ≈ 67.5k 行/s + 帧头帧尾 ≈ **70k 包/s**，与实测吻合 → 两条链路都是**完整满速流**。

### 上板踩出来的坑（都已在代码里修好）

1. **差分输入必须开端接**：`PH1P_LOGIC_IBUF_DIFF` 的 `DIFF_TERM` 默认 `"FALSE"`，TD 自带软 MIPI PHY
   也没写这个参数。开启 `DIFF_TERM("TRUE")` 后同一个 tap 上收包数从 743 → 4151（**5.6 倍**）。
2. **IDELAY 采样点要实测**：auto_delay_ctl 的判据（4 lane 同时字节对齐）在本板找不到窗口，
   回落到复位值 tap=32，而实测眼图中点在 **tap=45~47**（32 的收包率只有它的 1/9）。
   现在固定 `CAM_IDELAY_TAP = 6'd46`（`USE_MANUAL_TAP=0` 可切回自动扫描）。
3. **子卡 A 排那侧差分串了 100R，C 排才是 0R 直连**：走 A 排时每条 lane 都能找到 MIPI 同步头
   （LNA=0xF）但组装成包就废，只收到 ~12% 的包。改用**底板 FEP1B 的 C 排球号**后
   B 口从 586 包/s → 70146 包/s，A 口同样提满。
4. **传感器的 XCLR 释放 / I2C 启动要等久一点**：原来上电 1.3ms 就开始配置，B 口那颗 NACK
   → 一直不配置 → 不出流。改成 MCLK 先跑、**168ms** 后再放开 XCLR 并启动 I2C，两路都零 NACK。
5. **HDMI 预览不能靠"活动标志"在测试图/摄像头之间直接切换**：活动判据原本 1.4ms
   （`2^18` 字节时钟），正好落在 MIPI 帧消隐期内，于是每帧都在两个源之间闪一次，
   画面呈现"例程测试图 + 摄像头"叠加。改成 **89ms（`2^24`）** 后正常。
6. **帧缓存必须写成"简单写口"才会被判成 ERAM**：`if (r_wr_en) r_fb[addr] <= data;`
   这种单时钟单条形式，TD 会推断成 **ERAM20K 硬块**（960×540 = 203 块 / 上限 300，
   LUT6 只有百余个）；一旦写成带复位/多分支的复杂形式，就落成分布式 RAM
   （LUT），几万字节直接撑爆器件——实测 960×540 版本报 `slice 65664 > 25600`。
7. **单块大显存会把自己的选择器拖慢**：整帧 518KB 交给 TD 会映射成约 191 个 ERAM20K，
   块间的地址译码和读出多路选择各有 4 级 LUT + 长布线，在 137.5MHz（7.27ns）上压不住
   （实测写侧 4.99ns、读侧 7.02ns，SWNS −0.312ns）。**把帧缓存拆成 4 个 bank**（每个只装
   135 行 ≈ 51 块），每个 bank 内部选择器浅一级，读侧再做一个 4:1 选择即可收敛。
   教训：ERAM 够用不代表时序够用，块数一多，"选择"本身就成了关键路径。
8. **垂直抽降的"配对"不能按组递增行号**：原来每个源行组都给行号 +1，但两组才写一行，
   于是帧缓存里隔行是陈旧数据（画面有暗横条）。改成"只有真正写出去的那一行才换行号"。
   （这个 bug 在 320×180 版就存在，出图后才发现。）

### 还没做的

- [ ] **彩色**：当前存灰度（2×2 平均）。要彩色需存 RGB565/YUV，位数翻倍 → 得再降分辨率或分时。
- [ ] **画质**：现在只做 2 抽头水平 + 2 行垂直平均；要继续改善可换 4 抽头平均或加插值。
- [ ] 自动扫描（`auto_delay_ctl`）判据不够好；换板子要重新扫（每 2s 换 tap，读 CNA/CNB 找平台中点）。
- [ ] 输入/输出延迟约束（20 输入 / 12 输出未标），不影响功能。
- [ ] I2C 内部 `scl_clk` 网无时钟定义 → `check_timing` 剩 1 条 HIGH。

---

## 二、目录与工程规范

```
f9p_ph1p100_imx415x2/
├── fpga_prj.al                 TD 工程入口（器件 PH1P100SBG484 -3；文件清单即"源文件清单"）
├── build.tcl                   headless 编译（open_project → launch_runs → save_best_bits）
├── download_sram.tcl           只下 SRAM 的下载脚本（bw.sh download_sram.tcl）
├── README.md                   本文件：现状 / 接线 / 约定 / 坑
├── uisrc/
│   ├── 01_rtl/                 本工程原创 RTL
│   │   ├── f9p_imx415x2_top.v        顶层
│   │   ├── cam_preview.v             摄像头预览（抽降 + 帧缓存 + 放大）
│   │   └── dbg_uart.v uart_tx.v pulse2toggle.v clk_activity.v   上板遥测
│   ├── 02_sim/                 仿真（暂空）
│   ├── 03_ip/                  第三方/厂商代码，来源见 03_ip/README.md
│   │   ├── mipi_phy_ph1p/            软 D-PHY（原创）
│   │   ├── mipi_csi_2/               CSI-2 包层（米联客 AFC03）
│   │   ├── ui_imx415_cfg/            IMX415 寄存器表 + I2C（米联客）
│   │   ├── ui_pll/ vtc/ tpg/         HDMI 时钟/时序/测试图（米联客 25_rgb2hdmi_out）
│   │   └── alip/ui_HDMI_TX/          HDMI TX IP（含加密 RTL）
│   ├── 04_pin/                 约束
│   │   ├── fep_vid006_imx415.adc     管脚
│   │   └── timing.sdc                时序
│   ├── 05_boot/                上电加载文件（暂空）
│   └── 06_doc/                 备注文档
└── fpga_prj_Runs/              编译产物（.gitignore 排除，不入库）
```

**规范约定**

1. **目录分工**：原创 RTL 只进 `01_rtl/`；`03_ip/` 只放第三方/厂商代码，每个来源都登记在
   `03_ip/README.md`（来源、是否改写、许可状态）；约束只放 `04_pin/`。编译产物不入库。
2. **文件头**：每个 `.v` 开头写明 模块名 / 用途 / 所属工程+器件 / 数据流或接口 / 修订记录。
3. **命名**：端口沿用米联客约定（`I_` 输入、`O_` 输出、`IO_` 双向、`I_xxx_clk/rst_n`）；
   内部信号 `r_` 寄存器、`w_` 组合逻辑、`C_` 常量；参数全大写。
4. **不写魔数**：分辨率、抽降比、时钟频率等一律做成 `parameter`/`localparam`，
   派生值（如放大倍数 `SCALE = H_ACT/SW`、地址位宽）用函数自动推导，改一处即可换分辨率。
5. **不变量**：`cam_preview` 的三条约束写在模块 `initial` 里自检——
   `SW*DEC_CYC*4 == 3840`、`SH*DEC_LINE == 2160`、`H_ACT % SW == 0`（放大整数倍）。
   帧缓存写口保持"单时钟 + 单条 `if (we)`"形式，否则推断不出 ERAM（见坑 6）。
6. **注释写事实**：写"实测值/为什么"（如 tap=46 是实测眼图中点），不写"把 A 赋给 B"。
7. **git**：功能完成即提交，提交信息写清"做了什么 + 实测结论"；位流/日志/报告不入库。

---

## 三、接线（已上板实测确认）

**结论：两路 MIPI 的 lane/时钟都走底板 FEP1B 的 C 排**（子卡侧是 `MIPIA_FLANE*` / `MIPIB_FLANE*`
/ `MIPIA/B_CSI_FCLK*`），控制线分在两个连接器上。

| 信号 | 子卡引脚 | 子卡网络 | 底板球号 | 说明 |
|---|---|---|---|---|
| MIPI-A clk | C15 / C16 | MIPIA_CSI_FCLK_P/N | K18 / K19 | K18/K19 是时钟可用脚 |
| MIPI-A data0 | C6 / C7 | MIPIA_FLANE0_P/N | N20 / M20 | |
| MIPI-A data1 | C13 / C14 | MIPIA_FLANE1_P/N | K21 / K22 | |
| MIPI-A data2 | C8 / C9 | MIPIA_FLANE2_P/N | N18 / N19 | |
| MIPI-A data3 | C10 / C11 | MIPIA_FLANE3_P/N | M21 / L21 | |
| MIPI-B clk | C17 / C18 | MIPIB_CSI_FCLK_P/N | J19 / H19 | J19/H19 是时钟可用脚 |
| MIPI-B data0 | C26 / C27 | MIPIB_FLANE0_P/N | J22 / H22 | |
| MIPI-B data1 | C24 / C25 | MIPIB_FLANE1_P/N | G17 / G18 | |
| MIPI-B data2 | C22 / C23 | MIPIB_FLANE2_P/N | J20 / J21 | |
| MIPI-B data3 | C19 / C20 | MIPIB_FLANE3_P/N | L19 / L20 | |
| A 口 I2C | C4 / C5 | MIPIA_FSCL / FSDA | N22 / M22 | LVCMOS18 + 上拉 |
| A 口 MCLK | A5 | MIPIA_FCLK | L18 | LVCMOS18 |
| A 口 复位(FGPIO) | A4 | MIPIA_FGPIO | M18 | LVCMOS18 |
| B 口 I2C | A28 / A29 | MIPIB_FSCL / FSDA | H13 / G13 | LVCMOS18 + 上拉 |
| B 口 MCLK | C29 | MIPIB_FCLK | G20 | LVCMOS18 |
| B 口 复位(FGPIO) | C28 | MIPIB_FGPIO | H20 | LVCMOS18 |

HDMI：`HDMI_CLK_P/N`、`HDMI_D0~D2_P/N` 按底板 HDMI 定义；显示器实测 2560×1440@240Hz，
本工程输出 **1920×1080@60**（137.5MHz 像素时钟，显示器自动适配）。

系统时钟 `FPGA_50M_CLK = H4 (1.35V, SSTL135)`；LED = E21 / D21 / E22 / D22；
调试串口 `FPGA_UART_TX0 = R17`（板载 FT2232H 通道 B → `/dev/ttyUSB1` 115200）。

三条靠反解图纸/实测确认的规律：

1. 底板第二个 FEP 连接器的 C 排与第一个连接器的 B 排同网：**C(n) = B(n)**
   （实测 C4=N22=B4、C27=H22=B27、C28=H20=B28、C3=GND=B3）。
2. 子卡原理图 C/D 排的**网络名比引脚号错开一行**（标在 C(n) 旁的网络名实际在 C(n+1)）。
   反证链：MIPIA_FSCL 若在 C3（=GND）则 A 口 I2C 必然 NACK，实测 errA=0；同理 B 口按 C28/C29 取
   球号后 errB 才归零。
3. 子卡 A 排那侧差分串了 **100R**，C 排是 **0R** 直连 —— 所以必须用 C 排球号（见坑 3）。

---

## 四、为什么不用 TD 的 MIPI D-PHY IP

TD 6.2 自带 `anlogic.com:ip:MIPI_DPHY:1.0`（`ip/depot/MIPI_DPHY_1.0`），实测：

- `create_ip` 能建出 IP 并登记进 `.al`；`set_property` **能改参数**，但顺序与 Vivado 相反：
  **`set_property <值> <参数名> <IP对象>`**；`open_project` 之后必须先 `load_project_ips`。
- `generate_target` 在批处理里**不产出 RTL**（rc=1，目录里只有 xml/params）→ 例化它就报
  `HDL-8007 ERROR: xxx is a black box`。生成 IP RTL 是 GUI 动作，没有公开的 Tcl 文档。
- 在 PH1P100SBG484 上该 IP 只给 `Physical Type = LVDS`（硬 MIPI 只对 PH1P35/PH1P50 开放），
  即它自己也是"ISERDES + 动态 IDELAY"的软实现 —— 自己写一条等价路径反而更可控。

坑（已踩）：`03_ip` 被删空后再跑 `create_ip`，TD 会重写 `.al` 并**静默删掉已有 IP 的 `<IP_FILE>` 条目**
（表现为另一个 black box）——`.al` 必须留备份。

---

## 五、时序与时钟域

```
create_clock sys_clk50m          20.000ns   (板载 50M)
create_clock mipi_a/b_clk_hs      1.333ns   (实测 clk lane 750MHz DDR → 1.5Gbps/lane)
create_generated_clock *_byte_clk -divide_by 4   (PH1P_PHY_LCLK DIV=4 → 187.5MHz)
create_clock pclkx1              7.2727ns   (HDMI 像素时钟 137.5MHz)
create_clock pclkx5              1.4545ns   (HDMI OSERDES 5 倍串行 687.5MHz)
set_clock_groups -asynchronous -group {sys_clk50m} -group {mipi_a_*} -group {mipi_b_*} \
                                -group {pclkx1 pclkx5}
```

- generated clock 必须一起放进时钟组，否则跨域路径仍被分析：补之前 SWNS −4.396ns，补之后收敛。
- 两条时钟 lane 都落在时钟可用脚（K18/K19、J19/H19），`PHY-5019` 警告为 0。
- MIPI 字节域 → HDMI 像素域是**跨时钟域**，靠 `cam_preview` 里的帧缓存 + 2 级同步器过界
  （`ASYNC_REG`），不做数据握手。

---

## 六、编译 / 下载 / 调试

```
cd /home/xiaozhu/Projects/f9p_ph1p100_imx415x2
td build.tcl                                    # 编译出位流（无 GUI）
/opt/anlogic/TD_Release_2026.2_NL/bin/hwserver -r -s 5555 -f 12 -v -w 5556 -i 0 &
/opt/anlogic/TD_Release_2026.2_NL/bin/bw.sh download_sram.tcl    # -mode jtag = 只下 SRAM，不碰 flash
stty -F /dev/ttyUSB1 115200 cs8 -cstopb -parenb raw -echo; cat /dev/ttyUSB1   # 看状态
```

诊断永远看 `fpga_prj_Runs/<run>/run.log` 与 `final_timing.rpt`（控制台只报
`PRJ-8806 ERROR: Run … has exited unexpectedly`）。

子卡与模组资料：`/home/xiaozhu/Documents/HW-MLK-F9P-CA05-PH1P100_文档整理/`（含 `08_子卡硬件资料/`）。
