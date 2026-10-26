import pathlib,json,sys,hashlib,datetime,re
sys.dont_write_bytecode=True
p=pathlib.Path(r'D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery\T10.a1-abort-cdc-fix');sys.path.insert(0,str(p));import run_abort
result=json.loads((p/'local-result.json').read_text());idx=json.loads((p/'corrected-dut-index.json').read_text());sha=run_abort.sha
idx.update(stopped_modifying=True,active_commands=0,changed_file_count_total_against_original=2)
(p/'corrected-dut-index.json').write_text(json.dumps(idx,indent=2))
rows=[]
for name in run_abort.CASES:
 a=[x for x in result['selected_matrix'] if x['name']==name];mx=max(x['stats']['recovery_elapsed'] for x in a)
 rows.append('|'+name+'|2/2|'+','.join(str(len(x['decoded'])) for x in a)+'|'+str(mx)+'|')
report='''# T10.a1-abort-cdc-fix round0 开发交付

状态 ready_for_test，仅为开发局部验证完成；综合验收由随后一个新独立测试者负责。runtime=Codex，开发者 /root/fpga_dev_abortcdc_221529。仅修改本包 candidate/camera_a1_uart_top.v；八RTL组合由 corrected-dut-index.json 完整冻结。原六模块与已通过exporter直接引用保护路径，七项SHA均保留。新top SHA：'''+sha(p/'candidate/camera_a1_uart_top.v')+'''

## 实现与可观察合同

摄像头域增加一个43bit holding token及有限 pending abort/drop/loss 状态。真实FIFO w_ready参与出队，stall时valid/data/sideband保持。crop_abort独立于crop_valid受理；首个不能放入holding的像素使整个丢弃区间失效，旧holding像素先送、abort后送，所有内容经过原真实异步FIFO。已提出的旧token不会被覆盖，abort payload为abort=1/last=0/sof=0/pixel=0。发生错误后只在abort真实接受之后的fresh crop_sof恢复，接受abort同拍的SOF及其余残帧均被丢弃。

同一丢弃区间内多次异常合并为一个abort事件；不把事件数声称为精确丢失帧数。目的域 raw_abort_events 对每个实际消费的abort加1并加到 o_st_errors，真实slot释放仍由原slot store的 st_dropped计数；未分配writer的abort仍有可观察错误事件。没有摄像头状态直接跨域，也没有改FIFO、crop、store、编码核、exporter或协议。

RAW会话保留至last被真实store接受；e_last仅进入skid时不再提前撤销raw_active。FIFO abort在组合接口层屏蔽store wr_valid/wr_begin，优先撤销skid/take/refill/last与pending admission，再发原域raw_abort释放WRITING slot。abort后至少一个周期阻止新SOF抢在store释放之前开始；孤立非SOF数据被丢弃。正常ready/reading槽及读/编码/导出路径保持。

保守故障策略允许取消已经完整捕获但last尚未提交的当前写会话：last-skid case先以真实DDR stall保留last，再以新相机帧的ROI前短行产生真实abort，明确要求旧未发布写会话被撤销。已发布/READING槽不受该abort撤销；未将crop/store替换为测试stub。

## 局部真实运行结果

每种case在cam周期14ns/A1周期5.333ns、相位1.7ns以及cam周期3.7ns/A1周期5.333ns、相位0.91ns各运行。clean W8/H2/FIFO_AW2与clean32及两种中写reset W32/H2/FIFO_AW4；其余W8/H2/FIFO_AW2。UART与A1同一net，UART_DIV4，ROI(4,2)、CAM_W=W+8/H8、PREP/PRED1、HB_DIV0。W32 RAW80B使用4个20B有效DDR字，实际压缩91B占3字；地址单位256bit word，RAW_BASE0/CMP_BASE131072。

|case|两时钟比例通过数|严格完整包数（slow,fast）|最后FE后最大A1周期|
|---|---|---|---|
'''+ '\n'.join(rows)+'''

完整矩阵的20项选择及每项control/stats/decoded在 local-result.json。四个good源seed均不同；reset后epoch1使用1100..1103，其余1000..1003。每项至少两帧且本次实际四个good全部完整导出，严格逐字节/源身份、四CRC、标准zlib EOF/unused_data/unconsumed_tail、零重复/旧epoch/尾垃圾；overflow允许先前完全收到的100/101前缀帧排空，任何发生源丢弃的帧不在合法源集合。

bad-frame两比例均观察crop_abort=1/crop_valid=0，源abort写入1、真实FIFO消费1、RAW abort1、实际store drop至少1，后续四good恢复。full-abort在A1钟暂停期间用真实相机数据填满FIFO，保留pending abort；恢复A1后token queue从真实FIFO写接受到读接受逐个比较，abort写/读各1且无丢失。fast比例还命中abort token在满FIFO保持1个cam周期。overflow在真实DDR stall下送8帧，实际满、真实丢beat、abort与错误计数均命中，释放后恢复。

pending-reset在真实满FIFO及pending abort同时存在时断言reset、重开A1时钟，检查holding/pending/skid/RAW所有权和统计清零，新epoch四包正确且没有旧abort。fresh SOF与abort真实写接受同拍两比例均恰好命中一次，碰撞seed2000整帧丢弃，下一fresh SOF恢复。last-skid两比例均命中e_last尚在skid、DDR未接收，abort撤销last、原WRITING slot真实drop1、坏会话零发布。

RAW/encoded reset均以外部AW/W已接受且尚未发布为严格前置，原trace保存精确cycle/计数/slot。DDR模型的内存、pending AR及held R不随DUT reset清空，reset仅门控新请求；本次reset命中时旧AR未完成状态没有命中，不声称覆盖这个额外边界。

## 有效负对照、纠正记录与输入版本

原top+已PASS exporter+原六项正确全量编译后，在真实短行路径命中 ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED：crop_abort有效但无FIFO abort接受，RAW半帧仍活动，真实drop0。证据 old/bad-frame-slow-retry。该目标断言在送恢复帧之前直接拒绝，避免其他旧握手缺陷抢先中断。没有用编译失败充反例，也没有把ModelSim exit0当通过。

保留两次环境定位失败：corrected/sof-abort-fast 首次没有对齐所需同拍事件；增加真实FIFO下一拍full判据后仅纠正重跑一次成功。old/bad-frame-slow 首次被旧top的valid stall变化断言先拒绝；将目标abort断言前移后仅纠正重跑一次。两者均非候选RTL修复，所有失败日志保留。首次准备git status的GBK解码失败一次，使用明确UTF8/errors=replace后纠正，未碰生产文件。

全量compile恰好2次：新候选八RTL及原top八RTL各一次，均Errors0/Warnings0。另有3次只编译TB的增量动作（相位对齐、旧目标断言前移的old/corrected各一次），没有任何编译后RTL修改。仿真精化保留原u_cmp_store漏接两个观察输出的3条告警，非控制接口，未屏蔽。

最后重新执行19项final TB矩阵，全部通过；fast SOF使用此前唯一成功纠正运行。test-input-versions保留initial/aligned实际源码，TB-version-binding.json证明aligned与final唯一差别在ifndef CORRECTED内，CORRECTED宏下展开程序完全相同。原top有效负对照与19项矩阵使用最终TB。独立测试者应从唯一manifest重新编译运行全部20项，不引用历史包PASS或开发工作库。

checker-negatives.json的17项实际负例全部拒绝：尾字节、重复包、截断、CRC有效旧epoch源、四CRC分别破坏、合法zlib拼接，以及8种故障的inject_hit删除。没有放宽恢复阈值或删除负对照。40次corrected实际仿真中39次局部通过、1次注入对齐miss；old共2次，其中最后1次目标有效拒绝。49条编译/仿真进程记录均保存完整argv/cwd/PID/实际秒数/退出码，所有进程已wait。

## 工程边界、保护与复测

保护检查189项加额外38项身份均零漂移：108规划输入、dispatch输入、原八RTL绑定、resume01与passed exporter冻结产物、原r0产物/manifest和已PASS manifest/index。七个受保护RTL无复制改写，新top之外没有RTL差异。见protection-before/after、candidate.diff及corrected-dut-index。所有新文件仅本包目录；无删除、共享盘符/他人进程操作、代理派生、生产/TD/板候选修改。TD/综合/route/bitgen/CWC/download/Flash=0。

每个编译/仿真都在启动前有subprocess真实300s上限和自有PID树终止措施，TB另有cycle和绝对时间watchdog；均未触发超时。最初小型读取/搜索缺少显式硬超时，实际各低于3秒，保留该过程偏差；后续子进程静态/工具查询明确60s控制，不把exec yield当超时。此报告不宣称已做实现级CDC/STA/资源或硬件资格。

开发局部G0/G1检查已运行，独立综合验收待进行。G2=not_run，G3/G4/G5=N/A沿planner-abort-cdc-fix的离线边界。唯一manifest-r0.json列全输入、工具、实际命令、测试源码版本和所有产物SHA，stopped_modifying=true / active_commands=0。

复测必须独立重建新top+passed exporter+原六项，并完整跑20项矩阵、真实abort/slot释放、holding/stall/reset/SOF/last优先级、原top有效拒绝及17个checker负例；不能拼旧恢复包成功结果。开发runner固定写HERE，测试者需要在自己的允许证据目录建立独立runner/库，使用manifest的RTL与TB/model绝对路径。通过后由原规划回绑并续原恢复开发resume02，本包不新开第五任务，不修改任务板/dispatch/旧manifest。

回退无需生产操作：原八输入及旧候选全部保持，保留本包全部失败与成功证据。详细可复用触发及修正在lessons-r0.md。
'''
(p/'dev-report-r0.md').write_text(report,encoding='utf-8')
(p/'lessons-r0.md').write_text('''# T10.a1-abort-cdc-fix lessons

- 相机无反压时，FIFO满不能只把valid OR abort；必须用真实w_ready保护已提出token，并把第一次丢beat变成有序、可保持的abort。控制与数据同队列，恢复从abort接受后的fresh SOF开始。
- out_last进入skid不等于DDR/store接受last。RAW会话必须持续到真实最后握手，abort组合门控wr_valid/wr_begin并撤销skid，才能避免store中abort与last写的顺序覆盖。
- 尚未分配writer的abort同样需要观察统计；用目的域实际消费事件计数，明确它是合并区间事件而非精确每帧计数。
- 同拍SOF/abort测试需要以真实FIFO下一拍full条件对齐，fast cam下不能假设目前room会持续到下一拍。保留第一次未命中日志，再作一次有新证据的TB纠正。
- 旧DUT可能有多个缺陷，负对照要尽早在目标条件断言，避免无关stall断言抢先拒绝而假充目标复现。完整编译与原始目标证据不可省。
- 最终输入需保留真实TB版本及宏展开等价性，局部开发通过只交独立综合测试，不提升G2/硬件资格。复现入口run_abort.py、TB-version-binding.json及local-result.json。
''',encoding='utf-8')
(p/'reuse-decision.json').write_text(json.dumps(dict(historical_package_PASS_reused=False,all_20_cases_run_on_exact_new_eight_RTL=True,final_TB_19_reruns=True,fast_sof_uses_one_successful_alignment_retry=True,corrected_preprocessed_program_equal=True,proof_path=str(p/'TB-version-binding.json'),independent_tester_must_rebuild_all_cases=True),indent=2))
print('REPORT_AND_LESSONS_WRITTEN',len(report))
