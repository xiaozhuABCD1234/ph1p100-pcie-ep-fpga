# T08.dual-local-closure — 离线G0/G1收口

正式round1 integrated PASS，实际修复1；原r0 FAIL与全部历史失败/超用保留。父T08硬件任务未完成，状态保持。

唯一manifest：workflow/runs/20261025-180900_fpga-dual-offline-closure/T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json
SHA256：38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3

独立报告：workflow/runs/20261025-180900_fpga-dual-offline-closure/test-reports/T08.dual-local-closure-r1-integrated.md
SHA256：71ef63293bd253182ad23f04ac8889a29e1d7be8bc0a7cc4869dc12bb0e472aa

详细交接：workflow/runs/20261025-180900_fpga-dual-offline-closure/T08-offline-handoff01.md

规划复核：workflow/runs/20261025-180900_fpga-dual-offline-closure/T08-planner-closeout01/audit.json

原开发 /root/fpga_dev_dual_local_180900；唯一原测试者 /root/fpga_tester_dual_local_180900。14 fresh case、独立112数据对象、有效B-release负对照；I2C/sync旧部分由原测试者按新manifest源/参数/刺激绑定复用。

本轮r1总29/30调用、1/2compile、14/14case；测试者全历史73调用/3compile/34case；original_edges2次已满。开发142调用/7compile/44case及r0超用保留。无自动复跑/新增修复。

G2 STA/资源/物理CDC未跑；G3/G4曝光/板级恢复/稳定吞吐awaiting_hardware。未迁生产或OpenCode候选、未TD/硬件/下载/Flash。回退为停止采用隔离mode-fix02，原生产未替换。

本run尚未结束：T10原首次唯一综合测试者已派出，尚未收到判定；不赋PASS，不监控、不重派。

## 本run最终收口

T10现已同输入formal round0综合PASS，post-acceptance实际修复0；本run两个原离线包全部完成。上文T10待返回为当时的部分收口历史。T08 r1 PASS、实修1及所有证据不变；父硬件状态不因本run置done。最终交接和SHA索引：workflow/runs/20261025-180900_fpga-dual-offline-closure/handoff.md、candidate-binding-final.json、final-summary.md。
