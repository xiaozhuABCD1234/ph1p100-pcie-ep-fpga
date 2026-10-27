# T03 可复用 lessons

- 触发：协议写44B头+zlib，但P2接收slot_stream_len并直接对齐。修正：分别保存exact zlib、当前描述符布局、离线补头布局；验证入口为48条真实RTL描述符和r0/rtl-results.json。只看软件生成A1U1会漏掉硬件缺口。
- 触发：zlib.decompress可能接受额外成员/尾数据。修正：校验eof/unused_data/unconsumed_tail并用严格DEFLATE解析器交叉核对；extra-zlib与重封装截断用例必须在修复header/stream CRC后仍被拒绝。
- 触发：P2注释声称尾处理，却没有payload接口；store最后字清零不等于整DMA页清零。修正：限定实证仅70..95B，96..4095B标模型；current-dma sidecar记录未证明假设。
- 触发：camera/session不在A1U1头，P2相机选择固定0。修正：sidecar保存显式上下文并与调用者预期核对，记录其不能证明线上身份；完整P3身份承接仍由板级集成实现。
- 触发：ModelSim 10.5b在vsim -modelsimini处错误包裹Windows反斜杠绝对路径。修正：传Path.as_posix()；保留首次rc12和日志，仅有新证据后重试一次，不重复编译。
