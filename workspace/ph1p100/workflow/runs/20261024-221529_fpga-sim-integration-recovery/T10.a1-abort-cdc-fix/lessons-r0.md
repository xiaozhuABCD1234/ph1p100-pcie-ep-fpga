# T10.a1-abort-cdc-fix lessons

- 相机无反压时，FIFO满不能只把valid OR abort；必须用真实w_ready保护已提出token，并把第一次丢beat变成有序、可保持的abort。控制与数据同队列，恢复从abort接受后的fresh SOF开始。
- out_last进入skid不等于DDR/store接受last。RAW会话必须持续到真实最后握手，abort组合门控wr_valid/wr_begin并撤销skid，才能避免store中abort与last写的顺序覆盖。
- 尚未分配writer的abort同样需要观察统计；用目的域实际消费事件计数，明确它是合并区间事件而非精确每帧计数。
- 同拍SOF/abort测试需要以真实FIFO下一拍full条件对齐，fast cam下不能假设目前room会持续到下一拍。保留第一次未命中日志，再作一次有新证据的TB纠正。
- 旧DUT可能有多个缺陷，负对照要尽早在目标条件断言，避免无关stall断言抢先拒绝而假充目标复现。完整编译与原始目标证据不可省。
- 最终输入需保留真实TB版本及宏展开等价性，局部开发通过只交独立综合测试，不提升G2/硬件资格。复现入口run_abort.py、TB-version-binding.json及local-result.json。
