# T10.dual-aplus-scheduler — 离线G0/G1完成

formal round0 integrated PASS，post-acceptance实际修复0；当前唯一报告为workflow/runs/20261025-180900_fpga-dual-offline-closure/test-reports/T10.dual-aplus-scheduler/r0/supplement02/T10.dual-aplus-scheduler-r0-integrated.md，SHA256 ae758aa13e9eebb9df1b7922a23eec8d5c8aee0d53d316d63447d4e7b1e309dc。

唯一manifest：workflow/runs/20261025-180900_fpga-dual-offline-closure/T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json，SHA256 5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b。两旧r0 FAIL和旧canonical仍为历史快照，当前索引：workflow/runs/20261025-180900_fpga-dual-offline-closure/test-reports/T10.dual-aplus-scheduler/r0/supplement02/canonical-report.json。

原开发 /root/fpga_dev_dual_scheduler_180900；原唯一测试者 /root/fpga_tester_dual_scheduler_180900。16有效旧case122帧＋最后同沿矩阵8帧，共130严格还原帧和2有效负对照；原19进程加尚未执行第20个，未重跑旧套件。四次同物理cycle接纳/释放、完整身份/所有权与CMP持有/ACK均闭合。

测试累计69调用/4compile/20case；原45/2/19、补充01 12/1/0、补充02 12/1/1均保留。同问题机会2/2、夹具失败根因2/2、fairness2次，开发faults3/3未变；完整开发calls未知。原额度容量错误、失败/读取控制偏差/截止历史保留。

G2 STA/物理CDC/资源未跑，G3/G4曝光/板级恢复/稳定硬件吞吐待验证；100MHz TB单核约48.46MB/s，不是双路155.52MB/s实时。未合并T08、未迁生产/OpenCode、未TD/硬件/下载/Flash。父T10主源state/blocker/board_chain保持，不置done。回退为继续不采用隔离候选。

最终交接与证据：workflow/runs/20261025-180900_fpga-dual-offline-closure/handoff.md、delivery-index.md、candidate-binding-final.json、final-summary.md。
