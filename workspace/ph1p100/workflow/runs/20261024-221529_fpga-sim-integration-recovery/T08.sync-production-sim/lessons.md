# T08 开发 lessons（round0）

- 接管配置I2C须保留完整初始化表，并禁止表后的自动/周期启动；每路只保留一个真实ui_i2c。cfg_done只表示初始化阶段完成，不能代替每笔ACK。
- ui_i2c的bus_error可能在busy下降前清除，必须在事务期间累积NACK，并在busy完成同拍与累积值合并生成唯一响应。最后字节NACK反例覆盖这一边界。
- ready跨域释放后只能在新SOF开始整帧准入；pair锁定撤销须中止开放帧。缺B时A独立接收过一个坏帧，A/B R10F内部frame ordinal会合理不同，不能错误地要求两路ordinal始终相等；仍须严格核对各路源图案、地址和帧身份。
- Windows ModelSim10.5b把反斜杠形式的-modelsimini路径经Tcl包装后报EINVAL；原失败日志保留在local/clean-attempt1。runner统一把Path参数转为正斜杠后实际运行成功，未创建/修改共享盘符。
- 冻结寄存器表含非UTF8注释，独立oracle只解析ASCII寄存器常量，读取时对注释解码采用errors=replace，原始输入字节和SHA不变。
- NACK故障采用手动start脉冲，日志无START行；oracle显式从第一条真实REQ到恢复START划分故障段，并完整核对7笔前缀和6笔清理，避免遗漏故障序列。初次检查失败证据保留，不改原日志。
- 开发检查入口为run_t08.py/check_t08.py；综合验收须重新编译并在测试写域运行，绑定唯一manifest。G2及硬件父任务门槛不能继承本仿真证据。

- 额外pending-I2C reset用例在真实busy上升、accepts=1/responses=0时命中；旧会话一笔明确取消，新的epoch完整初始化和warmup后恢复。最终build2对全部必须场景重新绑定输入SHA。
