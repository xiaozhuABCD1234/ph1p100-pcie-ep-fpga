# 本轮用户原话与 TD route 绕行边界

## 当前用户原话

先做1

## “1”指什么

上一轮 `20261027-055621_fpga-honly-td-and-ah` 给出二选一，用户选择第 1 项：

> **先把布线跑出来（推荐）**：开一个新 run，专门绕开 TD 的 ChipWatcher 崩溃（换导入方式/去掉 debug 负载/换或重装 TD/最小工程复现），拿到 routed STA。配额建议：TD 启动 ≤3、synth ≤1、route ≤2、**不 bitgen**。这是目前唯一缺失的关键事实。

## 已有基础

`20261027-055621_fpga-honly-td-and-ah` 已 finished：

- H-only 候选 synthfix：core `d2960cfe0111b7b61aff281e3f16427834dda26107f37867d5c7c89ac346aad8`（85,221 B）；frame_top `4afc26e246fbae4e32c5ab7e88dffb496048d10966c5ee42b290b3e71f60e30a`（29,207 B）；synthfix manifest `034777c5…`；4 帧 N 6,196,749.5 / L 5,834,940，4/4 帧头逐字节相同。
- TD r1 synthesis PASS：SWNS **+0.029 ns**、STNS 0、HWNS 0、Period 2.533、coverage 97.06%、0/4,969 endpoints；IO 121/286、slice 3,337/71,680、reg 1,663、ERAM 27、DSP 0。
- TD 6.2.3 在 `import_db → Import ChipWatcher` 两次 coredump（1.44/1.22 s），无 `phy_1/*.pr.db`、无 routed STA/QoR/check_timing/CDC；209.6 analysis not_run。
- `eligible_for_next_stage=false / not_evaluated`；不是时序失败，是工具崩溃。
- TD r1 manifest：`8325f230cb8581783b8e1a0ea835e33d00b8337e0dffb6a15e7d95926c8869fa`（83 artifacts）。
- 报告：`test-reports/T10.ah-honly-td-r1-integrated.md`；合并判定：`dual-verdict.md`；启动文本：`user-summary.md`。

## 本轮目标

在 **不改 RTL/SDC/时钟/例外/候选** 的前提下，绕过 TD 在 `import_db → Import ChipWatcher` 的 coredump，取得同一 H-only 候选的 **routed DB + routed STA**（187.5 MHz；可选 209.6 analysis-only）。

必须回答：

1. 崩溃能否在最小工程复现？是特定 gate DB、ChipWatcher debug 负载、TD 版本、导入路径/选项，还是工程/库状态导致？
2. 哪一种绕行有效：换 TD 版本、重装/修复 TD、关闭/剥离 ChipWatcher/debug、换 import 方式、最小工程导入、清理工程/库、换工作目录，还是其它？
3. 绕行后是否得到 **同一 DUT** 的 routed DB（core d2960cfe / frame_top 4afc26e2）？不得改 RTL/SDC/时钟/例外/候选；不得换一个更简单的 DUT 冒充。
4. routed STA 是否满足：**routed WNS≥0、hold≥0、flow.status NUM_FEPS=0、ERAM+CWC≤300、slice≤71680、IO≤286**；附 check_timing、report_cdc、report_qor、clock_utilization、worst ≥10 路径归因（frame_top 双 CRC32 / core replay-emit / scan）。
5. 若无法绕行，冻结最小复现、崩溃 dump、TD 版本/环境、已试方案与结论；不得把 synth +0.029 当 routed 通过。

## 硬约束

- 只做 FPGA 侧 TD route/STA；不接 RK；**0 bitgen/CWC/下载/Flash/板卡/COM/JTAG/RK/网络**。
- 不改 RTL/SDC/时钟/周期/例外/候选；不改 H-only/synthfix/TD r1 目录/报告；不改其他 run、b18–b20、integrated delivery、board-integration、旧 P1–P4、生产源、tasks.json、docs/work/.agents。
- 新 run 独立目录；TD 工程/库/日志只在本 run；不复用其他 run 的 work 库。
- **TD 独占**：先确认 `20261027-0726_fpga-board-integration` 与 `20261026-2138_fpga-integrated-delivery` 不在用 TD/板卡；preflight 0 进程、相关目录 ≥20 min 静默；忙则 blocked=TOOL_UNAVAILABLE，不等待/不抢/不共享。不要 remap/release T:；脚本用绝对路径。
- 用户已授权本轮新 TD 配额：**TD 启动 ≤3、synth ≤1、route ≤2、analysis-only ≤1、bitgen 0、download/Flash/board 0**。若需要换 TD 版本/重装，必须先做最小复现并记录，再执行；不得无界重试。
- 不批量删除；不 commit/push；新权威仓 `D:\fpga\repos\ph1p100-pcie-ep-fpga` 本轮不作为源、不写。
- 单次 TD synth ≤1800 s、route ≤2400 s、analysis ≤600 s；总墙钟由规划冻结。

## 关键输入路径

- run：`workflow/runs/20261027-055621_fpga-honly-td-and-ah`
- 合并判定：`.../dual-verdict.md`；用户摘要：`.../user-summary.md`；TD r1 放行：`.../r2-ruling.md`
- TD r1 manifest：`.../T10.ah-honly-td/r1/manifest-r1.json`（`8325f230…`）
- TD r1 工程：`.../T10.ah-honly-td/r1/td/{a1_ah_eng_top.v,a1_ah_small_top.sdc,01_synth.tcl,02_route.tcl,03_2096_analysis.tcl}`
- synth gate DB/报告：`.../T10.ah-honly-td/r1/td/run-syn1/{a1_ah_gate.db,syn_gate_timing.rpt,syn_gate_area.rpt,syn_flow.status,synth_console.log}`
- route 崩溃：`.../T10.ah-honly-td/r1/td/run-route1/`、`.../run-syn1/route_console.log`、`minidump-20261027-093503.dmp` / `-093540.dmp`
- H-only synthfix 候选：`.../T10.ah-honly-synthfix/r0/changed-src/{a1_deflate_core.v,a1_frame_top.v}`；manifest `034777c5…`
- TD 安装：`D:\anlogic\TD_Release_2026.2`（版本以实际 `td_commands_prompt.exe` 为准；是否有其他版本需只读调查）
- 当前 TD 占用：`workflow/runs/20261027-0726_fpga-board-integration`、`workflow/runs/20261026-2138_fpga-integrated-delivery`

## 输出目录

`D:/fpga/ph1p100/workflow/runs/20261027-150010_fpga-honly-td-route`

## 期望

由规划角色按项目有界规则拆分本轮“TD route 绕行”；优先一个包：最小复现 → 绕行 → routed STA；必要时第二个包只做环境/版本修复；不要一次开多个。主只原样转发，不解释技术需求。
