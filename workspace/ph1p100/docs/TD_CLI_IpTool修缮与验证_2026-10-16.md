# TD CLI / IpTool 修缮与验证报告（2026-10-16）

- run：`workflow/runs/20261016_185639_td_cli_iptool`（工作包 T01.tool-A/B/C/D）
- 角色：fpga-dev（T01.tool-C 报告与同步工作包）；撰写日期：2026-10-16
- **一句话结论：6.2.2 上 IpTool headless 生成经 20/20 次受控尝试全部失败、边界经受控实验证实（无任何完整 IP 产物）；TD CLI 六命令（含 bitgen）在 scratch 工程 0→bit 全链真实跑通；TD 2026.2（6.2.3.210850）并行安装成功、Tcl IP flow 命令族实测可用、DDR1333 参数注入成功；DDR1333 IP 最终经「CLI 引导配方 + 用户在场 GUI Generate」生成成功并通过双复现验收（2026-10-17，见 §6；**GUI 步骤不计 headless 成功**，全自动 headless 生成仍不成立）。**
- 溯源纪律：每条结论对应证据文件 + 哈希；**本报告引用的全部 SHA256 为 2026-10-16 撰写时磁盘重算值**；旧证据绑定 6.2.2、新证据绑定 6.2.3，**不跨版本拼接**；未实测项一律如实标注，不写"通过"。

## 0. 需求三项映射（requirement.md）

| # | 用户交付 | 工作包 | 结果（如实） | 主要证据（SHA 见 §7） |
|---|---|---|---|---|
| 1 | 修缮 TD CLI 中 IpTool 设置问题并实际跑通 | T01.tool-A（6.2.2）/ T01.tool-D（6.2.3） | **未跑通（边界已证实）**：6.2.2 无可用 headless 生成入口（20/20 尝试零产物）；6.2.3 命令族可用、参数注入成功，但生成被 `_adc.log` staging 前置确定性阻塞 → 转 GUI 决策点 | `ddr1333_iptool_cli_20261016.json`、`td2026_ipgen_20261016.json` |
| 2 | 写报告（docs 报告 + 证据） | T01.tool-C | 本报告 + 4 份证据 JSON + 3 处文档增补/更新 | 本文件；§7 索引 |
| 3 | 其他 CLI 控制命令核验、保证跑通 | T01.tool-B（6.2.2）/ tool-D 回归（6.2.3） | **跑通**：六命令（open_project/import_device/launch_runs/wait_run/report_timing_summary/bitgen）在两版本各完成一次 scratch 0→bit 全链（bit 未下载，G2-lite） | `td_cli_commands_20261016.json`、`td2026_regress_evidence.json` |

用户追加决策（requirement.md 附录3，原话）：「…先把版本更新下，然后下完新版本后如果还无法进行ip核设置就进行gui」→ 已按此执行 T01.tool-D（安装+验证）；GUI 属下一步（未执行）。

## 1. 现状与 10-15 前史

- **10-10 基线**：`tools/td/verify_cli.tcl`（SHA `B3269486…`，422 B，本批未改）六命令注册检查通过；当时已录：TD/TD CLI 不能处理中文路径、正斜杠必需、退出码不可单独证明成功。
- **10-15 前史**（两文档两证据，均为 6.2.2；本批只读引用）：
  - 不带 `-tcl` 的 copy 形态生成两次超时（30 s / 45 s，零产物）——`docs/evidence/ddr1333_ip_regeneration_20261015.json`（SHA `4A3400D4…`）；
  - `-tcl -source` 诊断入口可用（取得命令帮助，含 `create_dialog`）；copy 增加 `-tcl` 后自然 exit 1、零输出零产物；`-qcerr` 20 s 超时——`docs/evidence/ddr1333_ip_retry_20261015.json`（SHA `B50E3EB0…`）；
  - 190248 人工包准备完成（197 项输入 SHA、私有 depot、绑定 guard、保留式清理；GUI 未启动/未验证）——`DDR1333候选评估与生成入口_2026-10-15.md`（`DD216712…`）、`DDR1333_IPTool再次尝试与人工操作_2026-10-15.md`（`D894A825…`）。
- **官方文档边界**：IPUG034（MIS IP，仅 GUI 定制流程）与 SWUG105（Tcl 实现流）**均不记载 IpTool headless 生成**；自动生成属未文档化探索（规划者核实，见 `fpga-design-guide.md` §1/§3）。
- 工具常量（6.2.2）：`td_commands_prompt.exe` `79EC5667…`（119,567,120 B）、`IpTool.exe` `DA9E765E…`（19,382,784 B）、Tcl 8.6.15、DB_VERSION 46207。

## 2. 根因分析（脚本 argv 缺陷 vs 工具行为 vs 环境约定；含 6.2.2/6.2.3 对比）

### 2.1 脚本 argv 缺陷（我们侧，已修复并于 6.2.2 侧坐实）

| # | 缺陷/行为 | 实测证据（6.2.2，A 证据 `078b5ac3…`） | 修复/结论 |
|---|---|---|---|
| a | **`-user`/`-gen` 是目录选项，不是文件选项**：参数被当"目录 + 期望文件名"拼接校验（`-user X` 校验 `X/Design.xml`；`-gen Y` 校验 `Y/Component.xml`） | H2d 对话框原文 `Failed to identify the file: …/ddrmc_x32.xml/Design.xml`（PNG `EE9627FC…`）；H2e 弹 `…/Component.xml/Component.xml`（PNG `13592F32…`）。历史脚本（165740/190248 launcher、10-15 copy 尝试、本批前 9 次）全部使用文件形态 | 一切自动生成尝试必须用**目录**形态；`prepare_ddr1333_ip.py` 默认 argv 已参数化并附警示 |
| b | **`-use_value` 是自动路径开关**：不带 `-use_value` 时即使加 `-no_status` 也会开交互配置窗并永久等待人工 | attempt 13（h2h）：900 s 超时被杀，窗口实拍含 "Switch to Default Configuration" 工具栏；早前 H2 600 s 同现象 | `-use_value default|copy` 必带；见 c |
| c | **不带 `-app_path` 时错误对话框不出现**（静默）；加 `-app_path` 后才弹出错误详情 | H2d（加 app_path 后弹错）；H2/H2b 静默 exit 1 | 排障时带 `-app_path D:/downlaod/bin/td.exe`（注意其派生 `<stem>_commands_prompt.exe` 子进程名） |
| d | **`-tcl` 与生成参数互斥**：`-tcl` 是脚本模式开关、强制 `-source *.tcl`；与 `-gen/-user` 同用要么快速 exit 1（0.27 s）要么挂起（`-qcerr` 20 s） | 10-15 记录 + 本批复核 | "copy + `-tcl`"从未到达生成逻辑 |
| e | **手工编辑实例破坏 copy 取值**：仅改 `Design.xml`/`.params_*` 而不同步 `.m_params` → copy 时取值回退默认（日志 `set_spin_box_text REF_CLK 100.00 / DDR_SPEED 800.00`） | H8：换用**工具期自产、未手改**实例（002820 `vendor/ip/ddrmc_x32` 只读副本）作 `-user` 源后，日志出现真实取值 `50.00 / 1600.00` → 根因坐实 | 后续 `-use_value copy` 一律用内部一致的实例；`prepare` 脚本 `argv_notes` 已增警示（具体破坏编辑点未逐项隔离） |

**脚本侧修缮交付**（T01.tool-A）：`tools/td/prepare_ddr1333_ip.py` 终版 SHA `2D345898…`（14,468 B；历史基线 `81b4f29a…`）：`cli_entry_status` 改**写实**（不再自标 `inferred`，引用证据 JSON、可 `--entry-status` 覆盖）；argv 参数化（`--comp-name/--use-value/--extra-flag/--user-mode/--gen-mode`）；**10/10 断言全数保留**（002820 manifest、220 项基线逐项 SHA、70 引脚 golden 比对、`mkdir exist_ok=False`、保留式清理"无活动 file delete"等，经测试者逐行 diff 复核）。新增实验 runner `tools/td/run_ddr1333_ipgen.py` SHA `B44E065C…`（48,089 B；无删除调用、超时真杀进程树、`assert_exp_dir` 限定实验目录）。

### 2.2 工具行为（工具侧；6.2.2 与 6.2.3 对比）

**6.2.2 侧（A 证据 `078b5ac3…`）**：

1. **修正形态进入生成阶段但确定性失败**：attempts 11/12/14（双目录 + `-no_status` + `-app_path`；copy×2 + default×1）均 exit 0、~2.5 s、导出 8 文件/57,702 B 脚手架，工具日志 `#IP Generate Failed!`；三次 `log/ipgen.log` 与 `.m_params` **逐字节一致**（`88550b28…` / `46432cc0…`）→ 系统性失败、与值模式（copy/default）无关。失败细节在短命子进程 `td_commands_prompt.exe`（<0.5 s，无 `td_*.log`、stdout/stderr 不继承）内——常规模具不可捕获（H9 判据）。
2. **6.2.2 无 Tcl IP flow 命令族**（H6 定案）：`create_ip/get_ipdefs/get_ips/generate_target/generate_ipinst/load_project_ips/close_project_ips/report_ip_status/ip_upgrade/create_ipinst/delete_ipinst/list_ipinst` 全部 **absent**；present 者为 `set_property/get_property/create_syn_ip/xmlipgen/ipgen_synip/print_ip_config/read_ip_adc/export_ip_lib/set_ip_property/set_ippin_assignment/save_best_bits/reset_runs` 等（另见注册表 `generate_gate/generate_simulation/process_vlog_files/read_adc/export_ip_pins/export_ip_sdc/import_ip_pin_list/set_hxt_property/set_ipinst_assignment`），全部**无单命令帮助文本**（`help` 只打印整表）。
3. **6.2.2 侧无任何可用"设参 + 生成"入口**（H7 关闭该线）：`set_ip_property` 静默受参（无可观测效果）；`read_ip_adc` 需工程 IP model（`USR-8321`）；`create_syn_ip` 需 top model（`PRJ-9009`）；`xmlipgen` 恒为 `HDL-8001 XmlIpGen cannot find all xml file`（需 IpTool 预备的未公开 XML 文件集；`-h/-help` 空输出）；`ipgen_synip` 无动作；`export_ip_lib` 报错。
4. **`-tcl -source` 是唯一已证实可用的 IpTool 入口**（诊断用途）：本批复跑 exit 0、trace 齐全、Tcl 8.6；`generate_ipinst` 不存在、`create_dialog` 实际未注册（`invalid command name`，仅存于静态 help 表）→ "脚本驱动生成"在已注册命令集合内**不可行**。
5. **工具会在实验目录外写安装目录一个 21 B 状态文件**：`D:/downlaod/bin/.setup.ini`（内容 `LAST_POS=(251, 177)`，窗口位置缓存；SHA `CA6E73AE…`，mtime 20:41:42 = A 最后尝试时段）；IpTool.exe 本体与官方 depot 锚点全程未变——如实记录，非破坏性。

**6.2.3 侧（D 证据 `td2026_ipgen_20261016.json`，A9D0B9B0…）**：

6. **Tcl IP flow 命令族真实存在且可用**：`create_ip -vlnv/-component_name/-export_path`（export_path 必须为**已存在目录**）、`load_project_ips`（跨会话重开工程后必须）、`get_ips`、`set_property CONFIG.<param> <value> [get_ips <n>]`（参数顺序与 Vivado 相反）、`generate_target [get_ips <n>]`、`close_project_ips`；成功 `IPT-1001`、失败回滚删除 staging、首次成功后工具清理其 `.IpToolIpDataBackupDir_*` staging。
7. **DDR1333 参数注入可行**：29 项 `set_property` 全部 rc 0（5 项 ReadOnly 警告：`PH1P_PINGPONG_PHY/PZQ_CAL/PZQ_SHARE/RDBI/DDR_PARITY`）；派生值在 `.params_ddrmc_x32.txt` 正确：`tCK=1500`、`PH1P_DDR_CL=10`、`CWL=7`、`PH1P_ACTUAL_FREQ=666.7`、`PH1P_DDR_SPEED=1333.00`、`PH1P_SPEED_BIN=DDR3-1333J`；`PH1P_SYSCLK_LOC=H4` 被拒（`IPT-1002 … The range list is empty`，该参数范围依赖 ADC check 产物）。
8. **DDR 生成被 `_adc.log` staging 前置条件确定性阻塞**（本批最终边界）：`generate_target` 恒败 `[Error-TclFile] couldn't open "<export>/.IpToolIpDataBackupDir_ddrmc_x32/ddrmc_x32_adc.log": no such file or directory`（≥8 次同因，1.6–4 s 内失败）。机制（脚本级只读复核 + 实测三方闭合）：`Dependency.tcl` 的 `update_gui_pll→cal_onlyacbkby` / `update_sysclk_loc` 以 `open r` **读** `<export>/<comp>_adc.log`，写该文件的是 `drc_check`（同文件尾段）；工具在 generate 开始时**清空 staging** → **先读后写** → 首次生成永缺该文件。该文件正常由 **GUI 的 ADC 选择/应用（check）步骤**物化（工具自产参考件：002820 `vendor/ip/ddrmc_x32_adc.log`，1,387 B `CAB90FE0…`，格式 `sig,bank,byte,pin`）。CLI 无等价入口：`read_adc`/`read_ip_adc` 均 `USR-8321`；`CONFIG.PH1P_IO_ASSIGN` 的 set 不触发 check（其无依赖回调）。
9. **小 IP headless 生成跑通**（对照成立）：`APB_GPIO` 冒烟 `create_ip→set_property→generate_target` 产出 `IPT-1001` 与完整 RTL（79,151 B 等）——证明命令族/流程本身可用，隔离出 DDR 特有的 ADC-check 依赖。

**版本对比（6.2.2 → 6.2.3）**：

| 维度 | 6.2.2（`D:\downlaod`） | 6.2.3（`D:\anlogic\TD_Release_2026.2`） |
|---|---|---|
| Tcl IP flow 命令族 | **无**（H6 定案） | **有**（8 项 PRESENT，实测可用） |
| IpTool 版本 | `2026.03(193873 2026/03/31)` | `2026.08(208212 2026/08/14)`（新锚点 `5B0654AA…`） |
| Tcl | 8.6.15 | 8.6.17 |
| DB_VERSION | 46207 | **46207（相同）** |
| DDR 生成入口 | 修正形态仍 `#IP Generate Failed!` | 参数注入成功；generate 卡 `_adc.log` staging（同一工具内前置） |
| 外部配方（`create_ip/get_ips/set_property/generate_target`） | 不可移植（未注册） | 已可移植（SWUG105 2026.08 §4.4 收录；外部 H2 记录同族） |

### 2.3 环境约定（B 证据 `6f648f0f…` 逐条实测复证；含 6.2.3 回归同现象）

| 约定 | 实测结论 |
|---|---|
| 正斜杠必需 | `./x.tcl` 成立（q1）；`.\x.tcl` 失败——被 Tcl 字符串转义吃成 `.q2_backslash.tcl`（`couldn't read file`） |
| cwd 硬约束 | 相对路径全部按 **cwd** 解析、与脚本位置无关（q7b 错误 cwd 连 `./脚本` 都找不到；q7c 绝对脚本 + 错误 cwd → `PRJ-8642` 且显式 `exit 1` 传播）；`td_*.log/.logw` 严格写 cwd（root 28 = 14 阶段 ×2 实测） |
| 退出码语义 | **脚本内显式 `exit 1` 会传播**；而**加载失败/未捕获命令错误**（文件不存在、invalid command、PRJ-8642）→ 打印错误、落入 `td >` 交互提示、进程 **exit 0**（neg1/neg2/q2/q3b/q8 五处实证）⇒ 成功判定只能"退出码 + 显式标记 + 非空产物"三件套 |
| `-help` | 被当脚本文件名（`couldn't read file "-help"`，exit 0） |
| stdin 多行 | 口径修正：简单 3 行管道 stdin 实测可用；真实流程仍一律文件执行（10-10 "括号解析错误"未复现） |
| 中文路径 | 复证不可用（q8，ASCII cwd 内隔离测试）；一切 TD 执行须 D 盘 ASCII 目录且 cwd=该目录 |
| 打开既有工程 | 先整目录复制再 open（open/close 会改写 `.al`）；冻结工程只读 |
| 双版本共存（tool-D） | 用户 PATH 追加新 bin 于旧 bin **之后**（裸名 `td_commands_prompt` 仍先命中 6.2.2）；`.al` 扩展名**默认关联已切到新版本 ProgID**（双击 .al 打开 2026.2 GUI；旧版仍可用绝对路径/右键）；脚本一律使用**绝对路径** |

## 3. 逐项修复与验证结果

### 3.1 T01.tool-A — IpTool headless 生成（6.2.2）H1–H9 边界结论

全部为真实执行记录（A 证据 `078B5AC3…`；三维测试 round0 PASS，零修正轮，报告见 `test-reports/T01.tool-A-r0-*.md`）：

| 假设 | 单变量/目的 | 结果（如实） |
|---|---|---|
| H1 | usage default 形态（无 `-user`/`-tcl`） | exit 1 @2.64 s、静默、零产物 |
| H2 系列 | copy 形态 → +`-no_status` → +`-proj_path` → +`-app_path` → `-user` 目录化 → **修正形态实跑** → 复跑 → 去 `-use_value` → `default` 模式 | 600 s 超时（窗口 ~7.2 s 起挂起）→ 静默 exit 1 @2.58 s → 同 → **弹目录契约错误对话框** → 弹 gen 侧同错 → exit 0 @2.83 s、8 文件脚手架、`#IP Generate Failed!` → 逐字节同日志 → 交互窗 900 s 超时 → 与 copy 完全同败（系统性问题） |
| H3 | `-tcl -source` 探针（`info commands`/help） | `generate_ipinst` 不存在；`create_dialog` 未注册；库命令不覆盖生成 → 脚本驱动生成不可行；`-tcl -source` 正对照 exit 0 可用 |
| H4 | TD CLI `xmlipgen`（scratch 工程） | 内部引擎步骤：`-h/-help` 空、猜参被拒、裸调用 `HDL-8001`（需未公开 XML 文件集）→ 不是用户入口 |
| H5 | GUI 边界取证（私有副本 launcher） | 窗口出现、参数表能显示（窗口证据客观记录）；绑定 marker 40 s 内未出现；**未**把 "GUI 打开过"写成"生成跑通"；190248 人工包保留为下一步 |
| H6 | 6.2.2 命令集普查（只读探针） | 命令缺口**定案**（见 §2.2-2）；"外部 6.2.3 配方不可移植"由此成立 |
| H7 | 最小受控调用（设参+生成候选入口） | 无可用入口（`USR-8321/PRJ-9009/HDL-8001` 证据）→ 该线关闭 |
| H8 | 一致源实例对照（工具自产实例作 copy 源） | **取值加载机制坐实**（日志 50/1600；手改实例回退默认的根因确认）；外部 golden ADC 路径本地化后仍 `#IP Generate Failed!`（4 次运行 log `78A4A21C…`/.m_params `FDE70A5A…` 逐字节一致）→ 外部"ADC 路径"根因**必要但不充分** |
| H9 | 生成链子进程捕获 | 子进程 `td_commands_prompt.exe` 约 0.2 s 被 spawn、存活 <0.5 s；cmdline/控制台文本不可得 → 判"常规模具无法捕获子进程失败文本"（需调试器/ETW 或原厂支持） |

- **尝试账**：20/20 触顶（10+4+6），单变量纪律未违反；负对照（不存在 `-user` 路径）实测 exit 1、零产物（tester 独立复现）；`-tcl -source` 正对照通过。
- **结论**：**无 headless 生成成功**、无任何完整 IP 产物、无候选冻结；T01 维持 blocked。修复侧交付=脚本写实/参数化 + runner + 证据 + 边界结论（本轮"修缮"的可交付部分已闭环；工具级生成仍不可行）。

### 3.2 T01.tool-B — TD CLI 六命令端到端核验（6.2.2）

实验目录 `D:\TD\work\csi2\_validation\td_cli_20261016_205203`（只新建；16 阶段脚本/资产冻结后 SHA 全过）；证据 `td_cli_commands_20261016.json`（`6F648F0F…`；含 raw `command_table` 与 `analysis` 节）。三维 round0 PASS（`test-reports/T01.tool-B-r0-*.md`）。

| 命令 | 覆盖 stage | exit | 成功标记（原始 stdout 复核） | 非空产物（磁盘重算） | 结论 |
|---|---|---|---|---|---|
| `import_device` | s1–s4 | 0 | stage 标记 + `ARC-1001` | `gate.db` 143,506 B `E0318D87…` | **pass** |
| `open_project` | s2/s3/s4/q7a | 0 | `…ROUTE_RETURNED`/`…TIMING_RETURNED`/`…BITGEN_NO_DOWNLOAD`/`Q7_OPEN_OK` | `pr.db`/rpt/bit | **pass** |
| `launch_runs` | s1/s2 | 0 | `…LAUNCH_RUNS_RETURNED` + PRJ-1403 | `gate.db`/`pr.db` | **pass** |
| `wait_run` | s1/s2 | 0 | PRJ-1405/1406 + 后续产物 | `run.log` 28,930 B | **pass** |
| `report_timing_summary` | s3/s4 | 0 | `TD_CLI_E2E_TIMING_SWNS 17.081` | rpt 163,693 B `B63A6578…` | **pass** |
| `bitgen` | s4 | 0 | `…BIT_BYTES 5223983` + `…BITGEN_NO_DOWNLOAD` | **bit 5,223,983 B `1816AFF8…8E939115`**（未下载）；bid 190 B `11E94771…` | **pass** |

- 全链 `syn 8.8 s / route 22.4 s / timing 6.3 s / bitgen 6.8 s`（每阶段整进程含 TD 启动）；时序 SWNS 17.081 / HWNS 0.222 / PERIOD 0.000。
- **负对照（必须实测，已实测）**：`neg1_open_missing`（开不存在工程）→ `PRJ-8642`、脚本中止、**exit 0**、collector 判 fail；`neg2_undefined_command` → `invalid command`、**exit 0**、fail；对照 q7c 显式 `exit 1` 传播 ⇒ "退出码不可单独证明成功"获双重实证。
- **已知 quirk 逐条落证**（10 条）：正/反斜杠、`-help` 当脚本名、stdin 口径、cwd 约束三例、中文路径、exit 语义、`save_best_bits` 观察（见 §4.2）、`td_*.log` 写 cwd。测试冻结后 `tools/td/verify_cli.tcl` 未改（`B3269486…`）；新增 `verify_cli_e2e.py`（`D59D349F…`）/`verify_cli_e2e.tcl`（`440785F3…`）。
- 边界：scratch 仅 **G2-lite**（证命令可用），bit 未下载；`D:\downlaod` 前后全量 mtime 扫描零写入；002820 与 190248 manifest 未变。

### 3.3 升级审核结论与用户决策记录

- 审核材料：`upgrade-review.md`（SHA `C8E1FFC41A9B1D55FB2E53D0D8CF4D4CAD6804CF76808C2BAE1E03D296BE6BA3`，规划者 2026-10-16 21:0x 只读审核，未下载/未安装）。**总结论：取决于条件（大概率能解决，但 4 个条件未闭环）；不升级的 GUI 路径是确定可行的保底。**
- 关键事实链（审核内分级为【事实】/【外部实测声称】/【推断】/【未知】）：队友两仓库与本机同板样本均使用 TD **6.2.3.210850（Release_2026.2）**；其 IP flow 配方依赖该版本（我 6.2.2 未注册，双侧实测）；DDR MC「设置 ADC + `generate_target`」有外部实测声称（`IPT-1001`/61 文件），**完整参数注入（1333 档）未闭环**；MIPI_DPHY 批处理不产 RTL 为反例（覆盖按 IP 而异）；本机无 2026.2 安装包；并行安装可保持全部 6.2.2 冻结锚点，就地升级不推荐；仅换 depot 不可行（缺口在 TD 主程序）。
- **用户决策记录**（main-log 261016 2240/2315/2405 条目；requirement.md 附录3）：选择「更新版本（与队友 6.2.3 对齐），若仍无法进行 IP 核设置则转 GUI」；安装包 `C:\Users\czz\Downloads`（TD+BW 两个），授权安装到新目录。主调度据此设立 T01.tool-D；**C 报告排至升级尝试出结论后执行**（不回溯改 A/B 结论）。

### 3.4 T01.tool-D — 6.2.3 并行安装 + 锚点登记 + 四步验证（结论：边界 + GUI 决策点）

**安装**（install 证据 `td2026_install_20261016.json` `EF5545CC…`）：

- 安装包 `C:\Users\czz\Downloads\TD_Release_2026.2_NL.exe` SHA `3B92ABE8…751A0A`（1,969,702,400 B；磁盘重算；"= 官网页值"本环境**无法匿名复核**，本机可证="磁盘哈希 = dev 记录值 + Authenticode 签名有效 + PE 版本一致"）；BW msi（`B399BFF9…`，68,226,048 B）仅记录未装。
- 安装器 = Advanced Installer 21.6.1 引导器 + 独立 MSI（ALLUSERS=1；主目录属性 `APPDIR`；ProductCode `{C96C0B0F…}`）；`/qn` 非提权必败 1603（日志根因行 `MSI_LUA: … no credential elevation is possible`）；**`/exenoui /qb /norestart APPDIR="D:\anlogic\TD_Release_2026.2" /L*V <log>` + 用户点 1 次 UAC「是」→ exit 0 @106 s 安装成功**。
- **license 处置**：新装 license 为空 → 合成 worker `RUN-8008 Cannot find license file`（外层易误判为管理器缺陷：`PRJ-5303`/`PRJ-8806`）；复制 `D:\downlaod\license\Anlogic.lic`（`DC19FEE6…45C1A6`，NODELOCKED，至 2027-03-31）后全链通过。
- 版本直取：**TD Release_2026.2 / 6.2.3.210850**（Built 11:35:58 Aug 19 2026）；Tcl **8.6.17**；DB_VERSION **46207**（与 6.2.2 相同）。

**新锚点登记**（全部磁盘重算命中；旧 6.2.2 与 `D:\downlaod` 锚点全程未变）：

| 项 | 6.2.3 新装（`D:\anlogic\TD_Release_2026.2`） | 6.2.2（`D:\downlaod`，未变） |
|---|---|---|
| `bin\td_commands_prompt.exe` | `2629E474…C1223`（123,372,304 B） | `79EC5667…87190`（119,567,120 B） |
| `bin\td.exe` | `FA2A5AC6…06A87`（123,372,304 B，**同尺寸、不同构建**；dev-notes"同体二拷贝"措辞已按哈希更正） | `B7129888…DA2AFA` |
| `bin\IpTool.exe` | `5B0654AA…75CEC`（24,507,392 B） | `DA9E765E…A3DE46` |
| `bin\bw.exe` | `89501B2D…22008`（18,968,840 B） | `FF57B653…B277D7`（历史锚） |
| `arch\ph1_100p.db` | `939EC294…3FF77B`（11,037,320 B） | `8E7E8812…CF3AA2` |
| MIS depot `Component.xml` / `Dependency.tcl` | `3E854A26…BBFB8`（229,562 B）/ `51C2311F…52075A`（135,645 B） | `FEB4F5BC…D5E543`（229,550 B）/ `CD927834…119623`（135,217 B） |
| `license\Anlogic.lic` | `DC19FEE6…45C1A6`（258 B，复制自 6.2.2） | 同 SHA（源未变） |

**四步最小验证**（ipgen 证据 `td2026_ipgen_20261016.json` `A9D0B9B0…`；试验根 `D:\TD\work\csi2\_validation\td2026_20261016_214505\`）：

1. **命令族探针**：PRESENT（8 项）= `create_ip/get_ipdefs/get_ips/set_property/get_property/load_project_ips/close_project_ips/generate_target`（另有 `read_adc/read_ip_adc`）；ABSENT = `report_ip_status/generate_ipinst/create_ipinst/delete_ipinst/list_ipinst`；`help` 只打印整表（`USR-1002`），注册表含 7 命令 usage 原文。tester 独立探针与 dev 逐项一致。
2. **小 IP smoke = PASS**：`APB_GPIO` `create_ip→set_property(AL_GPIO_WD=8，.params 复读)→generate_target` → `IPT-1001 : The target has been generated successfully.`；产物 RTL 79,151 B 等；tester 独立重跑（新实例名）**与 dev `.params` 逐字节一致**（`0728459C…`）。
3. **DDR1333 = 边界（确定性失败）**：参数注入成功（见 §2.2-7）；`generate_target` 恒败 `_adc.log` staging（≥8 次同因）→ **候选未冻结**；tester 独立单次尝试同根因同响应（其 `.params` 与 dev 仅 ADC 路径行不同）。
4. **六命令回归 = PASS**：冻结套件**字节副本**（仅改 `TD_EXE`/`PH1_DB` 两行；副本 SHA `F916DDA1…`，与 tester 独立构造副本逐字节相同）在新版重跑：p1/s1(syn)/s2(route)/s3(timing, DB_VERSION=46207)/s4(bitgen) 全 PASS；quirk 抽查 q1✓/q2✗按预期/q3b✗按预期/q7a✓；`save_best_bits` 仍"接受无产物"（同 6.2.2）。回归证据 `cli_regress\td2026_regress_evidence.json` SHA `ADCC42F5…`；关键产物：gate.db `4665BF81…`、pr.db `CD620226…`、timing rpt `319548F7…`、**bit 5,223,979 B `CFE81199…A4048CFC`**（未下载）。
   - system 测试者**独立复跑**（不复用任何 dev 成品）：6 阶段全 PASS、零 PRJ-88xx，bit `B6276241…F7791B9`（5,223,979 B）与 dev bit 逐字节仅差头部 `# Date:` 2 字节、**Global CRC 相同** → 6.2.3 bitgen 对同一设计内容确定。

**四步结果小结**：①②（smoke）跑通、③（DDR 生成）**未跑通 = 边界**、④（CLI 回归）跑通；GUI 后备**未执行**（决策点，见 §4.1）。三维 round0 PASS（`test-reports/T01.tool-D-r0-*.md`）。

## 4. 边界与未决项

### 4.1 DDR1333 headless 卡 `_adc.log` staging → GUI bootstrap 待用户（主未决项）

> **2026-10-17 更新（已收束）**：下方选项 A/B 均已执行——A 前提**不成立**（GUI OK 不物化 `adc.log`、CLI 重试 2/2 同错，实测否证）；**B 成功**（用户在场完整 GUI 生成 + 双复现验收 PASS）。完整记录见 §6；以下为当时的边界分析与决策原文。

- 现状（6.2.3）：参数注入可行、派生值正确，但 `generate_target` 因 `<comp>_adc.log` **先读后写**的前置顺序确定性失败（≥8 次同因；详见 §2.2-8），CLI 无 ADC-check 等价入口（`read_adc`/`read_ip_adc=USR-8321`，`CONFIG.PH1P_IO_ASSIGN` set 不触发 check）。
- **GUI bootstrap 选项（待用户决策，均未执行）**：
  - **A**：用户在场用 6.2.3 GUI 打开 r1/r2 工程（`D:\TD\work\csi2\_validation\td2026_20261016_214505\ddr1333_r1\ddr1333_proj.al`）对 IP 对话框应用一次 ADC（物化 `<comp>_adc.log`）→ 随后按 CLI `generate_target` 重试并复测；
  - **B**：全 GUI 生成（190248 包或新包）。
  - 执行前建议补一页 runbook（入口/预期/**停止条件**：GUI 打不开工程 / 应用后无 adc.log / CLI 仍败 → 停并转备用或原厂求证）。**GUI 步骤一律不计 headless 成功**；成功后仍须按 §4.1 原口径（两次独立复现、产物闭合、1333J/CL10/CWL7/666.7/70 引脚核对）验收后才冻结候选。
- 备选：向原厂求证 headless 的 ADC-check 等价入口（证据链已足以支撑询证）。

### 4.2 管理器怪癖与 `save_best_bits`

- `launch_runs/wait_run` 管理器历史缺陷（`PRJ-8806/8808/8818`）**本次在全新微型设计上间歇复现 1/4**（system 测试者两条独立 chain 中押中 1 次；命中窗口存在跨进程竞争可能，未定因）。关键判读规则：**`wait_run` 报错 ≠ 产物失败**——该次 worker 完整完成（run.log/fix_hold/export 全流程）、`place.db`/`pr.db` 可用、下游 `open_run`（PRJ-1408，内部 import_db）与 bitgen 均续行成功。生产脚本应结合 `run.log`/`flow.status`/DB 产物三件套判读，或失败时自动核对产物再决定；native 恢复路径 `s2n_native_route.tcl` 保持备选（本批两次 `not_run(not_needed)`，不冒充修复）。
- `save_best_bits`：6.2.2 与 6.2.3 均"调用被接受（无错误）、无 best_result 产物"（dev + 多名 tester 复现）；与外部 6.2.3 `build.tcl` 期望不完全等价——如实记录、不作验收/缺陷定论。

### 4.3 安装器 PATH/.al 副作用（已披露，影响低）

- 用户 PATH：新 bin `D:\anlogic\TD_Release_2026.2\bin\` **追加在旧 `D:\downlaod\bin\` 之后**（裸名解析仍先命中 6.2.2）；机器 PATH 未动。
- `.al`：新 ProgID `Anlogic.TD_Release_2026.2.al` 创建，且 **HKCR `.al` 默认关联已切换到新版本**（双击 .al 打开 2026.2 GUI）；旧 ProgID 保留、旧版仍可用绝对路径/右键打开。
- 其它：公共桌面快捷方式 `TD_Release_2026.2.lnk`；卸载注册项新旧并存（旧 `{2A7C3A75…}` InstallLocation=`D:\downlaod\` 未变）；`%APPDATA%\Anlogic\…\install` 提取残留 files=0（安装器自清）；VC redist/服务无变化。
- 纪律（已入 `docs/TD命令行使用说明.md` 与 `tools/td/README.md` 增补）：**双版本共存期一律绝对路径调用**；裸名示例（如 README 历史行 `td_commands_prompt.exe ./…`）不可照抄到 PATH 环境不同的机器。

### 4.4 "PH1P100 DDR3 800Mbps" 口径议题（未决，非本批动作）

- DS1300_PH1P_Datasheet_1.2.1 表 3-60 称 PH1P100 DDR3=800 Mbps（规划者本机 PDF95/印89 核实），与现役 002820=1600、09 例程 1600、板卡手册 800Mbps×32bit 存在三方差异；**与 TD 版本无关**，升级不改变口径，也不改变 DDR1333/1600 目标资格。列为 T01 决策材料（承接既有记录），需与 STA/板测数据一起定。

### 4.5 其它未决/边界

- IpTool **6.2.3 本体**的 headless 尝试未做（本批 DDR 走 Tcl IP flow）；`-tcl` 生成路在 6.2.2 已关闭，6.2.3 未重探。
- 残余 `#IP Generate Failed!` 子进程失败文本（6.2.2）与手改实例破坏 copy 取值的**具体编辑点**均未隔离（需调试器/ETW 或原厂支持）。
- `.setup.ini`（6.2.2 安装目录 21 B 窗口位置缓存）被工具自身改写——已逐次记录；两版本 IpTool.exe 及官方 depot 锚点全程未变。
- 6.2.3 与 6.2.2 的 scratch bit 差 4 B（**6.2.3 = 5,223,979 B 比 6.2.2 = 5,223,983 B 少 4 B**，头部字段差异；dev 证据/lessons 中该方向曾写反，数值正确，本报告与 README 已按磁盘实测更正）。
- 两版本 DB_VERSION 相同（46207）——引用升级表述时可用"双版本 DB 兼容"表述（tester 建议，有工具日志原文支撑）。

### 4.6 口径与记录观察（三维测试者逐条交办，本处归档）

| 来源 | 观察 | 处置 |
|---|---|---|
| A-eng §7-1 | 证据 JSON attempts 汇总表 `h6_probe/h7_probe` 缺 `output_files` 字段（磁盘 20/20 `result.json` 完整） | 口径注：以各 attempt `result.json`（SHA 锚定）为准，不改冻结证据 |
| A-func §3-1 | ledger `h2d_apppath.exit_code=null`（磁盘 result.json=1，600 s 超时杀进程后的转写）；duration 圆整 | 同上；无产物/窗口挂起/被杀事实一致，不影响结论 |
| A-func §3-2 | ledger 19/20 条 `argv=null`（argv 在各 result.json 内） | 引用一律指向 result.json；不改证据 |
| A-func §3-3 | h2h 对话框 PNG 未纳入证据 `dialog_sha256` 字段 | tester 补算 `30D8F93B65D1F7926F19F7C31AC44CF65F8466AB214CDF1A48B21583AEED78FF`，本处登记 |
| A-func §3-4 | 派发简报中 lessons 哈希前缀 `08cd3aa4` 与磁盘不符 | 磁盘（当时）`16BA6D1C…`（后含 tool-D 节更新为 `46875DAE…`）；判定不依赖该哈希，仅记录 |
| A-eng §7-4 / B | `tools/td/__pycache__/*.pyc`（语法检查副产品，75,497 B 等） | 标准 Python 缓存，未入任何 manifest；保留不纳入基线 |
| B-func §3-1 | `q3_help` 行 `collector_pass=true` 与 `expectation_met=false` 并存 | 证据 `analysis.limits` 已明示以 q3b 为准（记录口径），非缺陷 |
| B-sys §4 | PRJ-8806 间歇复现 1/4 与判读规则 | 已入 §4.2 与本报告；README/使用说明增补同条 |
| D-sys D1 | bit 4B 差方向曾写反 | 已按磁盘实测更正（§4.5 本条） |
| D-sys D2 | GUI A/B 缺显式停止条件/点击级步骤 | 已在 §4.1 记入建议 runbook 要求；用户选定后由开发出一页 runbook |
| D-sys D3 / D-eng ① | `.al` 默认关联切换未在证据 JSON 明示 | 已在 §4.3 明示 |
| D-eng ② | 证据 `recorded_at` 使用近似串（`23:2x/23:3x`） | 后续证据精确到分（不改旧证据） |
| D-eng ③ | 冻结套件注释仍写 `D:/downlaod/…`（常量已重定向） | 引用时勿混淆版本；修订注释属后续（须哈希登记） |
| D-eng ④ | "安装包哈希=官方页值"无法匿名复核 | §3.4 已按可证边界表述 |
| D-eng ⑤ | `td.exe` "同体二拷贝"措辞 | 已更正为"同尺寸、不同构建"（哈希不同） |
| D-func §3-1 | "8 次同因"计数口径 | 规范表述：**≥8 次（另有 2 次 `generate_target all` 形态仅 RC1、未取到文本）** |
| D-func §3-2 | `gui_probe_1.png` 实际内容=桌面+会话窗口（不含向导窗口） | 向导存在性仅由文本/子进程记录支撑（安装成功另有独立证据链）；引用时注明该内容边界 |
| D-func §3-3/3-4 | `load_project_ips` 同会话"already in use" ERROR 无害；未先 `load_project_ips` 的 `get_ips` 为空 | 已入 §2.2-6 备注；后续脚本姿势 |

## 5. 下一步与回退

> **2026-10-17 更新**：第 1 项 GUI bootstrap 已执行并收束（A 否证、B 成功、双复现 PASS，见 §6）；第 2–4 项纪律与回退继续有效。

1. **下一步（唯一解锁路径，待用户）**：GUI bootstrap —— 选项 **A**（6.2.3 GUI 应用一次 ADC → CLI 重试）或 **B**（全 GUI 生成；**B 若走 190248 包**：launcher 仍为文件形态 `-user …/ddrmc_x32.xml -gen …/Component.xml`，与 6.2.2 教训 #1 的目录契约不一致，使用前须先目录化或先验证 GUI 交互入口是否受该约束）。成功后按 §4.1/§4.4 原口径验收、冻结新候选；**GUI 步骤不计 headless 成功**。
2. **190248 后备（6.2.2）**：包完整（197/197，manifest `A94F8948…`；launcher/guard/retention/input_pins.adc 均在位）；`manual_kit_preflight.json` 记录 `visible_gui_launched=false / generated_ip=false`——保持原样冻结，不预先改动。
3. **新锚点与工具纪律**：双版本并存（6.2.2=`D:\downlaod` 冻结；6.2.3=`D:\anlogic\TD_Release_2026.2` 新锚点已登记）；**新候选全链同版本**（IP→综合→route→STA→bit 不跨版本拼接）；**旧证据不迁移**（A/B 证据与结论继续绑定 6.2.2；新证据绑定 6.2.3）；脚本一律绝对路径；冻结工程只开副本；不批量删除（逐文件）；不下硬件/不 Flash。
4. **回退**：6.2.2 工具链与全部冻结锚点未动、可继续既有流程；新装可整体弃用（卸载项已登记）；一切失败现场保留（含缺 license 的 `td_cli_td2026_1`）；190248 与 002820 原样。

## 6. GUI 应用与 CLI 重试结果（2026-10-17 落成；原 pending 小节）

> 本节由 2026-10-16 版 pending 小节升格而成；全部结论绑定证据文件 + 磁盘重算 SHA。**机制定位：DDR1333 IP 的产出方式为「CLI 引导配方（create + 全参数注入）+ 用户在场一次 GUI Generate」——GUI 步骤不计入 headless 成功；全自动 headless 生成仍不成立。**

### 6.1 方案 A：前提不成立（实测否证）

- 引导包：`D:\TD\work\csi2\_validation\td2026_gui_bootstrap_20261017_000935`（CLI create + 27 参数注入完成、停在 generate 前；`.params` 复核 1333.00/1333J/CL10/CWL7/tCK1500/ACTUAL666.7；`pre_gui_manifest.json` 14 文件冻结）。证据：`docs/evidence/td2026_gui_bootstrap_20261017.json`（SHA `741E909D…EE0457`，6,919 B）。
- 用户执行 GUI OK/应用（会话约 00:57–01:04）：`log/ipgen.log` 显示 ADC check 正确运行（banks 4/5、ac{5 1..3}、dx{4 0..3}，与 golden ADC 一致），但 **`ddrmc_x32_adc.log` 未在根级/staging/全树任何位置物化**（staging 目录被 GUI 流程清理删除）。
- post-GUI CLI `generate_target` 重试 2/2 同错：`IPT-1002 … couldn't open "<staging>/ddrmc_x32_adc.log"`（5.8/5.9 s、exit0 外壳 + RC1）；`SYSCLK_LOC=H4` 仍 range 空。
- **判据与结论**：`<comp>_adc.log` 是**完整生成步骤的产物**（002820 proc.log "generate adc file success" 同族），不是 OK/apply 步骤的产物——工具侧"先读后写"断点无 CLI 等价入口。**方案 A 前提 REFUTED（已实测）**，不记作 headless 成功。证据：`docs/evidence/td2026_ddr1333_generate_20261017.json`（SHA `1B5CE403…F9A63771`，8,725 B）。

### 6.2 方案 B：用户在场 GUI 完整生成成功（§4.1 成功分支一次全过）

- 会话（14:21–14:23）：IP 对话框 OK → **打开** IP Generating Options（Binary Path=`D:/anlogic/TD_Release_2026.2/bin/td.exe`、Synthesis=Behavior、Export to=`<bootstrap>/ip_out`）→ Generate；完成标记 `#GUI-2000 … generated successfully` + `#IP Gen Succeeded`；proc.log 12 步全 success；drc_check.log 全文 PASS（"the design rule check pass!"）。
- 产物闭合（64 文件 / 765,835 B；磁盘复核 64/64）：`ddrmc_x32/`（.params/.m_params/.ports/xml/Design/DesignConfiguration + 双 wrapper）+ `src/{rtl 全树, adc, sdc}` + `sim/fileset` + 根级 `ddrmc_x32_adc.log` 5,988 B `C50695DF…`、`ddrmc_x32_drc_check.log` 489 B `75721975…`、`ddrmc_x32_proc.log` 391 B `9C1CDF4B…`。
- 参数/派生/引脚全 PASS：1333.00 / DDR3-1333J / CWL7 / 派生 CL10 / tCK1500 ps / SYSCLK_LOC=H4 / PLL_LOC=BANK33 / IO1.35 / x16 / 2048 / REF50；物理 CK = 50×80/3/2 = 666.6667 MHz ≤ 666.667；**70 引脚与 golden 逐项一致**（唯一排除 golden 未用 `ddr_addr[14]=J5`，符合 ADR_WIDTH=14；0 多余）；ADC 指向本地 `input_pins.adc` `F0904238…`。
- 候选冻结：`candidate_manifest.json`（64 文件全清单+SHA）SHA `D71057F3…C08434`（17,708 B）；引脚比对 `accept_pincompare_result.json` SHA `0964C4CB…F8806`。证据：`docs/evidence/td2026_ddr1333_accept_20261017.json`（SHA `B85A2405…80F544E`，10,809 B，含 `second_reproduction_update`）。

### 6.3 第二次独立复现（run2）：裁定 PASS

- run2 全新目录 `D:\TD\work\csi2\_validation\td2026_b_run2_20261017_143128`：同冻结配方（CLI create + 全参数注入）+ 用户在场**再一次** GUI Generate；完成标记齐备（`#IP Gen Succeeded`/`#GUI-2000`；`log/ipgen.log` `D2DA8684…`）；闭包 64 文件（磁盘复核 64/64）；三日志与 run1 **逐字节相同**（adc.log `C50695DF…`、drc `75721975…`、proc `9C1CDF4B…`）。
- 全量比对：64 文件中 **60 逐字节一致**（含全部 RTL、src/adc、src/sdc、双 wrapper、.m_params、.ports、DesignConfiguration.xml 与三日志）；4 个差异文件经字段级归一**严格证明非实质**——`.params`/`Design.xml`＝仅各自 run 目录的 `input_pins.adc` 路径串（ADC 同内容 `F0904238…`）；`ddrmc_x32.v`＝仅 Gen time 时间戳；`ddrmc_x32.xml`＝仅 XML 属性次序（语义 diff=0）。
- 裁定：**两次独立复现成立（PASS）**。比对工件：`run1_run2_diff_report.json` SHA `579BE12A…E3C8CB`（12,252 B）；`semantic_diff_result.json` SHA `9B30DF65…C6C15EF`（390 B）；run2 manifest `run2_candidate_manifest.json` SHA `9B3E5D00…D09D716`（64 文件，11,027 B）；run2 引脚 `run2_pincompare_result.json` SHA `27C375C7…F5E6DC`（70/70）。证据：`docs/evidence/td2026_b_run2_20261017.json`（SHA `A60F2166…080D87FD`，7,407 B，status=complete）。

### 6.4 CLI 复现路径的结构性限制（如实记录）

- CLI 携带法尝试（R3 新目录 `td2026_ddr1333_r3_cli_142716`）：把真实生成的 adc.log（`C50695DF…`，5,988 B）预置到预期 staging 路径后 CLI `generate_target` 仍同错——该文件在**会话加载阶段即被工具清除**（会话内检查 `STAGING_ADC_EXISTS:0`），staging 随后回滚。
- 结论：**CLI 路径不可复现（结构性）**——"先读后写"时序在 6.2.3.210850 无法经外部预置绕过；每次独立复现的最小单元＝CLI 冻结配方 + 一次用户在场 GUI Generate。单次 GUI 生成**不**记为两次复现，**不**记为 headless 成功；剩余全自动路径＝原厂询证/后续版本修复（备选，未实施）。

### 6.5 冻结候选与 T01 下一步入口

- **推荐冻结候选（run1）**：`D:\TD\work\csi2\_validation\td2026_gui_bootstrap_20261017_000935\ip_out`（manifest `candidate_manifest.json` `D71057F3…`，64 文件）；**run2 为等价镜像**（`D:\TD\work\csi2\_validation\td2026_b_run2_20261017_143128\ip_out`，`9B3E5D00…`）。
- 集成输入＝64 文件闭包 + 该目录工程 boot 文件（`ddr1333_proj_boot.al`；`.params`/`Design.xml` 中 `PH1P_IO_ASSIGN` 指向各自 run 目录的 `input_pins.adc`，而 `src/adc/ddrmc_x32.adc` 已本地化、自包含）。
- **边界（如实标注）**：下游集成/综合/route/STA/bit/CWC 与板验（G3/G4）**不在本 run 范围**——本 run 无 bit、无下板、无任何硬件动作；GUI 会话已全部关闭（td.exe 残留 0）。
- 已向任务板同步：T01 `blocked`→`active`（DDR1333 IP 生成入口阻塞已解除；剩余＝集成/时序/颜色板验等待办）。

### 6.6 纪律与设备状态收尾（复核通过）

- `D:\downlaod` 三锚点未变、无批量删除、无硬件动作；`D:\anlogic` 新写入仅工具自身 `bin\.setup.ini`（21 B 窗口缓存，非破坏性，已逐次记录）。
- GUI 期间新写文件（`.lock.f`/`run.bat`/`multirun_script.tcl`/`log/*`；`.al` 增 IP_FILE 与 syn_1/phy_1 runs）均已登记于证据；GUI 生成的 `multirun_script.tcl` 的 import_device 行为空（残缺脚本、未产出构建物）——GUI quirk 观察，见 generate 证据 limits。

## 7. G 层与证据索引

**G 层记录（本批，规划事先确定）**：

| 任务 | G0/G1 | G2（生产候选） | scratch G2-lite | G3/G4 | 硬件 |
|---|---|---|---|---|---|
| T01.tool-A | pass | not_run（无产物/无候选） | — | not_applicable | not_applicable |
| T01.tool-B | pass | not_applicable（不产候选） | pass（0→bit 证命令） | not_applicable | not_applicable |
| T01.tool-D | pass（G1+执行证据） | not_achieved/not_applicable（候选未冻结） | pass（smoke + 回归 0→bit） | not_applicable | not_applicable |

**证据与锚点索引**（SHA256 均为 2026-10-16 磁盘重算；`…` = 中间省略）：

| 类别 | 路径 | SHA256 / 说明 |
|---|---|---|
| A 证据 | `docs/evidence/ddr1333_iptool_cli_20261016.json` | `078B5AC32221522146A83245C7ECBAA4F0836F83AFD719EAE99AE54B3356CCF7`（42,808 B） |
| B 证据 | `docs/evidence/td_cli_commands_20261016.json` | `6F648F0F048300931A612AB79D7288AD6C41BFD78B3F0CCA376BB75955E2544E`（100,000 B） |
| D 安装证据 | `docs/evidence/td2026_install_20261016.json` | `EF5545CC08C6B94DAC0421A93DF50561BC93CFB4B5EF5FB708B380233A825D37`（8,384 B） |
| D 生成/回归证据 | `docs/evidence/td2026_ipgen_20261016.json` | `A9D0B9B09DFD2FA2EC5119A61C3DE0538B9B9074DA2F54C49BAC231F05D4C8A1`（15,855 B） |
| D 回归汇总 | `D:\TD\work\csi2\_validation\td2026_20261016_214505\cli_regress\td2026_regress_evidence.json` | `ADCC42F583DAEF7E63A5B3ABDB3F7040B3435087EEDEA8F3AD70E5B638FD1531`（59,238 B） |
| 脚本（修改） | `tools/td/prepare_ddr1333_ip.py` | `2D345898…D00F20F`（14,468 B） |
| 脚本（新增） | `tools/td/run_ddr1333_ipgen.py` | `B44E065C…57862B7D`（48,089 B） |
| 脚本（新增） | `tools/td/verify_cli_e2e.py` / `.tcl` | `D59D349F…31D8F139B`（21,703 B）/ `440785F3…92E1AFA0C4`（1,246 B） |
| 脚本（基线，未改） | `tools/td/verify_cli.tcl` | `B3269486…35BB22F2`（422 B） |
| bit（6.2.2 B） | `…\td_cli_20261016_205203\td_cli_e2e_counter.bit` | `1816AFF8…8E939115`（5,223,983 B；未下载） |
| bit（6.2.3 dev / tester） | `…\td2026_20261016_214505\cli_regress\td_cli_td2026_2\…bit` / `…\td2026_tester_system_20261016_233123\runs\td_cli_tester_sys1\…bit` | `CFE81199…A4048CFC` / `B6276241…F7791B9`（各 5,223,979 B；未下载） |
| 6.2.2 工具 | `D:\downlaod\bin\{td_commands_prompt,IpTool,td}.exe` | `79EC5667…87190` / `DA9E765E…A3DE46` / `B7129888…DA2AFA` |
| 6.2.3 工具 | `D:\anlogic\TD_Release_2026.2\bin\{td_commands_prompt,td,IpTool,bw}.exe` | `2629E474…C1223` / `FA2A5AC6…06A87` / `5B0654AA…75CEC` / `89501B2D…22008` |
| depot/DB/license | `…\arch\ph1_100p.db`、`…\ip\depot\MIS_DDRF6F1D0P0_1.2\{Component.xml,Dependency.tcl}`、`license\Anlogic.lic` | 6.2.2 `8E7E8812…`/`FEB4F5BC…`/`CD927834…`；6.2.3 `939EC294…`/`3E854A26…`/`51C2311F…`；license 同 `DC19FEE6…` |
| 安装包 | `C:\Users\czz\Downloads\TD_Release_2026.2_NL.exe` | `3B92ABE8…751A0A`（1,969,702,400 B） |
| 冻结包/工程 | 190248 `preparation_manifest.json` / 002820 `input_manifest.json` / golden ADC | `A94F8948…79BD64`（197 项）/ `8F8E4EFE…F9A1C8` / `F0904238…DB33DA` |
| 10-15 证据 | `docs/evidence/ddr1333_ip_retry_20261015.json` / `ddr1333_ip_regeneration_20261015.json` | `B50E3EB0…49E6AD` / `4A3400D4…FC16F079` |
| run 材料 | `upgrade-review.md` / `dev-plan.md` / `input-index.md` / `requirement.md` / `fpga-design-guide.md` / `main-log.md` / `dev-notes-td2026.md` / `lessons-learned.md`（C 追加前） | `C8E1FFC4…96BE6BA3` / `FE66E22E…976C50D8` / `03EA920A…36330AE` / `E163CAF2…90471F` / `475F85B2…82B96` / `44625B63…08DFE7` / `9607740F…D0506` / `46875DAE…DA989` |
| 测试报告 | `test-reports/T01.tool-{A,B,D}-r0-{functional,engineering,system}.md`（9 份，均 PASS） | 路径引用；细节见各报告 |
| 2026-10-17 追加证据 | `docs/evidence/td2026_gui_bootstrap_20261017.json` / `td2026_ddr1333_generate_20261017.json` / `td2026_ddr1333_accept_20261017.json` / `td2026_b_run2_20261017.json` | `741E909D…`（6,919 B）/ `1B5CE403…`（8,725 B）/ `B85A2405…`（10,809 B）/ `A60F2166…`（7,407 B） |
| 2026-10-17 候选与比对 | run1 `…\td2026_gui_bootstrap_20261017_000935\ip_out`（`candidate_manifest.json`）/ run2 `…\td2026_b_run2_20261017_143128`（`run2_candidate_manifest.json`）；`run1_run2_diff_report.json` / `semantic_diff_result.json` | `D71057F3…C08434`（64 文件）/ `9B3E5D00…D09D716`（64 文件）；`579BE12A…E3C8CB` / `9B30DF65…C6C15EF` |

（本报告由 fpga-dev 于 2026-10-16 撰写；2026-10-17 完成 §6 落成、双复现记录与 T01 状态同步；未修改任何冻结文件。）
