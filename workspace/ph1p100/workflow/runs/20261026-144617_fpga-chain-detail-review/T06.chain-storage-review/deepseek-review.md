# DeepSeek 最小上下文辅助与独立核对

实际调用任务ID=`9bd077a583a64023aeee78a5e68d98a6`，project_root=`D:\fpga\ph1p100`，1轮，返回completed。原始工具响应保存在deepseek-response.json。只发送给定1920x1080/RAW20B占32B/RAW与CMP容量地址常量及算术任务；未发送完整源码、会话、图像、凭据、环境或无关文件。没有请求/执行worker操作，没有pending call_id需要resume；没有重试。completed仅代表worker回答结束。

独立核对使用witness/check_storage_contract.py实际标准库整数算术与冻结源码锚点，不采用其回复作最终判定。可采用数值：RAW payload=2592000B、RAW DDR每方向=4147200B、四搬运容量预算=13483840B/帧、单路404515200B/s、双路809030400B/s、25%参考505644000/1011288000B/s。CMP2594720B是槽容量预算，2594706B只是给定旧示例，不是已证明的膨胀上界。

拒绝的具体错误：

- answer文本含`129600*16`等表达式而非合法JSON数值，不能直接加载为结果文件。
- 把两槽容量称为60fps、30fps只用一半、双路消耗全部槽容量，没有持槽时间和服务率依据。槽数是深度，不能推出fps或吞吐。
- 把MODE1 CMP也按20B/字计算“payload”，与MODE1每字32B矛盾；本包CMP容量按81085*32=2594720B。
- 表述CMP容量仅为transport而非payload过度：MODE1满字下有效stream最多32B/字，部分尾字需精确长区分。
- “两个流填满两个槽所以零吞吐余量”没有时间维度，拒绝。

地址差异只限定同份生成参考，不据worker术语推导真实MC映射。所有排序/发布/恢复判断均由Codex读取冻结源码、保留条件并独立构造见证，未委托架构或最终综合测试。
