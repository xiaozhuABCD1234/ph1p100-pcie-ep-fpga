# F9P 板载 DDR3 集成调查 + 最小 bring-up 设计（只读调查，未改任何 RTL）

- 日期：2026-10-15
- 范围：**只读调查**。本文件是本次唯一被创建/修改的文件。
- 本次**未做**的事：未构建 TD 工程、未生成/导出任何 IP、未下载 bitstream、未 ssh 任何板子、未运行仿真器（本机无仿真器）、未安装/下载任何软件。
- 本机环境（关键）：`/opt/anlogic/TD_Release_2026.2_NL`，实际 `td` 版本 **6.2.3.210850**（见 `ph1p_pcie_ep_top.al:5`）；例程工程/IP 是 **6.2.2(build 190657)** + IpTool `2026.01(189136 2026/01/26)` 生成的（见 `09_ddr3_.../prj_src/ip/ddrmc_x32/ddrmc_x32.v:6-9`、`DesignConfiguration.xml:13`）。
- 临时文件：为提取 PDF 文本曾写 `/tmp/swug105.txt`、`/tmp/ipug034.txt`、`/tmp/ddrdir.txt`，**调查结束已删除**（`rm -f`）。除此之外没有留下任何文件。
- 结论中凡是没有实测/实证的，一律标 **未确认**，没有把推断写成实测。

---

## 0. 结论速览

| # | 问题 | 结论 | 置信度 |
|---|---|---|---|
| 1 | DDR IP 产物怎么来 | **(c) 只能从例程拷** 是唯一有本机实测依据的可行路径；(a) 的 `create_ip`/`set_property`/登记部分实测可用，但 **`generate_target` 在批处理里不产出 RTL**（MIPI_DPHY 实测先例）→ 对 DDR IP "纯命令行搞定" **未确认、大概率不行**；(b) GUI 是官方文档唯一"生成"流程，也是 09 例程的实际生成方式 | 高（(c)/(b)）；中（(a) 不行） |
| 2 | 用户侧接口 | native **PAXI**（例程选它）：**单拍 256 bit = 32 B/拍**，**没有 len/size/burst 信号**；用户侧时钟是 IP **输出**的 `dhi_clk`（1600 Mbps 配置下 = **200 MHz**，实测 5.000 ns），复位 `ddrphy_rst_n`、校准完成 `ddrphy_rdy` 都是 IP 输出；`cfg_clk`（50 MHz）带 APB | 高（有 RTL 行号 + 厂商 build 报告） |
| 3 | sys_clk(H4) 与 DDR refclk | **不是"抢脚"**：IP 的 `ref_clk` 只是一个普通输入端口，IP **自己不给 refclk 写引脚约束**；H4 的引脚约束本来就在我们工程里（`constraints/ph1p_pcie_case_ep.adc:17`）。要做的只是把同一个 `sys_clk` 网络 **同时**送给既有 PCIe PLL 和 DDR IP 的 `ref_clk` | 高 |
| 4 | 速率口径 | 三处口径：板卡手册/芯片数据手册 **800 Mbps**；例程目录名 **1066**；例程 IP 实配 **1600**（tCK=1250 ps、DDR3-1600K、CL=11）。**新发现（比"口径矛盾"更严重）**：该 IP 的 `CWL` 是默认值 **5**，而 GDP1BFLM-CB 数据手册规定 CL=11 时 tCK∈[1.25,1.5)ns **必须 CWL=8**（CWL=5,6,7 是 Reserved）→ 例程那版 1600 配置在颗粒侧**不是 JEDEC 合法组合** | 高（两侧都有原文） |
| 5 | 建议 | 预算按 800 Mbps（3.2 GB/s）；**用 GUI 重新生成一版 800 Mbps 的 IP**（DDR3-800D：CL5/CWL5，合法且与数据手册口径一致）；同时可先照抄例程 IP 做一次性"1600 到底行不行"的对照实验 | — |
| 6 | 是否需要"下载后重启" | DDR **不需要**（没有主机侧枚举问题）；只有 PCIe 那套需要。DDR 侧真正的要求是：**复位释放后必须等 `ddrphy_rdy`（=cal_done）才能发第一次 PAXI 访问**，期间大概毫秒级训练时间 | 中（机制清楚，时长未实测） |

---

## 1. DDR IP 怎么来（问题 1）

### 1.1 TD 确实有 IP flow 的 Tcl 命令（文档层证据）

`/opt/anlogic/TD_Release_2026.2_NL/doc/SWUG/SWUG105_TCL_Command_User_Guide.pdf`（SWUG105，2026.08）**4.4 节 "IP flow 命令"**（PDF 第 38–40 页）：

- `4.4.1 create_ip`：`create_ip -vlnv <ip vlnv> -component_name <component_name> [-export_path <path>]`
  - 原文：「-export_path <path>：（可选）指定 IP 生成位置。若不指定，默认生成在工程文件同级目录的 al_ip 文件夹下」
  - 示例：`create_ip -vlnv anlogic.com:ip:AXIS_Data_FIFO:1.0 -component_name axis_data_fifo_1`
- `4.4.2 get_ipdefs`（列 IP Catalog 全部 vlnv）
- `4.4.3 get_ips [component_name]`
- `4.4.4 generate_target <objects>`：「生成目标 IP 输出文件」，示例 `generate_target [get_ips data_fifo_0]`
- `4.4.5 load_project_ips`：**原文**「用于命令行或脚本中在 open_project 命令后使用，加载工程中所有存在的 IP，将其加入 TCL 流程管理中。图形化界面下无需关心。」
- `4.4.6 close_project_ips`

即：**Tcl 层面"能建/能配/能 generate"** 是官方文档写着的；但文档**没有**给任何"批处理生成 IP RTL"的实例，也没有说明哪些 IP 支持批处理。

### 1.2 后端是 IpTool 子进程，且 IpTool 内部确实有 batch 子命令集

TD 主程序里与 `create_ip` 相关的字符串（`strings bin/td`，行号是 `strings` 输出序号）：

```
2773308 -depot           2773313 create_ip -vlnv "      2773316 set_property
2773317 -vlnv             2773319 -export_path           2773323 ERROR: No IP matching VLNV '
2773324 Failed to launch iptool.
2876008 ipxact:design.ipxact:componentInstances.ipxact:componentInstance
2876009 IpTool exited immediately, exit code =
2876017 ' dose not support batch mode. please enter other valid vlnv
2876018 ' dose not support the current project device. please enter other valid vlnv.
2805214 component/vendorExtensions/customTool/
2805215 component/vendorExtensions/modulePath/
```

`bin/IpTool` 里的 batch 子命令与开关：

```
aliptIpgenRegisterBatchCmds      alCmdIsBatchMode        gIpGenBatchMode
CMD_BATCH_GENERATE_INST          CMD_BATCH_SET_PROPERTY  CMD_BATCH_GET_PROPERTY
CMD_BATCH_REPORT_PROPERTY        CMD_BATCH_GET_IP_DEFS
-batch   -tcl   -- batch reload
' dose not support batch mode. please enter other valid vlnv
canUpgradeFrom   ipst_upgrade   ipupgrade   -report_ip   report_ip_status
{} be locked, please upgrade it before generate by defalut, lock reason: {}
```

解读（推断，非实测）：`create_ip` 会拉起 IpTool，走 `CMD_BATCH_GENERATE_INST`；**并且存在"某些 IP 不支持 batch mode"的分支**——判据很可能是 XPath `component/vendorExtensions/customTool/`（见 1.3）。

### 1.3 哪些 IP 支持批处理：IP Catalog 里的 `customTool`

`/opt/anlogic/TD_Release_2026.2_NL/ip/depot/Catalog.xml`（167 条 IP 条目）：

- 带 `<ipxact:customTool>use_host</ipxact:customTool>` 的 **53 条**，是**老式必须用宿主 GUI 工具生成**的 IP：`PLL 1.0`、`PCI Express 1.0/1.3`、`DRAM 1.0`、`DDR3/4 SDRAM 4.0`、`MIPI IO 1.0`、`RAM 1.0`、`FIFO 1.0` 等。
- **不带 customTool** 的 114 条（新的 ipxact 格式 IP），包含：
  - `MIS_DDRF6F1D0P0` 1.2（Catalog.xml:1005-1016）——即本项目的 DDR IP：
    ```xml
    <ipxact:vlnv vendor="anlogic.com" library="ip" name="MIS_DDRF6F1D0P0" version="1.2"/>
    <ipxact:deviceRegexp regexp="^PH1P100GEG324$|^PH1P100SBG484$|^PH1P100SBG676$|^PH1P100SBG677$|...|^PH1P50SBG484$"/>
    <ipxact:DisplayName>MIS - DDR2/DDR3/DDR4</ipxact:DisplayName>
    ```
    → **`PH1P100SBG484` 在支持列表里**（这点对本项目很重要，且与例程 `ph1p_ddr.al:11` 的 `<Device>PH1P100SBG484</Device>`、`<Speed>-3</Speed>` 一致）。
  - 也包含 `MIPI_DPHY 1.0`、`PCI_ExpressF6F1D0D0 1.0`、`PLLF6F1D0P0 1.1` 等。

**但是**：`customTool` 只能证明"这类 IP 允许 TD 内建 `xmlipgen` 处理"，**不能证明 `generate_target` 会产出 RTL**——见 1.4 的实测反例，那正是 `MIPI_DPHY`（同样不带 customTool）。

TD 内建生成器 `xmlipgen` 的开关（`strings bin/td`）：

```
xmlipgen
--usernamed_file --design_file --designConfig_file --component_file --package --only_usernamev --debug
Start xmlipgen command / Finish xmlipgen command
```

### 1.4 **本机实测先例（最重要的一条证据）**

本仓库既有工程的 README 记录了对 `anlogic.com:ip:MIPI_DPHY:1.0` 的**实际批处理实验**：

`/home/xiaozhu/Projects/f9p_ph1p100_imx415x2/README.md:163-173`（原文）：

> TD 6.2 自带 `anlogic.com:ip:MIPI_DPHY:1.0`（`ip/depot/MIPI_DPHY_1.0`），实测：
> - `create_ip` 能建出 IP 并登记进 `.al`；`set_property` **能改参数**，但顺序与 Vivado 相反：
>   **`set_property <值> <参数名> <IP对象>`**；`open_project` 之后必须先 `load_project_ips`。
> - `generate_target` 在批处理里**不产出 RTL**（rc=1，目录里只有 xml/params）→ 例化它就报
>   `HDL-8007 ERROR: xxx is a black box`。生成 IP RTL 是 GUI 动作，没有公开的 Tcl 文档。
> - 坑（已踩）：`03_ip` 被删空后再跑 `create_ip`，TD 会重写 `.al` 并**静默删掉已有 IP 的 `<IP_FILE>` 条目**（表现为另一个 black box）——`.al` 必须留备份。

同一实验的脚本还在：`/home/xiaozhu/Projects/f9p_ph1p100_imx415x2/gen_ip.tcl`
（`import_device ph1_100p.db -package PH1P100SBG484 -speed 3` → `open_project` → `load_project_ips` → 一串 `set_property <值> CONFIG.GUI_xxx $ip` → `generate_target all $ip`，第 34 行）。

**这条证据的分量**：
1. 参数名的形式是 `CONFIG.<参数名>`（对 DDR IP 应为 `CONFIG.PH1P_DDR_SPEED` 之类）。
2. `create_ip` / `set_property` / 登记进 `.al` 这条链**实测能用**。
3. **`generate_target`（产出 RTL）实测不能用**。DDR IP 是否同样失败 **未确认**（没有实测），但风险很高：两者同属"不带 customTool 的新式 IP"，且 DDR IP 的产物生成同样依赖 `Dependency.tcl` + `plugin_end.tcl` 里的**一堆依赖求值 proc**（`update_pll`/`update_drc_check`/`update_sysclk_loc`/`gui_sw_idx`…，见 `.../MIS_DDRF6F1D0P0_1.2/Dependency.tcl:154-2681`），其中 `update_sysclk_loc` 会去读 `PH1P_IO_ASSIGN` 指向的 adc、并用全局 `CFG_BANK_INDEX/CFG_PKG_CSV` 求 PLL/Bank 位置——批处理下这些全局是否被正确初始化，**未确认**。

### 1.5 09 例程的 IP 是 **GUI** 生成的（直接证据，不是推断）

`/mnt/nvme/fpga/TD/work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/prj_td/log/ipgen.log`（全文 18 行）——里面是 GUI 操作回放：

```
 1 ipgen_gui_set_spin_box_text IP_Generator PH1P_REF_CLK 100.00
 2 ipgen_gui_set_spin_box_text IP_Generator PH1P_DDR_SPEED 800.00
 3 ipgen_gui_set_spin_box_text IP_Generator PH1P_REF_CLK 50.0000
 4 ipgen_gui_set_spin_box_text IP_Generator PH1P_DDR_SPEED 1333.00
 9 ipgen_gui_set_spin_box_text IP_Generator PH1P_DDR_SPEED 1600.00
11 ipgen_gui_select_combobox_item IP_Generator PH1P_SPEED_BIN DDR3-1600K 3
12 ipgen_gui_click_push_button IP_Generator OK
13 ipgen_gui_select_dialog IP_Generating_Options
14 ipgen_gui_click_push_button IP_Generator GenOptionDialog.Generate
16 ipgen_gui_select_dialog StandardMessageBox #IP Gen Succeeded
18 #GUI-2000 : The IP files have been generated successfully. :{PH1P100SBG484(F:/al_data/F9P_PH1P100/08_ddr3_ddrmc_cal_x32_1066mbps/prj_src/ip/ddrmc_x32/ddrmc_x32.xml)}
```

可以读出三件事：
1. 生成方式是 **GUI**；且在 800 → 1333 → 1600 之间试过几轮，最后定在 **REF_CLK=50 MHz / DDR_SPEED=1600 / SPEED_BIN=DDR3-1600K**。
2. 生成时的器件就是 **PH1P100SBG484**，工程路径就是 F9P_PH1P100。
3. 除 REF_CLK/DDR_SPEED/SPEED_BIN 外**没有点过任何别的参数**（没有 CWL、CL、阻抗、DQ Bytes…的操作）→ **其余参数全是默认值**（这就是 0 号结论里 CWL=5 的来源，见 §3.7/§5）。

官方文档也是 GUI 流程：`/opt/anlogic/TD_Release_2026.2_NL/doc/IPUG/IPUG034_PH1P_MIS_IP_Guide.pdf` §3.1.1「新建 IP」原文：「打开 TD 软件，依次点击 Tools -> IP Catalog -> Primitive IP -> Memory and Storage-> MIS – DDR2/DDR3/DDR4, 得到如下界面」；§3.2「完成配置后，点击 OK 按钮，软件默认在工程所在文件夹的 al_ip 下生成 `<IP_USERNAME>` 文件夹、`<IP_USERNAME>_drc_check.log`、`<IP_USERNAME>_adc.log`、`<IP_USERNAME>_proc.log`」。

### 1.6 例程 IP 目录逐文件清单 + "器件相关 / 板级相关"分类

目录：`/mnt/nvme/fpga/TD/work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/prj_src/ip/ddrmc_x32/`
（先验证过：`/mnt/nvme/.../work/peripheral/09_.../prj_src/...` 与 F9P 官方包 `01_start/02_peripheral_demo.zip` 内的同名文件 **md5 完全一致** —— `ddrmc_x32.v`/`.params_ddrmc_x32.txt`/`src/adc/ddrmc_x32.adc`/`golden_adc/ap115v2_ddr3_x32.adc` 四个文件两边 md5 相同，说明 work 目录里那份就是官方例程原件，没有被本地改过。）

注册方式（关键）：整个 IP 目录在工程 `.al` 里**只登记一个 xml 文件**：

`prj_td/ph1p_ddr.al:203-212`
```xml
<IP_FILE>
  <File Path="../prj_src/ip/ddrmc_x32/ddrmc_x32.xml">
    <Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&R" Val="true"/>
    <Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="21"/>
  </File>
</IP_FILE>
```
RTL/ADC/SDC 都由 `ddrmc_x32.xml` 内部的 fileset 带进来（共 **52 个文件**，已逐个核对：xml 里列出的 52 个文件在目录里全部存在，**没有缺项**）：

| 文件 / 目录 | xml 里登记的 | 性质 | 说明 |
|---|---|---|---|
| `ddrmc_x32.xml` | — | 器件+板级 | 元数据：参数/端口/文件清单；`moduleName ddrmc_x32`（xml:21） |
| `Design.xml` | — | 器件+板级 | **生效参数值**（configurableElementValue，见 §3.7 行号表） |
| `DesignConfiguration.xml` | — | 器件 | IP 版本、`viewRef="DDRMC"`、`ipGenVersion 189136 2026/01/26` |
| `.params_/_.m_params_/_.ports_ ddrmc_x32.txt` | — | 器件+板级 | GUI 参数快照 / 派生参数 / 端口快照（本项目调查主要引用源） |
| `ddrmc_x32.v` | ✅ | **器件+板级** | IP 顶层 wrapper：把参数固化进 `ph1p_ddrmc_wrapper_ddrmc_x32` 的例化（tCK/BK_NUM/…/CWL/…） |
| `ph1p_ddrmc_wrapper_ddrmc_x32.v` | ✅ | **器件** | IP 功能顶层（时钟、APB、PAXI/AXI、控制 RAM、DDRIO 端口） |
| `src/rtl/**`（含 `top/`、`clk/`、`cal/`、`init/`、`misc/`、`phy/`、`mc/`） | ✅ | **器件** | DDRPHY+MC 本体；`mc/mc0_alc_mc_top_all.enc.sv` 是**加密** SV（不可读、不可改） |
| `src/rtl/include/ph1p_mis_define.vh` | ❌（被 include） | **器件** | **固化的配置宏**：`DRAM_DDR3 / DDR3_2G / DDR3_X16 / DDR3_1600K / PH1P100 / PH1P_VCCIO_1V35`（1-9 行） |
| `src/rtl/timing/ddr3/*.vh` | ✅ | **器件** | 时序参数表；`ddr3_parameter.vh:128-132` 决定 `DDR3_1600K → CL=11` |
| `src/rtl/phy/include/ph1p_ddrphy_board_delay.vh` | ❌（被 include） | **板级** | 板延时段落；由生成器写；`fast_init_wrapper.v:88` 以相对路径 include |
| `src/rtl/phy/ddrphy_cfg_rom.txt` | ✅ | **器件** | PHY 配置 ROM 初始化 |
| `src/adc/ddrmc_x32.adc` | ✅ | **器件(站点) + 板级(球号)** | 见下 |
| `src/sdc/ddrmc_x32.sdc` | ✅ | **器件** | IP 层时钟约束（`derive_clocks` + 5 条 `rename_clock` + 一条 async group） |
| `sim/fileset/fileset_mis.f` | ❌ | 仿真用 | 仿真 filelist（含 `<mis_path>` 占位） |

`src/adc/ddrmc_x32.adc` 里其实是两类东西：
- **板级（球号）**：`set_ippin_assignment { ddr_dq[0] } {LOCATION = U3; IOSTANDARD = SSTL135;}` 等 71 条 —— 来自生成时输入的 `PH1P_IO_ASSIGN`（golden adc）。
- **器件相关（硬核站点）**：`set_ipinst_assignment {ph1p_ddrmc_wrapper/.../dx_byte[0]$...$u_ddrphy_byte} {LOCATION = X77Y70Z0;}`、`ac_byte[0..2] → X77Y90/Y100/Y110`、`u_pll0 → X77Y80Z0`、`u_pll1 → X77Y119Z0`、`mlclk/ioclk/bkref` 等 18 条。

**结论（对任务书里"可否把 F9P 的引脚 adc 换进去复用"的直接回答）**：
> **不需要换。** 例程生成时用的输入 adc 就是 F9P 球号（`Design.xml:91` 原文写着
> `PH1P_IO_ASSIGN = "F:/al_data/F9P_PH1P100/08_ddr3_ddrmc_cal_x32_1066mbps/golden_adc/ap115v2_ddr3_x32.adc"`），
> 生成的 `src/adc/ddrmc_x32.adc` 与 `_adc.log` 里的 bank/byte/bit 也和 `PH1P100SBG484` 的
> `PH1P_DDRPHY_IP/.../pkg/PH1P100SBG484.csv` 完全对得上。文件名与头部注释里的
> `DEVICE : PH1P50SBG484 / Bank31,Bank32` 是**从 PH1P50 版本复制过来没更新的陈旧注释**，
> 以 71 条球号和 `_adc.log` 为准。

`_adc.log`（`prj_src/ip/ddrmc_x32_adc.log`，共 71 行）的 bank 列可以**独立证明** DDR 落在 BANK32/33：

- 所有 `ddr_dqs*/ddr_dq*/ddr_dm*` 的 bank=**4**（= bank 索引 4 = **BANK32**）
- 所有 `ddr_addr*/ddr_ba*/ddr_ck*/ddr_cse/…` 的 bank=**5**（= **BANK33**）
- 第 71 行：`refclks,5,2,0,` → **DDR 的参考时钟就是 BANK33 byte2 bit0 = H4**

（bank 索引表：`/opt/anlogic/TD_Release_2026.2_NL/ip/depot/MIS_DDRF6F1D0P0_1.2/PH1P_DDRPHY_IP/Other/ph1p_ddrphy_ip/pkg/cfg.csv` 中 `PH1P100SBG484` 行为
`BANK11_0+BANK12_1+BANK13_2+BANK14_3+BANK32_4+BANK33_5`；`PH1P100SBG484.csv:262` 为 `H4 ,5 ,2 ,0 ,Y`。）

DRC 检查通过：`prj_src/ip/ddrmc_x32_drc_check.log` 9 行，最后一行 `Complete all signals check ,the design rule check pass!`（参数里也落了 `PH1P_DRC_CHECK : PASS`，`.params_ddrmc_x32.txt:119`）。

### 1.7 三选一：**明确的答案**

| 选项 | 判定 | 依据 |
|---|---|---|
| (a) 能纯命令行搞定 | ❌ **对"生成 IP RTL"这一步不成立**（至少未确认、大概率不行）；仅 `create_ip`/`set_property`/登记 `.al` 这部分可用 | SWUG105 §4.4 有命令，但 `generate_target` 在本机对 MIPI_DPHY **实测不产 RTL**（`f9p_ph1p100_imx415x2/README.md:167-168`）；IpTool 里有 `' dose not support batch mode` 分支 |
| (b) 必须用 TD GUI 点一遍 | ✅ **这是官方文档 + 厂商实际使用的生成流程** | IPUG034 §3.1/§3.2；`09_.../prj_td/log/ipgen.log` 是 GUI 回放日志 |
| (c) 只能从例程拷 | ✅ **唯一零风险的现成路径，且完全合法**（同为 PH1P100SBG484、球号同 F9P） | 例程 IP 目录完整（52/52 文件齐）、DRC PASS、能编译出 bit（`prj_td/ph1p_ddr_Runs/best_result/ph1p_ddr.bit` 2026-05-22） |

**最终口径**：
1. **想用 1600 Mbps 那套参数** → 直接 **拷** 例程 IP 目录（(c)），零生成风险。
2. **想改参数（尤其想改成 800 Mbps，见 §4.3）** → 必须 **(b) 用 GUI 重新生成一遍**（Tcl 路未验证，别指望）。
3. 不管走 (1) 还是 (2)，工程登记都只是 `add_files al_ip/ddrmc_x32/ddrmc_x32.xml` 一行。

### 1.8 如果调用方要放行一次"命令行生成"实验（草案，**未执行**）

```tcl
# 注意：本文件未运行。仅供放行后实验；
# 顺序与坑来自 ~/Projects/f9p_ph1p100_imx415x2/gen_ip.tcl + README 实测经验
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
open_project {ph1p_pcie_ep_top.al}
create_ip -vlnv anlogic.com:ip:MIS_DDRF6F1D0P0:1.2 -component_name ddrmc_x32 -export_path al_ip
load_project_ips                                  ;# 必须：open_project 之后先调这个
set_property "DDR3"   CONFIG.PH1P_DDR_TYPE   [get_ips ddrmc_x32]
set_property 50.0     CONFIG.PH1P_REF_CLK    [get_ips ddrmc_x32]
set_property 800.0    CONFIG.PH1P_DDR_SPEED  [get_ips ddrmc_x32]   ;# 800 口径（见 §4.3）
set_property 4        CONFIG.PH1P_DQ_BYTE    [get_ips ddrmc_x32]
set_property "x16"    CONFIG.PH1P_COMP_TYPE  [get_ips ddrmc_x32]
set_property 2048     CONFIG.PH1P_COMP_DENSITY [get_ips ddrmc_x32]
set_property "DDR3-800D" CONFIG.PH1P_SPEED_BIN [get_ips ddrmc_x32]
set_property "1.35"   CONFIG.PH1P_IO_VOL     [get_ips ddrmc_x32]
set_property "Internal" CONFIG.PH1P_VREF     [get_ips ddrmc_x32]
set_property 0        CONFIG.PH1P_AXI_CTRL   [get_ips ddrmc_x32]   ;# 0 = native PAXI（例程口径）
set_property <绝对路径>/ddr3_x32_f9p.adc CONFIG.PH1P_IO_ASSIGN [get_ips ddrmc_x32]
generate_target [get_ips ddrmc_x32]        ;# ← 预计在这里失败（不产出 RTL）
report_ip_status [get_ips ddrmc_x32]
```
判据：`al_ip/ddrmc_x32/` 下是否出现 `ddrmc_x32.v` + `ph1p_ddrmc_wrapper_*.v` + `src/rtl/**` + `src/adc|sdc`，以及 `ddrmc_x32_proc.log` 是否跑完（例程的 proc.log 见 §1.6）。**注意**：参与实验前先 `cp ph1p_pcie_ep_top.al /tmp/`（README 记录的坑：TD 会重写 `.al` 并静默删掉已有 `<IP_FILE>` 条目）。

---

## 2. 端口与时序（问题 2）

### 2.1 IP 顶层端口（`prj_src/ip/ddrmc_x32/ddrmc_x32.v:12-67`）

```
input  ref_clk                 // 参考时钟（本例=sys_clk，板上 H4/50MHz）
input  sys_rst_n               // 低有效系统复位，直接控制内部 PLL
output apb_pclk                // = cfg_clk
input  apb_prst_n, apb_psel, apb_penable, apb_pwrite
input  [15:0] apb_paddr ; input [31:0] apb_pwdata ; output [31:0] apb_prdata ; output apb_pready
output dhi_clk                 // ★ 用户逻辑时钟（DHI/PAXI 都在这个域）
output cfg_clk , output cfg_rst_n
output ddrphy_rst_n            // ★ 用户逻辑复位（由 IP 产生）
output ddrphy_rdy              // ★ 初始化+训练完成（=cal_done，见 §3.5）
input  [26:0] paxi_awaddr  , input paxi_awvalid , output paxi_awready
input  [255:0] paxi_wdata  , input [31:0] paxi_wstrb , input paxi_wvalid , input paxi_wlast , output paxi_wready
input  [26:0] paxi_araddr  , input paxi_arvalid , output paxi_arready
output [255:0] paxi_rdata  , output paxi_rlast , output paxi_rvalid , input paxi_rready
input  [1:0] usr_ref_type , input usr_ref_req , output usr_ref_ack   // 用户刷新控制
output [7:0] ecc_err_sig , output [7:0] ecc_err_mul                 // ECC=OFF 时无意义
output ctl_ram_rst_n , output ctl_ram_cke                            // 控制 RAM 相关
output [0:0] ddr_ck_p/ddr_ck_n/ddr_reset_n/ddr_cke/ddr_odt/ddr_cs_n/ddr_ras_n/ddr_cas_n/ddr_we_n
output [2:0] ddr_ba ; output [13:0] ddr_addr
inout  [3:0] ddr_dqs_p/ddr_dqs_n/ddr_dm ; inout [31:0] ddr_dq
```

二选一接口由 `PH1P_AXI_CTRL` 决定：`=0 → MC0_MIS_AXI 未定义 → PAXI`（例程口径，`.params:17/74`、`.ports:17-47` 的 `axi_*; 0`）。AXI 模式下才有 `axi_aclk/axi_aresetn/awlen/awsize/awburst` 等（见 `ph1p_ddrmc_wrapper_ddrmc_x32.v:91-160`）。

**关键点：PAXI 模式下没有独立的"用户 AXI 时钟"输入** —— 唯一的用户时钟是 IP 输出的 `dhi_clk`（`ph1p_ddrphy_clk_top.v:138 assign dhi_clk = pll1_clk_0;`）。所以用户逻辑**必须**跑在 `dhi_clk` 上（或自己做 CDC）。

### 2.2 时钟树与实际频率（**已用厂商 build 报告实测）**

文档：IPUG034 §2.1.3「PLL0 用于产生 DDRPHY 的并行时钟 ctl_clk 和串行时钟 ddr_clk。PLL1 用于产生用户逻辑相关的 dhi_clk(usr_clk)。其中 dhi_clk 为 DHI 接口工作时钟」；「ref_clk 输入来源可使用 GCLK 专用时钟管脚（输入参考时钟周期抖动必须小于 25ps，推荐与 AC 信号在同一 Bank），或内部全局时钟网络（可能由于 PLL 级联造成系统性能下降）」。

公式（`ip/depot/MIS_DDRF6F1D0P0_1.2/Dependency.tcl:926-1122 update_pll`）：
- `PH1P_ACTUAL_FREQ = PH1P_REF_CLK × PLL0_FBKCLK_DIV / (PLL0_REFCLK_DIV × PLL0_CLK2_DIV)` = 50 × 32 / (2 × 1) = **800 MHz（DDR_CK）**
- `PLL1_REFCLK_FREQ = PH1P_ACTUAL_FREQ / 4` = 200 MHz（PLL0→PLL1 级联）
- `PLL0_CLK3` 目标是 50 MHz（`CLK3_DIV=16` → 800/16 = 50 MHz）→ **cfg_clk = 50 MHz**

**实测交叉验证**（厂商自己编译的 09 例程 place 报告）
`prj_td/ph1p_ddr_Runs/phy_1/place_clock_utilization.txt` A 节 Global Clock Resource Stat：

```
| u_ddrmc_test_top/u_ddrmc_x32/usr_clk | ... | Clock Period 5.000  |  ← dhi_clk = 200 MHz
| u_ddrmc_test_top/u_ddrmc_x32/mcu_clk | ... | Clock Period 20.000 |  ← cfg_clk = 50 MHz
```

（`usr_clk` 驱动的正是 `u_ddrmc_mtest/clk`。）同时那份报告显示 DDR IP 会自己造 3 个 `PH1P_PHY_GCLK`、4 个 `IOCLK`、2 个 `MLCLK`（资源占用见 §4.8）。

**换算**：`dhi_clk = DDR_CK/4 = PH1P_DDR_SPEED/8`。所以
- 1600 Mbps → dhi_clk 200 MHz（32 B × 200 MHz = 6.4 GB/s = 理论峰值 ✅）
- 800 Mbps → dhi_clk 100 MHz（3.2 GB/s）

### 2.3 PAXI 协议细节

**(1) 一拍 = 32 B，没有突发长度信号。** IPUG034 表 2-10 只定义了 `awaddr/awvalid/awready/wdata/wstrb/wvalid/wready/wlast` 与 `araddr/arvalid/arready/rdata/rlast/rvalid/rready`；**没有 `awlen/awsize/awburst`**。原文：「当 paxi_awvalid 和 paxi_awready 信号同时为高电平时，每一时钟周期传输一个地址」。
例程实现佐证（`prj_src/rtl/mtest/ph1p_ddrmc_mtest.v:441-454`）：
```verilog
assign cmd_rdy      = paxi_awready & paxi_arready;        // 读写通道不能同时发
assign paxi_awvalid = (cmd_type == CMD_WR) ? wr_en   : 1'b0;
assign paxi_wvalid  = wr_en & cmd_en;
assign paxi_wlast   = 1'b1;                               // ★ 每拍都是最后一拍
assign paxi_rready  = 1'b1;                               // ★ 永远 ready
assign paxi_arvalid = (cmd_type == CMD_RD) ? cmd_en  : 1'b0;
```
IPUG034 §2.3.3.2 原文：「pAXI 接口的读写通道分离，但不支持读写命令同时发送」；「pAXI 接口的写数据信号可以在写地址信号后最多 2 个时钟周期后产生」。

**(2) 写掩码极性有矛盾（必须实测确认）**：IPUG034 表 2-10 写 `paxi_wstrb`「写数据掩码信号，**高电平有效**」；但例程把整条掩码**恒置 0**（`ph1p_ddrmc_mtest.v:436-438`：`assign wmask_phase[p*DX_NUM+n] = 1'b0;` 对全部 p、n）——若"高有效"成立则例程一个字节都写不进去。**两处必有一处错**，本调查无法判定（未实测）→ 列为 bring-up 第一个要试的开关（全 0 / 全 1 各试一次）。

**(3) 地址映射（`ROW_COL_BANK`，本例口径）** IPUG034 表 2-12（DDR3）：
```
Row[ROW_WIDTH-1:0] = paxi_axaddr[COL_WIDTH+BA_WIDTH +: ROW_WIDTH]
Col[COL_WIDTH-1:0] = { paxi_axaddr[3+BA_WIDTH +: COL_WIDTH-3], paxi_axaddr[2:0] }
Ba[BA_WIDTH-1:0]   = { paxi_axaddr[3 +: BA_WIDTH-1], paxi_axaddr[3+BA_WIDTH-1 +: 1] }
```
代入 `ROW=14, COL=10, BA=3`（27 bit 地址）：`Row[13:0]=addr[26:13]`、`Col[9:3]=addr[12:6]`、`Col[2:0]=addr[2:0]`、`Ba[2]=addr[4], Ba[1]=addr[3], Ba[0]=addr[5]`。
例程的地址发生器是**线性**的（`paxi_stg_cmd_gen.v:57-59`）：`cmd_addr = {wr_addr[23:0], 3'b000}`，`wr_addr` 每拍 +1 → **paxi 地址每拍 +8**。

> ★ **由此得到本项目最有用的结论**：把 DRAM 看成 **2^24 个 32 B 原子（= 512 MB）**，第 t 个原子的 PAXI 地址就是 `{t[23:0], 3'b000}`——**整片 512 MB 线性可寻址，不需要写任何 bank/row/col 计算**（`addr[2:0]` 恒 0，因为一拍覆盖 BL8 的 8 个列）。地址低位先走 bank（打乱过的 3 bit）、再走列、再走行。

**(4) 32 B 拍内的字节布局**：IPUG034 表 2-4/2-8 原文「`dhi_wdata` 是按 Byte 拼接的，每 Byte 对应 `dhi_wdata[n*64 +: 64]`，步进为 64，…每 Byte 内部分为 8 个 Burst，步进为 8」→ `paxi_wdata`/`paxi_rdata` 的 256 bit = **4 个 DQ byte × 8 个 burst（列）**，即 byte lane = `dqbyte*8 + col`。
（例程为了按 DQ byte 做逐字节比对又做了一次重排：`paxi_rdata[p*DQ_WIDTH+n*8 +: 8] → rdata_byte[n*64+p*8+:8]`，`ph1p_ddrmc_mtest.v:398-400`。）
对帧缓存的意义：**只要写入与读出用同一套 lane 规则，环回自洽**；只在"主机要按像素线性解析 DDR 原始内容"时才需要做 32 B 内的置换。**该布局未实测**（由文档 + 例程代码推断）。

### 2.4 复位与"校准完成"

- `sys_rst_n`（IP 输入）：低有效，**直接控制内部两个 PLL**；释放后系统自动进入初始化流程（IPUG034 §2.1.3）。
- `ddrphy_rst_n`（IP 输出）：给用户逻辑用的同步化复位（例程用它做 mtest 的 `rst_n`）。
- `ddrphy_rdy`（IP 输出）：**就是 cal_done**。证据：`src/rtl/top/ph1p_ddrmc_top.v:228` 是 `.cal_done ( ddrphy_rdy )`；例程用户逻辑的用法是
  ```verilog
  ph1p_ddrmc_mtest ... .clk (dhi_clk), .rst_n (ddrphy_rst_n), .ddrphy_rdy (ddrphy_rdy)   // ddrmc_test_top.v:139-176
  ```
  并且 mtest 内部再打一拍 `ddrphy_rdy_r` 后才开始发命令（`paxi_stg_cmd_gen.v:66-68`）。
- **用户逻辑必须等 `ddrphy_rdy` 才能发第一次访问**（例程 cmd FSM 从 IDLE → WR 是靠 `start`；逻辑上 ddrmc 未 ready 时不能发命令）。

### 2.5 校准状态可以用 APB 读（IPUG034 §2.4.1/§2.4.4，表 2-25）

APB 16 bit 地址 / 32 bit 数据，挂在 IP 的 `apb_pclk`（= `cfg_clk` 50 MHz）上：

| 地址 | 含义 |
|---|---|
| `16'h3000` | ID = `32'h20251202`；`[7:0]=dbg_cal_step`（bit0 WRLVL、bit1 GATE、bit3 WLA start） |
| `16'h3004` | `[15:8]=dbg_cal_done`、`[23:16]=dbg_cal_err`（bit0 WRLVL、bit1 GATE、bit3 WLA） |
| `16'h3008` | CR：`[3:0]=nsel`（WLA 第 1..4 笔）、`[7:4]=bsel`（DQ Group 0..8） |
| `16'h3010/14` | WLA 回读数据 w0/w1（64 bit） |
| `16'h3018/1c` | RDEYE/WREYE 左右边界（`[8:0]` 左、`[24:16]` 右；RDEYE/WREYE **默认未开放**，需手动设置） |

文档给的用法示例：「如访问 WRLVL 的结果，只需读取地址为 `16'h3004` 的 APB 地址，返回的数据中，bit[0] 为 WRLVL start，bit[8] 为 WRLVL done，bit[16] 为 WRLVL err」。
→ **"校准失败"是可诊断的**，这直接决定了下面 §3.6 自检寄存器要暴露什么。

例程里 APB 的接法与地址分配（`ddrmc_test_top.v:127-133, 199-222`）：

```verilog
assign ddrphy_apb_pclk = cfg_clk;  assign mtest_apb_pclk = cfg_clk;
assign ddrphy_apb_psel = (usr_apb_paddr[23:20] == 4'h0) ? usr_apb_psel : 1'b0;  // 0x0_xxxx → DDRPHY
assign mtest_apb_psel  = (usr_apb_paddr[23:20] == 4'h1) ? usr_apb_psel : 1'b0;  // 0x1_xxxx → mtest
```

其它杂项端口：`usr_ref_type[1:0]` 选择刷新周期（`00=tREFI`,`01=tREFI/2`,`10=tREFI/4`,`11=用户模式`）；用户模式下把 `usr_ref_req` 拉高 ≥1 个 dhi_clk，收到 1 拍 `usr_ref_ack` 表示刷新完成（IPUG034 表 2-19 + §2.3.4）。例程把这些与 `ecc_err_*`/`ctl_ram_*` 全部留空不连（`ddrmc_test_top.v:100-140` 的例化里没有这些端口）——**"留空是否安全"未确认**（`ctl_ram_rst_n/ctl_ram_cke` 是两个输出，且 IP 参数里 `GEN_ECC_EN=1 / PH1P_ECC_EN=0 / MC_ECC=OFF`）。

---

## 3. 最小 bring-up 设计（设计说明，**不含 RTL**）

### 3.1 目标 / 范围

- 阶段 1（本次要落地的"最小"）：DDR 起来 → 写图案 → 读回 → 比对 → 结果放进 **PCIe BAR0 可见的寄存器** → 主机（RK3588）能读到"通过/失败/错比特/校准状态"。
- 阶段 2（本次只留接口，不实现）：整帧（4K 灰度 8.29 MB）进 DDR 帧缓存 + DDR→PCIe MWr 推给主机。
- 非目标：不改动现有相机/PCIe 通路行为；不删除现有 ERAM 帧缓存（但阶段 2 会需要它让位，见 §4.8）。

### 3.2 文件规划（**待调用方放行后才动手**）

| 动作 | 路径 | 说明 |
|---|---|---|
| 拷 | `al_ip/ddrmc_x32/`（整目录 52 文件） | 来源 `/mnt/nvme/.../work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/prj_src/ip/ddrmc_x32/`（= 官方 zip 原件）。**不要拷 `sim/`** 也行，但保留无害 |
| 新增 | `rtl/ep_side/ddr/ddr_selftest_engine.v` | dhi_clk 域：图案生成 + PAXI 主机 + 读回比对（≈250 行；照 `mtest/paxi_stg_cmd_gen.v` + `data_gen.v` + `data_check.v` 的思路重写，但 base/len 可配） |
| 新增 | `rtl/ep_side/ddr/ddr_cfg_apb_master.v` | cfg_clk(50 M) 域：把我们 UBUS 的一小段地址翻译成 APB（读 `0x3004` 校准状态 / mtest 内部寄存器） |
| 新增 | `rtl/ep_side/ddr/ddr_status_cdc.v` | dhi_clk/cfg_clk → tl_clk_user 的 toggle 握手 CDC，搬一个 status 快照（复用工程里已有的 `pulse2toggle.v`/`clk_activity.v` 写法） |
| 新增 | `rtl/ep_side/ddr/ddr_status_regs.v` | tl_clk_user 域：UBUS slave，只读/读写几个寄存器（照 `img_regs.v` 的 UBUS 时序协议） |
| 新增 | `constraints/ddr3_f9p_x32.adc` | 只放**非 DDR 引脚**的东西（sys_rst_n、LED 等）；**DDR 管脚一律不写**（见 §3.4） |
| 改 | `create_project.tcl` | `add_files` 增 4 行 RTL + `add_files constraints/ddr3_f9p_x32.adc` + `add_files al_ip/ddrmc_x32/ddrmc_x32.xml` |
| 改 | `constraints/ph1p_pcie_case_ep.sdc` | 增异步时钟组（见 §3.4） |
| 新增 | `sim_do/tb_ddr_selftest.v` | 测试台**只写不跑**（本机无仿真器） |
| 不动 | `constraints/ph1p_pcie_case_ep.adc:17`（sys_clk H4 SSTL135） | **必须保留**，它就是 DDR refclk 的引脚约束 |

### 3.3 IP 参数：两套口径 + 推荐

| 参数（GUI 名 / `.params` 名） | 例程（=照抄） | **推荐（800 Mbps 口径）** | 依据 |
|---|---|---|---|
| DDR Type | DDR3 | DDR3 | 板上是 DDR3L 颗粒 |
| RefClk Freq | 50.0000 | 50.0000 | 板上只有一颗 50 MHz（见 §3.4/H4） |
| **DDR Speed** | **1600.00** | **800.00** | 芯片数据手册表 3-60/表 1-2：PH1P100 DDR3 = **800 Mbps** |
| DQ Bytes | 4 | 4 | 32 bit / 8 |
| IO Voltage | 1.35 | 1.35 | 板卡手册：`SSTL135`、DDR3L |
| Vref Type | Internal | Internal | 例程口径 |
| Type / Density | x16 / 2048 | x16 / 2048 | 颗粒 = 128 Mb×16 = 2 Gb × 2 片 = 512 MB |
| Speed Bin | DDR3-1600K | **DDR3-800D**（或 800E） | 800 Mbps → tCK 2.5 ns；800D → CL5/CWL5，**JEDEC 合法** |
| CWL | 5（**默认值，未被人点过**） | 5 | 数据手册：CL=5 时 CWL=5 @ tCK 2.5–3.3 ns ✅；**1600/CL11 时 CWL 必须是 8，填 5 是 Reserved** ❌ |
| CI/Address Map | ROW_COL_BANK | ROW_COL_BANK | 与例程一致，线性寻址结论见 §2.3 |
| AXI Interface | 不勾（PAXI） | 不勾（PAXI） | 例程口径；PAXI 更简单（无 ID/len/burst 要管） |
| ECC | 关 | 关 | 例程口径（开 ECC 会吃掉 1 个 DQ byte） |
| Training / Board Delay | 勾 Training，Byte0-8 不单独配 | 同 | IPUG034 §3.1.2「使能 Training 则 Byte0-Byte8 无需单独的 Board Delay 配置」 |
| RefClk Type / RefClk Location | SINGLE / H4 | SINGLE / H4 | 见 §3.4 |
| ADC File Path | golden adc（F9P 球号） | 同一个文件即可 | §1.6 |

**为什么推荐 800 而不是照抄 1600**（三条都指向同一处）：
1. **器件口径**：`DS1300_PH1P_Datasheet_1.2.1.pdf` 表 3-60「External Memory Interface 性能」：PH1P100 / DDR3 / **800** Mbps；表 1-2「PH1P FPGA 封装」PH1P100SBG484 行同样是 800 Mbps。板卡手册也写「数据带宽 800Mbps*32bit」。
2. **颗粒口径**：`DS-00843-GDP1BFLM-Rev1.0.pdf` 表 11-2：CL=11 时 **CWL=8** 且 tCK∈[1.25,1.5)ns；CWL=5/6/7 标注 **Reserved**。例程那版是 CL=11 + CWL=5 → **颗粒侧非法组合**。
3. **集成难度**：800 Mbps → `dhi_clk` 只有 100 MHz（PCIE 侧用户时钟才 62.5 MHz），我们这边的 CDC/时序收敛压力小一半；带宽 3.2 GB/s 仍是 PCIe Gen2×2（≈1 GB/s 量级）的 3 倍，**根本不是瓶颈**。

（`GDP1BFLM-CB` 颗粒本身是 DDR3L-1866 CL13-13-13，见该 datasheet §2 ORDERING INFORMATION「GDP1BFLM-CB  128Mb x16  1866Mbps  13-13-13」——所以 1600 不是"颗粒不行"，而是"FPGA 侧口径 + CWL 配置"的问题。）

### 3.4 约束（引脚 / 时钟 / 时序）

**(1) 引脚：DDR 管脚不用我们写，但必须"直连"**

IP 自带的 `src/adc/ddrmc_x32.adc` 用的是 `set_ippin_assignment`（**IP 引脚**约束），例程的顶层 adc（`prj_src/adc/ap115v2.adc`，18 行）里**一条 `ddr_*` 都没有**——说明 TD 是从 IP 引脚约束导出顶层管脚的。由此得到一条硬性设计规则：

> **DDR 的 `ddr_*` 信号必须从 IP 实例直连到顶层端口，中间不许插任何逻辑**（不能插 ILA、mux、IBUF、电平转换）。顶层端口名/位宽要与 IP 一致：
> `ddr_ck_p/ddr_ck_n/ddr_reset_n/ddr_cke[0]/ddr_odt[0]/ddr_cs_n[0]/ddr_ras_n[0]/ddr_cas_n[0]/ddr_we_n[0]/ddr_ba[2:0]/ddr_addr[13:0]/ddr_dqs_p[3:0]/ddr_dqs_n[3:0]/ddr_dq[31:0]/ddr_dm[3:0]`
> （例程顶层 `example_top.v:25-39` 就是这么摆的；注意它把 `ddr_ck_p` 写成**标量**，而 ADC 里写的是 `ddr_ck_p[0]`——TD 接受这种写法，照抄即可。）
>
> **"IP 引脚约束是否一定会派生顶层管脚"这一点在 TD 文档里没找到定义（SWUG105 全文没有 `set_ippin_assignment`）→ 未确认**，但例程事实如此。

**(2) sys_clk / H4 / DDR refclk：结论是"共享"，不是"抢脚"**

- 板上只有一颗 50 MHz 单端时钟，球号 **H4**（板卡手册「时钟输入 50MHZ 单端时钟*1」；`ap115v2.adc:4` 与我们的 `ph1p_pcie_case_ep.adc:17` 都写 H4 + SSTL135）。
- H4 在 **BANK33**（= DDR 的 AC bank）：`PH1P100SBG484.csv:262 = "H4 ,5 ,2 ,0 ,Y"`；IP 生成时记录的 refclk 就是它（`ddrmc_x32_adc.log:71 = "refclks,5,2,0,"`），IP 参数 `PH1P_SYSCLK_LOC=H4`、`PH1P_REFCLK_TYPE=SINGLE`、`PH1P_PLL_LOC=BANK33`（`Design.xml:94-97`）。
- 但 **IP 自己不给 refclk 写引脚约束**（`src/adc/ddrmc_x32.adc` 里 `refclk` 出现 **0** 次；golden adc 里第 21-22 行的 `ref_clk_p=H4 / ref_clk_n=J4` 是**注释掉的**）。IP 的 `ref_clk` 就是一个普通输入端口（`ddrmc_x32.v:14`）。
- 现状：我们的工程把 H4 上的 `sys_clk` 送给了 `u_pcie_pll_ep.refclk`（`rtl/ep_side/ph1p_pcie_ep_top.v:243-247`）。

→ **做法**：顶层只保留一个 `sys_clk` 输入端口，一条引脚约束，把**同一个网络**同时接到
`u_pcie_pll_ep.refclk` 和 `u_ddrmc_x32.ref_clk`（DDR IP 的 PLL0 在 BANK33、与 H4 同 bank，正好符合 IPUG034「推荐与 AC 信号在同一 Bank」）。

→ **要注意的风险**：IPUG034 §2.1.3 提醒经"内部全局时钟网络"时「可能由于 PLL 级联造成系统性能下降」；而且现在这条时钟要带 3 个 PLL（PCIe 用户 PLL + DDR PLL0 + DDR PLL1）。**是否会被 TD 判 DRC 警告、是否需要给 DDR 单独走 IOCLK 直连 —— 未确认**（必须实配一次看 place 报告）。备用方案：给 DDR 用 `PH1P_REFCLK_TYPE=BUFG`（即明确按全局时钟网走，不占用 DDR bank 的 refclk 位置）——但这需要重新生成 IP（改参数）。

**(3) 时钟/时序约束**

- `constraints/ph1p_pcie_case_ep.sdc:1` 的 `create_clock -period 20 -name sys_clk` **保持不动**（50 MHz，与 IP 的 `PH1P_REF_CLK=50` 一致；例程 `prj_src/sdc/ap115v2.sdc:2` 也是 period 20）。
- IP 自带 `src/sdc/ddrmc_x32.sdc`（8 行）已经做了：`derive_clocks`、把 PLL0 的 `clkc[0..3]` 重命名为 `ref_clk/ctl_clk/ddr_clk/mcu_clk`、把 PLL1 的 `clkc[0]` 重命名为 `usr_clk`，以及 `set_clock_groups -asynchronous -group [get_clocks mcu_clk]`。
- **我们必须在顶层 SDC 里把 `usr_clk`（= dhi_clk）并进已有的异步组**，否则 STA 会拿 5 ns 的 dhi_clk 与 16 ns 的 tl_clk_user 当同步时钟去算，必然假违规（这和之前相机字节时钟踩过的坑是同一类；见 `constraints/ph1p_pcie_case_ep.sdc:29-32` 的注释）。建议：
  ```tcl
  set_clock_groups -asynchronous \
      -group [get_clocks {tl_clk_user sys_clk}] \
      -group [get_clocks {usr_clk ctl_clk ddr_clk mcu_clk}] \
      -group [get_clocks {cam_a_clk_lane cam_a_byte_clk}] \
      -group [get_clocks {cam_b_clk_lane cam_b_byte_clk}]
  ```
  （**具体时钟名要等第一次 `report_clocks`/`all_clocks` 打印出来核对**——`usr_clk` 是 IP sdc 里 `rename_clock` 后的名字，未实测。）
- `sys_rst_n` 不需要额外 SDC（异步复位）。

### 3.5 自检通路模块划分

```
                    ┌──────────────── 现有工程（tl_clk_user 62.5MHz）───────────────┐
 RK3588 ⇄ PCIe ⇄ ep_ubus_bridge ──ubus_*_logic──┬── img_regs（原有）
                                                └── ddr_status_regs（新）  ←── CDC ──┐
                    └──────────────────────────────────────────────────────────────┘   │
                                                                        ddr_status_cdc │(toggle 握手)
   ┌──────── dhi_clk 域（1600 配置 200MHz / 800 配置 100MHz）────────┐                  │
   │  ddr_selftest_engine  ⇄ paxi_* ⇄  ddrmc_x32                    │ ←── status 快照 ─┘
   │   ├ 图案生成(LFSR/固定图样)  ├ 写序列  ├ 读序列  ├ 逐字节比对  │
   │   └ ERR_CNT / RD_CNT / 首个错拍地址+期望值+实际值              │
   └────────────────────────────────────────────────────────────────┘
   ┌──────── cfg_clk 域（50MHz）────────┐
   │  ddr_cfg_apb_master → apb_* → IP   │  读 16'h3004 校准状态、0x3000 step
   └────────────────────────────────────┘
```

| 模块 | 时钟域 | 职责 | 参考/来源 |
|---|---|---|---|
| `ddr_selftest_engine` | dhi_clk | 产图案、发 PAXI 写/读、比对、计数 | 照抄思路：`mtest/paxi_stg_cmd_gen.v`（FSM + 线性地址）、`data_gen.v`（LFSR/图样）、`data_check.v`（逐字节比对 + 首错锁存） |
| `ddr_cfg_apb_master` | cfg_clk | 读 DDRPHY APB 的 CAL 状态（`0x3000/0x3004`），转成 32 bit 快照 | IPUG034 §2.4.4 表 2-25 |
| `ddr_status_cdc` | dhi_clk/cfg_clk → tl_clk_user | 把 status 快照搬过界 | 复用工程既有 `rtl/ep_side/cam/pulse2toggle.v` 的 toggle 握手风格 |
| `ddr_status_regs` | tl_clk_user | UBUS slave，暴露给主机 | 照 `rtl/ep_side/img/img_regs.v` 的 UBUS 时序（ren→1 拍→bken 同拍 rdata） |

**为什么自己写而不是直接搬 `mtest`**：`mtest` 的测试范围是**写死的 256 拍 = 8 KB**（`paxi_stg_cmd_gen.v:38 localparam NUM_TRANS = 256`，地址从 0 起），只能证明"能读写一小块"，做不了整帧（259,200 拍）的验证。阶段 1 先照 8 KB 做（最省事），阶段 2 换成 base/len 可配版本。

### 3.6 寄存器映射（主机侧看到的）

沿用工程现有约定：`ep_ubus_bridge` 把 `waddr/raddr[31:24]==8'hFF` 的访问送到逻辑侧，逻辑侧再按低字节索引（`img_regs.v` 用了 `0x40~0x7F`，`ep_bar_win.v` 用了 `0x74~0x9C` —— **先核对现有解码区间，别撞地址**）。建议新开一段（例如 `0xA0~0xCF`）：

| 偏移 | 名 | R/W | 含义 |
|---|---|---|---|
| `0xA0` | DDR_MAGIC | R | 固定魔数（探测本模块是否被综合进去） |
| `0xA4` | DDR_STATUS | R | bit0 = `ddrphy_rdy`（cal_done）；bit1 = selftest done；bit2 = selftest error；bit3 = APB 访问完成；bit4 = cal_err 非零 |
| `0xA8` | DDR_CAL | R | {cal_err[7:0], cal_done[7:0], cal_step[7:0], 8'h0}（APB `0x3004`/`0x3000` 原样） |
| `0xAC` | DDR_ERR_CNT | R | 比对错误字节数 |
| `0xB0` | DDR_RD_CNT | R | 完成的读拍数 |
| `0xB4` | DDR_ERR_ADDR | R | 首次出错的 32 B 拍序号（= PAXI 地址>>3） |
| `0xB8/0xBC` | DDR_ERR_EXP/ACT | R | 首次出错时的期望/实际 256 bit 的 32 bit 切片（配一个 slice 选择寄存器） |
| `0xC0` | DDR_TEST_CTRL | R/W | bit0 = 启动一次性自检；bit1 = 目标速率档位标志（0=800/1=1600）；写 1 自清 |
| `0xC4/0xC8` | DDR_BASE/DDR_LEN | R/W | 阶段 2 用：帧缓存基址（拍）与长度（拍） |
| `0xCC` | DDR_VERSION | R | 模块版本 |

**跨域细节**：`ddrphy_rdy`、`ddr_err_cnt` 等都在 dhi_clk/cfg_clk 域，必须经 toggle 握手（或异步 FIFO，工程里已有 `sfifo.v/wfifo.v`）过到 `tl_clk_user`；`DDR_TEST_CTRL` 的启动脉冲反向也要过界。**不要**用简单的两级同步器直接搬多比特总线（会撕）。

### 3.7 上电 / 复位 / 校准流程

```
配置完成 → sys_rst_n 释放 → IP PLL0/PLL1 lock → DDRPHY 初始化(MRS/RESET/CKE) → 训练(WRLVL/GATE/WLA)
   → ddrphy_rdy=1（cal_done）  ← 此时才能发第一次 PAXI 访问
   → selftest: 写 N 拍图案 → 读回 → 比对 → 锁存 status → 拉高 done/err
   → 主机读 BAR0 0xA4/0xAC 判读
```

- **复位来源建议**：`sys_rst_n` = 外部 `pcie_power_on_rst`（板上 SW7/R14，我们 ADC 里已有）+ 一个"配置后延迟释放"的计数复位（保证每次下载完 bitstream 都有一段确定长度的低电平）。这和 PCIe 侧"要重新枚举"不是一回事——**DDR 不需要重启主机、也不需要重新下载后再重启**。
- **"下载后重启"问题的回答**：DDR 不需要。但要注意两点：
  1. `ddr_reset_n` 是 IP 输出的（`EN_RST_PORT=1/GEN_RESET=1`，`.params:84/139`），颗粒复位由 IP 自己管；对 FPGA 而言只要 `sys_rst_n` 释放就会重跑初始化+训练（**训练耗时未实测**，参考量级：IP 里的 FIU 延时链校准计数 `nDLY = 400e6/tCK/4`（`ph1p_ddrphy_wrapper_ddrmc_x32.v:141-145`），1600 配置下 = 80,000 拍 ≈ 0.4 ms @200MHz，加上 WRLVL/GATE/WLA，估计**亚毫秒～毫秒量级**）。
  2. **IPUG034 §3.3.3「Training 期间注意事项」全文只有一句：「在 Training 期间，系统设计应尽量减少系统噪声。」** —— 也就是说训练期间**不要让相机/PCIe 高速接口同时满速跑**。对我们的现实意义：bring-up 第一步应先只验 DDR（相机空闲），别一上来就三路并发。
- **最小复位脉宽要求：IPUG034 未写 → 未确认。**

### 3.8 阶段 2：4K 帧缓存 + PCIe MWr（本次只做核算与接口预留）

**容量核算**（4K 灰度：3840×2160 = 8,294,400 B = 8.29 MB）：

| 项 | 数值 |
|---|---|
| 一帧 | 8.29 MB = **259,200 拍**（32 B/拍） |
| 512 MB DDR3 | 16,777,216 拍 |
| 能放几帧 | ≈ 61 帧 |
| 一拍对齐：一帧放进 **2^18 拍（8 MiB）** 的槽位即可（259,200 < 262,144） | 乒乓槽 = 拍 0 与拍 2^18 |
| PAXI 地址 | `slot_base[23:0] << 3 | beat_in_slot << 3`，即 `{beat_index[23:0], 3'b000}` |
| 带宽（保守 800 Mbps） | 3.2 GB/s → 写一帧理论 2.59 ms |
| 带宽（IP 实配 1600 Mbps） | 6.4 GB/s → 理论 1.30 ms |
| PCIe Gen2×2 上限 | ≈1 GB/s 量级 → 一帧约 8.3 ms |
| **结论** | **DDR 不是瓶颈，PCIe 才是**（DDR 比 PCIe 宽 3~6 倍）；帧率上限由 PCIe 决定，≈100 fps 量级 |

**接口预留**：DDR 侧只需要 `DDR_BASE/DDR_LEN` 两个寄存器（§3.6），让"谁写帧、写哪"可被主机配置；`DDR→PCIe MWr` 的发起者（TLP 生成）**现有工程里没有**（`pcie_ep_engine.v` 里的 `memwr_flag` 只是让 EP 回 completion，不是通用 MWr 主机）→ 阶段 2 需要新写一个 TX 引擎（`tl_tx_data/tl_tx_sop/tl_tx_eop/tl_tx_valid/tl_tx_wait/tl_tx_credits` 这些信号在 `ph1p_pcie_ep_top.v:161-168` 已经引出）。**这部分与 DDR bring-up 解耦，可以并行推进。**

### 3.9 与现有工程集成时要注意的冲突/坑（逐条）

| # | 事项 | 结论 / 注意 |
|---|---|---|
| 1 | **H4 / sys_clk** | **不冲突**：IP 不占引脚，只需把同一个 `sys_clk` 网络再送给 `ref_clk`。保留 `ph1p_pcie_case_ep.adc:17` 不动。风险：一条时钟带 3 个 PLL 是否被判 DRC/是否需要 IOCLK 直连 → 实配才能知道 |
| 2 | **Bank 划分** | DDR 占 **BANK32（DQ×4 byte）+ BANK33（AC/CLK/refclk）**；相机全在 **BANK13**；PCIe 在 **BANK94（HXT）+ BANK12**。三组球号两两不相交（本次又用 `_adc.log` 的 bank 列 + `PH1P100SBG484.csv` 独立复核了一遍）→ **零冲突** |
| 3 | **时钟树资源** | 现有占用（`ph1p_pcie_ep_top_phy.area`）：`#pll 1/12`、`#gclk 4/32`、`#ioclk 0/24`、`#mlclk 0/24`、`#lclk 2/24`。DDR IP 需要（09 例程实测）：`#pll 2`、`#gclk 3`、`#ioclk 4`、`#mlclk 2`、`#ddr_byte 7`。合计约 `pll 3/12`、`gclk 7/32`、`ioclk 4/24`、`mlclk 2/24` → **都够** |
| 4 | **ERAM** | 现在 `#eram 124/300 = 41.33%`（其中 640×480 帧缓存约 120 块）。**DDR IP 自己还要吃 41 块 ERAM20K**（09 例程 = 41/300）。若不动现有帧缓存，合计 ≈165/300（55%）——**能过但很紧**。阶段 2 把整帧搬去 DDR 后，应同时**删掉 `img_frame_src` 的 640×480 大数组**，ERAM 反而降到 ~45/300 |
| 5 | **逻辑资源** | 09 例程整工程（含 mtest + USR MCU + UART）= `#lut6 10607 (14.8%)`、`#slice 15377 (21.45%)`、`#reg 19223 (13.41%)`；我们现有 = `#lut6 3278`、`#slice 3703 (5.17%)`。总量有充裕余量（但 IP 本体与 mtest 各占多少**未单独测量**） |
| 6 | **Import Device** | 必须 `import_device ph1_100p.db -package PH1P100SBG484 -speed 3`（`build.tcl:9` 已有）。例程 `.al` 的 `<Speed>-3</Speed>`、Catalog 的 deviceRegexp 都含 PH1P100SBG484 → 一致 |
| 7 | **al_ip 注册方式** | 只需 `add_files al_ip/ddrmc_x32/ddrmc_x32.xml`（与现有 `al_ip/pcie_ep_core/pcie_ep_core.xml` 完全同构）。**不要勾 Copy sources into project**。注意 `.al` 里的路径是相对工程根的 |
| 8 | **`.al` 会被静默重写** | 已在别的工程踩过：`create_ip` 会重写 `.al` 并可能删掉已有 `<IP_FILE>` 条目。动手前先备份 `.al` |
| 9 | **IP/工具版本** | IP 是 6.2.2(190657)/IpTool 189136 生成的，本机是 6.2.3(210850)。**先例**：我们现在的 `al_ip/pcie_ep_core` 是 IpTool 171484 生成的，在 210850 下正常编译 → 版本差**不必然**触发升级。但 TD/IpTool 里确实有 `ip_upgrade`/`report_ip_status`/`{} be locked, please upgrade it before generate` 这些机制 → 打开工程后**先看有没有 IP 状态告警**，必要时 `report_ip_status` / `ip_upgrade`，或直接 GUI 里点升级 |
| 10 | **`ddr_*` 必须直连** | 见 §3.4(1)；这是最容易写错、且报错信息不友好的地方 |
| 11 | **加密的 MC** | `src/rtl/mc/mc0_alc_mc_top_all.enc.sv` 是加密 SV，工程里已有加密源先例（`rtl/rc_side/si5344_5345/soft_mcu/AHB_Core.enc.v`）→ 应该能读，但**不要去改它** |
| 12 | **现有相机的 CDC 习惯** | 我们的相机链路已经用 toggle 握手过时钟域（`pulse2toggle.v`/`clk_activity.v`）——DDR 状态回传照这个做，不要新引入"多比特直接打两拍"的写法 |
| 13 | **别把 DDR 状态寄存器塞进 `img_regs`** | `img_regs` 有自己的地址段与 `hit_dly/bken` 仲裁，硬塞容易撞地址；新开模块更干净 |

### 3.10 分阶段落地与验收判据（每步可独立回退）

| 步 | 做什么 | 通过判据 | 失败退路 |
|---|---|---|---|
| S0 | 拷 IP 目录 + `add_files` 登记 + 顶层例化（DDR 引脚直连、`ref_clk=sys_clk`、`sys_rst_n=复位`），用户侧逻辑先**什么都不接** | `syn_1`/`phy_1` 跑完，**无 `HDL-8007` 黑盒**、引脚分配与 `_adc.log` 一致（看 place 的 `Detailed IO Report`）、DRC 无 DDR 相关 error | 若报 IP 锁定/版本 → 走 `ip_upgrade` 或 GUI 升级；若报引脚冲突 → 回到 §3.4 |
| S1 | 加 `ddr_selftest_engine` + status CDC + 寄存器；先在最保守的 800 Mbps 或照抄 1600（见 §3.3）下跑 8 KB 图案 | 主机读 `0xA4`：`ddrphy_rdy=1` 且 selftest error=0；`0xAC` 错误计数=0 | 若 `ddrphy_rdy` 一直 0 → 读 `0x3004` 看 cal_done/cal_err 定位哪一段训练失败；若 err 非 0 → 先试 `paxi_wstrb` 全 1/全 0（§2.3(2)），再考虑 board delay / ODT / 降速率 |
| S2 | 把测试长度扩到**整帧 259,200 拍**（base/len 可配） | 8.29 MB 全写全读比对 0 错；测读带宽（`RD_CNT`/时间） | 若只在长突发下错 → 怀疑刷新/重排（`PH1P_MC_REORDER`）、温度/噪声（IPUG034 §3.3.3） |
| S3 | 接真实相机流 + 乒乓帧缓存 | 帧号与帧内容校验（复用现有 `img_regs` 的帧校验思路） | — |
| S4 | DDR→PCIe MWr | 主机侧 `memcmp` 整帧一致 | — |

---

## 4. 风险与未确认项

| # | 项 | 等级 | 现状 / 证据 | 怎么销掉 |
|---|---|---|---|---|
| R1 | **例程那版 1600 配置的 CWL=5 不是 JEDEC 合法组合**（CL=11 要求 CWL=8） | 🔴 高 | `.m_params:23 CWL;1;5`、`Design.xml:77-78 (CL=11, CWL=5)`、`ddr3_parameter.vh:127-132 (DDR3_1600K→CL=11)`、`init/ph1p_ddrphy_dram_init.v:81,93 (MR2_CWL=CWL-5)`；颗粒手册表 11-2：CL=11 → CWL=8 @tCK 1.25–1.5ns，CWL=5/6/7 = Reserved；`ipgen.log` 证明 CWL 没被人改过（默认值） | ① 重新生成 800 Mbps（CL5/CWL5 合法，推荐）；② 或 1600 下把 CWL 显式设成 8；③ 直接问米联客/安路 |
| R2 | **`generate_target` 批处理不产 RTL**（对 DDR IP 未实测，但同机制 IP 有实测反例） | 🔴 高 | `f9p_ph1p100_imx415x2/README.md:167-168`（MIPI_DPHY 实测 rc=1 + `HDL-8007`）+ `gen_ip.tcl:33-36`；TD/IpTool 里有 `dose not support batch mode` 分支 | 放行一次 headless `create_ip`+`generate_target` 实验（§1.8），或在 GUI 里生成 |
| R3 | **1600 Mbps 是否在实板上真的可用**（"三处口径"的核心） | 🔴 高 | 例程已编译出 bit（`prj_td/ph1p_ddr_Runs/best_result/ph1p_ddr.bit`，2026-05-22）且 `bw` 日志显示 2026-04-30 连过一次编程器（`prj_td/log/bw_2026-04-30_10-33-11.log`，只有 connect/close，**没有任何下载/测试结果**）→ **是否上板跑通，未确认** | 上板跑 mtest；或问原厂 |
| R4 | **`paxi_wstrb` 极性**：文档说高有效，例程恒置 0 | 🟡 中 | IPUG034 表 2-10 vs `ph1p_ddrmc_mtest.v:436-438` | S1 里两种极性各测一次（1 行代码） |
| R5 | **一个时钟网络同时喂 3 个 PLL** 的 DRC/时序影响 | 🟡 中 | IPUG034 §2.1.3 关于"全局时钟网络/PLL 级联"的提醒；当前 `sys_clk` 已喂 PCIe PLL（`ph1p_pcie_ep_top.v:243`） | 实配后看 place/DRC 报告；退路 = `PH1P_REFCLK_TYPE=BUFG` 重新生成 |
| R6 | **`ddr_*` 是否必须从 IP 直连顶层**（IP 引脚约束派生顶层管脚的机制未在文档定义） | 🟡 中 | 例程事实（顶层 adc 无一条 `ddr_*`；`src/adc` 用 `set_ippin_assignment`），但 SWUG105 无该命令定义 | 直接在工程里试一次；若报"找不到 pin"就手写 `set_pin_assignment` 兜底 |
| R7 | **训练耗时 / 最小复位脉宽未定** | 🟡 中 | IPUG034 未写；只能从 `nDLY=400e6/tCK/4` 估 ~0.4 ms 量级 | 上板用 `ddrphy_rdy` 到复位释放的间隔实测（加计数器寄存到 status 里） |
| R8 | **IP 版本 189136 vs 本机 210850 是否触发升级/锁定** | 🟡 中 | `DesignConfiguration.xml:13`；TD/IpTool 有 `ip_upgrade`/`locked` 机制；反例：`pcie_ep_core`（171484）在本机正常 | 打开工程看告警；必要时 `report_ip_status` |
| R9 | **`ctl_ram_rst_n/ctl_ram_cke/ecc_err_*/usr_ref_*` 留空是否安全** | 🟡 中 | 例程留空不连（`ddrmc_test_top.v:100-140`），但 IP 有这些端口（`ddrmc_x32.v:45-51`）；`PH1P_ECC_EN=0` | 照例程先留空；若 DRC 报错再按 IPUG034 §2.3.4 接刷新/ECC |
| R10 | **32 B 拍内字节布局与帧缓存线性假设** | 🟢 低 | 由 IPUG034 表 2-4/2-8 + `mtest` 重排代码推断，**未实测** | S1 的环回自检天然规避（读写同规则）；真帧阶段再做一次"已知图样 → 主机读 DDR 原始内容"的对齐验证 |
| R11 | **ERAM 余量**（IP 自带 41 块 + 现有 640×480 帧缓存 120 块） | 🟢 低 | 09 例程 `#eram 41/300`；我们 `#eram 124/300` | 阶段 2 删掉片内整帧缓存即可 |
| R12 | 例程 IP 归属/许可证 | 🟢 低 | IP 属安路官方 IP（`Catalog.xml` `supportedLicense=included`）；例程随板卡包提供 | — |
| U1 | `ipgen.log` 里 800/1333 的尝试是否留下过可用产物 | — | 只有最后一次（1600）写进 `#GUI-2000` 成功日志；前几次没有成功行 | 无需销 |
| U2 | 板卡手册标注的 `DDR3L_A14 = J5` 与 IP 的 `ddr_addr[13:0]` 不一致 | — | 硬件手册 DDR 表有 `DDR3L_A14 J5`；golden adc 也写了 `ddr_addr[14]`，但 IP `ADR_WIDTH=14`、生成的 `src/adc` 里**没有** A14 | 属 4 Gb 颗粒的备用引脚；本设计按 2 Gb（14 行地址）用，不影响。**未确认**是否需要在 adc 里注释掉 J5 |

---

## 5. 证据索引（路径 : 行）

**TD 工具与文档**
- `/opt/anlogic/TD_Release_2026.2_NL/doc/SWUG/SWUG105_TCL_Command_User_Guide.pdf` §4.4（p.38-40）IP flow 命令：`create_ip` / `get_ipdefs` / `get_ips` / `generate_target` / `load_project_ips` / `close_project_ips`
- `/opt/anlogic/TD_Release_2026.2_NL/doc/IPUG/IPUG034_PH1P_MIS_IP_Guide.pdf`：§1.1 特性（BL8、x8/x16、DQ 8~72bit）；§2.1.3 时钟结构（PLL0/PLL1、ref_clk 抖动<25ps、同 Bank 建议）；§2.3.1 表 2-10 接口表（含 paxi_wstrb"高电平有效"）；§2.3.2.1 表 2-12 DDR3 地址映射；§2.3.3.2 pAXI 时序（读写不能同时发）；§2.3.4 表 2-19 刷新模式；§2.4.1 表 2-20 APB 地址映射；§2.4.4 表 2-25 CAL APB；§3.1 GUI 定制步骤；§3.2 IP 输出文件；§3.3.1 IO 管脚分配规则；§3.3.3 Training 注意事项
- `/opt/anlogic/TD_Release_2026.2_NL/ip/depot/Catalog.xml:1005-1016` MIS_DDRF6F1D0P0 v1.2 条目（deviceRegexp 含 PH1P100SBG484、**无 customTool**）；同文件 53 条带 `customTool=use_host` 的 IP
- `/opt/anlogic/TD_Release_2026.2_NL/ip/depot/MIS_DDRF6F1D0P0_1.2/`：`Component.xml`（4757 行，ipxact 参数表 + macros）、`Dependency.tcl`（2681 行，`set_param` 依赖表在 1-153 行，`update_pll` 926-1122，`drc_check` 1122+，`update_sysclk_loc` 2404）、`Layout.tcl`（GUI 布局与 tooltip，如 181 行 refclk type 用法）、`PH1P_DDRMC_IP/Other/plugin_end.tcl`（生成流水线：gen_file/gen_adc/gen_sdc/gen_define/gen_boardly/…）、`PH1P_DDRMC_IP/Other/upgrade.tcl`（`report_ip_status`/`upgrade_ip`，IP 版本 1.2.0）
- `/opt/anlogic/TD_Release_2026.2_NL/ip/depot/MIS_DDRF6F1D0P0_1.2/PH1P_DDRPHY_IP/Other/ph1p_ddrphy_ip/pkg/cfg.csv`（`PH1P100SBG484` 行 = `BANK11_0+BANK12_1+BANK13_2+BANK14_3+BANK32_4+BANK33_5`）、同目录 `PH1P100SBG484.csv:262`（`H4,5,2,0,Y`）
- 二进制字符串（只读 `strings`）：`/opt/anlogic/TD_Release_2026.2_NL/bin/td`（`create_ip -vlnv`/`set_property`/`xmlipgen`/`ip_upgrade`/`report_ip_status`/`component/vendorExtensions/customTool/`/`' dose not support batch mode`）；`/opt/anlogic/TD_Release_2026.2_NL/bin/IpTool`（`aliptIpgenRegisterBatchCmds`/`CMD_BATCH_*`/`gIpGenBatchMode`/`ipst_upgrade`）

**09 例程（= F9P 官方包原件，md5 已核对一致）**
- `/mnt/nvme/.../work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/prj_td/ph1p_ddr.al`（IP 登记 203-212，TOP `example_top`，Device/Speed 11-13，TD_Version 6）
- `.../prj_td/log/ipgen.log`（GUI 回放 18 行，第 18 行 `#GUI-2000 … PH1P100SBG484`）
- `.../prj_src/ip/ddrmc_x32/`：`ddrmc_x32.v:12-170`（端口 + 参数例化）、`.params_ddrmc_x32.txt`（1,4,5,6,7,12-14,17,21,27-31,74,105-116,117,119,121-124,135,139）、`.m_params_ddrmc_x32.txt`（tCK/CL/CWL/MC_DATA_WIDTH…）、`Design.xml:12-97`（生效参数）、`DesignConfiguration.xml:9,13`、`ph1p_ddrmc_wrapper_ddrmc_x32.v:25-70,87-160,340`、`src/rtl/include/ph1p_mis_define.vh:1-9`、`src/rtl/timing/ddr3/ddr3_parameter.vh:127-132`、`src/rtl/init/ph1p_ddrphy_dram_init.v:7,81,93`、`src/rtl/clk/ph1p_ddrphy_clk_top.v:135-138`、`src/rtl/top/ph1p_ddrmc_top.v:226-228,295-340`、`src/rtl/phy/ph1p_ddrphy_wphase_ctl.v:45`、`src/adc/ddrmc_x32.adc`（71 条球号 + 18 条站点）、`src/sdc/ddrmc_x32.sdc`（8 行）、`sim/fileset/fileset_mis.f`
- `.../prj_src/ip/ddrmc_x32_adc.log:1-71`（**bank 4 = DQ bytes、bank 5 = AC、第 71 行 refclks,5,2,0**）、`..._drc_check.log:1-9`、`..._proc.log:1-11`
- `.../golden_adc/ap115v2_ddr3_x32.adc:21-22`（refclk H4/J4 **被注释**）、`:24-51`（AC 含 `ddr_addr[14]=J5`）、`:53-103`（DQ/DQS/DM）
- `.../prj_src/adc/ap115v2.adc:3-17`（sys_clk H4 SSTL135 "100MHz" 注释为陈旧）、`.../prj_src/sdc/ap115v2.sdc:2`（period 20）
- `.../prj_src/rtl/top/example_top.v:6-39,57-103`、`top/ddrmc_test_top.v:48-63,100-176,199-222,240-262`、`mtest/ph1p_ddrmc_mtest.v:79-92,150-180,398-400,417-454,580-600`、`mtest/paxi_stg_cmd_gen.v:38,57-59,66-68`、`misc/mcu_rst_gen.v`
- `.../prj_td/ph1p_ddr_Runs/phy_1/place_clock_utilization.txt`（**usr_clk 5.000 ns、mcu_clk 20.000 ns**）、`route_clock_utilization.txt`、`ph1p_ddr_phy.area`（**#pll 2、#gclk 3、#ioclk 4、#mlclk 2、#eram 41、#ddr_byte 7、#lut6 10607、#slice 15377**）、`final_timing.rpt`（STA coverage 96.88%）、`ph1p_ddr_Runs/best_result/ph1p_ddr.bit`
- `.../prj_td/log/bw_2026-04-30_10-33-11.log`（只有 connect/close，无下载结果）

**F9P 板卡/芯片原始资料**
- `/mnt/nvme/fpga/TD/03_F9P_CA05_PH1P50_PH1P100/V2026/HW-MLK-F9P-CA05-PH1P100/02_hardware/HW-MLK-F9P-CA05-PH1P100.zip`
  - `…/01_硬件手册/米联客MLK-CA05-PH1P50-PH1P100核心模块硬件使用手册V1.0.pdf`：`时钟输入 50MHZ 单端时钟*1`；`2 片 DDR3L 数据带宽可达 800Mbps*32bit`；`DDR 型号 GDP1BFLM-CB / 单片 256MB / 片数 1/2`；`FPGA DDR 引脚分配表`（71 球号，与 golden adc 逐条一致）
  - `…/01_硬件手册/米联客MLK-F9P-CA05-PH1P50-PH1P100开发板硬件手册V1.0.pdf`：同一组参数 + DDR3 引脚表
  - `…/01_start/02_peripheral_demo/02_peripheral_demo.zip`：内含 `09_ddr3_ddrmc_cal_x32_1066mbps/`（与 work 目录同名文件 md5 一致）
- `/home/xiaozhu/Projects/.../fpga/doc/task3/实现方案_20261015.md`：§4.2/§5.1/§5.2（前一轮已核对过的板卡/器件资料索引，含 `DS1300` 表 3-60、`DS-00843` 等；本次复核为真）
- `/home/xiaozhu/Documents/HW-MLK-F9P-CA05-PH1P100_文档整理/05_芯片手册/01_FPGA/安路/DS1300_PH1P_Datasheet_1.2.1.pdf`：**表 1-2 PH1P FPGA 封装**（PH1P100SBG484 → DDR3 800 Mbps）、**表 3-60 External Memory Interface 性能**（PH1P100 / DDR3 / 800 Mbps）、§2.11 External Memory Interface（BL8、x8/x16、最大 72 bit）、§3.2.7.1 表 3-51（SSTL135 输入 800 Mbps）
- `/home/xiaozhu/Documents/HW-MLK-F9P-CA05-PH1P100_文档整理/05_芯片手册/03_DDR/DS-00843-GDP1BFLM-Rev1.0.pdf`：§2 ORDERING INFORMATION（`GDP1BFLM-CB 128Mb x16 1866Mbps 13-13-13`）、**表 11-2**（CL=11 → CWL=8 @ tCK 1.25–1.5 ns；CWL=5/6/7 为 Reserved）、§11.3 标准速度分级

**本机实测先例（别的工程）**
- `/home/xiaozhu/Projects/f9p_ph1p100_imx415x2/README.md:163-173`（`create_ip`/`set_property` 可用、参数顺序反 Vivado、`load_project_ips` 必需、**`generate_target` 批处理不产 RTL**、`.al` 被静默重写的坑）
- `/home/xiaozhu/Projects/f9p_ph1p100_imx415x2/gen_ip.tcl:1-39`（实际脚本：`import_device`→`open_project`→`load_project_ips`→`set_property <值> CONFIG.xxx $ip`→`generate_target all $ip`）

**本工程现状（集成基线）**
- `ph1p_pcie_ep_top.al:5`（TD_Version 6.2.3.210850）、`build.tcl:9`（import_device 行）、`create_project.tcl:41-43`（al_ip 注册方式）
- `constraints/ph1p_pcie_case_ep.adc:17`（sys_clk H4 SSTL135）、`:34-61`（相机 BANK13/18 脚）、`constraints/ph1p_pcie_case_ep.sdc:1-3,18-32`（现有时钟与异步组）
- `rtl/ep_side/ph1p_pcie_ep_top.v:243-247`（`sys_clk → u_pcie_pll_ep.refclk`）、`:161-168`（tl_tx_* 引出）、`:515-585`（ep_ubus_bridge / UBUS 逻辑侧）
- `rtl/ep_side/img/img_regs.v:1-39`（UBUS 寄存器块协议与地址段）
- `al_ip/pcie_ep_core/Design.xml:25-33`（PCIe 走 BANK94 CLK0 100 MHz，**与 H4 无关**）、`al_ip/pcie_ep_core/DesignConfiguration.xml:13`（ipGenVersion 171484）
- `ph1p_pcie_ep_top_Runs/phy_1/ph1p_pcie_ep_top_phy.area`（**#eram 124/300=41.33%、#pll 1/12、#gclk 4/32、#ioclk 0/24、#mlclk 0/24、#lut6 3278、#slice 3703**）

---

## 6. 下一步需要调用方决定的 3 件事

1. **DDR IP 怎么生成**：
   - A. 照抄例程 IP（零风险，参数=1600/CWL=5，见 R1）
   - B. **GUI 重新生成一版 800 Mbps（推荐，参数合法、口径一致）** ← 需要人操作 TD GUI
   - C. 放行一次 headless `create_ip`+`generate_target` 实验（§1.8），把 R2 一锤定音
2. **训练期间的系统噪声**：bring-up S1/S2 是否允许先把相机/PCIe 高速通路**停掉**（IPUG034 §3.3.3 建议"训练期间尽量减少系统噪声"）。
3. **`paxi_wstrb` 极性**：S1 里两种都试（这是 §2.3(2) 那处文档与例程矛盾的最小代价销法）。
