# T11 发布/导出/PCIe审查 round0

本包完成五步文档审查并提供可复查离线见证，等待独立综合测试，不宣称DUT或硬件通过。写入仅本目录，未改前三包、统一baseline、源码、全局任务板或dispatch。

1. UART与RAW/R10F分别检查：A1U1固定44B LE头，CRC32覆盖头0..39、raw/xform/zlib精确字节分别校验，内层zlib带Adler；从CMP末32B字只发送stream_len精确字节。R10F codec0头128B，header CRC自字段零后覆盖128B，raw/payload CRC只含有效packed载荷，DMA尾零不计CRC。profile静态prep/pred，admission ID不等于capture_seq，R10F有session/capture/mode但曝光/时间戳字段为0。CRC相同不代表相机像素及完整帧good。C01–C11、F01/F04/F05/F08。
2. PCIe工程和实际IP源补冻E01–E05；wrapper TD6.2.174248、IP元数据1.0/171484 2025-08-11，LINK_WIDTH=2。256bit数据+8bit DW有效，不能当byte keep；F0头四DW、FF八DW数据、F8四DW头+一DW门铃，代码的bswap256/bswap32与MSB DW位置需真实IP方向绑定。默认32DW=128B载荷≤最小合法MPS，dst128B对齐、frame4KiB倍数，因此不跨4KiB；门铃4B对齐、BE=f/0。ARM锁存dst/db/cap/session，检查非零/对齐/容量/64bit目的wrap/门铃重叠；单bit命令，cap/session活动期拒写，后续影子地址改动不改变latched值。DDR源边界32bit回绕反例F02明确默认固定基址不触发。ACK匹配held/session/seq才释放；CANCEL_TX经drain。TL accepted/doorbell_done不是PCIe completion/CPU消费；真实host分配/屏障/ACK及重启/晚R证据缺口保留。C12–C21、F02/F03/F06/F09。
3. `chain-review.md/chain-map.mmd/coverage.csv/chain-findings.json`合并前三份PASS审查，保留真实分支、15边、45原记录、14展示专题和39条独立根因/保留控制索引；继承复合说明不新增缺陷。C22–C24/C27–C28。
4. `witness/egress_witness.py`独立重算整数预算、源码锚定32bit边界/描述符失败开放事件与正控制、全部默认页偏移。`budget.csv/optimization.csv`区分纯预算、旧候选结果和未证生产事实；不复跑另一run长矩阵。C25–C26。
5. 标准产物与三份依赖manifest/独立报告全部绑定，运行记录在commands.json；活动结束后一次冻结manifest-r0.json，后续由新综合测试者做SHA/语义/去重/预算及不同判据核验。

本包最高风险新结论F01可用真实RTL导出器故障注入，或测试者不同事件判据核查E_OPEN状态选择；F02需独立扩位oracle/真实DUT边界。当前见证是静态源码锚定+算术/状态简模，不是cycle-accurate RTL或板测。正常匹配描述符、默认低地址槽、合法MPS/对齐作为正控制；不得把接口反例说成默认板上已发生。

已验依赖按冻结SHA只读复用，前包见证不重复执行。新G0/G1本地核查结果留文件，独立判定待测试者；新G2–G5不适用沿规划理由，旧门槛缺口见chain-review。没有立即删除任何CRC/Adler、FIFO/skid、row bank/obuf建议；源白名单与旧注释收口只计维护收益，无网表不能给资源百分比。

执行边界：根技能第一次短读发生在dispatch deadline规则读取前，未套显式timeout，保留此限制；其后读/搜/输入冻结均自有PowerShell Job+55秒Wait/Stop。一次短读函数名R碰撞内置r别名，引发Invoke-History参数错误；已用Read-Slice更正一次，保留失败记录，不把它当验证通过。Python检查用自有Process/WaitForExit真实240秒deadline，超时Kill(true)只终止该进程树。无TD/综合/bit/Flash/COM/JTAG/RK/网络下载/共享仿真库/盘符/删除/commit/push操作。

DeepSeek仅整数算术辅助，实际project_root=D:/fpga/ph1p100，未发源码/图像/secret。其不必要noop操作被拒，call_id以真实拒绝结果resume一次，模型随后completed。worker把RAW/R10F与A1U1错误混合、漏TLP头等，全部该表未采用；本地Python独立核对正确R10F及DDR预算，细节见witness/deepseek-review.json。复杂契约与最终验证均由Codex执行。
