# T10 原唯一测试者：最后一次同问题有界补充

PROJECT_ROOT `D:/fpga/ph1p100`；run `D:/fpga/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure`；原真实ID `/root/fpga_tester_dual_scheduler_180900`；task_id `T10.dual-aplus-scheduler`；integrated formal round0，post_acceptance实际修复0。读fpga-tester/现行有界合同、`dispatch-T10-r0-supplement02.json`、`T10-r0-supplement02-audit.json`，以及原supplement01计划的技术门槛；不要重读/重跑完整原套件，不派生、不换模型、不更改DUT。

稳定问题仍 `T10.dual-aplus-scheduler:LIMIT_REACHED:descriptor-release-same-edge-coverage`。补充机会1已用，本次**2/2最后一次**。上一编译Error1/Warning0、exit2，`tb_same_edge.sv:91`在`:172`的module reg声明前使用same_edge_manual；这个真实新诊断支持本次参数/夹具纠正。此前该失败编译根因只尝试1次，本次是同失败命令第2次，换目录/文件名不重置次数，不能第三次。不是DUT功能失败或实现修复。

## 唯一修正及新写域

只写 `test-reports/T10.dual-aplus-scheduler/r0/supplement02/**`。所有supplement01及原r0文件、FAIL报告和canonical索引保持原字节；开发manifest/三DUT文件、T08、规划输入、生产/OpenCode/TD均只读。

从supplement01复制自己的私有TB和必需helper/runner到新域。**只把 `reg same_edge_manual=1;` 移到该module第一次引用之前的声明区，保留初始化值且只声明一次**；原同一行的 `reg [3:0] sb_owned=0,sb_next;` 保持语义。保存真实diff，静态检查所有引用/声明和SV语法后再用最后一次编译，不先靠实验探路。不改四行矩阵/八帧期望、scoreboard、valid-ready采样、完整字段/字节oracle或放宽断言；不能以空wrapper/换top绕真实场景。

helper/runner只在自己的新域修正O/INI/lib/cwd/log/ledger/guard与真实本窗口deadline，不导入会写旧目录的helper，不沿用已启动的execute-started标记。纯路径/截止适配不能改变CRC/图案/身份判据。DUT直接只读编译相同三文件SHA。记录私有输入补充manifest；开发唯一manifest仍 `T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json`，SHA256 `5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b`。

## 最小安全预算和停止

本次最多**16保守实际工具调用/15分钟、1次compile、1个case进程**。起点为实际收到followup/首次可观察入口，命令前记录start/deadline(+15分钟)，不回填平台receipt或改旧窗口。保守wrapper/native/wait皆计数，留足报告和最终核验。原累计57调用/3compile/19case不清零；新累计上限73调用/4compile/20case。该case仍是原20总额尚未运行的第20个，不新增第21个。原supplement01未使用的call余量不反写成已用或从历史扣除。

读搜60秒，compile/case300秒实际timeout及TB watchdog，仅安全控制自己进程；yield不是timeout。本次compile1是上述声明顺序失败的唯一纠正重试，案例1没有再试额度。编译再次失败就保存日志、**不启动case、不再compile**；case失败/缺hit就保留真实结果，不自动第二次vsim。额度/API/容量/实际ID错误直接回原规划，不自动再试、换模型或创建替代。两次无进展同样停止。

同问题机会2/2用尽后的缺口不能由你自动再申请/重命名第三次补充；需原规划按真实结果处理。若确实命中一个新的真实DUT缺陷，给最小反例和完整身份，由原规划区分实际实现修复与本覆盖问题，不自行改RTL或虚构r1。

## 原矩阵不变

单一CASE10、W64/H8、PREP/PRED0、四行释放A0/A1/B0/B1，合法新free身份与释放身份不同，包括跨camera/同camera不同slot。必须4次同posedge descriptor valid/ready和rel valid/ready共同命中，外部历史独立scoreboard记录完整两身份和before/after，旧只清、新只置、其他held RAW/CMP不变；再走完八帧真实AR/R→core→CMP→ACK，四行生命周期都闭合。严格zlib EOF/no tail、数学RAW10、三长度/CRC、源身份与实际DDR字节判据保持。

不得force内部owned/state/rel/core，也不要求仍owned同槽在release当拍ready。不能以相邻拍、两个独立hit或PASS标签代替同沿日志，不能绕开原完整身份/无提前重复/错路释放检查。原原始16有效pass case、122帧和2有效负对照复用，不重跑fault/full/几何/fairness；fairness已有2次，禁止第3次；开发faults始终3/3。

## 同一round0唯一当前结论

新正式完整报告写 `test-reports/T10.dual-aplus-scheduler/r0/supplement02/T10.dual-aplus-scheduler-r0-integrated.md`，首行唯一PASS/FAIL。新canonical-report.json指向这份当前报告，列原根r0 FAIL和supplement01 FAIL的原路径/SHA为不可变历史；旧索引也不修改。仍是同一个测试者、同一个DUT、formal round0和实际修复0，没有第二视角或r1。

按精确compile1/compile2保存副本及新compile4来源逐项绑定旧有效证据/新矩阵，前后核唯一manifest及私有实际输入SHA，给reuse-decision/same-input-evidence-index。PASS需要唯一缺口真闭合并完整汇总三维/G0/G1；仅编译成功不够。历史公平构造失败/interface oracle修正/初始读取控制偏差、旧所有计数、这次失败编译都保留。G2/G3/G4仍not_run/awaiting_hardware，父硬件不置done，T08不动。

实际停止修改、活动命令0，回原合同metadata和真实增量/累计计数。blocked必须带原稳定problem_id、reason_code、new_information、最新证据、原范围准确动作/恢复路径；全部交原规划，不自行续接下一阶段。
