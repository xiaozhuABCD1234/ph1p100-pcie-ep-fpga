# 双路离线闭环最终交接

实际工程根 `D:\fpga\ph1p100`；run根 `D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure`。本次原两包离线G0/G1目标完成，最终dispatch为finished；不存在待自动派发的实现/实验/硬件动作。

## 唯一输入及入口

T08使用 `T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json`，SHA `38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3`。源码为该目录的candidate、dual_local_closure及其source-map/实际79项开发闭包；独立81项编译/14案例/字节oracle在 `test-reports/T08.dual-local-closure/r1/integrated-mode-fix02/`，正式round1报告在test-reports根。本包实际修复1；原r0 FAIL保持，edges两次已用满。

T10使用 `T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json`，SHA `5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b`；实际DUT在cmp-stall-fix01/candidate的core、frame、scheduler三文件。sources.f/integration-sources.tcl仅为源接入清单，不是TD执行授权。唯一当前round0报告/index在 `test-reports/T10.dual-aplus-scheduler/r0/supplement02/`，具体见candidate-binding-final。旧根r0及supplement01 FAIL/旧canonical索引是历史快照，不作为当前判定；不修改它们，也不把补充当实际修复1。

两个候选的数据接口遵循同一冻结指南，但各自只在独立环境被验收，尚未共同编译/联调。不能把两包PASS当作合并整机PASS；CRC reader与编码reader仍必须互斥拥有相应RAW槽，永久缺R的LOCK只能共同DDR reset解除。压缩stream和外层报文长度/CRC/身份仍各自按指南处理。

## 保留与复现

`candidate-binding-final.json`、`delivery-index.md`、`input-index-final.md`和正式报告提供准确路径/SHA；最终审计、预算和问题账分别为final-closeout-audit、budget-ledger-final、problem-ledger-final。原用户原话和所有continue/重试/只读授权保持原文件；旧程序偏差、未知账和超用历史不改写。

所有冻结来源、库和旧日志只读。将来确需复现，须由原规划先冻结一次新的有限执行输入/写域/预算，复用有效证据，检查原失败命令总次数；不可直接执行会写冻结目录或含过期deadline的旧开发/测试runner。禁止借新目录/ID清零：T08原edges2/2，T10开发faults3/3、fairness2次、覆盖问题机会2/2及夹具根因2/2都已记账。没有待后台运行的进程，主不继续wait/扫描或定时复跑。

回退：停止采用本run两条隔离候选，继续保留原生产路径；生产/OpenCode/TD/板候选从未被本run替换。没有删除、Git发布或硬件更改需要撤销。

## 后续边界与准确恢复文本

后续仅保留原计划的三个主题，不自动执行：两候选生产集成及G2/真实双相机曝光/恢复/长稳；双路实时服务架构与容量/吞吐取舍；原三算法共存与旧B10补丁迁入。当前服务率不足以支持双路RAW实时的主张，不能用平均压缩比或静态SHA免除实际性能门槛。

可在同run使用下列明确指令开始下一次**范围规划**，并由规划按当时tasks主源/并行候选和设备条件决定最小包；此文本本身不授予下载/Flash/TD/硬件操作：

`$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure；本轮目标：读取final-summary.md、handoff.md、candidate-binding-final.json和workflow/tasks.json，冻结下一阶段的有限目标与验收，不重复本轮已有效的离线实验。`

本run原规划 `/root/fpga_plan_dual_offline`；T08原开发/测试者 `/root/fpga_dev_dual_local_180900`、`/root/fpga_tester_dual_local_180900`；T10原开发/测试者 `/root/fpga_dev_dual_scheduler_180900`、`/root/fpga_tester_dual_scheduler_180900`。角色原ID能续则续，只有实际失效错误才文件恢复并登记真实映射，不预防性重建。
