# 仿真交付索引

本轮原两项仿真目标已完成，四正式包r0独立PASS。以下是隔离副本和证据入口，不是生产或上板候选。

|交付|入口|
|---|---|
|T08.sync-production-sim|[独立报告](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T08.sync-production-sim-r0-integrated.md) / [唯一manifest](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/T08.sync-production-sim/manifest-r0.json)|
|T10.a1-uart-descriptor-fix|[独立报告](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T10.a1-uart-descriptor-fix-r0-integrated.md) / [唯一manifest](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/T10.a1-uart-descriptor-fix/manifest-r0.json)|
|T10.a1-abort-cdc-fix|[独立报告](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T10.a1-abort-cdc-fix-r0-integrated.md) / [唯一manifest](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/T10.a1-abort-cdc-fix/manifest-r0.json)|
|T10.a1-recovery-sim|[独立报告](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T10.a1-recovery-sim-r0-integrated.md) / [唯一manifest](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/T10.a1-recovery-sim/resume02/manifest-resume02.json)|

最终A+修正文件：

- [camera_a1_uart_top.v](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/T10.a1-abort-cdc-fix/candidate/camera_a1_uart_top.v)
- [a1_uart_export.v](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/T10.a1-uart-descriptor-fix/candidate/a1_uart_export.v)
- [完整8RTL绑定](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/recovery-dut-binding-resume02.json)
- [双路overlay来源映射](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/T08.sync-production-sim/source-to-overlay.json)

交接与边界：

- [最终候选/SHA索引](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/candidate-binding-final.json)
- [最终指南](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/fpga-design-guide-final.md) / [最终输入索引](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/input-index-final.md)
- [完整总结](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/final-summary.md) / [交接](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/handoff.md)
- [20项实际结果](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/verification-summary-final.json) / [全部原账](D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/budget-ledger-final.json)

G0/G1通过，G2未运行，G3/G4/G5本离线包不适用；旧AR在reset时尚未完成的额外交错未覆盖。生产/TD/位流/下载/Flash均无操作，父硬件任务未置done。原失败日志/冻结输入保留，复现请使用新隔离输出目录。
