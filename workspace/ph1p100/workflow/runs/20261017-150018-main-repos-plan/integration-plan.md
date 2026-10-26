# 以队友两个原仓库为主的并入计划
日期：2026-10-17。本次仅规划，未实施、提交、推送、建PR、下载位流或操作硬件；原任务板不变。

## 1. 已核对的基线
| 主仓库 | 在线默认分支/HEAD | 结果 |
|---|---|---|
| [FPGA](https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga) | main / 2a4b253d9f2e56a943f1667b2a7a366824dcba34 | 与本地冻结副本一致 |
| [driver](https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-driver) | main / a0215c5a2fcb95bfc867a4768d4831d68edf64a2 | 与本地冻结副本一致 |
GitHub连接器和匿名网页均404；原生git ls-remote --symref在线成功，不能据404认定仓库不存在。写权限、分支保护未核实。
FPGA实际根目录有rtl/、al_ip/、constraints/、sim_do/、doc/及ph1p_pcie_ep_top.al、create_project.tcl、build.tcl；README部分prj/case_ep与内嵌driver路径已过时。
driver实际为src/、include/、Makefile及app/rs/，保留现有内核模块与Rust工具结构。
[本次来源与SHA差异快照](C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-150018-main-repos-plan/source-comparison.json)记录FPGA 7改6增/142相同，driver 8改3增/16相同；T11生产输入155条无漂移。

## 2. 工作方式
两个队友原仓库成为生产源码主源；本项目保留历史证据、赛题与研发记录，不再维护第二套生产顶层。
在原仓库内部各建codex/raw10-rka1分支，以各自main为基线；这是同仓协作分支，不是fork。
每个功能包小提交、同仓PR审阅后合入main；直接修改原仓库不等于直接推main。实施前核实协作者写权限，权限不足不影响本计划。
两个仓库用配对版本清单记录FPGA commit/bit SHA、driver commit、协议版本、工具/内核与验收结果。
后续执行沿用T03/T07/T11/T09/T10任务归属，不新建第二套全局任务板。

## 3. FPGA：先并入现成RAW10最小闭环
来源S1=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/fpga/csi2/pcie_integration
来源S2=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/tools/pcie_integration
S1下相对路径映射到FPGA原仓库同名相对路径，逐文件迁移，不整棵覆盖。

| 来源S1 → 原仓库同名目标 | 状态/用途 |
|---|---|
| rtl/ep_side/ddr/ddr_frame_pusher.v | 修改；RKA1单帧ARM、held、ACK、CANCEL、容量/地址检查与A/B独立release |
| rtl/ep_side/img/ep_bar_win.v | 修改；扩展寄存器、配置门禁与诊断 |
| rtl/ep_side/img/img_frame_src.v | 修改；诊断图源hold |
| rtl/ep_side/pcie_ep_engine.v | 修改；扩展控制/诊断接口 |
| rtl/ep_side/ph1p_pcie_ep_top.v | 修改；checked CSI、A/B RAW写者、缓冲所有权与帧长接线 |
| rtl/ep_side/cam/ui_cfg_imx415.v | 修改；声明顺序/隐式网兼容修正 |
| rtl/ep_side/ddr/cam_ddr_writer.v | 修改；诊断备用写者安全发布；正式RAW路径使用下列新写者 |
| rtl/checked/csi_rx_packet_integrity.v | 新增；采用T11冻结优化版，不能拿旧原源替换 |
| rtl/checked/csi_rx_10bit_unpack_checked.v | 新增；带keep的RAW10解包 |
| rtl/checked/crc16_upd4.v | 新增；匹配完整性检查器的CRC树 |
| rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v | 新增；保留peer PHY/对齐并接入包层检查 |
| rtl/ep_side/ddr/cam_r10f_writer.v | 新增；packed RAW10、R10F头/CRC/尾零及完整帧发布 |
| rtl/ep_side/ddr/crc32_upd4.v | 新增；匹配新写者的CRC树 |

保留原PCIe硬核、DDR AXI接口/仲裁、al_ip/、constraints/、RC参考与旧sim_do/，不复制相同142项、不批量删除。
S1/sim/ → 原仓库新增sim/：并入8个验收TB、编译清单、IP仿真桩、差分参照；临时tb_t11_dbg1.v不列正式验收入口。
S2 → 原仓库tools/pcie_integration/：并入仿真/TD入口、CRC生成器、严格解析、清单工具；改掉fpga/csi2/pcie_integration、workflow/runs及本机盘符默认路径。
create_project.tcl/build.tcl补齐新增源与include路径，统一单会话建工程→综合→布线→bit；输出放独立build目录，根.al按同一文件清单同步更新。
README同步真实根目录入口、驱动仓库链接及新协议操作；不复制当前候选.al中的本机绝对路径。
原T11清单AAB0CC08…6975、bit 14b32037…5686b及三维PASS是迁移来源证据；搬目录和改构建入口后必须重新生成该仓库候选、复跑G1/G2，不能沿用旧bit宣称新仓库通过。

## 4. driver：补丁转为正式代码，再补生产收帧循环
来源S3=C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/raw/rk-driver-src（已含T07主补丁+T11增量的最终树）。
在a0215c5基线上先检查并应用C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/backend/patches/rka1-driver.patch，再应用C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/raw/patches/t11-rka1-r10f-fix.patch。
审查最终diff并提交源码，补丁只留迁移依据；不要把整个S3覆盖主仓库。只并下列8改3增：
| 原仓库目标 | 内容 |
|---|---|
| Makefile、src/anlogic_pci.h、src/anlogic_pci_ctrl.c | 注册新RKA1模块、声明与ioctl分发 |
| include/anlogic_pci_ioctl.h | 0x61/0x161、128B槽数据偏移、单槽DMA尺寸、新ioctl15，旧结构布局保留 |
| src/anlogic_pci_frame.c | 合法参数/容量/槽布局检查，拒绝静默夹紧 |
| src/anlogic_pci_link.c | 扩展探测、CAP/SESSION、ARM/CANCEL与活动期配置门禁 |
| app/rs/src/lib.rs、app/rs/src/bin/frame_grab.rs | 接入RKA1与正式R10F解析 |
| src/anlogic_pci_rka1.c | 新增；RKA1控制 |
| app/rs/src/rka1.rs | 新增；寄存器封装与严格帧解析 |
| app/rs/src/bin/r10f_check.rs | 新增；独立离线校验 |

现有补丁仅离线apply/static检查，尚未RK编译/运行。frame_grab仍非完整生产收帧工具，后续必须补：
- control节点生命周期与ARM→等待held→完整拷贝/严格校验→匹配session和seq→ACK→再ARM；首次ARM前确认源曾发布完整帧。
- 正式模式必须要求R10F magic，损坏magic不能退回旧PGM诊断路径；拒绝未知格式/坏帧/短帧/坏CRC/session或seq不符。
- 输出原始.dma/.r10f与元数据；packed RAW10解包后另存预览，不能把原字节当8位PGM。拷贝和校验完成才允许ACK复用。
- 失败、超时、退出/拔链走CANCEL并等排空；记录错误码、丢帧/序号缺口与各段耗时。
- 在真实RK KDIR/工具链、cargo环境编译并验证旧预装模块替换与实际加载版本；保留可回退模块。

## 5. 两仓库必须同步的合同
将C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261017-011744-rk-fpga-align/contract/{registers.json,acceptance-vectors.json,compatibility.md,rk-required-changes.md}及必要样例整理到FPGA仓库docs/protocol/rka1-r10f-v1/。
driver仓库docs/protocol/保留同版本合同与样例SHA镜像，指定FPGA协议目录为规范主源，两边变更同一配对版本；不允许各自改字段。
冻结非压缩codec=0、RAW10 packed、小端、128B R10F头、1920×1080/stride2400、raw=payload2592000、dma2592768、尾640B零与三CRC覆盖范围。
主机槽头16B结构体+填充至128B数据起点，与DMA正文内部R10F头128B分开命名；默认单槽。
CTRL A=0x61/B=0x161只开模式，TX_CMD ARM才授权；ACK匹配(session,seq)，CANCEL不截半包，held源块不覆盖。
几何/ROI/Bayer相位目前未板证，必须标diagnostic；实测WC/行数/相位确认后回填并重验。SOF配对不等于曝光同步。
后续BPR1需另冻结版本/codec枚举、原长/精确压缩长/DMA长及CRC定义；不能只填codec_id复用codec0解析器。

## 6. 并入顺序与验收
| 阶段/现任务归属 | 交付与必要验收 | 回退/停止边界 |
|---|---|---|
| A T03/T07/T11 | 原仓库分支、协议镜像、FPGA上述13项RTL+工具、driver最终11项diff；新路径8TB/负例、严格解析向量、RK内核/Rust编译；同最终DB setup/hold≥0、资源与bit来源 | 不改时钟/SDC求通过；保留旧main与配对候选，条件缺失记blocked |
| B T07/T11 | 补完整收帧循环；先单A实收100帧零CRC错误、10min短稳、错ACK/超时/CANCEL/reset恢复；核实几何/相位与BDF/PAGE_SIZE/MPS/IOMMU | 新旧FPGA/driver成对回退，不能混用；没有RK条件只完成离线，不称闭环 |
| C T09 | 灰度、高斯、前帧HE独立硬件支路：补Bayer前端、HE、四像素接口和吞吐；金参考逐像素、坏帧/首帧/LUT切换/反压；重跑G2 | 模块通过后才接顶层，旧RAW路径保留；灰度/高斯局部RTL不记三算法完成 |
| D T04/T10/T11 | 一条Bayer预测+有界Rice+RAW回退，补行选择/头CRC/完整帧发布与BPR1 adapter；RK解码逐样本一致、最坏回退吞吐/资源 | codec0保持可用；规则接受口径未确认单列风险，不预开第二压缩器 |
| E T05/T08/T12 | A/B实际采集、调度与曝光同步；RK去马赛克、实拍标定/校正/匹配/深度、NPU和整链路性能 | 单pusher先按空闲边界调度A/B；实测不足再改引擎，不凭链路速率宣称双路30fps |

A/B是最低联调闭环，C/D是赛题基础功能的后续必做，不因先跑非压缩而取消。
每包停止修改、冻结同一输入后按项目流程新三维测试；离线包PASS与G3/G4实机结论分账。双路1080p30 RAW预算155.520MB/s、加25%为194.400MB/s，头/填充/TLP另计。

## 7. 后续并入与暂不并入
- Bayer工作树C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道中的codec/*.v、img/rgb8_gray_stream.v、gray8_gaussian3x3_frame.v、对应TB/模型：仅在C/D单独迁入FPGA rtl/ep_side/{codec,proc}/和sim/，核对未提交字节/所有者后再取；不接通就称完成。
- parallel/algorithms金参考→FPGA sim/reference/；BPR1 codec软件的同版本解码/向量→driver app/reference/bayer_codec/；parallel/rk解包/标定/匹配参考→driver app/reference/stereo/。生产入口必须先经严格R10F解析，不能直接照搬旧宽松解析器。
- 旧PAXI ddr_frame_store/HDMI预览完整工程不并入当前AXI主顶层；保留本项目历史与回退，不另造第二条DMA。
- 新DDR1333生成物不直接替换peer DDR AXI IP；两者接口/时钟/参数不同，只有单独验证AXI适配收益后再立候选。旧白平衡/HDMI1080p60目标保留，不因仓库迁移擅自撤销。
- 不并入RAW12封存、LZ77第二实现、抽象c2h_fixed_pattern_tx作为另一正式后端、算法stub、历史失败候选、旧bit/CWC/DB/log/完整备份目录。
- 本次没有开发派发；下一次实际实施以此计划与届时重新核对的两个main为入口。

