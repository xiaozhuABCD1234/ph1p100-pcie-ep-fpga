# 安路 PH1P100 PCIe EP 工程 —— 只读代码质量审查报告

审查范围：`rtl/ep_side/img/*`、`rtl/ep_side/ph1p_pcie_ep_top.v` 新增段、`rtl/ep_side/pcie_ep_engine.v` 补丁、`prj/case_ep/constraints/*`、`build.tcl`、`download_sram.tcl`、`sim_do/tb_img.v`。
方法：只读命令（read/grep/wc/diff）+ 只读引用 `log/`、`prj/case_ep/ph1p_pcie_ep_top_Runs/` 里的 QoR/timing/area 报告 + 与厂商原始工程做只读 diff。未修改、未创建任何文件，未运行 TD 与下载脚本。
行号约定：凡与 TD 诊断对齐的引用，均按 `grep -n`（按 `\n` 计行）计数，这个口径与 `log/cam*.log` 里的 `(行号)` 一致。

---

## 一、结论摘要

这份移植的**代码骨架是对的、可以继续往下走**：厂商那块 4KB 玩具 RAM 已被 `ep_bar_win.v` 换成真正按字节地址译码的 BAR0 窗口（`rtl/ep_side/img/ep_bar_win.v:20-33` 的寄存器表和 `:200-228` 的组合读 mux 自洽，1~4 dw 读的载荷映射与引擎的有效掩码推导吻合），帧缓存确实被 TD 推成了 ERAM20K 硬块（`phy_1/ph1p_pcie_ep_top_gain.area` 未找到；实际证据：`syn_1/ph1p_pcie_ep_top_gate.area:88`「u_img_frame_src … eram 123」，`:31`「#eram 123 out of 300 41.00%」），已约束的两个时钟域时序收敛（`phy_1/final_timing.rpt:44-47` 显示 tl_clk_user 62.5MHz/SWNS +5.29ns、sys_clk 50MHz），历史上导致 syn_1 直接崩掉（11 条 HDL-7225 + `PRJ-5303`/`PRJ-8806`，见 `td_20261015_115513.logw` 末三行）的隐式网络问题，现在只剩 1 处且是无害的标量（`rtl/ep_side/cam/ui_cfg_imx415.v:221` 的 `iic_busy`），`w_cam_stat` 也已精确为 256 位、`w_cam_a_stat/w_cam_b_stat` 精确为 32 位且位域与注释一致（`rtl/ep_side/ph1p_pcie_ep_top.v:950-958`）。但**在把摄像头像素接进帧缓存之前必须先补一个硬缺口**：整条 MIPI 字节域（每个接收器 ~390 个触发器）在 SDC 里没有任何时钟定义，`final_timing.rpt:8`「STA coverage 71.84%」、`:37-38` 的 Clock Summary 里只有 tl_clk_user/sys_clk，`place_clock_utilization.txt:39-40` 里 `w_a_byte_clk/w_b_byte_clk` 的 Constraint 一栏是 `None`、Clock Period 是空的——也就是说现在 FMAX 93MHz 这个好数字**不覆盖相机通路**，而那正是下一阶段要跑数据的地方；同时 `phy_1/place.qor:33-35` 的 QOR-5001(HIGH) 已经在点名这两个网络同时驱时钟和数据引脚。此外有 3 处会让人误判的事实性问题必须先修：相机 MCLK 实际是 12.5MHz 而不是注释说的 25MHz（`top:763-771`，逐拍推演见 §二 H2），新增的 `O_dbg_busy` 因为拼错了线名而恒为 0（`ui_cfg_imx415.v:55/59`），以及任何 >16 字节的 MRd 会静默返回错数据（`pcie_ep_engine.v:586-587` 的长度字段没有按 `ep_bar_win` 实际能提供的 4 dw 截断）。**结论：当前位流里程碑可以验收，但下一阶段（像素入帧缓存）建议先把 H1/H2/H3 处理完再开工。**

---

## 二、问题清单

### 阻断（针对“像素入帧缓存”这一下一阶段；对当前位流里程碑不构成阻断）

**B1. 相机字节时钟域完全没有时序约束，现有 FMAX 不覆盖它。**
`prj/case_ep/constraints/ph1p_pcie_case_ep.sdc:1-4` 只有 `create_clock -name sys_clk -period 20`、`derive_clocks` 和把 PLL 输出重命名成 tl_clk_user 这三行，没有给 `w_a_byte_clk/w_b_byte_clk` 任何 `create_generated_clock`/`set_clock_groups`。证据链：`prj/case_ep/ph1p_pcie_ep_top_Runs/phy_1/place_clock_utilization.txt:39-40`（`gclk_1/gclk_2` 的 `Constraint`=`None`、`Clock Period` 为空，负载 399/388）、`phy_1/final_timing.rpt:37-38`（Clock Summary 只有两行）、`phy_1/final_timing.rpt:8`（STA coverage 71.84%）、`phy_1/place.qor:33-35`（QOR-5001 HIGH 点名这两个网络）。
为什么：字节域里躺着 `csi_rx_packet_handler/word_align/gear_box/10bit_unpack/byte_align×4/auto_delay_ctl` 共约 787 个触发器（`phy_1/ph1p_pcie_ep_top_phy.area` 的 Hierarchy 表），以及全部字节→tl 的跨域路径；不约束就不会被优化、也不会有任何违例报告。而且 `rtl/ep_side/cam/rx_phy_ph1p.v:73-89` 的 LCLK DIV=4 说明字节时钟 = 串行时钟/4，参考工程按 1.5Gbps/lane 做过测试（`fep_vid006_imx415.adc:19-21` 提到 1.5Gbps 下衰减问题），即量级在 100~190MHz，远高于 tl_clk_user 的 62.5MHz。
改法：SDC 里对 `u_csi_a/u_rx_phy/u_hs_clk_div.clkdivout` 加 `create_generated_clock -divide_by 4 -source <serdes 时钟>`，再 `set_clock_groups -asynchronous` 把两个字节域与 tl_clk_user 分开，并对已有的同步链加 `set_false_path`；加完后重跑 STA，看字节域真实 FMAX 是否够。

### 高

**H1. MCLK 实际是 12.5MHz（占空 40%/60%），不是注释写的 25MHz。**
`rtl/ep_side/ph1p_pcie_ep_top.v:763-771`（累加器每拍 +2、`>=5` 时减 3 并翻转）逐拍推演（已用脚本复核）：acc 序列 0→2→4→6(翻转,回 3)→3→5(翻转,回 2)→…，翻转发生在第 3、5、8、10、13… 拍，半周期交替 2/3 拍，**平均半周期 2.5 拍 → 输出周期 5 拍 → 62.5/5 = 12.5MHz，高电平占 2/5=40%**。要得到 25MHz（周期 2.5 拍、半周期 1.25 拍）累加步长必须是 4（翻转间隔 1,1,1,2）。
旁证这不是“注释笔误而是改错”：I2C 分频被作者按 62.5MHz 重算过——`top:847/862` 用 `CLK_DIV(16'd624)`，62.5MHz/625 = 100kHz，而参考工程 `f9p_imx415x2/uisrc/01_rtl/f9p_imx415x2_top.v:185` 用 499（50MHz/500=100kHz），说明作者知道现在是 62.5MHz，唯独 MCLK 没跟着改。参考工程自己也标注“IMX415 实测需按模组改成 24/27MHz”（同文件 `:31`）。
改法：`top:770` 改成 `r_mclk_acc <= r_mclk_acc + 3'd4;`（阈值仍 5），或直接用 5 分频计数器得 50% 占空 25MHz；顺手把 `top:743/744/747` 的 50MHz/168ms 注释改对（168ms 是 50MHz 下的值，62.5MHz 下 `23'h7FFFFF` = 134.2ms）。

**H2. `O_dbg_busy` 接的是另一根没人驱的线 → I2C 忙位恒为 0。**
`rtl/ep_side/cam/ui_cfg_imx415.v:55` 声明了 `wire ic_busy;`（全工程无驱动），`:59` 写了 `assign O_dbg_busy = ic_busy;`；而厂商状态机用的是**未声明**的 `iic_busy`（`:182/:190/:194`），它的实际驱动力来自 `:221` 的 `.O_iic_busy(iic_busy)` 端口连接所生成的隐式网络。于是 `top:887-888` 采回来的 `w_a_i2c_busy` 连到 `w_cam_stat[192]`（`top:956`）永远是 0——这个状态字本来就是为了看“I2C 有没有在推进”而挂出来的，现在这一位是死的。
改法：`:55` 改成 `wire iic_busy;` 并删掉 `ic_busy` 这个名字（厂商状态机不受影响，`O_dbg_busy` 立刻变活）。注意 `reg_index` 是 8 位（`:75`）而 `O_dbg_idx` 是 9 位（`:48`），零扩展不算错；但 `top:887` 的 `w_a_i2c_idx` 只写不读（见 L4），所以“I2C 进度”字段整体到不了主机。

**H3. 任何超过 16 字节的 MRd（或寄存器地址上读多个 dw）都会静默返回错数据。**
`rtl/ep_side/pcie_ep_engine.v:586-587` 完成包长度直接用请求长度 `tl_mr_len_ff`（甚至把长度字段 0 解释成 1024 dw），byte count = `{len,2'b0}`；而第一个周期的有效掩码 `mrdata_cycle_valid` 是按请求长度算的（`v:621/631`）。但 `rtl/ep_side/img/ep_bar_win.v:108` 只准备了 4 个 dw，`:233-238` 把 `mrdata_rd_data[127:0]` 填 0。后果矩阵：(a) 读 0x60 请求 5~N dw → 第 5 个 dw 起是引擎移位路径 `v:510` 送出的重复/垃圾数据，byte count 还按请求长度报；(b) 读寄存器地址请求 >1 dw → 除第一个 dw 外全是 0；(c) 数据源与引擎对“长度字段=0”的解释不一致（`v:587`=1024 dw，`ep_bar_win.v:101`=1 dw，指针只前进 4 字节）。
现在没爆是因为主机侧只发 1-dw 读：`pcie_ep_test/driver/anlogic_pcie_drv/cdev_ctrl.c:241/272` 是 `ioread32`，`anlogic_pci_lib.c:117` 是 `readl`。一旦改用 `memcpy_fromio`/DMA 或别家的 RC 驱动，就会读出错帧而不报错。
改法：给 `ep_bar_win` 加 `rd_len_dw>4` 时的截断/UR 应答（需要引擎配合把 `tl_mr_len_ff` 按已服务长度改写），并在寄存器表里明确写“0x60 单次 ≤16 字节”。

**H4. `w_cam_stat` 这类“隐式 1 位网络吃宽端口”的风险机制仍然存在，而警告过滤日志看不见它。**
历史实证：`log/cam2.log:92`「HDL-1007 : undeclared symbol 'w_cam_stat' … ph1p_pcie_ep_top.v(450)」+ `:95`「HDL-7225 CRITICAL-WARNING: 'w_cam_stat' is already implicitly declared … (918)」+ `:147`「==== BUILD DONE ====」——**这一次是编过并出位流的**，即 256 位端口被接到了 1 位隐式网（只有最低位有数据，其余 255 位无驱动）。当前全量日志里同类只剩 1 条（`log/cam16.log:114` 的 `iic_busy`），4 条 HDL-5373（`cam16.log:96-98` 的 `rd_addr32/rd_len_dw`、`:115` 的 `reg_index`）。
真正的系统性风险在流程：**`*.logw`（TD 的告警过滤日志）根本不包含 HDL-1007**——我检查了全部 `*.logw`，没有一份含 "undeclared"，但有 14 份含 HDL-7225。也就是说只看 `.logw` 会漏掉“新增了一个未声明符号”的早期信号，而 `td_20261015_115513.logw` 证明这类问题一旦走到 HDL-7225 就直接把 syn_1 打崩（末三行 `PRJ-5303 WARNING: Run syn_1 failed` / `PRJ-8806 ERROR: Run syn_1 has exited unexpectedly`）。
改法：`build.tcl` 里加一步从**全量日志**里 grep `HDL-1007.*undeclared|HDL-7225|HDL-5373`，命中就非零退出；不要再用 `.logw` 作为唯一检查面。

### 中

**M1. 图像通路两半用了不同的复位源，PCIe 复位会静默改掉 MIPI 采样点。**
`rtl/ep_side/pcie_ep_engine.v:334` 给 `ep_bar_win` 的是 `.rst(tl_rst_user)`，而 `top:580` 给 `img_frame_src` 的是 `.rst(power_on_rst_dly)`；相机链路（`top:746-759` 的 `r_pwr_cnt2/r_rst_n_slow/r_rst_n`）**不接受任何复位**。因此在链路重训/热复位时：`ctrl_enable/ptr/cam_tap_cfg` 全被清 0/回默认（`ep_bar_win.v:123` 的 `7'b1_101110` = tap 46），而 `rx_phy` 的 IDELAY 仍在跑、帧源仍在写缓存，MIPI 眼图可能被悄悄改坏且没有任何东西重启 I2C 配置。
改法：图像通路统一到一个复位域；若保留现状，至少在文档里写明“PCIe 复位会重置 tap，主机会话必须重新写 0x9C”。

**M2. `ep_bar_win` 不做 BAR 译码，寄存器窗口在整个地址空间里按 4KB 重复。**
端口列表里没有 `tl_rx_bardec`（`pcie_ep_engine.v:332-352`），译码只用 `addr[11:0]`（`ep_bar_win.v:105/113/139/152`）。BAR0 是 1MB（`README.md` 的“上手三步”），于是 0x40~0x9C 每 4KB 重复一次，且**任何** Memory 访问（比如 BAR2 的 0x40、或同 4KB 窗口里别的设备的 BAR）都会命中并可能改写寄存器。当前没爆是因为 MSI-X 表在 BAR4 的 0x1000 起（`rtl/common/BDF.v:51` `MSIX_TABLE_OFFSET 28'h1000`，4×16B → `addr[11:0]` 落在 0x000~0x03F，避开了 0x40+）。
改法：把 BAR0 命中位（`tl_rx_bardec[0]` 或等价信号）引进 `ep_bar_win`，`req_rd/req_wr` 与读 mux 都加门控。

**M3. 子双字（非 4 字节整字）写寄存器会被解释错位。**
`ep_bar_win.v:147-154` 全部按“字节翻转后的第一个 payload dword”取值（`tlp_dw_s`，`:83-100`），完全没有看 `tl_rx_valid` 字节使能。`writeb/writew` 到 0x44 或 0x5C 时，被写的字节在 dword 里的 lane 位置决定了 bswap 后的落点，会置错位甚至读到未写入的 lane。今天能工作是因为厂商驱动统一用 `writel`（`anlogic_pci_lib.c:125`）。
改法：寄存器表加“仅支持 4 字节对齐整字写”，或按字节使能做 lane 选择。

**M4. 完成包的 Lower Address 与 DATA 窗口实际数据地址不符。**
`ep_bar_win.v:139` 锁的是请求地址 `tlp_addr[6:0]`（读 0x60 时就是 0x60），而返回的数据来自 `ptr`（`:179`、`:233-238`）。按 PCIe 规范，完成包 LA 字段必须是第一个返回字节的地址 → 规范偏离，只因 RC 不做校验才没暴露。
改法：DATA 情形下 `memrd_addr_lo <= ptr[6:0]`，或干脆把自动递增窗口改成“按地址寻址的帧数据窗口”。

**M5. 字节域→tl 域的几处跨域采样只有 1 拍甚至 0 拍。**
`top:928-931`：`s_a_lane<=w_a_lane_valid`（4 位）、`s_a_tap<=w_a_delay_tap`（6 位）各只用 1 个触发器，多位信号可能采到不自洽的组合；`top:932`：`s_a_cfg <= {w_a_bus_err, w_a_delay_done, w_a_cfg_done}` 把字节域的 `w_a_delay_done`（`rx_phy_ph1p.v:159-168` 的 `auto_delay_ctl` 跑在 O_byte_clk）和 tl 域信号拼在一个触发器里；`top:950-955`：`w_a_in_line/w_a_in_frame` 是字节域输出（`mipi_csi2_rx_ph1p.v:127-135`，`I_clock=O_byte_clk`）却**没有任何同步器**直接组合进状态字，而状态字组合进 `mrdata_rd_data`（`top:454` → `ep_bar_win.v:229-231`）——也就是说这条半稳态路径落在完成包的数据通路上（后果是偶发错一位状态，不是致命）。
改法：全部改成两级同步器（多位信号按慢变量处理或做握手/gray），`w_a_in_line/in_frame` 先打两拍再进状态字。

**M6. `r_a_pix/r_b_pix` 作为“像素计数”不可信（采样率不足）。**
`top:898-901` 把 `pixel_valid` 边沿做成 toggle，`top:922-927` 三级同步 + `[2]^[1]` 边沿检测，`top:937-938` 计数。3 级同步 + 边沿检测的写法本身是对的，但 toggle 翻转率的量级不允许：4K@30fps ≈ 2.49 亿像素/秒，即使按字节域 100~190MHz 估，toggle 也在 50~100MHz，而采样时钟只有 62.5MHz → 欠采样/混叠，计数只会偏小（奈奎斯特上限 62.5M 次/秒）。这个计数器从 `0x90/0x94` 暴露给主机（`ep_bar_win.v:220-221`），容易被当成帧率依据。
改法：把像素计数放到字节域做，跨域只搬慢速计数（或用 FIFO/握手）；库里只保留“收到过像素”的粘滞标志位。

**M7. `img_regs.v` 是死代码，但它和活代码是两套互相矛盾的寄存器表。**
`prj/case_ep/ph1p_pcie_ep_top.al:22-29` 仍以 `UsedInSyn=true` 登记它，`log/cam16.log:93` 显示 TD 每次都在 analyze，但 `phy_1/ph1p_pcie_ep_top_phy.area` 的实例层次表里**没有 `img_regs` 实例**（全设计只有 `u_img_frame_src`）；唯一消费者是 `sim_do/tb_img.v:37`。危险点在于它和 `ep_bar_win` 语义不同：没有 bswap（MAGIC 读回 0x50434946 而不是活模块的 0x46494350）、用掩码回绕（`img_regs.v:34` `PTR_MASK=0x0001_2BFC`，`:143` `(rd_ptr+4)&PTR_MASK`——76796+4 与掩码与完是 75776 而不是 0，算式已复核）、0x7C 返回 `DEADBEEF` 而活模块返回 `dbg_rd_idx`（`ep_bar_win.v:219`）。谁按这个文件“理解”或“恢复”图像寄存器都会踩坑。
改法：从 `.al` 删除 `img_regs.v`（或挪到 `doc/` 存档），寄存器表只保留 `ep_bar_win.v` 一份真源。

**M8. 唯一的 testbench 指向死模块，且三处期望值与活设计不符；本机也没有仿真器。**
`sim_do/tb_img.v:2/37` 测的是 `img_regs`；`:35/:38` 假设 125MHz（活设计 62.5MHz）；`:109` 期望 MAGIC=0x50434946（活模块经 bswap 后是 0x46494350，`ep_bar_win.v:83-100/209`）；`:165-168` 的最后一条断言“PTR 回绕到 0”在数学上就不成立（76796+4 与 0x12BFC = 75776）。仿真器确实没有：`iverilog/vvp/verilator/modelsim/vsim/ghdl` 全部找不到，`/usr/bin/vcs` 经 `dpkg -S` 确认是 `python3-vcstool` 而不是 Synopsys VCS。也就是说图像通路目前**零可执行回归**，只剩一次性 C 程序对照。
改法：把 TB 改成对 `ep_bar_win` 做（含 >4 dw、4 dw 边界、回绕、子字写四个反例），并让它在 CI 里跑起来（iverilog 很小，或走 TD 自带仿真）。

### 低

**L1. `ep_bar_win.v` 头部注释关于载荷位置的说法与代码相反（这是会诱发“改错代码”的注释）。**
`ep_bar_win.v:12-13` 写“第 0 个 dw 必须落在 `mrdata_rd_data[127:96]`，第 k 个在 `[96+32k +: 32]`”，而 `:238` 实际是 `{p_dw0,p_dw1,p_dw2,p_dw3,128'd0}`，即 dw0 在 `[255:224]`。对照引擎第一周期 `v:506` 把 `mrdata_rd_data[255:96]` 接到 tx 载荷 `[159:0]`、`:621/631` 的有效掩码（4 dw 读 = `8'b1111_1110`，bit7 对应 `[255:224]`），可确认**代码是对的、注释是错的**。改法：把 `:12-13` 按实际写对；否则下一个人“按注释修代码”会让所有读全错。

**L2. 寄存器表只登记到 0x70，另有 9 个地址没有进表。**
未登记：0x74 `last_wr`（`:154/217`）、0x78 `fb_raddr`（`:218`）、0x7C `dbg_rd_idx`（`:219`）、0x80~0x98 状态字 7 个 dw（`:220-226`）、0x9C tap（`:152/227`）；`top:740-741` 的注释写“0x80~0x94”，实际到 0x98；`top:956` 拼接时最前面的 `32'd0` 落在 `[255:224]`，而没有任何地址读它 → 这 32 位不可达。另外 0x5C 读回的是**移动后**的当前指针（`:214`），主机不能对它做读-改-写。

**L3. 魔法数与死参数：**`top:950/953` 拼接最高 6 位 `6'b110011` 是状态字签名，任何注释里都没写；`[15:11]` 的 `5'd0` 也没说明；`top:781-782` 的 `USE_MANUAL_TAP/CAM_IDELAY_TAP` 是死的（tap 实际来自 `ep_bar_win.v:123`），改它不会有任何效果。

**L4. 注释/默认值与实际不符（都是“时钟从 125MHz/50MHz 改成 62.5MHz”留下的残迹）与真正死掉的诊断：**
`img_frame_src.v:23`「125MHz 下 1e6 ≈ 8ms」（实为 16ms）；`ep_bar_win.v:40` 默认值注释写 640x480 而 `img_frame_src.v:21-22` 默认 320x240；`top:747`「~168ms」（实为 134.2ms）；`top:876-877` 的 `r_syscnt` 写了但从不读——`phy_1/final_timing.rpt:38` 里 `sys_clk … Fanout 1` 就是它被优化掉的直接证据，所以“sys_clk 有没有在跳”这个诊断其实不存在；`top:887-888` 的 `w_a_i2c_idx` 同样只写不读。`prj/case_ep/constraints/ph1p_pcie_case_ep.adc:33` 注释说“cam_a_xclr_n 占用原串口 rxd 的 P16”，实际 `:54` 是 M18——对照参考工程 `f9p_ph1p100_imx415x2/uisrc/04_pin/fep_vid006_imx415.adc:60` 确认**管脚是对的、注释是错的**（M18 是 AP115 那版的 rxd，P16 才是 AP119 版）。

**L5. “字节时钟在跑”这个位其实是粘滞的“曾经跑过”。**
`top:891-892` + `:939-940` 的 `r_a_bclk_seen` 一旦置 1 永不清，而注释 `top:948` 写“bit0 字节时钟在跑” → 字节时钟后来丢了也看不出来。`top:950-955` 同位的 `r_a_pv_seen` 同理（这个语义是对的，只是注释要改）。

**L6. 死代码/死文件清单（均已核对）：**
`top:71` `IMG_PTRMSK`（自注“未用”）、`top:743` `MCLK_DIV`、`top:781-782`、`top:84` 的 `img_pattern` 只在 `ep_bar_win.v:149` 被写、`:205` 被读回，而 `img_frame_src` 没有 pattern 输入（`top:575-578` 未接 `PIX_ADD`）→ **CTRL[3:2] pattern 位对图像没有任何作用**；`top:855-856` 起 `w_a_pixel/w_b_pixel`、`w_a_ae_done`、`w_a_pkt_done/sync_wait` 均无消费者；`.al` 里 `sfifo.v/wfifo.v`（`:247-262`）、`pulse2toggle.v`（`:279-286`）编译但无实例（层次表里没有它们，且 `pulse2toggle.v:7-20` 的逻辑被 `top:898-903` 手抄了一遍）；`.al:309` 的厂商 4KB `ram` IP 其唯一实例已被本次补丁删除（`pcie_ep_engine.v` 相对厂商版的 diff 第 3 段），XML 还被 TD 每次报缺失（`log/cam16.log:25-27`）。

**L7. 脚本健壮性：**`build.tcl:12-14` 在 `wait_run syn_1` 之后不检查 run 状态就 `save_best_bits` + 打印 `BUILD DONE`（失败判别完全依赖 TD 自己非零退出）；`build.tcl:5` 注释说“日志: log/td_*.log”，实际 `td_*.log` 落在调用目录；`download_sram.tcl:9` 把位流绝对路径写死、且下载后没有任何回读校验（`-mode jtag` 写在 `:42`，掉电即失这点注释是对的）。

**L8. 编码与行尾：**`.al:4` 声明 `TD_Encoding=UTF-8`，但 `rtl/ep_side/cam/ui_cfg_imx415.v` 是 **UTF-8 与 GBK 混排**（1310 个字节不是合法 UTF-8、另有 12 处不是合法 GBK；例如 offset 1010 是 UTF-8 的“控制模块”，offset 2842 是 GBK 字节），`ui_imx415_reg.v` 是纯 GBK；参考工程同文件同样两种解码都失败，所以这是继承来的、不是本次改动引入（我们新增的行是纯 ASCII）。风险是未来任何一次“另存为 UTF-8”都会把注释永久毁掉，也可能让 IDE 的行号/搜索对不上。另 `ph1p_pcie_ep_top.v` 混用 CRLF/LF（14 行带 CR）。TD 当前能正常吃下，故只列低。

**L9. 每次构建都出现的 `PRJ-9210` 噪音：**`log/cam16.log:25-27` 报三个 IP XML 不存在，但这三个文件在 `prj/case_ep/al_ip/{ram,pcie_ep_core,pcie_pll_ep}/` 下都存在（已 `find` 确认）——像是从工程根目录调用 `td build.tcl` 时 IP 相对路径解析的差异。它会淹没真实错误，值得花十分钟消掉或写进 README 说明。

---

## 三、逐文件点评（我们新写/改写的文件）

**`rtl/ep_side/img/ep_bar_win.v`（240 行）** —— 本次移植质量最高的文件：头部“时序预算”那段（`:15-18`）与引擎实际行为一致（`mem_first_cycle` 在 `pcie_ep_engine.v:559-565` 的定义、完成包第一拍在 `:486-508` 组装，我逐步对齐过：sop 后第 3 拍正好是 `rd_addr32` 已锁存、`ptr` 刚更新、`pf0..pf3` 仍是旧指针预取数据的时刻，1~4 dw 读的数据映射正确）。`ptr_fix` 用比较回绕而不是掩码（`:76-81`）是对上一版掩码 bug 的正确修正。问题集中在“窗口契约没写完”：注释里的 dw0 位置是错的（L1）、寄存器表缺 9 项（L2）、没有 BAR 门控（M2）、LA 与数据地址不符（M4）、服务长度只有 4 dw 而完成包长度不设上限（H3）。

**`rtl/ep_side/img/img_frame_src.v`（170 行）** —— “简单写口 + 组合读 + 输出寄存器”的写法确实换来了 ERAM20K 硬块，而且层次面积报告显示 640×480 的读多路选择并没有成为瓶颈（`final_timing.rpt` 最差路径 slack 5.29ns，路径就是 `img_frame_src.v(64)` 的 ERAM 读 mux → `ep_bar_win` 的预取寄存器，见 `phy_1/final_timing.rpt:77-85`），也就是说头部注释 `:9` 关于“640x480 要先拆 bank”的担心这次没有成立（但代价是 123/300 = 41% 的 ERAM）。打包顺序与注释一致（我按 `:138-143` 推过：lane0 在 `[31:24]`、x 最小者在 `[7:0]`，小端成立）。需要注意的是默认参数 320x240 与顶层 640x480 不一致、`:23` 的 8ms 注释过期，以及 `data_len` 把帧号字算在内（`:151`，主机按 W×H 读到的是 WORDS×4 字节，其中头 4 字节是帧号——文档写了，但很容易被下一个人当成 bug 去“修”）。

**`rtl/ep_side/img/img_regs.v`（148 行）** —— 已弃用但仍在工程文件表里，且是一份**语义冲突**的旧寄存器表（无 bswap、掩码回绕算式本身是错的、0x7C 语义不同）。它现在唯一的用途是给 `tb_img.v` 提供被测对象，等于用一份错误实现给一份错误 TB 提供通过的理由。建议直接从 `.al` 摘掉。

**`rtl/ep_side/ph1p_pcie_ep_top.v`（963 行，新增约 230 行 + 端口/例化改动）** —— 好的部分：所有 `img_*`/`cam_*`/`w_cam_stat`/`r_rst_n` 现在都在 `:74-88` 处先声明再使用（历史崩溃点已闭合），新增寄存器初值全是 0（GSR 友好，没有 `=1'b1` 的隐式上电值），`rxd` 端口删除后把 uart rx 静态拉高（`:88`）处理正确，拼接位宽精确（见 §四）。风险几乎全在这里：MCLK 12.5MHz（H1）、双复位域（M1）、跨域质量与像素计数（M5/M6）、四个死诊断/死参数（L4/L6）。另外 `:739-741` 的大段“跨时钟域只搬慢变电平 + toggle 计数”的说法与 `:950-955` 的无同步器组合使用是矛盾的，建议改成文档里如实列出每条跨域路径的处理等级。

**`rtl/ep_side/pcie_ep_engine.v`（补丁共 4 段，96 行 diff）** —— 补丁很干净且带显式标记（`:50`、`:323`），相对厂商原版只做了：加两个参数、加 img/cam 端口、把 `ram u_pcie_rx_eram` 换成 `ep_bar_win`、Lower Address 从 `memrd_addr[6:0]` 换成 `memrd_addr_lo[6:0]`（diff 第 4 段）。未动任何厂商 TLP 逻辑——这是对的。唯一遗留问题是完成包长度不按实际服务长度截断（H3），它的根源在厂商代码 `:586-587`，但现在被我们的窗口放大了，理应由我们补上。

**`prj/case_ep/constraints/ph1p_pcie_case_ep.adc`** —— 差分对与 8 根控制脚的 LOCATION/IOSTANDARD/PULLTYPE/DRIVESTRENGTH 与参考文件逐字一致（`adc:34-61` vs `fep_vid006_imx415.adc:22-67`），IO 报告确认全部落位且 I2C 有 PULLUP、DIFF_TERM=TRUE（`phy.area` 的 IO 表，差分电阻列 100）。丢掉的是参考文件里的前置条件与踩坑记录（BANK13 必须切 1.8V、A 排串了 100R 所以要走 C 排，`fep_vid006_imx415.adc:4-8/19-21`），以及 `:33` 那句错注释。

**`prj/case_ep/constraints/ph1p_pcie_case_ep.sdc`** —— 与厂商原文件**完全一致**（diff 无输出，221 字节），也就是说 SDC 一行没改：在引入了两个字节时钟域的今天，它已经不够用了（B1）。这是本报告里性价比最高的一处改动。

**`build.tcl` / `download_sram.tcl`** —— 逻辑可用（reset→launch→wait→save→exit；下载是 JTAG 到 SRAM 且注释明确说明不写 flash，`download_sram.tcl:2-4`）。缺三样：失败门禁（H4 的 grep 步骤）、产物新鲜度校验（`download_sram.tcl:9` 的绝对路径无时间戳检查）、以及对每次必现的 `PRJ-9210` 的处理说明。

**`sim_do/tb_img.v`（180 行）** —— 结构（task 化读写信道 + chk 断言 + 超时）本身是合格的、断言意图也好，但目标对象是死模块、时钟假设是 125MHz、MAGIC 期望值与 bswap 冲突、最后一条回绕断言数学上就不成立，且本机无仿真器 → 目前它是“看起来有测试”的幻觉。

---

## 四、已验证 / 未能验证

### 已验证（有代码或日志证据）

1. `w_cam_a_stat`/`w_cam_b_stat` **恰好 32 位**（`top:950-955`，拼接项 6+1+1+1+1+6+5+1+1+1+1+1+1+4+1=32），字段位置与注释自洽：`s_a_cfg = {bus_err, delay_done, cfg_done}`（`top:932`）→ bit5/6/7 = cfg_done/bus_err/auto_done，bit8/9/10 = in_frame/in_line/pv_seen，`[21:16]`=tap，bit22/23 = xclr/rst_n，bit24/25 = SCL/SDA —— 与 `top:948-949` 的注释逐位对齐。`w_cam_stat` = 32+32+32×4+32+32 = **恰好 256 位**（`top:956`）。
2. 历史故障链：`cam2.log:92/95/147` 证明“隐式网络 + BUILD DONE”当过真；`td_20261015_115513.logw` 证明同类问题走向 HDL-7225 时 syn_1 会直接崩（11 条 CRITICAL-WARNING + `PRJ-5303` + `PRJ-8806`）。当前全量日志只剩 1 条 undeclared（`cam16.log:114`）。
3. “42 条 HDL-1007 undeclared”这个前提**不成立**：`log/cam16.log` 里 HDL-1007 共 42 行，构成为 33×`analyze verilog file` + 4×`analyze included file` + 4×`back to file` + **1×undeclared**（`grep -o "HDL-1007 : [a-z ]*" | uniq -c` 实测）。全历史单次运行的 undeclared 峰值是 11（build4），不是 42。HDL-5373 在当前运行确实是 4 行（`cam16.log:96-98` 两处 `rd_addr32/rd_len_dw` 位于 `ep_bar_win.v:107/108`，声明在 `:114/115`；`:115` 的 `reg_index` 用于 `ui_cfg_imx415.v:58`，声明在 `:75`）——这四条建议顺手消掉：把 `rd_addr32/rd_len_dw` 的声明提到 `:107` 之前，把 `assign O_dbg_idx/O_dbg_busy` 挪到 `reg_index` 声明之后。
4. 0x9C **不存在**读写语义冲突：`ep_bar_win.v:152` 写 `cam_tap_cfg`、`:227` 读 `{25'd0,cam_tap_cfg}`，同一寄存器、位域一致。真正的毛病是“表里没登记”和 M2/M3/M4，不是地址冲突。
5. 帧缓存是硬块、且不是瓶颈：`gate.area:88`（u_img_frame_src eram=123）、`:31`（123/300=41%）；最差 setup 路径 slack +5.29ns、FMAX 93.371MHz（`final_timing.rpt:44-47`），路径正是 ERAM 读 mux → `pf` 预取寄存器（`:77-85`）。
6. `sys_clk` 域的诊断确实已被优化掉：`final_timing.rpt:38` 的 `sys_clk … Fanout 1`，而 `top` 里 `sys_clk` 只出现在 `:244`（PLL refclk）和 `:877`（死计数器）。
7. 相机参考代码的集成范围：`rtl/ep_side/cam/` 下 17 个文件里 16 个与参考工程**逐字节相同**（diff 全部 IDENTICAL），仅 `ui_cfg_imx415.v` 有 22 行 diff，内容就是新增 `O_dbg_idx/O_dbg_busy` 两个端口和两条 assign（`:48-49/58-59`）。`rl/ep_side/cam/auto_delay_ctl.v:7` 提到“新增 ST_WAIT_DATA”但那是参考工程自带的（该文件 IDENTICAL），不是本次改动。

### 未能验证（盲点，明确标注）

- **字节域真实 FMAX**：SDC 里没有这些时钟 → 无报告可看（B1）。这是最大的未知。
- **MCLK 实测频率与 IMX415 在 12.5MHz 下是否正常出图**：无示波器/硬件访问，H1 只到“代码语义 = 12.5MHz”这一步；12.5MHz 是否仍在模组可用范围、寄存器表是否隐含 24/27MHz 假设，未验证。
- **字节序（bswap 方向）**：`ep_bar_win.v:12-13` 的注释与 `:238` 的代码矛盾（L1），而 MAGIC 常量 `0x5043_4946` 经 bswap 后主机读到的是 `0x4649_4350`。两条路只能有一个是对的——**一次硬件读 0x40 就能定案**（读到 0x50434946 → 注释对、bswap 方向反了，整个帧数据会按 4 字节组错序；读到 0x46494350 → 代码对、注释和 `tb_img.v:109` 的期望都该改）。在没做这一步之前，我不能断言“图像搬对了”，只能说“寄存器回环自洽”。
- **>16 字节 MRd 在实机上是否真会发生**：驱动侧代码证据指向 1-dw 读（`cdev_ctrl.c:241/272`），但 RK3588 侧运行时的实际 TLP 长度没有观测过。
- **TB 从未在本机执行**：无 iverilog/modelsim（`/usr/bin/vcs` 是 python3-vcstool）；帧数据通路（字 0 = 帧号、像素公式）只经过我与 RTL 的静态推演，没有仿真落锤。
- **综合阶段的完整告警列表**：`syn_1/run.log`、`phy_1/run.log` 已不在仓库（`cam16.log:123-124` 引用了它们但文件不存在），所以除了 `log/*.log` 与 `*.logw` 之外的综合期告警（宽度不匹配、RAM 推断信息等）看不到。
- **`r_rst_n` 漏声明当年的具体现象**“PHY 常复位”来自代码注释 `top:757`，日志只能证明它当时是 undeclared（`cam2.log:94`），现象本身未验证。
- **FEP 子卡实际接的是 A 排还是 C 排**：`.adc` 用的是与参考 C 排一致的一组球号，但板级接线未验证。
- 主机侧（RK3588/驱动/C 程序）不在本次审查范围，未审。

---

## 五、建议的下一步（按优先级）

1. **补 SDC 并重跑 STA（B1）**：给两个字节时钟加 `create_generated_clock`、加 `set_clock_groups -asynchronous`、给已有同步链加 `set_false_path`；拿到字节域 FMAX 后再决定像素通路怎么接。顺手把 `final_timing.rpt:8` 的 71.84% 覆盖率抬上去。
2. **一次硬件读定案字节序（L1 + §四盲点）**：`pci_bar 0 0x40`，看到 `0x50434946` 还是 `0x46494350`；据此改注释或改 `bswap32` + `tb_img.v:109`。这一步几乎零成本，却决定整条图像通路的正确性叙述。
3. **修 MCLK（H1）**：`top:770` 改成 `+3'd4`（或改 5 分频 50% 占空），同时把 `:744/:747` 的 50MHz/168ms 注释改对；若实测想保留 12.5MHz，就把注释和 IMX415 寄存器表一起重新标定并写明依据。
4. **修 `ic_busy`→`iic_busy` 并让 I2C 忙位真正可读（H2）**：两行改动，改完就能用状态字 `[192]` 观察 I2C 是否在推进——这是后续排障最省事的一步。
5. **给构建加门禁（H4）**：`build.tcl` 从全量日志 grep `undeclared|HDL-7225|HDL-5373`，命中即失败；停止把 `.logw` 当唯一检查面。
6. **定死 BAR 窗口契约（H3/M2/M3/M4）**：0x60 单次 ≤4 dw 的截断或 UR、BAR0 命中门控、子字写限制或 lane 选择、DATA 情形 LA 用 `ptr[6:0]`——四条一起改一次，比以后一处处踩便宜。
7. **清理与收敛（M1/M7/L2-L6）**：从 `.al` 摘掉 `img_regs.v`、`sfifo.v`、`wfifo.v`、`pulse2toggle.v` 与废弃 `ram` IP；把 `ep_bar_win` 头部寄存器表补全到 0x9C；图像通路统一复位域；删掉 `r_syscnt/w_a_i2c_idx/IMG_PTRMSK/MCLK_DIV/USE_MANUAL_TAP/CAM_IDELAY_TAP` 或让它们真的起作用；`img_pattern` 要么接到 `PIX_ADD`/pattern 逻辑，要么从表里删掉。
8. **把回归建起来（M8）**：TB 改测 `ep_bar_win`（含 >4 dw 与 4 dw 边界、回绕、子字写四个反例），装上 iverilog 或接 TD 仿真流，纳入一键脚本。
9. **最后才是像素数据入帧缓存**：此时字节域已约束、MCLK 已确认、CDC 已按 M5/M6 规范化，才具备可验证的地基；同时要提前规划 ERAM 预算——640×480 单缓冲已占 41%（`gate.area:31`），双路/双缓冲会直接超器件。