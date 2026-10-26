# T08实际修复round1派发：修复已验RTL缺陷，保留round0账

实际PROJECT_ROOT `D:/fpga/ph1p100`；run不变；task_id仍 `T08.dual-local-closure`；原开发 `/root/fpga_dev_dual_local_180900`；原唯一综合测试者 `/root/fpga_tester_dual_local_180900`。BATCH_SIZE1，正式工作包仍2/4，不新增ID/任务/角色。

## 裁定与授权边界

已读原综合报告 `test-reports/T08.dual-local-closure-r0-integrated.md` 及其 `fix-and-retest.md`、`reuse-decision-r0.json`、`overlap-coverage.json`。round0真实综合FAIL：F01/F02是有效刺激复现的两项RTL缺陷，F03是原必要覆盖缺失。这里安排**真实DUT修复round1**，不是继续耗尽的round0检查、不是F03单纯加测、不是格式补充机会，也不是重命名同输入重跑。

依据初始dev-plan“真实失败原角色续接，最多round1—3实际修复”和“开发每次派发/测试每次派发”的有限预算，以及fpga-planner/fpga-dev/fpga-tester同任务FAIL续原角色合同，必要可逆修复已在当前用户目标与“接着做”范围内。没有新增目标/角色或提高原每次上限，因此无需再问同一原目标的实现许可。原被耗尽round0的compile/case和19:57截止保持最终历史，不再给round0实验。本轮只对真实修改后的新manifest分配更小的有界修复窗口；若无法实际修复F01/F02，不能用本文件为旧manifest追加纯F03仿真。

round0记录不清零：开发compile4/4、case19/20（实际工具调用总数未由产物完整记录，原开发须从原上下文补实数，未知不可填0）；综合测试保守工具44/45、compile2/2、case20/20；实际验收后修复完成0、已出报告round0 FAIL。round1此刻仅已排定，原开发实际开始改动后才记实际修复轮1；不提前记完成或PASS。稳定问题 `T08.dual-local-closure:LIMIT_REACHED:active-read-arrival-coverage` 保留，补充机会新增0；真实修复分账，不转成回答机会。

## 本轮工作范围（五步）

1. 只读核对round0 manifest和报告/独立TB，恢复真实旧账；在本任务 `r1/**` 建新overlay/脚本/TB/结果，不改原manifest及其任何参与文件。
2. 修F01：每路ready/valid描述符一旦呈现，所有字段在stall期间固定到接受；正确保留另一槽新pub、同拍take/refill；覆盖A/B和slot1先到/slot0后到等顺序，不靠拒绝合法pub或改成ready常1规避。
3. 修F02：外部AR接纳、当前pending/outstanding和合法释放的同拍事件统一裁决；读请求已由ext_arvalid&&ext_arready接受时，不能释放相同RAW槽；仍保持已呈现AR的stall稳定及必须drain后释放。覆盖两camera、两slot和status0/1/2的竞争以及迟到R/LOCK/reset。不能只改统计、解除保护或篡改status2语义。
4. 补F03真实重叠TB：对实际reader的已接受AR至最后有效R/排空窗口记录新SOF、完整pub及内容/释放；DDR模型允许读写并发且可有界延迟read，生产checked CSI/writer/CRC不替换。每路≥2个新SOF在实际读窗口到达，每路至少1个其他槽完整发布发生于某次实际读窗口；有保护满/丢整帧的明确计数/图案，不允许旧内容覆盖；此后至少2对good完整读回释放。记录实际时间/地址/身份，不能只测内部busy或插入源后等待读完再发下一对。
5. 运行以下有限局部回归、完成差异/影响/证据复用提案及lessons，停止修改和所有活动，冻结 `r1/manifest-r1.json`；只有必要结果齐备才ready_for_test，否则原样blocked。

## 复测集合与复用

必须在修正输入上复测：F01/F02矩阵（原独立tb_tester_edges的两个失败触发必须保留）；F03 overlap；正常six-pair/CRC/槽复用；case10/11/12/13/14/15覆盖CRC失败、两种AR时序abort/drain、缺R LOCK/reset、饱和/模式拒绝、旧epoch；contract同拍双pub/释放路由；legacy默认关闭；B释放误送A变异仍被拒绝。建议合并合法参数矩阵为单个有界TB进程，不以拆case改名绕失败命令次数。

对原综合测试者，原tb_tester_edges已真实失败1次，修正后同失败场景**仅余一次**有新证据的复跑（累计上限2）；本文件不新增第三次。开发者局部验证按其自身实际失败命令历史另账，不冒充独立验收或重置测试者次数。若该触发在本轮仍FAIL，保留结果直接回规划，不自动再改再跑此场景。其他命令/场景同首次+最多1次有新证据纠正重试，跨派发保留稳定根因计数；不得把新路径视作新额度。

未改变的I2C配置器/表/ui_i2c/同步控制/PHY桩及各自特定错误引脚序列，可以由**原综合测试者**根据新manifest逐文件SHA、参数/时钟/刺激与改动影响明确复用旧证据；开发只能提案，不可自判免测。只要影响不清楚或相关连接变动就须在本窗口内补必要测试，缺额度blocked。所有改变的描述符/AR/所有权/读回/持续到达证据必须新跑，不能拼旧PASS。独立数据oracle继续核真实R字节与身份/CRC/尾零，新增F03必须有真实重叠hit。

## round1有限预算（低于原每次派发上限）

开发本次≤45工具调用/60分钟、compile≤3、case进程≤14；测试本次≤30工具调用/45分钟、compile≤2、case进程≤14。本次调用/时间从真实续接开始记，开发绝对截止在dispatch冻结为本次派发时刻+60分钟；测试绝对截止从其真实续接开始+45分钟并登记，不沿用/伪改round0已结束窗口。原T10的19:55:19.126669截止和faults累计3规则完全独立且不变。

同时记历史累计：开发compile4+本次(最多3)=最多7、case19+本次(最多14)=最多33；测试保守calls44+本次(最多30)=最多74、compile2+本次(最多2)=最多4、case20+本次(最多14)=最多34。旧总工具调用缺值不得发明；新轮单独实记并保留unknown历史字段。上限属于原计划允许的真实修复派发，不是重置旧失败尝试或允许额外round0用例。

读搜60s，局部编译/静态/单case实际300s及TB cycle watchdog；单问题最多3轮有目标读取，同失败命令原计数保留、连续2次无进展/任一额度到限/工具/权限/API错误即blocked，禁止自动扩预算。只安全终止自己拥有进程；yield不是deadline。TD/硬件/盘符/COM/RK/bit/CWC/下载/Flash/外部消息/Git/批量删除=0。

## 写域、冻结、返回

开发只写 `T08.dual-local-closure/r1/**`；原r0 candidate/脚本/TB/manifest/报告全部只读。sources.f可引用原未变源（逐SHA绑定）并把变更模块指向r1 overlay，或在r1内复制源集，两者均须唯一模块定义和准确source-map。不得运行旧generator覆盖冻结根目录。

测试只写 `test-reports/T08.dual-local-closure/r1/**` 和 `test-reports/T08.dual-local-closure-r1-integrated.md`；复用读取旧自身证据，任何新增/变异不覆盖旧文件；使用r1真实manifest、前后漂移检查与r1复用决策。G0/G1仍必要，G2/3/4仍not_run/awaiting_hardware，不能用硬件缺项为这两RTL缺陷开脱或降低门槛。

开发ready_for_test后主followup真实原tester；无论PASS/FAIL/blocked都交原规划读取报告及计数再决定，不自动回开发更改次数。开发返回必须有停止声明、manifest、三维retest清单、影响/复用提案、实际本次/累计计数。保留F01/F02原错误证据与r0 FAIL。回退仍暂不采用新run隔离源，无生产候选改变。若宿主原ID真实失效，交规划文件恢复，不新建替代来扩预算。
