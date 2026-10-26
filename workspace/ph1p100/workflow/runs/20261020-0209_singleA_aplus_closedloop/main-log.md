# main-log（主传输留档，上海时间 yyMMdd HHmm）

| 时间 | 事件 | 真实返回/路径 |
|---|---|---|
| 261020 0209 | 用户显式调用 /fpga-orchestrator 执行；原话已保存 | workflow/runs/20261020-0209_singleA_aplus_closedloop/request.md |
| 261020 0209 | 需求文件存在性检查 True，9719 bytes（未由主读取内容） | docs/planning/2026-10-20-fpga-priorities/01_OpenCode启动需求_单A_Aplus闭环.md |
| 261020 0209 | 加载项目技能 fpga-orchestrator，读宿主适配/传输合同/有界规则 | .agents/skills/fpga-orchestrator/references/ |
| 261020 0218 | 服务重启后发现 `.agents/` 与根 `.git` 元数据已不在工作树；按用户“路径整理不要停”指示，用 general 子代理+重建规则摘要继续 | workflow/runs/20261020-0209_singleA_aplus_closedloop/role-rules.md |
| 261020 0220 | 规划完成 | ses_eaa7babd6ffed4RgqBNGtqMq1T；dispatch.json；4 包 |
| 261020 0224 | T10.a1-format-ref 开发 ready_for_test | ses_eaa728a0dffe6OKXhVG07nOd1Q |
| 261020 0227 | T10.a1-format-ref r0 综合 PASS | ses_eaa63fad2ffeEljGAT6ZrzM2h4 |
| 261020 0231 | T10.a1-enc-rtl 开发 ready_for_test | ses_eaa5c226effeCQEQn0fOCXxEKO |
| 261020 0235 | T10.a1-enc-rtl r0 综合 PASS（含 caveat） | ses_eaa43a47dffelNpnFUEP8B0DPm |
| 261020 0239 | T10.a1-frame-top 开发 ready_for_test | ses_eaa344977ffeEUtkGvdRoEgnTZ |
| 261020 0243 | T10.a1-frame-top r0 综合 FAIL（F1/F2/F3+覆盖缺口） | ses_eaa0e65a8ffeYW4JiQpQgv8W12 |
| 261020 0248 | frame-top r1 修复后 r1 综合 PASS | 原 dev/tester session |
| 261020 0255 | eng-freeze r0 blocked（Fmax 84.7 MHz） | ses_ea9d6d1f4ffeH9nIboqR1RgofJ |
| 261020 0302 | 规划批准 r1 有限修复（+1 TD） | dispatch-p4-r1.json |
| 261020 0307 | eng-freeze r1 blocked（Fmax 109.3 MHz） | p4/result-r1.md |
| 261020 0312 | 规划批准 r2 最终修复（+1 TD，无 r3） | dispatch-p4-r2.json |
| 261020 0319 | eng-freeze r2 blocked（Fmax 109.589 MHz，未 route） | p4/result-r2.md |
| 261020 0324 | 规划收尾 finished：3/4 PASS + 1 ⚠；T10 未完成；tasks.json T10=blocked | final-summary.md / user-summary.md |
| 261020 1432 | 按用户指示重建 `.agents/skills`：从 10-17 快照复制角色技能，重写 orchestrator/planner/dev/tester 与 work-limits/relay/report/opencode 参考 | .agents/skills/RECONSTRUCTION-NOTES.md |
| 261020 1435 | 技能注册恢复（fpga-tester 等）；`.opencode` 链接无需改配置 | skill registry |
| 261020 1436 | 原规划恢复并冻结 r3：TD 2 会话/120 min，187.5 MHz 不放宽 | ses_ea81f0e05ffeoC0dhoYZVxDKPg；dispatch-p4-r3.json |
| 261020 1439 | r3 开发 blocked：G1 PASS；S2 WNS -2.374 ns、Fmax 129.752 MHz；未 route | ses_ea81b4c66ffeP3pJwtUELqf9tj；p4/result-r3.md |
| 261020 1440 | 规划裁决不批 r4（三轮上限已满），status=needs_user_input | question-r4-authorization.md |
| 261020 1444 | 用户原话授权：“授权 r4：2 会话 / 120 分钟” | 用户选择 |
| 261020 1446 | 规划冻结 r4：TD 2 会话/120 min，预取修复范围 | dispatch-p4-r4.json |
| 261020 1452 | r4 开发 blocked：S2 WNS -2.446 ns、Fmax 128.551 MHz、TNS -183.480；未 route | ses_ea81b4c66ffeP3pJwtUELqf9tj；p4/result-r4.md |
| 261020 1455 | 规划收尾 needs_user_input：建议 r5 架构级 packer 重排；A/B/C/D 选项 | question-r5-or-board.md |
| 261020 1555 | 用户选择：授权 r5 架构重排 3 会话/150 min | 用户选择 |
| 261020 1713 | r5 S1 -0.957 ns；连接中断 | r5/logs/td_stdout.log |
| 261020 2005 | r5 续跑完成：best WNS -0.949 ns / 159.185 MHz；3/3 综合 | p4/result-r5.md |
| 261020 2015 | 规划收尾 needs_user_input（r6 需授权） | question-r6-authorization.md |
| 261020 2025 | 用户三次“接着做”；规划按知情接受冻结 r6 2 会话/90 min | dispatch-p4-r6.json |
| 261020 2035 | r6 blocked：S2 -1.346 ns / 149.723 MHz；frame_top smem we 路径 | p4/result-r6.md |
| 261020 2045 | 规划冻结 r7（frame_top 纯流水，2 会话/90 min） | dispatch-p4-r7.json |
| 261020 2055 | r7 blocked：S1 -1.287 ns / 151.057 MHz；TNS -73.092/165 端点；core 路径超范围 | p4/result-r7.md |
| 261021 0100 | 规划冻结 r8（core raddr，最后局部补丁） | dispatch-p4-r8.json |
| 261021 0115 | r8 blocked：S2 -0.470 ns / 172.325 MHz；TNS -37.591/147 | p4/result-r8.md |
| 261021 0130 | 规划按“接着做”冻结 r9（2 会话/90 min） | dispatch-p4-r9.json |
| 261021 0223 | r9 中断：P2/P3 完成，TD 未开始 | r9/p2、r9/p3 |
| 261021 1307 | 服务器恢复；旧 dev 会话两次 ECONNRESET | — |
| 261021 1330 | 新 dev 会话续接 r9（ses_ea1e23ca4ffektSBE3mhiRtgfI） | — |
| 261021 1345 | r9 blocked：S2 SWNS -0.434 ns / STNS -45.639；2/2 综合、0 route | p4/result-r9.md；core af6ab54b |
| 261021 1400 | 用户指令：“执行r10”；规划冻结 r10（2 会话/90 min） | dispatch-p4-r10.json |
| 261021 1420 | r10 blocked：S1 SWNS -0.450 ns / STNS -51.634 / 144 端点；1/2 综合 | p4/result-r10.md；core 7a10917d |
| 261021 1425 | 证据偏差：r10 早期 P2 误写 r9/p2 日志（vlog.log 哈希变），r9/p2/result.json 未变 | result-r10.md §6 |
| 261021 1430 | 规划最终收尾 needs_user_input：A 保持 ⚠ / B 150 MHz+CDC / C 新架构包 | question-r10-final.md |
| 261021 1445 | 用户要求“跑通优先”；规划评估后推荐 C-lite：187.5 单时钟 + 真实 2-cycle hash/threshold，新包 T10.a1-g2-2cyc | question-next-route.md |
| 261021 1500 | 用户同意 C-lite；2cyc r0：S2 -0.092、35 端点（frame_top dq_r） | p4/result-r0.md |
| 261021 1530 | 2cyc r0-c：frame dq_r 修复，S3 -0.156/92 端点（core htab） | r0/td/syn_gate_timing_s3.rpt |
| 261021 1600 | 2cyc r1：综合 +0.134 PASS；route slice 83072>71680 失败 | r1/td/a1_g2_r1_Runs/phy_1/run.log |
| 261021 1630 | area-map：cmem 单写口，reg 68085→2549、slice 72904→15058、ERAM 4→8；routed -1.115（bm DRAM 长线） | T10.a1-area-map/p4/result-r0.md |
| 261021 1700 | bm-eram：bm 同步 ERAM；X bug 修复；synth -1.094（htab） | T10.a1-bm-eram/p4/result-r0.md |
| 261021 1730 | htab-eram：htab 4×ERAM，WNS -0.144；r1 literal -0.245；r2 S_EXT -0.017/1 端点 | T10.a1-htab-eram/p4/result-r2.md |
| 261021 1800 | r2-b 更差 -0.548 回退；route-only harness 失败；waive2 routed -0.436/138 端点 | result-r2-waive2.md |
| 261021 1830 | hit-pipe：synth +0.021；routed -0.577/311 端点；测试者 r0/r1 均 FAIL | test-reports/T10.a1-hit-pipe-r1-integrated.md |
| 261022 1200 | bm-prefetch：G1 全绿（33/33 逐位、1080p 81707B）；synth +0.021；routed -0.421/10 端点 | T10.a1-bm-prefetch/r2-waive/result-r2-waive.md |
| 261022 1400 | bm-addr：synth +0.113；routed **-0.087/27**（最佳 routed） | T10.a1-bm-addr/r0-route/result-r0-route.md |
| 261022 1520 | adler-smem：synth **+0.233**（最佳 synth）；routed -0.541/299 | T10.a1-adler-smem/r0-route/result-r0-route.md |
| 261022 1600 | 规划最终收尾 finished：T10 3/4 PASS + 1 ⚠；~30 轮/40 综合/7 布线；无 bitgen/下载 | final-summary.md §31、user-summary.md §41 |
| 261022 1800 | qor-retime：retiming+phys_opt，routed -0.039/45（最佳 routed） | T10.a1-qor-retime/r0/result-r0.md |
| 261022 1900 | final-combo：微修+策略，routed -0.091/12；未达 +0.2 | T10.a1-final-combo/r0/result-r0.md |
| 261022 2000 | 用户批准结构性分拍；规划冻结 T10.a1-pipe-split | dispatch-pipe-split.json |
| 261022 2350 | pipe-split r0 布线：SWNS +0.047、0/4,649 违例、hold +0.021、Fmax 189.179；33/33 逐位、comp 355,261 | T10.a1-pipe-split/r0/route.qor |
| 261023 0300 | 独立综合测试 PASS（G2 小顶，caveat 47 ps） | test-reports/T10.a1-pipe-split-final-r0-integrated.md |
| 261023 0310 | 规划里程碑收尾：G2 小顶 done；T10 父任务仍 blocked；需求二/三 blocked | final-summary.md §37、user-summary.md §47 |
