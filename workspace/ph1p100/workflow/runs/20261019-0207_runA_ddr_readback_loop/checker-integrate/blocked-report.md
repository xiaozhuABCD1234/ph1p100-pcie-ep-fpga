# blocked-report — T11.runC-checker-integrate（fpga-dev，OpenCode）

- 时间：2026-10-19 02:29（上海）；runtime=OpenCode；status=**blocked**；未创建 manifest、未启动仿真/构建、**零上游写入**。
- 结论：**冻结输入与实际工作树不符，且另一并行 run 正在同一工作树写同一批文件（活跃在途）**；按"不合并、不覆盖他人在途改动/不让冻结绑定他人未完成中间态"，本包不能在当前状态下开工。

## problem 对象（有界规则格式）

| 字段 | 值 |
|---|---|
| problem_id | `T11.runC-checker-integrate:INPUT_CONFLICT:worktree` |
| reason_code | INPUT_CONFLICT |
| new_information | true（规划冻结后新出现：并行 run 于 02:23 起写入同一工作树，dispatch 描述的基线已失效） |
| evidence_path | `workflow\runs\20261019-0207_runA_ddr_readback_loop\checker-integrate\blocked-report.md`（本文件，含快照哈希与时间线） |
| requested_action | 原规划在本轮边界内裁定去重/恢复条件（见下"请求动作"）；不得由开发自行合并/覆盖/丢弃他人在途改动，也不得自行新建 worktree/分支规避（属扩权） |
| resume_input_path | `workflow\runs\20261019-0207_runA_ddr_readback_loop\dispatch.json`（+ `dev-plan.md` §3.1 + 本文件） |

## 证据

### A. 本 run 冻结描述（规划时点）

- `input-index.md` §2.2（02:16:55 写入）：上游=`upstream/ph1p100-pcie-ep-fpga`，HEAD `b0282d2a8dfdf11e6e63779510fe380dfffb5e83`，"继承的未提交改动（r3 复位域修复，**4 路径** worktree-only，**+46/−5**）"= `ep_bar_win.v`、`pcie_ep_engine.v`、`ph1p_pcie_ep_top.v`、`tb_ep_bar_win_debug.v`。
- 本 run 时间线：02:07 建 run；02:10 request；02:16—02:20 规划四件套；02:23:24 main-log 登记本开发派发。

### B. 实际工作树快照（02:27—02:28，HEAD 同上）

- `git status --porcelain` = **7 个 M + 6 个 ??**（非 4 路径）：
  - M：`rtl/ep_side/ddr/cam_r10f_writer.v`、`rtl/ep_side/ddr/ddr_frame_readback_checker.v`、`rtl/ep_side/img/ep_bar_win.v`、`rtl/ep_side/pcie_ep_engine.v`、`rtl/ep_side/ph1p_pcie_ep_top.v`、`sim/compile_checked.f`、`sim/tb/tb_ep_bar_win_debug.v`
  - ??：`constraints/ph1p_pcie_case_ep_closedloop.sdc`、`rtl/ep_side/ddr/closedloop/`、`rtl/ep_side/debug/ph1p_pcie_ep_top_closedloop.v`、`rtl/ep_side/img/algo/`、`sim/tb/tb_closedloop_writer_checker.v`、`tools/pcie_integration/td/00_all_closedloop.tcl`
- 快照哈希：`status_hash=87a12815f56762df3330024f1650ae89f3b1974c`；`diff_hash=50e34e6541ca18ff6a62c8f3b8477c0673a6348f`（均以 `git hash-object --stdin` 由 porcelain/diff 文本计算）。
- 文件 SHA256（工作副本）：`cam_r10f_writer.v`=B6C5AB12…3488E；`ddr_frame_readback_checker.v`=146BFB9F…9FCE7；`closedloop/ddr_closedloop_readback.v`=E19C3883…7B5AD；`sim/compile_checked.f`=7916F234…856A。
- mtime：`cam_r10f_writer.v`、`ddr_frame_readback_checker.v`=02:23:10；`closedloop/ddr_closedloop_readback.v`=02:23:49；r3 四路径=00:00（规划前，正常继承）。对比规划时点 02:16—02:20，上列 DDR/closedloop 改动**晚于冻结**。

### C. 所有者为并行 run `20261019-0212_codex_fpga_closedloop_b2`（Codex，同项目）

- 该 run 02:12 建立；`request.md` 含用户原话"**这个本来是opencode的任务，修改为codex试用**"；`main-log.md`：02:13 planner 注册、02:20 规划返回（`T06.codex-ddr-readback-int`、`T09.codex-production-int`）、02:20 起 B01 开发注册。
- 逐字对应：该 run `scripts\implement_t06.py` 的替换串（`parameter integer CLOSEDLOOP_EN`、`cl_release[0]`、`cl_pub_valid`…）与 worktree 中 `cam_r10f_writer.v` 改动一致；`scripts\make_tb.log`/`make_tb.err` 于 **02:27:23 仍在写入**（其开发此刻活跃）。
- 写域重叠（该 run `dev-plan.md`）："允许 rtl/ep_side/ddr/（checker 相邻适配/仲裁）、新 rtl/ep_side/img/algo/、新增 rtl/ep_side/debug/closedloop 诊断 wrapper；必要最小修改 rtl/ep_side/ph1p_pcie_ep_top.v、pcie_ep_engine.v、img/ep_bar_win.v 和 cam_r10f_writer.v；sim/compile_checked.f、sim/tb/受影响/新增 TB；新 tools/pcie_integration/td/00_all_closedloop.tcl 及必要 run-local 辅助脚本；新同层 closedloop SDC…"——与本包 write_scope **全量重叠**，且目标同为"DDR 读回校验集成进调试候选"。

## 为什么不能继续（不能以"叠加+保留"处理）

1. 本包语义步骤 1—3 必须改 `ph1p_pcie_ep_top.v`、`img/ep_bar_win.v`（字库块）、`ddr/**`、`sim/tb/**`、`sim/compile_checked.f` — 与并行 run 在途写同一批文件；分钟级并发写会损坏双方，且违背"其他聊天/worktree成果只读引用，未授权不合并、不覆盖"。
2. 本包步骤 5 要求冻结"HEAD→当前（含继承改动）"的 `candidate.diff`/manifest。当前累计 diff 含他人**未完成中间态**（其 B01 尚未收口、可能继续改/提交/回退）；此时冻结=把他人在途变更绑进我方证据链，下游 P2 构建（同一棵树）也会被其后续写入扰动 → 无法产生诚实、可复现的 manifest。
3. 去重与优先级（Track A 归 OpenCode 包还是 Codex run、是否隔离工作树/时隙、等待或重派）属**规划/用户裁定**，超出开发授权；开发自行选择任一方案（含"另建 worktree 规避"）都是扩权/改变冻结边界。

## 已做 / 未做

- 已做（只读）：本 run 四件套与技能、规则读取；上游 `git status/rev-parse/log/diff/stat`、文件 mtime 与 SHA256、快照哈希；并行 run 的 `request.md`/`main-log.md`/`dispatch.json`/`dev-plan.md`/`implement_t06.py` 交叉核对。约 19 次工具调用、≈15 min，零写入上游。
- 未做：P1 语义步骤 1—5 全部（集成 RTL、新调试字、几何核对、新 TB/8 TB 回归、manifest 冻结）；未启动 ModelSim/TD；未产生需复测的冻结构件。

## 请求动作（原授权范围内）

由**原规划者**裁定并给出可恢复条件，例如（示例，非开发自选）：
- (a) 与 0212 run 明确去重：确认本包等待其收口（完成/commit/revert 形成稳定树）后，以**当时快照**重派本包，并先更新 `input-index` 的继承描述与基线哈希；
- (b) 或为本包冻结独立工作树/时隙（需规划同步更新 `write_scope` 与冻结值）；
- (c) 或由用户裁定 Track A 归属其一、另一侧停派。
在上述条件满足前，本包不得以当前共享工作树开工。

## 恢复入口

- 恢复输入：`workflow\runs\20261019-0207_runA_ddr_readback_loop\dispatch.json`；配套 `dev-plan.md` §3.1、`fpga-design-guide.md`、本报告。
- 重派时请先核对上游快照哈希（status/diff hash 或 mtime 清单）与本报告 §B 是否一致；如 0212 run 已有新提交/新改动，须以重派时快照为准更新冻结描述。
