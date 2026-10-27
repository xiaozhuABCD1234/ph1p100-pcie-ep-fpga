"""Final planner evidence/record closure only. Never launches compiler/simulator."""
from pathlib import Path
import json,hashlib,datetime,re,copy,os,msvcrt
ROOT=Path(r'D:\fpga\ph1p100');R=ROOT/'workflow/runs/20261025-180900_fpga-dual-offline-closure'
E08=R/'test-reports/T08.dual-local-closure/r1/integrated-mode-fix02';E10=R/'test-reports/T10.dual-aplus-scheduler/r0';S10=E10/'supplement02'
M08=R/'T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json';M10=R/'T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json'
P08=R/'test-reports/T08.dual-local-closure-r1-integrated.md';P10=S10/'T10.dual-aplus-scheduler-r0-integrated.md'
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(p,x):
 p=Path(p)
 with p.open('x',encoding='utf-8',newline='\n') as f:json.dump(x,f,ensure_ascii=False,indent=2);f.write('\n')
def ref(p):return {'path':str(p),'sha256':sha(p),'bytes':Path(p).stat().st_size}
def verify(xs):
 out=[]
 for x in xs:
  p=Path(x['path']);h=sha(p);assert h==x['sha256'],str(p);out.append(ref(p))
 return out
def rel(p):return Path(p).relative_to(ROOT).as_posix()
stamp=datetime.datetime.now(datetime.timezone.utc).isoformat()
m08=read(M08);m10=read(M10)
assert sha(M08)=='38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3'
assert sha(M10)=='5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b'
b08=verify(m08['files']+m08['input_references']+m08['tools']);assert len(b08)==314
b10=verify(m10['files']+m10['static_outputs']+m10['tools']);assert len(b10)==122
cp08=verify(read(E08/'compiled-sources.json'));assert len(cp08)==81
c10=read(S10/'canonical-report.json');fv10=read(S10/'final-verification.json')
assert c10['verdict']==fv10['verdict']=='PASS' and c10['current_report_sha256']==fv10['report_sha256']==sha(P10)
assert sha(P10)=='ae758aa13e9eebb9df1b7922a23eec8d5c8aee0d53d316d63447d4e7b1e309dc'
assert sha(P08)==read(E08/'final-verification-r1.json')['report_sha256']=='71ef63293bd253182ad23f04ac8889a29e1d7be8bc0a7cc4869dc12bb0e472aa'
assert P08.read_text(encoding='utf-8').splitlines()[0]==P10.read_text(encoding='utf-8').splitlines()[0]=='### 判定：PASS'
assert c10['formal_round']==0 and c10['post_acceptance_repairs']==0
historical_fails=verify(c10['historical_FAILs']);verify(c10['historical_indexes_immutable'])
T08r0=R/'test-reports/T08.dual-local-closure-r0-integrated.md';assert sha(T08r0)=='2bddce8c19cd71727609eaee04bfedc141d280f0b87b55fccc837d183aa86fa6'
private10=read(S10/'private-input-manifest.json');private_verified=verify(private10['inputs']);case_evidence=verify(private10['case_evidence']);cp10=verify(read(S10/'compiled-source.json'));assert len(cp10)==4
ix=read(S10/'same-input-evidence-index.json');assert ix['total_strict_decoded_frames']==130 and ix['negative_controls']==2 and ix['no_original_suite_rerun']
source_provenance=[]
for bundle in ix['source_binding']:
 for x in bundle['bindings']:
  assert sha(x['retained_exact_bytes'])==x['sha256'];source_provenance.append(x)
wire=[];old_passes=[]
for q in sorted(E10.glob('*/result.json')):
 result=read(q)
 if result['status']!='pass':continue
 old_passes.append({'name':result['name'],'decoded_frames':result['decoded_frames'],'receipt':ref(q)})
 oracle=read(q.parent/'independent-oracle.json');assert oracle['eof'] and oracle['unused_data']==oracle['unconsumed_tail']==oracle['data_mismatch']==0
 for f in oracle['frames']:
  p=q.parent/f"c{f['camera']}_q{f['seq']}.zlib";assert sha(p)==f['wire_sha256'];wire.append(ref(p))
assert len(old_passes)==16 and len(wire)==122
new_oracle=read(S10/'matrix/independent-oracle.json');assert new_oracle['eof'] and new_oracle['unused_data']==new_oracle['unconsumed_tail']==new_oracle['data_mismatch']==0 and len(new_oracle['frames'])==8
for f in new_oracle['frames']:
 p=S10/'matrix'/f"c{f['camera']}_q{f['seq']}.zlib";assert sha(p)==f['wire_sha256'];wire.append(ref(p))
assert len(wire)==130
edge=read(S10/'matrix/independent-edge-audit.json');assert edge['status']=='pass' and edge['no_adjacent_cycle_substitution'] and edge['no_force_internal_state'] and len(edge['rows'])==4
seen=set()
for row in edge['rows']:
 a=row['accepted_descriptor'];v=row['release'];ri=v['camera']*2+v['slot'];di=a['camera']*2+a['slot'];seen.add(ri)
 assert a['cycle']==v['cycle']==row['same_physical_cycle'] and ri!=di
 assert row['external_ownership_after']==((row['external_ownership_before']&~(1<<ri))|(1<<di))
 assert a['epoch']==v['epoch']==2 and a['session']==v['session']==0x20261025 and v['status']==0
 assert row['closed']['owned']==row['closed']['ackpending']==0
assert seen=={0,1,2,3}
stat=read(S10/'static-check.json');assert stat['non_whitespace_tokens_except_declaration_unchanged'] and stat['one_declaration'] and stat['compile_retry_attempt']==2
tbold=(E10/'supplement01/tb_same_edge.sv').read_text(encoding='utf-8');tbnew=(S10/'tb_same_edge.sv').read_text(encoding='utf-8')
decl=r'reg\s+same_edge_manual\s*=\s*1\s*;'
assert len(re.findall(decl,tbold))==len(re.findall(decl,tbnew))==1
assert re.sub(r'\s+','',re.sub(decl,'',tbold))==re.sub(r'\s+','',re.sub(decl,'',tbnew))
assert tbnew.index('reg same_edge_manual=1;')<tbnew.index('if(!same_edge_manual)')
for name in ['helper.py','run_supplement.py']:assert sha(S10/name)==sha(E10/'supplement01'/name)
commands=[json.loads(x) for x in (S10/'commands.jsonl').read_text(encoding='utf-8').splitlines() if x.strip()]
assert sum(Path(x['argv'][0]).name.lower()=='vlog.exe' for x in commands)==1 and sum(Path(x['argv'][0]).name.lower()=='vsim.exe' for x in commands)==1
assert all(x['exit_code']==0 for x in commands)
res=read(S10/'matrix/result.json');assert res['status']=='pass' and res['decoded_frames']==8 and res['same_edge_hits']==4
assert 'Errors: 0, Warnings: 0' in (S10/'compile.log').read_text(encoding='utf-8')
console=(S10/'matrix/console.log').read_text(encoding='utf-8');assert 'TB_DONE' in console and 'ASSERT_FAIL' not in console and '** Fatal' not in console and console.count('HIT DESCRIPTOR_RELEASE_SAME_EDGE row=')==4
ac08=read(E08/'execution-accounting-r1.json');ac10=read(S10/'execution-accounting.json');dev10=read(M10.parent/'execution-accounting.json')
assert ac10['counts']['cumulative']=={'calls':69,'compiles':4,'cases':20} and ac10['counts']['stopped_modifying'] and ac10['counts']['active_commands']==0
assert ac08['stopped_modifying'] and ac08['active_commands']==0
roles=read(R/'role-ids.json');assert roles['tasks']['T10.dual-aplus-scheduler']['tester']=='/root/fpga_tester_dual_scheduler_180900'
binding={'run_id':R.name,'status':'offline_G0_G1_finished','merged_system_tested':False,'current_candidates':[
 {'task_id':'T08.dual-local-closure','manifest':ref(M08),'integrated_report':ref(P08),'round':1,'actual_post_acceptance_repairs':1,'verdict':'PASS','dimensions':{'functional':'pass','engineering':'pass','system':'pass'},'G0':'pass','G1':'pass','G2':'not_run','G3_G4':'not_run/awaiting_hardware','roles':roles['tasks']['T08.dual-local-closure'],'historical_FAILs':[ref(T08r0)]},
 {'task_id':'T10.dual-aplus-scheduler','manifest':ref(M10),'integrated_report':ref(P10),'canonical_report_index':ref(S10/'canonical-report.json'),'round':0,'actual_post_acceptance_repairs':0,'verdict':'PASS','dimensions':{'functional':'pass','engineering':'pass','system':'pass'},'G0':'pass','G1':'pass','G2':'not_run','G3_G4':'not_run/awaiting_hardware','roles':roles['tasks']['T10.dual-aplus-scheduler'],'historical_FAILs':historical_fails}],
 'production_adopted':False,'parent_hardware_done_by_this_run':False,'no_more_experiments_dispatched':True}
save(R/'candidate-binding-final.json',binding)
budget={'run_id':R.name,'formal_packages':2,'batch_size_per_task':1,'T08_tester':ac08,'T08_developer_known_cumulative':m08['actual_counts'],
 'T10_tester_original':read(E10/'execution-accounting-final.json'),'T10_tester_supplement01':read(E10/'supplement01/execution-accounting.json'),'T10_tester_final':ac10,'T10_developer':dev10,
 'immutable_limits_and_exhaustion':{'T08_original_edges':'2/2 used','T10_developer_faults':'3/3 used; no fourth','T10_fairness':'2 attempts; no third','T10_coverage_problem_supplement_opportunities':'2/2 resolved','T10_fixture_compile_root':'2/2 corrected retry resolved','T10_case_processes':'20/20 used'},
 'known_unknowns':['T10 complete historical developer calls and terminal capacity boundary remain unknown','T08 quota exact interruption receipt unavailable','T10 first original native receipt not recorded; conservative01:09 used'],
 'deviations_retained':['T08 developer original conservative101 over original60, cumulative142; not retrospectively compliant','Initial finite reads lacking external hard timeout remain in original records; later bounded controls do not erase history','Expired windows and static-closeout windows separately recorded; no experiment budget restored by static work'],
 'planner_final_experiments':0,'no_automatic_budget_renewal':True}
save(R/'budget-ledger-final.json',budget)
resolved=[
 {'problem_id':'T08.dual-local-closure:LIMIT_REACHED:active-read-arrival-coverage','state':'resolved','evidence':str(E08/'independent-overlap.json'),'resolution':'actual r1 real arrival/read overlap, complete ownership checks; original r0 FAIL retained','actual_repair_round':1},
 {'problem_id':'T08.dual-local-closure:PERMISSION_MISSING:mode-publication-stale-offer','state':'resolved','evidence':str(P08),'resolution':'static-only window restriction was not lack of original human scope; actual mode-fix02 source frozen and independently passed'},
 {'problem_id':'T10.dual-aplus-scheduler:LIMIT_REACHED:faults-retry-metadata','state':'resolved','evidence':str(R/'user-feedback-T10-retry01.md'),'resolution':'one explicit extra third developer attempt retained; current complete independent fault evidence passed; developer count3/3 remains'},
 {'problem_id':'T10.dual-aplus-scheduler:INPUT_CONFLICT:cmp-descriptor-stall','state':'resolved','evidence':str(P10),'resolution':'CMP offer correction frozen before first integrated acceptance; old actual counterexample rejected and current matrix passed; post-acceptance repairs0'},
 {'problem_id':'T10.dual-aplus-scheduler:API_ERROR:selected-model-capacity','state':'delivery_recovered','evidence':str(R/'T10-model-capacity01/evidence.json'),'resolution':'native error retained; continue03 resumed original role/model for static freeze, not automatic retry or model switch'},
 {'problem_id':'T10.dual-aplus-scheduler:LIMIT_REACHED:descriptor-release-same-edge-coverage','state':'resolved','evidence':str(S10/'matrix/independent-edge-audit.json'),'opportunities_used':2,'opportunities_limit':2,'fixture_compile_root_attempts':2,'fixture_compile_root_limit':2,'resolution':'four exact same physical cycles, complete identities and ownership, eight real lifecycle frames on same DUT; formal round0, actual repairs0'}]
ledger={'run_id':R.name,'active_problems_in_accepted_offline_scope':[],'historical_problems':resolved,
 'historical_external_events':[{'type':'usage_limit','task':'T08.dual-local-closure','references':[str(R/'user-feedback-continue01.md'),str(R/'user-feedback-continue03.md')],'preserved':True,'current_delivery':'original unique tester r1 PASS'},{'type':'model_capacity','task':'T10.dual-aplus-scheduler','reference':str(R/'T10-capacity-error01.md'),'preserved':True,'current_delivery':'same original role/model resumed only after new continue; no capacity availability claim'}],
 'other_history_preserved':['Both T10 earlier round0 FAIL reports and supplement01 canonical index remain byte identical','T08 r0 FAIL unchanged','T10 fairness producer failed then exactly one corrected retry passed','T10 interface oracle reset-cancelled READY correction reused same simulation; result-v1 preserved','T10 same_edge_manual first private compile failed, second corrected declaration-only compile passed'],
 'future_physical_gates_not_current_scope_failures':['G2 STA/physical CDC/resources','G3 true exposure/board recovery','G4 hardware stability/throughput'],'new_tasks_started':0,'hardware_authorization_added':False}
save(R/'problem-ledger-final.json',ledger)
for n in ['user-summary.md','delivery-index.md']:
 p=R/n;t=p.read_text(encoding='utf-8').replace('](/D:/','](D:/')
 if n=='delivery-index.md':t=re.sub(r'\]\((?![A-Za-z]:/|https?://)([^)]+)\)',lambda z:']('+(R/z.group(1)).as_posix()+')',t)
 p.write_text(t,encoding='utf-8',newline='\n')
record08=ROOT/'workflow/records/T08/20261025-180900-dual-local-closure.md'
old08=record08.read_bytes();(R/'final-T08-record-before.md').write_bytes(old08)
with record08.open('a',encoding='utf-8',newline='\n') as f:
 f.write('\n## 本run最终收口\n\nT10现已同输入formal round0综合PASS，post-acceptance实际修复0；本run两个原离线包全部完成。上文T10待返回为当时的部分收口历史。T08 r1 PASS、实修1及所有证据不变；父硬件状态不因本run置done。最终交接和SHA索引：workflow/runs/'+R.name+'/handoff.md、candidate-binding-final.json、final-summary.md。\n')
record10=ROOT/'workflow/records/T10/20261025-180900-dual-aplus-scheduler.md';record10.parent.mkdir(parents=True,exist_ok=True)
with record10.open('x',encoding='utf-8',newline='\n') as f:
 f.write('# T10.dual-aplus-scheduler — 离线G0/G1完成\n\nformal round0 integrated PASS，post-acceptance实际修复0；当前唯一报告为'+rel(P10)+'，SHA256 '+sha(P10)+'。\n\n唯一manifest：'+rel(M10)+'，SHA256 '+sha(M10)+'。两旧r0 FAIL和旧canonical仍为历史快照，当前索引：'+rel(S10/'canonical-report.json')+'。\n\n')
 f.write('原开发 /root/fpga_dev_dual_scheduler_180900；原唯一测试者 /root/fpga_tester_dual_scheduler_180900。16有效旧case122帧＋最后同沿矩阵8帧，共130严格还原帧和2有效负对照；原19进程加尚未执行第20个，未重跑旧套件。四次同物理cycle接纳/释放、完整身份/所有权与CMP持有/ACK均闭合。\n\n')
 f.write('测试累计69调用/4compile/20case；原45/2/19、补充01 12/1/0、补充02 12/1/1均保留。同问题机会2/2、夹具失败根因2/2、fairness2次，开发faults3/3未变；完整开发calls未知。原额度容量错误、失败/读取控制偏差/截止历史保留。\n\n')
 f.write('G2 STA/物理CDC/资源未跑，G3/G4曝光/板级恢复/稳定硬件吞吐待验证；100MHz TB单核约48.46MB/s，不是双路155.52MB/s实时。未合并T08、未迁生产/OpenCode、未TD/硬件/下载/Flash。父T10主源state/blocker/board_chain保持，不置done。回退为继续不采用隔离候选。\n\n最终交接与证据：workflow/runs/'+R.name+'/handoff.md、delivery-index.md、candidate-binding-final.json、final-summary.md。\n')
board_result={'updated':False,'strategy':'read latest under one nonblocking mandatory byte-range lock, append only T08/T10 offline evidence; no conflict retry','parent_hardware_done_by_this_run':False}
board=ROOT/'workflow/tasks.json'
try:
 with board.open('r+b') as f:
  length=max(1,os.fstat(f.fileno()).st_size);f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,length)
  try:
   f.seek(0);oldbytes=f.read();old=json.loads(oldbytes.decode('utf-8-sig'));new=copy.deepcopy(old)
   before={x['id']:copy.deepcopy(x) for x in old['tasks'] if x['id'] in ['T08','T10']};assert len(before)==2
   for task in new['tasks']:
    if task['id'] not in ['T08','T10']:continue
    is10=task['id']=='T10';entry=binding['current_candidates'][1 if is10 else 0]
    if is10:
     pk=task.setdefault('offline_sim_packages',{});assert 'T10.dual-aplus-scheduler' not in pk
     pk['T10.dual-aplus-scheduler']={'status':'PASS','round':0,'actual_repair_rounds':0,'manifest_path':rel(M10),'manifest_sha256':sha(M10),'integrated_report':rel(P10),'integrated_report_sha256':sha(P10),'canonical_report':rel(S10/'canonical-report.json'),'G0':'pass','G1':'pass','G2':'not_run','G3_G4':'not_run/awaiting_hardware','parent_hardware_done':False,'historical_FAILs_retained':True,'record':rel(record10)}
    else:assert task['offline_sim_packages']['T08.dual-local-closure']['manifest_sha256']==sha(M08)
    ev=task.setdefault('latest_evidence',[])
    items=[R/'final-summary.md',R/'handoff.md',R/'delivery-index.md',R/'candidate-binding-final.json',R/'budget-ledger-final.json',R/'problem-ledger-final.json',record10 if is10 else record08]
    if is10:items += [M10,P10,S10/'canonical-report.json']
    for p in items:
     if rel(p) not in ev:ev.append(rel(p))
    marker='['+R.name+':FINAL]';assert marker not in task.get('status_note','')
    task['status_note']=task.get('status_note','')+'\n'+marker+' 本run两原离线包已完成：T08 r1 PASS/实修1，T10同输入r0 PASS/post-acceptance实修0；各自唯一综合测试者、G0/G1通过。历史FAIL/额度容量/超用/未知计数保留。未合并整机/未迁生产或OpenCode，G2未跑、G3/G4待硬件，父state/blocker及并行board_chain保持。'
    task['latest_offline_sim_run_id']=R.name
   allowed={'latest_evidence','status_note','latest_offline_sim_run_id'}
   for a,b in zip(old['tasks'],new['tasks']):
    if a['id'] not in before:assert a==b
    else:
     ak=allowed|({'offline_sim_packages'} if a['id']=='T10' else set())
     assert all(a.get(k)==b.get(k) for k in set(a)|set(b) if k not in ak)
     assert a['state']==b['state'] and a.get('latest_run_id')==b.get('latest_run_id')
   assert all(old[k]==new[k] for k in old if k!='tasks')
   (R/'final-taskboard-before.json').write_bytes(oldbytes);data=(json.dumps(new,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
   try:f.seek(0);f.write(data);f.truncate();f.flush();os.fsync(f.fileno())
   except OSError:
    f.seek(0);f.write(oldbytes);f.truncate();f.flush();os.fsync(f.fileno());raise
   board_result.update(updated=True,parent_states_before={k:v['state'] for k,v in before.items()},parent_states_after={x['id']:x['state'] for x in new['tasks'] if x['id'] in before},parent_latest_run_ids_unchanged={k:v.get('latest_run_id') for k,v in before.items()},other_tasks_and_hardware_fields_unchanged=True,before_sha256=hashlib.sha256(oldbytes).hexdigest(),after_sha256=hashlib.sha256(data).hexdigest())
  finally:f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,length)
except OSError as ex:board_result.update(error=str(ex),no_retry=True)
save(R/'final-taskboard-update.json',board_result)
control_names=['request.md','planning-input-manifest.json','fpga-design-guide.md','dev-plan.md','role-ids.json','user-feedback-T10-retry01.md','user-feedback-continue01.md','user-feedback-continue02.md','user-feedback-continue03.md','user-feedback-readonly-recovery01.md']
outputs=['final-summary.md','handoff.md','user-summary.md','delivery-index.md','input-index-final.md','candidate-binding-final.json','problem-ledger-final.json','budget-ledger-final.json','final-taskboard-update.json']
audit={'closed_at_utc':stamp,'project_root':str(ROOT),'run_id':R.name,'accepted_offline_packages':2,'new_packages_started':0,'T08_manifest_bindings':b08,'T08_compiled_sources':cp08,'T08_prior_closeout':ref(R/'T08-planner-closeout01/audit.json'),'T08_current_report':ref(P08),
 'T10_manifest_bindings':b10,'T10_final_compiled_sources':cp10,'T10_prior_compile_provenance':source_provenance,'T10_private_inputs':private_verified,'T10_new_case_evidence':case_evidence,'T10_current_report':ref(P10),'T10_canonical_index':ref(S10/'canonical-report.json'),'T10_old_effective_results':old_passes,'T10_130_wire_files':wire,'T10_same_edge_audit':ref(S10/'matrix/independent-edge-audit.json'),'T10_declaration_only_correction_independently_compared':True,
 'historical_FAILs_unchanged':[ref(T08r0)]+historical_fails,'drift':0,'T10_final_case_count':20,'T08_final_tester_case_count':34,'both_stop_flags_true_and_active_commands_zero':True,'planner_repeated_experiments':0,'merged_system_tested':False,'G2':'not_run','G3_G4':'not_run/awaiting_hardware','parent_hardware_done_by_this_run':False,'taskboard_update':board_result,
 'control_inputs':[ref(R/n) for n in control_names],'outputs':[ref(R/n) for n in outputs],'task_records':[ref(record08),ref(record10)]}
save(R/'final-closeout-audit.json',audit)
finished=board_result['updated']
dispatch={'run_id':R.name,'project_root':str(ROOT),'output_dir':str(R),'task_ids':['T08.dual-local-closure','T10.dual-aplus-scheduler'],'batch_size':1,'status':'finished' if finished else 'blocked','needs_user_input':False,'question_path':None,'user_summary_path':str(R/'user-summary.md'),
 'input_paths':[str(R/'final-summary.md'),str(R/'handoff.md'),str(R/'delivery-index.md'),str(R/'candidate-binding-final.json'),str(R/'final-closeout-audit.json')],'write_scope':[],'protected':['Both frozen candidates/current and historical reports/evidence','Parent hardware states and parallel production/OpenCode/TD candidates','All counters, errors, old deadlines and unknown accounting'],
 'next_action':{'operation':'relay_to_user','user_summary_path':str(R/'user-summary.md'),'relay_verbatim':True,'no_permission_question':True},
 'scope_limits':{'original_formal_packages':2,'completed_offline_packages':2,'new_tasks_or_roles':0,'merged_system_tested':False,'hardware':0,'production_adoption':0,'TD_build_download_Flash':0},
 'execution_limits':{'new_experiments':0,'new_calls_to_developers_or_testers':0,'automatic_retries':0,'scheduled_monitoring':0,'event_wait_targets':[]},
 'final_results':{'T08.dual-local-closure':{'verdict':'PASS','round':1,'actual_repairs':1},'T10.dual-aplus-scheduler':{'verdict':'PASS','formal_round':0,'actual_post_acceptance_repairs':0}},
 'G0_G1':'pass for separate offline packages','G2':'not_run','G3_G4':'not_run/awaiting_hardware','parent_hardware_done_by_this_run':False,'run_finished':finished,'stop_event_waiting':finished,'handoff_path':str(R/'handoff.md'),'delivery_index_path':str(R/'delivery-index.md')}
if not finished:
 dispatch['problem']={'problem_id':'RUN:INPUT_CONFLICT:final-taskboard-update','reason_code':'INPUT_CONFLICT','new_information':True,'evidence_path':str(R/'final-taskboard-update.json'),'requested_action':'Preserve parallel writer; task records and offline PASS already frozen. No automatic taskboard overwrite/retry.','resume_input_path':str(R/'handoff.md')}
save(R/'dispatch-finished.json',dispatch)
save(R/'final-control.json',{'dispatch':ref(R/'dispatch-finished.json'),'audit':ref(R/'final-closeout-audit.json'),'user_summary':ref(R/'user-summary.md'),'handoff':ref(R/'handoff.md'),'candidate_binding':ref(R/'candidate-binding-final.json'),'finalized_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'status':dispatch['status']})
print(json.dumps({'status':dispatch['status'],'T08':'r1 PASS repair1','T10':'r0 PASS repair0','manifest_bindings':{'T08':len(b08),'T10':len(b10)},'T10_strict_frames':len(wire),'T10_same_edge_hits':len(edge['rows']),'drift':0,'taskboard_updated':finished,'parent_states_preserved':board_result.get('parent_states_after'),'new_experiments':0,'dispatch_path':str(R/'dispatch-finished.json')},ensure_ascii=False))
