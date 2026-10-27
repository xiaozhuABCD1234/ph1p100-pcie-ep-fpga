# 主传输日志

- 261027 1500 runtime=opencode；PROJECT_ROOT=D:\fpga\ph1p100；RUN_ID=20261027-150010_fpga-honly-td-route。
- 261027 1500 保存用户原话“先做1”与上一轮二选一背景至 request.md；使用项目 fpga-orchestrator 工作流，主仅传输。
- 261027 1500 本轮目标：H-only 候选（core d2960cfe / frame_top 4afc26e2 / synthfix manifest 034777c5）TD route 绕行，绕过 TD 6.2.3 import_db→Import ChipWatcher coredump，取得 routed DB + routed STA（187.5MHz，209.6 analysis-only 可选）；不改 RTL/SDC/时钟/例外；0 bitgen/板卡/网络。
- 261027 1500 用户授权新 TD 配额：TD 启动 ≤3、synth ≤1、route ≤2、analysis ≤1、bitgen 0、download/Flash/board 0；TD 独占 preflight，不抢 board-integration/integrated delivery 的 TD/T:。
- 261027 1500 规划角色即将派发；等待原生 subagent 返回真实 sessionID 与 dispatch 路径。
- 261027 1510 **AGENTS 新覆盖（2026-10-27）**：FPGA 板已交队友；本机只做仿真/编译/软件参考/静态核对/源码证据整理/已授权主仓同步；**本机不再启动 TD 综合、布局布线、STA、bitgen、CWC、COM/JTAG、下载或 Flash**；构建/最终时序/位流/实机由持板队友执行；后续成果以 D:\fpga\repos\ph1p100-pcie-ep-fpga 为实际工作根。该边界优先于旧 TD 配额。
- 261027 1510 规划返回 blocked/needs_user_input：runtime=opencode、role=fpga-planner、sessionID=ses_e83d60ee4ffeS5i0AsNjSAEWSN；problem_id=T10.ah-td-route:PERMISSION_MISSING:local-td-boundary；question-01.md；建议降级为队友执行包 T10.ah-td-route-kit（本机 0 TD；提供最小复现/单会话 synth→place→route 不 import_db 的绕行命令/门槛/证据模板），或需用户明确覆盖新边界才可本机 TD。实测 TD 物理空闲（0 进程、三目录 538/537/407 min 静默），但 blocked 原因是权限边界，不是占用。
- 261027 1510 本轮未启动 TD/仿真/候选改动；等用户确认队友执行包或明确覆盖边界。
