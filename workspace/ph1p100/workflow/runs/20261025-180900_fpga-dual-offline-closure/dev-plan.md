# 两包独立离线闭环实施与验收计划

项目根 `D:/fpga/ph1p100`，run `workflow/runs/20261025-180900_fpga-dual-offline-closure`，runtime Codex。本轮一个主要目标：双路FPGA已发布完整RAW帧的离线生命周期闭合，分采集/消费和编码服务两个正式包。`request.md`中的“上述两者”明确授权这两个工作内容；正式包2/4、仅两级、每包≤5项语义步骤；不增加目标/任务/层数上限，BATCH_SIZE=1，**不是batch2**。并行是两个各自新开发、各自新综合测试者的独立任务，不是角色复用。不得增加第三包或悄悄续做后续主题。

|task_id|问题/产物|实际工作树/允许写路径|依赖|functional|engineering|system|必要G层|状态|下一动作|
|---|---|---|---|---|---|---|---|---|---|
|T08.dual-local-closure（父T08，涉及T06接口）|生产RAW源集合派生双路同步接入＋本地DDR CRC消费/释放，连续超过两槽容量|本根；仅本run `T08.dual-local-closure/**`|冻结旧T08与b10配置器、本指南；不依赖T10实现|真实双路CSI/writer、引脚I2C/掩码读回、CRC、持有/回收/恢复|真实top编译精化、静态CDC/复位/地址、唯一manifest/源闭包|双消费者互斥、非覆盖/回退/无共享写|G0/G1；G2/3/4 not_run|ready|新开发→停止冻结→本任务一个新tester|
|T10.dual-aplus-scheduler（父T10，涉及T11接口）|两路完整R10F描述符→公平调度→DDR字节适配→真实A+核→双CMP sink槽与释放|本根；仅本run `T10.dual-aplus-scheduler/**`|冻结共同合同、真实frame/core；TB描述符/DDR模型独立生成，不依赖T08运行结果|两路交错真编码/严格逆变换、跨word/尾部/背压、所有权/故障|真实核SHA不变、编译精化、宽度/容量/服务预算、manifest|无饿死、held CMP/RAW不覆盖、错误会话拒绝|G0/G1；G2/3/4 not_run|ready|与T08可并行新开发→本任务一个新tester|

## 开发步骤（每包五项，不再拆子任务）

T08：1. 核对冻结SHA并只在自身目录复制旧生产派生源，加入可复用顶层/源列表与默认关闭的双路local模式；2. 在命名wrapper保留b10掩码读回/超时并接入同步独占I2C、接出既有同步快照；3. 双writer正式接出本指南描述符与匹配释放，复用CRC reader加双路公平选择/互斥读所有权和安全排空；4. 增补DDR读模型和正常/故障/持续采集TB及独立字节检查；5. 运行局部检查，保存差异/实际命令/预算与未测边界，停改/停活动冻结manifest及lessons。

T10：1. 核对/复制两份不可改core输入，按共同合同实现每路两槽描述符/所有权与帧公平选择；2. 实现R10F检查、native AXI reader和紧密256→40bit适配，安全abort/drain/lock；3. 接真实frame/core、双CMP sink槽/身份/容量及完成失败回收；4. 独立DDR/输入生产模型、严格zlib逆变换/源图案及公平/满队列/故障测试，输出服务预算；5. 运行局部检查、源闭包/接口接入说明与lessons，停改/停活动冻结manifest。禁止优化或修core。

## T08必须场景与门槛

1. 正常真实top：保留真实checked CSI/双writer/arbiter/sync/ui_i2c；引脚级I2C模型支持真实随机读，不以直接bus_done stub代替；每路≥6个不同完整good帧成功读回并释放（总≥12，必须重用同槽至少2次），A/B同时发布与在读时持续来帧均命中；每个R10F header/payload/长度/尾零与独立源图案一致，mismatch=0，误release/半帧pub/受保护覆盖=0。读回完成后至少两对新帧继续发布，不是只写满四槽即结束。
2. I2C：旧正常14角色事务与清理顺序/warmup8保留；新增掩码读回正例、受检位错误拒绝、非掩码位变化允许、最后字节NACK、busy/应答超时、已接受事务未响应时reset，失败时不误ready、不放半帧；reset后重配和warmup、≥2对good帧恢复。实际事务数与read_mask来源输出。
3. 数据与生命周期：A坏CRC/短帧/显式abort任一拒整帧；缺B造成失锁停止并恢复；消费者延迟致两槽满时丢整帧并计数且旧内容保持；本地CRC失败安全排空后释放、下一≥2对good恢复；AR等待ready的abort和已接受AR的迟到R/drain均命中；永久缺R必须LOCK保槽不误报可继续；共同reset后新会话正常且旧rel拒绝。
4. G0/G1：源集合包括新增同步/local模块，默认关闭路径精化及原正常case回归；启用模式真实top完整精化，无未解释目标端口/宽度/多驱动告警。引脚/DDR/checker明确列环境替代范围；静态核对候选编译源不存在stub替代真实writer/CRC/sync。至少一次高地址B槽读和W1920/H1080默认长度/边界可执行静态检查；小参数仿真不扩称全尺寸持续帧速。
5. 测试者独立重编译/运行正常及所有故障类别；另写或改造独立字节解析器使用Python标准CRC核验DDR实际读回数据；至少一个“B release误送A”或“未完成读即释放”的变异负对照正确编译并被对应断言拒绝。旧六场景证据可供设计参考，改cfg/双reader后不得直接复用成当前PASS。

## T10必须场景与门槛

1. 小/边界几何W8H2、W8H3、W64H8：两路不同图案至少各4帧交错（总≥8），同拍A/B入口、连续descriptor、只A/只B再双路均命中；每帧用真实frame/core输出并strict zlib+逆变换逐byte恢复，raw/xform/stream CRC和长度全正确，0错/0重复/0尾垃圾。W64H8足够多次跨32B/5B与行边界；W8H3覆盖odd-height末块。
2. 默认全尺寸：W1920H1080按A/B各1个完整不同帧顺序服务，真实core完成两个不同身份输出并严格还原；记录AR读bytes/words、payload组数518400、末beat keep、stream精确长。此为内容和地址/容量验证，不能称双路30fps。若本机无法在冻结deadline内完成，诚实blocked，不临场改小尺寸求PASS。
3. 公平/容量/接口：两路持续待服务时连续≥8次选择严格交替，任一路最多等待当前另一帧+至多一次选择；模型量化每帧有界完成周期。慢sink持有两个CMP槽时RAW不得被提前接纳或覆盖，匹配ACK后恢复；错误/旧epoch/重复rel和CMP ACK拒绝；输入/output随机确定种子背压，valid stall、同拍take/refill、最后一拍均断言。满/拒绝的source capture_seq缺口保留，不伪造连续号。
4. 故障：R10F头/载荷CRC错、错身份/base/高位越界/length截断拒绝且无CMP成功；容量不足、RRESP错误、编码时abort、AR pending/迟到R排空，均不发布半码流、释放正确RAW和未发布CMP、后续≥2个good继续；永久缺R进入LOCK保槽、共同reset恢复；不修改冻结核伪造frame_abort/commit。
5. 测试者独立重编译、重跑所有类别和全尺寸；至少一项不同判据（标准zlib严格EOF＋独立数学图案）及一项组跨word/相机身份交换变异负对照被拒绝；报告实际吞吐/队列/最坏stored容量，明确不满足双路实时的历史服务预算。外部R10F解析器不能用codec枚举变化接压缩流。

## 公共检查、工具与预算（派发前冻结）

两包各自全新开发、各自仅一个全新综合测试者，round0首次验收；真实失败原角色续接，最多round1—3实际修复；本轮不跨任务复用角色。旧任务/旧run的失败记录不重置，本轮新增接口目标用父T任务局部标签，未伪装续旧b10恢复包。

每开发≤60次实际工具调用/90分钟，每综合测试≤45调用/60分钟，规划≤30/15分钟。较默认覆盖理由：A需要完整生产top+引脚I2C读回/双DDR读模型；D需要真实核全尺寸两帧与多故障，均为有界离线实现；只覆盖执行预算，不扩大任务数/目标/权限。开发每次派发最多4次compile，tester2次；每个场景最多初次+1次有新证据纠正重试，同失败命令仍最多2次；总仿真case进程每角色每次≤20。禁止用shell循环绕次数。单问题≤3轮搜索，连续2次无实质进展/到限/漂移/缺工具或资料/API额度即停，返回稳定problem及恢复输入，不自动扩预算。

工具入口见input-index。每任务独占modelsim.ini/工作库/日志/WLF，无共享P/W/T/Y/X映射。读搜实际timeout60s；编译/局部静态/小几何单case实际300s；仅T10全尺寸双帧case允许实际600s（真实核数百万周期，预先有限覆盖），顶层testbench另加cycle watchdog。runner用subprocess timeout且仅终止自己进程树；exec yield不算timeout。不能安全控制时不启动，TOOL_CONTROL_MISSING。TD/synth/route/bitgen/CWC/下载/Flash=0，板卡/COM/RK/外部服务=0；无常驻监控。

G0/G1为必要门槛，Errors0/目标断言FAIL0/超时0/数据差异0，所有必须场景有显式hit与完成标记，不能仅exit0。engineering的最终STA/资源/物理CDC、system的曝光/板级恢复/长稳/硬件吞吐均not_run，后轮awaiting_hardware，事前如此定义是用户离线范围边界，不得把新RTL称完整实现资格通过。三维在离线合同内必须独立有证据；G2未通过或未知不能用旧报告补。

## 交付、冻结、测试和收尾

开发产物至少含真实RTL/候选差异、`sources.f`/`integration-sources.tcl`及文件存在性校验（仅源集成入口，不执行TD）、runner/checker/TB/模型、机器case结果与原日志、`interface-map.md`、`result-r0.md`、`lessons.md`、`manifest-r0.json`。必要约束/IP仅引用本候选准确路径及未运行状态；不得复制旧bit报告冒当前G2。manifest包含全部参与文件/工具/参数/命令SHA、共同指南/规划输入SHA、模型替代、`stopped_modifying=true, active_commands=0`。冻结后所有开发活动结束才ready_for_test。

tester只写本run `test-reports/<task_id>/**` 和 `<task_id>-r<round>-integrated.md`，不改候选；报告按现行report-contract，首行唯一PASS/FAIL、同manifest三维和G层、前后漂移0，独立复现和负对照真实命中。报告和返回须区分fail/not_run/blocked。开发/测试缺外部条件直接FAIL/blocked，不空转修复轮。

主仅按dispatch逐项spawn两个独立新developer，记录工具真实ID；任一ready_for_test返回即新建本任务唯一tester，不必等另包；测试返回PASS/blocked交回原规划。并发上限随宿主槽位，槽位不足顺序入队，不能创建替代角色或轮询进度。任一task blocked不阻止另一独立task按原合同完成；主不自行处理技术影响。

原规划只在收到结果后读报告，更新本run控制文件/独立交付索引，最终最小追加 `workflow/records/T08/20261025-180900-dual-local-closure.md`、`workflow/records/T10/20261025-180900-dual-aplus-scheduler.md`；必要时以并发安全的最新tasks.json只追加这两父任务证据说明并保留其他字段/state，不能覆盖OpenCode修改。发现并发冲突则只交记录路径，不自动重试覆盖。主不读技术计划/报告。

回退：停止采用新run隔离源，生产和板候选从未更换；所有日志/失败保留，不做删除、Git提交/发布。剩余仅三主题：①本轮两包结合b11最终冻结候选迁入统一生产、G2与真实曝光/恢复；②双路实时服务率/双核或其他架构的后续有界选择；③三算法共存及旧b10恢复补丁迁入。均不自动执行。准确后续入口为 `$fpga-orchestrator 恢复：D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure；本轮目标：读取两包manifest和独立综合报告，按本轮原范围继续未完成离线闭环。`，原真实角色有效则续原ID，不重置账。
