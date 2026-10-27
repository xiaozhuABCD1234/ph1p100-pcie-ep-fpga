# question-01 — 本轮需要你确认一件事

> **已确认（2026-10-27）：用户选择 A —— 做成队友执行包（本机 0 TD）。**
> 后续动作：`T10.ah-td-route` 记 `not_applicable_local_boundary`；放行 `T10.ah-td-route-kit`（本机只写包/静态核对，执行在持板队友环境）。本文件保留为决策依据，不再等待回复。

## 发生了什么

你选了“先做1”（本地绕开 TD 的 ChipWatcher 崩溃、拿 routed STA），我按这个目标读完了上一轮的全部证据并开始拆分。

但规划过程中 `AGENTS.md` 增加了 2026-10-27 覆盖段：

> 板已交队友；**本机只做仿真**，本地不再启动 TD 综合、布局布线、STA、bitgen、CWC、COM/JTAG、下载或 Flash；该边界**优先于**旧 run 的历史 TD/板卡额度。

因此你授权的 TD 配额（启动≤3、synth≤1、route≤2…）在**本机**已经不能用了。这不是设备被占用（规划时实测：0 个 TD 进程，三个相关目录静默 407–538 min），而是**权限边界变了**。

## 我已经冻结了什么（不花任何 TD）

- 崩溃点定位：`import_db <gate.db>` 在 `Import ChipWatcher` 处 coredump，placement 之前，两次同点、各留 minidump。
- **本轮新读到的关键结构证据**：TD 自己生成的默认流程脚本 `a1_ah_Runs/syn_1/a1_ah.tcl` 在 `opt_place` 步（`step==3`）会执行 `import_db $parent/a1_ah_gate.db`。所以“只改用 `open_project` + `launch_runs phy_1`”**大概率仍会崩**；真正能绕开的是**单会话 synth→place→route、全程不 `import_db`**（这条路径的完整命令清单已写进设计指南）。
- 绕行阶梯、门槛（routed WNS≥0、hold≥0、NUM_FEPS=0、ERAM+CWC≤300、slice≤71,680、IO≤286 + check_timing/CDC/QoR/clock_utilization/worst≥10 归因）、配额与超时、证据回传格式，全部冻结在本 run 的 `fpga-design-guide.md` 与 `dev-plan.md`。

## 请选一个（回复选项字母即可）

**A. 交付“队友执行包”（推荐，本机 0 TD）**
本机派 1 个开发 + 1 个综合测试者，产出：崩溃根因分析、S1 单会话 tcl（零 `import_db`）、S2 run-flow 诊断 tcl、S3 最小复现工程、验收/配额/回传清单、runbook。队友拿同一份包在持板机器上跑（≤3 次 TD 启动），把 routed DB + 全套报告回传，我再判 `eligible/not_eligible`。
代价：约 1.5 h 本机工时，0 TD；routed STA 结论取决于队友何时跑。

**B. 先不派，等本机 TD 权限恢复或等队友窗口**
本 run 保持 blocked。恢复本机 TD 需要你**新的一次明确授权**（本轮 3/1/2/1/0 的配额不会自动结转）。

**C. 直接关闭本 run**
把“TD 6.2.3 ChipWatcher 崩溃导致实现资格未评估”作为定论记账，H-only 候选止步 gate-level，不再追 routed STA。

## 如果你其实想的是“队友来跑”

那就选 **A**：包是我写、队友执行，符合新边界。若队友那边已经有自己的 TD 流程、不需要我的包，也可选 **C**，我会把崩溃复现与三条绕行假设写进交接，避免队友重踩。

> 无论哪个选项：我不会在本机启动 TD，也不会放宽任何门槛，更不会把上轮 synth 的 `+0.029 ns` 当成 routed 结论。
