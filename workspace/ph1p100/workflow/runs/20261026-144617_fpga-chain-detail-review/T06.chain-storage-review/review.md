# T06 存储链路细节审查（round0）

本包按原计划五步完成只读审查产物，待独立综合测试。最优先的新发现是 **begin/abort消耗一位排序状态可导致READY槽逆序，进而错配导出描述符（F05）**。已知原生地址与完整写mask差异继续保留（F01/F02）；没有实施优化或新候选。审查通过仅表示完整性与结论可靠，不代表被审查DUT已通过，不关闭父T06或整链路。

## 输入、候选与边界

统一baseline manifest SHA256=c08adc09b364828fee5d94953a89898a3220af8c8f99cdec52404fec06f74c96，287份快照在组装时逐项核对。T02已验manifest=af32567395a3083b3b5005df40cfc37857f54b133293a644782eca9d6a34b997，独立报告=c96751cda203daf4c53a47909760f7d5b2edd3b88abdedbda0e625d67d2fb920；其329个冻结文件逐项复核，全部只读引用。控制副本及恢复授权绑定于control-bindings.json。HEAD沿原计划27c596b01cd961dfa9d0850e4fbf879fe249de90，预存dirty/删除未知所有者全部保护。

实际b15编译入口B0155选changed-src store B0144、arb B0143、bridge B0153；旧td/src bridge B0163不能替换当前实际源。source-map.json记录原路径、快照、SHA、编译路径和旧candidate字段；只认证审查输入，未认证所有依赖到旧bit。b17在统一baseline只含计划/指南/索引，保留待实施状态；不跟随其活动目录变化。

三条存储分支分别处理：b15 A+ UART双RAW/双CMP槽；原生三槽preview store B0040；独立upstream RAW/R10F AXI生产参考B0098/B0101/B0103。后者有B响应、字节地址与AXI byte-enable，不能把native PAXI mask极性覆盖过去。预览replace READY不能作为DMA可覆盖依据。

## 五步覆盖

1. **布局/单位/容量**（C01–C06）：默认RAW每4个40bit组用一个256bit字，20B有效、32B传输；raw0=0..129599，raw1=129600..259199，cmp0=262144..343228，cmp1=343229..424313，间隙2944字。19位最大字下标在2^24字容量内；改参后的32bit加法/27bit截断/24bit原生转换需额外检查。RAW无行padding，行480组对应120字，RAW尾帧整字。MODE1 keep为连续低位和非末全字的前提必须保留，任意稀疏keep不能由popcount自动紧凑化。
2. **PAXI/CDC/接纳**（C07–C15）：地址漏左移与mask相反是确定源码差异；真实MC内部仍未证。桥AW/W使用aw_seen/w_seen分别持有直到双完成，WF pop后有等待；模型只同拍写，未覆盖分开接受。内部AW/W为原子pair，store忽略AWready依赖arb/bridge绑定；不能泛化为标准AXI master。arb grant未在stall锁定，新请求可能改变下游mux，需限定接口合同。读owner在AR建立到R/abort，轮转只提供在服务有界前提下的成功事务公平，不能承诺最大等待时间。bridge单AR至RLAST不是AW/AR互斥，L_max=1无独立原生证明。FIFO reset有各域释放，桥自身DDR FSM仍用A1释放复位，rf_pop_gray新增跨域未见专属skew约束。
3. **所有权/发布/恢复**（C16–C30）：正常begin仅取FREE、abort压制同拍flush且可在另一FREE槽同拍begin，这些保护不能删。RAW/CMP last仅入WF就READY，没有最终原生可见fence（F04）；晚CSI裁决只影响仍WRITING的槽，不能撤销已READY/READING（F06，继承T02-F02/F03）。一位slot_seq在begin而非真实publish翻转，abort制造排序歧义（F05）。descriptor队列同拍push/pop计数本身有统一接受点，但E_OPEN ID/长度错配只计错继续发，无法掩护F05。

   raw timeout仅R_RW且AR已被store侧接受时计8192 A1周期；实际是AF enqueue而非native MC接纳，不能称端到端MC延迟计时。same-slot retry最多2次，GUARD32768 A1周期；桥A1hold70000、DDRguard65536且保持WF。窗口内旧R排空有结构支持，超过窗口并落到新ar_busy的旧R没有tag/epoch可分（F07）。top watchdog在F_WAIT超16777216周期发rd_close并退IDLE，但store仅R_HOLD受理，R_AR可永久挂住（F08）；CMP RETRY_EN=0无同等读丢失恢复。raw_id是admission，不是capture_seq；业务reset也没有跨旧MC响应的独立代际保证。

   upstream RAW/R10F等待EOF/good、payload/beat总量、B响应及头重写后裁决，按实际pub_par设置protect位；满FIFO可丢EOF并依赖timeout。ARM/TX/HELD/session ACK与cancel DRAIN保护分开记录，错误ACK不释放HELD。旧closedloop报告限定其冻结候选；该分支完整DMA/PCIe外传后续T11审查，不把源码存在写成b15已接入。
4. **服务预算/模型见证**（C31–C35）：witness脚本源锚定地重算与构造反例，结果见witness/result-r0.json。payload每路77.760MB/s、双路155.520MB/s；RAW因20/32布局每方向124.416MB/s。按CMP槽容量2594720B预算（不宣称已证明编码膨胀上界），RAW写+读+CMP写+读=404.5152MB/s/路，双路809.0304MB/s；25%参考=505.644/1011.288MB/s。未计命令、refresh、额外头/fence和重试，因此是预算基础，非实测保证。总421370个256bit搬运/帧，单路12,641,100次/秒，双路25,282,200次/秒，需真实共享服务率与空窗资格。

   两槽只给深度，不能推出60fps；最坏持槽时间/RAW读后释放/生产CMP回收决定是否持续。P4单核187.5MHz、TB slot-free、93.75MB/s sink、行为DDR只在原scope成立；strict serial和raw不可压缩sink门槛保留，生产双路未证明。b15模型低19位数组地址、忽略mask、独立AW/AR，旧CRC全绿无法排除native误用。小图样五模型只说明给定合同下的错误/适配，不复现或归因真实MC缺R。
5. **交付/冻结**：35行checkpoints、15项findings及source-map、witness、commands、lessons、局部引用与哈希核查，所有开发活动结束后唯一manifest-r0.json。详细触发/收益/代价/后续验证在findings，不新增正式任务。

## 可复查见证与独立复核入口

- F05合法顺序轨迹A(slot0),B(slot1),C(slot0 abort),D(slot0)导致B/D同seq=1、expect=1，优先槽0返回D而描述符首项B。测试者应以独立FIFO提交oracle、穷举轨迹或实际store微仿真验证，不仅复读开发模型。
- 两字不同图样分别用宽松字地址、native addr>>3、mask1屏蔽、联合合同及外部address<<3/mask0适配对照。预期不一致0/1/2/2/0。这是离线算术模型，非厂商MC或真实DUT仿真。
- 单字WF已入队而native写阻塞、AF独立可读的发布轨迹显示read-before-visible允许窗口；没有声称已在实际板上捕获。
- R_AR下watchdog close不被store case处理，以及旧R超过guard落入新busy的归属谓词，均为源锚定状态/布尔见证，非cycle-accurate仿真。

## 优化顺序及已有证据资格

先正确性：原生地址/mask与接纳合同、F05顺序、发布可见/晚裁决、F08取消状态与代际隔离；再可观测性：失败AR完整地址/低3位、实际AW/W/AR接纳和写可见；再吞吐：生产slot-free/共享服务/真实sink/双路资源；最后来源收口。没有依据直接删除FIFO、skid、CRC或slot状态；同名源码副本只作可维护性冗余候选，没有ERAM/slice节省承诺。

旧b15 G2=原报告诊断SWNS+0.012ns而非生产STA/CDC签核；G3=原一次SRAM下载/150秒观察；G4=H4_UNRESOLVED、enc/exported=0；G5持续生产服务not_run。旧报告“已排除bridge根因”“L_max=1”等外推不采用。审计对cam11/cam12与均值失败字编号的纠正保留；不追逐跨快照后的三帧完成状态，报告内部已写完成而审计早期写仍运行，仅按各自时点资格记录。新G2–G5依冻结计划not_applicable：本包只读，不交bit/签核；这不删除原硬件缺口。

未运行TD、综合、布线、STA/CDC工具、RTL/完整帧仿真、bitgen/CWC、下载、COM/JTAG、Flash、板卡/RK或网络下载；不使用共享库/盘符。未修改生产、T02、baseline、任务板或其他run。回退为保持全部原候选；若审查结论错误，只在本任务新轮修正文档并重新冻结，旧结果保留。所有发现等待独立综合测试，当前无DUT通过声明。

补充资格：F05已确认的是store模块在合法接口事件轨迹中的发布顺序缺陷。描述符错配是消费者延迟领取、该轨迹在整机可达时的后果；默认全尺寸b15调度的完整可达性未在本包证明，也未声称板上实测发生。11份changed-src与旧candidate SHA全部独立核对，见candidate-bindings-r0.json。
测试者如复跑见证，请使用`check_storage_contract.py --stdout`并把输出保存至自身测试目录，避免改写冻结的开发result-r0.json；最高风险F05仍须使用不同判据。
