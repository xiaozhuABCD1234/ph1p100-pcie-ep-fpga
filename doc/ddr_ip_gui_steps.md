# DDR IP：命令行为什么拿不到 RTL + GUI 生成 800Mbps DDR IP 的点击清单

- 日期：2026-10-15
- 范围：**纯只读调查 + 本文件**。本文件是本次唯一被创建的文件。
- 本次**未做**：未构建 TD 工程、未下载 bit、未 ssh 板子、未下载/安装任何软件、未跑 `create_ip`/`generate_target`/`getf_*` 等会改状态的命令、未跑仿真（本机无仿真器）。
- 本机工具：`/opt/anlogic/TD_Release_2026.2_NL`，TD **6.2.3.210850**（`bin/td` stripped；`bin/IpTool` **未 strip，可查符号**），文档 `doc/IPUG/IPUG034_PH1P_MIS_IP_Guide.pdf`、`doc/SWUG/SWUG105_TCL_Command_User_Guide.pdf`。
- 结论分级：**【实测】**=本机跑出来的原始输出/文件；**【静态】**=读工具包/二进制/文档得出的确定性结论；**【推论】**=由上述两者推断、未直接验证；**【未确认】**=没有证据。
- 证据里凡是**上一轮实验**的日志（`/tmp/ddr_exp_*.txt`、`/tmp/pi_ddrip2.log`、`/tmp/ddr_dumps_before/`）都是既有的，本次没有重跑。

> ### ⚠️ 本次调查期间工作区里有**别的进程在活动**（不是本次操作）
> ```
> $ ps -eo pid,lstart,cmd | grep -E "IpTool|bin/td"
> 191964 四 10月 15 19:26:30 2026  /opt/anlogic/TD_Release_2026.2_NL/bin/td -gui
> 194120 四 10月 15 19:32:44 2026  /opt/anlogic/TD_Release_2026.2_NL/bin/IpTool -app_path .../bin/td
>        -catalog .../ip/depot/Catalog.xml -proj_path .../fpga -device PH1P100SBG484
>        -export_to .../fpga/al_ip -speed -3 -listen_close
> ```
> 同时：`/tmp/ddrip_exp/al_ip/ddr3_mc_0/` 在 19:36 出现了一份**完整生成产物**（`_proc.log`/`_adc.log`/`_drc_check.log` + 52 个 `src/**` 文件），而我在 19:33 看到的同一目录只有 6 个文件；仓库在 19:32–19:38 之间 `ph1p_pcie_ep_top.al` 一度显示为 ` M`（随后恢复，未进任何提交），并在 19:37 多了一个不是我做的提交 `2deadef`。
> **这些都不是本次调查产生的。** 下面凡引用 `/tmp/ddrip_exp` 下 19:36 的产物，都标为**【旁证】**，只用来说明"脚本链能不能跑通"，不作为"我跑通了"的证据。

---

## 0. 两个问题的答案（先给结论）

| # | 问题 | 结论 | 置信度 |
|---|---|---|---|
| 1a | DDR IP 包里到底有没有可供批处理调用的生成脚本？ | **有**，而且是完整一条链（`plugin_end.tcl` + `script/` 下 13 个 `gen_*/modify_*` tcl）。不是"包里没有脚本" | **【静态】+【旁证】** |
| 1b | `IPT-1002` 在哪个脚本里抛、判据是什么？ | **不在任何 .tcl 脚本里**。`IPT-1002` 是 IpTool 消息输出层给"ERROR 级消息"加的编号前缀（普通消息用 `IPT-1001`）；真正的失败判定在 IpTool 的 `IpGenGenerateInst`（= `generate_target` 的实现）：生成失败 → 取回 Tcl 错误串 → 打印 `IPT-1002 ERROR: Generate target failed. Reason: <错误串>` | **【静态】** |
| 1c | 空的到底是什么？ | **不是"生成脚本路径"，是 ADC 引脚约束文件参数 `PH1P_IO_ASSIGN`**。命令行 `create_ip` 建出的实例里它是空串；`gen_adc.tcl` 无条件 `open $adc_file r` → Tcl 报 `couldn't open "": no such file or directory` → 被包成 `[Error-TclFile]` → 外层报 `IPT-1002` | **【静态】+【实测】+【旁证】**（旁证：同一份实例把该参数填成真实 `.adc` 后，整条链 12 步全成功、52 个 RTL 文件落地） |
| 1d | 有没有别的命令行姿势能绕？ | 静态判断：**有两条**——(A) `set_property <F9P的.adc> CONFIG.PH1P_IO_ASSIGN <ip>` 后 `generate_target`；(B) `create_ip -user <GUI 生成过的实例 xml>`（把 adc 路径一起带进来）。**两条都没实测** | **【推论】** |
| 1e | 命令行到底能不能拿到 DDR IP 的 RTL？ | **不是"不能"，而是"只差一个必须由人指定的输入文件（.adc）"**。参数化建 IP 已实测可用；把 `PH1P_IO_ASSIGN` 填上以后能否一键跑通 = **未实测**（本次禁止跑）。要零风险现在就要产物 → **走 GUI** | **【推论】** |
| 2 | GUI 生成 800Mbps 版 | 完整点击清单见 §2；参数口径差异已逐条标注（§2.4 表） | — |

**根因一句话**：
> **MIS DDR IP 的生成脚本链本身齐全、也可以在无 GUI 下跑；失败原因是命令行 `create_ip` 建出的实例里 `PH1P_IO_ASSIGN`（ADC 引脚约束文件）是空串，而生成链里的 `gen_adc.tcl` 会拿它直接 `open $adc_file r`，于是 Tcl 抛 `couldn't open ""`，IpTool 把它包成 `[Error-TclFile]` 并以 `IPT-1002 Generate target failed` 返回。**

---

# 第 1 部分：为什么命令行生成 DDR IP 的 RTL 不行

## 1.1 【实测】上一轮实验的原始输出（既有日志）

`generate_target` 对 MIS DDR IP 失败（`/tmp/ddr_exp_run7_gen2.txt:145-156`，原文）：

```
RUN-1002 : start command "get_ips ddr3_mc_0"
ddr3_mc_0
RUN-1002 : start command "generate_target "
IPT-1002 ERROR: Generate target failed. Reason: [Error-TclFile] couldn't open "": no such file or directory
generate_target [get_ips ddr3_mc_0] -> rc=1 msg={}
  TREE al_ip/ddr3_mc_0 : 6 files
         806  al_ip/ddr3_mc_0/.m_params_ddr3_mc_0.txt
        5780  al_ip/ddr3_mc_0/.params_ddr3_mc_0.txt
        1508  al_ip/ddr3_mc_0/.ports_ddr3_mc_0.txt
       33303  al_ip/ddr3_mc_0/Design.xml
         968  al_ip/ddr3_mc_0/DesignConfiguration.xml
       25213  al_ip/ddr3_mc_0/ddr3_mc_0.xml
```

同一次运行里的**对照组 RAM IP 成功**（同文件 `157-173`）：

```
  TREE al_ip/ram : 10 files
        2289  al_ip/ram/RTL/include/hxt_parameter.v
        2496  al_ip/ram/ram_a5091d0ea69c.v
IPT-1001 : The target has been generated successfully.
generate_target [get_ips ram] -> rc=0 msg={}
  TREE al_ip/ram : 9 files
        2047  al_ip/ram/RTL/ram_ram.v          ← 新产出的 RTL
```

`/tmp/ddr_exp_run9_setprop.txt:281-283` 是第二次（按文档语法 `generate_target [get_ips ddr3_mc_0]`）复现的**同一条错误**。

失败的实例当时的参数快照（`/tmp/ddr_dumps_before/.params_ddr3_mc_0.txt`）：

```
117:PH1P_IO_ASSIGN :  : U : En :  :  :        ← 空
118:PH1P_AC_BYTE   :  : G : Dis :  :  :
119:PH1P_DRC_CHECK  :  : G : En :  :  :        ← 空（不是 PASS）
121:PH1P_PLL_LOC    :  : G : En :  :  :
124:PH1P_SYSCLK_LOC :  : U : En :  :  :
```
`/tmp/ddr_exp_run10_f9p.txt:264-265` 也读到 `PH1P_IO_ASSIGN = {}`。

而该实例的 `al_ip/ddr3_mc_0_drc_check.log` **只有一行**：
```
/*** DESIGN RULE CHECK START *** /
```
→ 说明 `drc_check` 走到"adc 文件不存在"就提前返回了（见 §1.4）。

## 1.2 【静态】TD/IpTool 侧：这条命令是怎么走的、`IPT-1002` 从哪来

**(1) TD 的 Tcl 命令 `generate_target`**
`bin/td`（stripped，但 `.dynsym` 有 139106 条符号）里：
- `IpGenerateTarget(Tcl_Interp*, int, Tcl_Obj* const*)` @`0x61cd820`（289 B）：
  1. `argc<=1` → 直接返回 1；
  2. 取 `argv[1]` 当**字符串**，`ToolRegistry::getIpToolManagerByName(name)` 取"该 IP 的 IpTool 子进程管理器"；取不到 → 返回 1；
  3. 进程没起就 `IpToolProcessManager::start(true)`，然后 `IpToolProcessManager::writeData("generate_target")`（这个字面串就在 `0x807c781`，紧邻 `load_project_ips` / `close_project_ips`）。
- 由此可以解释两件实测现象：Vivado 语法 `generate_target all $ip` 必然失败（`argv[1]` = `"all"`，找不到管理器）；而日志里总打 `start command "generate_target "`（参数由 manager 侧带）。

**(2) IpTool 的 `generate_target` 实现（`bin/IpTool`，未 strip）**
- 命令名清单在 `.rodata` 一串里：`get_ipdefs / report_property / generate_target / get_property / set_property / create_ip / set_param_enable / report_params / add_table / set_widget_prop / add_tab / set_param`。
- 实现符号：`IpGenGenerateInst(int, char**, alTclCmd::AL_Command*, Tcl_Interp*)` @`0x8a2660`（495 B）：
  1. `ipWatchDesignXmlFile(g_InstPath, false)`；
  2. `ipGenInstWithoutGui(false)` @`0x7ebf00` → `generateInstWithoutGui(bool)` @`0x7edb60` → `GenWindow::generateXmlForBatch(bool, QString, QString)` @`0x88c300`；
  3. 若 `gGenWin` 存在则 `GenWindow::getGenErrorForBatch()` @`0x860ec0` 取错误串；
  4. 失败 → 拼 `"ERROR: Generate target failed"`（rodata `0x1cc09e3`）+ `". Reason: "`（`0x1cc0a01`）+ 错误串，`Tcl_SetObjResult` 返回 1；成功 → `"The target has been generated successfully."`（`0x1cc10f0`）返回 0。

**(3) `IPT-1002` / `IPT-1001` 是什么**
`bin/IpTool` 里那段消息输出代码（文件偏移 ≈`0x18B90C0`，按 `.rodata` 反算 vaddr ≈`0x1CB90C0`）在做这件事：把要打印的文本前缀与 `"WARNING:"` / `"ERROR:"` 比较，
- 以 `ERROR:` 开头 → 写出常量 `IPT-1002`（`movabs rcx,"IPT-1002"` 后紧跟一个空格字节 `\xc6\x40\x08 0x20`）；
- 否则 → 写 `IPT-1001` + `": "`。

⇒ **`IPT-1001`/`IPT-1002` 是 IpTool 消息系统的"普通/错误"编号，不是某种失败原因的判据。** 本次需要的是它后面的文本：`Generate target failed. Reason: [Error-TclFile] couldn't open ""...`。
（同一个序号在 `bin/td` 里还挂着另外两条文案：`IPT-1002 ERROR: No IP matching the VLNV`、`IPT-1002 ERROR: The current IP %1 does not support creation using TCL commands.` —— 更说明它只是"IP 命令出错"的编号。）

**(4) `[Error-TclFile]` 是谁造的、判据是什么**
- 格式串 `[Error-%1] %2` 在 `bin/IpTool` rodata `0x1cbd73d`，**全二进制只有一个引用**：`GenWindow::addGenError(QString, QString)` @`0x868c60`。
- 唯一以 `TclFile`（rodata `0x1cbd74c`，长度 7）为类别的调用者是 `GenWindow::addGenSourceTclError()` @`0x868d90`：它 `tclGetErrInfo(interp)` 取 Tcl 错误串，再 `addGenError("TclFile", 错误串)`。
- `addGenSourceTclError` **只有 4 个调用点**，且**4 处都在 source 前先做了 `QFileInfo::isFile()` 判断**：

| 调用点 | 函数 | 被 source 的文件 |
|---|---|---|
| `0x867cdc` | `GenWindow::sourceTclFile(QString const&)` @`0x867ca0` | 传入的 tcl |
| `0x869004` | `GenWindow::fillUserControls(QVBoxLayout*)` @`0x868e80` | `<compPath>/Layout.tcl`（`"%1/%2"`@`0x1cb9576` + `Layout.tcl`） |
| `0x8691de` | `GenWindow::invokePluginTcl(QString const&)` @`0x869120` | fileset 里的 plugin tcl（空则**直接返回 1，不报错**） |
| `0x87bff2` | `GenWindow::sourceTclDependFiles()` @`0x87bf20` | `<compPath>/Dependency.tcl` |

⇒ **被 source 的文件本身是存在的**（否则会走 `isFile()` 的 false 分支，只 log 一句 `Error: failed to identify the layout file:` 之类，不会产生 `[Error-TclFile]`）。所以 `couldn't open ""` 是**脚本内容**里的一次 `open`/`source` 拿到空文件名。

**(5) 生成链**
`ip/depot/MIS_DDRF6F1D0P0_1.2/PH1P_DDRMC_IP/Other/plugin_end.tcl`（154 行）就是生成入口，逐行 source：

| 行 | 动作 |
|---|---|
| 12 | `open $proclog w`（`$IP_EXPORT_PATH/$IP_COMPONENT_NAME_proc.log`） |
| 19 | `glob $IP_EXPORT_PATH/$IP_COMPONENT_NAME/RTL/*.v`（wrapper 名） |
| 29 | `script/gen_file.tcl`（生成 `src/**` RTL） |
| 34 | `script/modify_ipfile.tcl` |
| 74-79 | `if {$PH1P_DDR_TYPE != "Integrated"} → source script/gen_adc.tcl` ← **本次失败点** |
| 97 | `script/gen_include.tcl` |
| 103 | `script/gen_sdc.tcl` |
| 108 | `script/modify_xmlfile.tcl` |
| 119 | `script/gen_define.tcl`（写 `src/rtl/include/ph1p_mis_define.vh`） |
| 124 | `script/gen_boardly.tcl`（写 `src/rtl/phy/include/ph1p_ddrphy_board_delay.vh`） |
| 129 | `script/modify_random.tcl`（删 `RTL/` 目录） |
| 134 | `script/gen_fileset.tcl`（写 `sim/fileset/fileset_mis.f`） |
| 140/146 | `script/modify_include.tcl`、`script/modify_phyinit.tcl` |
| 153 | `file delete -force "$IP_EXPORT_PATH/$IP_COMPONENT_NAME/Other"` |

（`PH1P_DDRPHY_IP/Other/plugin_end.tcl` 是同样结构的另一份，配套 DDRPHY 视图。）

## 1.3 【静态】空的那个路径 = `PH1P_IO_ASSIGN`（ADC 文件）

- 参数定义：`.../MIS_DDRF6F1D0P0_1.2/Dependency.tcl:122`
  ```tcl
  set_param -param_id {PH1P_IO_ASSIGN} -data_type {String} -list {*.adc}
  ```
  **没有 `-value`** —— 没人给它值就是空串（命令行 `create_ip` 只给 vlnv + 组件名，不可能给到它）。
  同一个文件 `:123/124/126/129` 把它喂给 `update_ac_num` / `update_drc_check` / `update_gui_pll` / `update_sysclk_loc`。
- 罪魁：`.../script/gen_adc.tcl`
  - `:22` 形参：`proc gen_adc {ddr_protocol IP_EXPORT_PATH IP_COMPONENT_NAME IP_DEVICE adc_file ...}`
  - `:56`（`ddr_ck` 两组的 DDR3 分支）/`:75`（单 `ddr_ck`，本例）`set fp [open $adc_file r]` ← **无任何存在性检查**
  - `:1023` 调用：`gen_adc $PH1P_DDR_TYPE $IP_EXPORT_PATH $IP_COMPONENT_NAME $IP_DEVICE $PH1P_IO_ASSIGN $PH1P_SINGLE_PLL ...`
  ⇒ `PH1P_IO_ASSIGN = ""` → `open ""` → Tcl 原生错误 `couldn't open "": no such file or directory` → 沿 `source` 链冒泡到 `invokePluginTcl` → `addGenSourceTclError` → `[Error-TclFile] couldn't open ""` → `IPT-1002 ERROR: Generate target failed. Reason: ...`。**逐字对得上。**
- 对照：`Dependency.tcl` 里的 `drc_check` 对同一个参数是**有守卫**的（`:1219-1229`）：
  ```tcl
  if {[file exists $adc_file]} { set fp [open $adc_file r] }
  elseif {$DDR_TYPE == "Integrated"} { ... return "" }
  else { set IP_GEN_PARAM_ERROR_FLAG 1
         set IP_GEN_PARAM_ERROR_MSG "The adc constraint file does not exist!" ; return "" }
  ```
  这就是旧实例 `_drc_check.log` 只有首行、`PH1P_DRC_CHECK=""`、`PH1P_AC_BYTE=""`、`PH1P_PLL_LOC=""`、`PH1P_SYSCLK_LOC=""` 的原因（这些派生量全都依赖 ADC/Master-Bank 解析）。
  **但这里的失败是"软"的**（只置标志位），所以流程不会停在这；真正把 Tcl 打断的是 `gen_adc.tcl`。
- `_adc.log` 也是脚本自己写的，不需要 GUI 额外动作：`Dependency.tcl:1982` 定义 `used_chippin_name_file = "$IP_EXPORT_PATH/$IP_COMPONENT_NAME_adc.log"`，`:2228` `open ... w` 逐行写 `信号,chippin`。
- `_adc.log` 的消费方（`update_gui_pll:2356→cal_onlyacbkby:2276`、`update_sysclk_loc:2434/2465`、`update_bk_num:2648`）都直接 `open "$IP_EXPORT_PATH/$IP_COMPONENT_NAME_adc.log" r`，其中 `cal_onlyacbkby` 在 `[file exists $PH1P_IO_ASSIGN]` 为假时**连 `open_adcfile_id` 都不会定义**——所以空 adc 时批处理还有一堆隐患，只是第一个中断点是 `gen_adc.tcl`。

## 1.4 【静态】DDR 包 vs RAM 包：到底差什么（回答"包里有/没有生成脚本"）

| 对比项 | RAM IP（`RAMF9F0D0P0_1.0`） | MIS DDR IP（`MIS_DDRF6F1D0P0_1.2`） |
|---|---|---|
| 包内生成脚本 | `RAM/Other/plugin_mid.tcl`（1 个） | `PH1P_DDRMC_IP/Other/plugin_end.tcl` + `PH1P_DDRMC_IP/Other/ph1p_ddrphy_ip/script/{gen_file,gen_adc,gen_include,gen_sdc,gen_define,gen_boardly,gen_fileset,modify_ipfile,modify_xmlfile,modify_random,modify_include,modify_phyinit}.tcl`（13 个）＋ DDRPHY 视图一份 |
| 包内静态 RTL | `RAM/RTL/ram.v`（IP 本体就是参数化 RAM） | 只有 `RTL/ph1p_ddrmc_wrapper.v`（外壳），**功能 RTL 全靠脚本生成** |
| 必须由人提供的输入 | 无 | **`PH1P_IO_ASSIGN`（.adc 引脚约束）** ← 唯一"人必须给"的东西 |
| `create_ip` 出来的实例 xml | 含 `<fileSet name="fs-ram">`（`ram.v` + `RTL/ram_ram.v` 带 `anlogic:coreRTL=yes`） | **完全没有 `<fileSet>`**（生成之后才会补上 `fs-<name>`，见 §1.5） |
| `generate_target` 实测结果 | rc=0，产出 `RTL/ram_ram.v` 【实测】 | rc=1，`IPT-1002`（`open ""`）【实测】 |

⇒ **不是"RAM 有脚本、DDR 没有"**，而是：
1. 两个 IP 的生成机制不同（RAM 是"包内静态 RTL + 少量 tcl"，DDR 是"脚本现场生成一大堆 RTL"）；
2. DDR 多了一个**必须由人指定**的 `.adc` 输入，而 `create_ip` 无法提供它。

## 1.5 【旁证】填上 ADC 之后，整条链是能跑完的（不是我跑的，见开头警告）

`/tmp/ddrip_exp/al_ip/ddr3_mc_0/`（19:36 生成，`PH1P_IO_ASSIGN = /opt/anlogic/TD_Release_2026.2_NL/ip/depot/MIS_DDRF6F1D0P0_1.2/example_adc/ap115_ddr3_x32.adc`）：

`ddr3_mc_0_proc.log`（12 行，全成功）：
```
wrapper_file_name : ddr3_mc_0_ph1p_ddrmc_wrapper.v
generate src file success
modify usrname file success
generate adc file success
generate include file success
generate sdc file success
modify xml file success
gen define file success
gen board delay file success
remove RTL folder success
gen fileset_mis.f success
run modify_include.tcl success
run modify_phyinit.tcl success
```
`ddr3_mc_0_drc_check.log`（9 行，末两行）：`Complete all signals check ,the design rule check pass!` / `/***  DESIGN RULE CHECK END   *** /`
`ddr3_mc_0_adc.log`：72 行（含 `refclks,4,2,0,`）
实例目录：`ddr3_mc_0.v`(5490) + `ddr3_mc_0_ph1p_ddrmc_wrapper.v`(20645) + `src/**`（52 个文件）+ `sim/fileset/fileset_mis.f`；`ddr3_mc_0.xml` 从 25213 B 涨到 35604 B，里面出现了 `<fileSet name="fs-ddr3_mc_0">`，**列出 53 项**（`src/adc/*.adc`、`src/sdc/*.sdc`、全部 `src/rtl/**` + 两个顶层 .v）。

⇒ 生成脚本链**可以**在无 GUI 参与下跑完（那个实例是 GUI 会话拉起的 IpTool，但跑的是同一套 tcl，不依赖鼠标）。**缺的只有 ADC 文件这一个输入。**

## 1.6 有没有别的命令行姿势能绕（**【推论】，本次按约束未跑**）

### 姿势 A（推荐先试）：直接把 ADC 文件 set 进去
```tcl
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
open_project {ph1p_pcie_ep_top.al}
load_project_ips                                        ;# 必须，open_project 之后
set ip [get_ips ddrmc_x32]
set_property 800.0  CONFIG.PH1P_DDR_SPEED  $ip          ;# 值 参数名 对象（反 Vivado）
set_property 1.35   CONFIG.PH1P_IO_VOL     $ip
set_property DDR3-800D CONFIG.PH1P_SPEED_BIN $ip
set_property x16    CONFIG.PH1P_COMP_TYPE  $ip
set_property 2048   CONFIG.PH1P_COMP_DENSITY $ip
set_property 50.0   CONFIG.PH1P_REF_CLK    $ip
set_property 0      CONFIG.PH1P_AXI_CTRL   $ip          ;# 0 = 原生 PAXI
set_property 0      CONFIG.PH1P_ECC_EN     $ip
set_property /abs/path/to/ddr3_f9p_x32.adc CONFIG.PH1P_IO_ASSIGN $ip   ;# ★ 关键这一条
generate_target [get_ips ddrmc_x32]
report_ip_status [get_ips ddrmc_x32]
```
- **依据**：唯一缺口就是这一个 String 参数（§1.3）；非空即整链跑通（§1.5 旁证）；`set_property` 对 CONFIG.* 已实测可用（含数值/枚举/String）。
- **前提/风险**：
  1. `.adc` 里的信号名必须符合 IPUG034 表 3-4 命名（`ddr_ck_p/n, ddr_reset_n, ddr_cke, ddr_cs_n, ddr_odt, ddr_ras_n, ddr_cas_n, ddr_we_n, ddr_ba, ddr_addr, ddr_dqs_p/n, ddr_dq, ddr_dm`），否则 DRC 不 PASS；
  2. **顺序必须是 `set_property <值> <名> <对象>`**；写反只丢一条 `USR-7001 CRITICAL-WARNING`，`catch` 仍返回 0（静默失败，上一轮实测踩过）；
  3. 别用 Vivado 语法 `generate_target all $ip`（必失败，§1.2(1)）；
  4. 动手前 `cp ph1p_pcie_ep_top.al /tmp/`（`.al` 会被静默重写，§2.7-4）。
- **判据**：`al_ip/<name>_proc.log` 出现且 12 行全 success、`al_ip/<name>/src/**` 出现、`<name>_drc_check.log` 末行 `...the design rule check pass!`。
- **未确认**：没有实测过 A 成功。**如果调用方放行一次实验，这一条是最小代价的一锤定音。**

### 姿势 B：`create_ip -user <GUI 生成过的实例 xml>`
IpTool 的命令行支持 `-user USER_PATH [-gen IP_PATH] [-export_to ...] [-comp ...]`（`bin/IpTool` 的 usage 串）与 `-use_value default`；本机也**实测**过 `RUN-1002 : start command "create_ip -user /tmp/ddrip_exp/al_ip/ram/ram.xml"`（`/tmp/ddr_exp_run7_gen2.txt:130`）。
⇒ 拿一份 GUI 生成过的 `al_ip/<name>/<name>.xml`（其 `Design.xml` 里 `PH1P_IO_ASSIGN` 已带绝对路径），用 `create_ip -user <它>` 复制出一个新实例，再 `generate_target`。**风险**：那份 xml 里的 adc 路径是原机器的绝对路径（例程里是 `F:/al_data/...`），跨机/跨目录会再次指向空/不存在的文件；且 `create_ip -user` 是否会重写 `.al`、是否会校验器件匹配，未确认。

### 姿势 C（零风险，本次任务的推荐）
GUI 生成一次 → 之后进工程只用 `add_files al_ip/<name>/<name>.xml`；命令行只负责编译（`build.tcl`）。这是官方文档唯一描述的流程（IPUG034 §3.1/§3.2），也是 09 例程的实际生成方式（`ipgen.log` GUI 回放）。

## 1.7 明确的结论（问题 1）

1. **命令行能不能拿到 DDR IP 的 RTL？**
   - 已经能拿到的部分：【实测】`create_ip` + `set_property CONFIG.*` + `.al` 登记可用；`generate_target` 对 **RAM** 产 RTL 可用。
   - DDR IP：**不是"命令不支持"，而是缺一个必须由人指定的 `.adc` 输入**。按静态分析（§1.2/§1.3）+ 旁证（§1.5），**补上 `CONFIG.PH1P_IO_ASSIGN` 后应当可以**；但**本次未实测**。
   - 若要求"现在就拿到产物且零风险"：**走 GUI**（第 2 部分）。
2. **"不能"的根因一句话**：
   > 生成脚本链是齐的；命令行建出的实例里 ADC 引脚约束文件参数 `PH1P_IO_ASSIGN` 为空，`gen_adc.tcl` 直接 `open $adc_file r` → Tcl `couldn't open ""` → IpTool 报 `IPT-1002 Generate target failed`。
3. 顺带纠正两条既有认知：
   - `IPT-1002` ≠ "生成脚本路径为空"的专用码，它是 IpTool 的 ERROR 编号（普通消息是 `IPT-1001`）；
   - `generate_target` 本身**是产 RTL 的**（RAM 实测），不存在"TD 批处理天生不产 RTL"这一说。

---

# 第 2 部分：GUI 生成 800Mbps DDR IP 的精确点击清单

适用：**MLK-F9P-CA05-PH1P100**（器件 `PH1P100SBG484` speed `-3`），板上 2×`GDP1BFLM-CB` = 512MB/32bit DDR3L；目标 **800 Mbps**、用户侧 **256bit 原生 PAXI**。
工具：TD 6.2.3（`/opt/anlogic/TD_Release_2026.2_NL/bin/td`）GUI。

## 2.0 动手前的 3 件准备（否则第 6 步一定失败）

1. **准备 F9P 的 ADC 引脚约束文件**（这是整个流程唯一的"人必须给"的输入，见 §1.3）：
   - 现成可用：`/mnt/nvme/fpga/TD/work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/golden_adc/ap115v2_ddr3_x32.adc`
     （71 条 `set_ippin_assignment`，球号来自 F9P 手册；该文件是 09 例程生成 IP 时实际使用的输入，见其 `Design.xml` 里 `PH1P_IO_ASSIGN = "F:/al_data/F9P_PH1P100/08_ddr3_ddrmc_cal_x32_1066mbps/golden_adc/ap115v2_ddr3_x32.adc"`）
   - 也可以直接用例程 IP 目录里**生成后**的那份：`.../09_ddr3_ddrmc_cal_x32_1066mbps/prj_src/ip/ddrmc_x32/src/adc/ddrmc_x32.adc`（含 `set_ipinst_assignment` 行也没关系，DRC 会跳过这些行：`Dependency.tcl:1236-1237`）
   - 建议先拷进工程放在手边（例如工程根下 `al_ip/ddrmc_x32_input.adc` 或 `constraints/` 外的独立位置），路径**不要带中文/空格**。
   - ⚠️ **不要**图省事去点 TD 自带的那 8 个示例 adc（`/opt/anlogic/TD_Release_2026.2_NL/ip/depot/MIS_DDRF6F1D0P0_1.2/example_adc/`）：它们对应别的板子。实测对比：
     | 信号 | `example_adc/ap115_ddr3_x32.adc`（头部写 `PH1P50MBG484`） | F9P 用的 `ap115v2_ddr3_x32.adc` |
     |---|---|---|
     | `ddr_ck_p` | `Y4` | `H3` |
     | `ddr_dq[0]` | `C2` | `U3` |
     | `ddr_dqs_p[0]` | `E1` | `R3` |
     | `ddr_addr[14]` | `AA5` | `J5` |
     | refclk | `V4/W4`（注释里 `LVDS18`） | `H4`（注释里被注掉，实际由工程顶层约束） |
2. **确认工程与器件**：TD 打开 `~/Projects/2026-embedded-chip-fpga-ph1p100/fpga/ph1p_pcie_ep_top.al`；`Import Device` 必须是 `PH1P100SBG484` / speed `-3`（`build.tcl:9` 已写死）。看 Project 面板里器件型号，别用 SBG676（那是 RC 参考板）。
3. **备份 `.al`**：`cp ph1p_pcie_ep_top.al /tmp/`（TD 打开/建 IP 时会改写它；见 §2.7-4）。

## 2.1 进入 IP 管理（GUI 入口）

| 步 | 点哪里 |
|---|---|
| 1 | 菜单 **Tools → IP Catalog** （IPUG034 §3.1.1 原文：「打开 TD 软件，依次点击 Tools -> IP Catalog -> Primitive IP -> Memory and Storage-> MIS – DDR2/DDR3/DDR4」（`/tmp/ipug034.txt:1759`）） |
| 2 | 左树依次展开 **Primitive IP → Memory and Storage → MIS - DDR2/DDR3/DDR4**，双击/点它 |
| 3 | 弹出 **Setup Exporting Options** 对话框（IPUG034 图 3-1）：<br>• **Export Path**：默认就是"当前工程所在目录下的 `al_ip`"→ 本工程要的就是 `<工程根>/al_ip`，保持默认（不要指到工程外）<br>• **Component Name**：默认 `Comp_inst` → **改成 `ddrmc_x32`**<br>&nbsp;&nbsp;（命名依据：09 DDR 例程就是 `ddrmc_x32`，本仓 `doc/ddr_bringup_plan.md` §3.2 也按这个名字规划；参考工程 `f9p_ph1p100_imx415x2` 里的 IP 叫 `ui_pll`（`uisrc/03_ip/ui_pll/ui_pll.xml`），它的命令行实验里 MIPI IP 叫 `mipi_dphy_a/b` —— 命名风格都是"功能_序号"）<br>• 名字会成为**模块名 + 文件名**（`ddrmc_x32.v` / `ddrmc_x32.xml` / `ddrmc_x32.adc` / 目录名），一旦定了后面不好改，先想好 |
| 4 | 点 **OK** → 进 MIS-DDR2/DDR3/DDR4 配置界面（IPUG034 图 3-2） |
| 5 | 界面顶部 **View** 下拉：选 **DDRMC**（DDRMC = MC + PHY；DDRPHY = 只要 PHY。我们要 MC，所以选 DDRMC；IPUG034 §3.1.2 原文：Memory Controller 组只有 DDRMC 模式可编辑） |

## 2.2 逐项参数（GUI 标签级），组内从左上到右下点完

> 下表"例程（09, F9P, 1600）"= 09 例程 IP 的生效值，来自 `.../prj_src/ip/ddrmc_x32/.params_ddrmc_x32.txt`（只读，已核对）；
> "本任务（800）"= 给 F9P 的建议值；**粗体**行是我方口径与例程不一致的地方。

### 组 1 DDR Solution Configuration
| GUI 标签 | 例程（1600） | 本任务（800） | 说明/依据 |
|---|---|---|---|
| DDR Type | DDR3 | DDR3 | 板上是 DDR3L，但 IP 没有 DDR3L 选项；1.35V 由下一项表达 |
| PingPong PHY | （灰） | （灰） | DDRMC 模式下不可编辑（IPUG034 §3.1.2-1b） |
| RefClk Freq | 50.0000 | **50.0000** | 板上只有一颗 50MHz 单端（球号 H4）；范围 25–400MHz |
| **DDR Speed** | 1600.00 | **800.00** | ⚠️ **不一致**。依据：`DS1300_PH1P_Datasheet_1.2.1.pdf` 表 3-60「External Memory Interface 性能」PH1P100/DDR3 = **800 Mbps**，表 1-2 同上；板卡手册也写「数据带宽 800Mbps×32bit」。例程目录名写 1066、IP 实配 1600，属"三处口径矛盾"；800 还与颗粒手册口径自洽 |
| DQ Bytes | 4 | **4** | 32bit / 8 = 4 个 DQ byte；滑块支持 1/2/4/5/6/8/9 |
| AC Bytes | 3 | （灰） | 不用点，由 DRC 解析 adc 后回填（IPUG034 §3.1.2-1f） |
| **IO Voltage** | 1.35 | **1.35** | ⚠️ **新建时默认是 1.5，必须改**。板卡是 `SSTL135`/DDR3L；DDR3 支持 1.35/1.5 |
| Vref Type | Internal | Internal | IPUG034：仅支持 Internal |

### 组 2 DRAM Configuration
| GUI 标签 | 例程（1600） | 本任务（800） | 说明/依据 |
|---|---|---|---|
| Type | x16 | **x16** | 颗粒 `GDP1BFLM-CB` = 128Mb×16（`DS-00843` §2）。**新建默认 x8，必须改** |
| Density(Mb) | 2048 | **2048** | 2Gb/片 × 2 片 = 512MB。**新建默认 512，必须改** |
| **Speed Bin** | DDR3-1600K | **DDR3-800D** | ⚠️ **不一致**。800 档只有 `DDR3-800D`/`DDR3-800E`（IPUG034 表 3-1）；派生 CL：800D→5、800E→6（`Dependency.tcl:832-833`）。选 800D 取更小延迟；800E 亦可 |
| CL | 11 | （灰） | 不可编辑，随 Speed Bin 派生（IPUG034 §3.1.2-2d） |
| **CWL** | 5（**默认值，没人点过**） | **5** | ⚠️ 800 档唯一可选 `5`（`Dependency.tcl:875-876`），天然合法。**例程那版 1600+CL11+CWL5 在颗粒侧不是 JEDEC 合法组合**（`DS-00843` 表 11-2：CL=11 时 tCK∈[1.25,1.5)ns 必须 CWL=8，5/6/7 为 Reserved）→ 这也是选 800 的第三个理由 |

### 组 3 PZQ Setting
| GUI 标签 | 例程 | 本任务 | 说明 |
|---|---|---|---|
| PZQ Calibration Enable | 不勾 | **不勾** | 照例程。勾了才会激活下面两项 |
| PZQ Configuration Sharing | 不勾 | **不勾** | 同上 |
| Master Bank | （灰，显示 BANK11） | （灰） | 只有 PZQ Sharing 使能才可编辑（IPUG034 §3.1.2-3c）；显示值不生效。**若将来要开 PZQ：必须选 DDR 所在 bank（BANK32 或 BANK33），且 VRP 需 240Ω 高精度电阻 —— 板上是否已接【未确认】** |
| DRAM_DRV / DRAM_ODT / HOST_DRV_AC / HOST_DRV_DX / HOST_ODT_DX | 40 / 60 / 40 / 40 / 60 | **同例程** | IPUG034 表 3-2 的取值范围；例程这套值已在 F9P 上编译过 |

### 组 4 DM or DBI Setting
| GUI 标签 | 例程 | 本任务 | 说明 |
|---|---|---|---|
| Write Direction | WDM | **WDM** | DDR3 支持 NONE/WDM（WDM = 用 DM 做数据掩码） |
| Read Direction | NONE | **NONE** | 只对 DDR4 有效 |

### 组 5 Memory Controller（只有 DDRMC 视图可编辑）
| GUI 标签 | 例程 | 本任务 | 说明/依据 |
|---|---|---|---|
| **AXI Interface** | 不勾 | **不勾** | ⚠️ 不勾 = 用户侧是**原生 PAXI**（`PH1P_MC_PAXI=1`、`paxi_*` 端口、单拍 256bit、无 len/size/burst）。要的就是这个（任务书要求）。若是 DQ Bytes=4，勾 AXI 也允许（IPUG034 表 3-3：仅 ECC 关时可启用），但 PAXI 更省事 |
| **ECC** | 不勾 | **不勾** | ⚠️ 板上只有 4 个 DQ byte（32bit 数据），开 ECC 需要额外的第 5 个 byte（DQ Bytes=5）→ **开不了**。勾了会吃掉一个 byte 的位宽 |
| Address Map | ROW_COL_BANK | **ROW_COL_BANK** | 与例程一致；配 4×… 线性寻址结论见 `doc/ddr_bringup_plan.md` §2.3(3) |
| Reorder | NORMAL | **NORMAL** | 与例程一致 |

### 组 6 IO Planning
| GUI 标签 | 例程 | 本任务 | 说明 |
|---|---|---|---|
| ddr_ck | 1 | **1** | 板上 1 组差分 CK |
| ddr_reset_n | 1 | **1** | DDR3 有效 |
| ddr_parity | 0（灰） | （灰） | 只对 DDRPHY 模式 DDR4 有效 |
| ddr_cs_n | 1 | **1** | |
| ddr_cke | 1 | **1** | |
| ddr_odt | 1 | **1** | |
| **ADC File Path** | `F:/.../golden_adc/ap115v2_ddr3_x32.adc` | **§2.0 准备的那份 F9P `.adc` 的绝对路径** | ⚠️ **这一步点错=全盘错**（引脚全到别的板上去了）。用右侧文件浏览按钮选，别手打。选完 DRC 会自动跑 |
| DRC Check | PASS | 应自动变 `PASS` | 只读文本（IPUG034 §3.1.2-7h）。不是 PASS 就别往下走，去看 `al_ip/ddrmc_x32_drc_check.log` 末行 |

### 组 7 PLL Configuration
| GUI 标签 | 例程 | 本任务 | 说明/依据 |
|---|---|---|---|
| Single PLL | 不勾 | **不勾** | 不勾 = PLL0→PLL1 级联（精度更好） |
| Actual Freq | （灰） | （灰） | = DDR_CK = DDR_Speed/2 → 800 档显示 400（MHz） |
| **PLL Location** | BANK33 | **BANK33** | IPUG034 §3.1.2-6c：必须是 DDR 方案占用的 bank，**优先 AC 信号所在 bank**。F9P 的 DDR：DQ 在 BANK32、AC/CLK/refclk 在 BANK33（`_adc.log` 里 `ddr_dqs_*` bank=4、`ddr_addr/ba/ck` bank=5；bank 索引表见 `pkg/cfg.csv` 的 `PH1P100SBG484` 行）→ 选 BANK33 |
| **RefClk Type** | SINGLE | **SINGLE** | 板上 50MHz 是单端（差分需两个脚）。若误选 DIFF，下面 RefClk Location 会变成一对脚（例如 `V4,W4` 这种），跟板上对不上 |
| RefClk Location | H4 | **H4** | H4 属 BANK33，正好满足"推荐与 AC 信号同 bank"。**可选值随 ADC 文件里 refclk 条目变化**（09 例程里是 `H4;;G4`），所以先定 RefClk Type 再选它 |

### 组 8 Training and Board Delay Setting
| GUI 标签 | 例程 | 本任务 | 说明 |
|---|---|---|---|
| Training | 勾 | **勾** | IPUG034 §3.1.2-8a：勾了则 Byte0-8 **无需**单独配 Board Delay |
| Byte0…Byte8 / AC Delay(ps) / DQ Delay(ps) | 全不勾 | **全不勾** | 例程全 Dis；勾 Training 时这些灰掉 |

## 2.3 生成（点 OK 之后）

| 步 | 动作 | 说明 |
|---|---|---|
| 6 | 配置界面右下角 **OK** | IPUG034 §3.2：「完成配置后，点击 OK 按钮，软件默认在工程所在文件夹的 al_ip 下生成…」 |
| 7 | 弹出 **IP Generating Options** 对话框 → 点 **Generate** | 依据 09 例程的 GUI 回放日志 `prj_td/log/ipgen.log`：`ipgen_gui_select_dialog IP_Generating_Options` → `ipgen_gui_click_push_button IP_Generator GenOptionDialog.Generate` |
| 8 | 等进度结束，看到 **`#GUI-2000 : The IP files have been generated successfully.`** | 同一日志第 18 行原文：`#GUI-2000 : The IP files have been generated successfully. :{PH1P100SBG484(.../<name>.xml)}` |

若报错：先看 `al_ip/ddrmc_x32_drc_check.log` 与 `al_ip/ddrmc_x32_proc.log`；
`IPT-1002 ERROR: Generate target failed. Reason: [Error-TclFile] couldn't open "": no such file or directory` → **ADC File Path 是空的**（第 1 部分的根因），回去重选。

## 2.4 生成后要落盘/入库哪些文件、放哪里

产物全部落在 **`<工程根>/al_ip/ddrmc_x32/`**（GUI 默认就在工程所在目录的 `al_ip` 下，与现有 `al_ip/pcie_ep_core/`、`al_ip/pcie_pll_ep/`、`al_ip/ram/` 同级），另外 3 个日志是它的**同级兄弟文件**。

```
<工程根>/
├── al_ip/
│   ├── ddrmc_x32/                       ← 整个目录都要入库（IP 的自我描述 + RTL + 约束）
│   │   ├── ddrmc_x32.xml                （35564B 量级）IP 实例定义：参数/端口/文件清单；.al 里登记的"那一行"
│   │   ├── Design.xml                   生效参数值（真正的参数值在这里）
│   │   ├── DesignConfiguration.xml      view/module name 绑定
│   │   ├── ddrmc_x32.v                  IP 顶层 RTL（把参数固化进 wrapper 例化）
│   │   ├── ddrmc_x32_ph1p_ddrmc_wrapper.v  IP 功能顶层（时钟/APB/PAXI/DDRIO 端口）
│   │   ├── src/adc/ddrmc_x32.adc        ★ DDR 引脚约束（set_ippin_assignment 70 条 + set_ipinst_assignment 17 条）
│   │   ├── src/sdc/ddrmc_x32.sdc        ★ IP 层时序（derive_clocks + 5 条 rename_clock + async group）
│   │   ├── src/rtl/**（52 个文件）       ★ DDRPHY/MC 本体（含加密的 mc0_alc_mc_top_all.enc.sv）
│   │   │   ├── include/ph1p_mis_define.vh        （被 include：DRAM_DDR3/DDR3_2G/DDR3_X16/DDR3_800D/PH1P100/PH1P_VCCIO_1V35）
│   │   │   ├── phy/include/ph1p_ddrphy_board_delay.vh  （生成物：Training 使能时 42 行全 0）
│   │   │   └── timing/ddr3/*.vh
│   │   ├── sim/fileset/fileset_mis.f     仿真 filelist（含 <mis_path> 占位）
│   │   └── .params_*/​.m_params_*/​.ports_*   TD 自写的参数/端口快照（建议保留做对照，也可删）
│   ├── ddrmc_x32_drc_check.log          ← 同级兄弟；入库（写清了 PASS）
│   ├── ddrmc_x32_adc.log                ← 同级兄弟；入库（信号→Bank/Byte/Bit 的映射，71~72 行）
│   └── ddrmc_x32_proc.log               ← 同级兄弟；入库（生成流水 12 行）
└── constraints/ph1p_pcie_case_ep.adc    ← **不要**把 ddr_* 写进这里（见 §2.7-9）
```

- **不要**把 `src/adc/*.adc` 拷到 `constraints/`；它是 IP 引脚约束，由 IP 自己带进工程，重复写会打架。
- **不要**勾（若有）"Copy sources into project"——复制一份 RTL 之后 IP 再生成会对不上（本仓规范也明确不勾）。
- 编译产物（`*_Runs/`、`*.bit`、`al_ip` 里的 `.db`）不入库。

## 2.5 在现有工程里注册

**A. GUI 生成时自动登记**：建 IP 时 TD 会往 `.al` 里写一条（上一轮实测：`create_ip` 出来的实例在 `.al` 里已有 `<IP_FILE> al_ip/dd3_mc_0/ddr3_mc_0.xml`，`CompileOrder 39`）。对应结构（本工程现有条目原文，`ph1p_pcie_ep_top.al:315-340`）：

```xml
<IP_FILE>
  <File Path="al_ip/pcie_ep_core/pcie_ep_core.xml">
    <FileInfo>
      <Attr Name="UsedInSyn" Val="true"/>
      <Attr Name="UsedInP&R" Val="true"/>
      <Attr Name="BelongTo" Val="design_1"/>
      <Attr Name="CompileOrder" Val="36"/>
    </FileInfo>
  </File>
  <!-- ... pcie_pll_ep(37)、ram(38) ... -->
</IP_FILE>
```

**B. 用 `create_project.tcl` 重建工程时**：在 IP 那 3 行后面加 1 行（`create_project.tcl:42-44` 的现有写法）：

```tcl
add_files al_ip/pcie_ep_core/pcie_ep_core.xml
add_files al_ip/pcie_pll_ep/pcie_pll_ep.xml
add_files al_ip/ram/ram.xml
add_files al_ip/ddrmc_x32/ddrmc_x32.xml        ;# ← 新增，全相对路径，不带绝对路径
```
（`.al` 里的路径是相对工程根的；RTL/ADC/SDC 都由 `<name>.xml` 内部 fileSet 带进来，**只登记 xml 这一行**就够。）

**C. `.al` 会被静默重写这条坑**：
- 现象 A：TD 打开工程/建 IP 时会改写 `.al`（也见过 `<Project Path="...">` 被改成当前目录）；
- 现象 B（已踩过）：把工程的 IP 目录删空后再跑 `create_ip`，TD 重写 `.al` 并**静默删掉已有 IP 的 `<IP_FILE>` 条目**，表现为另一个模块变 black box。
- 对策：**动手前 `cp ph1p_pcie_ep_top.al /tmp/`**；生成后再 `git diff -- ph1p_pcie_ep_top.al` 看有没有被顺手改掉别的条目。

## 2.6 每步之后怎么验证（做对了看什么）

| 步 | 验证动作 | 正确结果 |
|---|---|---|
| 0 | `ls -l <F9P>.adc`；`grep -c set_ippin_assignment <F9P>.adc` | 文件存在；71 条左右（例程输入为 71 条） |
| 5（选完 ADC File Path 后） | 界面 DRC Check 文本框；`cat al_ip/ddrmc_x32_drc_check.log` | 文本框显示 `PASS`；日志末两行 `Complete all signals check ,the design rule check pass!` + `/***  DESIGN RULE CHECK END   *** /` |
| 5（同时） | `wc -l al_ip/ddrmc_x32_adc.log`；`tail -3` | ~71–72 行；末行附近有 `refclks,5,2,0,`（= H4 在 bank 索引 5 / byte2 / bit0） |
| 8（生成完） | `cat al_ip/ddrmc_x32_proc.log` | 12 行，每一行都以 `success` 结尾（对照 §1.5 的 12 行清单）。**少一行就是那一步没跑** |
| 8 | `find al_ip/ddrmc_x32/src -type f | wc -l`；`ls al_ip/ddrmc_x32` | `src/` 共 **52** 个文件；顶层有 `ddrmc_x32.v` + `ddrmc_x32_ph1p_ddrmc_wrapper.v` |
| 8 | `grep -E "MC_DATA_WIDTH|AXI_DATA_WIDTH|tCK|CWL|CL;|ROW_WIDTH|ADR_WIDTH|MC_ADDR_WIDTH|AXI_ADDR_WIDTH|DX_NUM|BK_NUM|AC_NUM" al_ip/ddrmc_x32/.m_params_ddr3_mc_0.txt`（`_ddrmc_x32`） | 800 口径应为：`tCK 2500`、`CWL 5`、`CL 5`(800D)/`6`(800E)、`DX_NUM 4`、`MC_DATA_WIDTH 256`、`AXI_DATA_WIDTH 256`、`ROW_WIDTH 14`、`ADR_WIDTH 14`、`MC_ADDR_WIDTH 27`、`AXI_ADDR_WIDTH 29`、`BK_NUM 2`、`AC_NUM 3` |
| 8 | `cat al_ip/ddrmc_x32/src/rtl/include/ph1p_mis_define.vh` | `MC0_DRAM_DDR3` / `MC0_DDR3_2G` / `MC0_DDR3_X16` / **`MC0_DDR3_800D`** / `PH1P100` / **`PH1P_VCCIO_1V35`** / `DHI_DATA_FORMAT_BYTE` |
| 8 | `grep -c set_ippin_assignment al_ip/ddrmc_x32/src/adc/ddrmc_x32.adc`；`grep -c set_ipinst_assignment ...` | 70 / 17（32bit、4 DQ byte、CK1/CS1/CKE1/ODT1/reset1 的口径；不含 `ddr_addr[14]`，因为 `ADR_WIDTH=14` → 只到 `ddr_addr[13]`） |
| 8 | `grep -n "ddr_addr\|ddr_dqs_p\[0\]\|ddr_dq\[0\]" al_ip/ddrmc_x32/src/adc/ddrmc_x32.adc | head` | 球号应与 F9P 手册一致（例如 `ddr_dq[0] = U3`、`ddr_dqs_p[0] = R3`）。**这一步是"选错 ADC 文件"的唯一兜底检查** |
| 8 | `grep -c fileSet al_ip/ddrmc_x32/ddrmc_x32.xml` / 看 `fs-<name>` | 生成前为 0，生成后出现 1 个 fileSet，列出 ~53 个文件 |
| 9（注册后） | `grep -n "ddrmc_x32.xml" ph1p_pcie_ep_top.al` | 有 `<File Path="al_ip/ddrmc_x32/ddrmc_x32.xml">` 条目 |
| 9 | TD 里 `report_ip_status [get_ips ddrmc_x32]`（或 GUI 的 IP 状态提示） | 没有 locked / 需要 upgrade |
| 9 | 例化 + 编译（`build.tcl`） | 无 `HDL-8007 ERROR: xxx is a black box`；place 报告的 IO 与 `_adc.log` 一致 |

## 2.7 已知坑清单（含本机踩过/查到的）

1. **`set_property` 参数顺序反 Vivado**：TD 是 `set_property <值> <参数名> <对象>`（`SWUG105` §4.5.13.1）。**写反不报错**，只丢一条 `USR-7001 CRITICAL-WARNING: set_property object:ddr3_mc_0 name:DDR3 value:CONFIG.PH1P_DDR_TYPE error`，`catch` 仍返回 0 → "set 了没生效"。【实测·上一轮】
2. **`open_project` 之后必须先 `load_project_ips`**（否则 `get_ips` 拿不到 IP）。GUI 下无需关心。【实测·上一轮】
3. **"批处理不产 RTL"这句话要修正**：`generate_target` 是产 RTL 的（RAM IP 实测 rc=0、产出 `RTL/ram_ram.v`）；MIS DDR 失败是 `PH1P_IO_ASSIGN` 为空导致 `gen_adc.tcl:open ""` → `IPT-1002`。所以参考工程 README 里那条"生成 IP RTL 是 GUI 动作"只对**没配 ADC 的 DDR IP**成立。
4. **`.al` 会被静默重写**：见 §2.5-C。动手前备份。
5. **ADC File Path 是空/错的**：空 → 必失败（`open ""`）；错（拿 depot 自带 example_adc）→ DRC 也可能 PASS，但**引脚全到别的板上**。唯一兜底是 §2.6 里"比对 `ddr_dq[0]/ddr_dqs_p[0]/ddr_addr[*]` 的球号"。
6. **`PH1P_SYSCLK_LOC` 的可选值随 ADC 文件变**：例程（SINGLE 口径）是 `H4;;G4`；换成 DIFF 口径会变成 `V4,W4` 之类。先定 **RefClk Type**，再选 **RefClk Location**。
7. **例程那版 1600 的 CWL=5 不是 JEDEC 合法组合**（CL=11 要求 CWL=8；`DS-00843` 表 11-2 里 5/6/7 是 Reserved；`ipgen.log` 证明 CWL 没被人点过 = 默认值）。选 800 档就天然避开（800 只能选 CWL=5）。
8. **IP/工具版本差**：09 例程 IP 由 6.2.2(build 190657)/IpTool `189136 2026/01/26` 生成，本机是 `6.2.3.210850`。先例：现有 `al_ip/pcie_ep_core`（IpTool 171484 生成）在 210850 下正常编译 → 版本差**不必然**触发升级；但 TD 里有 `ip_upgrade`/`report_ip_status`/"be locked, please upgrade it before generate" 机制 → 生成后**先看有没有升级提示**，必要时在 GUI 里点升级。
9. **DDR 引脚必须在顶层与 IP 实例直连**：DDR 管脚来自 IP 的 `set_ippin_assignment`（IP 引脚约束），例程的**顶层 adc（`prj_src/adc/ap115v2.adc`）里一条 `ddr_*` 都没有**。所以：(1) 不要把 `ddr_*` 写进顶层 `.adc`；(2) `ddr_*` 从 IP 实例**直连**顶层端口，中间不许插逻辑（ILA/mux/IBUF）；(3) 顶层端口名/位宽要与 IP 一致（`ddr_ck_p/ddr_ck_n`、`ddr_addr[13:0]`、`ddr_dq[31:0]`、`ddr_dqs_p/n[3:0]`、`ddr_dm[3:0]`、`ddr_ba[2:0]`、`ddr_cke/odt/cs_n/ras_n/cas_n/we_n/reset_n`）。「IP 引脚约束一定派生顶层管脚」这一点 TD 文档没定义（SWUG105 里没有 `set_ippin_assignment`）→ 例程事实如此，**首次编译后要核对 place 的 IO 报告**。
10. **`ph1p_ddrphy_board_delay.vh` 里全 0 是正常的**（Training 使能时不用手工 board delay）。
11. **加密源码不要动**：`src/rtl/mc/mc0_alc_mc_top_all.enc.sv`。
12. **别把 `sim/` 里的 `<mis_path>` 当绝对路径**：`fileset_mis.f` 有占位符，是本机无仿真器也能留着的东西；本机不跑仿真。

## 2.8 生成之后，与现有 PCIe EP 工程集成还要做的 5 件事

（详细推导见 `doc/ddr_bringup_plan.md` §2/§3，这里只列动作）

1. **时钟共享，不抢脚**：顶层只留一个 `sys_clk`（H4，约束已在 `constraints/ph1p_pcie_case_ep.adc:17`，**不要动**），把同一网络**同时**给它 `u_ddrmc_x32.ref_clk` 和 `u_pcie_pll_ep.refclk`（`rtl/ep_side/ph1p_pcie_ep_top.v:243-247`）。IP 自己不给 refclk 写引脚约束。
2. **复位等你必须接的 IP 输出**：用户逻辑用 IP 输出的 `ddrphy_rst_n` 做复位、`ddrphy_rdy`(=`cal_done`) 到了才能发第一次 PAXI 访问。
3. **SDC 补异步时钟组**：IP 自带 `src/sdc/ddrmc_x32.sdc`（`derive_clocks` + `rename_clock` 出 `ref_clk/ctl_clk/ddr_clk/mcu_clk/usr_clk`）。要把它并进顶层 `constraints/ph1p_pcie_case_ep.sdc` 已有的异步组（否则 `usr_clk`=dhi_clk(800档 100MHz) 会跟 `tl_clk_user`(62.5MHz) 当真同步去算，必然假违规）。时钟名第一次 `report_clocks` 看一眼再写死。
4. **用户侧是 PAXI，不是 AXI4**：256bit/拍（32B）、无 len/size/burst、读写不能同拍发、写掩码极性文档与例程矛盾（IPUG034 表 2-10 说高有效，例程恒置 0）→ bring-up 时两种都试。现有 PCIe 用户逻辑要接 DDR 需 PAXI 直连或自己加桥。
5. **资源账**：DDR IP 自己吃 `#eram 41/300`、`#pll 2`、`#gclk 3`、`#ioclk 4`、`#mlclk 2`（09 例程实测）；现有工程 `#eram 124/300`（含 640×480 帧缓存）→ 合计约 55%，能过但紧；把整帧搬进 DDR 后应删掉片内大数组。DDR 占 BANK32/33，相机在 BANK13，PCIe 在 BANK94/12，**球号零冲突**。

---

## 附录 A：本次结论分级总表

| 结论 | 分级 | 依据 |
|---|---|---|
| DDR IP 包内有完整生成脚本链（plugin_end.tcl + 13 个 script/*.tcl） | 【静态】 | 包目录 + `Component.xml` fileSet + 脚本原文 |
| `generate_target` 对 MIS DDR 报 `IPT-1002 ... couldn't open ""` | 【实测】 | `/tmp/ddr_exp_run7_gen2.txt:147-149`、run9 `:281-283` |
| 同一命令对 RAM IP 产 RTL | 【实测】 | run7 `:157-183` |
| 命令行建出的实例 `PH1P_IO_ASSIGN` 为空 | 【实测】 | run10 `:264-265`、`/tmp/ddr_dumps_before/.params_ddr3_mc_0.txt:117` |
| 空路径来自 `gen_adc.tcl` 的 `open $adc_file r`（= `$PH1P_IO_ASSIGN`） | 【静态】（强） | `gen_adc.tcl:22/56/75/1023`；且包内"唯一的空实参 open"只有它（Layout.tcl 无 open，Dependency.tcl 全部 open 的实参都非空） |
| `[Error-TclFile]` 由 `GenWindow::addGenSourceTclError` 产生 | 【静态】 | 格式串 `[Error-%1] %2` 唯一 xref @`0x868c79`；类别串 `TclFile` @`0x1cbd74c` 唯一引用 @`0x868de6` |
| `IPT-1002`/`IPT-1001` 是 IpTool 的 ERROR/普通消息编号 | 【静态】 | `bin/IpTool` 消息输出代码里的 `ERROR:`/`WARNING:` 前缀分流与 `movabs "IPT-1002"` |
| 填上真实 ADC 后整链跑通（12 步全 success、52 个 src 文件、DRC PASS） | 【旁证】 | `/tmp/ddrip_exp/al_ip/` 19:36 产物（**非本次操作**，见开头警告） |
| 姿势 A（`set_property <adc> CONFIG.PH1P_IO_ASSIGN` + `generate_target`）能通 | 【推论】/【未确认】 | 缺口唯一 + 旁证；**未实测** |
| 姿势 B（`create_ip -user <实例xml>`）能通 | 【未确认】 | IpTool usage 有 `-user`；本机实测过 `create_ip -user .../ram/ram.xml` 这一步；未验证 DDR |
| 8 个 depot 自带 `example_adc/*.adc` 不是 F9P 引脚 | 【静态】 | 文件头 `DEVICE: PH1P50MBG484` 等；关键球号与 F9P 版逐条不同（§2.0 表） |
| 800Mbps 是 PH1P100+DDR3 的器件口径 | 【静态】 | `DS1300` 表 3-60 / 表 1-2；板卡手册 |
| F9P DDR 在 BANK32(DQ)/BANK33(AC)，refclk=H4 | 【静态】 | `_adc.log` bank 列 + `pkg/PH1P100SBG484.csv:262` + `pkg/cfg.csv`；`doc/ddr_bringup_plan.md` §1.6/§3.4 |
| PZQ 是否需要开、VRP 是否已接 240Ω | 【未确认】 | 板上原理图未查证；例程是关的 |
| GUI 建 IP 时自动写 `.al` 的 `<IP_FILE>` | 【实测·上一轮】 | 上一轮 `create_ip` 后 `.al` 里出现 `al_ip/ddr3_mc_0/ddr3_mc_0.xml` |

## 附录 B：证据索引（路径 : 行 / 地址）

**本次实测读取（只读）**
- `ph1p_pcie_ep_top.al:315-340`（IP_FILE 结构，pcie_ep_core/pcie_pll_ep/ram）
- `create_project.tcl:42-44`（`add_files al_ip/<name>/<name>.xml` 的写法）、`:40-41`（约束）
- `constraints/ph1p_pcie_case_ep.adc:17`（sys_clk H4 SSTL135）
- `bin/td`：`IpGenerateTarget` @`0x61cd820`；rodata `0x807c781`=`generate_target`；`strings` 里的 `IPT-1002 ERROR: No IP matching the VLNV` / `... does not support creation using TCL commands.`、`isBatchSupportedIp`/`batchWhitelist` 符号
- `bin/IpTool`（未 strip）：`IpGenGenerateInst` @`0x8a2660`（含 `ipWatchDesignXmlFile`@`0x7ec100`、`ipGenInstWithoutGui`@`0x7ebf00`、`getGenErrorForBatch`@`0x860ec0`、rodata `0x1cc09e3`/`0x1cc0a01`/`0x1cc10f0`）；`GenWindow::generateXmlForBatch`@`0x88c300`；`addGenError`@`0x868c60`（`[Error-%1] %2`@`0x1cbd73d`）；`addGenSourceTclError`@`0x868d90`（`TclFile`@`0x1cbd74c`）；4 个调用点 @`0x867cdc`/`0x869004`/`0x8691de`/`0x87bff2`；`sourceTclDependFiles`@`0x87bf20`（`Dependency.tcl`）；`invokePluginTcl`@`0x869120`（`/Other/plugin_end.tcl`@`0x1ce592c`、`/Other/plugin_mid.tcl`@`0x1ce5916`、`run plugin end.tcl`@`0x1cbd754`）；`AL_IpDesign::runPluginEndTcl`@`0xcc03a0`/`runPluginMidTcl`@`0xcc0090`；`cmdAliptIptoolGenTarget`@`0xa98ba0`（stub）
- `ip/depot/MIS_DDRF6F1D0P0_1.2/`：`Component.xml`（fileSet 名 `PH1P_DDRMC_IP`/`PH1P_DDRPHY_IP`，含 `Other/plugin_end.tcl`、`Other/upgrade.tcl`）；`Dependency.tcl:122`（`PH1P_IO_ASSIGN` 无 value）、`:154-179`（get_cfg_row 读 `pkg/cfg.csv`）、`:813-854`（update_cl）、`:856-901`（update_cwl）、`:1122-1130`（drc_check 建日志）、`:1219-1229`（adc 不存在 → 置错并 return ""）、`:1236-1237`（跳过 set_ipinst_assignment）、`:1982`+`:2228`（写 `_adc.log`）、`:2273-2286`（cal_onlyacbkby）、`:2404-2465`（update_sysclk_loc）、`:2642-2660`（update_bk_num）
- `.../PH1P_DDRMC_IP/Other/plugin_end.tcl`（154 行，逐行 source 表见 §1.2(5)）、`.../script/gen_adc.tcl:22/56/75/1023`、`.../PH1P_DDRPHY_IP/Other/plugin_end.tcl`
- `ip/depot/MIS_DDRF6F1D0P0_1.2/Layout.tcl`（GUI 布局：8 个 group、每项 label，见 §2.2 表；`DDRMC/DDRPHY` 两个 view）
- `ip/depot/MIS_DDRF6F1D0P0_1.2/example_adc/*.adc`（8 个，含 `ap115_ddr3_x32.adc` 头部 `DEVICE: PH1P50MBG484`）
- `/mnt/nvme/fpga/TD/work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/`：`prj_src/ip/ddrmc_x32/.params_ddrmc_x32.txt`（例程全参数）、`Design.xml`（`PH1P_IO_ASSIGN` 指向 `golden_adc/ap115v2_ddr3_x32.adc`）、`golden_adc/ap115v2_ddr3_x32.adc`（F9P 球号）、`prj_td/log/ipgen.log`（GUI 回放）
- `doc/IPUG/IPUG034_PH1P_MIS_IP_Guide.pdf`（本次读的是既有文本副本 `/tmp/ipug034.txt`）：§3.1.1（第 1759 行：Tools → IP Catalog → Primitive IP → Memory and Storage → MIS - DDR2/DDR3/DDR4；Setup Exporting Options 的 Export Path/Component Name）、§3.1.2（第 1800-2039 行：8 组参数逐项定义、Speed Bin 表 3-1、阻抗表 3-2、AXI 使能表 3-3、ADC 信号名表 3-4、Training 说明）、§3.2（第 2075-2108 行：输出文件表 3-5/3-6）
- 上一轮日志：`/tmp/ddr_exp_run7_gen2.txt:130-183`、`/tmp/ddr_exp_run9_setprop.txt:281-283`、`/tmp/ddr_exp_run10_f9p.txt:264-265`、`/tmp/ddr_dumps_before/.params_ddr3_mc_0.txt:117-124`、`/tmp/pi_ddrip2.log`

**【旁证】（19:36，非本次操作）**
- `/tmp/ddrip_exp/al_ip/ddr3_mc_0/`（`ddr3_mc_0.xml` 35604B 含 `fs-ddr3_mc_0` 53 项、`src/**` 52 文件、`src/adc` 70+17 条、`src/sdc` 12 行、`src/rtl/include/ph1p_mis_define.vh` 7 行）
- `/tmp/ddrip_exp/al_ip/ddr3_mc_0_proc.log`（12 行）、`_drc_check.log`（9 行）、`_adc.log`（72 行）
- `/tmp/ddrip_exp/al_ip/ddr3_mc_0/.params_ddr3_mc_0.txt:117`（`PH1P_IO_ASSIGN = .../example_adc/ap115_ddr3_x32.adc`）、`:119`（`PH1P_DRC_CHECK : PASS`）

**调查报告（本仓既有）**
- `doc/ddr_bringup_plan.md`（DDR 集成调查：速率口径/引脚 bank/PAXI 协议/自检设计）

## 附录 C：本报告没做的事

- 没有跑 `create_ip` / `set_property` / `generate_target` / 任何 TD 命令（§1.6 的两条姿势都只是静态判断，标【推论】/【未确认】）；
- 没有构建工程、没有 `bw.sh`、没有 ssh 板子、没有下载/安装任何软件；
- 没有修改除本文件以外的任何文件（本文件是唯一新增；工作区 19:32–19:38 期间出现的 `.al` 改动与 `2deadef` 提交都不是本次产生的，见开头警告）；
- 没有跑仿真（本机无仿真器，已知环境限制）。

## 附录 D：下一步建议（按代价从小到大）

1. **放行一次 15 秒的 headless 实验**（就是把 §1.6 姿势 A 跑一遍），一锤定音"命令行能不能拿 DDR RTL"，并把 §1.1 的 R2 风险销掉。
2. **GUI 生成 800Mbps 版**（§2 清单），生成时**务必用 F9P 的 adc**（§2.0）。
3. 生成后先只做 S0：拷贝/登记 + 顶层例化（DDR 直连、`ref_clk=sys_clk`）+ 编译，确认无 black box、IO 与 `_adc.log` 一致；再进自检设计（`doc/ddr_bringup_plan.md` §3.10）。
