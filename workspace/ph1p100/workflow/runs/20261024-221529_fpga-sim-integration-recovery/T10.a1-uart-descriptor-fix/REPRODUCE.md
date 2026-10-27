# 冻结输入复现说明

所有路径由corrected-dut-index.json和manifest-r0.json给出；生产文件与原8项输入不可修改。查看actual-commands.json得到每次真实argv/cwd/退出码/耗时。旧版与修正版各编译一次，旧版两例、修正版三例各运行一次，无重试。

独立综合测试者在自己允许的证据目录建立新的modelsim.ini、work库、run.do、WLF和所有输出文件。以vlog -sv -modelsimini <测试者INI> -work work编译corrected-dut-index中的8路径，加冻结ddr_recovery_model.sv、tb_full_clean.sv和tb_descriptor.sv；其余参数照实际argv，仅重定向所有输出路径与INI/work库。负对照独立建旧库，以原inputs/a1-r5/src/a1_uart_export.v替换唯一修正项，其余7项路径不变。

tb_descriptor MODE3运行队列边界，MODE2运行12个连续ID与queued reset；DESCS/PAYLOADS指向冻结fixtures，OUT/TRACE/STAT只指测试者目录。两正例须DESCRIPTOR_PASS/mismatch0、Errors0，独立字节核对全部6/14包。旧MODE3须命中QUEUE_COUNT_MISMATCH，旧MODE2须命中第3次DESCRIPTOR_ORDER_OR_X，均不得以编译失败替代。

tb_full_clean参数W8/H2/MAX_CYCLES1500000、CASE0，须4个完整正确包/292B及清零错误计数。保留真实延迟DDR模型和同钟UART合同。原3条仅观察端口告警已在开发报告解释。可直接调用冻结check_descriptor.check(<测试者case目录>,mode)及check_recovery.check(<测试者full目录>,0)；后者还必须独立强化为4包/4 exported/4 recovered及错误计数0。

准备/构造/冻结脚本为制作审计来源，已执行且开发目录已冻结，不要再次运行以覆盖开发产物；run_descriptor.py也禁止重复同kind编译/同case写入。独立测试须使用测试者自己的新命令/包装，不复用开发库声称独立重建。
