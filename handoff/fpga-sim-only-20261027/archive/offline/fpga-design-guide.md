# 本轮离线交付设计冻结
需求唯一来源 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/request.md。主目标：让板级主线可复用的 FPGA 离线接入证据形成闭环，三个并行准备事项各自判定。只新增本 run 内独立包；不改根 RTL、旧 P4/H-only/A+H，不使用 TD 或设备。

## 1 字节与身份
RAW10 packed：每四像素 P0..P3 对应 [P0>>2,P1>>2,P2>>2,P3>>2, P0[1:0]|P1[1:0]<<2|P2[1:0]<<4|P3[1:0]<<6]，stride=W*5/4，W%4=0、像素0..1023；字节流低地址先。u16容器不是packed，若后续来源u16须显式大小端/有效位/移位/ROI并逐样本校验，不默默取低8位。真实相位未知允许记录unknown；启用 phase0 Bayer重排/预测须有相位来源或明确规范化过程。

A1U1 v1 保持既有44B小端头：magic/version/flags/header_len/frame_id/W/H/raw_len/xform_len/stream_len/raw_crc/xform_crc/stream_crc/header_crc，最后CRC覆盖0..39；stream_crc只覆盖精确zlib；raw/xform CRC分别覆盖各自有效字节。flags仅prep/pred两位，保留位/非法version拒绝。严格zlib须 eof=true、unused_data与unconsumed_tail均空；逆变换后逐字节等输入、长度/四CRC一致。

四种长度分别命名：raw_bytes，zlib_bytes，a1u1_bytes=44+zlib_bytes，dma_bytes=align_up(content_bytes,4096)。当前 P2 输出 align_up(zlib_bytes,4096)，槽仅zlib；其输出不是44B A1U1文件。当前集成并未连接真实pusher/PCIe数据面，不能说已在板上发送。对当前槽只能称“依据绑定RTL的离线槽/描述符回放”。
离线重建工具负责补既有44B头供旧decoder消费，另存 camera_id(A0/B1)、slot_id、epoch、session、capture_seq、mode/prep/pred、源SHA与长度CRC的sidecar。camera/session不在A1U1头，sidecar不能冒充已实现的PCIe线上字段。必须同时交 current-slot.bin（精确zlib）、current-dma.bin（按当前描述符长度模拟，填充实际未证明则显式模型假设）、reconstructed.a1u1、replay-metadata.json；若有 proposed-a1u1-dma.bin 用 align_up(44+zlib,4096)，明确是离线参考布局。禁止仅改codec_id套R10F；不得引入新的外部压缩头/修改RK。

当前 gap责任表须指出：谁拥有raw/xform/stream三CRC与几何/flags、谁锁camera/session、谁补44B头、谁产生尾零/最终容量、谁核对ACK。没有真实连接处写 missing；本轮开发工具只完成离线补头，板级serializer与元数据传递交原集成线后续接入，不能声称本轮修好DMA硬件。

## 2 双路自由运行仿真
复用已独立通过T08 mode-fix02的真实checked CSI/writer/mailbox/ownership与双路local源集合，不再实现另一套writer、同步I2C或重复旧case16。新增独立回归主题是与本轮需求直接对应的free-run矩阵和可移交接口证据：源发生器只按自身时钟/预定帧表前进，绝不读下游ready决定是否推进；计数器监视真实source拍/EOF。持续场景超过每路两槽容量，刻意制造两路同拍SOF、帧间偏斜、消费者长忙、队列满、错误释放与恢复。
下游可用显式消费者忙/ACK环境模型，但真实writer/descriptor/保护/释放逻辑不得stub；模型边界逐项列出，不能把模型内存叫真实DDR/板级P4集成。新TB/旁观checker/runner允许，冻结源RTL不改。若需要改生产RTL/CDC/协议才能过该主题，立刻交原规划，不在TB藏补丁。

每路槽 FREE→WRITING→READY→READING→FREE；满/忙拒整帧，序号在源SOF增长并出现可解释缺口，不能覆盖held槽或混合帧。身份camera/slot/epoch/session/capture_seq锁存且stall不变，release全字段匹配；旧会话/错camera不得释放。消费者恢复后至少每路2个完整good帧，A/B像素oracle与CRC正确，丢弃帧不得pub。不可反压源允许丢帧，不承诺无损双路满速。
默认几何1920x1080 packed=2592000B/路、双路30fps有效RAW=155.520MB/s是预算；回归缩参W8或16/H>=2必须在manifest记录。小参数和仿真周期不证明1080p30服务率或曝光同步。

## 3 真实收益输入门
第三包仅接受 provenance 可追溯的传感器实拍：本地来源/原始SHA、设备/格式说明、W/H/stride、有效10bit与打包/变换、ROI与Bayer相位记录、许可/来源依据、样本正确性校核。最低3幅内容不同的真实帧可形成有限数据集；若用户只给1幅则仅出单样本，不用“图集代表性”表述。未知相位可在prep=0,pred=0模式基准，不能擅填RGGB；phase0预处理收益必须先有可核依据。
已知b18 sensor_pixel_oracle_verified=false只作历史回放控制，合成向量只作工具正反向测试，均排除real-summary。缺合格真实输入时 benchmark_result=blocked，real_sample_count=0，ratio=null，禁止把空集/控制样例写成真实收益PASS。

复用根 tools/codec/a1_ref.py 的 A+ v1 encode_frame 返回 stream/stats；其 record是A1T1测试格式，不将它当A1U1。逆变换与严格DEFLATE使用独立工具；不改编码器。输出每帧 raw/zlib/A1U1/dma 字节、raw/zlib 比率、含头/对齐比率、stored_blocks/block_count与stored_raw_bytes/总raw两种回退比例、解码SHA。汇总用总字节比，不混平均比率。CPU耗时如记录须标软件，不能外推RTL吞吐或H-only/A+H收益。

## 4 环境/证据与停止
工作目录 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/<task_id>/；开发只写其包，测试只写 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/test-reports/<task_id>/ 与报告。每包独立 modelsim.ini/work/日志/tmp，绝对源映射在本包生成；不原地运行会回写旧run的runner。根生产/约束/IP/时钟全部只读；单时钟P2/P3与双域旧writer的域/复位保持来源，不新增CDC或板约束。源/命令/输出/工具版本/参数SHA绑定唯一manifest，stopped_modifying=true、active_commands=0后才测试。测试前后漂移0。

已冻结：格式、长度区别、离线补头责任、源不可反压、各包范围/输入门与独立判定。待确认：第三包合格真实数据；后续板级补头/身份传递与真实PCIe窗口。不适用本轮：TD、最终STA/资源/物理CDC、硬件/COM/JTAG/Flash、RK更改/外部消息。
functional检查真实字节/真实不反压DUT及严格oracle；engineering检查源绑定、编译/静态接口/可重现；system检查证据诚实、接口兼容、非覆盖与回退。本轮G0/G1/G5为产物检查；G2不在此次TB/软件新增范围且未测，G3/G4 not_run/awaiting_hardware；不能因此升级任何父硬件任务。

