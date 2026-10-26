# RK/FPGA 适配冻结指南 v1

本轮正式写入仅在项目根，主要新目录 `fpga/csi2/pcie_integration/`、`tools/pcie_integration/` 与本 run。D 盘旧工程、temp 参考库、Bayer 工作树及其他 run 为只读。本指南决定由规划负责，开发遇不一致向原规划反馈。

## 分工与版本裁决

1. 传输统一采用 peer `2a4b253` 的 EP 主动 Posted MWr + BAR 控制 + 门铃，使用其匹配 PCIe core/PLL/engine，保留 DW-valid 语义；不再建设第二套 C2H 硬核。
2. 本方负责 checked CSI 完整性、RAW10 packed/几何/帧内容、完整帧发布、缓冲持有、内容 CRC、候选构建与 FPGA 测量。先合入后端与 checked 接收，再成帧。原 RGB565/HDMI1080p60 002820 工程完整保留回退；独立 PCIe 候选不宣称同时完成 HDMI 显示或颜色。
3. 首个独立 PCIe 集成候选沿用 peer DDR3-800E、AXI=1/PAXI=0 与匹配引脚/IP，避免强行将原 PAXI 当 AXI。旧 PAXI1600/DDR1333 工程不改、不中断。该选择仅适用于本次独立候选，不宣布全工程 DDR 性能已定案。吞吐以后实测；不因 AXI 路径存在就宣称双路满速。
4. RK 负责匹配 CTRL 位、128B DMA 起始偏移、容量/单槽约束、消费/回收、实际内核/用户态适配与实收验证。Codex 在本项目生成精确提交对应补丁和操作包，不写队友仓库，不发送消息，不发布。

## 数据格式与长度（沿用 R10F v1 非压缩）

RAW10 每4样本5字节，布局与 `frame_contract.py` 一致；10bit 样本不静默变成8bit。目标 1920×1080：stride=2400B，raw_bytes=payload_bytes=2,592,000B；头128B；content_bytes=2,592,128B；dma_bytes=ceil(content_bytes/4096)*4096=2,592,768B；tail_pad=640B，全0。每帧 MWr=20,256 笔（另加单DW门铃），DDR读=633个4096B突发。大、小模型不能混同。

R10F 头内 payload_bytes 不包含640B尾填充；transport 外层定长 slot_bytes=dma_bytes；RK 先以头的长度严格截取，再校验尾部零填充。CRC32 IEEE reflected 0xEDB88320 init/final XOR all1；非压缩 raw_crc32/payload_crc32 覆盖 packed 有效载荷，header_crc32 清0其0x58字段后覆盖128B。现有 BPR1 保留，不分配压缩枚举、不把它装进 codec=0。本轮首个可运行非压缩链路不等于 T10 压缩完成。

几何必须来自源包实际WC/行数。首版相机保留4K30模式，只允许按实际有效行确定的偶数 ROI 形成1920×1080，默认居中 x=960、有效图 y=540；physical dummy/embedded 行跳过另计，不能把 peer SKIP_ROWS=37 自述直接当本板测量。ROI Bayer phase按有效源相位和x/y奇偶推导，源相位3只是002820已选预览参数，正式帧需板证。不得把960×540预览放大成正式1080p。无法证明源几何时，只输出明确标 synthetic/diagnostic 的候选，不假称真实帧通过。

## BAR/主机内存合同

- 保留 peer 已定义 BAR0 0x40 magic=0x50434946 与 CTRL0x44；bit0 enable、bit1 test trigger自清、bit2 reinit/toggle、bit3 test pattern、bit4 reserved读0、bit5 DDR、bit6 push、bit7 source、bit8 A/B；将模式控制和采集 ready 区分。RK ARM_BITS 应含0/5/6（0x61），不得要求bit4=1；B选路另带0x100。无新版本号寄存器之前，由交付 manifest 的提交与寄存器表识别兼容版本。
- 0xB0/B4 给 DMA 载荷目标，0xB8/BC 给单DW门铃；0xC0/C4/C8/CC 含义保留。相机序号A=0xA0、B=0xE0，0x4C 是测试图源计数，不作相机实流证据。
- RK 16B `anlogic_frame_slot_hdr` 结构体大小保留。`frameinfo.hdr_bytes` 是 host 槽内传输数据起点，改为128B：槽前16B头 +112B padding，然后才是完整R10F头和payload。host偏移128B与R10F头128B是两层，不可混淆。stride=PAGE_ALIGN(128+dma_bytes)=2,596,864B，单槽后独占mailbox页总分配2,600,960B（4KiB页假设），RK运行前检查实际PAGE_SIZE。保留 ioctl号/结构体布局；用户态须使用返回hdr_bytes，不写死sizeof(slot_hdr)。
- 固定128B MWr要求dst%128=0，且每笔 `(addr&4095)+128<=4096`。原+16B应被负对照捕获。门铃4B对齐、不得落入DMA帧区；DMA授权容量必须>=dma_bytes，源base4KiB对齐且源范围不过DDR容量。低/高地址整帧锁存，溢出/0/未授权/容量不足禁止发包。新增容量/ACK寄存器必须由开发先给扩展表、默认禁推保护和RK匹配补丁，经测试约束，不能靠注释假设安全。
- 首版允许单槽one-shot或ACK后下一帧；未消费/释放不得覆盖。旧 peer 单槽持续覆盖模式只能作诊断，不作为正式可发布帧。reset撤销pending、会话切换隔离旧响应；完成先数据、后doorbell，无RO；CPU dma_rmb与消费时seq/header/CRC一致性验证，不能靠同一个seq读取两次证明传输期间未覆盖。

## ready/valid、CDC与完整性

CSI不可反压，溢出/CRC/ECC/错误WC/短行/短帧/abort拒整帧并记capture_seq缺口。checked模块必须真接进顶层，不得只放到目录。4px输出保持RAW10原值；SOF/行/EOF及good/abort与像素流水对齐。

源DDR缓冲从writing→complete→held_for_tx→released；不使用预览替换READY推定安全。TX packet内遇wait必须保持data/valid/sop/eop，timeout不能丢掉半个已开包；不得在未完成TLP时切给CPL。每个时钟域复位同步释放；异步FIFO指针约束、payload握手保持、状态toggle/两级同步按实际网表检查。源错误/取消不虚发完成门铃，且可恢复/排空有界。

## 构建和真实硬件

工具固定 TD Release2026.2/6.2.3，使用本机可用 CLI/IP Tool，核对版本与完成标记。新工程/数据库/产物全部在本run/candidate；若中文路径不支持，可用新建且不占用已有盘符的临时 subst 指向该run（实际写入仍在项目范围，记录映射并只撤销本轮映射），不得自动改到 D盘写。外部脚本先审查，仅在隔离副本跑，不执行其download_sram.tcl。

G2必须最终同一DB setup>=0、hold>=0、TNS=0、无未解释时钟/接口路径、资源<=器件容量，关键CDC/复位/引脚审阅；报告实际margin，不声称达到旧0.300ns优化目标。板测候选不能用逻辑综合代替最终STA。若含CWC，遵5.1完整物理ERAM/BID+bit配对检查。

用户本次已授权必要板验。仅由system测试持有硬件窗口，先识别实际JTAG板/器件、当前连接、电源连续性与回退bit身份；同候选G2达标并提供唯一bit后，可进行必要SRAM易失性加载及UART/JTAG观测，不重复请求已授权动作。不写Flash、不改电源/跳线、不重启RK或访问未知远程机器。若无法确定可用工具/窗口/RK端，准确awaiting_hardware并准备本地工具包，其他离线包继续。

已冻结：上述版本/分工/非压缩封装/长度/对齐/安全边界；待确认：真实相机几何相位、RK执行环境、正式双方G0签收、双路持续性能；暂不适用：本轮备份文档包G2/G3/G4/G5、压缩RTL、深度/NPU/曝光同步。每包具体G层见dev-plan，父任务不能因子包PASS转done。
