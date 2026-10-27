# 主传输日志（新 run）
- 261027 0726 runtime=OpenCode；用户显式启动板级集成新 run；登记用户原话与确认；PROJECT_ROOT=D:\fpga\ph1p100；BATCH_SIZE=1；沿用5倍防死循环额度（仅限本新任务）。
- 261027 0726 上游 run 20261026-2138_fpga-integrated-delivery 已收尾：P1/P2/P3=PASS，P4=⚠；功能基线 r2 manifest DFAB7F9D…；禁止 r3 派生变体；新 run 输出目录已建。
- 261027 0726 准备新建规划角色（新 run，干净上下文），传入 request.md、上游 handoff/final-summary/follow-on-run-request 与技能/设计指南路径。
- 261027 0730 runtime=OpenCode；subagent真实返回新run规划ID=ses_e85761830ffeyOloIjpjizuumr；返回ready：T11.BRD.P1，4包链（P1 ready，P2-P4依赖），dispatch已写；preflight提示T:仍指向b20 r0/td，构建前须td_env.ps1 -Force重指，且无他人TD会话。
- 261027 0730 准备按dispatch新建T11.BRD.P1开发角色（板级顶层/时钟复位CDC/真实约束/构建入口/G1缩尺仿真/整机bit条件满足时；不下载不Flash）。
- 261027 0800 runtime=OpenCode；subagent真实返回T11.BRD.P1开发ID=ses_e85651b61ffesAiCs1MzdIu7lb。
- 261027 0800 T11.BRD.P1开发返回ready_for_test；manifest=T11.BRD.P1/manifest-brd-p1-r0.json（27份产物哈希、stopped_modifying=true）。自报：G2p fail（150MHz WNS-2.273/TNS-31.547/79端点，不出bit；125MHz未测，TD会话4/4、synth3/3用尽）；G1正例fail（帧完整/P4已提交，但出口适配器始终不发desc_arm→无槽读/无MWr/无doorbell）；偏差需批（SLOT_WORDS=81920/BASE=2048、BAR 0x130..0x13C未实现、DDR×4重映射仅仿真）；发现r3派生文件在integrated_delivery/，r2依赖取自INT.P4/r2-timing-experiment/并对r3设硬守卫；TD计数sessions4/synth3/route0/bitgen0/CWC0。按spawn_single_tester新建唯一综合测试者。
- 261027 0810 runtime=OpenCode；T11.BRD.P1 round0综合测试者创建失败：ECONNRESET(sessionID=ses_e8537c37effeA3qXxO0TiJokgC)，无返回/无报告；按外部API错误登记，未据此判FAIL；用户指示接着做，重建新综合测试者（同名任务，无既有计数可续）。