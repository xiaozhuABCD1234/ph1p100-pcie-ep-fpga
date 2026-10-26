# 原唯一T10测试者：只补同沿descriptor/release门槛

你仍为 `/root/fpga_tester_dual_scheduler_180900`，task `T10.dual-aplus-scheduler`、integrated formal round0、实际post-acceptance修复0。PROJECT_ROOT `D:/fpga/ph1p100`；run `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure`。读你的fpga-tester角色/现行有界合同、本次dispatch、`T10-r0-supplement01-plan.md` 和audit。沿用自己原r0上下文及有效证据，不再大范围重复读取/跑原套件，不派生、不换模型、不替换角色。

稳定问题 `T10.dual-aplus-scheduler:LIMIT_REACHED:descriptor-release-same-edge-coverage`；本次有限原责任角色补充机会1/2。你原45调用/2compile/19case停止、原report FAIL、checker构造/修正历史及读取timeout程序偏差全部保留。developer faults3/3未改变；当前不是开发修复或r1。

## 输入与额度

唯一开发manifest原路径与SHA `5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b` 不变；DUT core/frame/scheduler保持三份冻结SHA。原16个有效通过case、2个有效负对照及其122帧完整数据可由你按同输入逐项复用；首次fairness失败和纠正后PASS都保留，不重跑第3次。compile1 TB的原字节是自己 `*-compile1.sv` 保留副本，compile2是当前TB；不能混淆来源。

本次最多**16保守实际工具调用/20分钟，1次compile，1个case进程**。新工具/compile为原scope必要的有限补充账；累计最多61调用/3compile；本次case仅消耗原20总额中第20个，不能第21个或重命名绕数。开工先记录实际receipt/start及+20分钟绝对deadline，保留旧窗口、失败和原45/2/19。wrapper/native/wait全部计数，留足报告/最终核验。读搜60秒、compile/case300秒及TB watchdog，exec yield不冒充timeout；只控制自己进程。

不能原地执行r0/runner.py（旧O/ledger/deadline会修改旧证据）。只写 `test-reports/T10.dual-aplus-scheduler/r0/supplement01/**`，在此创建私有TB/monitor/runner/库/INI/log、实际输入manifest和补充报告。所有旧r0证据、根r0 FAIL、开发源码/manifest只读，T08不动。没有RTL/核/生产/参数协议改动、TD/硬件/构建/映射/下载/Flash/Git/删除/外部消息授权。

## 一个真实矩阵case的通过条件

只围绕唯一缺口制作有限小几何矩阵，可沿用你当前真实DDR/core/CMP环境和独立oracle。至少覆盖A/B、两slot，4个不同释放身份的行可同时包含跨camera及同camera不同slot的合法新descriptor。旧release身份与新free ingress身份须不同；**不要求仍owned的同槽在释放当拍ready**。合法valid/ready从端口达成，不force DUT内部owned/queue/state/rel或core。

1. 在先前真实帧已完成AR/R/编码、实际rel_valid等待时，借合法rel_ready背压配合一个free ingress descriptor，让同一个posedge同时出现 `(a_desc_valid&&a_desc_ready || b_desc_valid&&b_desc_ready)` 和 `rel_valid&&rel_ready`。前置/后置字段稳定，避免SV采样竞争；只能计同一个物理cycle，不能相邻拍或分别命中后相加。
2. 该沿逐字段日志记录descriptor全部camera/slot/epoch/session/seq/base/dma/raw/W/H/phase，release全部camera/slot/epoch/session/seq/status，以及独立scoreboard ownership before/after。释放只清旧身份，新接纳只保留新身份，其他held RAW/CMP不被改变；expected来自外部生产/请求历史，不能仅复制DUT内部状态自证。若同沿两路都接纳，要分别记账。
3. 让新帧随后真实被选择、读/编码/出CMP并匹配ACK；保留实际AR/R、源图案/长度/CRC和释放的独立检查，确认新旧两份身份无错路/提前/重复/丢失及容量破坏。用原oracle的数学/严格zlib数据判据，不以handshake marker单独PASS。
4. 每矩阵行给显式同沿hit和闭合结果，若缺任何必要hit或断言失败就FAIL/blocked。不要为了补命中再自动启动第2个case或第2次compile。

若该缺口暴露真RTL缺陷，保存实际最小反例，保持同stable coverage问题的关联，回原规划，不修改候选或伪称已修复。API/额度/容量/路径错误按真实原因直接回，不能自动换模型、创建替代或重置尝试；此次compile/case预算没有自动重试余量。

## 同一r0最终综合结论

全部检查结束，输入manifest及私有实际编译源前后SHA，复用旧有效case的路径/compile版本/日志/数据/实际source对应，写新的reuse-decision和same-input evidence index。旧根目录 `test-reports/T10.dual-aplus-scheduler-r0-integrated.md` 原FAIL必须保持字节不变。

新当前综合报告写 `test-reports/T10.dual-aplus-scheduler/r0/supplement01/T10.dual-aplus-scheduler-r0-integrated.md`，仍round0。写canonical-report.json明确当前有效报告、新报告SHA、旧FAIL历史路径/SHA、同一DUT及没有实现修复；不产生两份当前独立判定。新报告必须完整重汇总functional/engineering/system、G0/G1及所有旧有效检查和本补充，首行唯一PASS/FAIL。保留原报告中有效结果、首次fairness构造失败及已用2次、interface oracle修正、初始读取控制偏差、原计数45/2/19和本次/累计真实账。开发faults3/3、历史calls未知、G2/3/4未跑及父硬件未完成均不可抹除。

停止修改且自己活动命令0后返回原合同metadata及精确report/manifest/reuse/计数。未闭合时给完整problem_id/reason_code/new_information/evidence_path/requested_action/resume_input_path，由原规划决定；不自行继续或改r1。
