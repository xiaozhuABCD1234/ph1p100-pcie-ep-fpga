# lessons-learned — T01.tool-A（IpTool/TD CLI DDR1333 生成入口，run 20261016_185639_td_cli_iptool）

开发者：fpga-dev（本工作包唯一开发者）。日期：2026-10-16（含两轮主调度授权续接：+4、外部参考增量 +6；20/20 次尝试触顶）。
结论一句话：**没有 headless 生成成功（无任何完整 IP 产物），边界已受控实验证实（20 次尝试）。** 修正形态（双目录 + `-no_status` + `-app_path`）能进入工具自动生成阶段；以**工具期未手改实例**为源时 copy 值真实加载（日志 50.00/1600.00），把手改实例是此前取值回退默认的根因坐实；外部 golden ADC 路径本地化后仍确定性 `#IP Generate Failed!`（4 次运行日志逐字节一致）——外部 ADC 根因**必要但不充分**。6.2.2 的 Tcl 侧无 `create_ip/generate_target` 族、亦无可用"设参+生成"入口（H6/H7 定案）。证据：`docs/evidence/ddr1333_iptool_cli_20261016.json`。

## 1. 可复用根因（按重要性）

1. **`-user` 和 `-gen` 是目录选项，不是文件选项。** IpTool 自动模式会对参数做"目录 + 文件名"拼接校验：`-user X` 校验 `X/Design.xml`；`-gen Y` 校验 `Y/Component.xml`。
   - 触发条件：照 usage 文本把 `ddrmc_x32.xml` / `Component.xml` 直接当参数（历史 165740/190248 脚本、10-15 copy 尝试、本批 H1/H2 前 9 次全部如此）。
   - 现场证据：H2d 对话框原文 `Failed to identify the file: .../ddrmc_x32.xml/Design.xml`；H2e（user 修正为目录后）弹 `.../Component.xml/Component.xml`。截图 SHA 见证据 JSON。
   - 影响面：`tools/td/prepare_ddr1333_ip.py` 的默认 argv、190248 的 `open_ddr1333_gui.cmd`、此前所有"copy 生成"记录。**后续任何自动生成尝试必须用目录形式。**
   - 残留疑点：交互式 GUI 入口是否也受此约束未证实（窗口能打开、参数表能显示；绑定 marker 40s 内未出现）。

2. **自动/无人模式的两个失败通道**（同一工具、不同表面）：
   - 不带 `-use_value`：**即使加了 `-no_status` 也会开交互配置窗**并永久等待人工（attempt 13：900s、窗口实拍含 "Switch to Default Configuration" 工具栏；早前 H2：600s）。`-use_value` 是进入自动路径的开关。
   - 带 `-use_value copy|default` + 修正形态（双目录 + `-app_path`）：进入自动生成阶段，导出 8 个实例脚手架文件（57,702 B），随即 `#IP Generate Failed!`（约 2.5s，exit 0，无窗口）。**copy 与 default 两种模式的工具日志与 .m_params 逐字节一致**（SHA 88550b28… / 46432cc0…，attempts 11/12/14）→ 失败是**生成阶段系统性问题**，与值模式无关。
   - 不加 `-app_path` 时错误对话框不出现；加 `-app_path D:/downlaod/bin/td.exe` 后才弹出错误（H2d）——注意 `-app_path` 也会派生 `<stem>_commands_prompt.exe` 子进程名。
   - H1（default 单独形态）与上述静默失败同族（2.5~2.8s 静默 exit1）。

3. **`-tcl` 与生成参数互斥。** `-tcl` 是脚本模式开关，强制要求 `-source *.tcl`；与 `-gen/-user` 同用时要么快速 exit1（10-15 的 0.27s 案例），要么挂起（`-qcerr` 20s 案例）。历史 "copy + -tcl" 尝试实际没有到达生成逻辑。

4. **Tcl 解释器没有任何生成命令。** 全部 `info commands` 已档（H3）；`generate_ipinst` 不存在；`create_dialog` 只在静态 help 表里，实际未注册（`invalid command name "create_dialog"`）；`open_iplib` 需要 create_iplib 生成的库结构，depot 目录不是库。库命令（create/open/import/info/list/find/delete/close_iplib）不覆盖生成。
   - 因此"用 -tcl 脚本驱动生成"的路线在已注册命令集合内**不可行**（GUI 对话框语义的命令在脚本上下文不存在）。

5. **`xmlipgen`（TD CLI）是内部引擎步骤，不是用户入口。** 工程上下文存在（native）；`-h/-help` 空输出；猜的参数（-gen/-xml/-device/-user）全部被拒；裸调用报 `HDL-8001 ERROR: XmlIpGen cannot find all xml file.`（需要 IpTool 预备的未公开 XML 文件集）。不要把"名字存在"当入口（10-10 表述按此修正）。

6. **我们自加的 guard 不是 H1 阻塞原因。** guard-free 私有包（H1var_plain）表现与 H1 完全一致（2.70s vs 2.64s 静默 exit1）。guard 的上下文依赖（IP_INSTALL_PATH 等）只在裸 tcl 源 Dependency.tcl 时触发，属已知设计（GUI 流程中由工具注入）。

7. **正对照仍然成立**：`-tcl -source` 今天复跑 exit 0、trace 齐全、Tcl 8.6（`tcl_recontrol`）。这是唯一"已证实可用的 IpTool 入口"（诊断用途）。

8. **修正形态已达生成阶段，但生成引擎确定性失败（本批最终边界）。** attempts 11/12/14（copy×2+default×1）：exit 0、~2.5s、8 文件脚手架、工具日志三条动作+`#IP Generate Failed!`，三次日志与 `.m_params` **逐字节一致**。失败细节在 `td_commands_prompt.exe` 短命子进程里（无 td_*.log、stdout/stderr 不落盘，疑似 `-nolog`），本批无法读取。→ 下一步优先：GUI 一次人工生成看错误详情 / 调试器或 ETW 抓子进程输出 / 原厂求证。

9. **值注入的可疑点（供下一批单变量验证）**：prepare 脚本只改了 `Design.xml` 与 `.params_*`（1333/CL10/CWL7/50MHz），**未同步 `.m_params_ddrmc_x32.txt`**（仍是基线 800Mbps/CL11/CWL5/50MHz）。副本实例内部可能不一致，导致 copy 路径取值失败/回退默认（工具实际设了 REF_CLK 100/Speed 800）。候选实验：用"工具自己生成过的一致实例"（如 09 peripheral 工程或一次性 GUI 生成）做 `-user` 复跑修正命令。

10. **工具会在实验目录外写安装目录一个 21B 状态文件**：`D:/downlaod/bin/.setup.ini`（内容 `LAST_POS=(251, 177)`，窗口位置缓存），每次自动运行均观察到（attempts 11–20 的 mtime 均被刷新）；未改 IpTool.exe 本体（锚点 SHA 不变）。如实记录，非破坏性。

11. **（外部增量）TD 6.2.2 命令缺口定案**：`create_ip/get_ipdefs/get_ips/generate_target/generate_ipinst/load_project_ips/close_project_ips/report_ip_status/ip_upgrade/create_ipinst/delete_ipinst/list_ipinst` 全部不存在；存在 `set_property/get_property/create_syn_ip/xmlipgen/ipgen_synip/print_ip_config/read_ip_adc/export_ip_lib/set_ip_property/set_ippin_assignment/save_best_bits/reset_runs`（注册表另有 `generate_gate/generate_simulation/process_vlog_files/read_adc/export_ip_pins/export_ip_sdc/import_ip_pin_list/set_hxt_property/set_ipinst_assignment`）。`-h/-help/help` 无用法文本（help 只打印整张注册表）。→ 外部 6.2.3 配方不可移植。

12. **（外部增量）6.2.2 侧无可用"设参+生成"入口**：`set_ip_property` 静默受参（无可观测效果、不可验证）；`read_ip_adc` 需工程 IP model（USR-8321）；`create_syn_ip` 需 top model（PRJ-9009）；`xmlipgen` 恒为 `HDL-8001 cannot find all xml file`（需未公开的 XML 文件集）；`ipgen_synip` 无动作；`export_ip_lib` 报错。该线关闭。

13. **（外部增量）取值加载机制坐实 + 外部根因必要不充分**：以 002820 `vendor/ip/ddrmc_x32`（工具期、未手改）为 `-user` 时，automated copy 日志出现 `set 50.00/1600.00`（此前手改实例只出现默认 100/800）→ **prepare 脚本的手工编辑破坏了 copy 取值路径**（根因确认，具体破坏点未隔离）。把外部 golden ADC 路径映射为本机 `input_pins.adc` 后行为不变、仍 2.5s `#IP Generate Failed!`（4 次运行 log SHA 78a4a21c…/.m_params fde70a5a… 逐字节一致）→ 外部"ADC 路径"根因在本机**必要但不充分**，残余失败另有其因。

14. **（外部增量 H9）子进程文本无法用常规模具取得**：`td_commands_prompt.exe`（+conhost）在启动后约 0.2s 被 spawn、存活 <0.5s，无 td_*.log、stdout/stderr 不继承；最终捕获轮记录到 pid/名称但命令行（查询返回 null）与控制台文本（抓取时缓冲为空）均未取得 → 判据"常规模具无法捕获子进程失败文本"，需调试器/ETW 级手段。

## 2. 本批受控实验账（10 次生成类尝试，正好触顶；细节见证据 JSON）

| # | attempt | 目录后缀 | 单变量 | 结果 |
|---|---|---|---|---|
| 1 | negctl_user | 191016 | 负对照（-user 不存在） | exit1、静默、零产物（失败可捕获）；另有两次空 argv 调试不执行工具 |
| 2 | h1_default | 191204_1 | H1 usage 默认形态 | exit1@2.64s 静默零产物 |
| 3 | h2_copy | 191508_4 | H2 copy 形态（长超时） | 600s 超时；窗口 ~7.2s 起挂起、CPU 冻结；kill 已验 |
| 4 | h1var_plain | 192929_10 | 私有包去 guard | 同 #2（guard 排除） |
| 5 | h1_qcerr | 193141_11 | +`-qcerr` | 同 #2（无文本输出） |
| 6 | h1v2_gendir | 193213_12 | `-gen` 指目录 | 同 #2（该形态仍不成） |
| 7 | h2b_nostatus | 192854_7 | +`-no_status` | 窗口消失→自动模式静默 exit1@2.58s |
| 8 | h2c_projpath | 193337_13 | +`-proj_path` | 同 #7 |
| 9 | h2d_apppath | 193357_14 | +`-app_path` | **弹出 Error 对话框**（user 路径应为目录）600s 挂起被杀 |
| 10 | h2e_userdir | 194444_15 | `-user` 改目录 | **弹出 File Identification Error**（gen 路径应为目录）；~135s 后 exit0、零产物（对话框消失归因有并发活动干扰，已如实记录） |

另：H3 探针 ×2（191344_2 / 191430_3）、H5 GUI 探针 ×2（192652_6）、H4 xmlipgen ×2（194801_17 / 194851_18）、正对照（194800_16）、runner 冒烟（191037_9）、未使用目录（192919_9，权限门测试产生，无执行）。

授权续接（+4，attempts 11–14，全新目录）：

| # | attempt | 目录后缀 | 单变量 | 结果 |
|---|---|---|---|---|
| 11 | h2f_corrected | 195304_19 | 修正形态双目录+no_status+app_path（copy） | exit0@2.83s；8 文件/57,702B；`#IP Generate Failed!`；子进程 td_commands_prompt 出现 |
| 12 | h2g_repeat | 195532_20 | 同 #11 复跑 | 逐字节同日志（88550b28…）与 .m_params（46432cc0…） |
| 13 | h2h_nousevalue | 195622_21 | 去 `-use_value` | 交互窗（900s 超时、kill 验证）；窗口实拍含 "Switch to Default Configuration" |
| 14 | h2i_defaultmode | 201333_22 | `-use_value default` | 与 copy 完全同败（日志/.m_params 逐字节一致）→ 系统性问题 |

外部参考增量（+6，attempts 15–20，全新目录；H6→H9）：

| # | attempt | 目录后缀 | 单变量/目的 | 结果 |
|---|---|---|---|---|
| 15 | h6_probe | 203627_23 | H6 命令集普查（只读） | 缺口定案：无 create_ip 族；12 个目标命令 present，全无帮助文本 |
| 16 | h7_probe | 203721_24 | H7 最小受控调用（scratch 工程） | 无可用设参+生成入口（USR-8321/PRJ-9009/HDL-8001 证据） |
| 17 | h8_toolmade_source | 203808_25 | H8 源=工具期未手改实例 | **取值加载机制坐实**（日志 50/1600）；仍 `#IP Generate Failed!`；8 文件/72,842B |
| 18 | h8b_local_adc | 203932_26 | +外部 ADC 路径本地化（记录变体） | 同败（72,830B）→ 外部根因必要不充分；4 次运行 log/` .m_params` 逐字节一致 |
| 19 | h8c_capture | 204025_27 | H9 捕获轮 1 | 同败；子进程未捕获（首采样阻塞窗口，harness 缺陷） |
| 20 | h8d_finalcapture | 204128_28 | H9 捕获轮 2（修正早期高频） | 捕获到 td_commands_prompt pid/名称（存活 <0.5s）；cmdline/控制台文本不可得 |

## 3. 下一步（给后续批次的精确入口）

1. **用户决策点（T01 解锁主路径）**：a) 用户在场做一次 GUI 生成（190248 包或新建等价包；GUI 点击清单已有外部佐证）；b) 升级/另装 TD ≥6.2.3 以取得 Tcl IP flow（版本缺口已实测；兼容风险未测）。二者皆超出本批授权。
2. **若继续 headless 深挖**（需新授权）：用调试器/ETW 挂到 `td_commands_prompt.exe` 读失败文本（子进程 <0.5s）；或向原厂索取 IpTool CLI 生成契约。
3. **值集一致性教训（已入 prepare 脚本 notes）**：后续再做 `-use_value copy`，必须使用**内部一致的实例**（工具生成或从工具自产文件集派生）；手工改 `Design.xml/.params` 而不同步 `.m_params` 会导致取值回退默认。
4. 复现 H8b 配方（测试者）：`new-dir --extra-source <002820 vendor/ip/ddrmc_x32>` + `variant --adc-to-local` + `run --raw IpTool.exe ... -user <新目录>/source/ddrmc_x32_extra -gen <新目录>/depot ... -no_status -app_path D:/downlaod/bin/td.exe -use_value copy`（预期：`#IP Generate Failed!`、8 文件脚手架、log SHA 78a4a21c…）。
5. 生成候选何时冻结：仅在成功分支（两次独立复现+参数/引脚核对全过）后执行，见 dev-plan §4.1；本批无候选。

## 4. 本批脚本/资产状态

- `tools/td/run_ddr1333_ipgen.py`（新，终版 SHA `b44e065c…62b7d`；版本史：`7b6f1596…` attempts 1–10、`98a517fc…` attempts 11–14、当前版 attempts 15–20 增加 Toolhelp32 快速子进程追踪/cmdline+控制台捕获、`--extra-source`、`adc-to-local` 变体与早期高频监控）。受控实验/生成 runner（new-dir/run/gui-probe/verify/variant），全记录、无删除、超时真杀进程树、自动抓对话框截图。
- `tools/td/prepare_ddr1333_ip.py`（修，`81b4f29a…` → `b388a796…` → `1d271cad…` → 终版 `2d345898…`）：`cli_entry_status` 写实（20 次结论、可 `--entry-status` 覆盖）；argv 参数化；`argv_notes` 增补"手改实例破坏 copy 取值"警示；全部断言与保留式清理未动。**未运行该脚本**（其输出目录名 `ddr1333_ip_*` 不在允许写路径内）；仅 `--help`/AST 校验。
- 证据 JSON：`docs/evidence/ddr1333_iptool_cli_20261016.json`（本批全部关键 SHA 锚定；含 attempts 1–20 与 `external_reference_increment_H6_H9` 段）。
- 实验目录：`D:/TD/work/csi2/_validation/ddr1333_cli_20261016_*`（28 个，仅新建；attempts 1–20 分布的目录均含 NOTES.md）。

## 5. 记录边界与已知限制

- h2e 的 exit0/对话框消失受桌面上并发活动干扰，无法完全归因；一切窗口证据仍以 0.5s 轮询 + PrintWindow 原始 PNG 为准。
- 残余 `#IP Generate Failed!` 的具体原因在预算内未能定因：取值已加载、ADC 已本地存在，仍确定性失败；子进程文本用常规模具取不到（H9 判据），需调试器/ETW 或原厂支持。
- 手改实例破坏 copy 取值的**具体编辑点**未逐项隔离（仅确认"未手改实例取值正常、手改实例回退默认"）。
- `.setup.ini`（安装目录 21B 窗口位置缓存）被工具在每次自动运行中改写——已逐次记录；IpTool.exe 本体与官方 depot 锚点 SHA 全程未变。
- 自动模式错误文本仅在带 `-app_path` 时可见——重要的工具行为；使 10-15 及更早的"静默失败"记录按新证据重新解释。
- 未动 `D:/downlaod` 除工具自身 `.setup.ini` 之外的任何内容、冻结工程、既有 `_validation` 目录；无批量删除；无硬件动作；未执行外部仓库任何脚本。
- 尝试数：20/20（10+4+6）触顶；同支失败 2 次即切换/停止（H8 支在两次同因失败后仅剩的最后一轮改用于 H9 捕获判据）；未违反单变量纪律。

---

# lessons-learned — T01.tool-B（TD CLI 其他控制命令端到端核验）

开发者：fpga-dev（本工作包唯一开发者）。日期：2026-10-16。环境：TD Release_2026.1_SP2 / 6.2.2.200067 / Tcl 8.6.15；`td_commands_prompt.exe` SHA `79EC5667…F87190` 未变；`ph1_100p.db` SHA `8E7E8812…CF3AA2`。全部实测在新建目录 `D:\TD\work\csi2\_validation\td_cli_20261016_205203`（只新建；16 阶段脚本/资产冻结后 SHA 全过）。证据：`docs/evidence/td_cli_commands_20261016.json`（每阶段 argv/cwd/pid/exit/标记/产物字节+SHA；含 raw command_table 与 analysis 节）。

结论一句话：**六命令 scratch 0→bit 全链路真实跑通（含 bitgen 5,223,983 B，SHA `1816AFF8…939115`）；管理器 syn+route 本次零 PRJ-88xx；已知 quirk 逐条实测复证；“退出码不可单独证明成功”获双重负对照实证。**

## 1. 可复用结论（按重要性）

1. **管理器 syn+route 在简单设计上直接可用**：fresh 工程 `create_project→add_files→top_module→create_run→launch_runs→wait_run`（综合仅 4.04s wall）、`create_run -syn_run→launch_runs -step route→wait_run`（route 20.18s）、`open_run`（PRJ-1408，内部对 `_pr.db` 执行 import_db）全部 exit0+标记+真 DB 产物。历史 PRJ-8806/8808/8818 **未复现** ⇒ 属上下文相关（大设计/调试核/策略切换），不是 6.2.2 的普遍缺陷；native workaround（`s2n_native_route.tcl`，备而未用）只适用于历史失败场景，不得当修复宣传。
2. **exit code 精确边界（新）**：脚本内**显式 `exit 1` 会传播**（q7c 实测=1）；而**加载失败/未捕获命令错误**（文件不存在、invalid command、PRJ-8642）→ 打印错误、落入 `td >` 交互提示、进程 **exit 0**（neg1/neg2/q2/q3b/q8 五处实证）。成功判定只能三件套：exit + 显式标记 + 非空产物。
3. **`.\x.tcl` 的失败机制 = Tcl 字符串转义**：参数被吃成 `.q2_backslash.tcl`（错误原文 `couldn't read file ".q2_backslash.tcl"`）。绝对正斜杠路径可用（q7c 实测）。调用一律 `td_commands_prompt.exe ./name.tcl`。
4. **相对路径全部按 cwd 解析，与脚本所在位置无关**：q7b（错误 cwd）连 `./脚本名` 都找不到；q7c（绝对脚本 + 错误 cwd）项目文件报 PRJ-8642。cwd=脚本/工程目录是硬约束；`td_*.log/.logw` 严格写 cwd（root 28 个=14 阶段 ×2、wrongcwd 4 个=2 阶段 ×2 实测）。
5. **中文路径参数复证不可用**：一个真实存在的中文路径脚本参数被报 `no such file or directory`（q8；ASCII cwd 内隔离测试，未在中文 cwd 执行任何工程动作；边界保持）。
6. **stdin 多行口径修正**：简单 3 行管道 stdin（set; if-brace; exit 0）实测**可用**（echo+标记+exit0）；10-10 “括号解析错误”未复现。真实流程仍一律文件执行。
7. **`-help` 被当脚本名复证**（`couldn't read file "-help"`，exit 0）。
8. **`save_best_bits` 观察**：6.2.2 此序列“调用被接受（无错误）但无任何产物”（无 best_result 目录）——与外部 6.2.3 `build.tcl` 第 5 步不完全等价；如实记录，不作验收/缺陷定论。
9. **bitgen 对 scratch 微设计直接可用**：`bitgen -bit` → BIT-1003 完成日志 + 5,223,983 B + 内部 export_bid 190 B；每阶段整进程耗时秒级（syn 8.8s / route 22.4s / timing 6.3s / bitgen 6.8s，含 TD 启动）。

## 2. 阶段账（16 阶段；负对照与 quirks 逐条）

| stage | 目的 | expect | exit | collector | 结果 |
|---|---|---|---|---|---|
| p1_verify_cli | 基线注册（verify_cli.tcl 字节同版复制） | pass | 0 | pass | 六命令 OK + Tcl 8.6.15 |
| q1_forward_slash | `./x.tcl` 正斜杠 | pass | 0 | pass | OK |
| q2_backslash | `.\x.tcl` | fail | 0 | fail | 转义吃斜杠、couldn't read file、exit 0 |
| q3_help | `-help` 当脚本名（首轮未声明标记） | fail | 0 | pass* | *collector=exit0-only；权威记录见 q3b |
| q3b_help_marker | 同上 + 标记版 | fail | 0 | fail | couldn't read file "-help" |
| q5_multiline_stdin | 多行 stdin | any | 0 | pass | 简单 3 行可用（口径修正） |
| neg1_open_missing | 负对照：开不存在工程 | fail | 0 | fail | PRJ-8642、脚本中止、exit 0 |
| neg2_undefined_command | 负对照：加载/求值失败 | fail | 0 | fail | invalid command、exit 0 |
| s1_syn | 建工程+add_files+top+syn 全链 | pass | 0 | pass | gate.db 143,506 B SHA `E0318D87…785529` |
| s2_route | create_run -syn_run + route | pass | 0 | pass | place.db+pr.db 156,270 B SHA `FD24A218…E21D15` |
| s3_timing | open_run+update_timing+report+parse | pass | 0 | pass | SWNS 17.081 / HWNS 0.222 / PERIOD 0.000 |
| s4_bitgen | open_run+STA 门+save_best_bits(观察)+bitgen | pass | 0 | pass | bit 5,223,983 B SHA `1816AFF8…939115` |
| q7a_open_cwd_ok | cwd=工程目录相对 open | pass | 0 | pass | OK |
| q7b_open_cwd_wrong | 错误 cwd + 相对脚本 | fail | 0 | fail | 脚本本身找不到 |
| q7c_open_abs_script_wrong_cwd | 绝对脚本 + 错误 cwd | fail | 1 | fail | PRJ-8642；显式 exit1 传播 |
| q8_chinese_script_path | 中文路径参数 | any | 0 | fail | couldn't read file（复证） |

collector 规则 = exit0 AND 标记 AND 非空产物 AND require 全过，与 dev-plan 三件套一致。

## 3. 边界与备注

- s2n_native_route.tcl（native 恢复路径）备而未跑：管理器未异常 ⇒ `not_run(not_needed)`；不虚跑、不冒充修复。
- `save_best_bits` 无产物一事已入证据 `analysis.limits`，未定论；q5 口径修正同处。
- scratch 为 G2-lite：bit 未下载；D:\downlaod 前后全量 mtime 扫描零写入；`_validation` 目录数 212→212；002820 `input_manifest.json` SHA 未变（`8F8E4EFE…F9A1C8`）。
- `tools/td/verify_cli.tcl` 未改（基线 SHA `B3269486…BB22F2`）；新增资产：`tools/td/verify_cli_e2e.py`（harness，SHA `d59d349f…f139b`）与 `tools/td/verify_cli_e2e.tcl`（stage1 脚本，SHA `440785f3…a0c4`），二者字节同版复制进 scratch 执行。
- 副产品如实记录：`python -m py_compile` 语法检查在既有 `tools/td/__pycache__/` 生成 `verify_cli_e2e.cpython-311.pyc`（32,916 B，2026-10-16 20:52:01）；尝试按单文件规则删除被沙箱权限拒绝（未绕行），保留该标准 Python 缓存文件；未纳入任何 manifest，不影响冻结基线。

## 4. 复现入口（测试者）

- `python tools/td/verify_cli_e2e.py init` → 每阶段 `stage`（精确参数见证据 `stages/*.json` 的 argv/cwd）→ `collect`；证据锚点 `docs/evidence/td_cli_commands_20261016.json`。
- 关键 SHA：TD CLI `79EC5667…F87190`；ph1_100p.db `8E7E8812…CF3AA2`；e2e py/tcl 与全部 stage 脚本 SHA 见证据 `experiment.files` / `analysis.frozen_inputs`。

---

# lessons-learned — T01.tool-D（TD 2026.2 并行安装与 headless 生成验证）

开发者：fpga-dev（本工作包唯一开发者；后台续接实例）。日期：2026-10-16。环境：TD Release_2026.2 / **6.2.3.210850**（2026-08-19 构建）/ Tcl 8.6.17 / DB_VERSION **46207**；新安装 `D:\anlogic\TD_Release_2026.2`（与 6.2.2 并行，`D:\downlaod` 未动）。证据：`docs/evidence/td2026_install_20261016.json`、`docs/evidence/td2026_ipgen_20261016.json`；断点笔记 `workflow/runs/20261016_185639_td_cli_iptool/dev-notes-td2026.md`。

结论一句话：**安装成功（需用户 1 次 UAC 点击；license 需手动复制）且 Tcl IP flow 命令族真实可用（小 IP headless 生成跑通、六命令 scratch 全链 PASS）；但 MIS DDR1333 的 headless generate 被工具内部 adc.log/staging 前置条件确定性阻塞（8 次同因失败）——判边界，GUI 后备为决策点，headless 成功不成立。**

## 1. 安装器与安装（可复用事实）

1. TD 2026.2 安装器 = **Advanced Installer 21.6.1** 引导 exe + 每机器 MSI（ALLUSERS=1；主目录属性 `APPDIR`；ProductCode {C96C0B0F…}）。静默参数用 AI 家族语法：`/exenoui /qn /norestart APPDIR="D:\…" /L*V "log"`（专有开关在前）。
2. **`/qn` 非提权必败 1603**：日志根因行 `MSI_LUA: Installation UI level is silent, no credential elevation is possible`（APPDIR / `/L*V` 均转发成功）。`/qb`（Basic UI）会弹 UAC：**用户点击“是”后 106s 装完**；这是本环境唯一可行路径（agent 侧提权被运行环境权限系统拒绝，属设计约束）。
3. **新装 license 为空**：不复制 license 时，注册/建工程/IP 工具都正常，但**合成 worker 在 optimize_rtl 报 `RUN-8008 Cannot find license file`**，外层表现为 `PRJ-5303 Run failed` + `PRJ-8806 Run has exited unexpectedly`（易误判为管理器缺陷！）。处置：复制 `D:\downlaod\license\Anlogic.lic`（SHA `DC19FEE6…`，NODELOCKED，2027-03-31）到 `D:\anlogic\TD_Release_2026.2\license\` 后全链通过。**6.2.3 与 6.2.2 的 DB_VERSION 相同=46207**。
4. 安装器副作用（如实记录，未回改）：用户 PATH 追加新 bin；创建 `.al` ProgID `Anlogic.TD_Release_2026.2.al`；公共桌面快捷方式；%APPDATA% 提取物被安装器自清；VC redist/驱动/服务无变化；`D:\downlaod` 三锚点哈希全程未变。
5. 新锚点：td_commands_prompt `2629E474…`（123.4MB，与 td.exe `FA2A5AC6…` 同字节数）；IpTool `5B0654AA…`（24.5MB）；ph1_100p.db `939EC294…`；MIS Depot（6.2.3 新版）Component.xml `3E854A26…`、Dependency.tcl `51C2311F…`。

## 2. Tcl IP flow（6.2.3 新能力，实测形态）

1. 命令族真实存在且可用：`create_ip -vlnv <vendor:ip:name:ver> -component_name <n> -export_path <已存在目录>`；`load_project_ips`（跨会话重开工程后必须，从 ip xml 重注册）；`get_ips`；`set_property CONFIG.<param> <value> [get_ips <n>]`；`generate_target [get_ips <n>]`（`all` 形态同义）；`close_project_ips`。`help` 只会打印整张注册表（`create_ip -help` 不产帮助文本）。
2. `-export_path` 必须指向已存在目录（不存在即报 `... does not exist`）；首次 generate 成功后工具清理其 `. *ToolIpDataBackupDir_*` staging；失败的 generate 回滚删除 staging。
3. 参数验证闭环：set 后**复读 `<ip>/.params_<n>.txt`**（U/G 标记逐项核对）比只看 exit code 可靠；派生值（CL/CWL/tCK/ACTUAL_FREQ）由依赖在 set/generate 时重算（1333 档实测 tCK=1500、CL=10、CWL=7、ACTUAL=666.7MHz）。
4. 若干参数在新版本为 **ReadOnly**（PH1P_PINGPONG_PHY/PZQ_CAL/PZQ_SHARE/RDBI/DDR_PARITY 等）→ set 只发 `USR-7001` 警告不致命；`PH1P_SYSCLK_LOC` 可选范围依赖 ADC check 产物，无 adc.log 时 range 为空、H4 无法 set。
5. smoke 首选 `anlogic.com:ip:APB_GPIO:1.0`（无 ADC/PLL 依赖的最小链：create/set/generate 产 `IPT-1001` + RTL）。

## 3. DDR1333 headless 边界（核心教训）

1. **症状**：`generate_target` 确定性失败 `[Error-TclFile] couldn't open "<export>/.IpToolIpDataBackupDir_<comp>/<comp>_adc.log": no such file or directory`（r1/r2、同会话/跨会话、`all` 形态、staging 预置/adc.log 预置/竞态注入 5 次，共 8 次同因，1.6~4s 内失败）。
2. **机制（实时审计+脚本级证据）**：generate 在 staging 目录运行依赖脚本；`Dependency.tcl` 的 `update_gui_pll→cal_onlyacbkby` / `update_sysclk_loc` 以 `open r` **读** `<export>/<comp>_adc.log`，写该文件的是 `drc_check`（同文件 L2228，位于其末尾）；工具在 generate 开始时清空 staging → 先读后写 → **首生成永缺该文件**。正常由 **GUI 的 ADC 选择/应用（check）步骤** 物化（工具自产参考：`002820\vendor\ip\ddrmc_x32_adc.log`，格式 `sig,bank,byte,pin`）。
3. **CLI 无等价入口**：`read_adc`/`read_ip_adc` 均 `USR-8321 cannot find ip model`；`CONFIG.PH1P_IO_ASSIGN` 的 set 不触发 check（该参数无依赖回调，回调挂在计算参数 PH1P_AC_BYTE/PH1P_DRC_CHECK 上）。预置 adc.log 到 export 根/实例目录/staging 均无效（工具只信自身 staging 构建）。
4. **下一步（GUI 后备与后续任务）**：a) 用户在场用 6.2.3 GUI 对 IP 对话框做一次 OK/应用（物化 adc.log）后再试 CLI generate——**未验证，须复测**；b) 直接全 GUI 生成并交回核查；c) 或向原厂求证 headless 的 ADC-check 入口。**不得把 GUI 步骤记作 headless 成功**；本轮候选未冻结。
5. 纪律复述：70 引脚核对基准 `input_pins.adc` SHA `F0904238…`（=golden）；生成输出必须指向**全新**目录（实测工具自清 staging/回滚行为）。

## 4. 六命令回归（新安装重跑）

1. 冻结套件**字节副本**（仅改 TD_EXE/PH1_DB 两行；副本 SHA `F916DDA1…`）在新版跑：p1/s1-syn/s2-route/s3-timing/s4-bitgen 全 PASS；q1 正斜杠 ✓、q2 反斜杠 ✗（同机制）、q3b `-help` ✗、q7a cwd ✓；**save_best_bits 仍“接受无产物”**（同 6.2.2 quirk）。
2. 回归证据：`td2026_20261016_214505/cli_regress/td2026_regress_evidence.json`（SHA `ADCC42F5…`）；关键产物：gate.db `4665BF81…`、pr.db `CD620226…`、timing rpt `319548F7…`、bit `CFE81199…`（5,223,979B，未下载）。
3. 6.2.3 的 bit 比 6.2.2 同设计多 4B（头部字段差异，作记录）。

## 5. 复现入口（测试者/后续任务）

- 安装复现：`…NL.exe /exenoui /qb /norestart APPDIR="D:\anlogic\TD_Release_2026.2" /L*V <log>`（需用户点 1 次 UAC）；随后复制 license（SHA 同 §1.3）。日志锚点：`install/msi_qb.log` `5E129902…`、失败样本 `install/msi_silent_unelevated.log` `4A1284E0…`。
- 锚点/命令族复现：`anchor/probe1.tcl`、`probe2_import.tcl`（原文 `probe1_out.txt` 178,289B）。
- smoke 复现：`smoke/smoke1/smoke_a..d.tcl`（产物 SHA 见 `td2026_ipgen_20261016.json` step1）。
- DDR 边界复现：`ddr1333_r1/ddr_a..g.tcl` + `ddr1333_r2/r2_allinone.tcl`、`ddr_h.tcl`（失败现场保留）。
- 回归复现：`cli_regress/verify_cli_e2e.py`（副本）+ `td2026_regress_evidence.json` stages 参数；root=`cli_regress/td_cli_td2026_2`。

---

# lessons-learned — T01.tool-D-A-retry（方案 A 实测收束）

开发者：fpga-dev（同任务续接）。日期：2026-10-17。证据：`docs/evidence/td2026_gui_bootstrap_20261017.json`、`docs/evidence/td2026_ddr1333_generate_20261017.json`。

1. **方案 A（GUI 只做 OK/应用 → CLI 生成）实测不成立**：GUI 的 OK 会正确运行 ADC check（ipgen.log 可见 banks 4/5、ac{5 1..3}、dx{4 0..3}，与 golden ADC 一致），但**不写 `<export>/<comp>_adc.log`**（根与 staging 均无；staging 还被 GUI 清理删除）；随后 CLI `generate_target` 两次复跑均同错（`couldn't open <staging>/<comp>_adc.log`）。结论：该文件是 GUI（IpTool 路径）**完整生成**步骤的产物（002820 proc.log 的 "generate adc file success"），不是对话框 OK 的产物——而 TD-CLI 的 Tcl 流水线在脚本写入前先读它，属工具侧断点。
2. **GUI（6.2.3，IpTool V2026.08）会话的其它可复用事实**：a) 打开工程 + 双击 IP 实例即可打开配置对话框（用户实操确认可达）；OK 后出现 “IP Generating Options”（可关闭=不生成）；b) GUI 会把 IP 加入 design_1 并自动建 `syn_1`/`phy_1` runs、生成 `run.bat`/`multirun_script.tcl`（其 `import_device -package -speed 3` 字段为空、脚本残缺，直接跑无任何构建产物——GUI quirk）；c) GUI 会创建并最终清删 `.IpToolIpDataBackupDir_*` staging；d) 工具在安装目录改写 `bin\.setup.ini`（21B 窗口位置缓存，同 6.2.2 行为类）。
3. **方案 B 是当前唯一确定通道**：同一对话框**不关闭 Generating Options**，填 Binary Path=`D:/anlogic/TD_Release_2026.2/bin/td.exe`、Synthesis=Behavior、Export to=`<bootstrap>/ip_out` 后点 Generate；产出闭包应与 002820 同形（src/RTL + adc/drc/proc 日志），之后按 §4.1 口径验收（70 引脚/派生值/两次独立复现），且**不得记作 headless 成功**。
4. 复现入口：`td2026_gui_bootstrap_20261017_000935`（`boot_retry_generate.tcl`、`boot_retry_out{,2}.txt`、`log/ipgen.log`）；失败现场全保留。

---

# lessons-learned — T01.tool-D-B-accept（GUI 完整生成验收 + CLI 复现裁定）

开发者：fpga-dev（同任务续接）。日期：2026-10-17。证据：`docs/evidence/td2026_ddr1333_accept_20261017.json`。

1. **方案 B（GUI 完整生成）实测成功**：IP 对话框 OK → **不关闭** “IP Generating Options”，填 Binary Path / Synthesis Options=Behavior / Export to 后点 Generate，约 2 分钟产出完整闭包（与 002820 同族：根级 adc/drc/proc 三日志 + src/{adc,rtl,sdc} + 双 wrapper）；完成标记 `#GUI-2000 ... generated successfully` + `#IP Gen Succeeded`；proc.log 12 步全 success（比 002820 多 modify_include/modify_phyinit 两步）。
2. **§4.1 验收全过**：1333.00 / DDR3-1333J / CWL7 / CL10 / tCK1500ps / SYSCLK_LOC=H4 / PLL=BANK33 / ACTUAL=666.7；物理 CK = PLL0 50×80/3/2 = 666.6667 MHz（≤666.667）；70 引脚逐项一致（golden 的 addr[14]=J5 因 ADR_WIDTH=14 正确不布）；ADC 指向本地 input_pins.adc；候选 manifest 64 文件冻结（D71057F3…）。
3. **CLI 复现裁定 = 不可行（结构性）**：把真实生成的 adc.log 预置于预期 staging 路径仍同错——工具在会话加载阶段清空其 staging（`STAGING_ADC_EXISTS:0`），"先读后写"顺序问题在 6.2.3.210850 上无法用外部预置绕过。**每个新 IP 实例的最小复现单元 = CLI create 冻结配方 + 一次用户在场 GUI Generate**；第二次独立复现必须再跑一次 GUI 生成（不得把单次 GUI 生成称两次）。
4. 决策建议（供规划/C 报告）：DDR MIS 版图流程按“一次性 GUI Generate + 完整闭包冻结”的口径如实表述；若需完全 headless，剩余路径仅原厂求证/后续版本修复。复现入口：引导目录 + `boot_create.tcl` 配方 + GUI 生成步骤（gui-bootstrap-A_instructions.md §方案B节）。

---

# lessons-learned — T01.tool-D-B-run2-verify（双复现裁定）

开发者：fpga-dev（同任务续接）。日期：2026-10-17。证据：`docs/evidence/td2026_b_run2_20261017.json`（及 accept 证据的 `second_reproduction_update`）。

1. **两次独立复现成立（PASS）**：run1/run2 均为「CLI 冻结配方 create+set → 用户在场 GUI Generate」；闭包各 64 文件；**60/64 逐字节一致**（含全部 RTL、src/adc、src/sdc、wrapper、adc/drc/proc 日志——**adc.log 逐字节相同**是引脚等价的最强证明）；4 个差异文件逐一字段级证明非实质：`.params`/`Design.xml`=仅各 run 目录的 input_pins.adc 路径串；`ddrmc_x32.v`=仅 Gen time 时间戳；`ddrmc_x32.xml`=仅 XML 属性顺序（语义 diff=0）。
2. **判定方法学沉淀**：字节级 diff（首差偏移+hex 上下文）+ 语义级归一比对（XML 属性序/空白不敏感、运行目录串与时间戳归一化）组合，可把“看似大量差异”的 XML 收敛为 0 语义差异；`.params` 归一后逐字节相等直接钉死“仅路径字段”结论——建议后续同族比对复用 `run2_verify.py`/`semantic_diff.py`。
3. **可复现性的最终口径**：每个新 IP 实例 = 一次 CLI 冻结配方 + 一次用户在场 GUI Generate；两次复现已验证该模式产出封闭且一致；CLI 全 headless 生成在 6.2.3.210850 上仍不成立（已证），如需全自动须原厂路径/版本修复。
4. 复现入口：run1/run2 目录 + gui-bootstrap-A/B instructions + `run2_verify.py`/`semantic_diff.py`；候选推荐 run1（manifest `D71057F3…`），run2 镜像（`9B3E5D00…`）。

---

# lessons-learned — T01.tool-C（报告与同步）

开发者：fpga-dev（本工作包唯一开发者）。日期：2026-10-16。
结论一句话：四份证据 JSON + 九份 r0 三维报告（A/B/D 全 PASS、零修正轮）已逐条核对并将文档级观察并入报告/README/使用说明；T01 任务板仅更新 status_note/references，如实保持 blocked（headless 未成立、GUI bootstrap 为下一步）。

1. 可复用根因/触发（汇总给后续批次）：
   - **GUI bootstrap 依赖（6.2.3）**：`<comp>_adc.log` 由 GUI 的 ADC check/apply 物化，CLI 无等价入口（read_adc/read_ip_adc=USR-8321）→ 任何"MIS DDR IP 全自动化"任务先解决该前置，或按 A/B 选项走 GUI；GUI 步骤不得记 headless 成功。
   - **IpTool 自动路径三要素（6.2.2）**：`-user/-gen` 目录契约 + `-use_value` 开关（否则开交互窗等待人工）+ `-app_path` 才见错误对话框；`-tcl` 与生成参数互斥；手改实例（不同步 .m_params）破坏 copy 取值。
   - **退出码不可单证**：显式 exit1 传播、加载失败/未捕获错误 exit0；判定=exit+显式标记+非空产物+哈希三件套。
   - **管理器 PRJ-8806 间歇 1/4**：wait_run 报错≠产物失败（查 run.log/flow.status/DB）；save_best_bits 两版均"接受无产物"（不作验收）。
   - **双版本纪律**：绝对路径调用；旧证据不迁移（A/B 绑定 6.2.2）；新锚点登记（PATH 追加、.al 默认关联切换等安装器副作用如实记录）；bit 确定性看 bit/Global CRC、不看 .al/.db 逐字节；两版 bit 差 4B（6.2.3 少 4B）。
2. 文档纪律：证据口径修正仅以"备注/更正"呈现（不改冻结证据）；报告每条结论引用证据路径+磁盘重算 SHA；GUI 结果单列 pending 小节。
3. 本轮交付：`docs/TD_CLI_IpTool修缮与验证_2026-10-16.md`（新建）、`tools/td/README.md` 与 `docs/TD命令行使用说明.md` 增补（0 删除）、`workflow/tasks.json` 仅 T01（JSON parse 自检过）、本小节。
4. 复现入口：报告 §7 证据索引（4 证据 JSON + `td2026_regress_evidence.json` + 脚本/工具/bit/manifest 锚点）。

---

# lessons-learned — T01.tool-C 最终更新轮（报告落成与同步，2026-10-17）

开发者：fpga-dev（本工作包唯一开发者）。日期：2026-10-17。
结论一句话：报告 §6 已从 pending 落成为完整小节（方案 A 否证、方案 B 成功一次全过 §4.1、run2 双复现裁定 PASS、CLI 复现结构性限制、候选与 T01 下一步入口）；主 README 增补 2026-10-17 当前入口块；tasks.json 仅 T01 刷新（blocked→active、references +4、status_note 刷新）；全部引用 SHA 磁盘重算核对。

1. 最终结论（可复用）：
   - **DDR1333 IP 产出方式定案**：CLI 引导配方（create+全参数注入）+ 一次用户在场 GUI Generate；**GUI 不计 headless 成功**（全自动 headless 仍不成立）。
   - **双复现判定方法可复用**：逐字节 diff + 字段级归一（run 目录串/时间戳/XML 属性序）；run1↔run2 60/64 逐字节一致、adc.log/drc/proc 三日志逐字节相同即强等价证明。
   - **CLI 复现结构性不可行**：预置真实 adc.log 于 staging 会在会话加载期被工具清除（`STAGING_ADC_EXISTS:0`）；最小复现单元＝CLI 冻结配方 + 一次 GUI Generate。
2. 文档同步：报告 §4.1/§5 加 2026-10-17 收束注记（保留原文）、§7 增补 2026-10-17 证据/候选/比对行；根 README 新增当前入口块（不删旧块）；tasks.json 仅 T01、JSON parse 自检过。
3. 入口：推荐候选 run1 `td2026_gui_bootstrap_20261017_000935\ip_out`（manifest `D71057F3…`）；run2 镜像 `9B3E5D00…`；集成输入=64 文件闭包+boot 文件；下游集成/STA/bit/CWC 与板验不在本 run。
