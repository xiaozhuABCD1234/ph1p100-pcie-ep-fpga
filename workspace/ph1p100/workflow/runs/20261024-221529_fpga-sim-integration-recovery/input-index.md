# 输入索引（冻结 2026-10-24）

PROJECT_ROOT=`D:\fpga\ph1p100`；OUTPUT_DIR=`D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery`。以下相对路径均相对此根或 OUTPUT_DIR 中明确标出的 `inputs/`。

## 需求与现行合同

- 用户原话、图片逐字转录、附件索引：`request.md`。本轮用户明确要求执行两个离线仿真缺口；没有新增下载、Flash、外部消息或吞吐修复授权。
- 根 `AGENTS.md`；`.agents/skills/fpga-planner/SKILL.md`、`fpga-design-guide/SKILL.md`、`fpga-dev/SKILL.md`；`fpga-orchestrator/references/{work-limits,relay-contract,report-contract,project-context}.md`。现行一个综合测试者优先于历史三测试描述。
- 根 README、CODEX_HANDOFF 及 workflow/README 已核对；历史摘要不能覆盖新报告。统一任务主源仍是 `workflow/tasks.json`，当前 T08=ready、T10=active；父任务的硬件终点未完成。

## 本轮采用的输入

|用途|来源|本轮冻结位置/边界|
|---|---|---|
|双路生产 RAW 顶层|`upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/ph1p_pcie_ep_top.v` 及 RTL 依赖、`sim/compile_checked.f`、顶层端口桩|`inputs/production-raw/`；是真实 A/B CSI→cam_r10f_writer→DDR 生产源码线；不是板上 P2 A+ 候选|
|同步控制原型|上述生产树 `rtl/ep_side/cam/sync_offline/` 5 RTL、`sim/tb/tb_sync_offline.sv`|已含于 production-raw；旧独立报告为 `workflow/runs/20261019-2117_runD_batch2_continue/test-reports/T08.codex-sync-offline-r0-integrated.md`，仅证明小顶 G0/G1/G2|
|探索同步边界|`work/parallel-sim-20261024-2204/{summary.md,sync/inputs.json,sync/tb_sync_pair_boundaries.sv}`|`inputs/exploration/`；探索证据，不能替代本轮正式独立验收|
|A+ 恢复 DUT|探索 `boundaries/src/` 中 8 项真实 RTL、DDR模型、TB和工具|`inputs/a1-r5/src/`；核心明确采用 r5 SHA `29b1e3e1a66abef78c228c4189322b0139a266d43bf02827dd1ebe498cdc9828`；不混 P2/r4 位流|
|A+ 解码/判据|探索 `boundaries/checker/` 及 `boundaries/{result.json,run_boundaries.py,run.do}`|`inputs/a1-r5/checker/`、`inputs/exploration/boundaries/`；r0 TB 的 MODE3/4 无独立语义，必须新建显式故障用例|
|历史写入中复位问题|旧 b1 r4 `result-r4.md` 和 TB|`inputs/legacy-recovery/`；`FRAME_CYC/2` 曾超时、复位清零计数，都是待验证问题；不得先假定 DUT 或 TB 有错|

`planning-input-manifest.json` 固定 108 项/3,411,057 字节，列 source/frozen/SHA256/size。它是规划输入，不是开发待测 manifest。`freeze_inputs.py` 仅复制列明输入，无测试或源码修改。开发从这些冻结副本创建任务工作目录，不再用活动源替换输入。

## 所有者与保护

- 本仓 HEAD=`27c596b01cd961dfa9d0850e4fbf879fe249de90`，分支 `codex/ddr-timing-margin`；工作树已有大量 dirty、删除和 untracked，属于既有会话/迁移，全部保留。本轮不 reset/clean/commit/push。
- 另一工作树 `C:\Users\czz\.codex\worktrees\bayer-codec-reference\FPGA创新设计赛道` 只读，不授予写权。
- 板上调试线：`workflow/runs/20261020-0209_singleA_aplus_closedloop`、`D:\fpga_work`、`D:\TD\work\csi2`、所有共享 bit/CWC/DB 和原生产树只读。本轮不占用设备、TD GUI、盘符、硬件窗口。
- 旧 P2 仅保护身份：bit `d1ac8726e84f6584d49979dd223d6e8c484e559bf2a3ad3b2302972c58efc142`，不拿它证明 r5 或同步 overlay。
- `docs/` 是 OneDrive junction，本轮不得在那里新建产物。开发/测试只能写各自本 run 任务域；规划只能写本 run 及两任务新记录。统一任务板到收尾读最新版本后最小更新，不用当前旧副本覆盖其他会话状态。

## 未决与不进行

真实曝光同步/电气、上板恢复、长稳和满速仍无本轮证据；77.76 MB/s comp 缺口留原探索记录，明确不修。两项仿真采用不同源码线，各自候选、manifest、判定，不拼成一个硬件系统已通过。
