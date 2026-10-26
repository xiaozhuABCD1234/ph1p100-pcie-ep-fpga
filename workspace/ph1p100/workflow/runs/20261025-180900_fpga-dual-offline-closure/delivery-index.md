# 最终交付导航

本run两个原正式包均离线G0/G1 PASS；两份独立隔离实现，不是合并整机。所有相对路径以本文件目录为根。

|内容|文件|
|---|---|
|自含用户短总结|[user-summary.md](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/user-summary.md)|
|结果、证据与证明边界|[final-summary.md](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/final-summary.md)|
|复现注意、回退、原角色与恢复指令|[handoff.md](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/handoff.md)|
|最终输入/原话/授权导航|[input-index-final.md](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/input-index-final.md)|
|唯一候选/当前报告完整SHA|[candidate-binding-final.json](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/candidate-binding-final.json)|
|最终静态证据复核|[final-closeout-audit.json](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/final-closeout-audit.json)|
|历史预算/超用/未知账|[budget-ledger-final.json](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/budget-ledger-final.json)|
|已闭合问题及历史外部错误|[problem-ledger-final.json](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/problem-ledger-final.json)|
|并行安全主任务板更新回执|[final-taskboard-update.json](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/final-taskboard-update.json)|
|T08正式r1独立报告|[T08 r1 PASS](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/test-reports/T08.dual-local-closure-r1-integrated.md)|
|T08唯一manifest|[mode-fix02 manifest](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json)|
|T08完整单包交接|[T08-offline-handoff01.md](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/T08-offline-handoff01.md)|
|T10当前唯一正式r0独立报告|[T10 r0 PASS](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/test-reports/T10.dual-aplus-scheduler/r0/supplement02/T10.dual-aplus-scheduler-r0-integrated.md)|
|T10当前/历史报告对应|[canonical-report.json](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/test-reports/T10.dual-aplus-scheduler/r0/supplement02/canonical-report.json)|
|T10唯一manifest|[static-closeout02 manifest](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json)|
|T10最后同沿完整身份矩阵|[independent-edge-audit.json](D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/test-reports/T10.dual-aplus-scheduler/r0/supplement02/matrix/independent-edge-audit.json)|

原T08 r0 FAIL、T10根r0 FAIL和supplement01 FAIL仍在原路径；T10旧canonical是各时间点历史快照，以本索引指向的supplement02当前报告为唯一最终结论。原始日志、负对照、计数、过期窗口、quota/capacity错误和未知历史均不删除或覆盖。

主源单包记录在工程 `workflow/records/T08/20261025-180900-dual-local-closure.md` 与 `workflow/records/T10/20261025-180900-dual-aplus-scheduler.md`；任务板仍是工程 `workflow/tasks.json`。本run只补证据，不升级父硬件state。
