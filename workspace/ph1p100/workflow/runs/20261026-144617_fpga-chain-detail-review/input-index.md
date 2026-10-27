# 审查输入索引

本轮根：`D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review`。原话 `request.md`；任务/验收 `dev-plan.md`；工程语义 `fpga-design-guide.md`；下一动作 `dispatch.json`。

## 统一快照

`baseline/source-manifest.json`记录每项原始绝对路径、仓库相对路径、快照路径、SHA256、大小及复制前后漂移检查；`baseline/snapshot/`供四包只读复用。`baseline/git-status.txt`保存规划时已有修改/删除，仅识别保护范围；`baseline/git-worktrees.txt`登记工作树，不授予其他树写权。快照是审查样本，不是可构建板级候选，不会把不同分支局部PASS拼成整机。

## 采用版本与证据角色

| 输入准确路径（均相对D:/fpga/ph1p100） | 用途与边界 |
|---|---|
| AGENTS.md；.agents/skills/fpga-planner/SKILL.md；fpga-design-guide及fpga-dev/fpga-tester技能；orchestrator/references/{work-limits,relay-contract,report-contract,project-context}.md | 当前工作流规则，源文件只读 |
| README.md；CODEX_HANDOFF.md；workflow/README.md；workflow/tasks.json | 入口/全局调度；任务板snapshot_date=2026-10-20，不以旧状态盖新证据；本轮不修改 |
| docs/项目成果整合与进度复核_2026-10-25.md | 10/25 11:01–11:03状态，后续结果分别补证 |
| docs/OpenCode_b15根因审计与定位建议_2026-10-26.md | 地址/mask/并发/计数字段审计及条件模型，非真实MC最终根因 |
| workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b15-ddr-pace/{CANDIDATE-MANIFEST-b15-ddr-pace-r0.json,result-r0.md,r0/changed-src/*,r0/td/src/*,r0/td/a1_board.al,r0/td/p2_board.sdc,r0/sim/p2_paxi_model_b15.v} | 本轮主要A+板级诊断源与模型，逐项与manifest/编译路径核对；b15未闭环 |
| 同b15 r0/td/src/vendor/rtl/mtest/{paxi_stg_cmd_gen.v,ph1p_ddrmc_mtest.v}；r0/td/src/vendor/ip/ddrmc_x32/src/rtl/top/ph1p_ddrmc_top.v | 与该候选绑定的原生地址/mask/接纳参考；不泛化其他IP版本 |
| 同b15 r0/board/captures/status_v5.txt；tools/a1/pc_decode.py | 累计计数/字段及诊断解码来源；不代替逐事务证据 |
| workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b11-aplus-read/ | 稳态分析的生产top来源，只读旧候选；不与b15混为同输入 |
| workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b17-paxi-native/{dev-plan,fpga-design-guide,input-index}.md | 规划读取时有计划无实施/验收；另一活动线，保护整个目录 |
| fpga/csi2/src/**；upstream/ph1p100-pcie-ep-fpga/rtl/**；parallel/frame/frame_contract.py | 既有CSI/图像/存储/PCIe/RAW合同参考；源码存在不等于被当前top采用 |
| workflow/runs/20261019-0212_codex_fpga_closedloop_b2/test-reports/{T06.codex-ddr-readback-int-r0-integrated.md,T09.codex-production-int-r0-integrated.md} | 既有生产离线集成证明，核对真实编译路径和输入后才引用 |
| workflow/runs/20261024-221529_fpga-sim-integration-recovery/{delivery-index.md,T08.sync-production-sim/} | 同步/恢复隔离仿真与源映射，不是当前板级曝光同步 |
| workflow/runs/20261025-180900_fpga-dual-offline-closure/{delivery-index.md,T08.dual-local-closure/,T10.dual-aplus-scheduler/} | 双路离线调度/恢复，单独候选 |
| workflow/runs/20261025-233401_fpga-steady-state-reverdict/{user-summary.md,final-summary.md,T10.ss-4run-matrix/r0/manifest-r0.json,test-reports/T10.ss-4run-matrix-r0-integrated.md} | 最新已验稳态scope与sink/内容限制；不重复四帧长仿真 |
| workflow/runs/20261026-143924_fpga-1080p30-g0-production/request.md | 另一活动run的有限目标与保护边界，本轮只读不重复开发 |
| docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md；docs/DeepSeek独立检测与现行方案整合_2026-10-16.md；docs/双目首版_整链路方案与团队交付.md | 历史方向/接口背景，RAW12/Rice旧描述不覆盖后续LZ77/A+用户决定 |

快照清单是实际存在路径的权威枚举；上表通配符只是导航。缺项记 `baseline/missing-inputs.json`，开发不能据上表文件名声称已读/已验。需要补充相关只读源时，包内另冻来源与SHA，不能更改统一baseline；实质改变目标基线交原规划。

## 所有者与保护

主仓库预存dirty/删除归原活动工作，未知所有者一律保护；Bayer工作树由独立轨道持有，不写。b17与143924均为活动线，本轮0设备/0共享ModelSim库/0盘符映射。docs实际指向OneDrive，仅源资料读取。新任务只写自身目录，测试只写本run/test-reports，规划只写本run控制和收尾。

DeepSeek仅把给定b15审计短摘录转换为6类证据边界，未读取项目文件、未作架构决策、未执行命令；原返回与独立核对见 `planning/deepseek-result.json`、`planning/deepseek-review.md`。不采用其中关于“非R响应”、把事务计数说成延迟统计、或否认已执行条件模型结果的错误转述。
