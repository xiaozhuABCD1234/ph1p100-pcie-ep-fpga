# dev-plan — T01 DDR1333 IP 集成与 1333/1600 对比数据（run 20261017_153201_T01_ddr1333_integration）

规划日期：2026-10-17。规划者已独立核实 requirement.md 注记与 D 盘现场（只读；结论见 input-index.md「核实结论」）；差异之处以核实为准。本计划不照抄注记。

## 0. 交付映射与批建议

| 用户交付 | 工作包 | 建议批次 |
|---|---|---|
| 1. 完成 DDR1333 IP 集成（从 002820 派生全新候选，换新生成 IP，其余等值） | T01.tool-E1 | 批1 |
| 2. 构建链（综合→route→最终 STA）+ 与 1600 同口径对比表 + 0.300ns 如实评定（含 4b 控制候选；bitgen/CWC 可选延伸） | T01.tool-E2 | 批2 |
| 3. 报告/任务板同步（交数据与建议，不替用户选频点） | T01.tool-E3 | 批3（依赖 E1/E2 实测结果） |

- 默认 BATCH_SIZE=1；E1→E2→E3 **严格顺序**（同一候选树串行推进），不并行。每包新开发 + 三维测试。
- E2 内含两个子项：**E2a=1333 主候选**（必做）、**E2b=1600ctl 控制候选**（002820 原样复制后以同一 6.2.3 工具链重建；默认执行，理由见 §1.8：隔离"工具版本 vs DDR 频点"混杂因素）；E2-opt=bitgen/CWC（可选，条件见 §4.2）。
- 一切真实工具执行在 D 盘 ASCII 目录、cwd=工程目录、正斜杠；仓库只放脚本与证据索引。

## 1. 独立核实要点（规划者只读核实，2026-10-17；细节锚点见 input-index.md）

1. **002820 的 DDMC 接线（已核实）**：顶层 `camera_ddr_display_top.v`（build 的 `top_module`）实例化 `ddrmc_display_top`（例化名 `u_ddrmc_test_top`）；`ddrmc_display_top.v` 内实例化 `ddrmc_x32 u_ddrmc_x32`（`ref_clk=sys_clk50m`、APB、PAXI 直连 `camera_rgb565_display_guarded u_capture`、ddrio、`usr_ref_type=2'b00/usr_ref_req=1'b0`）。IP 注册=build 脚本 `add_files ./vendor/ip/ddrmc_x32/ddrmc_x32.xml`（fileset 带入 `src/adc/ddrmc_x32.adc`、`src/sdc/ddrmc_x32.sdc`）。
2. **新旧 IP 闭包结构（已核实）**：均为 61 文件同布局（`ddrmc_x32/` 下 .params/.m_params/.ports/.v/.xml/Design/DesignConfiguration + sim/fileset + src/{adc,rtl,sdc}）。差异：wrapper 文件更名 `ph1p_ddrmc_wrapper_ddrmc_x32.v`（模块 `ph1p_ddrmc_wrapper_ddrmc_x32`）→ `ddrmc_x32_ph1p_ddrmc_wrapper.v`（模块 `ddrmc_x32_ph1p_ddrmc_wrapper`），`ddrmc_x32.v` 随之更新第 69 行；**60 个同名文件中 33 个逐字节一致、27 个不同**（6.2.3 全量再生成 + 1333 参数；含 `src/rtl/top/ph1p_ddrmc_top.v`、phy/mc/timing 等）。**`src/adc/ddrmc_x32.adc`（75199743…）与 `src/sdc/ddrmc_x32.sdc`（ADB63179…）与 002820 逐字节相同 → 本项目集成无需改 ADC/SDC**。
3. **接口不变（已核实）**：`ddrmc_x32` 模块端口 53 行新旧完全一致（无增删改名）；IP 内部实例名保持（`ddrmc_x32.v` 内例化名仍 `ph1p_ddrmc_wrapper`、wrapper 内仍 `ph1p_ddrmc_top`），项目 `timing.sdc` 与 IP `src/sdc` 的 `rename_clock`/`set_inst` 层级路径不受影响。⇒ **项目侧 RTL 与约束零改动即可"只换 IP"**。
4. **参数与派生（已核实盘上文件）**：`.params`：`PH1P_DDR_SPEED=1333.00`、`PH1P_SPEED_BIN=DDR3-1333J`、`CWL=7`、`tCK=1500`；`.m_params`：`CL=10`、`PLL0_REFCLK_DIV=3/FBK=80/CLK2=2/CLK3=27`（物理 CK=50×80/3/2=**666.6667≤666.667MHz**）、`PLL1_REFCLK_FREQ=166.7`（用户域 5ns→约 6ns）、`SYSCLK_LOC=H4`、`PLL_LOC=BANK33`、IO1.35、x16、2048、REF50。`.params` 的 `PH1P_IO_ASSIGN` 指向 run1 引导目录的 `input_pins.adc`（F0904238…）——**保留原样记录、不改写**（生成溯源；实际构建引脚以闭包内 `src/adc` + `board.adc` 为准）。
5. **002820 manifest（已核实）**：220 项、SHA `8F8E4EFE…F9A1C8`；其中 61 项为 `vendor/ip/ddrmc_x32/**`、另有 `vendor/ip/ddrmc_x32_{adc,drc_check,proc}.log` 3 项、`vendor/ip/RTL/**` 2 项与 `vendor/adc/ap115v2.adc` 1 项为**未被构建引用的历史遗留**（只读保留，本轮不改）。bit=`4d591c31…`（002820 自身冻结依据）。
6. **上一 run §6.5「集成输入=64 文件闭包+boot 文件」核实**：闭包=61+3 日志，**对构建充分**——xml fileset 引用全部落在闭包内（E1 需逐条核对无悬空）、ADC 已本地化且与旧同内容、SDC 无差异、**无需 depot 无关化**（构建不访问 `D:\downlaod` 或私有 depot；6.2.3 用自带 `arch\ph1_100p.db` `939EC294…`）；boot `.al`（`EF721C4D…`）不进入派生输入，仅作注册形态旁证（`<IP_FILE>` xml 形式与 `build_rgb565.tcl` 的 `add_files` 一致）。
7. **0.300ns 口径（已核实来源）**：来自 `docs/RGB565时序裕量优化_2026-10-15.md`「首轮以最终 setup 裕量至少 0.3 ns 为优化目标」；判定工具=`tools/td/check_timing_margin.py`（`--min-setup-ns 0.3` + `Confidence: Routed` + 显式端点组数完整性 + 违规端点合计=0 + `STNS==HTNS==0` + `hold/period>=0`）；114913 是"实现期 0.300ns 用户 uncertainty 预留后恢复 nominal 交付"的等价实验。**该目标是探索轮自定优化线，非器件/板卡保证**。本轮 1333 候选以 **nominal（不加预留）**为主口径（与 002820/103222/111134 一致），`min-setup 0.3` 的接受/拒绝**如实记录**（不强制通过）。
8. **对比基线与工具版本混杂（已核实）**：002820 STA=setup 0.000/TNS0、hold 0.020、period 2.200、66 组（`candidate_timing.rpt B2A78335…`）；103222/111134/114913=0.001/0.008/−0.177、68 组（6.2.2）。**历史 1600 数据全部产自 6.2.2；新 1333 IP 由 6.2.3 生成，按"新候选全链同版本"纪律须用 6.2.3 构建** ⇒ 直接对比会混入工具版本因素；故 **E2b 用 002820 原样复制（1600 IP 不变）以 6.2.3 重建**，与 1333 候选同工具、同脚本、同参数，唯一差异=DDR IP；历史 6.2.2 行保留在对比表并**逐行标注工具版本**。
9. **6.2.3 工具锚（已核实）**：`D:\anlogic\TD_Release_2026.2`；CLI `bin\td_commands_prompt.exe` SHA `2629E474…C1223`、`td.exe` `FA2A5AC6…06A87`、`IpTool.exe` `5B0654AA…75CEC`；license `license\Anlogic.lic` `DC19FEE6…45C1A6`（已复制；缺失时合成 worker RUN-8008，历史实测）；`DB_VERSION=46207`。安装包 `TD_Release_2026.2_NL.exe` `3B92ABE8…751A0A`。6.2.2（`D:\downlaod`）保持冻结对照，`tools/td/run_rgb565_native.py` 不动。
10. **任务板观测时点**：`workflow/tasks.json` SHA `91CDFE22…F73E`（2026-10-17 规划时观测；T01 state=active，含并行线更新）。E3 更新时按**最新观测**对 T01 域唯一匹配编辑，不触碰其它任务。
11. **报告形状将再变化**：002820=66 组、timing 轮=68 组；6.2.3+新 IP 的最终报告组数需**人工复核后显式设定**给 `check_timing_margin.py`，禁止按文件现有组数自证完整（沿用 2026-10-15 规则）。

## 2. 受控边界（本批全部工作包适用，越界即停）

- **冻结件只读**：`D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820`（及 `camera_rgb565_20261014_140836`、`camera_rgb565_timing_20261015_*`、`camera_rgb332_reference_20261013_215134`）、`D:\TD\work\csi2\_validation\` 全部既有目录（含 190248 包与 `td2026_*` 引导/证据现场）、`D:\downlaod` 全部、golden ADC、其它工作树、`parallel/`。**禁止直接 open 既有工程**（open/close 会改写 `.al`）；需要检查一律读文件或在新建副本上进行。
- **新建 only**：新候选目录 `D:\TD\work\csi2\prj\camera_rgb565_ddr1333_<YYYYMMDD_HHMMSS>` 与 `camera_rgb565_ddr1600ctl_<YYYYMMDD_HHMMSS>`（`mkdir(exist_ok=False)`）；`tools/td/` 新脚本；`docs/evidence/` 新 JSON；本 run 目录。任何阶段产物（`native_*.json/.txt`）**不覆盖**，失败现场全保留。
- **不批量删除**：不删任何既有文件；派生采用"只复制不复制"（wrapper 更名=不复制旧名文件 + 写入新名文件），不做删除操作。6.2.3 安装树只读使用（工具自身可能写 `bin\.setup.ini` 缓存——如发生如实记录，不清除）。
- **不下硬件/不 Flash/不跑 GUI**：无任何板卡动作；bit 产物（如做）仅作候选，不上板。
- **中文路径禁令**：一切 TD 执行在 D 盘 ASCII 目录、cwd=工程目录、脚本引用用正斜杠 `./x.tcl`；不从仓库中文路径运行构建。
- **公平原则（写死）**：除 DDR IP 闭包（61 文件）+ 3 个 IP 日志外，候选其余部分与 002820 **逐字节等值**（不做路径重定位——002820 持久冻结，其被引用的 ROM/文件仍有效；由此候选对 002820 的全部改动被限定在 64 文件替换范围内：范围外零差异、可全量断言核查）。
- **不得削弱既有断言**：新 runner 必须保留 `run_rgb565_native.py` 的全部既有断言（manifest 全量核对、no-overwrite、marker+产物+SHA 三件套、超时真实记录、sta 摘要提取），仅允许因 6.2.3 与"数据产出"目的做**记录性扩展**（工具 SHA 断言、execution_ok 与 timing_signoff 的明确区分，见 §4.2）。
- **顺序集成**：同一候选树上的派生→构建→报告严格串行；E1 冻结（三维 PASS）前不得开始 E2 构建；E2 冻结前不得写 E3 结论。

## 3. 工作包最小表

| task_id | 问题/产物 | 允许写路径（越界即停） | 依赖 | functional 验收 | engineering 验收 | system 验收 | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| T01.tool-E1 | 从 002820 派生 DDR1333 新候选（只换 IP）+ 1600ctl 派生；闭包完整性与等值断言 | 新建 `tools/td/prepare_rgb565_ddr1333.py`；新建 `D:\TD\work\csi2\prj\camera_rgb565_ddr1333_*`、`camera_rgb565_ddr1600ctl_*`；新建 `docs/evidence/ddr1333_integration_<date>.json`；本 run 目录 | 无（输入已冻结） | 见 §4.1：差异集恰 64 文件；其余 156 项逐字节一致；参数/端口/引脚断言全过；xml fileset 与磁盘文件互查无悬空 | 脚本断言全过并留运行记录；run1 单源（D71057F3…）逐文件核对；不改 002820（复算锚点） | 仓库→候选一键入口；overlay/manifest 齐备可供 E2 runner 直接消费 | G0/G1（输入一致性+文档）；G2 not_run | ✅ round0 三维 PASS（test-reports/T01.tool-E1-r0-*.md） | 无（已关闭） |
| T01.tool-E2 | 6.2.3 全链构建：综合→route→最终 STA（1333 主候选 + 1600ctl 控制）；同口径对比数据；0.300 如实评定；bitgen/CWC 可选 | 新建 `tools/td/run_rgb565_ddr1333.py`；只写两个新候选目录；新建 `docs/evidence/ddr1333_build_sta_<date>.json`（+可选 bitgen 段）；本 run 目录 | E1 三维 PASS 且候选冻结 | 见 §4.2：两候选 build/route 真实执行三件套齐；STA 字段独立再抽一致；0.300 gate 显式组数+输出；对比表同口径字段齐（缺项须 n/a+理由） | 工具 SHA 断言命中；超时/失败如实；无覆盖/无越界写；002820 等冻结件零漂移 | 命令+参数可复现；数据支撑频点决策与 0.300 结论；边界（板测/真实 DDR 行为未测）如实 | G2（实现+最终 STA；报告形状人工复核）；G3/G4 N/A；bitgen 可选=候选延伸 | ✅ round0 三维 PASS（test-reports/T01.tool-E2-r0-*.md） | 无（已关闭） |
| T01.tool-E3 | 报告与同步：docs 报告 + tasks.json（仅 T01）+ 可选 tools/td/README 增补 | 新建 `docs/DDR1333集成与1333vs1600对比_<date>.md`；改 `workflow/tasks.json`（仅 T01）；增补 `tools/td/README.md`；本 run 目录 | E1/E2 实测结果（两者证据齐后） | 报告逐条可溯源（证据路径+SHA）；无未实测"通过"；建议节只列数据与决策指引 | 路径/SHA/工具版本准确；tasks.json 合法 JSON 且最小 diff（并行线漂移按观测时点登记） | 下一入口（用户决策材料、可选 bit/上板包入口）明确；T01 不置 done（父任务含板验） | G0/G1；硬件层 N/A | ✅ round0 三维 PASS（test-reports/T01.tool-E3-r0-*.md） | 无（已关闭） |

## 4. 各工作包详情

### 4.1 T01.tool-E1 — 派生 DDR1333 候选（+1600ctl 控制派生）

**目标**：产出唯一冻结候选 `D:\TD\work\csi2\prj\camera_rgb565_ddr1333_<ts>`：=002820 全量文件（220 项 manifest 逐项 SHA 校验后复制）+ 以 run1 闭包替换 `vendor/ip/ddrmc_x32/**`（61 文件）+ 替换 3 个 IP 日志；其余零改动。同脚本 `--control` 模式产出 `camera_rgb565_ddr1600ctl_<ts>`（=002820 原样复制，零改动，仅加冻结脚本；供 E2b）。

**派生脚本断言（必须全部在 `prepare_rgb565_ddr1333.py` 内，`__debug__` 保护，运行即验）**：
1. BASE=002820：`input_manifest.json` SHA=`8F8E4EFE…F9A1C8`、`camera_ddr_display.bit` SHA=`4d591c31…`、条目数=220；逐项 SHA 复算；OUT `mkdir(exist_ok=False)`。
2. 新 IP 源=run1 `D:\TD\work\csi2\_validation\td2026_gui_bootstrap_20261017_000935\ip_out`：`candidate_manifest.json` SHA=`D71057F3…C08434`、64 项、逐项 SHA 复算；**单源**（不得混用 run2 文件；run2 `9B3E5D00…` 仅作为等价镜像在 overlay 中登记）。
3. 新闭包关键锚：`ddrmc_x32.xml`=`92155F9D…`、`ddrmc_x32.v`=`7EDEF919…`、wrapper `ddrmc_x32_ph1p_ddrmc_wrapper.v`=`609F3C60…`、`.params`=`86D1C0B6…`、`.m_params`=`6401066A…`、`Design.xml`=`72F2BB57…`、`src/adc`=`75199743…`、`src/sdc`=`ADB63179…`、三日志=`C50695DF…/75721975…/9C1CDF4B…`、引导 `input_pins.adc`=`F0904238…`。
4. 参数文本断言：`.params` 含 `PH1P_DDR_SPEED : 1333.00`、`PH1P_SPEED_BIN : DDR3-1333J`、`CWL : 7`、`tCK : 1500`；`.m_params` 含 `CL; 1; 10`、`PLL0_FBKCLK_DIV; 1; 80`、`PLL0_REFCLK_DIV; 1; 3`、`PLL1_REFCLK_FREQ; 1; 166.7`。
5. **接口等值断言**：解析新旧 `ddrmc_x32.v` 的 `input/output/inout` 行集合完全相等（53 行）；新 wrapper 含定义 `MC0_DDR3_1333J`；新 `src/adc` 内 `set_ipinst_assignment` 层级前缀仍为 `ph1p_ddrmc_wrapper/ph1p_ddrmc_top/…`（与 SDC rename 路径一致）。
6. **闭包闭合断言**：`ddrmc_x32.xml` 的文件名列表逐条在磁盘存在（无缺失）；磁盘 `ddrmc_x32/**` 文件集合 ⊆ xml 列表∪{Design/DesignConfiguration/.params/.m_params/.ports}（无多余混入）。
7. **改动范围断言**：候选对 002820 的改动**仅限** 64 文件替换范围（61 闭包 + 3 日志）：(a) 范围内 60 个同名文件逐字节等于 run1 对应文件（其中 33 个与旧亦相同、27 个不同）；(b) 旧 wrapper 不复制、新 wrapper 写入且 SHA=run1（记录 before_sha/not_copied 理由）；(c) 范围外 156 项逐字节等于 002820（含 `camera_ddr_display_top.v`、`ddrmc_display_top.v`、`build/route/bitgen tcl`、`timing.sdc`、`board.adc`、`camera/**`、`vendor/ip/RTL/**`、`vendor/adc/ap115v2.adc`、`frozen_*` 等）；(d) 机器核算并记录实际逐字节差异清单（预期=27 变更 + 3 日志 + 1 移除 + 1 新增=32 条目；不符即驻留解释，不掩盖）；不做路径重定位（见 §2 公平原则）。
8. 结果自检：输出 `input_manifest.json`（新 SHA，221 项）+ `ddr1333_overlay.json`（base、baseline_manifest_sha256、new_ip{run1 根+manifest SHA、run2 镜像 SHA}、input_count、changes（逐文件 before/after/reason）、removed（旧 wrapper）、unchanged_guards（关键等值文件哈希）、fairness_checklist、hardware_verified=false、build_tool_anchor=6.2.3 CLI SHA）+ `frozen_prepare_rgb565_ddr1333.py`（自拷贝）；断言输出目录计数=221（frozen 后），写 manifest/overlay 于计数之后；`--control` 模式差异集=0（除 frozen 脚本）。

**允许写路径（精确）**：新建 `tools/td/prepare_rgb565_ddr1333.py`；新建两个候选目录（只新建）；新建 `docs/evidence/ddr1333_integration_<YYYYMMDD>.json`（E1 段：派生记录+断言输出）；本 run 目录。其余一切只读。

**三维验收**：functional=§4.1 断言 1–8 全过且运行输出入证据；engineering=脚本内无越界写、002820 与 `_validation` 锚点复算零漂移、run1 单源、失败即停不覆盖；system=从仓库一键派生入口可用、overlay 可供 E2 直接消费、E2 所需输入（清单/工具锚）齐备。

**停止条件/时间上限**：任一断言失败即停（如实记录，不手改生成物、不改 RTL 掩盖）；净执行 ≤1h。

**回退**：无任何既有文件被改；失败现场保留；002820 仍是唯一冻结基线。

### 4.2 T01.tool-E2 — 6.2.3 构建链与对比数据

**新 runner `tools/td/run_rgb565_ddr1333.py`（新写，不得削弱既有断言）**：
- 继承 `run_rgb565_native.py` 全部断言：工程路径限定（`D:/TD/work/csi2/prj` 下、名以 `camera_rgb565_` 开头）；执行前 manifest **全量** SHA 核对；`native_<stage>.json/.txt` 不覆盖；命令=`[6.2.3 CLI 绝对路径, ./脚本.tcl]`、cwd=工程；marker+产物+SHA 三件套；超时真实记录；route 阶段提取 `SWNS/STNS/HWNS/HTNS/Period Check WNS`。
- 新增（记录性扩展，非削弱）：断言 CLI SHA=`2629E474…`；记录 runner/脚本/输入 manifest/产物/日志 SHA；**区分** `execution_ok`（exit0+marker+产物完整 → runner 退出码）与 `timing_signoff`（组数评审后的 0.300 gate，单独记录）——本任务产出包含"负时序也是有效数据"的诚实结论，但 **bitgen 阶段保持 fail-closed**（不满足全项非负不产 bit，沿用 `bitgen_rgb332_body.tcl` 门槛）。
- 阶段与超时：`build` ≤2400s、`route` ≤5400s、`bitgen` ≤1800s；超时 kill 进程树并记 `timed_out:true`。

**执行序列（顺序）**：
1. E2a：对 `camera_rgb565_ddr1333_*` 运行 `build` → `route`（native，含 `update_timing -mode final` + `capture_timing.rpt`）。
2. E2b：对 `camera_rgb565_ddr1600ctl_*` 同 runner 同参数运行 `build` → `route`。
3. STA 口径与 gate：(a) 从两份 `capture_timing.rpt` 独立再抽 SWNS/STNS/HWNS/HTNS/Period/组统计，与 runner 记录比对一致；(b) **人工复核**报告形状后显式确定 `expected_endpoint_groups` 并记录理由；(c) 运行 `tools/td/check_timing_margin.py <rpt> --min-setup-ns 0.3 --expected-endpoint-groups <复核值>`，stdout+exit 入证据；(d) 提取 Clock Summary 中 `ddr_user`（/usr_clk）周期与资源（`capture.area` 的 LUT/REG/ERAM/DSP/PLL）；(e) 与历史 002820/103222/111134/114913 冻结报告中的同口径字段并排（历史行只读引用，标注 6.2.2）。
4. E2-opt（可选）：仅当 1333 与/或 1600ctl route 最终 STA 全项非负（setup/hold/period≥0 且 TNS=0）且时间允许时，按既有 `bitgen_rgb565.tcl` 流程对满足条件的候选运行 `bitgen`（可选含 CWC 导出）；**不上板**；否则记 `not_run(理由)`。

**同口径对比表（写进 `docs/evidence/ddr1333_build_sta_<date>.json`，E3 报告表格化）字段**：候选名/阶段｜工具版本+CLI SHA｜脚本 SHA（build/route/bitgen）｜runner SHA｜input_manifest SHA+项数｜build: exit/marker/gate.db SHA｜route: exit/marker/selected DB SHA｜最终 STA：setup/STNS、hold/HTNS、Period WNS｜组数/违规端点合计｜报告路径+SHA｜`ddr_user` 周期｜资源 LUT/REG/ERAM/DSP/PLL｜物理策略（TimingHigh）｜备注（版本/预留差异）。历史行（002820 等）无法取得字段填 n/a+原因。（可选）对比表可增设『800E（参考，不实施）』行：仅列队友配置锚与理论带宽/接口差异（来源见 input-index §3.6），不进入本轮构建/验证，不与实测行混排归因。

**允许写路径（精确）**：新建 `tools/td/run_rgb565_ddr1333.py`；只写两个新候选目录（build/route/bitgen tcl 由派生自带，runner 不重写）；新建 `docs/evidence/ddr1333_build_sta_<YYYYMMDD>.json`；本 run 目录。其余一切只读。

**三维验收**：functional=两候选 build/route 的三件套记录齐+STA 再抽一致+0.300 gate 显式评定+对比表字段齐（缺项 n/a 有理由）；engineering=工具/输入/产物/日志 SHA 链完整、超时与失败如实、无覆盖/无越界写、冻结件零漂移（002820 manifest/bit、190248 包、6.2.2 工具锚复算）；system=命令+参数可复现、数据足以支撑 1333/1600 对比与 0.300 结论、边界与下一入口明确（bit 可选结果、后续上板包留待决策）。

**必要 G 层**：G2（真实综合+route+最终 STA，两份报告形状人工复核）；G3/G4 N/A（无板测/无长稳）；E2-opt bit=G2-bit 候选（未下板）。

**停止条件/时间上限**：同阶段同因失败 ≤3 次即切换/收束；总机器时间按超时表；E2 净开发（含 E2b 与可选 bitgen）≤4h；若时间墙触顶：**保底裁剪顺序=先保 1333 主候选+对比表，E2b 可裁剪并如实记录（此时对比限制为 002820@6.2.2 历史行+版本差异说明），bitgen 先裁**。

**回退**：全部失败现场保留；002820 及历史候选原样；候选不入任何既有工程、不下板；6.2.3 全链若暴露工具缺陷→如实收束（不改 6.2.2 路线、不自动启用 GUI/190248，必要时提请用户）。

### 4.3 T01.tool-E3 — 报告与同步

依赖 E1/E2 证据齐（不得先写结论）。产物：
1. `docs/DDR1333集成与1333vs1600对比_<YYYY-MM-DD>.md`：需求 1–4 映射；集成记录（闭包映射/参数/差异集 64/等值核查/端口不变）；构建记录（工具、命令、产物、SHA、时间）；**同口径对比表**（含工具版本列与历史行）；**0.300ns 评定**（gate 输出+结论，如实）；频点建议材料（1333/1600 数据事实、带宽预算回顾引用、DS1300「PH1P100 DDR3 800Mbps」口径 flag 提醒、决策指引——只交数据不替用户选；**800E/AXI 列为 C4 第三候选**：列队友配置锚（`al_ip/ddr3_mc_0` `4D7060F8…`/`ipGenVersion 208212`，800E/CL6/CWL5/×32/AXI=1）、接口差异与 PAXI→AXI 迁移面（推帧读源适配 I4、4KB 对齐/尾突发 C3、双路余量复核 T5）、带宽对照（3.2/5.33/6.4GB/s），引用 `workflow\runs\20261016_2110_pcie_unified_path\` 两文档与 `upgrade-review.md` §6——**只列入口与影响，不做实施承诺、不进入本批构建**）；未决/边界（bitgen 可选结果、板测未做、800E/AXI 未实施=C4 待决）；回退（002820 原样可用）。所有结论引用证据路径+SHA，无未实测"通过"。
2. `workflow/tasks.json`：仅更新 T01（status_note/references 增补本次报告与证据；state 维持 active 或按实际刷新；**不置 done**——父任务含板验/颜色 G3/G4）；改动前记录观测时点 SHA，T01 域唯一匹配编辑；改后 JSON 解析自检。
3. `tools/td/README.md` 增补（新 runner 用法+边界，不删旧记录）。

**三维验收**：functional=报告逐条可溯源、无夸大、建议节只列数据事实；engineering=路径/SHA/版本准确、tasks.json 合法且最小 diff（并行线漂移按观测时点登记）；system=下一入口明确（用户决策材料、可选 bit/后续上板包）、T01 状态与事实一致。

**G 层**：G0/G1（文档一致性）；硬件层 N/A。时间上限 ≤2h。

## 5. 「必须实测通过」vs「如实记录边界」

必须实测通过（不接受推断替代）：
- E1：断言 1–8 的真实运行输出（含差异集 64 的机器核算）；002820/run1 锚点复算。
- E2：两份 build/route 的真实执行记录（exit/marker/产物/SHA）；STA 字段独立再抽；`check_timing_margin` 显式组数评审+gate 输出；对比表全字段（含 n/a 理由）。
- E3：报告每条结论对应 E1/E2 证据文件+SHA。

如实记录边界的典型情形（写清证据与下一步）：
- 1333 或 1600ctl 出现负时序/未达 0.300：**是本轮合法数据**，照实记录（不产 bit、不"放宽"）；`timing_signoff` 与 `execution_ok` 分开。
- 6.2.3 构建出现工具内部缺陷：记录缺陷+影响+workaround 评估，不冒充修复；是否改走 6.2.2/GUI 全链交用户决策。
- bitgen/CWC：时间墙或冲突即 `not_run(理由)`，不算失败。

## 6. ready/blocked 元数据

| 工作包 | 状态 | 阻塞依赖 |
|---|---|---|
| T01.tool-E1 | ✅ round0 三维 PASS（已关闭） | — |
| T01.tool-E2 | ✅ round0 三维 PASS（已关闭） | — |
| T01.tool-E3 | ✅ round0 三维 PASS（已关闭） | — |

## 7. 需要用户决策/在场的事项

1. **本批无启动阻塞、无需用户在场**（无 GUI、无板测）。执行中若触发：6.2.3 全链若暴露工具缺陷需改走 6.2.2/190248 GUI 全链（用户在场）时，提请决策。
2. bitgen/CWC 为可选延伸（条件见 §4.2），不请求决策；产 bit 也不上板。
3. 频点终选（1333/1600/800）与「器件手册 800Mbps」资格差异：本轮只交数据与建议，**后续用户决策**（不属本批强制范围）。C4（800E/AXI vs 1600K/1333——含 PAXI→AXI 迁移）同属后续用户决策；E3 报告按 §4.3 提供对比材料（来源见 input-index §3.6）。
4. 提示：`workflow/tasks.json` 被并行线持续更新——E3 按观测时点唯一匹配编辑，不属用户决策。

## 8. 角色与回退

- E1/E2/E3 各派**新开发者**；每包完成后各派功能/工程/系统**三新测试者**（同一冻结输入、独立报告、`report-contract.md` 格式，`OUTPUT_DIR/test-reports/<task_id>-r0-<dim>.md`）。
- 测试预算边界：三维测试者**不得重跑完整 TD 构建**（时间墙；E2 报告以冻结产物与哈希复核+独立重算 STA/gate 为准）；系统测试者可用**派生脚本复跑**（新时间戳目录，廉价）验证 E1 可复现性。若确需构建复跑，先经规划批准并记录理由。
- 修正轮：同任务 FAIL 续原角色，最多三轮实际修复；复测影响/证据复用由开发/测试给清单。
- 回退：全部失败现场保留；002820 与全部历史候选原样；190248 包保持冻结备用；任何新候选不自动进入既有工程/bit/板测。
