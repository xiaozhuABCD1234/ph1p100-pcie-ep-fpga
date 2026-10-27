from pathlib import Path
import json,hashlib,re,datetime,collections
E=Path(__file__).parent;D=E.parent.parent/'T08.dual-local-closure';R=D.parent;M=D/'manifest-r0.json';REPORT=R/'test-reports/T08.dual-local-closure-r0-integrated.md'
def save(name,o):(E/name).write_text(json.dumps(o,indent=2,ensure_ascii=False),encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
suite=json.loads((E/'suite-results.json').read_text());oracle=json.loads((E/'independent-oracle-results.json').read_text());before=json.loads((E/'freeze-before.json').read_text());after=json.loads((E/'freeze-after.json').read_text());neg=json.loads((E/'negative-result.json').read_text());edge=json.loads((E/'tester-edges/sim-result.json').read_text())
assert len(suite)==18 and all(x['sim_pass'] and not x['timeout'] and x['exit_code']==0 for x in suite)
assert len(oracle)==17 and all(x['pass_'] for x in oracle)
assert before['manifest_sha256']==after['manifest_sha256']==sha(M) and not before['mismatches'] and not after['mismatches']
assert neg['negative_rejected'] and not edge['sim_pass']
commands=[]
for p in sorted(E.rglob('*.command.json')):
 x=json.loads(p.read_text());x['record_path']=str(p);commands.append(x)
save('command-inventory.json',commands)
# All reads and releases were independently matched; characterize the missing
# overlap coverage using the recorded actual AXI handshakes, without simulating.
overlap=[]
for x in oracle:
 if not x['label'].startswith('case'):continue
 pubs=[v.split() for v in (E/x['label']/'events.log').read_text().splitlines() if v.startswith('CLPUB')]
 for p in pubs:
  for f in x['frames']:
   if f['epoch']==int(p[1]) and f['first_r']<int(p[2])<f['last_r']:overlap.append(dict(case=x['label'],publication=p,reading=f))
save('overlap-coverage.json',dict(publications_during_actual_R_spans=len(overlap),normal_publications_during_actual_R_spans=sum(x['case']=='case00' for x in overlap),records=overlap,source_fact='pair_frame waits 6000 system clocks after injecting a pair; three_good also checks both reads completed before next pair',verdict='required continuing new arrivals while read active not independently evidenced'))
findings='''# T08 round0 fixes and required retest

F01 — descriptor changes during stall. In dual_local_closure.v lines70–96, ai/bi are recomputed by slot priority. Publish A slot1 (seq101, base00900000), leave a_desc_ready=0, then publish slot0(seq102, base00100000). Without a ready handshake, observed a_desc_slot/seq/base change to slot0/102/00100000. The four-slot mailbox has retained both objects, but its ready/valid output contract is violated. Hold the selected identity until its transfer; exercise both cameras and slot-order permutations.

F02 — accepted external read and release in one cycle. In mode2, after slotA0 seq201 is transferred, drive valid legal ext AR and matching rel_status2 on the same rising edge, DDR arready=0. ext_arready=1 accepts the read into the skid, but release checks old ar_pending/outstanding and frees the slot: held=0, a_release=1, ar_pending=1. A writer can reuse memory while the consumer still owns an accepted request. Release/status0/1/2 and AR arbitration must include same-cycle events for the applicable slot; test all status/camera/slot races and delayed R/LOCK/reset paths. This is an actual frozen-DUT defect, not a bad-R/illegal-address stimulus.

F03 — required overlap evidence absent. Normal run has 0 publications while an actual read span is active. The production TB injects a pair, waits6000 cycles, and requires both reads complete before injecting the next pair. Existing results prove six pairs, repeated slot reuse and fault recovery; they do not prove continued arrival during an active read. Add explicit active-reader+new-frame input hit markers and content/ownership checks, with complete-frame acceptance/drop and at least two later successful pairs. The original testcase/process budget20/20 and compile2/2 is exhausted; planner must supply an authorized next dispatch before further execution.

Reproduction uses the already compiled build-baseline and tb_tester_edges, whose source and raw log remain in this directory. No extra round0 simulation is authorized. After an actual fix and new frozen manifest, the original tester must recompile and rerun F01/F02, all impacted mode2 handshakes and local drain/release ownership, F03 overlap, simultaneous publication, saturation/mode rejection, normal pin-I2C/CRC lifecycle and default-disabled regression. Keep B-to-A release mutation rejected. Do not reuse changed-module evidence without a new explicit mapping.
'''
(E/'fix-and-retest.md').write_text(findings,encoding='utf-8')
reuse=dict(round=0,input_status='same',manifest_path=str(M),manifest_sha256=sha(M),reuse='Only this tester own completed baseline logs are reused after quota interruption; no developer or historical PASS used as current acceptance',unaffected_source_files_all_hashes_same=True,negative_fixture='deliberately mutated test-only source, never part of the frozen candidate',future_reuse='Undecided until actual repair manifest; all impacted interface/ownership cases require retest',evidence_paths=[str(E/'freeze-before.json'),str(E/'freeze-after.json'),str(E/'planning-source-audit.json'),str(E/'independent-oracle-results.json')])
save('reuse-decision-r0.json',reuse)
problem=dict(problem_id='T08.dual-local-closure:LIMIT_REACHED:active-read-arrival-coverage',reason_code='LIMIT_REACHED',new_information=True,evidence_path=str(E/'overlap-coverage.json'),requested_action='Planner to account for F01/F02 real fixes and supply bounded next dispatch for required active-read/new-frame coverage; no extra round0 compile or simulation',resume_input_path=str(E/'fix-and-retest.md'))
blocked=[dict(category='LIMIT_REACHED',status='blocked',missing='required active-read/new-frame overlap evidence; compile2/2 and case20/20 used',recovery_path=str(E/'fix-and-retest.md'),problem=problem)]
checks=['F01 held descriptor stability for A/B and both slot-order permutations','F02 same-cycle AR acceptance vs status0/1/2 release and ownership','F03 new complete frames while real reader active, explicit hit and later recovery','all impacted normal/saturation/drain/LOCK/reset/stale identity cases','default-disabled real-top pin I2C/CRC regression and B-to-A negative control']
retest=dict(required_dimensions=['functional','engineering','system'],required_checks=checks,report_paths=[str(REPORT),str(E/'fix-and-retest.md')],input_status='same',reuse_decision_paths=[str(E/'reuse-decision-r0.json')])
counts=dict(functions_exec_calls_after_final_verification=19,native_tool_operations_after_final_verification=23,conservative_sum_after_final_verification=42,tool_limit=45,compiles=2,compile_limit=2,case_processes=20,case_limit=20,round=0,actual_repair_rounds=0,absolute_deadline_asia_shanghai='2026-10-25T19:57:00+08:00',quota_pause='Parent supplied resume01 says quota interrupted until19:41; no count or time reset',resumed_at_utc='2026-10-25T11:49:24Z',session_retrieval='One original exec session15982 retrieval returned Unknown process id; no retry, use persisted exact native command records and completed suite file',encoding_corrections='Two independent read/audit encoding issues each corrected once with new UnicodeDecodeError evidence; no compile/case retry')
save('execution-budget-tester-r0.json',counts)
dims={k:dict(applicable=True,result=v,G0='pass',G1=('fail' if k!='engineering' else 'pass'),G2='not_run',G3='not_run/awaiting_hardware',G4='not_run/awaiting_hardware') for k,v in [('functional','fail'),('engineering','pass'),('system','fail')]}
# The engineering pass covers actual compile/hash/address/CDC structure checks;
# functional/system interface properties remain failed and cannot be hidden.
meta=dict(task_id='T08.dual-local-closure',dimension='integrated',dimension_results=dims,verdict='FAIL',report_path=str(REPORT),manifest_path=str(M),blocked=blocked,retest=retest,cumulative_counts=counts)
save('return-r0.json',meta)
case_desc=['正常六对、槽复用','末字节NACK/清理/重启','缺B/半A拒绝/重锁','DDR写期间共同reset','同步stop/restart及warmup','I2C已接受未响应时reset','受检mask位错误拒绝','非mask位变化允许','never-busy超时','busy-never-done超时','实际R载荷CRC损坏及drain','AR未握手时abort/保持/drain','已接AR后迟到R/abort/drain','永久缺R LOCK/共同reset恢复','两槽满丢整帧/模式切换拒绝','旧epoch释放拒绝']
lines=[]
for x in suite:
 lab=x['label'];desc=case_desc[x['case']] if lab.startswith('case') else ('双路同拍发布/转交/释放路由合同' if lab=='contract' else 'DUAL_LOCAL_EN=0原正常case')
 count=next((q.get('actual_read_frames',len(q.get('frames',[]))) for q in oracle if q['label']==lab),None)
 lines.append('|'+lab+'|'+desc+'|'+str(x['exit_code'])+' / '+str(round(x['elapsed_seconds'],2))+'s|'+str(count if count is not None else 'contract')+'|pass|')
width=[v for v in (E/'case00/vsim.log').read_text(errors='replace').splitlines() if '(vsim-3017)' in v]
report=f'''### 判定：FAIL

task_id: T08.dual-local-closure  
dimension: integrated  
round: 0（首次验收；未发生实际修复轮）  
实际工作树: D:\\fpga\\ph1p100  
候选: {D}\\candidate  
冻结manifest: {M}  
manifest SHA256: {sha(M)}  
报告生成UTC: {datetime.datetime.now(datetime.timezone.utc).isoformat()}

综合结论：18项冻结回归和独立数据检查通过，但测试者另写的有效边界TB复现F01/F02两项DUT接口缺陷，必需的在读期间持续来帧覆盖亦未成立，故不能通过G0/G1离线验收。一次综合测试覆盖三个维度，不声称三个独立测试视角。

|维度|事先适用范围|结果|G层|
|---|---|---|---|
|functional|真实双路checked CSI/writer、引脚I2C、实际DDR字节/CRC、恢复及描述符|fail：F01；回归数据正确；F03覆盖不足|G0源合同审查pass，G1 fail|
|engineering|实际源闭包、独立编译/精化、哈希、静态CDC/reset/地址、告警审查|pass（仅离线工程检查）|G0 pass；G1编译精化pass；不抵销功能失败|
|system|消费者互斥/所有权/释放、默认路径/隔离与回退|fail：F02释放后仍有已接受AR；F03缺覆盖|G0审查pass，G1 fail|

上述适用性由本run dev-plan.md、fpga-design-guide.md派发前冻结。必要门槛为Errors0、目标FAIL0、timeout0、mismatch0及各必需场景显式hit；F01/F02使目标FAIL0不满足。G2物理实现/最终STA/setup/hold/TNS/资源/物理CDC未授权，not_run；G3/G4真实曝光、板级恢复/稳定性/硬件吞吐not_run/awaiting_hardware；G5未排期。旧G2/G3/G4不复用。RK、PCIe承载、三算法共存和生产迁入为规划预定不适用。没有上板观察者、板窗或当前bit身份，未制造实测。

工具实际运行：Python3.11.5；ModelSim ALTERA STARTER EDITION vsim10.5b、vlog10.5b（2016.10）。版本原日志在 {E}\\python-version.log、vsim-version.log。工具SHA另见freeze-before/after。已独立验证121项原规划源文件全部匹配，候选相对旧生产派生源确有5项变化，71项source-list存在且实际进入编译，另6项仿真/测试源共77项。真实writer/checker/arbiter/checkedCSI/sync/ui_i2c定义均唯一；无stub替换这些DUT。vendor_env只替代PLL/PCIe环境/DDR行为，sensor_i2c仅SCL/SDA，MIPI宏只绕过PHY。

实际执行与原日志：tester_control.py prepare独立建立build-baseline/modelsim.ini和work，vlib/vlog各exit0，vlog Errors0/Warnings1；mutant独立build-mutant为第二次compile。sources.json记录实际77项文件及SHA。suite显式16生产case+2aux，并发最多2，各独立cwd/log/WLF，单case subprocess300s和TB cycle/time watchdog；无case重试。所有原生命令、cwd、PID、退出码、timeout及耗时在command-inventory.json及各*.command.json。文件非空、完成标记及Fatal/scoreboard均独立检查，不仅看exit0。

|case|实际场景|exit / elapsed|完整帧检查数|结果|
|---|---|---|---|---|
{chr(10).join(lines)}

数据判据：independent_oracle.py为测试者另写，不导入开发check_t08/r10f_oracle。按实际AXI R地址/握手时间重建4096B帧，核验128B头全部身份/几何/保留/未知时间、标准zlib.crc32、20B数学源图案、逆RAW10的16像素和零DMA尾；逐释放按epoch/camera/slot匹配已完成实际读，能发现释放路由错误、提前/重复释放，即使数据CRC自洽。I2C以冻结b10原表而非候选期望变量作判据，201初始化写、每路49随机读、独占同步后精确14笔角色写、受检位错误拒绝/非掩码变化放行及最终master NACK均有引脚/断言证据。实际R帧210份，其中case10两份为明确注入损坏并检查CRC不等，其余208份正确；默认关闭帧dump6份正确，共216份完整数据对象被检查。正常A/B各6，四槽分别至少重复使用2次。各故障后至少6对good，case4为12对。结果和逐帧证据在independent-oracle-results.json及每case tester-oracle.json。正常发布期间实际读跨度的重叠数0，不能把间歇六对外推成持续到达。

独立负对照：仅测试证据目录mutant_b_release_to_a.v把mode2完成B释放脉冲误送A，原候选不改。正确编译后tb_dual_contract在144ns以“CONTRACT_FAIL B release routes only to B”Fatal拒绝，Errors1，无CONTRACT_PASS；negative-result.json记录negative_rejected=true、mutation.json绑定两SHA。这证明对应路由判据会拒绝坏实现；变异不属于冻结DUT通过证据。注意ModelSim此调用遇Fatal仍最终exit0，故本报告按Fatal和标记判读，绝不以exit0洗成PASS。

F01（真实缺陷）：dual_local_closure.v:70–96的ai/bi按当前mailbox优先级组合选槽。测试者tb_tester_edges先发布A1/seq101/base00900000，ready持续0，再发布A0/seq102/base00100000；输出在无握手下变为slot0/seq102/base00100000，违反冻结合同stall保持所有字段。原断言日志：EDGE_FAIL stalled_descriptor_must_not_change_on_slot0_publication held=3 slot=0 seq=102 base=00100000。影响A/B同结构，两槽乱序/反压组合。

F02（真实缺陷）：mode2描述符A0/seq201移交后，同拍给合法ext_arvalid和匹配status2释放；DDR arready=0而ext_arready=1，外部请求已被接纳进skid。148行调度AR、157–164行释放检查旧ar_pending/outstanding，结果held=0、a_release=1、ar_pending=1，仍有待发送请求却已让writer可复用。原断言：EDGE_FAIL accepted_AR_must_prevent_status2_release_same_cycle held=0 ... releaseA=1 ar_pending=1。status2含义为未读，接口必须互斥/拒绝同拍竞争；刺激没有越界、错身份或坏DDR。tb_tester_edges在152ns以TESTER_EDGE_FAIL count2 Fatal结束，exit0但sim_pass=false。原日志及刺激源在tester-edges/vsim.log、tb_tester_edges.sv。不通过其他18正例掩盖。

F03（必需覆盖缺口）：正常脚本pair_frame注入后等待6000周期，three_good要求读回完成才进下一对。既有记录没有证明新帧持续输入与读回重叠，overlap-coverage.json明列实际发布/读跨度。冻结dev-plan的“在读时持续来帧”不能以旧证据或槽满测试替代。进一步case需原规划按累计预算给后续动作；round0 compile2/2、case20/20无余量，未再启动仿真。

工程静态证据：tester-static-review.json、tester-source-differences.json、planning-source-audit.json；b10 read_mask函数ASCII逻辑精确相同，模式表整文件SHA精确相同。new ownership/AXI均DHI时钟，共同DDR reset；writer async FIFO与sync_sof_mailbox/reset保留，sync观测停留既有50MHz域；没有异步多位重采样。物理CDC/最终实现资格没有证明。tester-default-boundary.json可执行枚举默认W1920/H1080：raw2592000/content2592128/dma2592768，每槽8MiB、29bit不溢出、四槽不重叠，所有read burst<=128beat且不跨4KiB；B高地址在小几何实际R中访问。小W8H2结果不代表全尺寸持续帧速。双1080p30紧密RAW需求155.52MB/s、写+读最低311.04MB/s；本轮不声称实时。

告警：编译仅继承pcie_ep_engine.v:127冗余数字vlog2600；生产精化73条为vsim3017三条与缺省未连接端口vsim3722七十条（未用输出/默认关闭扩展口等），详见tester-warning-audit.json。三条宽度告警原文：
{chr(10).join(width)}
新独立edge TB也有刻意未接的非观察输出，均不影响输入宽度或目标断言。没有多驱动错误、丢失真实目标模块或未解释目标端口类型；这些告警不抵销F01/F02。

输入漂移：freeze-before.json与freeze-after.json各检查500项（candidate/test input/tool及五规划文件），mismatch0；manifest SHA前后相同。测试只写本run test-reports任务目录及本报告，未改开发候选/旧证据/兄弟任务/生产/活动TD，未删除文件、未用盘符映射、未TD/硬件/下载/Flash/RK/外部消息。quota续接沿用原manifest/轮次/compile/case，复用仅本测试者已完成的当前同输入证据，详见reuse-decision-r0.json。一次原exec会话过期获取失败已保留说明且未重试，已有原生退出记录及suite18记录闭合。

累计预算（含下一次最终只读核验，若未发生应以其日志修正）：functions.exec19次、内部原生工具操作23次；保守二者合计42<=45。compile2/2；case20/20=生产16+原contract1+legacy1+tester_edges1+mutation1；实际修复轮0。绝对截止19:57上海不因quota延长。读搜在早期有限命令已完成后用subprocess60s包围；局部后处理300s。两次读取/静态脚本编码问题均凭新Unicode错误信息各只纠正一次，无编译或仿真重试。详细execution-budget-tester-r0.json。

阻塞只针对F03所需新增执行已达本轮限额；F01/F02是确定RTL失败。最小下一步、修复/复测清单在fix-and-retest.md，机器返回/retest在return-r0.json。输入状态same；将来修复后须新manifest并由原综合测试者判断影响及复用，不能拼输入PASS。回退为停止采用本隔离候选；生产及板级候选从未替换。准确恢复入口：$fpga-orchestrator 恢复：{R}；本轮目标：读取两包manifest和独立综合报告，按本轮原范围继续未完成离线闭环。
'''
REPORT.write_text(report,encoding='utf-8');print('REPORT_WRITTEN',REPORT);print('MANIFEST',sha(M));print('RETURN',E/'return-r0.json');print('UTC_NOW',datetime.datetime.now(datetime.timezone.utc).isoformat())
