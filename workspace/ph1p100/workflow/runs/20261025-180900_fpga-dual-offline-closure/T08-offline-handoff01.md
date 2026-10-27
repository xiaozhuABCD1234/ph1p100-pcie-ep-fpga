# T08.dual-local-closure 离线交付收口

本包正式round1 integrated PASS，实际实现修复1。functional/engineering/system均在原G0/G1离线合同内通过；原round0 FAIL与缺陷证据保留。唯一原开发 `/root/fpga_dev_dual_local_180900`，唯一原综合测试者 `/root/fpga_tester_dual_local_180900`；无替代角色或拼接不同候选的总PASS。

唯一实现候选为 `T08.dual-local-closure/r1/mode-fix02/`，manifest `manifest-mode-fix02.json`，SHA256 `38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3`。正式独立报告 `test-reports/T08.dual-local-closure-r1-integrated.md`，最终回执时间2026-10-26 01:13:13上海；报告SHA256 `71ef63293bd253182ad23f04ac8889a29e1d7be8bc0a7cc4869dc12bb0e472aa`。本run所有路径以 `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure` 为根。

## 实际完成

描述符反压期间身份保持、同拍外部AR接纳/释放互斥、模式请求与发布同拍的所有权/无phantom路径，以及实际读回期间持续新帧输入均闭合。真实checked CSI、writer、arbiter、CRC reader、sync与pin I2C来源经独立重编译/绑定，原默认关闭路径回归通过。

本轮独立1次compile、14个case进程：mode矩阵、原edges、全部camera/slot/status矩阵、case16真实overlap、正常六对、case10–15、fresh contract、legacy与有效B-release误送A负对照。原edges保持r0同样刺激/期望，共首次失败+一次纠正输入复跑2次，余0。负对照被实际断言拒绝，未计作当前DUT故障。

测试者自己的字节oracle检查112份对象：106份实际4096B读回，其中2份是明确CRC损坏刺激，其余104份匹配；另6份legacy dump匹配。case16每路3个新SOF、1个不同槽完整pub落入真实AR至最后R窗口；每路保留2帧seq缺口，随后6个good恢复。normal每路六帧、四槽反复复用。模式8组合、12种camera/slot/status竞争与228bit完整描述符stall监视通过。

未变I2C/sync旧case1–9只由原综合测试者按72项源SHA、18参数、时钟/刺激一致性复用其旧证据，见 `reuse-decision-r1.json`、`additional-provenance-audit.json`；变化的consumer/offer/AR/所有权/overlap均fresh，没有继承旧总PASS。原r0总FAIL保持。

## 计数与边界

测试者r0：44调用/2compile/20case，FAIL。r1 quota前4调用/0compile/0case，continue03再25调用/1compile/14case；r1合计29/30调用、1/2compile、14/14case。全部测试历史73调用/3compile/34case，实际修复1。原quota、旧截止已过期、静态GBK错误一次有新证据纠正、真实中断时刻未知均保留。开发累计142调用/7compile/44case，原r0超用不追认成合规。

候选和独立81编译源前后匹配，314项manifest绑定无漂移。独立报告/receipt/source/reuse/log的规划静态复核见 `T08-planner-closeout01/audit.json`。规划没有重跑实验或改变测试者判定。

G2最终STA/资源/物理CDC，G3/G4曝光、板级恢复、稳定性和硬件吞吐均not_run/awaiting_hardware；小参数W8H2不证明双1080p30持续服务率。默认1920×1080 raw2592000/content2592128/dma2592768及四槽8MiB/29bit/4KiB边界是静态/离线证据。155.52MB/s RAW需求、最少311.04MB/s RAW写+读只是预算。生产、OpenCode候选、TD工程/bit及板上候选均未迁入本实现，父T08状态不置done。

## 交接与回退

已停止修改/活动命令0。后续复现须新获派发并将runner/库/日志写到自己的新允许域，冻结源和本轮证据只读；不能直接运行带旧deadline、会写冻结local的开发脚本。回退为停止采用隔离候选，生产没有被替换，无删除。

本包当前没有剩余必要离线复测，不自动运行余下compile/call或进入r2。后续生产集成、G2和真实双相机/曝光/恢复/长稳应由另次有界目标及硬件窗口承接，不由本PASS授权。

本run尚未结束：T10首次唯一独立测试者 `/root/fpga_tester_dual_scheduler_180900` 已真实派出，尚未收到综合返回。只接收其事件，不监控、推断PASS或重派。原规划收到T10返回后再做全run收尾。
