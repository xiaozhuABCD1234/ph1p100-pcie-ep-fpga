# T11可复用经验

- 检出ID/长度不一致后只记错再发送是失败开放；验证应观察任何外部头字节是否已发出，并把slot回收/描述符重同步作为同一事务。
- 边界比较中的加法位宽决定是否允许回绕；目的64bit保护不能代替源32bit保护。模块接口反例必须说明默认top是否可达。
- local enqueue、TL accept、线末stop-bit、CPU可见/消费、ACK各有不同完成事件。slot数据复制后释放可能安全，不能因此改称主机完成。
- RAW packed、b15 RAW存储占用、A+内层、UART外头、R10F有效长/DMA/TLP开销分别计算。worker算术也须独立复核；发现混合格式即拒绝其表。
- 合并审查要保留每条原finding ID恰好一次，并保留合法小几何/默认几何、模型/真实MC、隔离/生产等触发限定；不按组数宣称新增缺陷。
- PowerShell短函数名R会命中内置r历史别名；使用无歧义Read-Slice。命令启动前实施真实deadline，yield不是timeout。
