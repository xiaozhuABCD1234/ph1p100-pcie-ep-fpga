# 本轮需求（用户原话，原样保存）

## 用户参数原话（/fpga-orchestrator 执行）

> 执行：继续 FPGA 侧闭环验证，进度优先，稳定性/优化后放。
> 基线 run：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel
> 今晚无人值守推进 N1→N2→N3→N4→N5（DDR 读回校验集成→重建→几何回填→坏帧/100帧仿真→证据与上板清单），
> 最后留一份“回来点两下”的上板清单；仅 SRAM、不写 Flash、不推送；不接 PCIe/RK/三算法。
> 这版是按"进度优先、填满今晚、闭环最大化"排的；如果新对话的规划角色认为 N1/N3 可以合并成一次构建，会更省时间，不影响你回来的验证节奏。

## 同一消息内附带的操作要求（原样要点）

- 先用当前 OpenCode 的原生 skill 工具加载 fpga-orchestrator（2.0.28 参数为 {"id":"fpga-orchestrator"}）；必要时直接读取项目根下 .agents/skills/fpga-orchestrator/SKILL.md。
- 只有参数明确要求“执行”或“恢复”才启动角色链；本命令在当前主会话运行，不把主传输者另派成子代理。
- 按共享 Skill 及 references/opencode-calls.md 执行：主只原样传输和机械留档，规划理解并有限拆分，每任务新开发和一个新综合测试者，同任务修复续真实原 sessionID；主不监控，子角色自行有界停止。
- 继承根 AGENTS 的约束及当前客户端实际权限，不扩大授权，不使用 Codex 专属工具名。

## 上下文（主登记，非用户原话）

- 同一参数由用户在会话中发送两次，内容一致；此处登记一次。
- 基线 run（已 finished，只读参照）：workflow/runs/20261018-1631_runA_fpga_side_readchannel/
  - 终态（自其 dispatch.json/main-log 机械摘录）：4 包全 PASS；G3=partial、G4=not_run；板上 SRAM=新候选 bit bfafdf97…；DDR 读回校验核心 RTL+TB 已 PASS、未集成（集成留后续主题）。
- 上一对话机械登记的清单来源（原样登记，供规划读取）：
  - user-precheck §7：workflow/runs/20261018-0001_merge_raw_into_upstream/user-precheck.md
  - next-round-proposal：workflow/runs/20261018-1347_runA_offline_sim/next-round-proposal.md
  - 基线 run：dev-plan §7、handoff.md、final-summary.md、input-index.md、user-input-13.md
- 仍然有效：禁止批量删除；不推送远端；不写 Flash；物理断电/接线等由用户操作（如需）。
- 默认 BATCH_SIZE=1；用户提示（原话见上）：若规划认为 N1/N3 可合并成一次构建会更省时间。
