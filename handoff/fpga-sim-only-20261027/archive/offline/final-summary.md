# 本轮结果与证明边界
run_id=20261027-060708_fpga-parallel-offline-delivery；实际根 D:/fpga/repos/ph1p100-pcie-ep-fpga。本轮按原需求完成三包的可执行交付与独立核验，结果是两个离线包接受、第三包工具准备接受而真实收益仍外部阻塞。没有统一整机候选，也没有整机PASS。BATCH_SIZE=1，三个正式工作包、两级；每包独立新开发/新综合测试，未跨包拼接验收。

| 包 | 唯一独立结果 | 实际修复 | 完成/未完成 |
|---|---|---|---|
| T03.pcie-byte-replay | round0 PASS | 0 | 当前槽/描述符字节定位、离线A1U1补头/metadata/回放、责任图与正负向完成；真实后端补头/身份/容量/尾零/PCIe连接未实现 |
| T08.freerun-isolation | round0 PASS | 0 | 真实冻结checked CSI/双writer/槽所有权的不可反压源隔离矩阵、满队列丢整帧/身份/恢复完成；未接入P4、未做双1080p30持续服务或曝光同步 |
| T04.real-raw10-benchmark | round0 FAIL，blocked | 0 | 可执行输入门/编码收益统计工具与独立核验完成；合格实拍0，真实收益0次测量，ratio/real_summary=null |

## 唯一输入与独立报告
每包各自唯一manifest和报告的完整SHA/角色见 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/candidate-binding-final.json；各包记录见 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/records/。这是三个不同证据闭包，不能组合成一个生产bit候选。manifest/report收口哈希再次重算；原测试者已分别完成全输入前后核验：T03 119项、T08 370文件、T04 151项，均0漂移。规划没有重跑或替代独立验收。原dispatch、plan、guide、index已被manifest绑定，保持字节不变，后续控制通过新增dispatch文件传递。

## T03实际结果
真实P2/store独立编译仿真，槽内70B实际zlib逐字节一致，开头78 9c，不是A1U1；P2输出dma=align(zlib,4096)。48条真实描述符含4052..4096长度夹具，其中44种按44B头布局会多一页；夹具不是压缩核真实数据。槽最后DDR word内26B零得到观察，整个DMA页尾零未证明。P2 cap=1仍ARM是记录下来的容量责任缺口，根pusher静态有拒绝但未接本次DUT。
4个正向（合成flags0/1/3与历史b18）严格EOF/四CRC/逆变换/逐byte通过，17项非法输入拒绝，独立头/像素oracle与变异命中。补头/sidecar由本离线工具完成，不假称硬件已补头。
硬件serializer、CRC/几何与camera/session桥、word×32字节映射、全页尾零和实际PCIe/ACK释放仍交原集成线后续。责任全文 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/T03.pcie-byte-replay/byte-responsibility.md。

## T08实际结果
测试者独立重跑六主题、420us长忙和ready-gated假驱动负对照；115个完整DMA帧、471040个native字节独立检查，身份/字节/CRC/尾零错0、held覆盖0、拒帧发布0。每路12源帧，busy/full超过两槽容量；恢复最少每路3good。源计划不依赖ready，真实DUT保留checked CSI/writer/mailbox/ownership/release。
W8/H2/20B packed/4096B DMA、小模型每槽仅4KiB；真实默认1920x1080的2592000B RAW及2592768B含128B头对齐DMA只是静态容量核对。双路30fps有效RAW155.520MB/s、含头对齐155.566080MB/s是计算预算，不是实测吞吐。实际双向SOF先后在纳秒范围，另有B延后微秒场景；不证明曝光同步。
P3仅接口语义核对、未实例化，P4未合入；物理DDR/PHY/PCIe、最终STA/CDC/资源均未测。旧源码SHA复用为输入，旧运行PASS未复用为本轮验收。

## T04实际结果
独立39项原工具控制重跑，40项测试者检查、9条结果独立字节/DEFLATE/RAW10逆变换；独立规范化、四CRC、长度/对齐/三比率及双回退统计一致。新增混合合成控制确认回退块比2/3与RAW字节比0.6不同；这是统计工具控制，不是实拍收益。空真实输入CLI实际rc3、real_sample_count=0、ratio=null、real_summary=null、benchmark_result=blocked。
工具用根A+ v1 fixed/LZ77/stored参考，不使用A1T1 record当A1U1；dma=align(44+zlib,4096)仅离线参考，不能混当前P2 align(zlib)。未知相位只00；明确u16大小端/10bit/移位后才转packed；不猜相位/字节序，不截断为8bit。
b18仍为历史真实UART来源，2594750B A1U1、2592000B RAW、540 stored回退，无源像素正确性oracle；可解码不等于合格真实收益图集。N/L、CONTENT=2和所有生成控制排除real-summary。
因此完整T04判定FAIL/blocked，并非发现DUT硬件坏；工具三维准备pass、真实测量三维blocked。缺项见 D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-060708_fpga-parallel-offline-delivery/questions-real-raw10.md。

## 工程、资源、时序与设备
T03 G0/G1/G5在离线范围pass，G2不适用本新增软件/TB；T08 G0/G1/G5pass、G2not_run（无RTL改动的TB包，未做物理资格）；T04 G0pass、G1/G5工具pass/真实blocked，G2纯软件不适用。全部G3/G4not_run/awaiting_hardware。
最终STA/WNS/TNS/hold、ERAM/CWC/LUT/IO资源、实际板级吞吐无本候选新数字，明确not_run。TD/synth/route/bit/CWC/下载/COM/JTAG/Flash、RK写入、安装、commit/push、外部消息全部0。P4/H-only/A+H及旧候选不改，根生产也未替换，全局任务板保持只读。
测试报告保留各角色初期只读bootstrap未先设置deadline的执行偏差；随后RTL/软件命令有实际deadline。也保留ModelSim负对照rc0但Fatal、失败launcher等历史，不抹去失败日志。不能将流程偏差或负对照误当新候选硬件故障。

## 当前停止与后续
本轮所有开发/测试均已实际返回、无新角色/命令派发。run状态blocked，唯一外部阻塞T04合格真实输入，不将总目标置完成；没有缺数据重试/修复循环。
准确角色/恢复入口及新目录规则见handoff.md；回退是停止引用新离线包，生产从未替换，无需删除。父T03/T04/T06/T08/T10/T11均不因本轮离线结果置done。
剩余最多三主题：①原集成线补44B头/身份/容量/尾零与真实PCIe；②自由运行捕获源接入生产、同候选G2/G3/G4及曝光/全尺寸服务；③取得合格实拍RAW10恢复收益测量。前两项仍由原活动线后续任务承接，不在本run自动执行。

