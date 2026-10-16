# 2026-embedded-chip-fpga-ph1p100

米联客 **MLK-F9P**（安路 Anlogic **PH1P100SBG484**）**PCIe Gen2×2 例程**。

原为 `02_fpga_start` 的 pll_test 骨架，现改为 PCIe 例程
（来源：`11_例程/11_3_高速接口与PCIe/12_pcie_gen2x2/`，原属 `02_peripheral_demo.zip`）。
旧骨架已挪到 `_old_pll_test_skeleton/`（不需要可直接删）。

教程：`06_入门与开发教程/03_米联客-安路FPGA开发板演示demo教程.pdf` 第 **144–148 页**（12 PCIE-EP 测试）。
官方参考设计：`doc/APUG081_安路科技PH1P系列FPGA PCIE RC对接EP参考设计.docx`。

## 目录结构

```
2026-embedded-chip-fpga-ph1p100/
├── prj/
│   ├── case_ep/                    # EP 模式工程（★ 对本开发板，器件 PH1P100SBG484）
│   │   ├── ph1p_pcie_ep_top.al               # ← TD 打开它
│   │   ├── ph1p_pcie_ep_top_compress.bit     # 预编译位流，可直接烧
│   │   ├── constraints/  (.adc / .sdc)
│   │   └── al_ip/        (pcie_ep_core / pcie_pll_ep / ram)
│   └── case_rc/                    # RC 模式工程（器件 PH1P100SBG676，属另一块 RC 参考板）
│       ├── ph1p_pcie_rc_top.al
│       ├── constraints/
│       └── al_ip/        (pcie_rc_core / pcie_pll_rc / Comp_inst)
├── rtl/
│   ├── ep_side/      # EP 侧 RTL（top / engine / int_handle / ubus_bridge）
│   ├── rc_side/      # RC 侧 RTL（含 pcie_prbs、si5344_5345）
│   └── common/       # 公共（PCIE_REG_TABLE、TLP_FMT_TYPE、ubus2pcie_apb、uart/…）
├── sim_do/           # 仿真：modelsim/sim.do、vcs/makefile、tb/
├── driver/
│   └── ph1p_pcie_driver/
│       ├── anlogic_pcie_drv/   # 内核驱动（.c/.h + Makefile）
│       └── anlogic_pcie_app/   # 用户态：pci_bar.c、devmem2
└── doc/              # APUG081 参考设计.docx、uart_cmd_file_pcie.txt
```

工程入口（.al）已把内部绝对路径改成当前目录；源文件用相对路径（`../../rtl/...`、`al_ip/...`），
已逐条核对，**引用文件 0 缺失**。

## 上手三步（对本开发板，EP 模式）

1. **烧 EP 位流 → 重启 PC → 建链**
   把 `prj/case_ep/ph1p_pcie_ep_top_compress.bit` 用 TD 下载到板子（或先重编再烧），
   板子插到主机的 PCIe 槽，重启主机，Linux 下 `lspci -s 01:00.0 -vvv` 应看到 **Gen2×2**，
   BAR0/2/4 各 1MB、BAR1 为 IO 256B。
   （烧录步骤见 `anlogic-td-fpga` 技能 / TD BitWriter：Cable = AL-LINK-FT(Local Host)，Local port=5555。）

2. **编译随板驱动**
   ```
   cd driver/ph1p_pcie_driver/anlogic_pcie_drv && make && insmod anlogic_pci.ko
   ```
   （`.ko` 是编译产物，未收录，需自行 `make`。中断测试只能用 `driver/int` 那份驱动。）

3. **用户态读写 BAR**
   ```
   cd ../anlogic_pcie_app && gcc pci_bar.c -o pci_bar
   ./pci_bar 0 0x0                 # 读 BAR0 偏移 0
   ./pci_bar 0 0x0 0x12345678      # 写
   ```

UART 命令脚本：`doc/uart_cmd_file_pcie.txt`（可经板载串口下发校验/测试命令）。

## 在 TD 里编译工程

- 打开 `prj/case_ep/ph1p_pcie_ep_top.al` → 一键编译（syn_1 + phy_1）→ Generate Bitstream。
- RC 工程 `prj/case_rc/ph1p_pcie_rc_top.al` 器件是 PH1P100SBG676，不是本板（F9P 是 SBG484）；
  它是 PCIe RC 侧参考设计，除非你有对接的 RC 板，否则用不到。
- 编译产物（`*_Runs/`、`.db`）未收录，首次打开需重新编译；`al_ip/` 内 IP 设计文件已保留，可再生成。

## 备注

- `driver.zip`、`driver/ph1p_pcie_driver.zip` 是原包自带的驱动打包文件，保留原样。
- 驱动目录里残留了部分内核模块构建中间物（`.mod`、`Module.symvers`、`modules.order` 等），
  重新 `make` 即可覆盖。
- 引脚约束在 `prj/*/constraints/*.adc`，时序在 `*.sdc`；引脚定义可查板卡的 `03_管脚定义表/PCIEx2-管脚定义表.xlsx`。

## 相机像素 → 帧缓存（`rtl/ep_side/img/cam_fb_writer.v`）

帧缓存（`img_frame_src.v` 里的 `fb[]`）此前只有测试图源能写。现在 IMX415（MIPI CSI-2，A 路）
收到的像素也能按**同样的布局**写进去，主机侧工具不用改：

- **写源选择**：BAR0 `0x44 CTRL` 新增 `bit4`（`0` = 测试图源，默认；`1` = 相机），读回同样在 `bit4`。
  原因是 `pcie_ep_engine.v` 的端口被冻结，该位借 `ctrl_pattern[1]` 送到顶层
  （寄存器语义不变：`[3:2]` 仍是 pattern 原值），详见 `ep_bar_win.v` 头部说明。
- **信号/时序约定**（逐条附文件:行）：`w_a_pixel/w_a_pixel_valid` 1 拍 = 1 组 = RAW10 的 4 像素；
  `w_a_vsync` = FS 1 拍脉冲（SOF）；`w_a_in_frame` 电平、下降沿 = FE（EOF）；
  `w_a_in_line` = 每个长包头 1 拍脉冲（行首，不是行内电平）。
- **数据通路**：字节时钟域（187.5MHz）按行/列裁剪左上角 640×480 并组字 →
  异步 FIFO（34bit × 512，格雷码指针）搬到 `tl_clk_user`（62.5MHz）→ 顺序写缓存；
  字 0..76799 全是像素，4 像素/32bit 字，低字节 = 最左像素，共 76800 字 = 307200 字节
  （帧号不占帧缓存：它就是 `0x4C FRAME_CNT` 这个寄存器）。
- 测试台 `sim_do/tb_cam_fb_writer.v`（逐字比对整帧 + FRAME_CNT + 丢包计数）。

## 片内帧缓存 → 板上 DDR3（`rtl/ep_side/ddr/ddr_frame_writer.v`）

帧缓存里那一帧现在能整帧搬进 DDR3，主机只读寄存器就知道去哪块内存取。

- **开关/触发**：BAR0 `0x44 CTRL` 新增 `bit5`（默认 0）。置 1 后，帧计数器一变
  （= 一帧已整帧写好）就搬一帧；`0x4C FRAME_CNT` 语义不变。
- **双缓冲**：顶层 `DDR_FRAME_BASE0`/`DDR_FRAME_BASE1` = 1MB / 1.5MB，按帧号奇偶交替，
  每帧 307200 字节（两块都 4KB 对齐，正好一个 AXI4 突发不跨 4KB 页）。
  主机正在读的那块不会被下一帧覆盖。
- **通路**：读 fb[] → 8 个字拼 256bit 一拍 → 异步 FIFO（格雷码指针，照 cam_fb_writer 的写法）
  → `dhi_clk`(100MHz) 域 → 每 4KB 一个 AXI4 突发（awlen=127、awsize=5、INCR、256bit 数据）。
  **fb 读口只有一份**，与主机读 0x60 的预取共用，仲裁在 `img_frame_src`：主机的预取一「脏」
  （刚换过 ptr）就把口还给主机，其余时间给搬运。
- **握手（只读）**：`0xA0 DDR_FRAME_SEQ`（单调递增，取自帧计数器）、
  `0xA4 DDR_BASE`、`0xA8 DDR_STATUS`（bit0 valid / bit1 busy / bit2 err / bit3 alive /
  bit4 cal_done / [31:16] err_cnt）、`0xAC DDR_LEN`。只有整帧的写响应全部收齐、
  且没有撕裂 / 没有非 OKAY 才发布序号 —— 主机看到序号变了，那一帧就是完整的。
- **测试台**：`sim_do/tb_ddr_frame_writer.v`（双缓冲 + 逐字节比对 + 撕裂用例 + AXI backpressure）。
  **本机没有仿真器，只写不跑。**

## 相机整帧（4K）直通 DDR3（`rtl/ep_side/ddr/cam_ddr_writer.v`）

**为什么不能沿用 fb[] 那条路**：片内帧缓存装不下 4K，这不是算法问题而是容量问题。
器件 PH1P100SBG484 一共 **300 块 ERAM20K**（= 300×2560B = 768000B，当前综合用掉 138 块）：

| 分辨率 | 灰度字节 | ERAM20K 块数 | 结论 |
| --- | --- | --- | --- |
| 640×480（现状） | 307200 | 120 | 放得下 |
| 960×720 | 691200 | 270 | 快到顶（剩余 162 块） |
| 1920×1080 | 2073600 | 810 | 放不下 |
| 3840×2160（4K） | 8294400 | 3240 | 比整颗器件多一个数量级 |

所以「超过 ~720p」必须离开 fb[]。传感器本来就在跑 4K（`I_cam_mode=1`）——MIPI 链路、
CSI-2 收包全都已经把每行 3840 个像素收进来了，`cam_fb_writer` 只是把窗口外的一律丢掉。
4K 直通就是把这一路**不再过 fb[]**，直接写进 DDR3：

```
CSI-2 字节域 187.5MHz                      DDR 用户域 dhi_clk 100MHz
  行/列计数 + 窗口裁剪 + 4 像素组 1 字
    → 异步 FIFO（34bit × 1024，格雷码指针）→ 攒 8 个字拼 256bit
    → 每 4KB 一个 AXI4 突发写 DDR3（双缓冲，按帧号奇偶）
```

- **开关**：BAR0 `0x44 CTRL` 新增 `bit3`（默认 0，读回同样在 bit3）。
  `bit3=1` 且 `bit4=1`（写源=相机）且 `bit5=1`（ddr_en）时，4K 直通生效；
  这三位同时成立才叫「想用」。
- **换手**：两条通路（fb[]→DDR3 的老路 / CSI-2→DDR3 的新路）共用一个 DDR AXI 写口，
  由 `ddr_wr_mux` 二选一，**只在两边都没有突发在飞时**换手（busy 是各自状态机给的），
  所以不存在「把一拍拦腰截断」。落到哪个值由 `sel_eff` 给出，`0xA0~0xAC` 那组握手字、
  推帧引擎的数据源都跟着它走。
- **帧几何**：`W/H/X0/Y0/SKIP_ROWS` 与 `cam_fb_writer` 同一套语义（4K 取图时
  `SKIP_ROWS=37` = 1 行 embedded + 36 行哑行）。默认就是**整幅 3840×2160**
  （`CAMDDR_X0/Y0=0`）。硬约束：`W*H` 必须是 4KB 的整数倍
  （3840×2160 = 2025×4096 ✓），这样帧尾不会出现半页突发。
  两个 DDR 块基址 1MB / 9MB，都在 512MB（AXI 29 位地址）之内、互不重叠。
- **发布条件（不虚报）**：像素字数 = W*H/4、本帧确实见过 EOF、交给 AXI 的拍数 =
  NBEATS、所有 4KB 突发的 bresp 都是 OKAY、上一帧的回执已经取走 —— 全成立才把
  `0xA0 DDR_FRAME_SEQ` +1 并更新 `0xA4/0xA8/0xAC`。任一条不成立：不发布、
  `0xA8` 的 err_cnt+1，然后自动从下一个 SOF 重新对齐（异常恢复期可能连丢 1~2 帧，
  这是刻意取舍：不虚报 > 不丢帧）。
- **上板先量几何**：`0xD0 CAM_DDR_DIAG = {lines_per_frame[15:0], max_grp_per_line[15:0]}`
  （借 `cam_stat[255:224]` 那 32bit，不新增端口）。
  - `max_grp_per_line` = 一帧内**单行最多收到几组**（裁剪前数）：4K 全幅应为
    3840/4 = **960**；若读到 966（=3864/4）说明传感器读出宽度是 3864 而不是 3840，
    窗口 X0/W 要跟着改。
  - `lines_per_frame` = 一帧行数（含 embedded/哑行）：4K 应为 `SKIP_ROWS + 2160` = **2197**。
  另外 `0x80` 相机状态字的 bit15 现在是「直通通路丢过像素组/标记」（原来保留 0），
  一眼就能看出是不是 FIFO 满导致的丢帧。
- **带宽核算**（4K 下都不是瓶颈，14.5fps 现状 / 若以后修到 30fps）：
  MIPI 4 lane × 1.5Gbps = 750MB/s 峰值；DDR3 用户侧 100MHz × 32B = 3.2GB/s；
  PCIe Gen2×2 理论 1GB/s（MWr 载荷 128B，开销约 13%）；
  4K 灰度 8bit：14.5fps = 120MB/s、30fps = 249MB/s；
  帧内写入的字域排空能力 100M 字/s（= 400MB/s）> 30fps 的 250MB/s。
- **测试台**：`sim_do/tb_cam_ddr_writer.v`（**已用 iverilog 跑通**，`ALL PASS`）：
  逐字节比对 DDR 内容、双缓冲、AXI 规则（awsize/INCR/4KB/wlast/末拍 wstrb 裁字节）、
  短板突发、坏帧不发布 + err_cnt、坏帧后恢复、诊断值。
  实例化参数刻意选成 W=20/H=44/BB=16：`W*H/4 = 220` 不是 8 的整数倍 ⇒ 末拍是**残拍**，
  `NBEATS=28` 不是 `BURST_BEATS=16` 的整数倍 ⇒ 最后一突发是**短板**，一次覆盖两条边角路径。

### 上板步骤（4K）

```sh
# 1) 主机侧：驱动按 4K 分配收帧缓冲（默认是 640x480）
insmod anlogic_pci.ko frame_width=3840 frame_height=2160   # frame_slot_bytes=0 ⇒ 8294400
#    板上 /usr/lib/modules/$(uname -r)/updates/ 那份厂商版必须被覆盖掉，见 driver/README.md

# 2) 主机侧写 BAR0 寄存器（cam_grab/pci_bar 都能写；顺序无所谓，但建议一起写）
#    0x44 = bit4(cam_sel) | bit5(ddr_en) | bit6(push_en) | bit3(cam_ddr_sel)
#          = 0x78
./pci_bar 0 0x44 0x78
#    0xB0/0xB4 = 主机收帧缓冲的 DMA 地址（探测时驱动已经填好 = 槽像素区起点）
#    0xB8/0xBC = mailbox 页里的门铃字（同上）
#    读回自检：0xD0 应是 {行数, 单行组数}；0xA8 bit0=valid bit2=err；0xAC=8294400

# 3) 板子上取帧
./frame_grab --info                 # 看几何：应为 3840x2160
./frame_grab -o f.pgm               # 8.29MB PGM
```

### 已知限制 / 还没做的

- **帧率仍是 ~14.5fps**：那是传感器 MCLK 12.5MHz + INCKSEL 决定的（25MHz 在本板锁不住，
  见顶层相机段的实测记录）。要 30fps 得先把 MCLK/INCKSEL 调到 24~27MHz 那一档并重新验证
  链路锁定，与本次改动无关。
- **只传高 8 位**（RAW10 >>2，1 字节 1 像素）。想要 RAW10/16bit 需要另开一条 16bit 通路，
  DDR/PCIe 带宽翻倍（4K 30fps 16bit ≈ 498MB/s，Gen2×2 就紧张了）。
- **CPU 侧 JPEG 是另一个瓶颈**：`display/` 那个推流工具在 RK3588 上单线程编 4K JPEG
  只能几 fps，`--auto --bayer gbrg` 更慢；要流畅推流得先加一级降采样。

## 提交信息规范

`<类型>(<范围>): <做了什么>`，首行不超过 78 字符；正文写清"为什么、怎么做的"，一行一句。

- 类型：`feat` / `fix` / `refactor` / `docs` / `build` / `chore` / `test` / `perf`
- 范围：本仓库的模块名，如 `rtl` / `constraints` / `ip` / `doc`
- 示例：`fix(rtl): 修正 IMX415 主时钟分频，恢复相机链路锁定`
- 由 `commit-msg` 钩子校验，不合规直接拒绝
