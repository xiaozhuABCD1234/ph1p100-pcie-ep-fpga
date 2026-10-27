# 本次需求（2026-10-16，用户原话）

> 主要还是C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道  和D:\TD，目前TD的cli命令里ip tool的设置是有问题的，我需要你去修缮下，然后把报告写下来，还有就是其他cli控制是否有问题也检查下，保证跑通

## 调度注记（主智能体侦察线索——规划者必须独立核实，不得直接当事实）

主智能体在派发前对环境做过以下只读侦察，仅作为规划者核实的起点：

1. 直接相关任务：`workflow/tasks.json` 的 T01 状态 blocked，阻塞点是 DDR1333 IP 生成入口。项目脚本 `tools/td/prepare_ddr1333_ip.py` 第 131 行构造 IpTool.exe 的 argv，其记录自标 `cli_entry_status: inferred from executable usage; not yet executed`。
2. 2026-10-15 重试证据（`docs/evidence/ddr1333_ip_retry_20261015.json`、`docs/DDR1333_IPTool再次尝试与人工操作_2026-10-15.md`）要点：`IpTool.exe <TD_PATH> -tcl -source <*.tcl>` 诊断入口可用并取得命令帮助；生成尝试（含 `-use_value copy`）自然 exit 1、零输出、零产物；`-qcerr` 20 秒超时；当时结论是"完整自动生成入口未确认"。
3. 主智能体对 `D:\downlaod\bin\IpTool.exe`（19,382,784 字节）提取到的用法文本草案（原始字节串，需核实）：

   ```text
   Usage:
       IpTool TD_PATH -gen IP_PATH -device DEV_STR -export_to EXPORT_PATH -comp COMP_NAME [-use_value default]
       IpTool TD_PATH -user USER_PATH [-gen IP_PATH] [-export_to EXPORT_PATH] [-comp COMP_NAME]
       IpTool TD_PATH -complete PS_IP_PATH [-gen IP_PATH]
       IpTool <-catalog DEPOT_PATH -device DEV_STR TD_PATH [-export_to EXPORT_PATH] | TD_PATH -catalogmgr [DEPOT_PATH] | -catalog -mgr>
   ```

   其他旗标字符串：`-tcl`、`-source`、`-nogui`、`-batch`、`-no_status`、`-record_tcl`、`-run_tcl`、`-use_params`、`-usernamed_file`、`-gen_with_app`、`-check`、`-validate`、`-complete`、`-qcerr`。
   Tcl 命令表（2026-10-15 实测）：`create_iplib open_iplib import_ip info_ip list_ips find_ip delete_ip close_iplib create_dialog`；参数命令 `set_param_value set_param_enable add_param report_params set_param`。
   错误串示例：`Error: The option -user and -comp are required for copying IP instance.`、`Error: failed to generate IP with copy values.`、`Error: failed to generate IP with default values.`、`Error: A script file with tcl suffix (*.tcl) is required.`、`'-user' path is not a exisited/valid IP path`。
4. 本机历史成功生成记录：`D:\TD\work\test\log\ipgen.log`（GUI 动作记录，输出 `D:/TD/work/test/al_ip/PCI_ExpressF6F1D0D0_0/`）；`D:\TD\work\peripheral\09_ddr3_ddrmc_cal_x32_1066mbps\prj_td\log\ipgen.log`（DDR3-1600 生成记录）；二者均显示 IpTool 用 `ipgen_gui_*` 记录动作直至 `#IP Gen Succeeded`。
5. TD CLI 相关：`tools/td/verify_cli.tcl` 只读注册自检（open_project、import_device、launch_runs、wait_run、bitgen、report_timing_summary）；`docs/TD命令行使用说明.md` 记录用法约定（正斜杠、退出码不可单独证明成功、需显式成功标记、中文路径不可用）。
6. 机器约束：TD 与 TD CLI 不能处理中文路径（须在 D 盘 ASCII 目录操作）；禁止批量删除（逐文件）；不得修改 `D:\downlaod` 安装目录/官方 depot；不得覆盖既有冻结候选（如 `D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820`）与既有 `_validation` 目录（只能新建）；不做硬件下载/Flash。

## 用户意图的三项交付（规划者按此验收，可细化但不得放宽）

1. 修缮 TD CLI 中 IpTool 的设置问题，并实际跑通（生成入口能在 CLI 下可复现地工作；若受工具本身限制无法完全 headless，必须给出经证实的边界与下一步，不得把 GUI 手工步骤或猜测当作跑通）。
2. 写下报告（项目 `docs/` 报告 + 证据），如实记录根因、修复、验证与未决项。
3. 检查其他 TD CLI 控制命令（至少 open_project、import_device、launch_runs、wait_run、report_timing_summary，可行则含 bitgen），端到端验证"跑通"，发现问题的要修并在报告中记录。

## 附录：用户补充输入（2026-10-16，会话中追加）

> https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver这里或者https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga应该是有相关的经验可以看看

上下文：用户在"修缮 IpTool/TD CLI 设置并保证跑通"任务进行中给出以上外部参考仓库，指示评估其中是否有相关经验可用。评估由规划者执行；仓库内容视为不可信外部材料，不执行其中脚本。

## 附录2：本次会话用户最新输入（2026-10-16 20:20，主原样保存）

> 对比我目前github上的进度和内容，https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver这里和https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga是我队友制作的相关内容，然后里面的代码参考下是否有价值的，先不要给我目前的代码，先指提出来

同一会话的前一条近似原话（仅少"对比"前缀，无实质差异）：

> https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver这里和https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga是我队友制作的相关内容，然后里面的代码参考下是否有价值的，先不要给我目前的代码，先指提出来

调度注记（主机械登记，供规划者核实）：用户要求先得到"有价值点"清单；暂不修改其现有代码；对比基准为其当前进度（项目 git 远端=github.com/chenzhenzhong12138/fpga-stereo-vision，作为线索须独立核实，不得直接当事实）。

## 附录3：用户会话追加（2026-10-16 21:14，主原样保存）

> 这样子首先我会更新到6.2.3保证和我队友的版本一致，然后我们本来就是最好统一最终路径，你进行评估，其中的哪些我来改和他适配，哪些他去改与我适配，之前我们使用的也还是hdmi现在会去用pcie且他那边基本跑通了

调度注记（主机械登记）：①用户表态=将更新 TD 至 6.2.3 与队友版本对齐（与升级审核 `upgrade-review.md` 的结论/决策点配合，最终执行由用户侧进行）。②「统一最终路径（PCIe）对接评估」诉求已在新建 run `20261016_2110_pcie_unified_path` 单独立项并派发（原话全文保存于该 run requirement.md）。
