# fpga-design-guide — T01 DDR1333 IP 集成与 1333/1600 对比（run 20261017_153201_T01_ddr1333_integration）

依据 `.agents/skills/fpga-design-guide/SKILL.md` 编写。只冻结本批（T01.tool-E1/E2/E3）涉及的数据、接口、参数、工作目录、构建入口与约束约定；未列项沿用既有项目文件，不另立冲突标准。全部数值锚点为 2026-10-17 规划者只读核实值。

## 1. 现基线工程入口（002820 冻结基线，只读引用）

**工程**：`D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820`；manifest SHA `8F8E4EFE9B9320CBC595F94E337395744DBD957630576123576EE2C357F9A1C8`（220 项）；bit SHA `4d591c31da9a71b9c261972e5089930af3e441c2096ed37736c8d2340ddd8865`。

**顶层与 DDR 接线链**（指定名冻结，E1 断言"接口不变"以此为准）：

```
camera_ddr_display_top (build 的 top_module；camera_ddr_display_top.v)
 ├─ f9p_camera_display_core u_camera   // CSI/相机/HDMI/预览；输出 display_*、cap_*、ddr_rgb/ddr_vs/ddr_hs/ddr_de
 ├─ usr_mcu_wrapper                     // APB 主；ROM 由 `USR_MCU_ROM_INIT 宏指定
 └─ ddrmc_display_top u_ddrmc_test_top  // ddrmc_display_top.v（=本工程 DDR 板级封装）
     ├─ ddrmc_x32 u_ddrmc_x32           // 本任务替换对象（vendor/ip/ddrmc_x32/**）
     │   .ref_clk=sys_clk50m（H4）      .sys_rst_n、APB（pclk/prst/psel/…）
     │   .dhi_clk（DDR 用户域）         .cfg_clk（供板级 MCU 的 APB 时钟）
     │   .ddrphy_rdy/.ddrphy_rst_n      .paxi_*（AW/W/AR/R 直连 u_capture）
     │   .usr_ref_type=2'b00 .usr_ref_req=1'b0（保留厂商刷新策略）
     │   ddrio：ddr_ck_p/n、reset_n、cke、odt、cs_n、ras/cas/we、ba[2:0]、addr[13:0]、dqs_p/n[3:0]、dq[31:0]、dm[3:0]
     └─ camera_rgb565_display_guarded u_capture (.SW(960),.SH(540))  // PAXI 主；错误旗/计数/LED
```

- 时钟/复位：`ref_clk=sys_clk50m`（50MHz 输入）；DDR 用户域时钟由 IP 内 PLL1 产生（`dhi_clk`，1600 档=200MHz；1333 档预计约 166.7MHz）；`sys_rst_n` 直连 IP；display/CSI 时钟来自 ui_pll 与 MIPI 恢复时钟（见 `timing.sdc`）。
- **约束**：项目 `timing.sdc`（SHA `0C32C5F7A536BBC811901D5AF254A4FDDC270DCDD2B59C16CAEB006EF0F7FE1C`，2350B）含：`sys_clk50m` 20ns；`mipi_a/b_clk_hs`；`rename_clock pclkx1/pclkx5/mclk27`（ui_pll）；**`rename_clock ddr_user [get_clocks {u_ddrmc_test_top/u_ddrmc_x32/usr_clk}]`**；时钟组异步；`derive_clocks`；两条 FIFO 的 4 条 `set_path_skew 4.000`。**本批不修改该文件**（1333 的周期变化由 IP 内 PLL 分频自然产生，E2 在 STA 中核对实际 `ddr_user` 周期）。
- **引脚**：非 DDR 引脚在项目 `board.adc`（SHA `1CB30346FA17DA6BB0E77802CA72C4B4BB4AECC1445711E19391CF4EE2271580`，7154B）；**DDR 引脚来自 IP 闭包 `vendor/ip/ddrmc_x32/src/adc/ddrmc_x32.adc`（SHA `751997438BD28E2A956864493B3083008E1458878263DD709A569FECA09C0BAA`，`set_ippin_assignment`，含 `set_ipinst_assignment` 硬核位置）**；golden 基准 `ap115v2_ddr3_x32.adc`（`F0904238…DB33DA`）为 70 引脚比对源（已由上一 run 逐项核对）。
- **IP 注册**：`build_rgb565.tcl` 内 `add_files ./vendor/ip/ddrmc_x32/ddrmc_x32.xml`（fileset 带入 `src/adc`、`src/sdc` 与全部 `src/rtl`）；另有 `add_files ./board.adc`、`./timing.sdc`。
- **构建入口（脚本，SHA 冻结）**：`build_rgb565.tcl`=`5AA25FD2…`（create_project/全部 add_files/`top_module camera_ddr_display_top`/`set_strategy -run phy_1 TimingHigh`/`launch_runs syn_1`/`wait_run syn_1 -quiet`）；`route_rgb565.tcl`=`019DB289…`（native 路径：`import_device`→`open_project .al`→`load_run_param -run phy_1`→`import_db syn_1 gate.db`→`commit_param place`→`insert_debugger`→`place`→`export_db csi_checked_place.db`→`commit_param route`→`route`→`update_timing -mode final`→`report_timing_summary ./capture_timing.rpt` 等六报告→`export_db csi_checked_debug_pr.db`）；`bitgen_rgb565.tcl`=`FCCE5E20…`（→`bitgen_rgb332_body.tcl`：open .al→`import_db` pr db→final STA **fail-closed 门**（sw/hw/pw≥0、TNS=0、skew 约束 4 条+8 条 Slack 非负、abnormal 无端点）→`bitgen -bit ./camera_ddr_display.bit`→`close_project`；**不下载**）。
- **既有 runner**：`tools/td/run_rgb565_native.py`（SHA `5196D62DAE04917F95B9989016DF06FA791DDCF7E2108AB20BF9F99D6F8AE755`；**硬编码 6.2.2 CLI**，本批不改、不复用其执行）。其断言集合是本批新 runner 的下限（见 §3）。
- **velocity 参考（非本批）**：002820 实测 build≈2.3min、route≈16.7min（6.2.2）；114913 route≈28min。

**vendor 布局（002820）**：

| 路径 | 内容 | 本批处置 |
|---|---|---|
| `vendor/ip/ddrmc_x32/**`（61 文件） | 现役 1600 IP 闭包（.params/.m_params/.ports/`.v`/`.xml`/Design/DesignConfiguration + `sim/fileset` + `src/{adc,rtl,sdc}`） | **被新 IP 闭包整体替换** |
| `vendor/ip/ddrmc_x32_{adc,drc_check,proc}.log` | 1600 IP 生成日志（1387/489/327B） | **替换为新 IP 对应日志**（见 §2） |
| `vendor/ip/RTL/ph1p_ddrmc_wrapper_9c315a506595.v`、`vendor/ip/RTL/include/define.v` | 历史遗留，未被 build/编译引用（仅 manifest 收录） | 原样保留（等值豁免，见 §5 清单） |
| `vendor/rtl/**`（usr_mcu_srcs 等，含 `mcu_rom/mcu_rom.txt`） | MCU 源码与 ROM | 原样保留 |
| `vendor/adc/ap115v2.adc` | 历史引脚表，未被引用（仅 manifest 收录） | 原样保留（等值豁免） |

## 2. 新 IP（DDR1333 闭包）与差异（冻结）

**冻结源（推荐 run1）**：`D:\TD\work\csi2\_validation\td2026_gui_bootstrap_20261017_000935\ip_out\`，`candidate_manifest.json` SHA `D71057F3E3B859AD34BBEC477232938A8AA6DE8BBDDF04AE1C75605074C08434`（64 文件=61 闭包+3 日志）；**等价镜像 run2**：`D:\TD\work\csi2\_validation\td2026_b_run2_20261017_143128`（`9B3E5D00…`）。派生**只用 run1 单源**。

**文件映射（E1 冻结）**：

| 源（run1 `ip_out\`） | 候选内目标 |
|---|---|
| `ddrmc_x32\**`（61 文件，含 `ddrmc_x32.xml`、`ddrmc_x32.v`、`ddrmc_x32_ph1p_ddrmc_wrapper.v`、`Design.xml`、`DesignConfiguration.xml`、`.params/.m_params/.ports`、`sim/fileset/fileset_mis.f`、`src/adc/ddrmc_x32.adc`、`src/sdc/ddrmc_x32.sdc`、`src/rtl/**`） | `vendor/ip/ddrmc_x32/**`（同相对路径整体替换） |
| `ddrmc_x32_adc.log` / `ddrmc_x32_drc_check.log` / `ddrmc_x32_proc.log` | `vendor/ip/ddrmc_x32_adc.log` / `…_drc_check.log` / `…_proc.log`（替换） |
| （旧）`vendor/ip/ddrmc_x32/ph1p_ddrmc_wrapper_ddrmc_x32.v` | **不复制**（wrapper 更名：由 `ddrmc_x32_ph1p_ddrmc_wrapper.v` 取代；记录 before_sha 与理由，不做删除操作） |

**新旧差异（规划者逐字节比对，60 个同名文件）**：33 个逐字节一致（含 **`src/adc/ddrmc_x32.adc`=`75199743…`、`src/sdc/ddrmc_x32.sdc`=`ADB63179…`**，及各 cal/rc/… 文件）；27 个不同：

```
.m_params_ddrmc_x32.txt  .params_ddrmc_x32.txt  ddrmc_x32.v  ddrmc_x32.xml  Design.xml  DesignConfiguration.xml
sim/fileset/fileset_mis.f
src/rtl/cal/ph1p_ddrphy_cal_gate_wrapper.v   src/rtl/cal/ph1p_ddrphy_cal_wla.v
src/rtl/include/ph1p_mis_define.vh           src/rtl/mc/mc0_alc_mc_top_all.enc.sv
src/rtl/phy/ddrphy_cfg_rom.txt               src/rtl/phy/ph1p_ddrphy.v
src/rtl/phy/ph1p_ddrphy_cmd_decode.v         src/rtl/phy/ph1p_ddrphy_cmd_execution.v
src/rtl/phy/ph1p_ddrphy_cmd_wrapper.v        src/rtl/phy/ph1p_ddrphy_fast_init_wrapper.v
src/rtl/phy/ph1p_ddrphy_init.v               src/rtl/phy/ph1p_ddrphy_top.v
src/rtl/phy/ph1p_ddrphy_wphase_ctl.v         src/rtl/phy/ph1p_ddrphy_wrapper.v
src/rtl/timing/ddr3/ddr3_800.vh  ddr3_1066.vh  ddr3_1333.vh  ddr3_1600.vh  ddr3_parameter.vh
src/rtl/top/ph1p_ddrmc_top.v
```

（+wrapper 更名 1 项；E1 必须机器复算并与此清单**精确一致**。）

**接口不变量（E1 断言项）**：`ddrmc_x32` 模块端口 53 行新旧完全一致；`ddrmc_x32.v` 内 wrapper 例化名仍 `ph1p_ddrmc_wrapper`、wrapper 内仍 `ph1p_ddrmc_top`；`src/sdc`（rename 路径 `ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/…`）与 `src/adc` 的 `set_ipinst_assignment` 路径前缀均不受更名影响 → **项目侧 `ddrmc_display_top.v`、`camera_ddr_display_top.v`、`timing.sdc` 零改动**。

**参数（冻结值，E1 断言）**：

| 项 | 值 | 说明 |
|---|---|---|
| PH1P_DDR_SPEED / SPEED_BIN | 1333.00 / DDR3-1333J | `.params` |
| tCK / CWL / 派生 CL | 1500 ps / 7 / 10 | `.params` + `.m_params` |
| PLL0（物理 CK） | REFCLK 50、REF_DIV 3、FBK 80、CLK2 2、CLK3 27 → 50×80/3=1333.33MT/s，CK=666.6667MHz | ≤666.667MHz |
| PLL1（用户域） | REFCLK_FREQ 166.7、CLK0_DIV 9 | dhi_clk 约 166.7MHz（6ns）；以 E2 STA 实测为准 |
| 位置/电压/颗粒 | SYSCLK_LOC=H4、PLL_LOC=BANK33、IO1.35V、x16、2048Mb、REFCLK SINGLE、WDM、无 ECC、ROW_COL_BANK、NORMAL 重排、驱动 40/40/60/40/60 | 与 1600 相同配置，仅速率相关派生变化 |
| PH1P_IO_ASSIGN | 指向 run1 引导目录 `input_pins.adc`（`F0904238…`） | **保留原样**（生成溯源；构建实际引脚=闭包 `src/adc`+`board.adc`） |
| 生成头 | IpTool 2026.08(208212 2026/08/14)、TD Release_2026.2、Gen time 2026-10-17 14:23 | 6.2.3 全量再生成 |

**boot `.al`（旁证，不入候选）**：`ddr1333_proj_boot.al`（`EF721C4D…`）显示 IP 注册形态 `<IP_FILE><File Path="ip_out/ddrmc_x32/ddrmc_x32.xml">`，与 `build_rgb565.tcl` 的 `add_files …/ddrmc_x32.xml` 一致；**不把 boot 文件作为派生输入**。

## 3. 构建工具与调用约定（6.2.3，冻结）

- **CLI**：`D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe`，SHA256 `2629E474DF036A871807E564190FEBFBBD9780A09365F600C10463911C8C1223`（**runner 必须断言命中**）；`bin/IpTool.exe`=`5B0654AA…`、`bin/td.exe`=`FA2A5AC6…`；`arch/ph1_100p.db`=`939EC294…`；`license/Anlogic.lic`=`DC19FEE6…`（已在位；缺失时合成 worker RUN-8008，历史实测）；`DB_VERSION=46207`（实测）。
- **调用约定（沿用并冻结）**：命令=`[CLI 绝对路径, "./脚本.tcl"]`；**cwd=工程目录**；正斜杠必需（`./x.tcl`）；多行 Tcl 必须文件执行；`-help` 会被当脚本名；运行在 cwd 写 `td_*.log/.logw`（随工程保留）；**成功判定=退出码+脚本内大写完成标记+非空产物清单+哈希（三件套缺一不可）**；脚本加载失败也可能 exit 0。
- **版本纪律**：新候选全链同版本（IP 生成=6.2.3 → 综合/route/STA/bit 全用 6.2.3）；**旧证据不迁移**（002820/103222/111134/114913 继续绑定 6.2.2）；`run_rgb565_native.py` 与 6.2.2 工具保持冻结不动。
- **策略不变**：`build_rgb565.tcl` 原样（TimingHigh）；不做 `TimingUltra`/uncertainty 预留等实验（那是 111134/114913 的历史变量；本轮单变量=IP+工具版本，并通过 E2b 控制隔离工具版本）。
- **已知 quirk 沿用**：物理管理器历史问题→route 走 native `import_db`（脚本原样）；不对既有工程直接 `open_project`（先在候选副本上操作）；不从仓库中文路径运行；`D:\anlogic` 安装树只读（工具自身可能写 `bin\.setup.ini` 缓存，如实记录）。
- **license/DB 绝对路径注意**：CLI 从安装树解析 `ph1_100p.db` 与 license；不得混用 6.2.2 的 `D:\downlaod` 锚点（对照用，不执行）。

## 4. 候选派生与文件映射规则（E1 冻结）

- 新候选：`D:\TD\work\csi2\prj\camera_rgb565_ddr1333_<YYYYMMDD_HHMMSS>`；控制候选：`camera_rgb565_ddr1600ctl_<YYYYMMDD_HHMMSS>`（`mkdir(exist_ok=False)`；绝不覆盖）。
- 复制规则：逐项读取 002820 manifest 并**先全量复核 SHA**，再写候选；除 §2 映射的 64 文件外逐字节照抄；**不做路径重定位**（002820 持久冻结、其被引用文件有效；由此候选对 002820 的全部改动被限定在 64 文件映射范围内：范围外零差异、可全量断言）。`--control` 模式=零改动复制（改动集空、范围外零差异）。
- 候选内附加文件：`frozen_prepare_rgb565_ddr1333.py`（脚本自拷贝）、`input_manifest.json`（新 SHA，221 项）、`ddr1333_overlay.json`（差异记录：base/manifest/new_ip/removed/changes/unchanged_guards/fairness_checklist/`hardware_verified:false`/build 工具锚）。
- 断言不得被裁减（§4.1 列表见 dev-plan）；任何断言失败→停止并如实报告，**不手改生成 RTL/不掩盖**。
- `ddrmc_x32.xml` 完整性：E1 逐条核对 xml 文件名列表与磁盘一致（无悬空/无多余）。

## 5. 「只换 IP、其余保持等值」公平对比原则与核对清单

**原则**：1333 候选与 1600 基线（002820）的一切非 IP 输入逐字节等值；1333 与 1600ctl 使用同一工具版本、同一脚本、同一 runner、同一流程参数；历史 6.2.2 行在对比表逐行标注版本，不与 6.2.3 行混合归因。

| # | 核对项 | 期望 | 取证方式 |
|---|---|---|---|
| 1 | `ddrmc_display_top.v`、`camera_ddr_display_top.v` | 与 002820 逐字节一致（SHA 相等） | E1 断言+overlay unchanged_guards |
| 2 | `build_rgb565.tcl`、`route_rgb565.tcl`、`bitgen_rgb565.tcl` | 与 002820 一致（5AA25FD2/019DB289/FCCE5E20） | E1 断言 |
| 3 | `timing.sdc`、`board.adc` | 一致（0C32C5F7/1CB30346） | E1 断言 |
| 4 | `src/adc/ddrmc_x32.adc`、`src/sdc/ddrmc_x32.sdc`（IP 内） | 与 002820 **逐字节相同**（75199743/ADB63179） | E1 断言 |
| 5 | 相机/CSI/HDMI/打包/FIFO/store/reader/pixels/guarded 等（`camera/**` 与顶层 RTL） | 全量一致 | E1 差异集断言 |
| 6 | `vendor/ip/RTL/**`、`vendor/adc/ap115v2.adc` 等未引用遗留 | 原样保留（不参与编译） | E1 记录豁免 |
| 7 | ROM 引用 | `camera_ddr_channel…` 无改动；`camera_ddr_display_top.v` 的 `USR_MCU_ROM_INIT` 指向与 002820 相同的既有外部 ROM；`camera_ddr_capture_top.v` 保持 002820 指向（其冻结目录仍有效） | E1 差异集=64 覆盖 |
| 8 | 策略/参数 | TimingHigh、无 uncertainty 预留、无 SDC/ADC/PLL 手改 | 脚本 SHA 相等 + E2 记录 |
| 9 | 工具版本 | 1333 与 1600ctl 同 6.2.3（CLI SHA 2629E474…）；历史行标注 6.2.2 | E2 记录逐行版本列 |
| 10 | STA 口径 | 同 `update_timing -mode final`→`capture_timing.rpt`；同字段抽取；`check_timing_margin --min-setup-ns 0.3` 同门；端点组数**人工复核后显式** | E2 证据+gate 输出 |

## 6. 证据与文档约定（本批）

- 新证据 JSON（新建，不改既有）：E1 → `docs/evidence/ddr1333_integration_<YYYYMMDD>.json`（派生记录+断言输出+overlay 锚）；E2 → `docs/evidence/ddr1333_build_sta_<YYYYMMDD>.json`（执行记录+STA+gate+对比表+可选 bitgen 段）。
- 报告（E3）：`docs/DDR1333集成与1333vs1600对比_<YYYY-MM-DD>.md`（中文；需求映射/集成/构建/对比表/0.300 评定/建议材料/未决/回退；逐条引用证据+哈希）。
- 任务板：`workflow/tasks.json` **仅 T01**；改前记录观测 SHA（规划时点 `91CDFE22…`）；改后 JSON 解析自检。
- 测试报告：`OUTPUT_DIR/test-reports/<task_id>-r0-<dimension>.md`（`report-contract.md`，首行判定；三维独立）。
- 运行产物：`native_<stage>.json/.txt` 写在候选工程内，**不覆盖**；`td_*.log` 随工程保留。
- 大文件不进仓库（gate.db/pr db/bit/cwc 等留 D 盘工程；仓库只存 JSON 证据与报告）。

## 7. 已冻结 / 待确认 / 不适用

- **已冻结**：§1 基线入口/接线与脚本 SHA；§2 新 IP 源、映射、差异清单与参数值；§3 6.2.3 工具锚与调用约定；§4 派生规则与断言边界；§5 公平核对清单；§6 证据路径与记录义务。
- **待确认（由 E2 实测回答，先不定论）**：6.2.3 全链综合/route 是否一次通过；`ddr_user` 实际周期与 Clock Summary；最终报告端点组数；0.300 gate 接受与否（如实）；1600ctl 结果；可选 bitgen 是否条件满足。
- **不适用并说明**：G3/G4（无板测/无长稳/无下载）；HDMI 串行电气资格；GUI 操作；SDC/ADC 修改（无差异）；800 档评估（后续用户决策项）。

## 8. 本次三个测试维度的边界

- 功能（E1）：派生断言与差异集核算、参数/端口/引脚不变量、xml 闭环、单源核对。
- 工程（E1/E2）：哈希链、no-overwrite、超时/失败如实、越界写扫描、冻结件零漂移；E2 另含 STA 再抽一致性与 gate 评审记录。
- 系统（E1/E2/E3）：仓库→候选→构建→数据的端到端入口与可复现性；对比表与结论边界（未板测/真实 DDR 行为未测）；任务板/报告一致性。
- 所有维度**不测**：真实相机颜色、真实 DDR 校准行为、板卡持续运行、GUI/下载——这些属后续板测（G3/G4）与用户决策范围。
