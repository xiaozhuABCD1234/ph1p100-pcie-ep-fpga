- 日期：2026-10-15
- 来源：r9000p 上 pi 编码 agent 的只读取证会话（本次未改任何工程文件）。
- 内容由 pi 给出，入库时未作改动。

---

# `TMST-7700` / `RTCLK-5079` 只读取证报告

**本次动作**：只读。未改工程内任何文件（`git status --short` 为空，`git status --porcelain -uall` 为空）；未创建任何临时文件（不需要，见下）；未重跑构建；未调用 TD；未 ssh 板子；未做任何 git 写操作。

**一个重要更正**：任务书写"没有 check_timing 报告落盘"——**实际已落盘**：

| 文件 | 大小 | 时间 | 产生处 |
|---|---|---|---|
| `ph1p_pcie_ep_top_Runs/phy_1/ph1p_pcie_ep_top_chk.timing` | 5231 B | 2026-10-15 20:28:32 | `phy_1/ph1p_pcie_ep_top.tcl:242` `check_timing -verbose -file ${prj_name}_chk.timing`（route 步骤） |

它和 `final_timing.rpt`(20:28:30)、`route_clock_utilization.txt`(20:28:32)、`ph1p_pcie_ep_top_exception.timing`(20:28:32) 同一时刻，就是那次 20:28 出 bit 的构建产物。所以 Q1 不需要跑 TD 查询（而任何 td 调用都可能触碰 run 目录，违反只读，故不做）。

---

## 1. 那 3 / 6 条严重问题到底是哪几条（实测，原文直引）

`phy_1/ph1p_pcie_ep_top_chk.timing:3-16`（报告目录，括号里就是条数）：

```
1. checking no clock(3) (HIGH)
2. checking clock definition(3) (HIGH)
3. checking dummy node(1) (HIGH)
4. checking invalid constraint(0) (HIGH)
5. checking pll clock constraints(0) (HIGH)
6. checking combinational loops(0) (HIGH)
7. checking soft fifo timing exception constraints(0) (HIGH)
8. checking no path constraints(0) (MEDIUM)
9. checking shadowed/ignored timing exception constraints(0) (MEDIUM)
10. checking no input delay(29) (MEDIUM)
11. checking no output delay(17) (MEDIUM)
12. checking partial input delay(0) (MEDIUM)
13. checking partial output delay(0) (MEDIUM)
14. checking abnormal input delay(0) (MEDIUM)
```

### 1.1 类别 = "无时钟 / 无根时钟驱动"（3 条，HIGH）

`chk.timing:19-28` 原文：

```
1. checking nets with no clock driven. (HIGH)
---------------------------------------------
There is 1 clock net that with no clock driven by root clock pin: u_cfg_a/X_ui_i2c/scl_clk_reg_syn_9.oqa. (HIGH)

	u_cfg_a/X_ui_i2c/scl_clk

There are 2 clock nets that with no clock driven by root clock pin: u_pcie_pll_ep/ph1p_phy_pll_wrapper_Inst/u_PH1P_PHY_PLL.lock. (HIGH)

	u_ph1p_pcie_ep_subsystem_top/tl_clk_user_ce_n
	pcie_pll_locked
```

逐条：

| # | 网络 | 根驱动 | 性质 |
|---|---|---|---|
| 1 | `u_cfg_a/X_ui_i2c/scl_clk` | 寄存器输出 `…scl_clk_reg_syn_9.oqa` | i2c 内部 SCL 时钟（`rtl/ep_side/cam/ui_i2c.v:81` `reg scl_clk = 1'b0;`，被 `always@(posedge scl_clk)` 当钟用）→ 有物理时钟网但**没有 `create_clock`/`create_generated_clock`** |
| 2 | `u_ph1p_pcie_ep_subsystem_top/tl_clk_user_ce_n` | PLL 的 `.lock` 脚 | 见下 |
| 3 | `pcie_pll_locked` | PLL 的 `.lock` 脚 | `rtl/ep_side/ph1p_pcie_ep_top.v:266` `.lock(pcie_pll_locked)`；`:324` `.tl_clk_user_ce_n(!pcie_pll_locked)`，`tl_clk_user_ce_n` 直接进 PCIe core 的**时钟使能脚**（`al_ip/pcie_ep_core/pcie_ep_core.v:22`），TD 把 CE 脚算成 clock pin |

即**不是**"生成时钟未约束"（2.5 = 0），而是这三条：**寄存器产生的时钟没声明** + **PLL lock 网络被当钟树用但无时钟源**。

### 1.2 类别 = "时钟定义问题 / local clock"（3 条，HIGH）

`chk.timing:41-45` 原文：

```
2.4 There are 3 local clocks. (HIGH)

	cam_a_byte_clk
	cam_b_byte_clk
	sys_clk
```

- `cam_a_byte_clk` / `cam_b_byte_clk`：`constraints/ph1p_pcie_case_ep.sdc:21-22` 定义的 generated clock，根是 `u_csi_a/u_rx_phy/u_hs_clk_div.clkdivout`（**LCLK** 输出），故根不是专用全局时钟源。
- `sys_clk`：`sdc:1` `create_clock … [get_ports {sys_clk}]`，但物理上走局部绕线（= `RTCLK-5079`），所以被判成 local clock。

### 1.3 另外 1 条 HIGH（不是时序约束）+ MEDIUM 两类

`chk.timing:50-52`：`There is 1 node is dangling. (HIGH)`，20 个 `PH1P_PHY_HR_PAD` 的 `…rdiff_enb`（MIPI 差分输入使能，未驱动 = 正常悬空）。

`chk.timing:12-13` + 明细：**29 个输入端口无 input delay**（cam_a_sda, mipi_a/b_*, pcie_mperst, pcie_power_on_rst, pcie_rx_p/n, ref_pad_clk_p/n, user_int_trigger），**17 个输出端口无 output delay**（cam_*_mclk/scl/sda/xclr_n, debug_led[3:0], pcie_tx_p/n, txd）。全是 **MEDIUM**。

### 1.4 "3 SEVERE / 6 SEVERE" 与上面的对应（**推论**）

`phy_1/run.log:780`（placement 阶段 8.10）`DRC TMST-7700 CRITICAL-WARNING: 3 SEVERE …`
`phy_1/run.log:1372`（route 阶段 5.10）`DRC TMST-7700 CRITICAL-WARNING: 6 SEVERE …`

最吻合的算术是：**SEVERE = "no clock"(3) + "local clock"(3)**，dangling node 不计入"timing constraint issue"；placement 阶段只算出 no-clock 的 3，route 后叠加 local-clock 的 3 → 6。
**这一条是推论**：TD 没有公开计数规则，且 `check_timing` 只在 route 步骤写盘（`phy_1/ph1p_pcie_ep_top.tcl:242`），placement 阶段的 3 条明细没有落盘，无法逐条比对。

---

## 2. 是接入 DDR 之后才出现的，还是之前就有？（实测证据链）

**结论：接入 DDR 之前就有。DDR 提交一行约束/RTL 都没改。**

证据 1 —— DDR 提交的范围（`git show --stat 61b9100`）：

```
63 files changed, 19567 insertions(+), 2 deletions(-)
 .../MIS_DDRF6F1D0P0_0/src/sdc/MIS_DDRF6F1D0P0_0.sdc   |   12 +
 ph1p_pcie_ep_top.al                                   |   17 +-
```
`git show --name-only 61b9100 | grep -E "^(constraints|rtl|sim_do)/"` → **无输出（exit=1）**。63 个文件全是 `al_ip/MIS_DDRF6F1D0P0_0/**` + `.al`。

证据 2 —— 约束文件的改动史只有两次，都在 DDR 之前：

```
21dd0e6 2026-10-15 17:44:37  修正 IMX415 MCLK 为 25MHz/平均占空 50%，并补两路 MIPI 字节时钟 SDC   ← constraints/ph1p_pcie_case_ep.sdc
97dceec 2026-10-15 15:53:25  初始提交…
```

证据 3 —— **SDC 自己承认见过 TMST-7700**（`constraints/ph1p_pcie_case_ep.sdc:28`，17:44 那次提交写的）：

```
# …（实测预算只剩 0.004ns），报出与逻辑无关的 −6.8ns 假违规（TD DRC TMST-7700/5089）。
```

证据 4 —— 三条主问题的 RTL 来源全是 DDR 之前提交的：
`rtl/ep_side/ph1p_pcie_ep_top.v:846-850`（r_mdiv2，`git log` 最后改动 `c2daa30` 19:16）、`rtl/ep_side/cam/ui_i2c.v:81`（scl_clk）、`top.v:264/324`（sys_clk→PLL refclk、PLL lock→CE）。

证据 5 —— **DDR IP 在 20:27 构建里根本没被例化**：

- `td_20261015_202725.log` 里 `Successfully analyzed 81 source files`（含 `al_ip/MIS_DDRF6F1D0P0_0/…`）——只是编译；
- 但 `phy_1/run.log` 的 Design Statistics：`#ddr_byte 0 out of 24`、`#IO 37 out of 286`、`#pll 1`，没有 DDR 硬核；
- 全仓库 `grep -rn "MIS_DDRF6F1D0P0_0" --include=*.v --include=*.al …` 除 `al_ip/` 自身，只有 `.al:346` 的 `<IP_FILE>` 一条 → **顶层没有例化**。

→ DDR IP 既不可能制造、也不可能消掉这些 DRC。

证据 6 —— DDR 带来的 sdc/adc **没有被读入**：

- `phy_1/settings.cfg:3-4` 与 `syn_1/settings.cfg:3-4`：
  `set IpADCList { pcie_ep_core ../../al_ip/pcie_ep_core/pcie_ep_core.adc }`
  `set SDCList {"../../constraints/ph1p_pcie_case_ep.sdc"}`
  **没有 `IpSDCList`**（而 flow 脚本支持它：`phy_1/ph1p_pcie_ep_top.tcl:93/111-114` `read_sdc -ip`）。
- `.al:299-319`：`ADC_FILE` 只有 `constraints/ph1p_pcie_case_ep.adc`，`SDC_FILE` 只有 `constraints/ph1p_pcie_case_ep.sdc`。
- IP 其实自带了：`al_ip/MIS_DDRF6F1D0P0_0/src/sdc/MIS_DDRF6F1D0P0_0.sdc`（12 行，`derive_clocks` + 5 个 `rename_clock` + `set_clock_groups -asynchronous -group [get_clocks mcu_clk]`）与 `src/adc/MIS_DDRF6F1D0P0_0.adc`（91 行）——**当前构建未生效**。

**未确认**：没法给出"同一份报告"的前后对比——`phy_1/run.log` 被 20:27 构建覆盖了（根目录 `td_*.log`(16:56~19:12) 只是 `import_device/open_project/launch_runs/wait_run` 的启动日志，不含 DRC 段）。所以第 2 问的判定是靠上面 6 条间接证据链，而不是直接 diff。

---

## 3. `RTCLK-5079`：r_mdiv2 是谁 / 为什么走局部绕线 / 收尾方案清单

### 3.1 报错原文（`phy_1/run.log:1366-1371`）

```
DRC RTCLK-5079 CRITICAL-WARNING: Detected clock net "sys_clk_dup_1" driven by clock source instance utilizes local routing resource(s), which may degrade the timing performance in ../../rtl/ep_side/ph1p_pcie_ep_top.v(26).
Driver instance pin: sys_clk_syn_2.di (AL_PHY_PAD:H4(GCLK IO))
Fanout(Local/Clock/Total)=1/2/2
Sink pins with local routing (the first 5 ones):
r_mdiv2_reg_syn_3.clk
```

### 3.2 `r_mdiv2` 是谁（实测）

`rtl/ep_side/ph1p_pcie_ep_top.v:844-853`：

```verilog
// ---- (b) 50MHz sys_clk ÷ 4 = 12.50MHz（整数分频，占空 50%、周期零抖动）----
reg r_mdiv2     = 1'b0;
reg r_mclk_c125 = 1'b0;
always @(posedge sys_clk) begin
    r_mdiv2 <= ~r_mdiv2;
    if (r_mdiv2) r_mclk_c125 <= ~r_mclk_c125;
end
wire w_mclk = r_mclk_sel_f ? r_mclk_c125 : r_mclk_125;   // :853
```

- **用途**：IMX415 传感器 MCLK 的"候选源 B"（`sys_clk` 50MHz ÷4 = 12.5MHz）。`top.v:865-866` `assign cam_a_mclk = w_mclk; assign cam_b_mclk = w_mclk;`
- **当前默认配置下是否在用**：**输出侧没被选中，但寄存器一直在跑**。
  - 选择位来自 CTRL[2]：`top.v:789` `wire w_mclk_sel_raw = img_pattern[0];` → 经 16 拍去抖 `r_mclk_sel_f`（`:793-800`）。
  - 默认值：`rtl/ep_side/img/ep_bar_win.v:144-145` `ctrl_pattern_r <= 2'd0; ctrl_cam_sel <= 1'b0;`，`img_pattern = {ctrl_cam_sel, ctrl_pattern_r[0]}`（`:133`）→ 上电 CTRL[2]=0 → 走 `r_mclk_125`（62.5MHz `tl_clk_user` 那档，`top.v:836-842`），**不走 r_mdiv2**。
  - 但 `r_mdiv2`/`r_mclk_c125` 没有时钟门控，上电就在翻转 → **在网表里是活逻辑**，这是 sys_clk 的第 2 个时钟负载。
  - 顺带更正一个常见误读：`top.v:1010-1011` 的诊断计数器 `r_syscnt` 无读者，已被优化掉（`final_timing.rpt` 里 sys_clk 只有 2 个端点），所以它不在负载里。

### 3.3 为什么只 2 个扇出还走局部绕线（实测）

sys_clk 的全部负载（`route_clock_utilization.txt:226`，原文）：

```
| local_16 | N/A | PH1P_PHY_HR_PAD | None | 2 | 2 | sys_clk_dup_1 | PH1P_PHY_LSLICE(1) | PH1P_PHY_PLL(1) |
```

= `r_mdiv2` 那 1 个 LSLICE 寄存器（`final_timing.rpt:4293-4310` 的 `sys_clk -> sys_clk` path group，Begin/End = `r_mdiv2_reg_syn_3`，`Statistics: … 2 Total Endpoints`）+ PCIe PLL 的 `.refclk` 1 个（`top.v:264`）。

- `final_timing.rpt:55`：`clk7  local  …  20.000  50.000  …  Fanout 2  Max-Level 1` → STA 已经把 sys_clk 标成 **local** 类型。
- `route_clock_utilization.txt:62`：`| local_16 | PH1P_PHY_HR_PAD | sys_clk_syn_2.di | … | x77y101z0 | 2 | 2 | 20.000 | sys_clk | sys_clk_dup_1 |`
- **placement 阶段就已经是这个走法**（`place_clock_utilization.txt:211` 同样列出 `local_2 | PH1P_PHY_HR_PAD | sys_clk_dup_1 | PH1P_PHY_PLL(1) | PH1P_PHY_LSLICE(1)`）→ 不是布线失败，是**结构性判决**。
- 原因（**推论**，机制清楚）：sys_clk 只有 2 个负载，远低于 TD 的高扇出/全局树插入门限（本次 `hfn_to_clock=1000000000`，见 `td_20261015_202725.log`），且它直接从 GCLK-capable IO pad H4（`adc:17` `LOCATION = H4; IOSTANDARD = SSTL135`）出来，TD 就按 `local_16` 走；对比组：`tl_clk_user`(fanout 1432) 插了 GCLK，`scl_clk` 也被自动插了 `…created_gclkinst…`（`route_clock_utilization.txt:225`），连 `bufg_feedback` 都插了。

### 3.4 收尾方案清单（**只列取舍，不实施**）

| 方案 | 做法 | 收益 | 代价 / 风险 |
|---|---|---|---|
| A. 给 sys_clk 走专用时钟资源 | RTL 里显式经 `PH1P_PHY_BUFG`（或让 TD 对 sys_clk 插 GCLK） | 直接消掉 RTCLK-5079 和 check_timing 2.4；PLL 前 skew 可控 | 改 RTL 或用属性；+1 全局钟（现用 4/32，余量够） |
| B. 删掉不用的一档分支 | 去掉 `r_mdiv2/r_mclk_c125` 与 CTRL[2] 选择（并删 `r_syscnt`） | sys_clk 可能只剩 PLL refclk 一个负载，local clock 可能自动消失 | 丢失"50MHz÷4 干净 12.5MHz"备用 MCLK 源；若板测需要切源要重加；需要重跑构建验证 |
| C. 把 MCLK 分频搬进 `tl_clk_user` 域 | 用 62.5MHz 分频出 12.5MHz（占空可调但会有组合抖动） | sys_clk 退化成"纯 PLL refclk 输入"，结构最干净 | 改功能；12.5MHz 的占空/抖动要重算并上板复测 |
| D. 按差分约束重写 H4/G4 | `sys_clk` 改成差分对（H4/G4）+ 差分 `set_pin_assignment`，与 DDR IP 的 `PH1P_REFCLK_TYPE=DIFF` / `PH1P_SYSCLK_LOC=H4,G4` 对齐 | 与 DDR refclk 方案一致，一次解决两个问题 | 与现 ADC（H4 单端 SSTL135，`adc:17`）冲突，必须同时改板级约束；PCIe PLL 能否接受差分输入需验证 |
| E. 只用约束"消音" | 对 sys_clk 加 `set_clock_groups`/忽略 DRC | 报告变干净 | **掩盖问题，不算收尾**；不推荐 |

同类问题（顺带）：`RTCLK-5078`（`phy_1/run.log:1360`，`u_cfg_a/X_ui_i2c/scl_clk` 由非时钟源驱动走局部绕线）与 §1.1 的第 1 条同源——根治要把 I2C 的 SCL 从"当 posedge 时钟用"改成"使能门控"，或给它补 `create_generated_clock`。

---

## 4. 结论：会不会影响后续 DDR 接入 / "构建通过带 CRITICAL-WARNING"要不要处理

### 4.1 对 DDR 接入的影响

**(1) 当前这批 TMST/RTCLK 对 DDR 接入"不构成直接冲突"**——但要说清两点边界：

- DDR IP 现在**未例化**（§2 证据 5），不是这些告警的来源；
- DDR IP 的 refclk 参数与我们现有的 sys_clk 引脚**类型不一致**：
  - `al_ip/MIS_DDRF6F1D0P0_0/.params_MIS_DDRF6F1D0P0_0.txt:122` `PH1P_REFCLK_TYPE : DIFF : U : En : DIFF;;SINGLE;;BUFG`
  - 同文件 `:124` `PH1P_SYSCLK_LOC : H4,G4 : U : En : H4,G4`
  - 而我们 `constraints/ph1p_pcie_case_ep.adc:17` `set_pin_assignment { sys_clk } { LOCATION = H4; IOSTANDARD = SSTL135; }`（单端）
  - **实测**：DDR IP 自己的 adc 里**没有** sys_clk 引脚约束（`grep sysclk al_ip/MIS_DDRF6F1D0P0_0/src/adc/MIS_DDRF6F1D0P0_0.adc` 无结果，文件里只有 `ddr_*` 的 `set_ippin_assignment` 和 `ph1p_ddrmc_wrapper/...` 的 `set_ipinst_assignment`），与 `doc/ddr_bringup_plan.md` 第 3 条的判断一致（"不是抢脚…IP 自己不给 refclk 写引脚约束"）。所以**引脚本身不冲突，但 DIFF vs SINGLE 必须定案**。

**(2) 接入 DDR 时几乎必然出现**新的 **TMST-7700**（这才是真风险）：DDR IP 会引入 PLL0/PLL1 与 `ref_clk/ctl_clk/ddr_clk/mcu_clk/usr_clk` 等一堆新时钟，而 IP 自带的 `al_ip/MIS_DDRF6F1D0P0_0/src/sdc/MIS_DDRF6F1D0P0_0.sdc`（12 行，含 `set_clock_groups -asynchronous -group [get_clocks mcu_clk]`）目前**没有被加入 `IpSDCList`**（两个 `settings.cfg` 都没有这个变量，`.al` 也没登记）。不登记 → 新 PLL 输出无约束/异步组缺失 → TMST-7700 条数会涨。

**(3) sys_clk 的局部绕线与 DDR refclk 复用**：接入后 sys_clk 要多喂一个 DDR refclk，扇出上升，TD 很可能自动插 GCLK → `RTCLK-5079` 可能自行消失；也可能变成更明显的 PLL 前 skew 问题。**未确认，必须接入后重跑 DRC 看。**

### 4.2 "构建通过但带 CRITICAL-WARNING"的处理建议与优先级

**要处理，但不必停线。** 依据（实测）：
- `phy_1/run.log:733` `RUN-0008 : Do timing check and 0 issue(s) found`
- `final_timing.rpt:24-26` `SWNS: 0.349ns, STNS: 0.000ns / HWNS: 0.021ns, HTNS: 0.000ns`
- `phy_1/run.log:1314` route 后 timing check 仍 0 issue
→ 当前 bit 功能可用；但 TMST-7700 掩盖的是**未约束路径不进 STA**（`final_timing.rpt:6` `STA coverage: 97.48%`，即约 2.52% 的寄存器对没被任何约束覆盖）。

| 优先级 | 事项 | 理由 |
|---|---|---|
| **P1（接 DDR 前必做）** | ① sys_clk 位置/类型定案（方案 A/B/D 择一）；② 把 `al_ip/MIS_DDRF6F1D0P0_0/src/sdc/MIS_DDRF6F1D0P0_0.sdc` 纳入 `IpSDCList`；③ 决定 r_mdiv2 分支去留 | 直接决定 DDR refclk 约束与是否会新增 TMST |
| **P2（可与 DDR 并行）** | 3 条 no-clock：`scl_clk` 补 `create_generated_clock`（或改成使能门控）；`tl_clk_user_ce_n`/`pcie_pll_locked` 明确声明（CE/复位本质，`set_case_analysis` 或 `create_clock -add`） | 清掉 TMST-7700 的 6 条 SEVERE 主体 |
| **P3（可延后）** | 29 条 no input delay / 17 条 no output delay（MEDIUM） | 其中 pcie_*/mipi_* 属 IP 内部约束+异步组覆盖的接口，是"报告全端口"的副作用；不影响出 bit，但会长期占用 MEDIUM 清单 |

**门禁建议**：把 `phy_1/ph1p_pcie_ep_top_chk.timing` 的 HIGH 计数（第 3+4+5 行）作为每次接入新 IP 后的检查项——**HIGH 归零再继续**。

---

## 结论状态汇总

**实测**（有文件:行 + 原文支撑）
1. `check_timing` 报告确实存在：`phy_1/ph1p_pcie_ep_top_chk.timing`（5231 B，20:28:32）。
2. HIGH 明细：no clock 3 条（scl_clk / tl_clk_user_ce_n / pcie_pll_locked）+ clock definition 3 条（cam_a_byte_clk / cam_b_byte_clk / sys_clk）+ dummy node 1 条；MEDIUM：29 条 no input delay、17 条 no output delay。
3. `TMST-7700` / `RTCLK-5078` / `RTCLK-5079` 的 RTL/约束来源全部早于 DDR 提交；DDR 提交（61b9100）未触碰 `constraints/`、`rtl/`、`sim_do/`。
4. DDR IP 在 20:27 构建中被编译但未例化（`#ddr_byte 0`，顶层无例化）；其自带 sdc/adc 未进 `IpSDCList`/`SDCList`/`.al`。
5. sys_clk 负载恰好 2（PCIe PLL refclk + `r_mdiv2` 寄存器），走 `local_16`，placement 阶段已定；`r_syscnt` 无读者被优化掉。
6. `r_mdiv2` 默认**不被输出选中**（CTRL[2]=0），但一直在翻转，是活逻辑。

**推论**
1. "3 SEVERE / 6 SEVERE" = no-clock(3) → placement 3；再叠加 local-clock(3) → route 6；dangling node 不计。
2. TD 不插 GCLK 的原因是扇出仅 2、门限以下，而非布线失败。
3. 接入 DDR 会带入新的时钟约束缺口（若 sdc 不入 `IpSDCList`），TMST-7700 条数将上升。

**未确认**
1. TD 的 SEVERE 计数规则（无公开文档；placement 阶段 chk.timing 未落盘，无法逐条比对）。
2. 早期（DDR 之前）的 run.log 已被覆盖——"之前就有"靠间接证据链，没有同报告 diff。
3. sys_clk 局部绕线对 PCIe PLL 输入抖动/余量的实际影响（该域 SWNS 19.16ns/20ns 无违规，但 PLL 前 net 延迟 1.911ns 的抖动影响未评估）。
4. 接入 DDR 后 sys_clk 扇出/GCLK 归属与 RTCLK-5079 是否自动消失——需重跑构建/DRC。
5. **未运行任何仿真**（本机无仿真器，已知环境限制）；本次也未运行 TD、未重跑构建。