# 本轮设计指南

采用现行 fpga-design-guide 技能；本轮总目标为图片所列 FPGA 相机链路离线集成与恢复仿真闭环，两个工作包、batch=1 顺序派发。所有路径在 input-index 和 planning-input-manifest 中冻结。

## T08.sync-production-sim：生产 RAW 顶层派生仿真

真实 DUT 起点为 `inputs/production-raw/rtl/ep_side/ph1p_pcie_ep_top.v`，不得用 sync_offline_top 自身测试冒充生产顶层。允许在任务目录复制完整依赖并做最小可审阅 overlay，交付原文件到 overlay 的差异；不写回生产树。保留真实 sync_start_ctrl、mailbox/pair/reset、ui_i2c、配置表、checked CSI 解包及两个 cam_r10f_writer/仲裁器。厂商 PCIe/PLL/DDR/物理 MIPI 可以用明确列出的环境模型；从已有 MIPI_PHY_SIM_STUB 的包层边界注入 CSI 数据，不能替换目标数据通路、I2C握手或 SOF 配对为 stub。真实顶层必须精化、实际运行。

### 配置与 I2C

- 原生产顶层在 tl_clk_user 域有 A/B 两个 ui_cfg_imx415，CLK_DIV=624，cam_mode=1；真实 ui_i2c 写4字节：`34, addr[15:8], addr[7:0], data`，SDA低/高阻配外部上拉。现有 cfg 在表后会自动写启动/周期待机控制，30C1 默认驱动也与同步接管冲突。
- 新同步模式用可综合参数/接口明确选择；关闭模式保持原行为。开启时初始化阶段令两路 standby/stop/同步输出 Hi-Z，禁止自动/周期启动绕过同步控制，初始化完整完成后才允许同步器取得唯一事务所有权。不能只把 req_ready/rsp_ok 接常1；不能把 cfg_done 当每笔ACK。
- 接受仅 req_valid && req_ready；持有时 camera/addr/data稳定；已接受的一笔经真实 busy 上升/结束产生唯一 rsp_valid，准确锁存该笔任一 NACK，禁止 busy下降的同拍丢错误、重复应答或切到另一 camera。reset 撤销 pending；旧响应不得匹配新会话。超时保持现有 poison/reset要求。
- 独立引脚解码 scoreboard核对同步14笔：A 3000=1/3002=1/30C1=0F，B同；B 3003=1/30C0=2A；A 3003=0/30C0=2A/30C1=00；B 3000=0；等待≥24ms；A 3000=0；等待≥24ms；A 3002=0。cleanup六笔先两路standby、两路stop、两路Hi-Z。保留寄存器表内容来源；仿真缩短等待/分频必须显式参数化并另静态校验50MHz下24ms=1,200,000拍。

### 数据、SOF与复位

- 生产默认 RAW10：4像素/40bit输入，ROI 1920×1080、X0=960/Y0=540/SKIP_ROWS=37，packed=2,592,000B；R10F头128B、DMA=2,592,768B。A/B原地址对分别00100000/00900000、01100000/01900000，互不覆盖。本轮可参数化仿真 ROI 为8×2（10B/行、20B/帧），保留默认生产参数及格式/CRC算法；参数、地址单位、各长度必须写入manifest。
- SOF来自门控前两个真实接收输出，各自 byte clock，控制域按真实采样CDC。pair_window为控制时钟周期；用小参数做边界，不把 SOF差/同序号当曝光同步。
- warmup=8，前8个pair不ready，第9个pair后ready；ready经域隔离只能在各自下一SOF开始放行完整帧（因此最早第10帧可进入writer），不能从第9帧中间开门；停止/NACK/缺路撤销时已有半帧必须abort且不得发布。
- 用 A/B不同图案、帧序号和源ID检查实际两路写出的字节/长度/CRC/地址；配对错误、路互换、单路假双路必须被拒。连续至少3组被接收的完整帧均逐字节正确、每帧只发布一次。背压保持由真实 writer/arb实现。

## T10.a1-recovery-sim：固定 r5 DUT 的显式恢复测试

8项 RTL以 `inputs/a1-r5/src/`为唯一输入，RTL不可修改；仅新TB、外设模型、独立checker和runner。数据/封包/CRC/预测/DDR布局沿冻结真实模块，不新创协议。DDR模型以真实aw/w/ar/r接受握手保存/读回，随机/定点stall持有；延迟读响应归属不能在reset时假装自动清空除非接口确实清空。记录哪个reset清除哪个模型队列。

- 用例分开且有唯一标记：clean baseline；raw写入中 reset；编码/压缩写入中reset；坏帧（短行/缺行至少一种）；真实FIFO或slot满导致overflow。reset必须在已接受部分写且尚未完整发布时触发，并记录aw/w握手数、frame状态和精确时间，不用FRAME_CYC估计代替注入命中断言。
- 无reset的故障轮记录故障计数前后差值，要求至少一个实际目标错误/drop计数增加；整帧拒绝，不发布坏帧/溢出帧。不能要求reset后的计数还保留旧故障。
- reset轮独立epoch；reset前后相同图案不允许，避免旧响应/旧字节误判新帧。reset撤销pending/slot ownership；恢复的下一批完整帧正确，最多向源送4个good帧且至少2帧完整导出，最后一个完整帧FE后≤1,000,000个clk_a1周期完成（UART_DIV=4、小帧W8/H2）；必须逐字节/zlib解码/四CRC、无半帧、重复读0、尾垃圾0。每用例独立进程；仿真cycle watchdog和实际300s上限同时生效。
- overflow必须用真实有限容量和受控DDR stall/输出堵塞命中，并记录占用/满/丢弃与后续释放过程，不能force内部drop计数。释放后同样≤4个good帧恢复≥2个正确导出。
- 允许检查小几何W8/H2与FIFO_AW缩小（合法深度≥4）以有界触发；此为恢复逻辑证据，不证明1080p容量/满速/板级稳定。模式号本身不是覆盖，必须能显示注入前置条件、预期、实际及独立判据。

## 证明边界：已冻结/待确认/不适用

已冻结：上述格式、真实模块、接口、故障注入和恢复阈值、独占写域、G0/G1门槛与两个不同候选。

G2在本轮记录为not_run：本轮交付是隔离仿真overlay和固定RTL恢复测试，不生成/发布实现候选、不改变生产文件/时钟约束/IP。不能把其PASS称作生产集成已完成；同步overlay实际迁入和可下载候选必须另做真实完整G2（STA/CDC/资源/候选绑定），旧小顶G2不能继承。若开发发现必须修改受保护RTL才能继续，停止交规划，不能借本条豁免生产修改的G2。

G3/G4/G5不适用本仿真包：无硬件操作、长稳性能或发布授权。真实父任务这些门槛仍待完成。Functional=真实目标DUT与独立正反向判据；engineering=精化、时钟/reset/CDC接线静态审计、可复现manifest/超时；system=环境模型限制/写域/板候选隔离。真实工具缺失直接blocked，不临时降门槛。
