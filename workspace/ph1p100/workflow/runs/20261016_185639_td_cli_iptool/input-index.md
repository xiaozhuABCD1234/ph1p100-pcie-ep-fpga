# input-index — TD CLI / IpTool 修缮与验证（run 20261016_185639_td_cli_iptool）

规划者核实日期：2026-10-16（全部只读）。本索引给出本次需求的材料、现行证据、可复用资产与所有者/写权限；"核实结论"标注规划者独立核对结果（与 requirement.md 侦察注记的差异以本文件为准）。

## 1. 需求材料

| 材料 | 路径 | 状态/要点 |
|---|---|---|
| 本次需求（用户原话+注记） | `workflow/runs/20261016_185639_td_cli_iptool/requirement.md` | 三项交付：IpTool 设置修缮并跑通；写报告；其他 TD CLI 命令核验 |
| 项目约束 | `AGENTS.md` | 禁止批量删除（逐文件）；DeepSeek 委派边界；默认工作流入口 |
| 工作流说明 | `workflow/FPGA多智能体工作流_使用说明.md` | 批=1 开发+3 测试；run 产物清单；报告约定 |
| 任务板 | `workflow/tasks.json` | T01=blocked，阻塞点=DDR1333 生成入口；本次报告/证据将挂在 T01.tool-* |
| 项目入口导航 | `.agents/skills/fpga-orchestrator/references/project-context.md` | T 任务↔F 工作包映射；D 盘活动工程与边界 |
| 报告约定 | `.agents/skills/fpga-orchestrator/references/report-contract.md` | 三维报告格式与判定规则 |

## 2. 核实结论（对侦察注记的独立核对）

| 注记 | 核实结果 |
|---|---|
| IpTool.exe 用法草案（`-gen/-user/-complete` 等） | **确认存在但为转写版**：实际 usage 顺序为 catalog 形态→`-gen`/`-user` 形态→`-complete` 形态；`-tcl/-source/-nogui/-no_status/-qcerr/-gen_with_app` 等为独立选项串（规划者直接从二进制提取复核） |
| `-tcl -source` 诊断可用、copy 生成失败、`-qcerr` 20s 超时 | **全部确认**（见 `docs/evidence/ddr1333_ip_retry_20261015.json` 与两份 DDR1333 文档） |
| ipgen.log 成功记录 | **确认**，但两者都是 **GUI 动作记录**（`ipgen_gui_*`→`#IP Gen Succeeded`），不是 headless CLI 证据；输出为 `D:\TD\work\test\al_ip\PCI_ExpressF6F1D0D0_0\` 与历史 `F:/al_data/...` |
| verify_cli.tcl 六命令注册自检 | **确认**；2026-10-10 通过；但"注册"≠"端到端跑通"，后者由 T01.tool-B 补 |
| TD 命令行使用说明 | **确认**：正斜杠/退出码不可单证/显式标记/中文路径不可用；2026-10-10 版本 |
| 机器约束（D 盘 ASCII、禁止批量删除、不改 downlaod、保护冻结候选） | **确认**；既有 `_validation` 100+ 目录，实验必须全新目录 |
| 官方依据路径 | **确认存在**：IPUG034（v1.4，53 页）、SWUG105（2026.01，109 页）、TD_User_Guide_V6.2；**两者均不记载 IpTool headless 生成**（IPUG034 只有 GUI 定制流程；SWUG105 只有实现流 Tcl） |
| 规划者新发现 | IpTool 二进制注册命令串含 `generate_ipinst`（未开库时不激活，可作受控重探）；含 `xmlgenip/generate_gate/plugin_end.tcl/runTclTask` 串；TD CLI 内 `xmlipgen` 命令在工程上下文存在但 `-help` 无效（10-10 已记录，不可据名字宣称可用） |

## 3. 现行证据（本次相关）

| 证据 | 路径 | 状态 |
|---|---|---|
| DDR1333 生成入口前轮现场 | `docs/DDR1333候选评估与生成入口_2026-10-15.md` | 165740 准备+两次超时；参数依据（CL10/CWL7/1333J、70 引脚、tCK） |
| IpTool 再次尝试与人工操作 | `docs/DDR1333_IPTool再次尝试与人工操作_2026-10-15.md` | 190248 人工包完整步骤与停止条件；GUI 未启动 |
| 重试证据 JSON | `docs/evidence/ddr1333_ip_retry_20261015.json` | copy+`-tcl` exit1 零产物；`-qcerr` 20s 超时；197 项 SHA；独立审阅通过；边界清单 |
| 前轮证据 JSON | `docs/evidence/ddr1333_ip_regeneration_20261015.json` | 两次不带 `-tcl` 的超时（45s/30s） |
| TD CLI 使用说明 | `docs/TD命令行使用说明.md` | 六命令注册、批处理用法、正斜杠/退出码/标记约定 |
| TD 命令探查原始记录 | `tmp/probe_ip_cli.log`（273 KB，含大量命令帮助）、`tmp/probe_project_ip_cli.log`（工程上下文：`xmlipgen` 存在）、`tmp/probe_xmlipgen.log`（`-help` 空）、`tmp/iptool_help.log`（0 字节） | 10-10 探索；**注意**：`probe_project_ip_cli` 曾从仓库目录打开 D 盘工程触发路径错误并改动了 .al（后恢复）——教训：先复制再打开 |
| 10-10 结论记录 | `docs/RAW10稳定档位_PLL生成与接入交接.md`（第 149/153 行） | `create_ip/get_ips/get_ipdefs/generate_target/load_project_ips` 不存在；`xmlipgen/ipgen_synip` 名字存在但不可用；IpTool `-help` 无结果 |
| 002820 六 native 阶段证据 | `D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820\native_*.json`（build/route/inspect/audit_hdmi/bitgen/export_debug） | 全部 accepted（含 bitgen，2026-10-15 00:59）；证明六命令中多命令已在真实工程被使用，但无逐命令专项核验 |
| 时序轮次记录 | `docs/RGB565时序裕量优化_2026-10-15.md`、相关 `docs/evidence/camera_rgb565_timing_*.json` | 103222/111134/114913 背景；002820 route 走 native import_db（管理器历史问题线索） |
| T01 任务与记录 | `workflow/tasks.json` T01、`workflow/records/T01/`、`workflow/records/T01/handoff.md`、`workflow/records/T01/board-run.md` | blocked/awaiting_hardware 现状与入口 |

## 4. 可复用资产

| 资产 | 路径 | 用法/所有者 |
|---|---|---|
| 2026-10-15 人工 GUI 包（只读复用） | `D:\TD\work\csi2\_validation\ddr1333_ip_20261015_190248`（depot/、source/、output/、open_ddr1333_gui.cmd、input_pins.adc、manual_binding_guard.tcl、retain_ip_path.tcl、preparation*.json） | 197 项 SHA；GUI 未启动未验证；作为实验输入源与人工回退路径 |
| 准备脚本（本批将修改） | `tools/td/prepare_ddr1333_ip.py` | 断言基线/70 引脚/depot 哈希/保留式清理，`argv` 自标 inferred、未执行；T01.tool-A 修复对象 |
| 前轮冻结准备脚本 | `D:\TD\work\csi2\_validation\ddr1333_ip_20261015_190248\frozen_prepare_ddr1333_ip.py` | 与仓库版本对照的历史锚点 |
| 保留式清理/绑定 guard 模板 | 同上 `retain_ip_path.tcl`、`manual_binding_guard.tcl` | 私有副本清理（禁删）；可作新实验模板 |
| CLI 注册自检 | `tools/td/verify_cli.tcl` | 只读；T01.tool-B 作为基线重跑对象（不修改） |
| runner 范本（记录/标记/超时/哈希） | `tools/td/run_rgb565_native.py`、`tools/td/run_white_balance*.py` 等 | 退出码+标记+产物哈希+超时的既有格式范本 |
| 构建/bitgen Tcl 范本 | `tools/td/build_raw10_stable.tcl`、`tools/td/bitgen_camera_ddr_display.tcl`、`D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820\build_rgb565.tcl`/`route_rgb565.tcl`/`bitgen_rgb565.tcl` | 命令顺序与 catch/exit 风格范本 |
| 成功产物形状参考 | `D:\TD\work\test\al_ip\PCI_ExpressF6F1D0D0_0\` | 生成 IP 文件清单对照（GUI 产物） |
| 成功记录参考 | `D:\TD\work\test\log\ipgen.log`、`D:\TD\work\peripheral\09_ddr3_ddrmc_cal_x32_1066mbps\prj_td\log\ipgen.log` | GUI 完成标记形态参照 |
| 官方文档 | `D:\downlaod\Doc\SWUG\SWUG105_TCL_Command_User_Guide.pdf`；`D:\downlaod\Doc\IPUG\IPUG034_PH1P_MIS_IP_Guide.pdf`；`D:\downlaod\Doc\TD_User_Guide_V6.2.pdf` | SWUG105 §2.2/§3/§4；IPUG034 §3.1（GUI 定制）；均不覆盖 headless IP 生成 |
| 冻结基线工程（禁写） | `D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820` | 220 项输入、manifest `8F8E4EFE…`；仅只读引用 |
| golden 引脚表 | `D:\TD\work\peripheral\09_ddr3_ddrmc_cal_x32_1066mbps\golden_adc\ap115v2_ddr3_x32.adc` | 70 引脚核对基准（SHA `F0904238…`） |
| 工具哈希锚点 | `D:\downlaod\bin\IpTool.exe`、`td_commands_prompt.exe`；MIS depot Component.xml/Dependency.tcl | 见 fpga-design-guide §1 |

## 5. 所有者与写权限索引（本批）

| 路径 | 所有者 | 本批权限 |
|---|---|---|
| `tools/td/prepare_ddr1333_ip.py` | 项目（T01.tool-A 开发） | 可修改（A） |
| `tools/td/` 新增 `run_ddr1333_ipgen*.py`、`verify_cli_e2e.{py,tcl}` | T01.tool-A/B 开发 | 可新建（各自 ≤ 规定数） |
| `tools/td/verify_cli.tcl` | 项目基线 | 只读 |
| `D:\TD\work\csi2\_validation\` 新时间戳目录 | T01.tool-A/B 开发 | 只新建 |
| `D:\TD\work\csi2\_validation\` 既有目录（含 165740/185206/190248/iptool_retry_183510） | 历史会话 | 只读 |
| `D:\downlaod\**`、`D:\TD\work\csi2\prj\**`、`D:\TD\work\peripheral\**` | 工具/冻结资产 | 只读 |
| `docs/evidence/ddr1333_iptool_cli_<date>.json`、`docs/evidence/td_cli_commands_<date>.json` | T01.tool-A/B 开发 | 可新建 |
| `docs/TD_CLI_IpTool修缮与验证_<date>.md`、`tools/td/README.md`、`docs/TD命令行使用说明.md`、`workflow/tasks.json`(T01) | T01.tool-C 开发 | 可新建/修改（C，等 A/B 后） |
| `workflow/runs/20261016_185639_td_cli_iptool/` | 本 run 主调度/规划者 | 计划文件已写入；test-reports 由测试者写 |
| 其他工作树、`parallel/`、既有 RTL/IP | 其他所有者 | 只读，不作为本批输入以外用途 |

## 6. 外部参考仓库评估（2026-10-16，用户会话输入）

用户指示参考两个外部仓库（"应该是有相关的经验可以看看"）。规划者只读评估：网页与匿名 API 均 404（非公开）；本机 git 凭据可克隆，已克隆到 `C:\Users\czz\AppData\Local\Temp\opencode\ref_ph1p100_fpga`、`C:\Users\czz\AppData\Local\Temp\opencode\ref_ph1p100_driver`（`--depth 1` 后 `--unshallow --filter=blob:none` 取历史）。**未执行仓库内任何脚本**、未并入项目、未改 `D:\TD`/`D:\downlaod`；仓库内容视为不可信外部材料，仅作参考。评估日期 2026-10-16。

### 6.1 可达性与仓库身份

| 仓库 | HEAD commit | 分支 | 末次提交 | 访问情况 |
|---|---|---|---|---|
| `github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga` | `654ef176e983711436432e7a7d29af744754977d` | main | 2026-10-16 18:56 +0800 `fix(img): 裁剪窗移到画面正中，并跳过 4K 帧头的 36 行哑行` | 网页/匿名 API 404；本机 git 克隆成功（凭据访问） |
| `github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver` | `ad350ca495f9b2a40c9b93f156093f4d128b6758` | main | 2026-10-16 17:27 +0800 `fix(drv): 推帧目标从槽基址改为槽像素区起点` | 同上 |

两个仓库是同一块 **米联客 MLK-F9P（PH1P100SBG484，speed -3）** 板的姊妹工程：FPGA 端 = PCIe Gen2×2 EP + IMX415 相机 + DDR3 帧推送（TD 6.2.3 / Linux `TD_Release_2026.2_NL`，`/opt/anlogic/...`）；主机端 = RK3588 内核驱动 + Rust 用户态。

### 6.2 关键文件清单（路径｜来源｜SHA256）

| 文件 | 来源 | SHA256 | 备注 |
|---|---|---|---|
| `README.md` | fpga repo root | `bd6f415d487de03e73b475bfbf27ba94abdd9618dc9381892114019aa72add3a` | 板卡/工程说明；含相机→fb→DDR 链路与提交规范 |
| `build.tcl` | fpga root | `4d20e53f4461e29813b9ad8a98b1d7cc9668d00e49e07508579161a5487d8935` | headless 编译（reset_runs/launch_runs/wait_run/save_best_bits） |
| `create_project.tcl` | fpga root | `157ba519178d4f97544f485ee0bc5309def4a05030a2ee9fd6415333363b8f6f` | 工程重建；`add_files al_ip/<ip>/<ip>.xml` 注册约定 |
| `download_sram.tcl` | fpga root | `2a638149d337de04416be9251d95327ef42ac88a7851a0553c0dfd04b438ac46` | connect_cable/download（本批 N/A，禁下载） |
| `al_ip/ddr3_mc_0/Design.xml` | fpga | `4d7060f8877717b82e4e547617c80178c369a6c296a21827eb057a7a2ec551c0` | 800E 配置；`PH1P_IO_ASSIGN`=绝对路径 golden_adc；ipGenVersion `208212 2026/08/14` |
| `al_ip/ddr3_mc_0/.params_ddr3_mc_0.txt` | fpga | `ed062b1dc0bc6576a750335fe35f6dc0c38437f34eb1ae519e486d84c7670a71` | 含 `PH1P_IO_ASSIGN/DRC PASS/AC_BYTE 3` |
| `al_ip/ddr3_mc_0/.m_params_ddr3_mc_0.txt` | fpga | `535e28148b07fd73ee6b6d03d47f02e5e178022d7b66b30af8f391e27c058c21` | 派生参数自洽（tCK 2500/CWL 5/CL 6/DX 4/256bit） |
| `al_ip/ddr3_mc_0/src/adc/ddr3_mc_0.adc` | fpga | `751997438bd28e2a956864493b3083008e1458878263dd709a569feca09c0baa` | 板真实 DDR 引脚（70+ set_ippin_assignment） |
| `al_ip/pcie_ep_core/pcie_ep_core.xml` | fpga | `be3a63a90135d75e94667bbd3431f36f357d196e7aa7ccee83c34b42c59a4315` | PCIe EP core IP（T07 参考） |
| `constraints/ph1p_pcie_case_ep.adc` | fpga | `67831295aef0f5afbec9f2dfbf062922b793a6586e56c074ace21787b6365c98` | EP 顶层引脚 |
| `README.md` | driver repo root | `ab6525abef1f30ddfa680f52d1787c833c0dcee15f16e63168e2ec48020ff7da` | RK3588 主机侧驱动说明 |
| `include/anlogic_pci_ioctl.h` | driver repo | `cc27f482aeae553d606574f9a66b2790233736c73aed94bafa0238948b842a4d` | 收帧缓冲/邮箱/DMA 地址合同（T03/T07） |

历史文档（在其 HEAD 已删除，规划者从 git 历史提取；副本存于 temp `ref_*.md`）：

| 文档 | 来源 commit | 提取文件 SHA256 | 内容 |
|---|---|---|---|
| `doc/ddr_ip_gen_fix_20261015.md` | `78174ba` | `d6669bfbd93a39fb73f7dece307b31f32e9260cfe29e6f49950f5bda9953fe75` | **IPT-1002 根因**（PH1P_IO_ASSIGN 空→gen_adc open ""）+四步 Tcl 配方 |
| `doc/ddr_ip_gui_steps.md` | `675b8f7` | `edbd409119792c2add9048b3b55b9a73ad788f0a7154ce50c230caa2b72030a4` | 命令行失败分析（含 IpTool 二进制符号级证据）+**GUI 精确点击清单**+坑清单 |
| `doc/ddr_bringup_plan.md` | `a7417b3` | `4418bc4946e2b2db4c5d760bdc722b019f938678c7923b49a98a17f788a10e0e` | DDR 集成调查（IP 来源三选一、PAXI/复位/时序、§1.8 未执行的命令行草案） |
| `doc/cam_frame_pcie_verify_20261015.md` | `78656bc^` | `2b68244a2c3ebc7400a06c3f3e86e9e48d61e6aa184541e494d37a123c406bd5` | 相机像素→PCIe 端到端实测（2×2 Bayer/活性判据、SDC 过期核对） |

### 6.3 与 T01.tool-A 的相关性（IpTool/TD CLI 生成入口）——**有用（高）**

1. **失败根因同族（其"实测+静态"分级）**：命令行建出的 MIS DDR IP 实例 `PH1P_IO_ASSIGN`（ADC 引脚约束路径）为空 → 生成链 `plugin_end.tcl → script/gen_adc.tcl` 执行 `open $adc_file r` 拿到空串 → `[Error-TclFile] couldn't open ""` → `IPT-1002 Generate target failed`。填对**能过 DRC 的板真实 ADC** 后其整链 12 步 success、61 文件（旁证：该次生成由另一进程完成，非文档作者）。DRC 前提、规则细节（信号数/引脚须在器件包表/bank 组合/dqs 位号 6÷7/ck 相邻）均有原文。
2. **与我们现场吻合**：我们 h2f 修正形态（`ddr1333_cli_20261016_195304_19`）的输出 scaffold `Design.xml` 里**无 `PH1P_IO_ASSIGN`**、出现默认 `REF_CLK 100`/`DDR_SPEED 800`/`SPEED_BIN NONE`，`.m_params` 出现 tCK/BK/AC/DX=0 与 128bit/25bit 宽度；`log/ipgen.log` 记录 `set_spin_box_text REF_CLK 100.00 / DDR_SPEED 800.00 → #IP Generate Failed!` → 生成开始前参数状态未带入（同族问题的另一扇门）。
3. **其成功配方依赖 TD ≥6.2.3，本机缺失（规划者实测）**：配方 = `create_ip -vlnv … -component_name …` / `open_project` 后 `load_project_ips` / `set_property <值> CONFIG.<名> <对象>`（顺序反 Vivado）/ `generate_target [get_ips …]`（SWUG105 2026.08 §4.4 收录）。规划者只读探针（`td_commands_prompt.exe`，temp 目录，`info commands`）：本机 TD 6.2.2.200067 **未注册** `create_ip/get_ipdefs/get_ips/generate_target/generate_ipinst/load_project_ips/close_project_ips/report_ip_status/ip_upgrade`；**已注册** `set_property/get_property/create_syn_ip/xmlipgen/ipgen_synip/print_ip_config/read_ip_adc/export_ip_lib/set_ip_property/set_ippin_assignment/save_best_bits/reset_runs`。IpTool 版本：本机 `2026.03(193873 2026/03/31)`（本批 scaffold 头）vs 外部 `2026.08(208212 2026/08/14)`。⇒ **外部配方不能原样移植**。
4. **可直接引用的坑/事实**：`set_property` 参数顺序写反静默失败（仅 `USR-7001`，catch 仍 0）；`open_project` 后必须 `load_project_ips`；`.al` 会被静默重写（含"删空 IP 目录后再 `create_ip` 静默删除既有 `<IP_FILE>` 条目"案例）；`generate_target` 不改 `.al`，RTL 靠实例 xml fileset 被工程识别；depot 自带 `example_adc` 是别的板（实测球号全不同，用完 DRC 可能仍 PASS 但引脚全错）；**其 F9P 输入 ADC 与我们同一份 `ap115v2_ddr3_x32.adc`**；其 GUI 回放日志模式（`ipgen_gui_*`→`#IP Gen Succeeded`/`#GUI-2000`）与 09 例程一致。
5. **可参考（中）**：GUI 点击清单（@675b8f7 §2）与我们的 190248 人工包高度一致（Setup Exporting Options：Export Path 默认 `al_ip`、Component Name；参数 8 组；`IP Generating Options`→Generate）；其文档未记录 Binary Path/Synthesis Options 字段，我们的这两项填写仍以 IPUG034/TD_User_Guide 为准。
6. **边界事实**：其最终交付仍走 GUI（§1.7 结论：改参数必须 GUI；Tcl 路仅"链路可跑"旁证）。

### 6.4 与 T01.tool-B 的相关性——**有用（中）**

- `build.tcl`：`import_device` → `open_project` → `reset_runs {syn_1}` → `launch_runs {syn_1 phy_1} -jobs 4` → `wait_run syn_1 -quiet` → `wait_run phy_1 -quiet` → `save_best_bits` → `==== BUILD DONE ====`，证明**管理器 syn+phy 一体化流程**在其 6.2.3/Linux 可用。建议 B 包 scratch 端到端顺带覆盖本机已注册的 `reset_runs`/`save_best_bits`。
- `create_project.tcl`：IP 注册只需 `add_files al_ip/<ip>/<ip>.xml`（ADC/SDC 由 IP fileset 带入）；工程重建可 `-force`。
- `download_sram.tcl`：`connect_cable`/`download -mode jtag`（无写 flash）；本批禁止下载，仅记录为 T07 参考。
- 约定一致：`log/td_*.log` 写 cwd、cd 工程根、正斜杠路径。

### 6.5 与 T07（PH1P100 PCIe EP）的相关性——**有用（高，未来批次）**

- 完整 EP 工程资产：`al_ip/pcie_ep_core`（IpTool 生成的 EP core）、`al_ip/pcie_pll_ep`、`al_ip/ram`、`constraints/ph1p_pcie_case_ep.{adc,sdc}`、`rtl/ep_side/**`（engine/int_handle/ubus_bridge/uart/img/ddr 帧推）、`doc/APUG081_安路科技PH1P系列FPGA PCIE RC对接EP参考设计.docx`、`doc/uart_cmd_file_pcie.txt`。
- driver 仓库：RK3588 内核驱动（MMIO 门禁、收帧 DMA `dma_alloc_coherent`、探测武装）+ `anlogic_pci_ioctl.h`（帧缓冲/邮箱合同）+ Rust 用户态（`cam_grab`/`frame_grab`/`link_ctl`/`pci_bar`/`pcie_check`）。
- `cam_frame_pcie_verify`：相机→PCIe 主机端到端实测证据（对 T07/T12 判据设计有参考价值）。
- 其 DDR 落 BANK32/33、refclk H4 —— 与本项目文档一致（交叉印证）。
- 边界：其数据面是 PIO/寄存器/帧推，不是我们的 C2H 固定块路线；按“外部参考、未并入”引用。

### 6.6 口径冲突记录（**不改本批动作**）

外部文档引用 `DS1300_PH1P_Datasheet_1.2.1.pdf` 表 3-60 称 **PH1P100 DDR3 接口 800 Mbps**。规划者已在本机同一手册核实（`…\06_芯片手册\01_FPGA\安路\DS1300_PH1P_Datasheet_1.2.1.pdf`，PDF95/印89）：PH1P100 DDR3=800/DDR4=800 Mbps。而 09 例程实配 1600、本项目现役 002820=1600、DDR1333 候选评估中——存在"器件手册口径 vs 例程实践 vs 板卡手册 800Mbps×32bit"三方差异。**列为 T01 决策材料**（报告/任务板如实记录），本工具化批次不调整频点结论、不擅自变更目标。

### 6.7 结论

- 两仓库可达（本机凭据）、与当前工作高度相关：**A 有用（高，根因同族+配方与坑+版本缺口实测）、B 有用（中）、T07 有用（高）**；其成功配方因 TD 版本差**不可直接移植**。
- 已据此在 `dev-plan.md` §4.1 追加增量假设 H6+（新增尝试合计 ≤6 次）及对 B/C 的影响说明。
- 本次未执行外部仓库任何脚本；除本文件与 dev-plan 两处更新外未写项目仓库、未动 `D:\TD` 与 `D:\downlaod`。

## 7. 未决事项（含外部评估更新）

1. IpTool headless 生成：14 次受控尝试全部失败（修正形态达生成阶段但确定性 `#IP Generate Failed!`）；外部同族经验+本机命令缺口使"CLI 全自动改参数生成"在当前 6.2.2 上大概率不可行；剩余可测路径见 dev-plan §4.1（H6–H9，≤6 次）；T01 解锁主路径为 **GUI（用户在场）或 TD 升级**（用户决策）。
2. 若仅 GUI 可行：用户是否安排在场 GUI 生成（190248 或新包）；外部仓库 §2 点击清单可作独立佐证；在此之前 T01 维持 blocked/awaiting。
3. `launch_runs/wait_run` 管理器缺陷（exit1/PRJ-88xx、物理 run 创建）现状与 workaround 适用边界——B 包实测（外部 `build.tcl` 显示其在 6.2.3/Linux 可一体化跑通）。
4. bitgen 在 scratch 工程的实际可行性与耗时——B 包实测（用户口"可行则含"）。
5. 工具目录外写入（已观察 IpTool 改写安装目录 `.setup.ini` 窗口缓存）——继续每轮扫描并如实报告。
6. **TD 版本决策（新）**：是否升级/另装 TD ≥6.2.3 以获得 Tcl IP flow（`create_ip/get_ips/generate_target` 等）；需评估对现有冻结工程/流程的兼容风险——用户决策。
7. **DS1300 表 3-60 口径（新）**：PH1P100 DDR3 800 Mbps 与本项目 1600/1333 的资格差异——T01 决策材料，报告需如实列入。

## 8. TD 升级可行性审核（2026-10-16，用户指令"先审核下升级是否能解决然后决定"）

- 审核文件：`upgrade-review.md`（同目录）。本轮只读审核：未下载/未安装/未执行外部脚本。
- 关键新增事实：
  - 队友材料（GitHub 两仓库 + 本机 2026-10-10 拷入样本 `D:\TD\work\_peer_f9p_review_20261010\`，`fpga_prj.al` SHA `224FF716…`）均使用 **TD 6.2.3.210850（Release_2026.2）**；其 IP flow 配方（`create_ip/get_ips/set_property/load_project_ips/generate_target`）依赖该版本（我方 6.2.2 未注册，已实测）。
  - 6.2.3 对 DDR MC：设置 ADC + `generate_target` 有外部 H2 声称实测（IPT-1001、61 文件、proc 12 步、DRC PASS）；**完整参数注入（1333 档）未闭环**；MIPI_DPHY 批处理不产 RTL 为反例（批处理覆盖按 IP 而异）。
  - 本机无 2026.2 安装包（全盘抽查）；唯一本地安装器 = `D:\TD\03_MLK_AFH03_AFC03\软件&驱动\TD_Release_2026.1_SP2_NL.exe`（=现行同版，SHA `36e23685…`，1.89 GiB）。
  - 官方获取：anlogic 官网 TD 下载需登录+权限（邮件开通）；米联客需会员；最新版本号【未知】。license（NODELOCKED，至 2027-03-31，SHA `DC19FEE6…45C1A6`）【推断】可复用，官网有补领通道。
  - 并行安装可保持全部 6.2.2 冻结锚点（工具 SHA、DB_VERSION=46207、190248 depot 来源、bit/CWC）；就地升级不推荐；仅换 IP depot 不可行（命令缺口在 TD 主程序内，不在 depot）。
- 结论：升级**取决于条件**（获取渠道 / 并行安装 / §4 四步验证中"完整参数注入一次成功" / license 兼容），大概率能解决 headless 生成；GUI（190248，用户在场）仍为确定性保底；两路径可先后进行。对 T01.tool-B/C 无额外动作要求（B 证据继续绑定 6.2.2；C 报告增补引用 upgrade-review.md 与"双版本工具链"+每候选版本绑定表述）。
- 决策点（详见 upgrade-review §7）：①是否并行安装 2026.2；②获取渠道（官方/米联客/队友）；③是否先安排 GUI 保底；④若升级接受双版本纪律；⑤DDR 频点口径独立议题。
