# input-index — T01 DDR1333 IP 集成与 1333/1600 对比数据（run 20261017_153201_T01_ddr1333_integration）

规划者核实日期：2026-10-17（全部只读）。SHA 除注明「引自」外均为规划者本轮磁盘复算值；「引自」=既有记录锚，本轮未复算。本索引给出本次需求材料、现行证据、可复用资产与写权限；「核实结论」标注规划者独立核对结果（与 requirement.md 注记差异以本文件为准）。

## 1. 需求材料与约束

| 材料 | 路径 | 要点 |
|---|---|---|
| 本次需求 | `workflow/runs/20261017_153201_T01_ddr1333_integration/requirement.md` | 4 项：①DDR1333 IP 集成（新候选、不碰 002820、除 IP 外等值）；②构建+同口径对比表+0.300ns 如实评定；③bitgen/CWC 可选；④频点终选留给用户 |
| 项目约束 | `AGENTS.md` | 禁止批量删除（逐文件）；默认工作流；DeepSeek 边界 |
| 工作流说明 | `workflow/FPGA多智能体工作流_使用说明.md`、`workflow/README.md`（§5.1 候选交付必检项） | 批=1 开发+3 测试；三维验收；候选交付清单 |
| 任务板 | `workflow/tasks.json` | T01=active（并行线持续更新）；观测 SHA `91CDFE22539FF222017006401CF7515990164B1CEF90F1F083ECF51B0573F73E`（2026-10-17 规划时点） |
| 报告/传输约定 | `.agents/skills/fpga-orchestrator/references/{report-contract.md,relay-contract.md,project-context.md}` | 三维报告格式；主只传元数据 |

## 2. 核实结论（独立核对 requirement.md 注记）

| 注记/假设 | 核实结果（本轮只读） |
|---|---|
| 002820 的 ddrmc 实例/接线 | **确认**：`camera_ddr_display_top.v`(top) → `ddrmc_display_top u_ddrmc_test_top` → `ddrmc_x32 u_ddrmc_x32`（ref_clk=sys_clk50m；PAXI 直连 `camera_rgb565_display_guarded u_capture`；usr_ref_type=00/usr_ref_req=0）；注册=`add_files ./vendor/ip/ddrmc_x32/ddrmc_x32.xml` |
| 新 IP 闭包（run1）可作集成输入 | **确认且补充**：64=61 闭包+3 日志，自包含；**无需 depot 无关化**（构建不访问 depot/`D:\downlaod`）；**SDC 无差异**（`src/sdc/ddrmc_x32.sdc` 新旧逐字节一致 `ADB63179…`）；`src/adc/ddrmc_x32.adc` 亦逐字节一致 `75199743…`；boot `.al` 仅旁证（`<IP_FILE>` xml 形态与 build tcl 一致），**不入派生输入** |
| 集成=替换闭包即可？ | **基本成立+1 个注意点**：`ddrmc_x32` 模块端口 53 行新旧**完全一致**、IP 内实例名（`ph1p_ddrmc_wrapper`/`ph1p_ddrmc_top`）保持 → 项目 RTL/SDC 零改动；**注意 wrapper 文件更名**（`ph1p_ddrmc_wrapper_ddrmc_x32.v` → `ddrmc_x32_ph1p_ddrmc_wrapper.v`，模块名同步改），由 `ddrmc_x32.v`+`.xml` 内部一致更新，替换须整体进行 |
| 新旧 IP 差异范围 | **量化**：60 个同名文件中 33 逐字节一致、**27 个不同**（6.2.3 全量再生成：phy/mc/timing/top/params/Design/xml/sim fileset 等；清单见 guide §2）；+wrapper 更名 1 项 |
| 参数（1333 档） | **确认**：`.params`=1333.00/DDR3-1333J/CWL7/tCK1500；`.m_params`=CL10、PLL0 50×(80/3)/2=**666.6667MHz 物理 CK≤666.667**、PLL1_REFCLK_FREQ=166.7（用户域 5ns→约 6ns）、H4/BANK33/IO1.35/x16/2048/REF50；`PH1P_IO_ASSIGN` 指向 run1 引导 `input_pins.adc`（F0904238…，保留不改） |
| 派生机制（安全派生不碰 002820） | **由既有脚本模式核清**：`prepare_rgb565_white_balance.py`/`prepare_rgb565_timing.py` 先断言 BASE manifest+bit+条目数、逐项 SHA 复算，再 `mkdir(exist_ok=False)` 复制并做**受控替换**，写 changes/overlay+新 manifest，最后自拷贝 frozen 脚本。本批沿用该模式（差异集恰 64 文件，可全量断言；不做路径重定位） |
| `run_rgb565_native.py` 可否直接用 | **不可**：硬编码 `D:/downlaod/bin/td_commands_prompt.exe`（6.2.2）且工程名/路径断言为 6.2.2 流程；本批按同一断言强度**新写** `tools/td/run_rgb565_ddr1333.py`（锚 6.2.3 CLI，见 guide §3） |
| 0.300ns 口径来源 | **确认**：`docs/RGB565时序裕量优化_2026-10-15.md` 首轮目标「最终 setup 裕量至少 0.3 ns」；判定= `tools/td/check_timing_margin.py`（Routed+显式组数+Routed 端点 0+STNS/HTNS=0+hold/period≥0）；114913 为实现期预留实验（guard −0.477→nominal −0.177，差 0.300）。**非器件保证**；本轮 nominal 口径如实评定 |
| 002820/1600 历史数据（同口径字段） | **确认**：002820=setup0.000/STNS0、hold0.020、period2.200、66 组（`candidate_timing.rpt B2A78335…`；route `capture_timing.rpt C82A0385…`）；103222/111134/114913=0.001/0.008/−0.177、68 组（`docs/evidence/camera_rgb565_timing_20261015_*.json`）；**全部 6.2.2** → 与 6.2.3 新数据对比存在工具版本混杂，故 E2b 控制（002820@6.2.3）为公平对比的必要件 |
| 6.2.3 构建注意点 | **确认**：CLI `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe` `2629E474…C1223`；license `DC19FEE6…45C1A6`（缺失→RUN-8008）；arch `ph1_100p.db` `939EC294…F77B`；DB_VERSION=46207；绝对路径/cwd=工程/正斜杠；全链同版本纪律；6.2.2 与 `run_rgb565_native.py` 冻结不动 |
| 上一 run §6.5「64 文件闭包+boot 文件」是否充分 | **充分**（构建用）；补充 mapping 规则（日志落 `vendor/ip/*_*.log` 名；wrapper 更名）与"boot 不录入"结论；无需 depot/SDC 处理，「替换闭包+日志」即闭合 |
| tasks.json 并行漂移 | **确认**：本轮观测 `91CDFE22…`（与上一 run 收尾时的 `9513250E…` 不同，主日志已登记漂移映射）；E3 更新仅动 T01 并记录观测时点 |
| 规划者新发现 | ①`vendor/ip/RTL/**`（2 文件）与 `vendor/adc/ap115v2.adc` 为未被构建引用的历史遗留（仅 manifest 收录）→ 派生时原样保留（等值豁免）；②最终报告端点组数将随 6.2.3+新 IP 再变，须**人工复核后显式设定**给 gate（禁止自证完整性）；③`camera_ddr_capture_top.v` 的 ROM 路径指向 002820 自身（非 build 引用文件）→ 为实现"差异集恰 64 文件"，本批**不做路径重定位**（002820 持久冻结，引用有效） |

## 3. 输入清单（按组；锚点）

### 3.1 冻结基线 002820（只读）

| 项 | 路径 | SHA256 |
|---|---|---|
| manifest（220 项） | `D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820\input_manifest.json` | `8F8E4EFE9B9320CBC595F94E337395744DBD957630576123576EE2C357F9A1C8` |
| bit | 同上 `camera_ddr_display.bit` | `4d591c31da9a71b9c261972e5089930af3e441c2096ed37736c8d2340ddd8865` |
| 最终 STA 报告（bitgen 阶段） | 同上 `candidate_timing.rpt` | `B2A78335DC14B8F96335340E227375C090A18EB39BB4114C529576381FCCC556` |
| route STA 报告 | 同上 `capture_timing.rpt` | `C82A03857466397DA585013DDC8B6E491F154A016473DB2E603DFB9CE0220CDB` |
| 构建脚本 | `build_rgb565.tcl` / `route_rgb565.tcl` / `bitgen_rgb565.tcl` | `5AA25FD2…129288F9` / `019DB289…72BB5489` / `FCCE5E20…AF4D64201`（后 3 组为完整：`5AA25FD23B3D73D061B86CF82092F8C35E7BC9BA3B8D2B769243F071129288F9`、`019DB289DEC71867C51AF16B334C1E0EFB19A4B1D57A3E4E5870E8C672BB5489`、`FCCE5E2088E523A2B9B5F91633B172C411058CC382AF8A2393D05E7AF4D64201`） |
| 约束 | `timing.sdc` / `board.adc` | `0C32C5F7A536BBC811901D5AF254A4FDDC270DCDD2B59C16CAEB006EF0F7FE1C` / `1CB30346FA17DA6BB0E77802CA72C4B4BB4AECC1445711E19391CF4EE2271580` |
| 旧 IP 闭包关键锚 | `vendor/ip/ddrmc_x32\ddrmc_x32.xml`、`ph1p_ddrmc_wrapper_ddrmc_x32.v`、`.params`、`.m_params`、`src/adc/ddrmc_x32.adc`、`src/sdc/ddrmc_x32.sdc` | `758877FA…4526AC`、`66BBE13C…69EBCC`、`CC6754EB…8D51F89`、`88F924C0…04ED6F32`、`75199743…09C0BAA`、`ADB63179…AED428D6` |
| 阶段记录 | `native_{build,route,bitgen}.json/.txt`、`white_balance_overlay.json` 等 | route STA：setup 0.000/STNS 0、hold 0.020/HTNS 0、period 2.200；build≈2.3min、route≈16.7min（6.2.2） |

### 3.2 新 IP 候选（本次集成对象，只读）

| 项 | 路径 | SHA256 |
|---|---|---|
| run1 闭包根（推荐冻结） | `D:\TD\work\csi2\_validation\td2026_gui_bootstrap_20261017_000935\ip_out\` | `candidate_manifest.json`=`D71057F3E3B859AD34BBEC477232938A8AA6DE8BBDDF04AE1C75605074C08434`（64 文件） |
| 关键文件（run1） | `ddrmc_x32.xml` / `ddrmc_x32.v` / wrapper / `.params` / `.m_params` / `Design.xml` / `src/adc` / `src/sdc` | `92155F9D…B8B606` / `7EDEF919…35A326B0` / `609F3C60…E28FB6` / `86D1C0B6…7B38A2F` / `6401066A…B8A40FFB` / `72F2BB57…ED5AE24F` / `75199743…09C0BAA` / `ADB63179…AED428D6` |
| 三日志（run1） | `ddrmc_x32_adc.log` / `_drc_check.log` / `_proc.log` | `C50695DF…C229FF` / `75721975…E68537E` / `9C1CDF4B…026686F` |
| run2 等价镜像 | `D:\TD\work\csi2\_validation\td2026_b_run2_20261017_143128\run2_candidate_manifest.json` | `9B3E5D002B6C433726AE2FE703EE40F9F1CE933E494F95712CC3173ACD09D716`（64 文件；60 逐字节+4 字段级非实质） |
| 引导目录辅助件（只读） | 同上引导根 `input_pins.adc` / `ddr1333_proj_boot.al` / `open_ddr1333_gui_6.2.3.cmd` 等 | `F0904238…3C08DB33DA` / `EF721C4DC9F3DE2038D50203046E6D5EEBA41703DFCA55B46400EB8838DB7210` |
| 证据 | `docs/evidence/td2026_gui_bootstrap_20261017.json` / `td2026_ddr1333_generate_20261017.json` / `td2026_ddr1333_accept_20261017.json` / `td2026_b_run2_20261017.json` | 引自报告 §7：`741E909D…` / `1B5CE403…` / `B85A2405…` / `A60F2166…` |

### 3.3 1600 探索证据（历史对照，只读）

| 项 | 路径 | 要点 |
|---|---|---|
| 时序优化记录 | `docs/RGB565时序裕量优化_2026-10-15.md` | 三轮结果 0.001/0.008/−0.177；0.300 目标出处；基线瓶颈与结构改善记录 |
| 时序证据 JSON | `docs/evidence/camera_rgb565_timing_20261015_{103222,111134,114913}.json`（57/58/62KB） | native build/route 记录、STA 字段、guard 段（114913） |
| 白平衡基线证据 | `docs/evidence/camera_rgb565_wb_20261015_002820.json`（92KB） | 002820 自身 G1/G2 记录 |
| 判定工具 | `tools/td/check_timing_margin.py`、`tools/td/test_timing_margin.py` | 0.300 gate 与负对照 |
| DDR1333 生成依据 | `docs/DDR1333候选评估与生成入口_2026-10-15.md`、`docs/DDR1333_IPTool再次尝试与人工操作_2026-10-15.md` | 参数依据（CL10/CWL7/1333J/物理 CK 上限）、§5 恢复验证顺序 |

### 3.4 工具锚点

| 项 | 值 | 说明 |
|---|---|---|
| 6.2.3 CLI | `D:\anlogic\TD_Release_2026.2\bin\td_commands_prompt.exe` = `2629E474DF036A871807E564190FEBFBBD9780A09365F600C10463911C8C1223` | **本批唯一执行工具**；runner 断言 |
| 6.2.3 其他 | `td.exe`=`FA2A5AC6E5342B2F801EFA7A6AA345A5FD02D6F25FFA0D1E6380FF0EBD306A87`；`IpTool.exe`=`5B0654AAA44AE9340EEFCDC8CAC54FAED7490B0643F3FA53908C5706DB175CEC`；`arch\ph1_100p.db`=`939EC2948F40546C9C545786AF96AB4CB007A5ECF063F133DA2B7835983FF77B`；`license\Anlogic.lic`=`DC19FEE62EFF532D4C6A84C04CE34267B03190B753A3198A6788C3EC9E45C1A6` | DB_VERSION=46207；空 license→RUN-8008（历史） |
| 6.2.2（冻结对照，不执行） | `D:\downlaod\bin\{td_commands_prompt,IpTool,td}.exe` | 引自报告 §7：`79EC5667…87190` / `DA9E765E…A3DE46` / `B7129888…DA2AFA`；MIS depot `FEB4F5BC…`（只读） |
| 安装/生成证据 | `docs/evidence/td2026_install_20261016.json`（`EF5545CC…` 引自报告）、`td2026_ipgen_20261016.json`（`A9D0B9B0…` 引自报告）；安装包 `C:\Users\czz\Downloads\TD_Release_2026.2_NL.exe` `3B92ABE8…751A0A`（引自） | 6.2.3 就位与四步验证记录 |
| 上一 run 报告 | `docs/TD_CLI_IpTool修缮与验证_2026-10-16.md`（`ED59CF1E…` 引自 main-log） | §6 结果、§7 锚点索引 |

### 3.5 接口/脚本索引（本批相关）

| 项 | 路径 | 用途 |
|---|---|---|
| 派生模式范本 | `tools/td/prepare_rgb565_timing.py`（5915B）、`prepare_rgb565_white_balance.py`（`85808147…`） | E1 新脚本 `prepare_rgb565_ddr1333.py` 的断言/overlay 模式来源 |
| 执行模式范本 | `tools/td/run_rgb565_native.py`（`5196D62D…`，6.2.2 冻结） | E2 新 runner 的断言下限（不得削弱） |
| 上一 run 脚本 | `tools/td/prepare_ddr1333_ip.py`（引自报告 `2D345898…`）、`run_ddr1333_ipgen.py`（`B44E065C…`，本轮复算） | IP 生成侧历史（本批不执行） |
| 文档 | `tools/td/README.md`、`docs/TD命令行使用说明.md` | CLI/runner 用法与 quirk |
| 三维/证据约定 | `.agents/skills/fpga-orchestrator/references/report-contract.md`；`workflow/README.md` §5.1 | 报告格式与候选交付必检项 |

### 3.6 C4 / 800E 相关输入（供 E3 对比材料引用）

**触发**：requirement.md 附录（2026-10-17，用户澄清+主调度核实）——队友 DDR IP=**DDR3-800E / CL6 / CWL5 / x32 / AXI=1**（GUI 2026-08-14 生成；选 800E=批次需求+器件手册口径）；我方现役=**1600K / PAXI=1**；统一路径建议=以我方 csi2 为主线引入其 PCIe 后端，**C4（DDR IP 定案：800E/AXI vs 1600K/1333）待决**；本轮约束=同架构（PAXI、我方工程）下 1333 vs 1600 对比，**800E/AXI 为 C4 第三候选、不在本批实施**。

| 来源 | 路径 | 要点 |
|---|---|---|
| 本 run 附录 | `workflow\runs\20261017_153201_T01_ddr1333_integration\requirement.md`（2026-10-17 附录） | 上述澄清与约束原话 |
| 统一路径评估 | `workflow\runs\20261016_2110_pcie_unified_path\pcie-unified-path-assessment.md` | C4 行（800E/AXI vs 1600K/1333：两案带宽都够，差异在既有验证资产/时序目标/IP 生成入口）；I4=推帧读源适配面；C3=4KB 对齐/尾突发；T5=复测范围；R3=AXI 4KB 尾块；§2=队友资产 |
| 统一路径增量 | `workflow\runs\20261016_2110_pcie_unified_path\pcie-unified-path-addendum-20261017.md` | C4 未动（其 `al_ip/**` 仍未改：800E/AXI/PAXI=0；我方 1333 解锁后 C4 仍无新信息）；其新提交自述 0 violation、未改 `al_ip/**`；N3=双路推帧单引擎 |
| 上一 run 升级审核 | `workflow\runs\20261016_185639_td_cli_iptool\upgrade-review.md` §6 | 800Mbps 器件口径与 TD 版本无关；其 800E 为 GUI 2026-08-14 生成（非工具限制）；升级使换档再生成成本更低 |

**队友 IP 配置锚（只读；2026-10-17 本地副本复算）**：

| 项 | 值 |
|---|---|
| 位置 | 本地只读副本 `C:\Users\czz\AppData\Local\Temp\opencode\ref_ph1p100_fpga\al_ip\ddr3_mc_0\`（克隆 HEAD `654ef176e983711436432e7a7d29af744754977d`；仅参考，未并入本项目） |
| `Design.xml` | `4D7060F8877717B82E4E547617C80178C369A6C296A21827EB057A7A2EC551C0`（800E/CL6/CWL5/x16 2048Mb/×32；`PH1P_MC_AXI=1`、`PH1P_MC_PAXI=0`；refclk 50MHz；DRC PASS） |
| `.params_ddr3_mc_0.txt` | `ED062B1DC0BC6576A750335FE35F6DC0C38437F34EB1AE519E486D84C7670A71`（`PH1P_DDR_SPEED=800.00`、`PH1P_SPEED_BIN=DDR3-800E`、`CWL=5`、`tCK=2500`；`PH1P_IO_ASSIGN` 为 Linux 路径 `/mnt/nvme/…/golden_adc/ap115v2_ddr3_x32.adc`） |
| `.m_params_ddr3_mc_0.txt` | `535E28148B07FD73EE6B6D03D47F02E5E178022D7B66B30AF8F391E27C058C21`（`CL;6`、`CWL;5`、`PLL0_REFCLK_DIV;2`/`FBK;48`/`CLK2;3`→物理 CK 400MHz；`MC_DATA_WIDTH 256`、`AXI_DATA_WIDTH 256`） |
| `src/adc/ddr3_mc_0.adc` | `751997438BD28E2A956864493B3083008E1458878263DD709A569FECA09C0BAA`（**与我方 002820 及新 1333 闭包 `src/adc` 逐字节相同**——同一块板引脚表） |
| 生成信息 | `ipGenVersion 208212 2026/08/14`（GUI 生成；TD 6.2.3/Release_2026.2，与其仓库 `ddr3_mc_0.v` 头一致；引自前评估，本轮副本复算一致） |

**接口差异与带宽（对比材料口径）**：

- 接口：队友=**AXI4 256bit**（`PH1P_MC_AXI=1/PAXI=0`，`AXI_ADDR_WIDTH 29`）；我方=**原生 PH1P PAXI 256bit**（`AXI=0/PAXI=1`；`ddr_frame_store.v` 明示非标准 AXI）。C4 若选 800E/AXI，迁移面=I4（推帧读源：AXI 4KB 突发 vs PAXI 握手/字节序/仲裁）、C3（4KB 整数倍对齐/尾突发）、T5（双路+25% 余量复核）——**不实施承诺，只在 E3 材料列明**。
- 带宽（理论峰值；未扣仲裁/刷新/事务开销；引自统一路径评估 C4 行）：`800E×32≈3.2GB/s`；`1333×32≈5.33GB/s`；`1600×32≈6.4GB/s`。双路1080p30 packed RAW10 预算 155.520MB/s（+25%=194.400MB/s），2R+2S 约 622–778MB/s——**800E 带宽亦够（计算值，未实测）**。
- 标注：本小节输入**仅供 E3 对比材料/报告引用**；E1/E2 技术范围不变（仍为 002820→1333 替换 + 1600ctl 控制，PAXI 架构）。

## 4. 所有者与写权限索引（本批）

| 路径 | 所有者 | 本批权限 |
|---|---|---|
| 新建 `D:\TD\work\csi2\prj\camera_rgb565_ddr1333_*`、`camera_rgb565_ddr1600ctl_*` | E1/E2 开发 | 只新建（`exist_ok=False`） |
| 新建 `tools/td/prepare_rgb565_ddr1333.py`、`run_rgb565_ddr1333.py` | E1/E2 开发 | 新建（不削弱断言） |
| 新建 `docs/evidence/ddr1333_integration_<date>.json`、`ddr1333_build_sta_<date>.json` | E1/E2 开发 | 新建（不改既有证据） |
| 新建 `docs/DDR1333集成与1333vs1600对比_<date>.md`；增补 `tools/td/README.md` | E3 开发 | 新建/增补 |
| `workflow/tasks.json` | E3 开发（仅 T01） | 最小 diff；改前记录观测 SHA；JSON 自检 |
| `D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820` 及其余 `prj\*`、`_validation\*`、`D:\downlaod`、`D:\anlogic`（只读使用）、golden ADC、既有 `docs/evidence/*.json`、既有 RTL/IP、其它工作树、`parallel/` | 冻结资产/历史会话 | **只读** |
| 本 run 目录 | 本 run 规划/开发/测试 | 计划与 test-reports 写入 |

## 5. 未决事项

1. 1333/1600/800 频点终选与「DS1300 表 3-60 PH1P100 DDR3 800Mbps」资格差异——**后续用户决策**；本轮交数据与建议；C4（800E/AXI=第三候选，含 PAXI→AXI 迁移）同属后续决策，材料见 §3.6。
2. bitgen/CWC 可选延伸是否实际执行——条件见 dev-plan §4.2（STA 全项非负+时间允许）。
3. 6.2.3 全链在本工程的首次真实构建——E2 回答（历史仅 scratch 回归与 IP 生成为 6.2.3）。
4. 最终 STA 报告端点组数（002820=66、timing 轮=68 → 本轮需人工复核后显式设定）——E2 回答。
5. `workflow/tasks.json` 并行线持续更新——E3 按观测时点更新 T01（观测 `91CDFE22…`）。
6. 上板/颜色 G3/G4、亮点、长稳——不在本批（无硬件动作）。
