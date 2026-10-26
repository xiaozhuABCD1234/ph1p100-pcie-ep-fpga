用户显式选择了本项目的 /fpga-orchestrator 入口。以下是参数原文，原样保存与转发：

执行：FPGA 侧闭环加速推进，进度优先，稳定性/优化后放。
基线 run：C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261018-1631_runA_fpga_side_readchannel
本轮明确授权 batch=2：Track A=单A RAW→DDR 板级闭环（读回校验/几何/坏帧）；
Track B=T09 三算法并入生产工程+离线仿真+双相机同步RTL离线起步。
尽量合并构建；仅 SRAM、不写 Flash、不推送；不接 PCIe/RK；最后留“回来点两下”的上板清单。 

先用当前 OpenCode 的原生 skill 工具加载 fpga-orchestrator（2.0.28 的参数是 {"id":"fpga-orchestrator"}）；必要时直接读取项目根下 .agents/skills/fpga-orchestrator/SKILL.md。

只有参数明确要求“执行”或“恢复”才启动角色链。参数为空、只讨论/查看/修改规则时不启动，也不把选择本命令本身当执行需求。本命令在当前主会话运行，不把主传输者另派成子代理。

按共享 Skill 及 references/opencode-calls.md 执行：主只原样传输和机械留档，规划理解并有限拆分，每任务新开发和一个新综合测试者，同任务修复续真实原 sessionID；主不监控，子角色自行有界停止。继承根 AGENTS 的约束及当前客户端实际权限，不扩大授权，不使用 Codex 专属工具名。

这个本来是opencode的任务，修改为codex试用，然后还是使用工作流skill去做吧
