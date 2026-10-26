# 双路FPGA离线候选设计冻结 v1

本轮冻结两项可独立验收的源代码候选：T08.dual-local-closure、T10.dual-aplus-scheduler。生产/板级迁入不在本轮执行；“正式接入”交付是现有生产RAW顶层派生源集合中的真实RTL接入及可重现源闭包，不能仅新增TB回放stub。完整TD G2和板级G3/G4明确not_run，不以本轮PASS代替。

## 1. 数据与内存

唯一共同RAW格式是现有cam_r10f_writer的R10F v1 codec0、128B头、小端、packed RAW10，四像素40bit：`in_pix[7:0]=P0[9:2]`、依次P1/P2/P3、`[39:32]={P3[1:0],P2[1:0],P1[1:0],P0[1:0]}`。DDR word bit[7:0]是最低地址字节，连续packed流紧密占用32B beat。本轮**不采用**b10/b11的每20B占32B RAW槽布局；不能把四组/word的reader直接套入本轮。

长度分开：`raw_bytes=payload_bytes=W*H*5/4`，`content_bytes=128+raw_bytes`，`dma_bytes=ceil(content_bytes/4096)*4096`，`stride_bytes=W*5/4`；不把DMA尾零或R10F头送入编码核。W%4=0、W>=4、H>=2，A/B几何一致；默认W1920/H1080，ROI X960/Y540/SKIP37保留，只在TB实例缩参。默认raw=2,592,000、content=2,592,128、dma=2,592,768B；payload offset128。地址为字节，AXI宽29bit，base高位截断/加法溢出必须拒绝，不能静默别名。

RAW槽基址固定A0=0x00100000、A1=0x00900000、B0=0x01100000、B1=0x01900000，每槽8MiB区间；每次实际读取仅dma_bytes，读取不得跨槽；描述符base须匹配其camera/slot。完整默认几何容量在静态计算与至少地址高位实际访问中检查。

R10F CRC沿用原RTL/strict.py：raw/payload CRC覆盖精确packed有效字节；header CRC覆盖128B且0x58..5B清零；DMA尾零全0且不计CRC。camera_id A0/B1，session/capture_seq锁存帧身份。头内sof_timestamp/timestamp_hz仍为0，表示未知；同步观测另输出，不伪造为真实曝光时间。Bayer相位按原ROI物理原点规则保留，A+仅支持其声明相位：本轮prep=0/pred=0可接任意相位，prep=1仅显式测试phase0合成输入；非phase0启用prep须在descriptor接纳前拒绝，不能无声重排或仅改头标签。

## 2. 共同描述符与释放端口（DHI/consumer同一时钟域）

v1为本轮内部元数据端口合同，不新增R10F外部协议或codec枚举。两个入口分别命名`a_desc_*`、`b_desc_*`，相同字段；公共消费者输出命名`desc_*`。写者已有`cl_pub_valid`是**单拍通知而非ready/valid**：接入adapter须当拍捕获，每路两槽独立mailbox，可同时捕获A/B。禁止直接接ready而丢通知。

|字段|位宽/规则|
|---|---|
|valid / ready|各1bit；只在valid&&ready移交描述符，stall保持所有字段|
|camera_id / slot_id|各1bit，A=0/B=1；slot0/1由四个合法base推导|
|epoch / session / capture_seq|各32bit；epoch由本轮控制输入，reset后新会话更新；session来自写者；同epoch/session/camera/seq唯一|
|base / dma_bytes / raw_bytes|各32bit；地址和长度单位均字节，完整帧验证之后才产生|
|width / height|各16bit；stride隐含width*5/4，必须核对头|
|bayer_phase|2bit；与R10F头一致，不能从A/B身份猜相位|

完成接口命名`rel_valid/rel_ready, rel_camera_id[0:0], rel_slot_id[0:0], rel_epoch[31:0], rel_session[31:0], rel_capture_seq[31:0], rel_status[2:0]`。status 0=成功、1=校验/编码失败且已安全排空、2=接纳前明确拒绝且无读请求。其他值保留并拒绝。valid&&ready一次才转成对应writer `cl_release[slot]`单拍。必须匹配正持有的完整身份；重复/旧epoch/错误camera/seq的释放计数拒绝，不影响有效槽。reset允许由共同DDR复位取消所有所有权，不能用仅consumer reset覆盖未完成DDR事务。

槽状态FREE→WRITING→READY(mailbox)→READING→FREE；完整EOF/good/所有B响应OK及头回写结束后才能READY。写者对受保护槽的新CSI输入丢整帧并计数，不覆盖READY/READING。两个slot不要求无限队列；合法保护使每路最多2个未释放描述符。入口满时ready=0，脉冲适配mailbox保留；有异常重复pub则锁/报错，不能覆盖旧描述符。

## 3. 消费者互斥、AXI与恢复

新独立候选的`DUAL_LOCAL_EN=0`保持旧生产派生行为；启用时`CONSUMER_MODE=1`选双路本地CRC消费者，`=2`选外部编码消费者接口（本轮A只需端口和静态闭包，不要求将D候选合入），`=0`非法并安全禁用。mode只在共同reset或四槽FREE且所有AR/R归零时锁存，活跃中改mode拒绝并计数。CRC与编码、旧pusher不能同时获得同一RAW槽或DDR读响应。A/B两写者均须启用保护并接出cl发布/独立cl释放；原top仅A连接的缺口本轮必须修复。原CLOSEDLOOP中的第三帧自动abort注入在新正常工作模式禁用，故障由TB明确注入；旧默认路径保持原样。

本轮native DDR口是既有AXI4 256bit、字节地址29bit、arid/rid4bit、ARLEN8bit、ARSIZE=5、INCR，不是PAXI单拍硬核。每次只允许一个未完成burst，最多128beat，不能跨4KiB；AR一旦valid必须保持字段到握手，RRESP/RID/RLAST逐笔检查，R stall保持；不得以watchdog撤销已经握手的读。调度器可用单拍ARLEN0简化，但必须报告实际效率，不称生产吞吐。

超时/abort：停止新工作，对已接受AR排空全部预期R拍后才释放；CRC/编码失败可在排空后status1释放，不发布CMP成功。永久缺失响应无法证明排空时进入LOCK保留RAW/CMP并报fault，只有共同DDR reset恢复；不得释放后将旧R记入新会话。测例必须覆盖AR未被接收时stall、AR已接收/R未返回时abort、可恢复迟到R、永不返回R锁定、reset后的新epoch与旧release拒绝。共同reset的DDR环境显式清除自身未完成队列；不声称裸AXI存在硬件epoch标签。

## 4. 同步与I2C冻结（T08）

复用旧真实sync_start_ctrl、sync_reset、sync_sof_mailbox/pair、sync_frame_gate、checked CSI、writer与写仲裁。保留b10配置器的read_mask集合、busy请求完成及TRANSACTION_TIMEOUT；在本轮wrapper中使写表/掩码读回完成后保持3000/3002 standby，30C1 Hi-Z，cfg_done表示“安全待同步”，然后同步控制器独占同一ui_i2c执行旧14笔角色事务及清理。AE在同步序列中不得抢总线；旧自动CANCEL_STANDBY/START_MASTER不能绕开同步控制。不要用旧overlay整文件覆盖而丢掉读回能力。

初始化表沿用冻结IMX415模式1；standby覆盖项的expected读值须同步更新，其余read_mask与值保持。正常应答/最后字节NACK/掩码位错误/非掩码位变化/事务永不busy或不完成/中途reset均明确验证。读回传感器模型只通过SCL/SDA产生应答，检查器不直接从DUT期望寄存器读答案。warmup8、WAIT默认1,200,000、PAIR_WINDOW/FRAME_TIMEOUT沿旧同步模块默认；缩参值记manifest。同步观测输出skew/pair_seq/miss/relock/timestamp来自既有50MHz观测域，通过mailbox/稳定快照输出，不能异步采多bit；SOF差值只证明数字链路对应。

## 5. A+调度冻结（T10）

真实a1_frame_top/core只从input-index所列两份冻结文件复制，SHA必须不变；调度/adapter在新文件实现。每路2描述符slot mailbox，帧级round-robin，起始A优先，之后在两路均有工作时交替；一路空则另一继续，重新出现的等待路在当前帧结束后下一次选择中服务。两个输入同拍接受不能丢；不得用额外复制完整RAW帧隐藏槽所有权。

R10F头先完整校验身份/几何/CRC/边界；payload以连续32B输入适配连续5B组，必须处理40bit组跨256bit word，恰好W*H/4次`in_valid&&in_ready`，第一组in_sof=1且stall保持，最后组不混DMA尾；同拍take/refill计数正确。payload CRC边读边算，尾部错误须使CMP无commit。core模式在首组锁存，整个帧不变。

输出沿core原32bit低字节先、out_keep逐byte、out_last的ready/valid。完成只以真实frame_commit、精确字节长与CRC核对，失败frame_abort丢该次CMP内容。本轮两个CMP sink槽（各8MiB，行为内存，不使用物理地址）FREE→WRITING→READY→READING→FREE，保持source完整身份；容量在写每个有效byte前检查，满则不接下一RAW帧，不能覆盖held输出。sink接纳是本地模型握手，明确out_ack匹配完整身份才回收；不是RK ACK或PCIe。

不改A1U1 44B协议，不新建外部封包：主要产物是精确zlib流+metadata(sidecar或CMP descriptor)，其中raw/xform/stream长度CRC来自核、source身份来自RAW描述符。若工具为复用解码器生成A1U1文件，必须按既有44B头/CRC，camera/session仍在sidecar，不能伪称该头已含双路身份。严格zlib `eof=true, unused_data=b'', unconsumed_tail=b''`，逆变换后逐byte等原packed RAW，0错/0重复/0截断；失败和溢出不能发布半码流。

## 6. 吞吐与实现证明边界

本轮R10F紧密布局双路1080p30有效RAW155.520MB/s；RAW写+读最低311.040MB/s，另加双路每帧128B头、对齐尾、CRC回写、CMP写读/仲裁空窗。b10的248.832MB/s RAW写预算属于20B/32B布局，本轮不得混用。最坏stored zlib上界为raw+5*ceil(H/2)+6：1080p2,594,706B，CMP8MiB容量足够，A1U1头另加44B。core已有81.067MB/s是指定向量核级历史结果，单核调度不满足双路155.52的确定性证明。报告记录实际cycles、raw/cmp字节、队列峰值、丢帧和服务空窗；不以平均压缩比放宽最坏带宽。

G0=源/合同/静态闭包，G1=真实数字RTL离线仿真；两包必要G0/G1。新RTL必须编译/精化、检查CDC/reset结构、地址/计数宽度、无隐含latch意图及参数；但不声称已得最终物理CDC/STA/资源。G2=not_run（生产综合/布局布线不授权），G3/G4=not_run、awaiting_hardware（本轮离线交付不包含板验门槛）；G5未排期。父T08真实曝光同步与T10实时整机均未完成。新候选若要用于上板，必须后轮取得授权并补同候选G2/3/4，旧G2不可拼入。

已冻结：两包职责/端口/RAW格式/地址/释放/恢复/核版本/离线验收；待确认：后轮b11最终manifest、生产IP/时钟/板窗及实际曝光，当前开发不依赖；不适用：RK、PCIe承载、三算法共存、历史b10恢复移植、TD或硬件执行。
