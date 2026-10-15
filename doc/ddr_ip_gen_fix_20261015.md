# DDR IP `IPT-1002` 修复报告

**运行纪律**：本次共跑 **5 次 td**（2 次诊断 + 3 次假设实测），全部在 `/tmp`。仓库工作区未动（`git status` 干净），无 sudo / 无下载 / 无 bit 下载 / 无 ssh / 无 git 写操作。

---

## 1. 结论速览

| 问题 | 答案 |
|---|---|
| `IPT-1002` 根因 | **IP 实例的 `CONFIG.PH1P_IO_ASSIGN`（ADC 引脚约束文件路径）为空**；generate_target 跑到 IP 包里的 `plugin_end.tcl → gen_adc.tcl` 时执行 `open $PH1P_IO_ASSIGN r`，Tcl 抛 `couldn't open ""` |
| 命令行能否产出 DDR RTL | **能**（实测 `IPT-1001 : The target has been generated successfully.`，IP 目录 6 → 61 个文件） |
| 关键前提 | 喂进去的 `.adc` 必须能过 TD 的 DDR 布线 DRC；**TD 没随包提供 PH1P100SBG484 的 DDR ADC**，可用的最近替代是 `ap115_ddr3_x32.adc` |
| 能否写进工程脚本 | 能（确定性、幂等；见 §4 四行脚本），但 `.adc` 必须是板子真实的 DDR3 引脚分配 |

---

## 2. 根因链（全部有原始证据）

**① 空字符串不是"生成脚本路径"，而是"ADC 文件路径"**
`IpTool` 偏移 `25941836` 处两个相邻字面量：`[Error-%1] %2` 与 `TclFile` → `[Error-TclFile]` 是 `ip_st::EvalTclFile` 的 tag，含义是「source 的 Tcl 文件在求值过程中抛错」，不是「这个 tcl 文件打不开」。所以报错的主语是 Tcl 错误文本本身。

**② strace 定位到具体是哪一句**（run 2：`/tmp/h0b_strace.txt`）
source 链完整跑通到很后面：
```
PH1P_DDRMC_IP/Other/plugin_end.tcl
 → .../script/gen_file.tcl        (拷贝 50 个 RTL/vh 到 .IpToolIpDataBackupDir_ddr3_mc_0/ddr3_mc_0/src/rtl/)
 → .../script/modify_ipfile.tcl
 → .../script/gen_adc.tcl
 → <tmp>/ddr3_mc_0/src/adc/ddr3_mc_0.adc   (O_WRONLY|O_CREAT|O_APPEND)   ← 最后一个成功 syscall
```
之后进程直接退出，`gen_adc.tcl` 的下一句正是 `set fp [open $adc_file r]`，而 `adc_file` 是该 proc 的第 5 个入参 = `$PH1P_IO_ASSIGN`。注意：RTL 阶段其实**已经成功**（wrapper 与 src/rtl 都生成在临时目录里了），失败在收尾的 plugin 脚本。

**③ 该参数确实是空的**（跑之前证据）
```
al_ip/ddr3_mc_0/.params_ddr3_mc_0.txt:117: PH1P_IO_ASSIGN :  : U : En :  :  :
```
`Layout.tcl:155` 里它的控件类型是 `File Browser`、显示名 `ADC File Path`、`Dependency.tcl:122` 限定 `-list {*.adc}`。
Tcl `open ""` 的报错文本与观测的 `couldn't open "": no such file or directory` 完全一致。

**④ 还有第二个必要条件（H1 才暴露）**：ADC 必须过 DRC，否则不会写出 `<inst>_adc.log`，`gen_adc` 会以同一句 `open` 失败（见 §3 H1）。DRC 规则（读自 `Dependency.tcl` 的 `drc_check`）：每类信号数量与配置相等、引脚必须在器件 pkg csv 里、使用 bank 数 ≤3 且组合属于 `cfg.csv` 的 `BANK_USED`、dqs_p/n 位号须为 6/7 且同 bank+byte、dq/dm 不能占时钟位、ck 差分对相邻。

---

## 3. 逐次假设 · 跑前/跑后证据

| # | 假设/动作 | 改动 | 原始输出（after） | 产出 |
|---|---|---|---|---|
| H0a | 复现（抓 stdout） | 无 | `IPT-1002 ERROR: Generate target failed. Reason: [Error-TclFile] couldn't open "": no such file or directory` | `ddr3_mc_0/` 仍 6 文件 |
| H0b | strace 诊断 | 无 | 见 §2②；`.params` 里 `PH1P_IO_ASSIGN` 空 | 同上 |
| **H1** | 假设=「只是参数没设」 | `set_property CONFIG.PH1P_IO_ASSIGN .../example_adc/ph1p100_676_ddr3_x32.adc` | `IPT-1002 ERROR: ... couldn't open "/tmp/ddrip_exp/al_ip/.IpToolIpDataBackupDir_ddr3_mc_0/ddr3_mc_0_adc.log": no such file or directory`；`.params` 变 `PH1P_AC_BYTE : ERROR!` / `PH1P_DRC_CHECK : ERROR!` | 仍 6 文件。**错误位置前移，证明 §2 判断正确** |
| **H2** | 假设=「ADC 必须过 DRC；484 封装的 ap115 引脚全部合法」 | `set_property CONFIG.PH1P_IO_ASSIGN .../example_adc/ap115_ddr3_x32.adc` | **`IPT-1001 : The target has been generated successfully.`**（rc=0） | **6 → 61 文件**；`ddr3_mc_0_drc_check.log` 末行 `the design rule check pass!`；`ddr3_mc_0_proc.log` 12 步全 success |
| H3 | 假设=「从零 create_ip 一条龙可复现」 | 副本 `/tmp/ddrip_exp2` | `PRJ-8601 ERROR: Load project file /tmp/ddrip_exp2/ph1p_pcie_ep_top.al error. This file maybe not completed.` | **无结论**：我自己用 `sed -i '/ddr3_mc_0/d'` 准备副本时把 `.al` 弄坏了（基础设施失误，非假设结果）。按"用满预算即停手"未重跑 |

H2 的 DRC 通过依据（静态预判 + 实测一致）：`ap115` 的 **71/71 个 ball 全在 `PH1P100SBG484.csv`** 里，用到的 bank 是 `{4,5}`，正好等于 `cfg.csv` 中 PH1P100SBG484 允许的组合 `2=4_5`；信号数量与默认配置（DX=4/DQ=32/DM=4/ADR=14/BA=3/CK=1/CS=1/CKE=1/ODT=1/RST=1/WDM）完全吻合。反例：`ph1p100_676_ddr3_x32.adc` 的 73 个 ball 有 37 个不在 SBG484 ball 表里。

---

## 4. 可复现的最小步骤（实测）

```tcl
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
open_project {ph1p_pcie_ep_top.al}
load_project_ips
# ADC 必须是能过 DRC 的 .adc（这里用 TD 自带的 484 封装例程）
set_property CONFIG.PH1P_IO_ASSIGN \
  /opt/anlogic/TD_Release_2026.2_NL/ip/depot/MIS_DDRF6F1D0P0_1.2/example_adc/ap115_ddr3_x32.adc \
  [get_ips ddr3_mc_0]
generate_target [get_ips ddr3_mc_0]     ;# → IPT-1001
```
运行方式：`cd /tmp/ddrip_exp && QT_QPA_PLATFORM=offscreen td.sh <script> </dev/null`

三个必须知道的坑（实测）：
1. **不要信 `get_property CONFIG.PH1P_IO_ASSIGN` 的回读**——set 成功了它回读 `0`，但 `Design.xml/.params` 里是正确的路径。
2. 派生参数（`PH1P_DRC_CHECK/PH1P_AC_BYTE/PH1P_PLL_LOC`）在批处理里 `set_property` 之后**不会立即算**（`USR-8001 property ... not find`），它们在 `generate_target` 里才求值 → 所以 ADC 必须在 `generate_target` 之前设好。
3. `generate_target` **不改 `.al`**（实测 mtime 未变，`<IP_FILE>` 条目本来就存在），生成的 RTL 靠实例 xml 的 fileSet 被工程识别。

---

## 5. H2 产出清单（`/tmp/ddrip_exp/al_ip/ddr3_mc_0/`，61 个文件）

```
顶层(8): ddr3_mc_0.v(5490B, wrapper, module ddr3_mc_0, Gen time 19:36:39)
         ddr3_mc_0_ph1p_ddrmc_wrapper.v(20645B)   ddr3_mc_0.xml(35604B, 104 条 file 声明)
         Design.xml  DesignConfiguration.xml  .params_/.m_params_/.ports_ddr3_mc_0.txt
src/adc(1): ddr3_mc_0.adc(8522B, 生成好的 DDR 引脚约束, ex: ddr_ck_p[0] LOCATION=Y4)
src/sdc(1): ddr3_mc_0.sdc(780B, 时钟改名/分组)
sim/fileset(1): fileset_mis.f(2500B, 编译文件表 + incdir + DDRPHY_ROM_INIT)
src/rtl(50): top/ph1p_ddrmc_top.v(14898B)  mc/mc0_alc_mc_top_all.enc.sv(248062B)
             phy/ph1p_ddrphy_top.v(33297B) +16 个 phy/*.v +4 个 phy/include/*.vh
             clk/*.v(3) cal/*.v(7) init/ misc/ include/ph1p_mis_define.vh
             timing/ddr3/*.vh(7) phy/ddrphy_cfg_rom.txt
```
另外在 `al_ip/` 落了三个过程日志：`ddr3_mc_0_drc_check.log`(DRC 过程, 末行 pass)、`ddr3_mc_0_adc.log`(72 行 pin→bank,byte,bit)、`ddr3_mc_0_proc.log`(12 步生成日志)。

---

## 6. 分类说明

**实测**
- 根因链（strace + `.params` + Tcl 报错文本 + 报错位置前移/消失）
- `PH1P_IO_ASSIGN` = 空 → IPT-1002；填对 ADC → IPT-1001 且产出 61 文件
- ADC 必须过 DRC（H1 的 `_adc.log` 缺失报错 vs H2 的 `design rule check pass!`）
- 676 封装 ADC 在 SBG484 上非法（37/73 ball 不在 ball 表）
- `PH1P_IO_ASSIGN` 回读为 `0`；派生参数批处理下不在 set_property 时求值；`generate_target` 不改 `.al`

**推论**
- 生成的 RTL 会被后续 `open_project` 收编进工程：`ddr3_mc_0.xml` 现在与能正常工作的 `ram.xml` 同构（fileSet 列出全部 RTL/ADC/SDC），但**没有重开工程验证**（预算已用满）。
- `create_ip` + `generate_target` 一条龙可复现：`create_ip` 本身在之前的实验里已产出过本实例（实例 xml/.params/.al 条目都来自 headless create_ip），但 H3 那条"从零"链路**未跑通验证**。

**未确认**
- 从零 `create_ip → set ADC → generate_target`（H3 因我副本准备失误 PRJ-8601 作废，未重跑）。
- `ap115` 的引脚**不是** MLK-F9P 板真实 DDR3 引脚（板子 pinout 未知）→ 生成的 RTL 与板子无关、可用，但 `src/adc/ddr3_mc_0.adc` / `src/sdc/ddr3_mc_0.sdc` 只对输入 ADC 负责，上板前必须换成板厂的真实 DDR3 `.adc`。
- TD 随包**没有** PH1P100SBG484 的 DDR 例程 ADC（39 个 `.adc` 全查过），所以"命令行产出 DDR RTL"目前必须外带一个合法 ADC，这算是唯一的非自足环节。

**建议的下一步（等你放行）**
1. 找板厂/文档要 MLK-F9P（PH1P100SBG484）的 DDR3 x32 `.adc`，替换 `PH1P_IO_ASSIGN` 后重跑一次，得到与板子一致的 ADC/SDC。
2. 若要入库：把"设 `CONFIG.PH1P_IO_ASSIGN` + `generate_target`"两步写进 `create_project.tcl`，ADC 放在工程内（如 `al_ip/constraints/ddr3_ep.adc`）。
3. 当前顶层 `rtl/ep_side/ph1p_pcie_ep_top.v` **没有实例化该 DDR IP**（grep 无 `ddr3_mc_0`），综合不会覆盖到它——需要时才接。

证据文件：`/tmp/h0_stdout.txt`、`/tmp/h0b_strace.txt`、`/tmp/h1_stdout.txt`、`/tmp/h2_stdout.txt`、`/tmp/h3_stdout.txt`、脚本 `/tmp/td_ddr_h0_diag.tcl`…`h3.tcl`，TD 日志 `/tmp/ddrip_exp/td_20261015_193*`。
