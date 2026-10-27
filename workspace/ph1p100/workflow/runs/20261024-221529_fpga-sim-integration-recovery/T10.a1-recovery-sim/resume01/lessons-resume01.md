# 原恢复包续接01 lessons

- crop abort是独立控制事件；把FIFO写有效仅接像素valid会在没有像素的错误周期丢事件。本次实测FIFO有空间却没有abort写入，半帧ownership永久保留，后续SOF不能前进。定位入口defect-evidence-resume01.json。
- 修正描述符循环后必须重新跑完整管道，两个clean几何和两种外部中写reset均重新执行，不能把依赖包的clean或历史前两帧当恢复证明。
- W32/H2形成80B RAW及91B压缩流，使真实外部部分AW/W且未发布的复位前置条件可以严格命中；记录其地址、接受数和状态，避免仅靠内部入口计数。
- reset断言期清零与释放后跨界残帧错误计数不同，分别记录；保留DDR队列结构不等于已命中reset时未完成AR，证据边界必须写清。
- ModelSim Fatal仍可能进程exit0，必须同时检查明确标记、完整包、CRC/源/epoch和有界恢复；本次坏帧由RECOVERY_BOUND_FAIL拒绝，非cycle watchdog。
