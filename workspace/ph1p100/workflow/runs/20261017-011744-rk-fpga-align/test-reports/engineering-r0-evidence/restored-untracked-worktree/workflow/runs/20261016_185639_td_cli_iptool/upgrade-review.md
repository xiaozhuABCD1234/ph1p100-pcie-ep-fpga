# TD 升级可行性审核（决策材料）

- run：`20261016_185639_td_cli_iptool`；角色：规划者续接（第2次）；日期：2026-10-16（21:00–21:4x，时间盒 ≤2h）。
- 触发：用户指令「先审核下升级是否能解决然后决定」。**本轮只审核：未下载、未安装、未执行外部脚本；未改 `D:\downlaod`、`D:\TD` 工作区与任何被冻结产物。**
- 结论分级：【事实】=本机只读读取/命令输出；【外部实测声称】=外部/队友材料中记录的实测（细节丰富且多份材料互证，未在我方环境复现）；【推断】=由事实推导；【未知】=无证据，附核实方法。
- **总结论：取决于条件（大概率能解决，但 4 个条件未闭环）；不升级的 GUI 路径是确定可行的保底。**

## 0. 结论速览

| 问题 | 回答 | 依据 |
|---|---|---|
| 升级 TD 能否解决 T01.tool-A（DDR1333 headless 生成）？ | **取决于 X（见 §7 条件）**：条件 1–4 全满足 → 大概率解决；任一不满足 → 退回 GUI 保底 | §1.2、§4 |
| 目标版本是否包含所需命令族？ | **是**【事实+外部】：6.2.3.210850 使用 `create_ip/get_ips/set_property/load_project_ips/generate_target`（两条独立材料）；我方 6.2.2 实测**未注册**该族 | §1.1、§1.2 |
| 对 DDR MC 的批处理覆盖与非交互 generate？ | **部分证实**【外部实测声称】：设置 ADC + `generate_target` 成功（IPT-1001、61 文件、proc 12 步/DRC PASS）；**完整参数注入（1333 档）从未被测**；MIPI_DPHY 为"批处理不产 RTL"反例 → 覆盖按 IP 而异 | §1.2 |
| 目标版本能否获得？ | **不可匿名获取**【未知】：官网需登录+权限申请、米联客需会员；本机无 2026.2 安装包（已全盘核实），仅有当前版安装器 | §1.3、§1.4 |
| 是否影响 "PH1P100 DDR3 800Mbps" 口径议题？ | **无直接影响**（器件手册口径与 TD 版本无关）；升级后"换档再生成"成本更低而已 | §6 |

## 1. 版本侧

### 1.1 外部/队友实际使用的 TD 版本【事实】

| 来源 | 版本证据 |
|---|---|
| 外部 fpga 仓库（clone `ref_ph1p100_fpga`，HEAD `654ef176…`） | `ph1p_pcie_ep_top.al`: `<TD_Version>6.2.3.210850</TD_Version>`、`<!-- Last modified by TangDynasty Release_2026.2 -->`；`create_project.tcl`/`download_sram.tcl` 用法 `/opt/anlogic/TD_Release_2026.2_NL/bin/{td.sh,bw.sh}`；`al_ip/ddr3_mc_0/ddr3_mc_0.v`：`App version: Release_2026.2`、`IpTool version: 2026.08(208212 2026/08/14)` |
| 本机同板/同人样本 `D:\TD\work\_peer_f9p_review_20261010\`（2026-10-10 拷入的队友 F9P 工程） | `fpga_prj.al`（SHA256 `224FF716…4D677`）同样 `<TD_Version>6.2.3.210850</TD_Version>`；`README.md`（SHA `5881189C…BA599`）「工具：Anlogic TD 6.2.3」；`gen_ip.tcl`（SHA `16627CAE…AFC5C`）为该工程 IP 生成脚本；`build.tcl`（SHA `0570DD91…00324`）headless：`import_device → open_project → reset_runs {syn_1} → launch_runs {syn_1 phy_1} -jobs 4 → wait_run ×2 → save_best_bits` |
| 我方本机 | `Release_2026.1_SP2`，构建 `6.2.2.200067`；IpTool `2026.03(193873 2026/03/31)`（本批 scaffold 头）；Tcl 8.6.15 |

⇒ 队友整套 IP 生成/构建经验建立在 **TD 6.2.3.210850（Release_2026.2，Linux `_NL` 包）** 上，与本机相差一个 release（2026.1_SP2 → 2026.2）。

### 1.2 6.2.3 的 IP flow 对 DDR MC 的覆盖与成功记录【外部实测声称 + 推断】

外部材料（规划者从 git 历史提取：`ref_ddr_ip_gen_fix.md`@`78174ba`、`ref_ddr_ip_gui_steps.md`@`675b8f7`、`ref_ddr_bringup_plan.md`@`a7417b3`；SHA 见 input-index §6.2）：

1. **命令与文档**：`create_ip -vlnv … -component_name …`、`load_project_ips`（`open_project` 之后必须）、`set_property <值> <名> <对象>`（顺序反 Vivado）、`get_property/get_ips`、`generate_target [get_ips …]`；SWUG105 2026.08 §4.4 有官文（外部引用）；对应 vlvn `anlogic.com:ip:MIS_DDRF6F1D0P0:1.2`。
2. **DDR MC 失败根因（外部 strace 级）**：实例 `PH1P_IO_ASSIGN`（ADC 引脚约束路径）为空 → `plugin_end.tcl → gen_adc.tcl` 的 `open $adc_file r` 抛 `couldn't open ""` → `IPT-1002 Generate target failed`。
3. **headless 成功记录（外部 H2，声称实测）**：`set_property CONFIG.PH1P_IO_ASSIGN <ap115_ddr3_x32.adc> [get_ips ddr3_mc_0]` + `generate_target [get_ips ddr3_mc_0]` → `IPT-1001 : The target has been generated successfully.`（rc=0），实例 6→61 文件、`_drc_check.log` 末行 `…the design rule check pass!`、`_proc.log` 12 步全 success；运行方式 `QT_QPA_PLATFORM=offscreen td.sh <script> </dev/null`（shell 级 headless）。旁证：其过程目录里另一会话产出的完整生成目录（52 `src/**` 文件 + 12 步 proc.log）。
4. **反例与未闭环**：
   - MIPI_DPHY IP（同版本、同机）批处理 `generate_target` **不产 RTL**（队友 README 实测，rc=1，只出 xml/params）→ 批处理覆盖**按 IP 而异**。
   - 「从零 `create_ip → 设置全部参数 → generate`」（其姿势A/§1.8）**从未完整实测**（H3 因操作失误作废；RAM IP 产 RTL 为独立实测）。
   - 其最终交付的 800E DDR IP 是 **GUI** 于 2026-08-14 生成（`ipGenVersion 208212`），Tcl 侧证据晚于产物、靠 10-15 实验补齐。
5. **对 DDR1333 关键点的覆盖判断**：
   - ADC/IO 分配 `PH1P_IO_ASSIGN`：**已覆盖**（H2 声称实测）；
   - 数值参数（`PH1P_DDR_SPEED/SPEED_BIN/COMP_TYPE/COMP_DENSITY/REF_CLK/IO_VOL/CWL` 等）：`set_property CONFIG.*` 在该版本上可写（MIPI 等实测；对 DDR 的完整值集只在未执行的草案里）→ **未闭环**；
   - 非交互 generate：**已覆盖**（DDR H2 + RAM IP 实测）；
   - 派生参数（CL/CWL/PLL/tCK）由 `Dependency.tcl` 在 generate 时重算（外部二进制/脚本级证据）——正可规避我方 6.2.2 的"手改实例取值回退"失败模式（H8 已坐实）。

⇒ 版本侧答复：**命令族与 DDR 主链路在 6.2.3 具备**；"完整 1333 参数注入 + generate"组合需本机最小实验闭环（§4 第 4 步）。

### 1.3 官方最新版本与获取渠道

- 官网（`https://www.anlogic.com/support/tools-downloads`，规划者联网核实 2026-10-16）：存在「软件工具 → TD Windows / TD Linux → **TD_6.2**」分类；但**下载需会员登录**；非注册仅提供部分 FamilyOverview 与老版 TD4.6.x。页面原文提示：如需权限，注册会员并完善信息后，把需求与注册手机号发 `web@anlogic.com` 由客服开通。
- 官方 FAQ（`tech.anlogic.com`）：TD 自带约 **6 个月免费 License**；过期/缺失可官网「工具与资料下载→软件工具→TD License」下载 → 新版 license 有正规补领通道。
- **最新版本号【未知】**：无法匿名核实 2026.2 是否仍为最新（已知最新使用版本 = 6.2.3.210850，2026-08 出现；是否已有 2026.3 未知）。核实方法：用户账号登录官网看 TD_6.2 列表；或向队友索取其持有的 `TD_Release_2026.2_NL`（注意其现证为 Linux 包，Windows 包可用性【未知】）。
- 米联客（`www.milianke.com/p-downloads.html`）：资料下载需会员/VIP；**本机已证**米联客板卡包附带 TD 安装器（§1.4），若其发布更新包可带出新版 TD。

### 1.4 本机/常见位置是否已有更新安装包【事实，全盘抽查】

| 位置 | 结果 |
|---|---|
| `D:\downlaod`（现行 6.2.2） | 当前版本本体；无更新包 |
| D 盘全盘 + `C:\Users\czz`（名称匹配 `TD_Release*/TangDynasty`，深度 ≤3–4） | **无 2026.2 或更新安装包**；无第二套 TD 安装 |
| `D:\TD\03_MLK_AFH03_AFC03\软件&驱动\TD_Release_2026.1_SP2_NL.exe` | **2,031,876,408 B（1.89 GiB）**，SHA256 `36e2368573d46207a32de0f5c02153273bc1416df575d71bd0012ac755bdc2b3` —— 与现行同版本（2026.1_SP2_NL，Windows）的**米联客随包安装器**，可作回退重装保障 |
| `D:\BaiduNetdiskDownload\03_MLK_AFH03_AFC03\…\TD_Release_2026.1_SP2_NL.exe.baiduyun.p.downloading` | 同安装器的百度盘下载缓存（同尺寸） |
| 环境 | Windows；D: 剩余 ≈272 GiB；无其他 TD 目录 |

## 2. 可行路径对比

### 2.1 就地升级 vs 并行安装

| 维度 | 就地升级（覆盖 `D:\downlaod`） | **并行安装（新目录，推荐形态）** |
|---|---|---|
| 冻结锚点 | 破坏性：工具哈希（td/IpTool/bw）、DB 版本、depot/Doc、license 目录、既有工程环境全部变化 | **保留**：6.2.2 原样；历史证据链（DB_VERSION=46207、工具 SHA、190248 depot 来源、bit/CWC）可继续复现 |
| 回退 | 需卸载/重装旧版（本机有同版安装器，但等于再动一次环境） | 弃用新目录即可；旧流程零扰动 |
| 结论 | 不推荐（等于重建整套冻结工具链） | 推荐（若升级）：双版本并存、绝对路径隔离、绝不混用 |

### 2.2 仅更新 IP depot（`D:\downlaod\ip`、`depotcache`）是否可行

【推断→明确否定】**不可行，对目标无帮助**：
1. 缺失的是 **TD 主程序注册的 Tcl 命令族**（`create_ip/get_ips/load_project_ips/generate_target`；外部二进制证据 `bin/td` 的 `IpGenerateTarget`/`IpToolProcessManager` 符号；我方 6.2.2 探针=未注册）——不在 depot 内，换 depot 不会出现这些命令。
2. depot 与 TD 版本绑定（`ipGenVersion`、`Dependency.tcl/upgrade.tcl`、`report_ip_status` 升级链）；向旧安装塞新版 depot 还会**污染现行冻结 depot 锚点**（Component.xml `FEB4F5BC…`、Dependency.tcl `CD927834…` 已入证据）。
3. `depotcache` 只是 catalog 元数据缓存，同理不提供命令能力；两版间 MIS depot 差异【未知】且与本卡点无关。

### 2.3 安装前提

- OS/磁盘：官方有 TD Windows 分支；安装器 1.89 GiB + 解包数 GB 级；D: 余量充足【事实】。
- License：现行 `D:\downlaod\license\Anlogic.lic`（SHA256 `DC19FEE62EFF532D4C6A84C04CE34267B03190B753A3198A6788C3EC9E45C1A6`；`# NODELOCKED license`，`FEATURE TD Anlogic 2027-03-31`，`HOST_ID = ANY`）**【推断】大概率可复用**（不绑定机器/版本）；若不认，走官网补领（§1.3）。
- 驱动：IP 生成与 CLI 构建不涉及 JTAG/下载；下载链（AL-LINK-FT、hwserver 5555）保持 6.2.2 不动。
- PATH：现行 PATH 含 `D:\downlaod\bin`（历史记录）；并行安装后**所有脚本一律绝对路径**，防止裸名解析到非预期版本。

## 3. 风险与本项目影响（重点）

### 3.1 冻结证据锚点与升级后的变化

| 现行锚点（6.2.2，【事实】） | 升级后变化 | 处置 |
|---|---|---|
| `td_commands_prompt.exe` SHA `79EC5667…F87190`；`td.exe` SHA `B7129888…DA2AFA`；`IpTool.exe` SHA `DA9E765E…A3DE46`；`bw.exe` SHA `FF57B653…B277D7`；`ph1_100p.db` SHA `8E7E8812…CF3AA2` | 新版各自新哈希【推断】 | 新候选记录新哈希；旧证据维持绑定 6.2.2，不回改 |
| 数据库格式：`Import design success TD_VERSION=Release_2026.1_SP2 , DB_VERSION=46207`（`docs/evidence/td_cli_commands_20261016.json` s3 阶段原文） | 新版 DB 版本号【未知】（大概率不同） | **不得跨版本混用 DB**：新候选全链（IP→综合→route→STA→bit→CWC）同版本闭环；6.2.2 的 DB/bit 只属旧候选 |
| 190248 私有 depot 来源 = `D:\downlaod\ip\depot\MIS_DDRF6F1D0P0_1.2` | 新装自带 depot 版本【未知】 | 6.2.2 侧不动；新版本用其自带 depot 并记录来源哈希 |
| CLI 约定/quirk（B 包 10 条，含 `save_best_bits` 在 6.2.2"接受但无产物"、exit 码双重语义、cwd 硬约束、中文路径不可用等） | 行为可能变化（队友 `build.tcl` 依赖 `save_best_bits` 在其 6.2.3 生效） | 升级后**重跑 B 套件**（`tools/td/verify_cli_e2e.py`）并对照 quirk 表更新 |
| CWC/BID 与 `check_chipwatcher_readback.py` 校验（002820，6.2.2 产物） | 旧产物不动；新版 CWC 格式差异【未知】 | 新版产物需先用独立核对重验读回工具，方可用于新候选 |

### 3.2 对既有工程/工具/调试链的影响

- **打开既有工程**：TD 打开旧工程可能改写 `.al`（外部 + 10-10 双重教训）→ 新版本**只开副本**；冻结工程（002820 等）保持只读；`.al` 先备份。
- IP 升级/锁定提示：旧 IP（IpTool 189136/171484 等）在新版本可能提示升级/锁定（`report_ip_status`/`upgrade.tcl`）；外部先例显示旧 IP 在新版可正常编译（不一定触发升级），但仍限副本内操作。
- ChipWatcher/BitWizard/JTAG：下载链继续用 6.2.2（不下载新驱动）；两版 BitWizard 并存时注意选对，本工作流不自动下载。
- 对 T01 现行候选：零触碰；新版本只服务**新候选（DDR1333）**。

### 3.3 混用版本约束（若升级）

- **首选**：新版生成 IP → 新版完整构建/STA/bit（全链同版本）。
- **需先实测**：新版生成的 IP 在 6.2.2 打开/综合（反向兼容未证；较新 `ipGenVersion` 可能触发升级/锁定）——如必须混合，先在副本 scratch 验证综合通过。
- **禁止**：同一候选的证据链跨版本拼接；跨版引用须显式标注来源版本。

### 3.4 对"跑通"验证体系的影响

- 新版本需登记：新 exe 哈希、Tcl 版本、DB_VERSION、日志路径/格式差异（`log/td_*.log` 惯例预计不变【推断】）、`reset_runs/save_best_bits/launch_runs` 行为复核。
- 既有 A/B 结论继续有效（绑定 6.2.2 与旧输入）；升级不追溯改旧证据；新候选按新锚点重记"三件套"。
- 报告与任务板需按"双版本工具链 + 每候选版本绑定"表述。

## 4. 升级后的最小验证序列与代价（若用户放行）

1. **安装**（用户操作）：新目录并行安装 2026.2/较新（**不覆盖** `D:\downlaod`）→ 启动 + license 检查（缺失则官网补领）。0.5–1h（下载另计）。
2. **命令注册探针**（15 min）：新 CLI 跑 `info commands` 探针（create_ip/get_ips/load_project_ips/generate_target/set_property/report_ip_status…）→ 落盘。
3. **小 IP 冒烟**（15–30 min）：scratch 工程 `create_ip`（如 AXIS FIFO/RAM）→ `set_property` → `generate_target` 产 RTL（只验命令族/流程）。
4. **DDR 生成闭环（关键，30–60 min）**：scratch `create_ip -vlnv anlogic.com:ip:MIS_DDRF6F1D0P0:1.2 -component_name ddrmc_x32` → `set_property` 全参数（1333.00 / DDR3-1333J / CWL7 / 50MHz / 1.35V / x16 / 2048Mb / `CONFIG.PH1P_IO_ASSIGN`=我方 `input_pins.adc` 本地化副本）→ `load_project_ips` → `generate_target` → 判据：`IPT-1001`、`_proc.log` 12 步 success、DRC PASS、文件数 ≥60、1333J/CL10/CWL7/PLL/70 引脚核对（沿用 dev-plan §4.1 生成成功分支验收）。
5. **CLI 六命令回归**（1–2h）：新版本重跑 `tools/td/verify_cli_e2e.py` 全套 → 新锚点 + quirk 对照。

**总代价估计：半天–1 天**（本会话工作 3–5h + 用户安装）。**风险：中低**（并行安装可回退；主要不确定 = 第 4 步完整参数注入一次成功率 + license 兼容）。
若第 4 步失败（仅默认值可生成、完整参数注入不可行）→ 升级收益缩水为"仍需 GUI 改参数 + CLI 生成"，与不升级的差距缩小，回到 §7 再决策。

## 5. 决策对比：升级（并行安装） vs GUI 人工生成

| 维度 | A. 并行安装 TD 2026.2 + 4 步验证 | B. GUI 人工生成（190248 包，用户在场） |
|---|---|---|
| 预期收益 | 打通 **headless/可脚本化** IP 生成：DDR1333 及后续任意变体可自动复现；对齐队友已验证配方；未来 IP 回归成本大降 | 立即拿到 DDR1333 候选 IP；6.2.2 GUI 流程零风险（190248 包 + 队友点击清单互证） |
| 成本 | 获取安装包（账号/渠道）+ 安装 + §4 验证（半天–1 天）；需用户操作安装 | 用户在场 1 次 GUI 会话（约 30–60 min） |
| 风险 | 新版对冻结体系影响（可控：并行+副本纪律）；完整参数注入一次成功性【未闭环】；license【推断可用】 | 不可自动化（参数一变即需再人工）；tool-A 验收维持"边界+人工路径" |
| 可逆性 | 高（弃用新目录；6.2.2 未动；旧安装器在手） | 高（无系统变更） |
| 证据体系影响 | 需新锚点 + 双版本纪律；旧证据不变 | 无变化；报告按"边界+人工"如实记录 |

若只能二选一：**短期解锁 T01（要 IP）→ B（确定性最高）**；**中期自动化/回归能力（"修缮"真正落地）→ A**。两者可先后进行（B 先出 IP、A 后补自动化），互不排斥。

## 6. 对 "PH1P100 DDR3 800Mbps 口径" 议题的影响

**无直接影响**【事实】：该议题是**器件手册口径**（`DS1300_PH1P_Datasheet_1.2.1.pdf` 表 3-60：PH1P100 DDR3=800 Mbps；本机 PDF95/印89 已核） vs 现役 1600、09 例程产物（1600）与板卡手册 800Mbps×32bit 的三方差异，与 TD 版本无关。升级不改变口径，也不改变 DDR1333/1600 目标资格；继续按 input-index §7.7 作为 T01 决策材料。附注：队友在 6.2.3 下选 800E 是为其自身批次需求与器件口径，**不是工具限制**。

## 7. 决策点清单（供用户）

1. **升级主决策**：是否获取并**并行安装** TD_Release_2026.2（≥6.2.3，新目录）作为新候选工具链？（条件：能拿到安装包；接受双版本纪律；接受 §4 半天–1 天验证）
2. **获取渠道**：官方账号（登录+权限邮件）还是米联客会员下载？或向队友索取 2026.2 包（**其 Windows 包可用性【未知】**；本机现无升级包）。
3. **保底安排**：是否先安排一次**用户在场 GUI 生成**（190248 包）先行解放 T01 的 DDR1333 IP（建议与第 1 项解耦）。
4. **若升级**：确认接受纪律——"新候选全链同版本 / 冻结工程只开副本 / 旧证据不迁移 / 新版工具哈希与 DB_VERSION 重新登记"。
5. **DDR 频点口径**（承接此前）：维持 1333/1600 还是向 800Mbps 器件口径收敛——独立议题；升级使"任意档位重生成"更便宜，可与 STA/板测数据一起定。

## 8. 证据来源索引

- 本机事实：`D:\downlaod\{bin,Doc,license,ip}`（版本/工具/许可/官方文档）；`D:\TD\work\_peer_f9p_review_20261010\`（队友工程样本：`fpga_prj.al`/`gen_ip.tcl`/`README.md`/`build.tcl`，SHA 见 §1.1）；`D:\TD\03_MLK_AFH03_AFC03\软件&驱动\TD_Release_2026.1_SP2_NL.exe`（SHA `36e23685…`）；`D:\TD\work\**\ipgen.log` ×33（DDR 相关=09 例程 + 本批 20 次尝试）。
- 我方 run 证据：`docs/evidence/ddr1333_iptool_cli_20261016.json`（A，20/20 尝试）；`docs/evidence/td_cli_commands_20261016.json`（B，含 `DB_VERSION=46207` 原文）；`lessons-learned.md`（A/B 结论与边界）。
- 外部材料（temp 只读）：`ref_ph1p100_fpga`/`ref_ph1p100_driver`（clone）与提取文档 `ref_ddr_ip_gen_fix.md`（@`78174ba`）、`ref_ddr_ip_gui_steps.md`（@`675b8f7`）、`ref_ddr_bringup_plan.md`（@`a7417b3`）、`ref_cam_frame_pcie_verify.md`（@`78656bc^`）；SHA 见 input-index §6.2。
- 官方页面（规划者联网，2026-10-16）：`www.anlogic.com/support/tools-downloads`、`tech.anlogic.com`（License FAQ）、`www.milianke.com/p-downloads.html`。
- 规划者 6.2.2 探针（命令集缺口）→ H6 已由开发者 `_validation` 复跑并落盘于 A 证据。

---

### 附：本审核的"事实/推断/未知"总表（简）

| 条目 | 分级 |
|---|---|
| 队友两仓库与本地样本均用 TD 6.2.3.210850（Release_2026.2） | 【事实】 |
| 6.2.3 注册 create_ip/get_ips/set_property/load_project_ips/generate_target | 【事实（外部两条互证）+ 我方 6.2.2 反证】 |
| DDR MC：设置 ADC + generate_target 可产完整 IP（IPT-1001/61 文件） | 【外部实测声称（含旁证）】 |
| DDR 完整参数注入（1333 档）一层成功性 | 【未知/未闭环】（需 §4-4 本机实验） |
| MIPI_DPHY 批处理不产 RTL（同版本反例） | 【外部实测声称】 |
| 最新官方版本号（是否已有 >2026.2） | 【未知】（官网需登录；方法=用户账号或问队友） |
| 本机无 2026.2 安装包；仅现行版安装器 | 【事实】 |
| license（NODELOCKED/2027-03-31）可被新版复用 | 【推断】（未装前无法证实；有官网补领通道） |
| 新版 DB/CWC 格式变化、反向兼容 | 【未知】（升级后以实测登记） |
| 800Mbps 器件口径与版本无关 | 【事实】 |
