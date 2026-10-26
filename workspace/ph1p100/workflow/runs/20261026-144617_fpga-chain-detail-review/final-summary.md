# FPGA整链路细节审查总报告（四包独立验收完成）

本轮按用户“把整条链路拆成细节小任务，审查逻辑冗余或谬误及优化空间”的需求完成4个正式审查包。四包分别由开发与独立综合测试者交付，全部首次round0 PASS，实际修复0轮、问题补充0次。审查覆盖124个包内检查点、15条接口边，保留45条原始判断记录并按14个专题归属；其中含继承说明、证据缺口、冗余候选和未发现问题的保留控制，不能把记录/专题/39条根因与保留控制索引都叫“缺陷数”。优化表为13行。

**验收通过的是只读审查的完整性与结论可靠性。生产RTL没有修复，没有新构建/位流/CWC、真实MC或板级验收；父T02/T06/T10/T11不因本轮审查完成而关闭。** 本报告是原规划收尾，唯一最终冻结审查候选仍是T11 manifest及其绑定的前三包；不改写开发冻结文档中“待验收”的历史措辞。

## 已验收的分包与证据

|审查包|检查点|原始记录|验收/实际修复|独立证据|
|---|---:|---:|---|---|
| T02.chain-input-review | 28 | 10 | r0 PASS / 0 | [报告](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/test-reports/T02.chain-input-review-r0-integrated.md) |
| T06.chain-storage-review | 35 | 15 | r0 PASS / 0 | [报告](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/test-reports/T06.chain-storage-review-r0-integrated.md) |
| T10.chain-transform-review | 33 | 11 | r0 PASS / 0 | [报告](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/test-reports/T10.chain-transform-review-r0-integrated.md) |
| T11.chain-egress-review | 28 | 9 | r0 PASS / 0 | [报告](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/test-reports/T11.chain-egress-review-r0-integrated.md) |

统一baseline含287项、7,877,833 B，manifest SHA256 `c08adc09b364828fee5d94953a89898a3220af8c8f99cdec52404fec06f74c96`；本轮采用冻结时点，不追逐b17或其他活动run后续变化。原主仓库HEAD为 `27c596b01cd961dfa9d0850e4fbf879fe249de90`，原有dirty/删除保护。四份manifest、独立报告和交付入口的准确SHA见 [交付索引](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/delivery-index.json)。

## 实际链路与未接入处

- b15链是单A CSI tap→crop/CDC→RAW槽→A+→CMP槽→UART诊断。B仅接收；HDMI当前为测试图。
- 三算法是另一生产参考中的Bayer→RGB/Gray→Gray/Gaussian/前帧HE并行诊断分支，未串到b15 A+。
- RAW/R10F PCIe是另一独立参考通路，codec0非压缩；不能把A+ UART与RAW PCIe拼成压缩PCIe已通。
- 同步/恢复离线候选与历史BPR1/Rice参考分别保留。SOF到达配对不证明曝光同步，用户历史RK收图反馈不证明当前A+候选端到端配对。

[源分支图](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/chain-map.mmd) · [15条边的契约覆盖表](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/coverage.csv) · [冻结全链路汇总](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/chain-review.md)

## 主要确定问题与优化顺序

|优先级|具体发现|后续闭环与资格|
|---|---|---|
|正确性1：样本格式|4×10bit样本向量被直接送给要求packed RAW10字节的A+入口，缺少重打包；独立位来源组合显示不等价。|唯一边界冻结格式，以真实checked解包→编码→独立源像素oracle验证。结论针对冻结b15源码，不声称旧bit已实拍测坏。|
|正确性2：好帧/取消事务|CSI晚CRC/FE裁决没有进入A+；crop最后ROI样本置done后漏掉末行后缀；最终字与abort/重SOF同拍仍commit。|最终好帧、最后写可见、取消、slot和描述符必须共同定义原子发布。只OR晚abort不能撤销已发布/已领取事务。|
|正确性3：原生接口/模型|PAXI地址缺参考要求的左移3位、完整写mask与同份厂商参考相反；行为模型忽略mask和原生接纳限制。|先冻结同版本原生合同，修正模型后小图样读回。读写同拍是否合法仍缺原生证据，真实MC“缺R”根因未定。|
|正确性4：所有权/导出|begin/abort消耗排序位，可在合法store接口轨迹下逆序领取；导出器检测ID/长度错配却继续发头。watchdog close也未覆盖R_AR等待态。|使用真实发布顺序与失败关闭合同，覆盖abort、stall、领取/取消、后继恢复；默认全尺寸整机可达性不能从模块反例直接推定。|
|正确性5：边界/消费者|合法小几何prep1逆变换错像素/越界；A+消费者宽容接受严格子集不允许的尾字节/对齐；PCIe源地址检查有32bit回绕反例。|小几何/地址输入反例分别验证；默认1080p/固定低地址不触发相应反例。strict padding是A+子集合同，不是通用zlib必拒规则。|
|先补证明再调性能|CMP14B余量依赖真实bit-offset成本一致；有限guard不能证明无限晚响应隔离；16bit tag约4.045秒回绕后的存活条件未证。|这些保留为证据缺口，不能写成已发生溢出、错码或板级故障；需定向真实DUT/形式/长时证据。|
|维护/资源最后|重复来源、未选文件、过时协议/算法注释可先收口白名单与文档。|CRC/Adler、FIFO/skid、row-bank/obuf服务不同消费者和故障模型，未证明可直接删除；没有综合网表差分，不能承诺资源百分比。|

[13行优化建议及最小验证/代价/回退](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/optimization.csv) · [去重原记录和根因索引](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/chain-findings.json)

## 吞吐、容量与资源口径

以下是独立重算的预算或有范围的历史值，不是本轮FPGA实测。

|对象|数值|必要限制|
|---|---|---|
|双路1080p30 packed RAW|155.520MB/s有效载荷；单帧2,592,000 B|外头、报文另计，不能用u16/DDR布局长度替代|
|A+理想上界|2,594,706 B/帧；双路155.68236MB/s|真实块起始bit offset成本前提未闭合；A1U1再加44 B|
|RAW/R10F PCIe|DMA2,592,768 B；含TLP头/门铃双路175.01304MB/s|默认128 B payload；还不含DLL/PHY/ACK/replay/idle，不是A+ PCIe格式|
|b15 DDR RAW写读+CMP写读|双路809.0304MB/s预算基础|RAW每20 B占32 B；未计refresh/仲裁/空窗，CMP容量前提沿T10|
|P4历史服务|单核187.5MHz、合成/comp代理、TB slot-free、93.75MB/s sink|strict-serial和不可压缩sink限制保留，不能外推自然/最坏内容及生产双路|
|历史STA/ERAM|b15 +0.012ns/102 ERAM；另T09 +0.100ns/200 ERAM|不同manifest/实现，不拼时序签核或相加双路资源|

[预算逐项表](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/budget.csv)；完整CRC/长度/尾零、DMA/TLP、完成/ACK和各接口引用见检查表。TL本地接受、UART入holding、wire完成、主机已见和CPU消费是不同事件；必须保留HELD及session/seq匹配ACK资格。

## 细分检查表与边界

[输入/CSI/同步：28项](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T02.chain-input-review/checkpoints.csv) · [DDR/PAXI/队列：35项](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T06.chain-storage-review/checkpoints.csv) · [算法/压缩：33项](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T10.chain-transform-review/checkpoints.csv) · [发布/PCIe：28项](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/T11.chain-egress-review/checkpoints.csv)

本轮G0/G1通过对应文档、静态符号/状态/算术、软件见证和独立复核；未运行cycle-accurate RTL、完整帧长仿真、TD/STA/CDC、bit/CWC或硬件。新G2–G5事先因只读范围不适用，既有硬件缺口仍保留：b15旧150秒观察不等于完整帧/恢复/长稳，enc/exported=0和H4_UNRESOLVED未被本轮改成通过；曝光同步、真实MC、生产持续服务与实际RK配对尚未证明。

过程保留限制：部分角色初次短读未套显式deadline，开发原worktree字符串变化无法归因；辅助解析/汇总脚本的失败和一次有证据纠正均保留，测试者采用独立判据/人工来源资格与限定同输入复用，没有把失败脚本称通过。具体见四份独立报告，不追称所有过程记录完美。额度/容量中断经用户明确继续后恢复，未换模型或自动连试。

## 仅保留的后续主题与回退

1. b17原生PAXI合同修复、小图样真实读回及缺R事务证据，按其最新真实状态另行冻结，不覆盖活动成果。
2. 另一run `20261026-143924_fpga-1080p30-g0-production` 的真实内容、生产slot-free/sink和双路资源/服务签核，本轮未重复。
3. 按优化表先实现一个正确性闭环，未来再做适用G2及真实曝光、完整帧、恢复与稳定性验收；RK深度/NPU继续暂缓。

当前不自动续做或下载；保留所有原生产源、位流/RAW兼容入口与历史回退。若审查结论要改，续对应原开发/原测试、新轮冻结并保留旧证据。恢复查阅和下一次精确启动文本见 [交接](D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review/handoff.md)。
