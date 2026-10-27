# fpga-design-guide — TD CLI / IpTool 修缮与验证（run 20261016_185639_td_cli_iptool）

本指南冻结本批（T01.tool-A/B/C）使用的工具入口、路径、参数、记录与证据约定。只冻结本次相关项；未列项沿用既有项目文件，不另立冲突标准。数值锚点均为 2026-10-16 规划者独立核实值。

## 1. 工具与路径常量（只读锚点）

| 项 | 值 | 说明 |
|---|---|---|
| TD 安装根 | `D:\downlaod` | 全程只读；禁改 bin/depot/Doc |
| TD GUI/IDE 二进制 | `D:\downlaod\bin\td.exe` | 存在（未核实哈希，不用于本批执行） |
| TD CLI | `D:\downlaod\bin\td_commands_prompt.exe` | SHA256 `79EC56674F8F7B889E25E11BDCA91F7D64C24BA0DE99E80680248F00B4F87190`；版本 TD Release_2026.1_SP2 / 6.2.2.200067，Tcl 8.6.15 |
| IpTool | `D:\downlaod\bin\IpTool.exe` | SHA256 `DA9E765EE1AF39594BC546224BA79CF84EAD5700C7BDDFE4A6FCC7BF95A3DE46`，19,382,784 B；与 10-15 文档一致，未变 |
| 官方 MIS depot | `D:\downlaod\ip\depot\MIS_DDRF6F1D0P0_1.2` | Component.xml SHA256 `FEB4F5BC5771CF9B8F816296754AB0BA9088CA9FFAFC9F001F9C1C50CBD5E543`；Dependency.tcl SHA256 `CD927834C559A6962E97159AE0C01CCA666C9E66B6C2CBBC7BCECB4C0B119623`；官方原件只读 |
| 成功生成参考记录 | `D:\TD\work\test\log\ipgen.log`、`D:\TD\work\peripheral\09_ddr3_ddrmc_cal_x32_1066mbps\prj_td\log\ipgen.log` | 均为 **GUI 动作记录**（`ipgen_gui_*`→`#IP Gen Succeeded`），只作"完成形态"参考，不是 headless 证据 |
| 成功产物参考形态 | `D:\TD\work\test\al_ip\PCI_ExpressF6F1D0D0_0\` | 含 Design.xml/DesignConfiguration.xml/`.params_*`/`.ports_*`/<comp>.v/<comp>.xml/RTL/ 等，仅作产物清单形状对照 |
| golden 引脚表 | `D:\TD\work\peripheral\09_ddr3_ddrmc_cal_x32_1066mbps\golden_adc\ap115v2_ddr3_x32.adc` | SHA256 `F09042381856BF55DE58F89DEBF70167A2956904528D92FD71C6993C08DB33DA`；70 引脚核对基准 |
| 冻结基线工程（禁写） | `D:\TD\work\csi2\prj\camera_rgb565_wb_20261015_002820` | `input_manifest.json` SHA256 `8F8E4EFE9B9320CBC595F94E337395744DBD957630576123576EE2C357F9A1C8`（与 prepare 脚本断言一致） |
| 既有私有包（只读复用） | `D:\TD\work\csi2\_validation\ddr1333_ip_20261015_190248` | 197 项准备输入+私有 depot+guard+retention；GUI 未启动、未验证 |
| 实验写区 | `D:\TD\work\csi2\_validation\` 下**新建**时间戳目录 | 既有 100+ 目录一律不写；不得覆盖 |

官方依据：`D:\downlaod\Doc\SWUG\SWUG105_TCL_Command_User_Guide.pdf`（Tcl 批处理与命令，§2.2/§3/§4）；`D:\downlaod\Doc\IPUG\IPUG034_PH1P_MIS_IP_Guide.pdf`（MIS IP，仅 GUI 定制流程）；`D:\downlaod\Doc\TD_User_Guide_V6.2.pdf`。核实结论：**两份 PDF 都不记载 IpTool/xmlipgen 的 headless 生成用法**——自动生成属未文档化探索，报告须如实标注。

## 2. TD CLI（td_commands_prompt.exe）调用约定（冻结）

- 脚本路径用正斜杠并带 `./` 前缀：`td_commands_prompt.exe ./build.tcl`；反斜杠 `.\` 会被解析出转义字符而失败。
- cwd 必须为脚本/工程所在 ASCII 目录；脚本内相对路径（`./...`、`import_device ph1_100p.db`）按 cwd 解析。**不从仓库中文路径运行真实构建**。
- 多行 Tcl 必须写成文件执行（stdin 多行有解析错误记录）；`-help` 被当脚本文件名，不可用作帮助入口。
- 退出码语义：脚本加载失败也可能返回 0；**成功判定 = 退出码 + 脚本内显式完成标记 + 非空产物清单 + 哈希**（三件套缺一不可）。标记用大写下划线串（沿用 `TD_CLI_OK`、`*_RETURNED`、`*_NO_DOWNLOAD` 风格）。
- 运行会在 cwd 生成 `td_*.log`/`td_*.logw`；原始日志随实验目录保留，不搬运大文件到仓库。
- 打开既有工程前先整目录复制到新目录再 open（open/close 会改写 `.al` 等状态；历史教训见 `docs/RAW10稳定档位_PLL生成与接入交接.md:153`）。
- 命令依据：六命令注册检查用 `tools/td/verify_cli.tcl`（只读，不改）；实现流命令语义见 SWUG105 §4.1（import_device/create_project/open_project/add_files/top_module/launch_runs/wait_run/open_run）与 §4.10（bitgen）。

## 3. IpTool 入口约定与受控实验格式（冻结）

- IpTool 是**未文档化**工具；任何"入口可用"结论只能来自真实执行记录。usage 串（二进制内）实际形态：catalog 形态 `<-catalog DEPOT_PATH -device DEV_STR TD_PATH [-export_to EXPORT_PATH] | TD_PATH -catalogmgr … | -catalog -mgr>`；生成形态 `TD_PATH <-gen IP_PATH -device DEV_STR -export_to EXPORT_PATH -comp COMP_NAME [-use_value default] | -user USER_PATH [-gen IP_PATH] …>`；`-tcl -source` 为脚本执行入口（已证实可用）；`-nogui/-batch/-no_status/-qcerr/-gen_with_app` 等为独立选项串。
- 已知行为（10-15 实测，保留）：`-tcl -source *.tcl` 可执行并取帮助；copy 生成加 `-tcl` → 自然 exit1 零输出；`-qcerr` → 20s 超时；不带 `-tcl` 的 copy 形态 → 45s/30s 超时。
- 实验目录命名：`D:\TD\work\csi2\_validation\ddr1333_cli_<YYYYMMDD_HHMMSS>`（每次尝试独立，`mkdir(exist_ok=False)`）。输入从冻结源（190248 或经 prepare 脚本的重建输出）**逐文件复制并验 SHA**。
- 每次执行记录（JSON，沿用 `docs/evidence/ddr1333_ip_retry_20261015.json` 风格）：argv、cwd、pid、started/ended、timeout_seconds、exit_code、timed_out、stdout/stderr（文件+SHA+字节数）、产物清单（相对路径+字节+SHA256）、输入 before/after SHA、单变量说明、子进程/窗口观察、实验目录外写入扫描结果。超时须真实 kill 进程树。
- 学习锚点：`create_iplib/open_iplib/close_iplib/list_ips/import_ip/info_ip/delete_ip/find_ip/generate_ipinst/help` 为二进制注册命令串；`generate_ipinst` 在未开库上下文未激活（可作受控重探假设）；`create_dialog` 帮助明示"对话框然后生成"（GUI 语义）；IpTool 内含 `xmlgenip`/`plugin_end.tcl`/`runTclTask` 串。以上均为线索，不是结论。

## 4. 私有 depot 与保留式清理约定（冻结）

- 官方生成器的清理脚本会递归删除输出中的 `Other`/`RTL` 等（违反"禁止批量删除"），**永远不在安装目录/官方 depot 上执行生成**。
- 一律使用私有副本：已知 `file delete -force` 替换为 `retain_ip_path`（保留移动到私有 `_retained/`，拒绝越界/链接/边界本身，重名另存）。
- 新尝试复用该机制（可引用 190248 的 `retain_ip_path.tcl`/`manual_binding_guard.tcl` 作为模板）；保留最终"无剩余活动 `file delete`"断言与安装 depot 未变断言（哈希见 §1）。
- 安装 depot/`D:\downlaod` 任何写入都视为越界（工具自身行为若发生，须如实记录并报告）。

## 5. 证据与文档约定（冻结）

- 证据 JSON：`docs/evidence/ddr1333_iptool_cli_<YYYYMMDD>.json`、`docs/evidence/td_cli_commands_<YYYYMMDD>.json`；schema 1；含 recorded_at/status/attempts/artifacts(SHA256)/limits/review 边界；不得改写既有证据文件。
- 报告：`docs/TD_CLI_IpTool修缮与验证_<YYYY-MM-DD>.md`（中文，含需求映射、根因、修复、逐项验证、边界、未决、下一步、锚点哈希）。
- 文档同步：`tools/td/README.md`、`docs/TD命令行使用说明.md` 增补式更新（保留旧记录并标日期）；`workflow/tasks.json` 仅动 T01 的 status_note/references，改后做 JSON 解析自检。
- 测试报告：按 `report-contract.md`，`OUTPUT_DIR/test-reports/<task_id>-r<n>-<dimension>.md`；各测试者独立报告，不改生产文件（必要变异输入独立保存）。

## 6. 禁止写路径（越界即停）

- `D:\downlaod\` 全部（含 bin/depot/Doc）。
- `D:\TD\work\csi2\prj\` 下所有冻结工程（明确含 002820）与既有 `_validation` 目录。
- 仓库：既有 `docs/evidence/*.json`、既有 RTL/IP、`tools/td/verify_cli.tcl`、其他工作树、`parallel/`。
- 任何板卡动作：下载/Flash/写板（本批 N/A，不请求授权）。

## 7. 已冻结 / 待确认 / 不适用

已冻结：§1 工具与哈希锚点；§2 TD CLI 调用与成功判定三件套；§3 实验目录/记录格式与红线；§4 保留式清理；§5 证据与文档路径命名。
待确认（本批实验回答，先不定论）：IpTool headless 生成本身是否可行、正确形态是什么；`generate_ipinst`/`xmlipgen` 是否可非 GUI 使用；`launch_runs/wait_run` 管理器缺陷现状；bitgen 在 scratch 工程可行性与耗时。
不适用并说明：G3/G4（无板测/长稳动作）；生产候选 G2（本批不综合/STA 任何生产候选；scratch G2-lite 仅证明命令可用）；模型/仿真层多数 N/A（本批是工具与工程验证）。

## 8. 本次三个测试维度的边界

- 功能（functional）：A 的参数一致性与产物闭合、负对照；B 的六命令逐条标记/产物；C 的报告溯源。不测历史板卡行为。
- 工程（engineering）：退出码+标记+产物哈希三件套、全新目录/输入 SHA、单变量与超时记录、安装目录与冻结工程零写入、保留式清理复核。
- 系统（system）：从仓库脚本到工具结果的端到端入口、scratch 工程 0→bit（可行则含）、T01 后续集成入口与人工包方向、任务板/文档一致性；不声称任何板测或生产 bit 结论。
