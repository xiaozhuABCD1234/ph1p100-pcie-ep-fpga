# 本轮审查工程指南

应用 `.agents/skills/fpga-design-guide/SKILL.md`；本文件冻结审查口径，不新造生产协议。

## 已冻结

- 工作目录 `D:/fpga/ph1p100`；全部新产物在本run；`docs`为OneDrive junction，只读。baseline/source-manifest.json及其snapshot为本轮统一版本；实时来源变化不替换冻结输入。
- FPGA硬件PH1P100SBG484、双IMX415、RK3588、PCIe主路线保留；本轮只审查FPGA与RK接口，深度/NPU暂缓；HDMI1080p60、RAW12封存等既有决定不改。
- 目标RAW10 packed：1920×1080，4样本/5字节；一帧2,592,000 B，行2400 B；u16容器4,147,200 B不能当packed长度。纯计算每路30fps=77.760MB/s，双路155.520MB/s；25%=97.200/194.400MB/s是参考预算，头/报文另计，不替代P1080硬目标。各实际b15源的采集/裁剪几何由源码逐项确认，不能用目标几何推定传感器输出。
- DDR占用不等于传输payload：b15审计指出该布局期望129600个256bit字，而packed RAW10仅81000个256bit字；须沿真实store的数据组织核对，不能把两者当同一帧容量或沿用错误81000字的故障百分比。
- 对每个路径冻结实际宽高/stride/ROI/CFA/方向/端序、sof/eol/fe/good/abort及精确有效字节；算法Gray8/RGB8不冒充Bayer，同色预测不跨模式直接复用。
- 接受事件由真实接口定义。标准ready/valid需stall稳定data+sideband、同拍take/refill；CSI不可反压，溢出/坏帧不能发布半帧。PAXI不是凭名字即可套用AXI；地址/掩码/接纳以该候选生成IP和原生参考为审查证据。
- 256bit字下标、原生PAXI地址、字节偏移分别命名；转换只能在明确边界。已知b15审计给出厂商参考word_index<<3和完整写mask=0的差异；内部MC加密与真实接纳规则的未证明部分仍保留。单AR在途≠AW/AR互斥。
- RAW/CMP/传输槽的持有、发布、完成、回收及会话隔离按实际源审查；预览替换旧READY不证明DMA可覆盖。发布计数不证明DDR内容正确，队列加深不修复长期服务不足。
- 当前A+/LZ77/DEFLATE实际模块与格式优先于10/15–16 Bayer/Rice方向摘要。BPR1、R10F和A+分别定位，不能互换codec_id即宣称兼容；raw长度/压缩精确长/外传长/DMA对齐长、CRC/Adler覆盖头/载荷/尾零独立核对。具体多项式、位序、填充从冻结格式源码取，不凭名称假设。
- Gray/Gaussian/HE按实际DUT核对signed扩位、舍入饱和、边界、首帧/坏帧、旧LUT/新LUT发布、四lane同bin。旧仿真PASS只对原输入成立，不等于已接入A+或板级。
- PCIe审查包含真实生成端口、DW-valid与byte keep、MPS/4KiB/BE、DMA地址容量授权、完成可见性/ACK和回收；UART诊断输出不证明PCIe生产sink吞吐；RK用户已确认可收图解码的历史事实也不证明本轮A+候选配对完成。
- 时钟/复位/CDC约束只审查已有源/报告。b15 +0.012ns来自该候选报告，不是新签核；异步切组不证明Gray skew/复位释放充分。187.5MHz软件周期预算、最终STA、真实DDR持续服务与双路系统吞吐分别结论。
- 工作流G0接口层、G1离线模型层，与性能报告中的1080p30“G0”分开；本轮性能名P1080。77.76MB/s、6.25M cycles@187.5MHz按来源范围使用；slot-free/strict-serial、冷启动/稳态、sink受限/真实服务率不混淆。
- 构建入口仅用于追溯真实编译源：b15 `r0/td/a1_board.al` 与 `p2_board.sdc/board_p2.adc`，以及既有生产/离线任务manifest；**本轮不得执行TD或下载入口**。微型校验只在任务独占目录执行。

## 待确认/审查事项

本轮不把未决项推给用户做无必要访谈。开发按dev-plan四包逐项查证：生产实际路径/模式接入、b15原生合同与模型差异、b17仍是计划还是产生新冻结结果、真实帧/内容源、slot-free/生产sink、双路真实曝光同步、候选完整G2–G5证据。新结果只标快照后变化，不追逐或并入本轮。

每项明确 `confirmed_issue / redundancy_candidate / evidence_gap / no_issue_found`，带输入/触发/故障模型及验证；建议删除状态/缓存/校验前须证明接受事件、所有权、恢复和消费者等价。不以减少代码行数当正确性或资源收益。

## 不适用与三维边界

functional=审查语义/引用/算术及小型见证；engineering=来源/编译候选/manifest/SHA、既有STA/CDC/资源证据资格；system=相邻契约/候选交接/未测边界。新G2–G5执行不适用，因为不改生产行为、不交新bit、不签核DUT；既有门槛缺口必须保留，审查PASS不能外推硬件PASS。所有正式包均须一个与开发独立的综合测试者。
