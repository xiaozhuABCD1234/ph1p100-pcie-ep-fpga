# 第四包：相机中止/溢出跨CDC恢复（2026-10-25）

原任务与既有“接着做”授权继续，必要可逆修复仅在本run副本内。正式包现为4/4，两级、1目标、batch1；本文件不新增生产写回、TD/bit/下载/Flash或任何额外目标。第四包 `T10.a1-abort-cdc-fix` 的唯一结果是：相机帧损坏/丢beat导致的中止可靠、有序送达RAW写者，坏帧不发布，后续完整帧恢复。

## 实际证据与不同根因

原恢复包resume01编译一次、两clean及两中写reset局部通过，但bad-frame实际失败，overflow未运行。坏ROI行使crop_abort=1、crop_valid=0；FIFO接w_valid=crop_valid，故即使w_ready=1也未接收abort。RAW活动半帧2group未释放，后续SOF被!raw_active阻塞，4good之后等待完整1,000,000 A1周期仍recovered0。证据是 `T10.a1-recovery-sim/resume01/defect-evidence-resume01.json` 和对应raw trace，非timeout推测。

稳定新problem=`T10.a1-recovery-sim:SCOPE_CLARIFICATION:crop-abort-cdc-loss`，补充机会0；旧descriptor问题澄清机会1保留。这与已独立通过的描述符修复不同，不把旧ID/轮数改名重试。原恢复包尚未综合验收、实际修复0；累计42工具调用、2compile、3clean实跑、3fault（两reset+坏帧）、载入前失败1。T08和descriptor-fix均r0独立PASS不变。

## 输入与窄写域

基于 `recovery-dut-binding-resume01.json` 的8RTL：已PASS exporter SHA `0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097` 必须字节不变。只允许新包 `candidate/camera_a1_uart_top.v` 修改cam→A1 FIFO入口保持/abort/丢帧控制、RAW侧abort/skid/admission及必要直接统计；其余7RTL不改，不改crop、async FIFO、slot store、编码核或协议。源码与模型/TB只从冻结输入/原resume01只读引用或在本新包复制，不覆盖旧文件。

允许开发写 `OUTPUT_DIR/T10.a1-abort-cdc-fix/**`；测试只写对应test-reports证据域和 `<task_id>-r<round>-integrated.md`。inputs、旧r0/resume01、两项已PASS候选、生产/upstream/fpga/tools、TD/板候选、共享盘符和其他工作树全保护。

## 五项语义步骤与接口合同

1. 真实crop abort是独立事件，即使crop_valid=0也必须受理。接出FIFO w_ready，建立摄像头域有限pending/保持控制，不能简单OR后在满FIFO再丢abort。源CSI不可反压；首次不能容纳的像素/异常使整帧失效，保留abort请求直到真实FIFO接受。FIFO侧已提出的token在stall保持w_valid/data/sideband稳定，可用本模块内小holding寄存器；不得强制跨域状态。
2. abort token与已接受像素在同一真实43bit异步FIFO有序传递（abort=1、像素SOF/LAST为无效，禁止把旧像素当数据）。先前已接受的像素在abort前，后续完整新帧SOF在abort后；pending/丢帧期间不插入新SOF或半帧。abort接受与新SOF同拍时优先abort，丢到下一个fresh crop_sof再开完整帧；连续异常可按同一丢弃区间合并，但必须说明事件/帧统计含义，不能声称未计的每帧都精确计数。
3. RAW侧abort必须优先并撤销该写会话的pending skid/take/refill/last、释放真实WRITING slot，不能只在raw_active位为1时处理却留下尚未完成DDR提交的写会话。显式考虑e_last进入skid后、真正store接受前的边界，以及abort与skid take/新SOF同拍。通过本top控制真实store接口，不能用层次force/修改slot store。读/已发布槽保护与正常帧顺序保持；异常真实drop/error计数至少增加一次且无坏帧发布。
4. 定向真实DUT正反向：复现原bad-frame abort-only/valid0丢失；FIFO满时abort保持、释放后按序送达；真实overflow整帧拒绝/恢复；pending abort期间reset和fresh SOF并发边界；至少两组非同频cam/A1时钟比例/相位（如cam14ns与A1 5.333ns，及cam3.7ns与A1 5.333ns，正常喂数间隔可限制以免无意overrun）。检测真实accepted abort恰一次、RAW abort/slot释放、无死锁/半帧/旧epoch。原top+已修exporter必须正确编译后在目标bad-frame断言失败，禁止编译错充反例。
5. 同一新8RTL候选重跑完整clean W8/H2>=4帧、clean W32/H2、RAW/encoded外部AW/W中写reset、bad-frame、overflow及checker反例，输出差异/命令/有限账/唯一manifest和完整corrected-dut-index.json。停止所有修改和命令后交一个新独立综合测试者；通过后回原规划，再续原恢复任务，不新建第五包。

## 数据、命中与验收门槛

保持现有A+封包、44B头、四CRC、严格zlib、源像素和帧所有权。W32/H2 RAW80B，RAW store每256bit DDR字只装4个40bit group（有效20B），实际4个RAW字；resume01压缩流91B占3个DDR字。地址RAW_BASE0/CMP_BASE131072以256bit word计；不能把R10F其他线字节地址约定移入本模块。

两种中写reset实际前置：外部相应RAW/CMP AW/W已接受且尚未发布完整帧，记录slot/skid/计数；W32/H2、FIFO_AW4。坏帧/overflow W8/H2、FIFO_AW2，FIFO满/拒收必须实际命中，禁止force drop/计数或故障后reset掩盖恢复。保持DDR已接受延迟响应/内存，不能DUT reset时暗清模型；若pending old AR在reset时未命中，明确不宣称该额外条件被覆盖。

异常释放后最多4个不同good输入，至少2个完整正确导出，最后good FE后≤1,000,000 A1周期；严格逐字节/四CRC/zlib EOF和无unused_data/unconsumed_tail、零旧epoch字节/重复读/尾垃圾；坏帧或丢beat的受影响帧零发布，真实计数增加。每case真实进程、命中断言/中止路径观测和完整原始日志；不能仅信exit0/TB CASE_PASS。

functional=上述真实正常/边界/坏帧/满FIFO/overflow/复位及有效旧DUT反例；engineering=单文件窄差异、7项SHA保留、CDC只经过真实FIFO/源保持与目的原域控制、reset/stall检查、工具/命令/manifest前后零漂移；system=隔离写域/环境模型限制/候选身份与板候选保护。G0/G1为必需；G2 not_run，G3/G4/G5本离线任务N/A。不得用静态CDC审计或仿真宣称STA/硬件资格；TD/综合/route/bitgen/CWC/download/Flash=0。

## 有限预算、停止与后续

新开发每派发≤60工具调用/75分钟，综合测试≤45调用/60分钟；有限覆盖理由是源保持/满FIFO控制及真实双时钟正反向、完整恢复矩阵，需要多于简单队列修正的一次性环境准备。读取/搜索实际60s，单编译/单仿真实际300s+TB watchdog；首次+最多1次有新证据命令纠正，单问题≤3搜索轮，连续2轮无进展/缺工具权限额度直接blocked。每派发全量compile≤2，每冻结case首次+一次必要纠正，不盲重试。r0首次验收，最多3轮实际修复续本包原开发/原tester；不得因此扩到第二个改动RTL。

若真实证据证明还需要修改本top之外的RTL或第五个正式结果，不继续增包/改ID/新run绕上限，由原规划在4包边界内收束并给具体缺项。用户已授权的本top可逆修复不再次询问。

第四包同候选独立PASS后，原规划冻结组合DUT（本top+已PASS exporter+原6项SHA），续原恢复开发到新resume02目录，完整复跑受影响矩阵，原恢复首轮综合仍r0。所有旧blocked/原始失败/compile/仿真/实际修复和两个稳定problem机会分账不清零，不拼resume01局部PASS。
