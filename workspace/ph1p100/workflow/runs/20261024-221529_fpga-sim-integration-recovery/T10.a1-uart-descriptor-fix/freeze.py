"""Final local audit and single immutable handoff. No simulations or rebuilds."""
import datetime,hashlib,json,pathlib,re,sys
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent;RUN=HERE.parent
sys.path.insert(0,str(HERE))
import check_descriptor,check_recovery
TASK='T10.a1-uart-descriptor-fix'
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def save(name,value):(HERE/name).write_text(json.dumps(value,indent=2,ensure_ascii=False),encoding='utf-8')
assert not (HERE/'manifest-r0.json').exists(),'already frozen'
assert HERE.resolve()==HERE and HERE.name==TASK
before=json.loads((HERE/'protected-before.json').read_text())['files']
after=[dict(path=x['path'],sha256=sha(x['path'])) for x in before]
assert after==before,'PROTECTED_DRIFT'
save('protected-after.json',dict(files=after,checked=len(after),drift=[]))
rtl=['a1_deflate_core.v','a1_frame_top.v','a1_raw_crop.v','a1_ddr_slot_store.v','a1_ddr_arb2.v','a1_uart_export.v','camera_a1_uart_top.v','capture_async_fifo.v']
original_map={x['path'].replace('\\','/').lower():x['sha256'] for x in before}
mapping=[]
for name in rtl:
    original=RUN/'inputs/a1-r5/src'/name
    candidate=HERE/'candidate'/name if name=='a1_uart_export.v' else original
    original_sha=original_map[str(original).replace('\\','/').lower()]
    assert sha(original)==original_sha
    mapping.append(dict(logical_name=name,path=str(candidate),sha256=sha(candidate),source_path=str(original),original_sha256=original_sha,changed=name=='a1_uart_export.v'))
assert len(mapping)==8 and sum(x['changed'] for x in mapping)==1
assert len(list((HERE/'candidate').iterdir()))==1
index=dict(task_id=TASK,round=0,purpose='isolated corrected simulation DUT; no production or hardware qualification',frozen=True,
           changed_file_count=1,unchanged_original_count=7,files=mapping,
           rtl_paths={x['logical_name']:x['path'] for x in mapping},source_manifest_path=str(RUN/'planning-input-manifest.json'))
save('corrected-dut-index.json',index)
results=[]
for case,mode in [('boundaries',3),('wrap',2)]:
    folder=HERE/'corrected'/case
    rechecked=check_descriptor.check(folder,mode)
    recorded=json.loads((folder/'result.json').read_text())
    assert rechecked['status']=='PASS' and recorded['status']=='PASS'
    results.append(dict(case=case,packet_count=len(rechecked['packets']),status='PASS',mismatch=0,evidence_path=str(folder/'result.json')))
full=check_recovery.check(HERE/'corrected/full-clean',0)
assert full['status']=='PASS' and len(full['decoded'])==full['stats']['exported']==full['stats']['recovered']==4
assert all(full['stats'][k]==0 for k in ['raw_drop','cmp_drop','geom','err','fifo_rejected','dup_words','old_r_count'])
results.append(dict(case='full-clean',packet_count=4,status='PASS',mismatch=0,evidence_path=str(HERE/'corrected/full-clean/result.json')))
stats=(HERE/'corrected/boundaries/stats.txt').read_text()
bins={int(k):int(v) for k,v in re.findall(r'COV bin=(\d+) hits=(\d+)',stats)}
assert all(bins[k]>0 for k in range(12) if k not in (1,3))
negatives=[]
for case,target in [('boundaries','QUEUE_COUNT_MISMATCH old=1 push=1 pop=1 expected=1 actual=0'),('wrap','DESCRIPTOR_ORDER_OR_X pop=3 expected_id=1003 actual_id=xxxxxxxx')]:
    folder=HERE/'old'/case;log=(folder/'console.log').read_text(errors='replace')
    result=json.loads((folder/'result.json').read_text())
    assert target in log and result['status']=='FAIL' and result['target_negative_detected']
    negatives.append(dict(case=case,compiled=True,rejected=True,target=target,evidence_path=str(folder/'console.log')))
compiles=[json.loads((HERE/k/'compile-result.json').read_text()) for k in ['old','corrected']]
assert all(x['status']=='PASS' for x in compiles)
commands=[]
for p in sorted(HERE.rglob('*.command.json')):
    record=json.loads(p.read_text());assert record['timeout_seconds']==300 and not record.get('timed_out',False)
    assert record['returncode']==0
    commands.append(dict(record_path=str(p),**record))
assert len(commands)==9 # vlib/vlog x2, old simulations x2, corrected simulations x3.
save('actual-commands.json',dict(commands=commands,active_commands=0,process_control='subprocess wait(timeout=300); terminate only owned PID tree on timeout; no timeout occurred'))
save('local-result.json',dict(task_id=TASK,round=0,status='LOCAL_PASS_PENDING_INDEPENDENT_TEST',cases=results,negative_controls=negatives,
    legal_transition_bins=bins,protected_inputs=dict(checked=108,drift=[]),G0='local_pass',G1='local_pass',G2='not_run',G3='not_applicable',G4='not_applicable',G5='not_applicable',active_commands=0))
save('execution-budget.json',dict(task_id=TASK,round=0,max_tool_calls=45,max_minutes=60,full_compiles_used=2,full_compiles_limit=2,
    simulations_used=dict(old_boundaries=1,old_wrap=1,corrected_boundaries=1,corrected_wrap=1,corrected_full_clean=1),
    actual_repair_rounds=0,failed_command_retries=0,search_rounds_for_defect=2,
    tool_call_accounting=dict(outer_functions_calls_including_final=18,nested_native_calls_including_final=20,combined_conservative_bound=38),
    read_deadline_seconds=60,compile_sim_deadline_seconds=300,timeout_events=0,
    execution_deviation='First four small read/status commands completed in 1.2-1.5s each but lacked an additional explicit 60s deadline wrapper; subsequent read/audit commands used owned PowerShell jobs with 60s limits. This is disclosed and not represented as deadline coverage of those initial reads.'))
save('tool-versions.json',dict(python=sys.version,modelsim='ModelSim Intel FPGA Edition 10.5b',executables=[str(pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')/(x+'.exe')) for x in ['vlib','vlog','vsim']],version_evidence_paths=[str(HERE/'old/vlog.log'),str(HERE/'corrected/vlog.log')]))
lessons='''# T10.a1-uart-descriptor-fix round0 lessons

- 两项队列的索引必须显式模2；第三次读写是必要负对照。旧版真实第三次出队读到 xxxxxxxx，不能仅测头两帧。
- 计数应由同一拍真实接受的 push/pop 集中更新。同拍两者都接受时占用保持；旧版第二个非阻塞赋值覆盖第一个，实际 1 变 0。
- admission 使用旧 count。满队列同拍出队也拒新描述符，st_err 递增；修复不偷偷更换容量策略。
- 队列复位测试先证明 active E_OPEN 且 queued=2，复位后检查索引/计数/状态/统计，再以不同ID与不同源字节验新 epoch。
- 必须把计数断言和实际串行字节解析结合。严格 zlib/四CRC/完整源字节/无重复/无尾垃圾共同约束，避免 CASE_PASS/exit0 掩盖数据错误。
- 复跑入口与实际 argv 在 actual-commands.json；旧反例编译成功，分别命中 QUEUE_COUNT_MISMATCH 和 DESCRIPTOR_ORDER_OR_X。综合测试者应在自己的写域独立建库，不复用开发库作为独立重建。
'''
(HERE/'lessons-r0.md').write_text(lessons,encoding='utf-8')
report='''# T10.a1-uart-descriptor-fix round0 开发交付

状态：ready_for_test。本报告只说明本地开发检查完成；正式综合判定由一个新的独立综合测试者给出。runtime=Codex，开发会话 /root/fpga_dev_descriptor_221529。授权入口为 dispatch-dq-fix-r0.json 与 planner-amendment-authorized-dq-fix.md。

## 实现与输入身份

唯一 RTL 候选为 candidate/a1_uart_export.v；candidate.diff 列出全部差异。dq_wr/dq_rd 改为1位并在接受时取反；dq_cnt保留2位；reset索引清零；accepted push=desc_push且旧count<2，accepted pop=旧estate IDLE且旧count非0；count按10加1、01减1、00/11保持集中更新。描述符顺序、CRC、帧格式、DDR、时钟、UART握手、编码核和两项容量策略保持。原8项均只读；corrected-dut-index.json由1项修正路径及7项原始SHA路径组成完整DUT，没有复制或修改另外7项RTL。

## 实际复现与局部验证

旧/新各完成一次全部8RTL、真实顶层、DDR模型及两个TB的编译，vlog各Errors0/Warnings0。共2次全量compile，未重试，达到本派发上限。

旧版 boundaries 真实同拍接受 push/pop，目标断言报 old=1 push=1 pop=1 expected=1 actual=0。旧版 wrap 实际第3次出队，目标断言报 expected_id=1003 actual_id=xxxxxxxx。两例均已正确编译、进入真实DUT执行；不是用编译失败作反例。日志各Errors1为预期目标Fatal，ModelSim进程退出0不作为负例判据。

修正版 boundaries：10类合法(old_count,request,pop)组合均有实际hits；两类count0 pop=1不可能组合明确排除。覆盖空/单项/满、单项同拍push/pop、满拒收、full+pop拒收并st_err加1、满队列无push出队。输出1001/1002/1003/1006四包；拒收1004/1005均不输出；queued reset前真实active E_OPEN且queued=2，reset索引/占用/状态/统计清零，已接受未导出的7001/7002/7003被撤销；新epoch只输出2001/2002。共6完整包，严格独立字节检查PASS/mismatch0。

修正版 wrap：真实导出模块顺序输出1001..1012共12个不同ID，经历多次读写回绕；随后重复queued reset并完整输出新epoch的2001/2002。共14包，严格zlib、四CRC、源字节、无X、顺序、零重复、零尾垃圾全部通过。单模块fixture为Python标准zlib生成的20字节RAW/profile0 payload；存储侧由独立fixture队列提供ID/长度和数据，期望不读取DUT描述符内容。

修正版 full-clean：真实camera_a1_uart_top、7项原始RTL及唯一修正导出器实际精化/执行，W8/H2、UART_DIV4、FIFO_AW2、HB_DIV0；camera/A1异相时钟经真实CDC FIFO，UART=A1符合原合同。4个good输入种子1000..1003全部完整输出ID1..4，292B；cap/enc/raw_pub/exported均4，raw/cmp drop/geom/err/FIFO reject/duplicate/old-response均0。原checker的最低2包门槛在本包runner额外强化为精确4包，同时TB等待与完成断言也强化为4包。四个73B包均独立严格zlib/四CRC/RAW像素逐字节通过。

完整管道保留3条原有精化告警：u_cmp_store漏接仅观察输出st_read_words/st_dup_words（一条端口数、两条漏端口）。原7RTL受保护，未屏蔽告警；相关顶层接线无修改。单模块两正例Errors0/Warnings0；full-clean Errors0/Warnings3有上述固定解释。无目标端口、位宽或时钟新告警。

## 工程、隔离与限制

108项规划保护输入before/after逐项SHA一致，漂移0。所有新增文件和工具产物均在本任务目录；不改生产/upstream/fpga/tools、原inputs、其他任务/旧run、docs junction、TD/板候选或共享盘符；无删除、消息或其他进程操作。模型真实成对AW/W握手、周期stall及延迟AR/R响应，DUT reset只门控新请求而不清DDR模型内存/已接受响应；本包full-top仅执行clean，原恢复包的故障case不在本包冒充覆盖。

各编译/仿真实际argv、cwd、拥有PID、退出码、耗时与300s deadline见actual-commands.json及原*.command.json；TB同时有cycle watchdog。库/INI/run.do/WLF/日志均独占；全部命令已wait，无后台活动、超时或杀进程。最初4次小读取/状态命令实际各约1.2–1.5s但未另包60s deadline，这是已披露执行偏差；后续读取审查使用拥有PowerShell Job的60s限制，不将yield时间冒充deadline。

G0/G1仅为本地仿真资格已具备，等待独立综合测试；G2=not_run，G3/G4/G5按规划为not_applicable。TD/综合/route/bitgen/CWC/download/Flash均0。本结果不证明可上板/生产时序或父恢复任务通过。没有扩大为第二RTL/协议/容量修复。

## 冻结、复测和回退

唯一manifest-r0.json列出真实RTL/模型/TB/checker/fixtures/runner/参数/工具与实际证据SHA；corrected-dut-index.json给出恢复包所需完整8RTL映射。冻结最后动作由freeze.py执行并自校验，之后停止修改与所有命令，active_commands=0。freeze-verification.json绑定manifest SHA。retest清单在relay-metadata.json；独立测试须自行建库、重跑所有队列正反例与四帧clean，核对保护输入。测试者不能向本开发目录写入。

回退入口是原只读inputs/a1-r5/src及本run原dispatch；原生产/板候选未改变，保留全部正反例与产物，无清理删除。若未来迁入生产，应另做完整G2/CDC/资源/候选绑定及硬件资格。后续恢复包由原规划保留历史计数并以changed输入恢复原真实开发者。
'''
(HERE/'dev-report-r0.md').write_text(report,encoding='utf-8')
readme='''# 冻结输入复现说明

所有路径由corrected-dut-index.json和manifest-r0.json给出；生产文件与原8项输入不可修改。查看actual-commands.json得到每次真实argv/cwd/退出码/耗时。旧版与修正版各编译一次，旧版两例、修正版三例各运行一次，无重试。

独立综合测试者在自己允许的证据目录建立新的modelsim.ini、work库、run.do、WLF和所有输出文件。以vlog -sv -modelsimini <测试者INI> -work work编译corrected-dut-index中的8路径，加冻结ddr_recovery_model.sv、tb_full_clean.sv和tb_descriptor.sv；其余参数照实际argv，仅重定向所有输出路径与INI/work库。负对照独立建旧库，以原inputs/a1-r5/src/a1_uart_export.v替换唯一修正项，其余7项路径不变。

tb_descriptor MODE3运行队列边界，MODE2运行12个连续ID与queued reset；DESCS/PAYLOADS指向冻结fixtures，OUT/TRACE/STAT只指测试者目录。两正例须DESCRIPTOR_PASS/mismatch0、Errors0，独立字节核对全部6/14包。旧MODE3须命中QUEUE_COUNT_MISMATCH，旧MODE2须命中第3次DESCRIPTOR_ORDER_OR_X，均不得以编译失败替代。

tb_full_clean参数W8/H2/MAX_CYCLES1500000、CASE0，须4个完整正确包/292B及清零错误计数。保留真实延迟DDR模型和同钟UART合同。原3条仅观察端口告警已在开发报告解释。可直接调用冻结check_descriptor.check(<测试者case目录>,mode)及check_recovery.check(<测试者full目录>,0)；后者还必须独立强化为4包/4 exported/4 recovered及错误计数0。

准备/构造/冻结脚本为制作审计来源，已执行且开发目录已冻结，不要再次运行以覆盖开发产物；run_descriptor.py也禁止重复同kind编译/同case写入。独立测试须使用测试者自己的新命令/包装，不复用开发库声称独立重建。
'''
(HERE/'REPRODUCE.md').write_text(readme,encoding='utf-8')
inputs=[pathlib.Path(x['path']) for x in mapping]+[HERE/n for n in ['tb_descriptor.sv','tb_full_clean.sv','ddr_recovery_model.sv','check_descriptor.py','check_recovery.py','run_descriptor.py','descriptors.hex','payloads.hex','fixtures.json','corrected-dut-index.json']]
inputs += [RUN/'inputs/a1-r5/checker/a1_pattern.py',RUN/'planning-input-manifest.json',RUN/'planner-amendment-authorized-dq-fix.md',RUN/'dispatch-dq-fix-r0.json']
inputs += [HERE/k/n for k in ['old','corrected'] for n in ['modelsim.ini','run.do']]
protected=[pathlib.Path(x['path']) for x in before]
artifacts=[p for p in HERE.rglob('*') if p.is_file() and 'lib' not in p.relative_to(HERE).parts and p.suffix.lower()!='.wlf' and p.name not in ['manifest-r0.json','freeze-verification.json','relay-metadata.json']]
files=sorted(set(inputs+protected+artifacts),key=lambda p:str(p).lower())
entries=[dict(path=str(p),sha256=sha(p),bytes=p.stat().st_size,role='dut' if p in [pathlib.Path(x['path']) for x in mapping] else ('protected_input' if p in protected else 'test_input_or_evidence')) for p in files]
manifest=dict(task_id=TASK,round=0,run_id=RUN.name,runtime='Codex',developer_id='/root/fpga_dev_descriptor_221529',frozen=True,stopped_modifying=True,active_commands=0,
    created_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),corrected_dut_index_path=str(HERE/'corrected-dut-index.json'),files=entries,
    parameters=dict(standalone=dict(W=8,H=2,UART_DIV=4,HB_DIV=0,fixture_raw_bytes=20,profile=0),full_top=dict(W=8,H=2,UART_DIV=4,FIFO_AW=2,HB_DIV=0,CAM_W=16,CAM_H=8,ROI_X=4,ROI_Y=2,camera_clock_period_ns=5.333,a1_clock_period_ns=5.333,a1_phase_ns=1.7,uart_clock='same net as clk_a1',profile=3)),
    libraries=dict(old=str(HERE/'old/lib'),corrected=str(HERE/'corrected/lib')),G0='local_pass_pending_independent_test',G1='local_pass_pending_independent_test',G2='not_run',G3='not_applicable',G4='not_applicable',G5='not_applicable',
    excludes=dict(compiled_work_libraries='derived artifacts; independent tester must rebuild',wlf='optional derived waveforms',self='self hash stored in freeze-verification.json',post_freeze_metadata=['freeze-verification.json','relay-metadata.json']))
save('manifest-r0.json',manifest)
manifest_sha=sha(HERE/'manifest-r0.json')
for x in entries:assert sha(x['path'])==x['sha256'],x['path']
assert after==[dict(path=x['path'],sha256=sha(x['path'])) for x in before]
retest=dict(required_dimensions=['integrated'],required_checks=[
 'independent full rebuild with one corrected RTL and seven original SHA paths; narrow queue-only diff',
 '10 legal count/request/pop transitions including simultaneous accepted push/pop and both full-pop admission cases',
 'full rejection st_err increment and accepted FIFO descriptor ordering',
 'real exporter >=12 unique IDs across pointer wraps plus queued reset/new epoch; strict source bytes/zlib/four CRC/no X/no duplicates/no tail',
 'real camera_a1_uart_top >=4 fully correct clean frames; zero error/drop/duplicate/old-response counts',
 'compiled old-DUT target negatives for simultaneous count and third-descriptor X',
 'before/after protected input and manifest SHA drift0; timeout/model/clock isolation audit'],
 report_paths=[str(HERE/'dev-report-r0.md'),str(HERE/'local-result.json')],input_status='changed',reuse_decision_paths=[str(HERE/'dev-report-r0.md'),str(HERE/'corrected-dut-index.json')])
metadata=dict(task_ids=[TASK],status='ready_for_test',stopped_modifying=True,active_commands=0,
 artifact_paths=[str(HERE/n) for n in ['dev-report-r0.md','local-result.json','candidate.diff','actual-commands.json','execution-budget.json','protected-before.json','protected-after.json','REPRODUCE.md','freeze-verification.json','relay-metadata.json']],
 manifest_path=str(HERE/'manifest-r0.json'),manifest_sha256=manifest_sha,test_input_paths=[str(p) for p in inputs],lessons_path=str(HERE/'lessons-r0.md'),blocked=None,retest=retest,corrected_dut_index_path=str(HERE/'corrected-dut-index.json'))
save('relay-metadata.json',metadata)
save('freeze-verification.json',dict(task_id=TASK,manifest_path=str(HERE/'manifest-r0.json'),manifest_sha256=manifest_sha,manifest_files_checked=len(entries),manifest_drift=[],protected_files_checked=len(before),protected_drift=[],changed_rtl_files=1,unchanged_original_rtl_files=7,local_checks_reparsed=True,stopped_modifying=True,active_commands=0,notes='All spawned subprocesses were waited before final audit; after this finalizer exits no further commands or modifications are authorized by this developer handoff.'))
print(json.dumps(dict(status='ready_for_test',manifest_sha256=manifest_sha,manifest_files=len(entries),protected_checked=108,changed_rtl=1,unchanged_rtl=7,active_commands=0),ensure_ascii=False))
