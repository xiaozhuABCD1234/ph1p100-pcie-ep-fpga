# 20261024-221529_fpga-sim-integration-recovery 离线仿真收束

本轮finished，用户原两项仿真目标完成，四包r0独立PASS/实际验收后修复0。父硬件任务state保持原值，G2/硬件/性能未升级。

- T10.a1-uart-descriptor-fix: PASS；manifest SHA fd0cb6e7f920ba136049fdadd395f029bcd9df3d58dc2d14a2312e9a0d3c33e1；报告 workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T10.a1-uart-descriptor-fix-r0-integrated.md。
- T10.a1-abort-cdc-fix: PASS；manifest SHA db84411dfdcf979b1fc5f6a25e11812f90f0834896a8b76787b85cd434fa5dcd；报告 workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T10.a1-abort-cdc-fix-r0-integrated.md。
- T10.a1-recovery-sim: PASS；manifest SHA 628579eae2b6b2c1afc66a477799960a6b180b213e848bdbc0e1e955437d82e1；报告 workflow/runs/20261024-221529_fpga-sim-integration-recovery/test-reports/T10.a1-recovery-sim-r0-integrated.md。

最终入口：workflow/runs/20261024-221529_fpga-sim-integration-recovery/delivery-index.md、candidate-binding-final.json、final-summary.md、handoff.md；原恢复累计60calls/4compile/27sim，独立tester29calls/2compile/21sim，问题机会1/0和旧失败均保留。旧AR在reset时未完成not_covered；不生产/TD/下载/Flash，不自动第五包。
