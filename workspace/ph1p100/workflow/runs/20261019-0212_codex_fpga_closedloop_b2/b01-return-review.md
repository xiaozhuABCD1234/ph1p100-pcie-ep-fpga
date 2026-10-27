# 原规划对B01 blocked返回的处理
日期：2026-10-19。原规划=/root/fpga_planner_b2；原开发=/root/fpga_dev_closedloop_b01。来源dev-return-b01.json、两个development-report、candidate/development-result.json、manifest/evidence-index与实际失败日志。主未读技术材料。

## 事实与门槛
B01两任务都为partial development/blocked，ready_for_test=false。未创建综合测试者，未发生综合round0；实际修复round1–3均0。开发本地G1通过项是作者证据，不能记为独立综合PASS。无生产bit、CWC、最终DB，TD尝试0，无硬件操作。
联合TB第一次compile的隐式声明/未定义变量失败已保存first-compile-failure.txt；一次有新证据重排后第二次仍在rb_*声明处报8个vlog-2388，未开始DUT仿真。同一问题已经首次+一次重试。规划没有修TB、没有执行第三次命令、没有改名/换run绕限。
原规划重哈希manifest236项及evidence18项，0漂移，manifest SHA=2B328FC0A23ECAE57E8D95C6CA66E2C9726CC95B9D536EDD673380BCACFFEABE，见b01-planner-freeze-audit.json。该PASS只是冻结身份复核，不是RTL/G1/G2/板验判定。

## 状态与计数
| 包 | 当前状态 | G层/缺项 | 下一动作 |
|---|---|---|---|
| T06.codex-ddr-readback-int | blocked，未验收 | standalone局部证据；联合G1未编过，G2/CWC not_run | 保留同问题计数，需真实新增用户输入或外部条件变化由原规划明确恢复 |
| T09.codex-production-int | blocked，未验收 | core/adapter本地G1部分通过，overflow动态覆盖缺失，共享G2/CWC not_run | 与T06同冻结输入保留，不拆出假PASS、不换ID绕共享门槛 |
| T08.codex-sync-offline | ready | 原计划已列独立离线包；B01活动结束，同写树释放；不读取/改B01新实现 | 本次派发新独立dev，batch=1，后接一独立integrated tester |
| T02.codex-singleA-board | blocked_by_B01 / awaiting_hardware | 缺合格bit/CWC/DB以及真实GUI窗口 | 不上板、不把旧bit当新候选；保持两点击模板不可执行 |

problem_id固定T06.codex-ddr-readback-int:LIMIT_REACHED:integrated-tb-compile。该命令attempts=2，补充机会0，实际修复0。不是外部设备缺失，而是已触发本轮同失败命令上限；规则规定到限后仅真实新用户输入/条件变化可由原规划明确恢复，本次没有这样的新增条件。错误原因容易理解也不能视为授权重置。
开发报告已经包含最小技术纠正建议；规划不转交另一开发修复、不请求worker执行、不让T08代理顺手处理。恢复仍用本run、原task_id、原dev真实ID，计数必须保存。

## 独立继续的合法性
原dev-plan已列T08工作包，依赖为B01结束释放同写树，未要求B01必须PASS；原计划明确T02缺窗口时可batch1推进T08。本次仅执行此已冻结独立包，不增加目标/包数/层数。总包仍4、默认单包新dev/一tester，不复用B01角色。
B01 manifest包含原dev-plan.md与fpga-design-guide.md：本次不改这两文件。新的状态/细化写入本文件与task-T08-sync-offline.md，dispatch更新但不回填B01 manifest。T08允许写路径全部是未存在的新目录/新TB/本run sync-offline；禁止改任何B01manifest条目及全局sim文件表。
T08结束再交原规划收尾；本轮未获新增B01恢复条件时不自动回到失败命令。用户最后收到的总结须明确：RAW→DDR未闭环、新生产位流未产出、同步只离线原型，板清单当前尚不可执行。

## 准确恢复入口
恢复输入=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261019-0212_codex_fpga_closedloop_b2/candidate/development-result.json、candidate/manifest.json、problem-ledger.json及本文件。
未来用户如明确要求恢复T06/T09并允许在同问题下新增有限纠正尝试，由原规划先记录新增输入、有限值及原计数，再followup_task原开发/root/fpga_dev_closedloop_b01；不预防性探测旧ID。单纯状态提问不构成恢复。

