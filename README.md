> **当前阶段（2026-10-27）**：FPGA 板由队友持有。本地只做仿真、接口核对和证据整理，构建与实机联调由队友推进。
> **晚班更新**：T11 r2 的 64×48 G1 开发自检 PASS，但 r2 不是最终构建候选；export r0g 在完整帧路径上 blocked（32 B beat 字节序、×32/×128 地址单位冲突）。先读 [晚班状态](docs/STATUS_20261027_EVENING.md)，再读 [仿真状态、未验证项与队友接续顺序](docs/FPGA_SIM_ONLY_HANDOFF_20261027.md)；候选与原始证据见 [本轮交接包](handoff/fpga-sim-only-20261027/README.md)。
> [早期代码、队友材料与同步记录](docs/PROJECT_SYNC_20261027.md) 保留作为历史来源；其中活动 run 快照停留在各自同步时点。
> FPGA：[本原仓 main](https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga/tree/main)；RK：[驱动与应用原仓 main](https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver/tree/main)。
> 当前代码在 [rtl/](rtl/)；父工作区源码、文档、工作流与候选快照在 [workspace/ph1p100/](workspace/ph1p100/)，同名文件须按 SHA 区分。
> 队友从 [B 路真帧交接包](handoff/rk-a1u1-b18-20261026/README.md) 开始；配套 bit/CWC/BID 在 [artifacts/](artifacts/)。
> 集成进展看 [活动 run 快照](workspace/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/dispatch.json)；原 `D:\fpga\ph1p100` 活动 run 继续原地推进。
> 本次同步不代表整机验收通过；下方保留原工程说明，历史路径与结论请结合当前入口核对。

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

## 相机整帧（4K）→ DDR3（`rtl/ep_side/ddr/cam_ddr_writer.v` ×2 + `ddr_wr_arb.v`）

**为什么不能过片内帧缓存**：fb[] 装不下 4K，这不是算法问题而是容量问题。
器件 PH1P100SBG484 一共 **300 块 ERAM20K**（= 300×2560B = 768000B）：

| 分辨率 | 灰度字节 | ERAM20K 块数 | 结论 |
| --- | --- | --- | --- |
| 960×720 | 691200 | 270 | 快到顶 |
| 1920×1080 | 2073600 | 810 | 放不下 |
| 3840×2160（4K） | 8294400 | 3240 | 比整颗器件多一个数量级 |

传感器本来就跑 4K（`I_cam_mode=1`）——MIPI 链路、CSI-2 收包已经把每行 3840 个像素
收进来了。A/B 两路都**不过 fb[]**，直接写进 DDR3：

```
CSI-2 字节域 187.5MHz                       DDR 用户域 dhi_clk 100MHz
  A 路（w_a_byte_clk）：行/列计数 + 窗口/组字 → 异步 FIFO(34b×1024) → 攒 8 字拼 256bit ┐
  B 路（w_b_byte_clk）：同上                                                          ├→ ddr_wr_arb
                                                                                      ┘   → u_ddr3_mc_0 写口
                                                                                          （4KB 突发，双缓冲按帧号奇偶）
```

- **两路完全独立**：A/B 各一片 `cam_ddr_writer`，各在自己的字节时钟域，各有一对
  双缓冲基址、一组握手字、一组诊断。两路之间**没有任何信号二选一** —— 把两个字节
  时钟域的信号拿去做组合 mux（连时钟一起 mux）会在 TD 里报一堆跨域 hold，
  所以只在 DDR 域（单一时钟）做写口仲裁。
- **开关**：BAR0 `0x44 CTRL` 的 `bit5`（ddr_en）置 1 时两片同时 armed；没 armed 时
  它们连帧都不收（不会灌满 FIFO、也不会抢写口）。
- **写口仲裁**（`ddr_wr_arb.v`）：DDR3 IP 只有一个 AXI4 从口，两路按突发分时：
  被授权者 busy 期间不换手（一次突发不被拦腰截断），它一空闲就把端口让给 busy 的
  另一方。为什么不能沿用「两边都空闲才换手」——那样 grant 会冻在空闲的那一路上、
  把等端口的另一路锁死，死锁分析写在该文件头部。
  仲裁粒度取决于各 writer 的 `axi_busy` 口径，这一点很容易踩：
  **`axi_busy` 只能报「AXI 通道在飞」（`a_st != A_IDLE`），不能把整帧（`c_st != C_SYNC`）
  也算进去** —— 后者等于让某一路独占端口一整帧（4K 下 63ms），另一路的 FIFO 只有
  1024 组（≈31us）缓冲，必然大量丢组。板上实测过这个坑：两路各只发布一半帧
  （相机 15.7fps、发布 7.9fps，`0xA8/0xE8` 的 err_cnt 以同样速率上涨）。
- **帧几何**：`W/H/X0/Y0/SKIP_ROWS`，4K 取图 = `3840×2160 / X0=Y0=0 / SKIP_ROWS=37`
  （跳过 1 行 embedded + 36 行哑行）。硬约束：`W*H` 必须是 4KB 的整数倍
  （3840×2160 = 2025×4096 ✓），否则帧尾会出现半页突发。
  双缓冲基址：A = 1MB / 9MB，B = 17MB / 25MB（一帧 7.91MB，两块间隔 8MB，互不重叠）。
- **发布条件（不虚报）**：像素字数 = W*H/4、本帧确实见过 EOF、交给 AXI 的拍数 =
  NBEATS、所有 4KB 突发的 bresp 都是 OKAY、上一帧的回执已经取走 —— 全成立才更新
  握手字（A 路 `0xA0~0xAC`、B 路 `0xE0~0xEC`）。任一条不成立：不发布、
  `0xA8` 的 err_cnt+1，并从下一个 SOF 重新对齐（异常期可能连丢 1~2 帧，
  这是刻意取舍：不虚报 > 不丢帧）。
- **诊断**：`0xD0`（A）/ `0xD8`（B）= `{lines_per_frame[15:0], max_grp_per_line[15:0]}`。
  `max_grp_per_line` = 一帧内单行最多收到几组（裁剪前数）：4K 全幅应为
  3840/4 = **960**；若读到 966 说明传感器读出宽度是 3864，窗口 X0/W 要跟着改。
  `lines_per_frame` 应为 `SKIP_ROWS + 2160` = **2197**。
  另外 `0x80`/`0x84` 状态字的 bit15 是「直通通路丢过像素组/标记」，一眼看出有没有
  FIFO 满导致的丢帧。
- **IDELAY tap**：`0x9C`（A）/ `0xD4`（B）各配 `{manual_en, tap[5:0]}`，默认 46 + manual
  （自动扫描会落到 32，误码很高）。两路 PCB 走线不同，**必须分开配**。
- **推帧取哪一路**：`0x44` 的 `bit8`（`0` = A 路默认，`1` = B 路），决定推帧引擎读哪组
  握手字与哪个 DDR 基址（推帧引擎只有一份，所以主机侧同一时刻看到一路；两路同时推
  需要再加一份推帧引擎与 DDR 读口仲裁）。
- **每帧的两类诊断字**（定位「为什么这帧没发布」用，板上就是靠它们定的案）：
  `0xDC = {notack[15:0], stuck[15:0]}`、`0xF0 = {last_beats[15:0], last_wcnt[15:0]}`、
  `0xF4 = {24'd0, verdict_snap}`（bit0 p_bad / bit1 没见 EOF / bit2 字数不符 /
  bit3 拍数不符 / bit4 非 OKAY bresp / bit5 该帧 pub_ok）。`last_wcnt` 正常 = W*H/4
  的低 16 位（4K = 0x1F_A400 的低半 = 0xA400）。
- **⚠ 传感器每张图前面还发一小帧（embedded 数据）**：板上实测 FS 速率 15.7/s，而
  真正的图像帧只有 **7.85/s**（12.5MHz MCLK 下 4K 就是这个速率），两倍关系来自
  「每张图前带一帧极小帧（8 个字、没有 EOF）」。那一小帧会被判定为坏帧
  （`0xF4` 的 bit0/1/2/3 全置位）而不发布、并让 `0xA8` 的 err_cnt 每帧 +1 ——
  **这是预期行为、不是故障**：发布速率 = 真实图像帧率 = 7.85fps/路。
- **带宽**（4K 灰度 8bit，A/B 同时跑）：MIPI 4 lane×1.5Gbps = 750MB/s 峰值/路；
  DDR3 用户侧 100MHz×32B = 3.2GB/s；两路写 DDR ≈ 240MB/s；
  推帧到主机两路 ≈ 240MB/s（Gen2 ×1 热重配后理论约 500MB/s）。
- **测试台**：`sim_do/tb_cam_ddr_writer.v`（逐字节比对、双缓冲、AXI 规则、短板突发、
  坏帧不发布 + 恢复、诊断值；实例参数刻意取 W=20/H=44/BB=16，一次覆盖残拍与短板
  两条边角路径）、`sim_do/tb_ddr_wr_arb.v`（通道方向、未授权者被关住、busy 期间不换手、
  让出端口、以及「等端口时换手」的死锁形态）。

### 上板步骤（双路 4K）

```sh
# 1) 主机侧：驱动默认就按 4K 分配（3840x2160 = 8294400 字节/槽）
insmod anlogic_pci.ko
#    板上 /usr/lib/modules/$(uname -r)/updates/ 那份厂商版必须被覆盖掉，见 driver/README.md

# 2) 主机侧写 BAR0 寄存器（cam_grab/pci_bar 都能写；顺序无所谓，但建议一起写）
#    0x44 = bit5(ddr_en) | bit6(push_en)          = 0x60   （推 A 路）
#           再 | bit8 就是推 B 路                  = 0x160
./pci_bar 0 0x44 0x60
#    0xB0/0xB4 = 主机收帧缓冲的 DMA 地址、0xB8/0xBC = mailbox 页里的门铃字
#    （探测时驱动已经填好）
#    读回自检：0xA8 bit0=valid bit2=err；0xAC 与 0xEC 都应是 8294400；
#              0xD0/0xD8 应是 {2197, 960} 附近；0x9C/0xD4 看两路的 tap

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


## raw10-rka1 迁入说明（2026-10-18）

本分支（`codex/raw10-rka1`）把已验收的 RAW10/R10F/DDR/PCIe（RKA1 单帧 ARM/held/ACK/CANCEL）通路
逐文件并入本仓，保留原 PCIe 硬核、DDR AXI 接口、IP 与约束；不改时钟/SDC。

- 新增目录：`rtl/checked/`（包完整性检查/解包/CRC 树）、`sim/`（8 个正式 TB + 编译清单）、
  `tools/pcie_integration/`（仿真/TD/CRC/严格解析/清单工具）、`docs/protocol/rka1-r10f-v1/`
  （R10F v1 合同与样例镜像，SHA256SUMS）。
- 运行前设置：$env:MSIM_BIN=<modelsim_ase>\win32aloem；$env:TD_BIN=<TD_Release_2026.2>\bin（仅工具链安装位置；工程路径均相对检出根）。
- 仿真（ModelSim ASE，检出根运行，单 TB 建议 5 分钟内）：
  `powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_sim.ps1 -Tb tb_t11_r10f_e2e
   -OutDir build/g1/e2e -TbFiles tb/tb_t11_r10f_e2e.v -Defines MIPI_PHY_SIM_STUB`
  另外 7 个 TB：tb_cam_r10f_writer / tb_t11_csi_enable_corner / tb_ddr_frame_pusher_rka1 /
  tb_csi_integrity_diff / tb_csi_checked / tb_ep_bar_win_rka1 / tb_ddr_wr_arb_peer。
- 构建（TD 2026.2 单会话 syn+phy+bit，不下载/不写 Flash）：
  `powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_td.ps1 -Stage 00_all -OutDir <构建输出目录>`
- 离线检查：`python tools/pcie_integration/r10f_strict.py selftest`、
  `python tools/pcie_integration/r10f_tools_consistency.py --rust-src <RK侧 rka1.rs 路径>`。
- 几何/ROI/Bayer 相位仍为未板证占位（diagnostic）；板测与下载需另行授权。
