# 本轮需求（用户原话，原样保存）

## 用户参数原话（/fpga-orchestrator 执行）

> 执行：FPGA 侧闭环加速推进，进度优先，稳定性/优化后放。
> 基线 run：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel
> 本轮明确授权 batch=2：Track A=单A RAW→DDR 板级闭环（读回校验/几何/坏帧）；
> Track B=T09 三算法并入生产工程+离线仿真+双相机同步RTL离线起步。
> 尽量合并构建；仅 SRAM、不写 Flash、不推送；不接 PCIe/RK；最后留“回来点两下”的上板清单。

## 用户随后补充原话（同一会话，原样保存）

> 我之前把这项任务交给了codex，现在有一定进展，看后进行接着做，并且不要和track A相互堵塞

## 同一消息内附带的操作要求（原样要点）

- 先用当前 OpenCode 的原生 skill 工具加载 fpga-orchestrator（2.0.28 参数为 {"id":"fpga-orchestrator"}）；必要时直接读取项目根下 .agents/skills/fpga-orchestrator/SKILL.md。
- 只有参数明确要求“执行”或“恢复”才启动角色链；本命令在当前主会话运行，不把主传输者另派成子代理。
- 按共享 Skill 及 references/opencode-calls.md 执行：主只原样传输和机械留档，规划理解并有限拆分，每任务新开发和一个新综合测试者，同任务修复续真实原 sessionID；主不监控，子角色自行有界停止。
- 继承根 AGENTS 的约束及当前客户端实际权限，不扩大授权，不使用 Codex 专属工具名。

## 上下文（主机械登记，非用户原话）

- 用户明确授权本轮 batch=2，并要求“进度优先，稳定性/优化后放”“尽量合并构建”。
- 硬边界：仅 SRAM、不写 Flash、不推送、不接 PCIe/RK；最后留“回来点两下”的上板清单。
- 基线 run（已 finished，只读参照）：`workflow/runs/20261018-1631_runA_fpga_side_readchannel/`
  - 机械摘录：4 包全 PASS；G3=partial、G4=not_run；板上 SRAM=新候选 bit bfafdf97…（主未独立验证）。
- 用户所指“之前交给 codex”的 run（并行，只读参照；本轮需先看其进展再接着做）：
  `workflow/runs/20261019-0212_codex_fpga_closedloop_b2/`
  - 机械摘录（来自其 main-log/dispatch/user-summary，主未独立验证）：
    - batch B01 = `T06.codex-ddr-readback-int` + `T09.codex-production-int`；两项 integrated r0 PASS（同 manifest 699 项，SHA c7a40897…；生产次数 6/6；实际修复 0）。
    - `T02.codex-singleA-board`：SRAM 下载 120 s 超时、无成功标记、加载状态 unknown；采样 0/3；blocked，未重试。
    - `T08.codex-sync-offline`：早期 blocked（离线 TB 编译次数上限）；最终任务表为 held。
    - 该 run 已于 261019 2112 左右收尾（`final-summary.md`、`board-checklist-final.md`、`handoff.md` 等存在）。
- 本机并行 OpenCode run（Track A，in flight，只读参照）：
  `workflow/runs/20261019-0207_runA_ddr_readback_loop/`
  - 机械摘录：P1 checker-integrate PASS r1；P2 build PASS r0；P3 sim-campaign PASS r0；P4 board-checklist awaiting_user_gui（未预加载；最近一次因 TD 窗口被并行 Codex 构建占用而未上板）。
- 用户要求“不要和 track A 相互堵塞”：规划须把本 run 与上述 Track A 线的板卡/TD 窗口、worktree、构建与候选冻结做互斥/并行安排，不得互相阻塞；具体归属与拆分由规划读取材料后决定。
- 仍然有效：禁止批量删除；不推送远端；不写 Flash；物理断电/接线等由用户操作（如需）。
- 默认每任务新开发 + 一个新综合测试者；用户本轮 batch=2 为实际实现批，不改变默认 4 包/两级/每包 5 项语义步骤上限，超限按有界规则切片。
