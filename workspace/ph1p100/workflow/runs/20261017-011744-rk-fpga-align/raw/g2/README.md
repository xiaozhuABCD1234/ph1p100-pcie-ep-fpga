# G2 证据（T11.rk-align-raw） —— 同一最终 DB，**达标**

证据本体在候选工程里：`workflow/runs/20261017-011744-rk-fpga-align/raw/candidate/prj/`；
本文件只做索引与结论。SHA 收进 `../candidate-manifest.json` 的 `build_artifacts`。

## 1. 入口与完成标记

* 命令：`powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_td.ps1 -Stage 00_all
  -OutDir workflow/runs/20261017-011744-rk-fpga-align/raw/candidate/prj`
* 入口脚本：`tools/pcie_integration/td/00_all.tcl`（单会话 create → syn_1 → phy_1 → `save_best_bits`；
  未执行 `download_sram.tcl`、未下载、未写 Flash）。中文路径由 run_td.ps1 临时 subst（`S:`，用完撤销）。
* TD 6.2.3：`td exit 0`；`td_00_all.log` 有 `PRJ-1406 Run phy_1 finished` +
  `PRJ-1424 The implemented result of phy_1 is saved as best result` +
  控制台完成标记 **`T07_ALL_DONE`**（共享入口脚本里的标记文本沿用 T07，运行域为 T11）；
  phy_1 墙钟 418 s。
* 账目：本包 TD 重建 **1 次**（派发允许 ≤2 次；无需第 2 次）。
* 已知的收尾报告告警（与 T07 相同、非实现问题）：会话收尾的 `report_area/report_timing`
  因“未 import netlist / Cannot find top model”被 skip —— 判定用的是 phy_1 运行目录内
  TD 自己生成的 `final_timing.rpt` / `*.area` / `*.chk.timing`。

## 2. 判定结果（同一最终 DB）

| 项 | 值 | 判据 |
|---|---|---|
| 最终 STA | `phy_1/final_timing.rpt`：Generated **Sat Oct 17 09:41:30 2026**、**Routed**、Both corners、CRPR on、STA coverage 95.46% | — |
| **Setup** | **SWNS = +0.115 ns，STNS = 0.000 ns（0 violated endpoints / 18,724 endpoints）** | setup ≥ 0 且 TNS 0 → **✓** |
| Hold | HWNS = +0.020 ns，HTNS = 0.000 ns | ✓ |
| 按时钟（SWNS） | clk0 `usr_clk` 100 MHz +0.626；clk1 `tl_clk_user` 62.5 MHz +5.058；**clk2 `cam_a_byte_clk` 187.547 MHz +0.115 / R-Period 5.217 ns（191.68 MHz）/ 0 违例**；**clk3 `cam_b_byte_clk` +0.150 / R-Period 5.182 ns（192.98 MHz）/ 0 违例** | 全部非负 |
| 最差路径 | `u_csi_a/u_gear_box/O_word_out_reg[3].clk → u_cam_r10f_writer/f_mem_syn_65.csa[2]`（**本包新增写者的 FIFO 写口**），数据路径 **4.503 ns**（cell 1.495 ns 33% / net 3.008 ns 67%）、**逻辑级 4**（LUT5×2/LUT6×1/LUT4×1）、Budget 5.332 ns | 余量 **+0.115 ns** |
| 资源 | LUT6 **15,599/71,680（21.76%）**、slice reg 16,796/143,360（11.72%）、**ERAM 136/300（45.33%，FIFO20K=0）**、DSP 0/220、PCIE 1/1、DDR 7/24、PLL 3/12、PAD 107/286 | ≤ 器件 ✓ |
| 位流 | `phy_1/ph1p_pcie_integration.bit` **5,224,023 B**，SHA256 **`14b32037eb0b4aff4f9ea1f61b75160c11ff9381e23f11563f97ecaf5bf5686b`**（与 `best_result/` 同 SHA）；同次 `pr.db`/`place.db`/报告 | 同源 ✓ |

**与 T07 r3（同入口、同判据、未放宽任何约束）的对照**：SWNS +0.107→**+0.115 ns**、
STNS 0.000 保持、违例端点 0 保持、ERAM 134→136（写者 FIFO 的 2 块）、LUT6 19.13%→21.76%、
bit 换为新候选；`TMST-7700` SEVERE 5（同类、逐项见 §3）。

## 3. 约束检查（`phy_1/ph1p_pcie_integration_chk.timing`）逐项说明

| 项 | 数量/级别 | 解释与结论 |
|---|---|---|
| no clock | 2（HIGH） | `u_pcie_pll_ep/...PH1P_PHY_PLL.lock` 与 `tl_clk_user_ce_n`：数据/使能类网被误当候选时钟网；真实时钟见 clock summary（clk0..clk3+50 MHz 均有定义）——不构成未约束时钟 |
| clock definition（local clock） | 3（HIGH） | `cam_a/cam_b_byte_clk`（PHY 内分频输出，187.547 MHz）与 `sys_clk_dup_1`（50 MHz 参考，peer 原样）：IP/PHY 生成 + SDC/IP 自带约束覆盖 |
| dummy node | 2 | 与 T07 同类（peer 原样） |
| invalid constraint / pll clock constraints / combinational loops / soft fifo exception / no-path / shadowed | 0 | 无 |
| no input delay / no output delay | 73 / 87（MEDIUM） | 慢速 IO 与源同步/串行接口（由 IP 自带 sdc 管住）；**本包未改约束**（SDC 与 T07 同一 SHA） |
| `TMST-7700` SEVERE（`phy_1/run.log`） | place 阶段 2 / post-route **5** | = 上表 2 无根时钟网 + 3 local clock；与 T07 同类，**与 setup 违例无关** |
| STA coverage | 95.46% | TD 覆盖率统计（非“通过率”）；未覆盖主要是异步域内部与无 delay 慢速 IO |
| CWC | not_applicable | 候选无 CWC 生成物（清单可核） |

## 4. 结论

**G2 通过**：同一最终实现 DB（`place.db`/`pr.db` + 报告）Routed、setup **SWNS +0.115 ns /
STNS 0.000 / 0 违例端点**、hold +0.020 ns、资源在器件内、位流与同次 DB/报告同源
（`14B32037…5686B`）。达标手段 = T11 正式通路（新增写者 + 顶层换接）在**不放宽 SDC、
未加 multicycle/max_delay、未改 187.5 MHz 或相机速率前提、未改 checked 原源**下重建。
余量相对于相机字节域仍薄（本条域最差路径 67% 是布线）：任何后续 RTL/约束改动都必须
重跑 G2 并以「cam_a/cam_b 字节域 setup ≥ 0」为回归门槛。

失败/历史留痕：T07 的 round0/round1 负裕量记录保留在 `../../backend/g2/README.md`
（未删除、未覆盖）；本目录无 T11 的负裕量（本次唯一构建即达标）。
