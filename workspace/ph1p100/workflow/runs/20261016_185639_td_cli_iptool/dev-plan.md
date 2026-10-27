# dev-plan — TD CLI IpTool 修缮与验证（run 20261016_185639_td_cli_iptool）

规划日期：2026-10-16。规划者已独立核实 requirement.md 侦察注记与 D 盘现场（见 input-index.md「核实结论」）；本计划不照抄注记，差异之处以核实为准。

## 0. 交付映射与批建议

| 用户交付 | 工作包 | 建议批次 |
|---|---|---|
| 1. 修缮 TD CLI 中 IpTool 设置问题并实际跑通 | T01.tool-A | 批1 |
| 3. 其他 TD CLI 控制命令核验（open_project/import_device/launch_runs/wait_run/report_timing_summary，可行含 bitgen） | T01.tool-B | 批2 |
| 2. 报告（docs 报告 + 证据）与必要文档/任务板同步 | T01.tool-C | 批5（依赖 A、B 实测结果 + 升级审核/决策与 tool-D 结论） |
| 1（续）. 用户决策（2026-10-16）：升级 TD 2026.2（并行安装），先验证 headless 生成；仍不行则转 GUI | T01.tool-D | 批4（awaiting_user_installer：等用户提供 6.2.3.210850 安装包；见 §4.4） |

- 默认 BATCH_SIZE=1；A 与 B 互不依赖、写路径不相交；C 必须在 A、B 有实测结果后单独进行，不得先写结论。
- T01.tool-C 的范围将纳入升级审核/决策（`upgrade-review.md`）与 T01.tool-D 结果；按用户 2026-10-16 决策，**C 排至升级尝试出结论后执行**（不因此回溯修改已完成的 A/B 结论与既有测试报告）。
- A、B 均在 D 盘 ASCII 目录做真实工具执行（TD/TD CLI 不能处理中文路径）；仓库只放脚本与证据索引。
- 每包完成后按工作流派功能/工程/系统三个测试者；同批修正由原角色续接，最多三轮。

## 1. 独立核实要点（与侦察注记的差异；细节见 input-index.md）

1. `IpTool.exe`（SHA256 `DA9E765E…A3DE46`，19,382,784 B，与 10-15 文档一致）usage 字符串真实存在，但注记里的排版是转写版：实际 usage 先列 catalog 形态，再列 `-gen`/`-user` 形态与 `-complete` 形态；`-tcl`、`-source`、`-nogui`、`-no_status`、`-qcerr` 等是独立选项串。**没有**任何官方文档（IPUG034 53 页、SWUG105 109 页、TD_User_Guide）记载 IpTool 的 headless 生成用法——IPUG034 只写 GUI 定制流程，SWUG105 只写实现流 Tcl 批处理；自动生成属未文档化探索，必须实验证伪/证实。
2. 2026-10-15 证据（`ddr1333_ip_retry_20261015.json`、两份 DDR1333 文档）核实无误：`-tcl -source` 诊断入口可用并取得命令帮助（含 `create_dialog`）；copy 生成加 `-tcl` 后自然 exit 1、零输出零产物；`-qcerr` 20s 超时；更早两次（不带 `-tcl`）30/45s 超时。**结论未变：完整自动生成入口未确认。**
3. 二进制字符串证据补充（规划者核实）：IpTool 注册命令串含 `generate_ipinst`（10-15 诊断在未开库上下文未见其激活——可在 `open_iplib` 后重探，属候选假设）；另有 `xmlgenip`、`generate_gate`、`_commands_prompt .exe`/`runTclTask`/`plugin_end.tcl` 等串；`create_dialog` 帮助文本明示"创建设置对话框然后生成"（GUI 语义）。TD CLI 内 `xmlipgen` 命令在工程上下文真实存在（`tmp/probe_project_ip_cli.log`），但 `-help` 无可用帮助（10-10 已记录），不可据名字推测可用。
4. 两份 `ipgen.log` 参考均为 **GUI 动作记录**（`ipgen_gui_*` 直至 `#IP Gen Succeeded`），不是 headless CLI 成功证据；输出为 al_ip 路径及历史 `F:/al_data` 路径。
5. TD CLI 现状：`verify_cli.tcl` 六命令注册检查 2026-10-10 通过；近期六个 native 阶段（002820，含 bitgen）均经 `td_commands_prompt.exe ./xxx.tcl` 真实执行并 accepted——但这些命令尚无一份"逐命令端到端核验"的专门证据，且存在已知quirk（脚本加载失败也可能 exit 0；需显式标记；launch_runs 管理器历史上有 exit1/PRJ-88xx 而 worker 完成的情况；002820 的 route 曾绕过管理器用 native import_db 路径）。B 包需把这些变成逐命令的实测结论。
6. 官方依据路径均存在（核实）：`D:\downlaod\Doc\IPUG\IPUG034_PH1P_MIS_IP_Guide.pdf`（IPUG034 v1.4，53 页）、`D:\downlaod\Doc\SWUG\SWUG105_TCL_Command_User_Guide.pdf`（SWUG105，2026.01，109 页）、`D:\downlaod\Doc\TD_User_Guide_V6.2.pdf`。
7. 现场常量核实（锚点哈希见 fpga-design-guide.md）：002820 冻结基线 `input_manifest.json` SHA=`8F8E4EFE…F9A1C8` 与准备脚本断言一致；`_validation` 下已存在 100+ 既有目录（全新目录规则必要）；MIS 私有 depot 与 golden ADC 就位。

## 2. 受控实验边界（本批全部工作包适用，越界即停）

- **每次工具尝试使用全新独立目录**：`D:\TD\work\csi2\_validation\ddr1333_cli_<YYYYMMDD_HHMMSS>[_序号]\`（或 `td_cli_<ts>\`），以 `mkdir(exist_ok=False)` 创建；**绝不**复用或写入任何既有目录（含 `ddr1333_ip_20261015_165740/185206/190248`、`iptool_retry_20261015_183510`、`iptool_help_20261015`）。每次尝试从冻结输入重新复制并逐文件验 SHA。
- **每次执行必须记录**：完整 argv、cwd、pid、start/end、timeout、exit_code、timed_out、stdout/stderr 全文文件及 SHA、产物清单（相对路径+字节数+SHA256）、输入 before/after SHA、子进程/窗口观察、以及工具是否在实验目录之外写入（按 mtime 扫描并在证据中如实报告）。
- **超时上限**：探查类 ≤120s；IpTool 生成类单次 ≤900s；TD 构建类按 §4 各包。超时必须真实 kill 进程树并记 `timed_out:true`。
- **单变量原则**：每个变体只改一个可解释变量；每假设连续失败 3 次即切换或停止；IpTool 生成类总尝试 ≤10 次。
- **负对照必须实测**：如错误 comp 名/错误 user 路径/不存在的工程名，证明收集器能捕获失败（exit 码 + 错误串 + 零产物），不接受推定。
- **禁止**：修改 `D:\downlaod`（bin/depot/Doc 全禁）；覆盖任何既有目录或冻结工程（`D:\TD\work\csi2\prj\**`，明确含 002820）；批量删除（逐文件规则，能不删就不删；vendor 清理一律走保留式机制）；硬件下载/Flash/写板；把 GUI 人工步骤或字符串推断写成"headless 跑通"。
- **中文路径禁令**：一切 TD/TD CLI/IpTool 执行均在 D 盘 ASCII 目录且 cwd=该目录；不从仓库中文路径运行真实构建（10-10 教训：从仓库目录 open_project 触发相对路径解析错误并改动了 .al，后经恢复）。
- **打开既有工程前必须先整目录复制到新目录**（open_project/close_project 会改写 `.al` 等工程状态）；冻结工程一律只读引用，不直接 open。
- **生成 IP 只作为新候选**：未经核验不得替换任何冻结工程/bit；不得手工改生成 RTL/PLL 掩盖派生值；准备输入目录不可当可编译产物。
- **保留式清理**：不得运行安装目录的默认生成器（会递归删输出 `Other`/`RTL`）；仅对私有副本使用既有 `retain_ip_path` 机制。

## 3. 工作包最小表

| task_id | 问题/产物 | 允许写路径（越界即停） | 依赖 | functional 验收 | engineering 验收 | system 验收 | 必要 G 层 | 状态 | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|
| T01.tool-A | IpTool/TD CLI DDR1333 生成入口修复与真实跑通（或经证实边界） | 改 `tools/td/prepare_ddr1333_ip.py`；新增至多 1 个 `tools/td/run_ddr1333_ipgen*.py`；新建 `D:\TD\work\csi2\_validation\ddr1333_cli_*\`；新建 `docs/evidence/ddr1333_iptool_cli_<date>.json` | 无 | 见 §4.1；二分支：完整 headless 生成跑通（两次独立复现+参数全对）或边界经受控实验证实 | 全程记录+输入/安装目录不变+全新目录+保留式清理；单变量、负对照、超时证据 | 入口可从仓库脚本调用、候选为独立新包不碰冻结工程、T01 后续集成入口明确 | G1 参数/文件一致性 + 执行证据；候选 G2/G3/G4 not_run | ✅ round0 三维 PASS（test-reports/T01.tool-A-r0-*.md） | 无（等待 C 汇总） |
| T01.tool-B | TD CLI 其他控制命令端到端核验（六命令） | 新增 ≤2 个 `tools/td/verify_cli_e2e.{py,tcl}`；新建 `D:\TD\work\csi2\_validation\td_cli_<ts>\`；新建 `docs/evidence/td_cli_commands_<date>.json` | 无 | 六命令逐条：真实执行+显式标记+非空产物；失败者有可复现错误证据 | exit/标记/产物/哈希三件套；负对照证明退出码不可单证；冻结工程零写入 | 从 scratch 工程 0→bit 全链路（bitgen 可行则含）；已知quirk记录；对生产流程的影响评估 | G1（harness/标记语义）+ scratch G2-lite（仅证命令，不构成任何生产候选 G2）；G3/G4 N/A | ✅ round0 三维 PASS（test-reports/T01.tool-B-r0-*.md） | 无（等待 C 汇总） |
| T01.tool-C | 报告与同步（docs 报告+证据+README+任务板） | 新建 `docs/TD_CLI_IpTool修缮与验证_<date>.md`；改 `tools/td/README.md`、`docs/TD命令行使用说明.md`（增补不删旧）、`workflow/tasks.json`（仅 T01） | A、B 实测结果（两者均出证据后）**及升级审核/决策与 tool-D 结论** | 报告覆盖根因/修复/逐项验证/边界/未决项，每条结论可溯源到证据文件+哈希 | 路径/SHA/工具版本准确；tasks.json 为合法 JSON 且仅动 T01 | 下一入口可用：T01 状态刷新、人工包方向明确、无虚假"完成"结论 | G0/G1；硬件层 N/A | ✅ r0+r1 全三维 PASS（r1 增量：test-reports/T01.tool-C-r1-*.md） | 无（已关闭；§6 已落成） |
| T01.tool-D | TD 2026.2（≥6.2.3）并行安装与 headless 生成验证（用户决策；安装包由用户提供） | 新安装目录（安装前与主调度确认）；新建 `D:\TD\work\csi2\_validation\td2026_*\`；`docs/evidence/` 新 JSON（`td2026_*`）；`tools/td/` 新 runner（如有，不得削弱既有断言） | ①用户提供安装包（目标 6.2.3.210850；官方若无此版另行提请决定）；②安装目录/license 方式安装前确认 | 见 §4.4：命令族实测 + 四步最小验证；headless DDR1333 成功分支沿用 §4.1 同口径（两次复现/产物闭合/参数与 70 引脚核对）；失败按用户指令转 GUI 后备（不计 headless 成功） | 新锚点（SHA/Tcl/DB_VERSION）登记、旧锚点不动；全新目录；不批量删除；`D:\downlaod` 不被覆盖/改写 | 新版本 scratch 六命令回归；新候选全链同版本；GUI 后备入口明确 | G1+执行证据（新候选 G2 视集成结论）；G3/G4 N/A | ✅ r0+r1 全三维 PASS（r1：B-run2 双复现裁定；test-reports/T01.tool-D-r1-*.md） | 无（已关闭） |

## 4. 各工作包详情

### 4.1 T01.tool-A — DDR1333 生成入口修复与真实跑通

背景：T01 阻塞点即本包。输入冻结件已就绪（197 项 SHA 的 190248 私有包：私有 depot 副本+保留式清理+引脚表+绑定 guard），可直接复用其**只读内容**作为新尝试的输入来源；本包目标是让生成入口可复现工作，或给出经证实的边界。生成成功后产物仅为**新候选**，集成/综合/STA 属 T01 后续（不在本包）。

受控实验候选假设（逐条单变量实测；顺序可按成本调整，但每条必须真实执行或给出不执行理由）：

- H1（usage 文档形态，10-15 未测过）：`IpTool.exe D:/downlaod -gen <私有depot的Component.xml> -device PH1P100SBG484 -export_to <新output> -comp <新名> -use_value default`（不带 `-user`/`-tcl`）。先用 default 证"工具是否具备 headless 生成能力"，产物参数对错暂不判（但全部记录）。
- H2（copy/适配形态）：`-user <适配后实例 xml> -gen <Component.xml> -device … -export_to … -comp ddrmc_1333 -use_value copy`（不带 `-tcl`，即 10-15 出现 45s 超时的形态）＋单变量变体：`-no_status`、`-nogui`、`-batch`、`-gen` 指向不同路径形态。必须回答：阻塞是隐藏对话框、路径解析还是其它（在进程存活/窗口/输出上取证）。
- H3（`-tcl -source` 驱动内部命令，已证入口可用）：脚本先 `puts [info commands]`，对 `generate_ipinst`/`create_dialog` 取 `help`；尝试 `open_iplib -path <私有库>`、`import_ip`、`find_ip` 等后再查 `generate_ipinst` 是否激活；若存在非 GUI 生成命令则构造生成脚本。若唯一入口为 `create_dialog`（帮助文本即"对话框然后生成"），该假设结论为 GUI 依赖，需窗口证据支持。
- H4（TD CLI `xmlipgen`，工程上下文）：在**新建 scratch 工程**（import_device+create_project）内实测 `xmlipgen` 参数行为（`-h`/`-help` 已知无效，不可据名字宣称可用；只记录实测）。注意它与 IpTool 内部 `xmlgenip` 串的关系只是线索，不是事实。
- H5（GUI 边界取证／人工包路径）：仅当 H1–H4 均无 headless 生成时执行：以新建私有副本尝试启动 190248 同款 launcher；如实记录窗口是否出现（无用户在场时窗口证据须为客观记录，如可枚举窗口/进程状态），**不得**把"GUI 打开过"写成"生成跑通"；同时保留/更新人工包说明作为下一步。

生成成功分支的完整验收（"必须实测通过"）：
- 两次独立运行（两个全新目录、同一冻结输入）均出现工具完成证据（如 `#IP Gen Succeeded` 等价标记或 exit 0+完整产物；若两者冲突以产物完整性为准并记录）；
- 产物闭合：Design.xml、DesignConfiguration.xml、`<comp>.xml`、`.params_*`、`.ports_*`、wrapper、`src/rtl`、`src/adc`、`src/sdc`、DRC/ADC 日志齐备且非空；两次运行的核心文件逐字节一致（存在时间戳类差异须逐字段列出并证明仅时间字段）；
- 参数与引脚核对全部通过：`PH1P_DDR_SPEED=1333.00`、`PH1P_SPEED_BIN=DDR3-1333J`、CWL=7、派生 CL=10、实际 PLL 物理 CK ≤ 666.667 MHz（tCK≥1.5ns，按生成文件实际分频计算）、70 个 DDR 引脚与 `ap115v2_ddr3_x32.adc` 逐项一致、ADC 指向私有 input_pins.adc；任一项不符即拒绝，不算跑通；不得手改生成 RTL 掩盖。
- 生成候选冻结：候选目录内写入文件清单+SHA（manifest），作为 T01 后续集成的输入；不改任何冻结工程/bit，不生成 bit，不下板。

边界分支的完整验收（"如实记录边界"，不得放宽）：
- attempts 表完整（每条 argv/exit/timeout/输出/产物/SHA/单变量说明）；`-tcl -source` 正对照通过；失败可复现（≥2 次）或超时可复现；
- 若判 GUI 依赖：提供客观证据（如：进程在无交互下挂起至超时且零产物 + 进程状态/窗口句柄记录；或生成唯一命令帮助文本为对话框语义），并给出下一步选项（用户在场时的人工生成路径、或向原厂/文档求证）；
- 脚本侧"修缮"仍须交付：修正 `prepare_ddr1333_ip.py`（或新 runner）使其记录真实 entry 状态（不再自标 inferred）、参数化实验 argv、保留全部断言与保留式清理；相关使用说明写入 WP-C 报告；
- 报告与任务板不得写"生成入口已在 CLI 跑通"；T01 维持 blocked/awaiting 相应状态。

允许写路径（精确）：`tools/td/prepare_ddr1333_ip.py`（修改）；`tools/td/` 下至多 1 个新增 runner 脚本；新建 `D:\TD\work\csi2\_validation\ddr1333_cli_*` 目录（只新建）；新建 `docs/evidence/ddr1333_iptool_cli_<YYYYMMDD>.json`。其余一切只读。
停止条件：H1–H5 全部有结论；或总尝试达 10 次；或单假设连续 3 次同因失败 → 切换/停止并转边界记录。时间上限：单次生成尝试 ≤900s，本包 ≤1 个工作日（约 6h 净执行），超限即收束出结论。
回退：190248 人工包保持原样可用；任何失败现场保留，不删除、不重跑覆盖。

#### §4.1 增量假设 H6+（用户外部输入，2026-10-16；规划者已核实）

背景（细节见 input-index「外部参考仓库评估」）：用户给出的两个仓库（fpga HEAD `654ef176…`、driver HEAD `ad350ca4…`）为同一块 MLK-F9P（PH1P100SBG484）的姊妹工程（PCIe EP+IMX415+DDR3，TD 6.2.3/Linux）。其历史文档记录了我们同类问题的完整经验：MIS DDR IP 生成失败根因是实例 `PH1P_IO_ASSIGN`（ADC 引脚约束）为空 → `gen_adc.tcl` 的 `open $adc_file r` 抛错 → 生成失败（与我们 `#IP Generate Failed!` 同族）；其成功链路依赖 TD 6.2.3 的 Tcl IP flow（`create_ip/load_project_ips/get_ips/set_property <值> <名> <对象>/generate_target`），最终交付仍走 GUI（点击清单与我们的 190248 包高度一致，同一份 `ap115v2_ddr3_x32.adc`）。规划者只读探针已实测：**本机 TD 6.2.2.200067 未注册** `create_ip/get_ipdefs/get_ips/generate_target/generate_ipinst/load_project_ips/close_project_ips/report_ip_status/ip_upgrade`；**已注册** `set_property/get_property/create_syn_ip/xmlipgen/ipgen_synip/print_ip_config/read_ip_adc/export_ip_lib/set_ip_property/set_ippin_assignment/save_best_bits/reset_runs`。⇒ 外部配方不能原样移植；以下假设用于把「外部经验」在我们环境可证伪地检验。

预算与约束：本增量批新增尝试**合计 ≤6 次**（用户授权额度；原 14 次已触顶）；每次全新独立目录（`mkdir(exist_ok=False)`）、单次超时 ≤900s、单变量、完整 argv/exit/stdout/stderr/产物/SHA 记录；§2 全部红线与记录义务不变（不改 `D:\downlaod`、不覆盖既有目录/冻结工程、不批量删除、不下载、不把外部材料/推断当实测；**不执行外部仓库任何脚本**，其内容仅为参考材料）。GUI 路径与 190248 包不在本轮尝试内。

- **H6（1 次，只读探针）本机命令集缺口定案**：在全新 ASCII 目录运行探针 Tcl（`info commands` 覆盖上述命令族；对已注册命令取 `help`/`-h` 文本），输出原文留档（新 `_validation\td_ipa_<ts>\` 或 temp；不打开工程、不写工程）。判据：present/absent 清单+help 文本入证据；与规划者探针一致时定案“6.2.2 无 Tcl IP flow 命令族”。若意外发现命令存在，则转 H7 实测。
- **H7（≤2 次，条件于 H6 或帮助文本发现可用入口）6.2.2 侧 IP 参数/生成入口语义探测**：对 `set_ip_property/print_ip_config/read_ip_adc/xmlipgen/create_syn_ip/ipgen_synip` 做 help+最小受控调用（一律在新建目录/副本上），确定是否存在“给 IP 实例设参数并生成”的可用入口。若找到→按 §4.1 原验收（两次独立复现+参数/引脚核对）单变量实测；若确认无→记录 help 证据并关闭该线。
- **H8（1 次）一致源实例对照**（外部“用 GUI 生成过的实例做复制源”主张与我们 lesson #9 的交叉验证）：以**未手改、工具自产**的实例（002820 `vendor/ip/ddrmc_x32` 的只读副本）作 `-user` 源，复用本批已定型修正形态（双目录+`-no_status`+`-app_path`，全新目录，新实例名）。单变量=源实例一致性（其余 argv 与 h2f/h2g 相同）。判据：出现完整产物（`_proc.log` 12 步 success / DRC PASS / 文件数≥60）为“源一致性是根因”的强证据；相同 `#IP Generate Failed!` 为否证。**即使成功也不等于 1333 可交付**（值注入仍缺入口）。
- **H9（≤2 次，可与 H7/H8 同次运行）生成链子进程细节捕获**：复用修正形态 + runner `--post-parent-wait`；单变量=仅增强子进程观察（子进程命令行/cwd/退出码、stdout/stderr 留存尝试、实验目录旁 `_proc.log/_drc_check.log/_adc.log` 存在性、`log/ipgen.log` 增量）。判据：取得子进程失败文本，或明确“常规模具无法捕获”并留证据。

停止规则：任一假设连续 2 次同因失败即停该支；总尝试触及 6 即收束出结论；全部现场保留。
对 T01.tool-B 的影响：无强制变化；建议 scratch 端到端时顺带覆盖本机已注册的 `reset_runs` 与 `save_best_bits`（外部 `build.tcl` 同款流程），随同一次运行记录，不新增批次。
对 T01.tool-C 的影响：报告增补“外部参考评估”节（仓库/commit/SHA、版本缺口实测、GUI 佐证、`DS1300` 表 3-60 口径 flag）；不得把外部经验写成我们已跑通；任务板更新照旧等 A/B 证据。

### 4.2 T01.tool-B — TD CLI 其他控制命令端到端核验

范围：至少 `open_project`、`import_device`、`launch_runs`、`wait_run`、`report_timing_summary`，可行则含 `bitgen`（用户原话）。命令语义以 SWUG105（§3 脚本模式、§4.1/4.10）与 `docs/TD命令行使用说明.md` 为依据。

方法（两段）：
- P1 注册与约定基线：在 D 盘新目录重跑 `tools/td/verify_cli.tcl`（只读注册检查），记录 Tcl 版本与六命令注册；记录退出码。
- P2 端到端 scratch 工程：`D:\TD\work\csi2\_validation\td_cli_<ts>\` 内新建极小 ASCII 工程（自写微型计数器 RTL + 小 ADC 约束，非生产代码）：`import_device ph1_100p.db -package PH1P100SBG484 -speed 3` → `create_project` → `add_files` → `top_module` → `launch_runs syn_1` → `wait_run syn_1 -quiet` → 物理阶段（create_run + `launch_runs -step route` + `wait_run`；若管理器行为异常，另做记录并按需用文档化 native 路径对照，但须注明这是 workaround 不是修复）→ `open_run` + `update_timing -mode final` + `report_timing_summary -file`（解析 SWNS/HWNS/Period 行）→ `bitgen -bit …`（可行则含；产物非空+SHA）→ `close_project`。
- 负对照（必须实测）：
  - 故意失败脚本（如 open 不存在的工程）→ 收集器必须判 fail；实测 TD 退出码是否 0（“退出码不可单独证明成功”的实证）；
  - （可选，低优先）从仓库中文路径 cwd 运行极简脚本 → 记录实际失败现象作为文档证据（只在新目录/仓库 tmp 运行，不碰工程）。
- 逐命令验收表：命令名｜实际 argv/脚本行｜cwd｜exit｜成功标记｜非空产物+哈希｜结论（pass/问题记录）。发现“我们脚本/用法”的问题要修（例如相对路径、正反斜杠、cwd 约定）；工具内部缺陷（如管理器 exit1 而 worker 完成、PRJ-88xx）如实记录+给 workaround 影响评估，不冒充修复。
- 已知quirk核对清单（须逐条落证据）：正斜杠必需（`./x.tcl` 成立、`.\x.tcl` 失败）；脚本加载失败可能仍 exit 0；多行须文件执行；`-help` 被当脚本名；日志 `td_*.log` 写在 cwd；cwd 必须=工程目录；中文路径不可用；launch_runs/wait_run 的行为与现有历史记录对照。

允许写路径（精确）：新增 `tools/td/verify_cli_e2e.py`、`tools/td/verify_cli_e2e.tcl`（名字可微调，总数 ≤2）；新建 `D:\TD\work\csi2\_validation\td_cli_<ts>\`（只新建）；新建 `docs/evidence/td_cli_commands_<YYYYMMDD>.json`。不得修改 `tools/td/verify_cli.tcl`（保持只读基线的可对照性）。其余一切只读。
停止条件：六命令全部有实测结论（成功或可复现问题）；或耗时达上限。时间上限：综合 ≤1800s、route ≤3600s、bitgen ≤900s（对齐现有 runner 默认），本包 ≤4h；超限的阶段记 `not_run(timeout)` 并说明。
回退：scratch 工程独立、失败不影响任何既有工程；历史 native 路径证据保留引用。

### 4.3 T01.tool-C — 报告与同步

依赖 A、B 的实测证据就绪（不得先写结论）。产物：
1. `docs/TD_CLI_IpTool修缮与验证_<YYYY-MM-DD>.md`：需求三项映射；现状核实（含 10-15 前史）；根因分析（区分：脚本 argv 缺陷 / 工具行为 / 环境约定）；逐项修复与验证结果（A 的每个 H 结论、B 的逐命令表）；边界与未决项（GUI 依赖与否、bitgen 是否可行、工具内部缺陷）；下一步与回退（含 190248 人工包状态）；G 层与证据索引锚点。所有结论须引用证据路径+SHA；不得写任何未实测的"通过"。
2. 证据索引：A、B 已各自新建 `docs/evidence/*.json`；C 只引用不改写。如需总索引，可在报告内表格化，不另建重复文件。
3. `tools/td/README.md`：增补本次入口（runner 用法、实验目录约定、边界），保留旧记录。
4. `docs/TD命令行使用说明.md`：增补本次核实（退出码/标记实测结论、新增注意事项），不改写旧日期记录。
5. `workflow/tasks.json`：仅更新 T01 的 `status_note`/`references`（加本次证据与报告路径；生成成功则注明新候选与后续入口；仍 blocked 则注明边界）。JSON 解析自检；不改其他任务；不新造全局任务 ID（本批用 T01.tool-A/B/C 局部标签）。

三维验收：functional=报告内容逐条可溯源、无夸大；engineering=所有路径/SHA/版本可复现核对、tasks.json 合法且最小 diff；system=下一入口可执行、T01 状态与现实一致、人工包方向明确。
G 层：G0/G1（文档一致性）；硬件层 N/A（无板测动作）。时间上限 ≤2h。

### 4.4 T01.tool-D — TD 2026.2 并行安装与 headless 生成验证（用户 2026-10-16 决策）

背景与决策：用户原话「因为我的队友是6.2.3，所以先把版本更新下，然后下完新版本后如果还无法进行ip核设置就进行gui」；获取渠道=「官方账号，我有会员，我给你发张照片看选哪个」（用户稍后提供下载页截图确认选项）。**下载/安装包提供由用户完成；本轮不下载不安装。** 依据 `upgrade-review.md`（同目录）：队友两仓库与本机同板样本均为 TD 6.2.3.210850（Release_2026.2），其 IP flow 命令族（`create_ip/get_ips/set_property/load_project_ips/generate_target`）为本机 6.2.2 缺失；DDR MC 在 6.2.3 上有「设置 ADC + generate_target」外部实测声称（IPT-1001/61 文件），**完整参数注入未闭环 → 由本包在本机验证**。

1. **安装包接收与锚定（等用户）**：接收 2026.2 安装包（目标构建 `6.2.3.210850`；**若官方当前仅有更新版本**：记录实际文件名/版本后提请用户/主调度另行决定，不自行改用）。到位后只读记录：文件名、字节数、SHA256、安装器版本、配套 license 说明。现行回退保障：本机已持同版安装器 `D:\TD\03_MLK_AFH03_AFC03\软件&驱动\TD_Release_2026.1_SP2_NL.exe`（SHA `36e23685…`，1.89 GiB）。
2. **并行安装到新目录**：新目录（候选如 `D:\anlogic\TD_Release_2026.2`，**安装前与主调度确认**）；**不覆盖、不合并、不改动 `D:\downlaod`**。许可/license 与驱动处理方式按实际安装器与官方说明（license 可能直接复用现行 `Anlogic.lic`；下载链/驱动继续用 6.2.2，不为其更新 JTAG 驱动，除非安装器明确要求）。安装动作由用户或经用户授权的操作者执行；安装后登记新安装树关键文件（至少 `bin/*.exe`）哈希清单。
3. **新工具锚点登记**：新 `td_commands_prompt.exe`/`td.exe`/`IpTool.exe`（及实际存在者）SHA256、Tcl 版本、DB_VERSION（以 import_db/构建产出实测为准）、license 状态；命令注册**实测**：`info commands` 覆盖 `create_ip/get_ipdefs/get_ips/set_property/get_property/load_project_ips/close_project_ips/generate_target/report_ip_status`，对已注册命令取 `help`/最小调用——须实测存在且可用，**不得据外部材料推定为存在**。
4. **四步最小验证**（按 `upgrade-review.md` §4）：(a) 小 IP（如 AXIS FIFO/RAM）`create_ip→set_property→generate_target` 产 RTL 冒烟；(b) MIS DDR 实例创建 `ddrmc_x32`（用新版本自带 depot；1333 档参数注入以新版本命令族为准）；(c) DDR1333 参数/派生值/引脚核对；(d) 本项目 scratch 六命令 CLI 回归——复用 B 的 `tools/td/verify_cli_e2e.py` 套件在新版本重跑并对照 quirk 表。
5. **headless DDR1333 生成（成功分支验收）**：两次独立复现（两个全新 `td2026_*` 目录、同一冻结输入）+ 产物闭合（Design.xml/DesignConfiguration.xml/`<comp>.xml`/`.params_*`/`.ports_*`/wrapper/`src/**`/DRC、ADC 日志齐备；核心文件逐字节一致，或仅时间戳字段差异且逐字段列明）+ 参数与引脚核对（1333.00 / DDR3-1333J / CWL7 / 派生 CL10 / 实际 PLL 物理 CK ≤666.667MHz / 70 引脚与 golden ADC 逐项一致 / ADC 指向私有 `input_pins.adc` 本地化副本）——口径与 §4.1 完全相同。**1333 档参数依据仍以 MIS 生成器（新版本 depot 的 Dependency/Layout.tcl 与 70 引脚 ADC）逐项核对**。候选冻结方式同 §4.1（manifest+SHA），只作新候选，不进入任何既有工程/bit。
6. **失败/边界分支（用户指令的 GUI 后备）**：若 headless 仍不成立（完整参数注入不可行或生成失败）：转 **GUI 后备**——用新版 GUI 或 6.2.2+190248 包（含本批实测的目录形态修正建议；GUI 会话需用户在场，届时形成用户决策项并登记）；**不得把 GUI 步骤算作 headless 成功**，报告按"边界+人工路径"如实记录。两条路径的失败现场全部保留。

允许写路径：新安装目录（待定，安装前确认）；新建 `D:\TD\work\csi2\_validation\td2026_*`（只新建）；`docs/evidence/` 新 JSON（`td2026_*` 命名）；`tools/td/` 新 runner（如有——复用/扩展 `run_ddr1333_ipgen.py` 或 `verify_cli_e2e.py` 均可，**不得削弱既有断言与安全机制**）。其余一切只读。
纪律：新候选全链同版本（IP→综合→route→STA→bit/CWC 不跨版本拼接）；冻结工程只开副本；旧证据不迁移（A/B 证据继续绑定 6.2.2）；新锚点重新登记；不批量删除（逐文件规则）；不下硬件/不 Flash；不改动 `D:\downlaod`。
停止条件/时间上限：等待用户安装包到位；第 3–5 步完成即出结论（预计本会话工作 ≤1 天）；第 4(d) 或第 5 步两次同因失败即收束并转 GUI 后备。

## 5. “必须实测通过” vs “如实记录边界”

必须实测通过（不接受推断/字符串/人工步骤替代）：
- A：H1–H5 每条有真实执行记录（或明确“因前序结论而不执行”的书面理由）；生成成功分支的两次独立复现+参数核对；负对照。
- B：六命令真实执行；负对照（失败脚本的捕获）；bitgen（若因超限未跑，须有实测超时记录而非跳过）。
- C：报告每条结论对应 A/B 证据文件+哈希。

如实记录边界的典型情形（写清证据与下一步，不写“跑通”）：
- IpTool 若只能 GUI：窗口/阻塞客观证据 + 人工包路径 + 原厂求证建议；T01 维持 blocked。
- `launch_runs` 管理器若存在工具内部缺陷：记录缺陷 + workaround（native import_db 路径）+ 对生产流程影响；不声称已修复工具。
- bitgen 若因 scratch 工程或时间不可行：`not_run` + 原因。
- `xmlipgen`/`generate_ipinst` 若无法获得可用形态：记录为未文档化且实验失败，不复活 10-10 的“名字存在即可能”表述。

## 6. ready/blocked 元数据

| 工作包 | 状态 | 阻塞依赖 |
|---|---|---|
| T01.tool-A | ✅ round0 三维 PASS | — |
| T01.tool-B | ✅ round0 三维 PASS | — |
| T01.tool-C | ✅ r0+r1 全三维 PASS（已关闭） | — |
| T01.tool-D | ✅ r0+r1 全三维 PASS（已关闭；双复现成立） | — |

## 7. 需要用户决策/在场的事项

1. 若受控实验最终证明**完整生成仅能经 GUI**：需要用户决策是否安排一次"用户在场"的 GUI 生成（使用 190248 既有包或本次新建的等价包）。此前 10-15 已准备 190248 人工包，用户尚未执行，也未验证窗口；该项不阻塞 A 的 CLI 部分，但决定 T01 解锁路径。
2. 无其他需要用户决策项；无硬件动作授权请求（本批不下板、不 Flash）。

## 8. 角色与回退

- A、B 各派一个开发者，完成后各派功能/工程/系统三测试者（读同一冻结输入出独立报告，用报告约定）。
- 修正轮次由原开发/测试者续接；A、B 的共享问题（如都涉及 td_commands_prompt 行为）在 C 汇总时注明对另一维的影响。
- 回退：全部失败现场保留；190248 人工包与 002820 及历次 timing 候选保持原样；任何新生成候选都不自动进入任何构建。
