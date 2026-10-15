# PH1P100 PCIe-EP 工程 只读代码质量审查报告

审查对象：``
取证方式：只读（读文件 / grep / wc / diff 厂商原版与参考工程 / 读已有综合与时序报告）。未修改、未创建任何文件，未运行 build.tcl、download_sram.tcl，未连接板卡。
本次可用到的“额外证据源”（都是仓库里已有的产物，非我生成）：
- `log/cam16.log`（14:15 分析日志，等于根目录 `td_20261015_141539.log`）
- `prj/ph1p_pcie_ep_top_Runs/syn_1/td_20261015_123428.log`（12:34 版含 elaborate 阶段告警）
- `prj/ph1p_pcie_ep_top_Runs/{syn_1/gate.qor,gate.area,phy_1/route.qor,final_timing.rpt,route_clock_utilization.txt}`
- 厂商原版 `…/12_pcie_gen2x2/rtl/ep_side/pcie_ep_engine.v`、参考工程 `…/f9p_ph1p100_imx415x2/`

---

## 一、结论摘要

**代码“能编、能收敛、能出位流”，但不能进入“摄像头出图”这一阶段。** 依据：本次改动确实把历史上最危险的一类错误（隐式 1 位网络）基本清干净了——`log/cam16.log:114` 全工程只剩 1 条 undeclared（`iic_busy`），而 12:34 那版还有 `HDL-7225 CRITICAL-WARNING`（`td_20261015_123428.log:100-101`）+ `HDL-5314` 无驱动（同文件 `:199-201`）；`w_cam_a_stat/w_cam_b_stat` 我逐位手算确认**恰好 32 位**且与注释一致；帧缓存也确实推成了 ERAM（`gate.area:88`）。**但有两件事必须先解决，否则下一阶段一定会做无用功**：① `ph1p_pcie_ep_top.v:763-771` 那个“平均 2.5 分频”实测是 **12.5MHz / 40-60% 占空**（注释和参考工程都是 25MHz / 50%），IMX415 的 INCK 直接错一倍；② 片内 ERAM 已被 640×480 测试帧占掉 **123/300 块（41%）**（`gate.area:31-32`、`:88`），而 IMX415 是 4K——把真实像素按现方案接进片内帧缓存**在物理上不可能**。此外 CSI-2 的**两个字节时钟完全没有时序约束**（`ph1p_pcie_case_ep.sdc:1-4` 只约束了 sys_clk 与 tl_clk_user），STA 覆盖率只有 **71.84%**（`final_timing.rpt:10`），收包路径 `u_word_align/u_packet/u_gear_box` 在整份时序报告里**出现 0 次**——相机链路的“时序通过”目前是无证据的。

**能否进入下一阶段：图像/寄存器通路可以继续（NVMe 级别的接口自测已在硬件上跑通），摄像头出图阶段建议先做 3 件事**：改 MCLK 并示波器实测、给字节时钟加约束、定下“不做整帧片内缓存”的数据方案。

---

## 二、问题清单

### 2.0 先逐条核对你给的 10 条（我读代码后的结论，不含推测）

| # | 你的描述 | 核实结论 |
|---|---|---|
| 1 | 42 条 HDL-1007 + 4 条 HDL-5373 | **数量需修正**：`log/cam*.log` 14 份**累计 44 条**（涉及 5 个信号名），另 `log/build4_20261015_115513.log` 有 11 条；**最新 `log/cam16.log` 只剩 1 条**（`iic_busy`，`cam16.log:114`）。5373 最新为 4 条（`cam16.log:96-98,115`），与你说的一致。真正会造成“256 位接成 1 位”的不是 1007 本身，而是 **HDL-7225 CRITICAL-WARNING**（`td_20261015_123428.log:100-101`）——12:34 版 `w_cam_stat`/`w_uart_rxd_unused` 就是这样被拆成两个网。**当前已修**（声明前移到 `ph1p_pcie_ep_top.v:86,88`）。剩余同类风险见 §2.4-L2/§四。 |
| 2 | `ic_busy`/`iic_busy` 拼写 | **属实且是厂商遗留，但不在主路径上**：`ui_cfg_imx415.v:55` 声明 `ic_busy` 只被 `:59` 的 `assign O_dbg_busy = ic_busy;` 使用（**无驱动**）；I2C 忙信号实际落在 `:221` 的隐式网 `iic_busy` 上，被状态机 `:190` 正常使用。所以 **I2C 配置功能没坏**，坏的是我们新加、并已暴露到主机的诊断位 `0x98[0]`（见 §2.2-H4）。 |
| 3 | 跨时钟域只做 1~2 级同步 | **部分属实、部分是高估**：`in_line/in_frame` 是**0 级**（`ph1p_pcie_ep_top.v:951-952` 直接进 256 位状态字）；`lane_valid` 是 1 级（`:928-929`）；**`tap` 和 I2C 进度不是跨时钟域**——`O_delay_tap/O_auto_delay_done` 来自 `auto_delay_ctl`… 见 §四“未验证”第 4 条的边界说明，而 `ui_cfg_imx415` 的 `I_clk` 就是 `tl_clk_user`（`ph1p_pcie_ep_top.v:848`），所以 `:887-888` 那句注释“跨到 tl 域”是错的。**toggle 计数不可靠的是 pixel_valid**（不是 vsync），见 §2.3-M2。 |
| 4 | 状态字被高位截断 | **现在恰好 32 位**，我按位核对了字段：`[31:26]=6'b110011`、`[25]=SDA`、`[24]=SCL`、`[23]=r_rst_n`、`[22]=r_rst_n_slow`、`[21:16]=tap`、`[15:11]=0`、`[10]=pv_seen`、`[9]=in_line`、`[8]=in_frame`、`[7]=auto_done`、`[6]=bus_err`、`[5]=cfg_done`、`[4:1]=lane`、`[0]=bclk_seen`（`ph1p_pcie_ep_top.v:950-952`），**与 `:945-949` 注释完全自洽**，`w_cam_stat` 合计 256 位（`ph1p_pcie_ep_top.v:956-958`）。唯一不一致：`6'b110011` 这个“签名”没有任何注释。 |
| 5 | 0x9C 语义冲突 | **不成立**：`0x9C` 是 `cam_tap_cfg` 的写（`ep_bar_win.v:152`）与读回（`:227`），同一个寄存器，无冲突。**真正的问题是寄存器表登记不全**（见 §2.3-M6）。 |
| 6 | 硬编码散落 | **属实**，320×240 改回去要动 4 个文件 7 处（见 §2.3-M5 与 §三）。 |
| 7 | `img_regs.v` 死代码 | **属实**：`.al:22-29` 仍标注 `UsedInSyn=true`，但全工程**只有 `sim_do/tb_img.v:37` 例化它**，顶层没有 → 白占综合时间，且它自带的 `PTR_MASK` 回绕是数学错的（§2.3-M7）。`IMG_PTRMSK`(`:71`)、`CAM_IDELAY_TAP`(`:782`)、`USE_MANUAL_TAP`(`:781`) **均只有声明、零引用**（grep 计数=1）。 |
| 8 | MCLK 分频器 | **实际输出 12.5MHz、占空 40%/60%，不是 25MHz**——逐拍推演见 §2.1-B1。 |
| 9 | 无仿真器、靠一次性 C 程序 | **属实且影响被低估**：`tb_img.v` 不但没跑过，它测的是**已废弃的 `img_regs`**，而且 `tb_img.v:168` 那条“PTR 回绕到 0”的断言按 `img_regs.v:143` 算**必然 FAIL**。仓库里只有 `driver/.../anlogic_pcie_app/pci_bar.c`（单寄存器读写），做帧校验的那个 C 程序**不在仓库**（见 §2.3-M7）。 |
| 10 | 命名/魔数/注释不符/编码 | **属实**，清单见 §2.4-L1/L2/L3。改动标记：厂商文件里我们的新增段落有 4 处 `本移植` 标记（`pcie_ep_engine.v:50,323`、`ph1p_pcie_ep_top.v:73,440,739`），但**引擎文件里被删掉的 `ram u_pcie_rx_eram` 只留了一行注释**，且我们新加的 `O_dbg_idx/O_dbg_busy` 在 `ui_cfg_imx415.v:57-59` 没有标记。 |

---

### 2.1 阻断

**B1｜MCLK 分频器输出 12.5MHz（文档/参考工程 25MHz），占空 40/60 —— 传感器参考时钟错一倍**
`rtl/ep_side/ph1p_pcie_ep_top.v:763-771`
逐拍推演（`tl_clk_user`=62.5MHz，由 `phy_1/final_timing.rpt:41` 的 `C-Period 16.000ns / 62.500MHz` 与 `td_20261015_123428.log:159` 的 `PCIE_CFG_TL_CLK_FREQ=9'b0111111`(=63) 双向确认）：

```
拍  本拍 acc  动作                输出
 0     0      acc<=2
 1     2      acc<=4
 2     4      acc<=6
 3     6      >=5 → acc<=3  翻   ← 第 4 拍翻转
 4     3      acc<=5
 5     5      >=5 → acc<=2  翻   ← 间隔 2 拍
 6     2      acc<=4
 7     4      acc<=6
 8     6      >=5 → acc<=3  翻   ← 间隔 3 拍
 9     3      5
10     5      >=5 → acc<=2  翻   ← 间隔 2 拍
```
翻转间隔恒为 2、3、2、3…（平均 2.5 拍）→ **半周期=2.5 拍 → 周期=5 拍 → f=62.5/5=12.5MHz**，且高电平 2 拍 / 低电平 3 拍（或反之）→ 占空 40%/60%。
而注释 `:743`（`MCLK_DIV = 2; // 50MHz/2 = 25MHz`）、`:762`（“62.5MHz → 25MHz”）都写 25MHz；参考工程是真的 `/2` 且 50% 占空：`f9p_ph1p100_imx415x2/uisrc/01_rtl/f9p_imx415x2_top.v:31`、`:93-98`（`wire w_mclk = (MCLK_DIV <= 1) ? sys_clk50m : (r_mclk_div < (MCLK_DIV/2));`）。
后果：IMX415 的 INCK 直接减半，`ui_imx415_reg.v` 里那张从 25MHz INCK 工程搬来的寄存器表（含内部 PLL/链路速率设置）与实际输入不匹配；“cfg_done 为 1”也不能证明出图（该 FSM 根本不看 bus_error，见 H5）。
建议改法（任选，改完必须示波器实测 L18/G20）：
(a) 只要“文档=代码”就先改注释并确认 12.5MHz 在模组 INCK 允许范围内（IMX415 规格约 6~27MHz，12.5 在范围内但寄存器表需重新对）；
(b) 要 25MHz 就把阈值判断改成每 1.25 拍翻转（`acc <= acc + 4`，阈值 5），代价是 1/2 拍交替的更大抖动，占空仍是 40/60；
(c) 最稳：用现成 PLL 资源单出一路 24/27MHz 给 MCLK，`/2.5` 这种分数分频本来就不该用累加器凑。

**B2｜片内帧缓存已经吃掉 41% 的 ERAM，4K 真像素接入不可行 —— 架构性阻断**
证据：`prj/ph1p_pcie_ep_top_Runs/syn_1/ph1p_pcie_ep_top_gate.area:31-32`（`#eram 123 out of 300 41.00%` / `#eram20k 123`）、同文件 `:88`（`u_img_frame_src | img_frame_src | … | eram 123`）——**全部 123 块都在我们新写的 `img_frame_src` 里**，也就是 `img_frame_src.v:64` 的 `reg [31:0] fb [0:WORDS-1]`。
算一下：ERAM20K=20Kbit=2.5KB，640×480=300KB → 120 块（和实测 123 吻合）。整器件 300 块 = **750KB**。IMX415 4K 灰度单帧 3840×2160 = **8.3MB，是整器件 ERAM 的 11 倍**；1080p 也要 2MB。
注意 `img_frame_src.v:15-21` 的模块头注释自己就写了“320x240 ≈ 30 块；再往上（640x480 = 120 块）要先按参考工程做法把帧缓存拆 bank，否则块间的读多路选择会成为关键路径”，而顶层 `ph1p_pcie_ep_top.v:67-68,574-575` 传进去的就是 640×480 —— **代码已经走到了注释警告的那一步**（好消息：时序没出问题，见 §四）。
建议：下一阶段方案先定型，三选一——(1) 传感器侧降到 1080p/720p/抽点，片内只留“行缓冲+行内多路”而不是整帧；(2) 走 PCIe 边收边写主机内存（当前 `ep_bar_win` 的 PTR 窗口本来就是这个思路）；(3) 外挂 DDR（本板 ERAM 之外的 DDR 控制器/引脚需单独确认）。**不要**按现在的写法把 4K 帧往 `fb` 里塞。

---

### 2.2 高

**H1｜`ep_bar_win` 把 TLP 地址只当成 3DW 头，4DW（64 位 BAR）访问解码全错**
`rtl/ep_side/img/ep_bar_win.v:96-100`：`tlp_addr = rx_data_ff[191:160]`。3DW 头时 `[191:160]` 是完整的 32 位地址（对）；4DW 头时 `[191:160]` 是 **address[63:32]**，低 32 位在 `[159:128]`——于是任何 64 位 BAR 访问都会令 `tlp_addr[11:0]=0`，写不进任何寄存器、读回 `default: 32'hDEAD_BEEF`（`:228`）。
而本设计 **BAR2/BAR4 就是 64 位 BAR**：`td_20261015_123428.log:158` 明确 `PCIE_CFG_PF0_BAR2_64BIT=1'b1, PCIE_CFG_PF0_BAR2_MASK=32'b…00000100`，BAR4 同理且是 MSI-X 表。同一个模块在 `:97` 已经为 4DW **数据**做了分支（`is_4dw ? rx_data_ff[127:96] : rx_data_ff[159:128]`），说明作者知道 4DW，只是漏了地址字段。
现状没爆是因为主机程序只用 BAR0（32 位 BAR → 3DW）：`README.md:52`、`driver/ph1p_pcie_driver/anlogic_pcie_app/pci_bar.c:83`（bar_id 由命令行给，**允许传 2/4**）→ 谁传 2 就会得到“读回 DEADBEEF”的怪现象。
建议：`tlp_addr = is_4dw ? {rx_data_ff[191:160], rx_data_ff[159:128]} : rx_data_ff[191:160]`；同时建议顺手用 `tl_rx_bardec/tl_rx_mchit` 判 BAR 命中，别再让所有 Memory BAR 共享一个窗口（这正是当初要修的老毛病，见 `ep_bar_win.v:3-10`）。

**H2｜完成包长度不夹到 4dw，主机读 >16 字节会静默拿到重复/垃圾数据**
`ep_bar_win.v:101`（`tlp_len = (|rx_data_ff[233:224]) ? {1'b0,…} : 11'd1`）、`:108`（`rd_dw_cnt` 夹到 4）、`:163-168`（PTR 只前进 ≤16B）、`:238`（恒定只给 4 个 dw：`{p_dw0,p_dw1,p_dw2,p_dw3,128'd0}`）。
但完成包的 **length 字段用的是请求长度**：`pcie_ep_engine.v:586`（最多 1024dw）、`:498`（`tl_mr_len_ff[9:0] // length(dw)`）、`:502`（byte count 也按 1024dw 算），而多拍数据来自 `:641` 的 `{mrdata_rd_data_ff[95:0], mrdata_rd_data[255:96]}` —— 对 `ep_bar_win` 而言就是**同一批 4 个 dw 反复**。
后果：一次 64 字节 MRd（例如驱动用 `memcpy_fromio`、或将来做 DMA 描述符）会返回一个“声称 16dw、实际内容重复”的完成包 → **RC 侧静默数据错误或 Malformed TLP**，不报错、不 graceful 失败。
最小代价改法：(1) 驱动/文档层面**强制 0x60 只发 ≤4dw 读**（当前一次性 C 程序就是 `readl` 单拍，所以没暴露）；(2) 若要在 RTL 里兜住，只能在 `pcie_ep_engine.v` 的 `TL_TX_ACK_MEMR` 里把 `tl_mr_len_ff` 夹到 4（并把 status 置 UR）——那是厂商代码，改动要单独评估。
附带一条同类边界值不一致（低危）：长度字段=0 时 `ep_bar_win.v:101` 当 1dw，而 `pcie_ep_engine.v:586` 当 1024dw；长度=0x400 时 `[233:224]` 低 10 位全 0，两边又分别看成 1dw/1024dw。

**H3｜两个 MIPI 字节时钟没有任何时序约束，CSI-2 收包路径 0 条被分析**
- 约束文件全文只有 4 行：`prj/case_ep/constraints/ph1p_pcie_case_ep.sdc:1`（`create_clock sys_clk 20ns`）、`:3`（`derive_clocks`）、`:4`（把 PLL 输出改名 `tl_clk_user`）。**没有** `create_clock/create_generated_clock` 给 `w_a_byte_clk/w_b_byte_clk`，也**没有** `set_clock_groups -asynchronous` 给那堆 CDC 路径。
- `phy_1/route_clock_utilization.txt` 里 `gclk_1 = u_csi_a/u_rx_phy/u_hs_byte_clk_bufg.clkout（w_a_byte_clk，扇出 399）`、`gclk_2 = u_csi_b/…（388）` 两行的 **constraint period 列是空的**（只有 `gclk_0 = tl_clk_user 16.000`）。
- `phy_1/final_timing.rpt:10`：`STA coverage: 71.84%`；`:31-42` 的 Clock Summary 只有 `clk0 tl_clk_user / clk1 sys_clk` 两个时钟。
- 决定性证据：整份 `final_timing.rpt` 中 `u_word_align / u_packet / u_gear_box / u_byte_align` 出现次数 **各为 0**（`grep -c`），而这些正是字节时钟域的核心逻辑（`mipi_csi2_rx_ph1p.v:96-142`）。
- 另外值得警惕：报告里少数进了图的字节域寄存器被标成 “triggered by clock tl_clk_user {…period=16.000000}”（例：`final_timing.rpt:78` 的 `u_csi_b/u_rx_phy/u_auto_delay_ctl/add2_syn_102`，而该模块时钟是 `I_byte_clk`：`rx_phy_ph1p.v:162-165`、`auto_delay_ctl.v:72`）。也就是说这一域要么**没分析**（28.16% 未覆盖），要么**按 62.5MHz 分析**（实际字节时钟高数倍，乐观若干倍）。两种情况下“时序通过”都不能作为相机链路的依据。
建议：SDC 里补 `create_clock`（或用 `create_generated_clock` 从 LCLK/BUFG 派生）+ `set_clock_groups -asynchronous -group {tl_clk_user} -group {w_a_byte_clk} -group {w_b_byte_clk}`；重跑后确认 `STA coverage` 与报告里出现 `u_word_align/u_packet`。

**H4｜`ic_busy`/`iic_busy` 拼写错误被我们接到了 PCIe 寄存器上 → 主机看到的 I2C 忙位永远是 0**
`rtl/ep_side/cam/ui_cfg_imx415.v:55` 声明 `wire ic_busy;`，`:59` `assign O_dbg_busy = ic_busy;` —— 这个网**没有任何驱动**；真正的忙信号从 `:221` `.O_iic_busy (iic_busy)` 落到隐式网，只被状态机 `:190` 使用。
我们的新增代码把它引到了主机：`ui_cfg_imx415.v:58-59`（我们加的端口/assign）→ `ph1p_pcie_ep_top.v:862`（`O_dbg_busy`→`w_a_cfg_busy`）→ `:887-888`（`w_a_i2c_busy`）→ `:956`（`w_cam_stat` 的 `[192]`）→ `ep_bar_win.v:226`（`0x98` bit0）。
后果：**I2C 功能正常**（主路径走隐式网），但 `0x98[0]` 恒定 0（TD 会把无驱动网常量化/优化），调试时“I2C 不忙”是假象；这也是本次唯一残留的 HDL-1007（`log/cam16.log:114`）。另外我们新加的 `O_dbg_idx`/`assign O_dbg_idx = reg_index`（`:58`）写在了 `reg [7:0] reg_index`（`:75`）**之前**，就是 4 条 HDL-5373 中的一条（`cam16.log:115`）。
建议：把 `:55` 的 `ic_busy` 删除、`:59` 改成 `assign O_dbg_busy = iic_busy;`，并把 `wire ic_busy;`/`assign O_dbg_idx` 移到 `reg_index` 声明之后（一行改动、消掉 1 条 1007 + 1 条 5373）。

**H5｜相机复位链与 PCIe 复位无关、配置只做一次且失败不重试、`cfg_done` 不能证明成功**
- `ph1p_pcie_ep_top.v:746-755`（`r_pwr_cnt2/r_rst_n_slow`）、`:758-759`（`r_rst_n`）、`:763-771`（MCLK 相关寄存器）**全部没有复位端口**，只靠 `= 23'd0` 这类初值；而 `tl_rst_user`/`power_on_rst_dly` 只复位 PCIe/图像侧（`:596-700`、`ep_bar_win` 的 `rst` 就是 `tl_rst_user`，`pcie_ep_engine.v:333`）。结果：**PCIe 热复位后主机写过的 tap 配置被清回默认（`ep_bar_win.v:123`），但相机块不重启**，两边状态不对称。
- XCLR 释放时刻 = 8388607/62.5MHz = **134ms**（`:749` 的 `23'h7FFFFF`），注释 `:745` 写 “~168ms”——那是 50MHz 下的数字，说明这段是从参考工程整体搬过来的（参考 `f9p…top.v:79` 也是“~168ms”）。
- `r_rst_n` 在约 16µs 就释放（`:759`，`>23'd1000`），比 XCLR 早三个数量级；这一条**不算 bug**，因为内部真正放行是 `csi_rx_clock_det`（`csi_rx_clock_det.v:87` 的 `r_reset_out <= (r_count_value >= 2)`，需要字节时钟真的跳起来）——但它意味着 `PH1P_LOGIC_IBUF_DIFF.interm_disable = ~I_rx_en`（`rx_phy_ph1p.v:68`）从 16µs 起就使能差分端接，属于“能用但没想清楚”的时序。
- 配置 FSM **完全不检查 `O_iic_bus_error`**：`ui_cfg_imx415.v:143-195` 里只有 `reg_index==REG_SIZE` 就置 `O_cfg_done`（`:163-164`），NACK 也会“成功”；且没有任何重试路径（`:171`/`:178` 复位 `reg_index<=0` 只为重配，不是错误恢复）。
后果：一旦上电那一刻传感器没准备好（MCLK 错、供电时序、I2C 上拉），**这一版只能靠重新配置 FPGA 才能救**，而主机看到的 `cfg_done=1` 是假象。
建议：给相机加一个主机可控的软复位位（`0x44` 还有 bit4 以上空闲）+ 让 FSM 检查 `O_iic_bus_error` 并在 error 时回到 `reg_index=0` 重试 N 次；同时把 `r_pwr_cnt2` 的复位接 `power_on_rst_dly`。

---

### 2.3 中

**M1｜`in_line/in_frame` 零级跨域、`lane_valid/tap` 一级同步**
`ph1p_pcie_ep_top.v:951-952`（`w_a_in_line, w_a_in_frame` 直接拼进 `w_cam_a_stat`）、`:928-929`（`s_a_lane <= w_a_lane_valid;` 4 位直接打一拍）。源域是字节时钟（`mipi_csi2_rx_ph1p.v:118-133`：`O_vsync/O_in_frame/O_in_line/O_lane_valid` 都出自字节域 `u_packet`），目的域是 `tl_clk_user`，中间**没有 2 级同步器**，而且状态字最终进的是 PCIe 完成包寄存器（`ep_bar_win.v:220-227` → `:233-238`）。
风险评估：`in_line` 翻转率约 2×2160×30 ≈ 130kHz、`in_frame`/`vsync` 各 ~30~60Hz，过渡率低 → 实际 MTBF 很大，**不至于像计数器那样出错**；但这是“把异步单 bit 直接送进 flop”，属于该修不该赌的类别。
建议：`w_a_in_line/in_frame/lane_valid/tap` 各加 2 级同步寄存器（`tap` 严格说是同域，加上也无害），并在 SDC 里对这些路径留 `set_max_delay` 或 `set_clock_groups` 说明。

**M2｜pixel_valid 用 toggle 计数在 4K 下必然混叠，`r_a_pix/r_b_pix` 不可信**
`ph1p_pcie_ep_top.v:924-925`（`a_pv_tgl` 在 `:901` 每来一个 `w_a_pixel_valid` 翻转一次）+ `:937-938`（在 62.5MHz 域用 `s_a_pv[2]^s_a_pv[1]` 数边沿）。
算数：IMX415 4K 档 ≈ 3840×2160×30 ≈ **249 Mpix/s** → toggle 频率 ≈ 124.5MHz > 62.5MHz 采样时钟 → 奈奎斯特不足，计数**必然漏数且不确定**；1080p30（62 Mpix/s → 31MHz toggle）也只是“2 个采样点/半周期”的临界状态。vsync（30Hz）和字节时钟活性（`clk_activity` 分频 2^15，`clk_activity.v:22-26`）都是可靠的。
后果：`0x90/0x94`（`ep_bar_win.v:224-225`）读到的是“有点活动”，不能当像素计数/帧完整性判据；若拿它当“相机是否正常”的验收指标会误判。
建议：把 `[10] 收到过像素` 改成一次性 sticky（已经如此）并在注释里明确 `r_a_pix` 只是“粗略活动指示”；要真计数就用字节域计数器 + 定期同步多 bit（或直接在字节域算完再搬）。

**M3｜DATA 窗口的完成包 Lower Address/地址语义不符合 PCIe 规范（工程上可用，但属已知偏差）**
`ep_bar_win.v:105`（`req_is_data = … tlp_addr[11:0]==12'h60`）、`:139`（`memrd_addr_lo <= tlp_addr[6:0]`）、`:109`+`:233`（数据来自 `ptr` 指向的 `pf0` 而不是请求地址 0x60 的内容）。
规范要求完成包的 Lower Address 与首个返回字节的地址一致；这里返回的是“窗口指针处”的数据，与地址 0x60 无关。当前主机驱动不校验、非预取 BAR 不会被缓存，所以能用；但 PCIe 分析仪/一致性测试会报，且**任何“读两次同地址应得同值”的假设都会失效**（第二次读 PTR 已 +4）。
建议：在 `ep_bar_win.v:33-45` 的表里把 0x60 明确写成 “FIFO 窗口，读后 PTR 自动 +4，不保证同地址同值”；若要规范合规，改成把真实地址映射到帧缓存地址上（`addr - 0x1000` 之类），而不是用 PTR 游标。

**M4｜只解 12 位地址 → 64KB BAR0 内每 4KB 出现 16 份别名（旧“回卷”缺陷的一种残留）**
`ep_bar_win.v:105,146,204` 全部只比较 `[11:0]`；而 BAR0 实际是 **64KB**（`td_20261015_123428.log:158`：`PCIE_CFG_PF0_BAR0_MASK=32'b11111111111100000000000000000000`）。于是 BAR0+0x1060 也会命中 DATA 窗口。不是功能故障，但会让“访问了未映射地址”失去保护，也让 README 的 BAR 尺寸描述失准（见 L3）。
建议：地址比较加上 `tlp_addr[15:12]==0`（或按 BAR0 实际尺寸 64KB 全解码），未命中回 `DEADBEEF`。

**M5｜`CTRL[3:2] pattern` 是一个“有寄存器、无效果”的控制位**
写入口 `ep_bar_win.v:148-150`（`ctrl_pattern <= tlp_dw_s[3:2]`）、读回 `:205`、注释 `:30` 写 “bit1 trigger(写1出单帧), [3:2] pattern”，顶层也连到了引擎（`ph1p_pcie_ep_top.v:443` → `img_pattern`）——但 `img_frame_src` 只接 `W/H/IDLE_CYCLE`（`ph1p_pcie_ep_top.v:574-576`），**`PIX_ADD` 参数未连接**（`img_frame_src.v:24` 默认 8'h00），而“图样选择”只可能落在 `PIX_ADD` 或 `:96` 的像素公式上 → 主机写 pattern 观察不到任何变化。
建议：要么把 `pattern` 接到 `PIX_ADD`/图样 mux（并在 `:30` 注明各档含义），要么把这个字段从寄存器表和 `img_pattern` 线里删掉（现在是死线，grep 计数=2 即“声明+端口”）。

**M6｜寄存器表登记不全 + MAGIC 读回与注释不符**
- 注释表 `ep_bar_win.v:33-45` 最后一行是 `0x70 PF0`，但实际解码到 `0x9C`：`0x74 last_wr`（写 `:154`/读 `:217`）、`0x78 fb_raddr`（`:218`）、`0x7C dbg_rd_idx`（`:219`）、`0x80~0x98 cam_stat`（`:220-226`）、`0x9C tap`（`:152/:227`）。**这些正是主机调试相机要用的地址，却没进表**（顶层注释 `ph1p_pcie_ep_top.v:739-741` 也把范围写成 `0x80~0x94`，实际到 0x98）。
- `:26` 表里写 `0x40 MAGIC R 0x50434946`，参数 `:36` 也是 `32'h5043_4946`，但读通路整字做了字节翻转（`:233` `p_dw0 = bswap32(…)`、`:238`），主机实际读回 `0x46494350`（内存字节 “PCIF”）。寄存器读写同走一个 bswap 所以自洽、图像通路的字节序也只能靠硬件实测（见 §四）；但**注释表里的“期望值”是错的**，下次拿它做自检会误判。
建议：补全 0x74~0x9C 的表项（每行写清 R/W 与字段位置），把 0x40 的期望值改成实际会读到的值或改成 `bswap32(MAGIC)` 的写法让注释与代码一致。

**M7｜可测试性：废弃模块还在综合、仿真文件测的是废弃模块且断言必错、帧校验程序不在仓库**
- `prj/ph1p_pcie_ep_top.al:22-29`：`img_regs.v` 仍 `UsedInSyn=true`；全工程仅 `sim_do/tb_img.v:37` 例化它。
- `sim_do/tb_img.v:2-3` 自称 iverilog 冒烟测试，但本机 **没有 iv erilog/verilator/vsim**（`command -v` 全部为空）→ 从未跑过；它测的 UBUS 通路是 `img_regs`，**没有一行覆盖真正在用的 `ep_bar_win`**（TLP 地址解码、bswap、4dw 夹取、完成包组包全无覆盖）。
- 就算装上 iverilog，`tb_img.v:168` 的 `chk("PTR 回绕到 0", v, 32'd0)` 也会 FAIL：`img_regs.v:143` 用的是 `(rd_ptr + 4) & PTR_MASK`，`PTR_MASK=0x12BFC`（`:34`），`0x12C00 & 0x12BFC = 0x12800 ≠ 0`；顺带这个“掩码”对 76800（非 2 的幂）本来就是错的（例如写 `PTR=0x1000` 会被清成 0）。对比之下 `ep_bar_win.v:79` 用比较回绕并注释“用比较回绕，别用掩码”，说明这个坑已经被踩过。
- 仓库里能跑的只有 `driver/ph1p_pcie_driver/anlogic_pcie_app/pci_bar.c`（`bar_id offset [data]` 单寄存器收发）；做帧搬运/校验的那个“一次性 C 程序”**不在仓库**，`README.md` 也没写它的用法 → **目前无法复现已记录的任何图像结果**。
建议：删掉 `.al` 里的 `img_regs.v`（同时删 `sim_do/tb_img.v` 或把它改成面向 `ep_bar_win` 的 TLP 级 tb），并把帧校验程序与期望数据结构（帧号在字 0、`pix=x+y+frame` 公式）落进仓库。

**M8｜hold 余量只剩 21ps，而且最差 hold 路径就在本次新写的帧缓存写口**
`phy_1/route.qor`：`Setup WNS 5290 / Hold WNS 21`（ps，0 违规端点）；`final_timing.rpt:821-828`：
```
Slack 0.021ns  Begin u_img_frame_src/add5_syn_105.clk → End u_img_frame_src/fb_syn_285.addra[9]
Data Path Delay 0.259ns  Max Fanout 123
```
第二差（0.024ns）是 `fb_wr_data[18]`(fanout 21) → ERAM 写数据（`:1410-1430` 附近）。也就是说整器件最脆的 hold 就落在 `img_frame_src.v:71` 的简单写口上。0.021ns 远小于该路径 0.100ns 的 clock uncertainty，换个版本重编/改一行就很可能翻成负值。
建议：给 `fb_wr_addr/fb_wr_data` 加一级流水或显式 `max_fanout`，或者把 640×480 拆 bank（顺便解决 B2 的读多路）；至少在 CI 里把 `route.qor` 的 Hold WNS 做成门限。

---

### 2.4 低

**L1｜编码与换行混排（GBK/UTF-8、CRLF/LF）**
`file` 结果：`rtl/ep_side/cam/` 下 **7 个文件不是合法 UTF-8**（`csi_rx_10bit_unpack.v / csi_rx_byte_align.v / csi_rx_clock_det.v / csi_rx_packet_handler.v / csi_rx_word_align.v / csi_rx_word_gear_box.v / ui_cfg_imx415.v / ui_imx415_reg.v`，`iconv -f UTF-8` 报错；`ui_cfg_imx415.v` 还是 “CRLF + NEL(0x85) line terminators”），而我们新写的文件（`ep_bar_win.v/img_frame_src.v/img_regs.v/tb_img.v/top`）是 UTF-8，`.al:4` 却声明 `TD_Encoding=UTF-8`；`ph1p_pcie_ep_top.v` 内部 **14 行 CRLF + 949 行 LF** 混排。TD 目前能吃（`cam16.log:118` 34 个文件全部 analyze 成功），但任何一次“用 UTF-8 编辑器打开并保存”都会破坏 GBK 注释，而 GBK 双字节的第二个字节可能是 `0x5C`（`\`）——**一旦落在行尾会把下一行代码吞进注释**（历史上这类事故的经典形态）。
建议：把 cam 目录按 GBK 原样保留并加 `.gitattributes`/说明，或统一转成 UTF-8 后**成批只跑一次 diff 校验**；新增代码统一 LF。

**L2｜死参数/死信号清单（grep 计数=“仅声明”或“写了没人读”）**
`ph1p_pcie_ep_top.v:71` `IMG_PTRMSK`（注释已写“保留（未用）”）｜`:743` `MCLK_DIV`｜`:781` `USE_MANUAL_TAP`｜`:782` `CAM_IDELAY_TAP`（tap 默认值实际来自 `ep_bar_win.v:123` 的 `7'b1_101110`，两处 46 重复定义）｜`:876-877` `r_syscnt`（**“诊断 sys_clk 是否在跳”的计数器被优化掉了**：`final_timing.rpt:41-42` 里 `sys_clk` 扇出=1，说明 32 个 flop 全没了；同时 `sys_clk` 只进 PLL）｜`:887-888` `w_a_i2c_idx`（写了不读）｜`:792-794` `w_a_pixel/w_b_pixel/w_a_pkt_done/w_b_pkt_done/w_a_sync_wait/w_b_sync_wait`（寄存器照建但无人使用，80 位像素总线接了就断）。
建议：要么接进状态字（例如把 `pkt_done` 计数、`sync_wait` 暴露给主机——它们才是调 CSI-2 最有用的信号），要么删除，避免下次读代码时误以为“已经接进通路”。

**L3｜注释与实际行为不符清单（可直接照着改）**
- `img_frame_src.v:23` “125MHz 下 1e6 ≈ 8ms” → 实际 `tl_clk_user=62.5MHz`，1e6 ≈ **16ms**（`:23` 与 `ph1p_pcie_ep_top.v:576` 的 `IDLE_CYCLE(1000000)`）。
- `img_frame_src.v:15-21` “320x240 = 76,800B ≈ 30 块 ERAM20K；640x480 要先拆 bank” → 实际构建是 **640×480**（`ph1p_pcie_ep_top.v:67-68`、`td_20261015_123428.log:170` 的 `img_frame_src(W=640,H=480)`、`:88` 的 123 块）。
- `ph1p_pcie_ep_top.v:743,745,762` 三处 “50MHz / 168ms / 25MHz” → 实际 62.5MHz / 134ms / 12.5MHz。
- `ph1p_pcie_ep_top.v:739-741` “0x80~0x94” → 实际 0x80~0x98（`ep_bar_win.v:220-226`）。
- `ep_bar_win.v:15-20` “完成包第 0 个 dw 必须落在 `mrdata_rd_data[127:96]`，第 k 个在 `[96+32k +: 32]`” → 与代码 `:238` 相反。我按引擎的 valid 掩码逐位核对过（`pcie_ep_engine.v:508-509` 的 payload 字段、`:621,630-631` 的 `mrdata_cycle_valid_32bit`、`8'hE0/8'hF0` 两个无数据完成包样例）：**代码是对的（`p_dw0` 在 `[255:224]`），注释是错的**。这条最危险，将来有人“按注释修正代码”就会把图像打乱。
- `prj/case_ep/constraints/ph1p_pcie_case_ep.adc:33` “cam_a_xclr_n 占用原串口 rxd 的 P16” → 代码是 `M18`（`:54`），参考工程也是 M18（`f9p_ph1p100_imx415x2/uisrc/04_pin/fep_vid006_imx415.adc:60`），**代码对、注释错**（M18 是 AP115 板那组被注释掉的 rxd，`:2-14`）。
- `rtl/ep_side/cam/clk_activity.v:2-5` 与 `ph1p_pcie_ep_top.v:945-949` 的 bit0 “字节时钟在跑” → 实际是 sticky“曾经跑到过”（`ph1p_pcie_ep_top.v:939` 只置位不清零），**时钟中途停掉看不出来**。

**L4｜遗留告警（都会掩盖真问题，建议清零）**
`log/cam16.log:96-98,115` 四条 HDL-5373（`ep_bar_win.v:107,108` 的 `rd_addr32/rd_len_dw`、`ui_cfg_imx415.v:58` 的 `reg_index`）；`td_20261015_123428.log:185` `cas_i` 未连（`rx_phy_ph1p.v:125`）、`:196-197` 两条 HDL-5007 位宽不符（`ui_cfg_imx415.v:227` `REG_INDEX` 实 8 形 9、`:228` `REG_DATA` 实 24 形 32）、`:203-204` HDL-5106 `ui_i2c.v:112,120` 初值。前三条 5 分钟能消掉（把变量声明提前、把 `REG_DATA` 端口改成 `[23:0]`），后两条是厂商风格，建议只加注释说明“已知、无害”。

**L5｜移植物丢失的前提条件 + 下载脚本不判结果**
- 参考工程的 ADC 开头有硬前提：“**FEP 口在 BANK13（HR-ADJ），子卡是 1.8V 器件 —— 上电前必须把 BANK13 跳线改到 1.8V**”（`fep_vid006_imx415.adc:4`），我们的 `ph1p_pcie_case_ep.adc:31-33` 只抄了引脚，**这条前提没抄**——照它上电有打坏 1.8V 器件的风险。建议照抄注释并在 `README.md` 里重复一遍。
- `download_sram.tcl:41-43` 只在 `$ok` 为真时执行 `download`，但**不检查 `download` 的返回值**，失败也走 `exit`（`:45`）返回 0；做自动化脚本时无法据此判成败。建议 `download` 后检查结果并 `exit 1`。

---

## 三、逐文件点评（我们新写的文件）

**`rtl/ep_side/img/ep_bar_win.v`（240 行）** — 方向正确，替换厂商 4KB 玩具 RAM 是本次最有价值的改动；时序假设（地址在 sop_ff 那拍锁存、数据下一拍组合给出）我对着引擎 FSM 复核成立（`pcie_ep_engine.v:583-590,620-640` 与 `TL_TX_ACK_MEMR` 的 `mem_first_cycle` 生成），4dw 预取轮转（`:175-190`）与 `fb_rdata` 的 1 拍延迟对得上（`img_frame_src.v:80-84`）。问题集中在“注释与代码不一致”（`:15-20` 的 dw 布局、`:26` 的 MAGIC 期望值、`:33-45` 表只到 0x70）和“假设过强”（只认 3DW 地址 `:96-100`、只解 12 位 `:105/146/204`、完成包长度不可控）。帧缓存末字附近的越界预取（`ptr` 接近 `PTR_BYTES` 时 `fb_raddr` 会读越界地址）只在主机做非 16B 对齐读时才出问题，属低危但建议在 `:79` 的 `ptr_fix` 旁边加一句“16B 读不可跨界”。

**`rtl/ep_side/img/img_frame_src.v`（170 行）** — 写口写法（`:70-72` 单条 if、无复位、无多分支）确实推成了 ERAM20K（`td_20261015_123428.log:186` “Inferred 2 RAMs”、`gate.area:88` 123 块），这个经验值得保留；帧号放字 0 + `pix=x+y+frame` 的公式（`:96`、`:130-136`）让主机能自查，是很好的工程习惯。扣分项：模块头注释描述的配置（320×240/30 块、125MHz/8ms）与实际构建（640×480/123 块、62.5MHz/16ms）全都对不上；`data_len` 报 `W*H`（`:151`）但字 0 被帧号占用，实际像素只有 `W*H-4` 字节，这一点只写在 `:11-14` 的注释里、寄存器表没体现，主机很容易 off-by-4。

**`rtl/ep_side/pcie_ep_engine.v` 的补丁（4 处）** — 我把它与厂商原版 diff 了：① 新增两个参数；② 新增 14 个 img/cam 端口；③ `ram u_pcie_rx_eram` → `ep_bar_win`（`:327-350`）；④ `memrd_addr[6:0]` → `memrd_addr_lo[6:0]`（`:506`）。改动面小、标记清楚（`:50,323`），**没有引入多驱动或删掉必要逻辑**；但替换后 `memrd_addr`（`:103,217-242`）、`mrdata_rd_addr/_dly`（`:123-124,600-618`）变成死逻辑（TD 会优化掉，无害），建议顺手删掉或注明“已由 ep_bar_win 取代”。

**`rtl/ep_side/img/img_regs.v`（148 行，已弃用）** — 它的 UBUS 时序（`:107-121` 2 拍读延迟）和寄存器表（`:17-30`）设计得比 `ep_bar_win` 更“像”一个寄存器块，正是这份设计被搬到 `ep_bar_win` 的注释表里（0x40~0x6C 完全对应）。但它的回绕实现是错的（`:34,137,143` 掩码式），也不支持帧数据窗口，**必须从 `.al:22-29` 撤掉**，否则既浪费综合又在 TB 里制造假信号。

**`rtl/ep_side/ph1p_pcie_ep_top.v` 新增段落（`:67-88` 声明、`:401-419` 参数、`:570-581` 帧源、`:739-958` 摄像头块）** — 声明前移（`:86` 的注释“声明必须早于例化处使用”）是把 12:34 那版 CRITICAL-WARNING 修掉的正解，值得保留这条注释作为“坑位标记”。摄像头段的问题是“组装得太快”：MCLK 分频算错（B1）、状态采样的 CDC 等级不一致（M1）、pixel 计数物理上不可能对（M2）、复位链与主机控制脱节（H5），以及 3 个未使用 localparam、1 个被优化掉的诊断计数器。这一段的注释重复了三遍同一张位表（`:944-949`），建议合并成一张并补上 `6'b110011` 的含义。

**`sim_do/tb_img.v`（180 行）** — 结构清晰（`do_read/do_write/chk` 任务、帧号与像素公式校验、越界回绕用例），如果对准 `ep_bar_win` 它就是一份很好的回归；现在的问题是**靶子错了 + 从未运行 + 其中一条断言必错**（`:37` 例化 `img_regs`、`:116` 期望 0x7C=DEADBEEF 而 `ep_bar_win.v:219` 0x7C 是 `dbg_rd_idx`、`:168` 必 FAIL）。建议把它改写成面向 `ep_bar_win` 的 TLP 级 tb（直接喂 `rx_sop_ff/rx_data_ff`、检查 `mrdata_rd_data` 与 `memrd_addr_lo`），这是唯一能便宜地覆盖 bswap/4dw/地址别名风险的办法。

**`prj/case_ep/constraints/*.adc`** — 摄像头部分与参考工程逐条一致（我逐行比过 `cam_a_xclr_n..cam_b_mclk` 8 条）、且 MIPI 差分对用的是参考工程实测更好的 C 排（`:34-53`，对应参考 `:22-48`），XCLR=M18 与参考一致；扣分在抄漏了 BANK13 1.8V 前提（L5）和一句错注释（L3）。

**`prj/case_ep/constraints/*.sdc` / `build.tcl` / `download_sram.tcl`** — SDC 与厂商原版逐字相同（`diff` 无输出），即**我们新增了一整个时钟域却没加一行约束**（H3）。`build.tcl` 逻辑简单可靠：`log/build4_20261015_115513.log` 尾部是 `PRJ-8806 ERROR: Run syn_1 has exited unexpectedly.` 且**没有**打印 `BUILD DONE`，说明失败时脚本会中止、不会假报成功（正面结论）；缺的是产物归档/时间戳。`download_sram.tcl` 用三次 `catch` 兜连接、只在成功时下载（`:41`），但 `download` 结果不判（L5），且 SRAM/JTAG 与 flash 的说明（`:3-4`）放在同一段容易误操作。

---

## 四、已验证 / 未能验证（盲点）

**已验证（有代码或日志证据）**
1. 隐式网络类故障已修：最新 `log/cam16.log:114` 只剩 1 条 undeclared（`iic_busy`）；12:34 版的 `w_cam_stat`/`w_uart_rxd_unused` 曾触发 `HDL-7225 CRITICAL-WARNING`（`td_20261015_123428.log:100-101`）与 `HDL-5314` 无驱动（`:199-201`）；`ph1p_pcie_ep_top.v:86,88` 的声明前移是对症的。
2. `w_cam_a_stat/w_cam_b_stat` **恰好 32 位**，位域与 `:945-949` 注释逐位一致；`w_cam_stat` 合计 256 位（我按拼接逐段相加核过）。
3. `ic_busy/iic_busy` **不在 I2C 主路径**（主路径用隐式网 `iic_busy`，`:190/:221`），坏的是 `0x98[0]` 诊断位。
4. I2C 速率是**按 62.5MHz 正确重算过的**：`CLK_DIV(16'd624)`（`:839,856`）→ 62.5MHz/625 = 100kHz，与参考工程 `499`@50MHz 等价（`f9p…top.v:179,185`）；这是本工程里“频率改了、常数也跟着改”的唯一一处，值得肯定。
5. 帧缓存**确实推成 ERAM 而非分布式 RAM**（`td_20261015_123428.log:186`、`gate.area:31-32,88`）。
6. 时序收敛：`phy_1/route.qor`（Setup WNS 5290ps / Hold WNS 21ps / 0 违规端点）；`final_timing.rpt:28` 一致。**但覆盖率只有 71.84%（`:10`），见未验证第 1 条。**
7. `ep_bar_win` 的完成包 dw 布局**代码正确、注释错误**（按 `pcie_ep_engine.v:621,630-631` 的 valid 掩码与 `8'hE0/8'hF0` 样例逐位推导）。
8. `cam/` 目录 16 个文件与参考工程逐字节相同，只有 `ui_cfg_imx415.v` 不同（22 行 diff = 我们加的 3 个端口 + 2 条 assign）。
9. `build.tcl` 在 run 失败时会中止（`log/build4_20261015_115513.log` 尾部无 `BUILD DONE`）。
10. 引脚 XCLR=M18 与参考工程一致（`ph1p_pcie_case_ep.adc:54` vs `fep_vid006_imx415.adc:60`），注释里的 P16 是笔误。

**未能验证（明确写出）**
1. **字节时钟域的时序**：既没有约束（SDC 全文 4 行），也没进时序报告（`u_word_align/u_packet/u_gear_box` 在 `final_timing.rpt` 出现 0 次），而少数进入报告的字节域寄存器被标为 `tl_clk_user`（`final_timing.rpt:78`）——两种解释（未分析 / 按 62.5MHz 错分析）都无法用现有报告排除。**该域能不能跑，目前没有证据。**
2. **一切硬件行为**：I2C 是否 ACK、tap=46 是否就是最佳眼位、12.5MHz MCLK 下 IMX415 是否仍能锁相并出 4K、`bswap32` 的字节序是否与主机期望一致（`ep_bar_win.v:233-238`）——我按约束不下载、不 ssh，全部未验证。帧校验程序不在仓库（§2.3-M7），所以连“历史上验证过什么”都无法复核。
3. **当前位流（14:15）的 elaborate 阶段日志缺失**：`prj/case_ep/…/syn_1/` 里最新的 TD 日志是 12:34，而源码最后修改是 14:15:38、位流是 14:16 —— 所以 `w_cam_stat[191]`（= `r_b_pix[31]`）现在是否仍有 “no driver”、`r_syscnt` 是否真被优化掉（我从 `final_timing.rpt:41-42` 的 `sys_clk 扇出=1` 反推为“被优化掉”，属**推断**），都只能用最新那次分析的告警（`cam16.log`）间接支持。
4. **`tap` 的时钟域**：`O_delay_tap` 由 `assign w_tap = I_manual_en ? I_manual_delay : w_auto_tap`（`rx_phy_ph1p.v:88`）产生，`w_auto_tap` 来自字节时钟域的 `auto_delay_ctl`（`rx_phy_ph1p.v:162-165`），所以 `s_a_tap`（`ph1p_pcie_ep_top.v:930`）在 manual_en=1 时是同域、在自动扫描时是跨域——两种模式下的 CDC 属性不同，我只做了静态阅读，未做门级/仿真确认。
5. **4DW 访问路径**：按 §2.2-H1 的代码分析必然错，但主机程序只用 BAR0(3DW)，所以**未实测 4DW/BAR2/BAR4**。
6. **无仿真器**（`command -v iverilog/verilator/vsim/vvp` 全空）→ `tb_img.v` 未运行；“PTR 回绕断言必 FAIL”是我手算掩码的结果，未实跑确认。

---

## 五、建议的下一步（按优先级）

1. **（半天）修 MCLK 并用示波器定案**：先量 L18/G20 实际频率（预期 12.5MHz），再决定是采用 12.5MHz（同步改注释与传感器寄存器表）还是改成 `acc+4` 出 25MHz（或干脆用 PLL 出 24/27MHz）。**在这一步完成前，不要花时间调 tap 和 CSI 参数**——INCK 不对，后面的现象都不可解释。
2. **（半天）给字节时钟加时序约束并重编**：SDC 补 `create_clock`（或 `create_generated_clock`）+ `set_clock_groups -asynchronous`，重跑后检查 `STA coverage` 上升、`final_timing.rpt` 里出现 `u_word_align/u_packet`。同时把这次重编的 elaborate 日志保留下来（现在缺 14:15 那次的），以便确认 `w_cam_stat[191]`/`r_b_pix[31]` 的无驱动告警是否仍在。
3. **（半天）清掉 5 分钟能清的告警**：`ui_cfg_imx415.v:55/59`（`ic_busy`→`iic_busy`）、把 `O_dbg_idx` 与 `reg_index` 声明顺序调正（消 1×1007 + 1×5373）、把 `ep_bar_win.v:107-108` 的 `rd_addr32/rd_len_dw` 声明提到使用之前（消 3×5373）、`REG_DATA` 端口改 24 位（消 5007）。目标：分析日志 0 warning，让以后的新告警一眼可见。
4. **（1 天）定帧数据方案，然后再动 RTL**：按 §2.1-B2 三选一。若选“降分辨率 + 行缓冲”，现在就把 `IMG_W/IMG_H/PTR_BYTES/IDLE_CYCLE` 收敛成 `ph1p_pcie_case_param.v` 里的一组参数（当前散落在 `ph1p_pcie_ep_top.v:67-71,576`、`ep_bar_win.v:40`、`img_frame_src.v:21-23`、`img_regs.v:34` 四处），这是“换板/换分辨率只改一处”的前提。
5. **（1 天）把 `ep_bar_win` 的几个假设补齐**：4DW 地址（H1）、只用 12 位解码（M4）、寄存器表补 0x74~0x9C 并修正 MAGIC/dw 布局注释（M6/L3）、`0x60` 大于 16B 读的行为写进文档并在驱动侧限制（H2）、`CTRL[3:2]` 要么实现要么删除（M5）。
6. **（1~2 天）恢复可回归性**：把 `tb_img.v` 改写成面向 `ep_bar_win` 的 TLP 级 tb（喂 `rx_sop_ff/rx_data_ff`，检查 `mrdata_rd_data/memrd_addr_lo/ptr` 前进/回绕），装 iverilog 跑通；把帧校验程序与期望图样公式入库；从 `.al` 撤掉 `img_regs.v`。这个 tb 是本项目唯一能便宜覆盖“字节序、4dw 夹取、地址别名”这三类静默数据错误的手段。
7. **（半天，写文档）**：`README.md` 补一节“BAR0 寄存器表 + 帧数据搬运步骤 + 一次性 C 程序的用法与判据”，并把 BANK13 1.8V 跳线前提抄进 `README.md` 与 `.adc` 顶部（L5）。当前 README 说 “BAR0/2/4 各 1MB”（`README.md:41`），实测是 BAR0=64KB、BAR2/BAR4=4KB（`td_20261015_123428.log:158`），这种描述会让调寄存器的人一开始就怀疑错方向。
8. **（持续）把 QoR 做成门限**：把 `route.qor` 的 Hold WNS（当前 21ps，最差路径在 `img_frame_src`）、`gate.area` 的 `#eram 123/300`、STA coverage 三个数写进构建脚本的检查项，避免下一次“编过了”被当成“没问题”。