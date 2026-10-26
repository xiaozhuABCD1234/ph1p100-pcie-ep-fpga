# user-summary-05.md — 决策已记录 + 启动文本已备好

**一句话：压缩路线按你定的来——先 A（标准 DEFLATE 流）+ 预留 Rice 第二模式（A+），阶段 1 全过后再做 C（逐块自适应：标准子流/Rice/RAW）。新对话的启动文本已经写好在 `new-run-prompt.md`，整段复制粘贴即可，不用改字。**

- 阶段划分：阶段 1（本 run 必做，4 包）= A+；阶段 2（阶段 1 全 PASS 后）= C（Rice 引擎 + 逐块选择），资源/时间/规则口径满足才启动；不满足就把 C 转后续，阶段 1 候选先交付（不静默丢 C）。
- 启动方式：
  - OpenCode：打开 `new-run-prompt.md`，复制「OpenCode 版」整段（第一行是 `/fpga-orchestrator 执行：…`），粘贴到新对话发送。
  - Codex：把第一行换成 `$fpga-orchestrator 执行：…`，其余不动。
- 边界已写进启动文本：不接 PCIe/RK、不写 Flash、不推送；涉板仅 SRAM；与 0212/Track B 独立 worktree、不碰对方文件、TD/板卡窗口串行；长稳/RK 先放。
- 本次没有派发任务、没改任务板、没碰代码或板子；0207 run 保持 finished。
