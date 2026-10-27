# 主传输日志

- 261026 2317 runtime=opencode；PROJECT_ROOT=D:\fpga\ph1p100；RUN_ID=20261026-231711_fpga-a-plus-h-prototype。
- 261026 2317 保存用户原话“尝试做A+H”与背景至 request.md；使用项目 fpga-orchestrator 工作流，主仅传输。
- 261026 2317 本轮目标：A+H 隔离 RTL 原型，先 H-only（2 B/cycle emit）再 A+H（2-position literal scan）；N/L 自然内容 4 帧 G0 ≤6.25M；A1U1/zlib 输出逐字节不变；只做离线 RTL/仿真，0 TD/板卡/下载/Flash/RK/网络。
- 261026 2317 约束：新 run；不碰 20261026-2138_fpga-integrated-delivery、20261026-144617_fpga-chain-detail-review；不改 b18/b19/b20、生产源、旧 P1–P4、tasks.json、docs/work/.agents；TD/板卡未经用户单独授权不做；4 帧单次约 22 min，规划需冻结有界预算。
- 261026 2317 规划角色即将派发；等待原生 subagent 返回真实 sessionID 与 dispatch 路径。
- 261026 2330 规划返回 ready：runtime=opencode、role=fpga-planner、sessionID=ses_e87353f24ffeWKBFxTR4tV0qzW；dispatch=P1 T10.ah-honly（ready），P2 A+H/P3 verdict 均 blocked。P1 冻结：基线 N/L 4 帧 + H bench comp/rand + H N/L 1 帧探针；预算 60 calls/180 min、4 次 full/probe、≤7200 s、单次 ≤2700 s；H 放行 P2 阈值 N ≤6,500,000 且 byte-exact。b11 core SHA=a91c2ed8…81b3e，frame_top=0064607a…7109；b6 core=6797db05…35bb；content raw40 N=e44fe7bc…、L=e7e3c21c…。
- 261026 2330 P1 新建唯一 fpga-dev；只做 H-only（2 B/cycle emit），不改 A；0 TD/板卡/网络；不改其他 run。
- 261027 0035 P1 H-only 开发返回 ready_for_test（N 全通过；L 探针未跑，partial/not_proven）：runtime=opencode、role=fpga-dev、sessionID=ses_e871a3611ffe23q9a9r6mIz2Jp；manifest=r0/manifest-r0.json（106 artifacts；SHA256=a0c564cab23962acd4f21df047223b4b884d68a98910d25c527b7a70fa7fa1a1；stopped_modifying=true/active_commands=0）；blocked=[]。Baseline N/L 4 帧精确复现（N 7,475,240/7,476,245；L 6,986,952/6,979,811；各 4 header）。H bench 8/16-bit：comp 2601d57c…a7c05/50,310 B/304,961 cycles；rand 54f262f2…496dd/153,766 B/161,479 cycles；byte-exact。H N 1 帧：6,197,186 cycles（2.39089 c/B），比模型 6,260,648 好 63,462，**已低于 G0 6,250,000**；header/CRC/last byte/counters 与 baseline 全等；无 stall/timeout。H L 1 帧 not_run（4/4 full/probe 用尽，未开第 5 次），L near-model ≤6,010,000 not_proven。6,500,000 release check N PASS。
- 261027 0035 AGENTS 更新：权威 FPGA 仓 https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga，本地完整 checkout D:\fpga\repos\ph1p100-pcie-ep-fpga；当前活动 run 仍在 D:\fpga\ph1p100，不搬动/重置；后续新任务优先在正确 checkout 开展。本 run 继续在现工作区收口，原型 diff 后续需按新仓 main 迁移评审，不能直接把旧工作区历史推入两仓。
- 261027 0035 按 dispatch 新建 P1 唯一综合测试者 round0；核 baseline/bench/H N、L not_run、manifest/写范围/0 TD；不把 H N 当 L 通过。
