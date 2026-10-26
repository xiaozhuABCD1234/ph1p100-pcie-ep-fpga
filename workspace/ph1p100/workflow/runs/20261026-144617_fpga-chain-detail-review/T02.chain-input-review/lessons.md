# T02 可复用经验

- 根因类型：同为40bit不能证明格式兼容。触发：checked unpack输出4×10bit，而A+按五字节packed读。修正方向：唯一边界显式格式适配；验证入口witness/check_input_contract.py及真实跨模块源像素oracle。只用全0/全1图样会漏掉这个问题。
- 事务错误：计数凑齐ROI不等于源帧通过CRC/FE。触发：crop先置done，晚到good/abort未接。修正方向：持有pending帧直到采用的判定点，不能用晚abort挽回已发布帧。验证：最后ROI行CRC/后缀短长、缺FE与后续恢复。
- 证据边界：编译列表/源码样本/旧bit是三种身份。统一baseline缺依赖可包内补冻，但缺旧依赖SHA时不能给历史bit背书；同名upstream配置器不能替换b15依赖。
- .al不是通用规范XML：UsedInP&R含未转义&，严格XML parser失败。只提取精确File Path可读入口，不能据此声称TD格式有错。正则搜索cam_pix[须转义或用SimpleMatch；原失败留执行记录。
- 序号边界：成功准入计数不同于全源capture_seq；SOF mailbox到达时间差不同于曝光同步；两者均需元数据与真实设备证据，不能用离线PASS覆盖。
- 本轮仅审查；修复和硬件证据仍须原规划在未来授权范围排期。所有保护文件原样保留。
