"""Read-only evidence review plus authorized T08 record/taskboard metadata append."""
from pathlib import Path
import hashlib,json,datetime,os,copy,msvcrt
ROOT=Path(r'D:\fpga\ph1p100');R=ROOT/'workflow/runs/20261025-180900_fpga-dual-offline-closure'
E=R/'test-reports/T08.dual-local-closure/r1/integrated-mode-fix02';O=R/'T08-planner-closeout01';O.mkdir(exist_ok=False)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(p,obj):
 with Path(p).open('x',encoding='utf-8',newline='\n') as f:json.dump(obj,f,ensure_ascii=False,indent=2);f.write('\n')
def verify(items):
 out=[]
 for x in items:
  p=Path(x['path']);a=sha(p) if p.is_file() else None
  out.append({'path':str(p),'expected':x['sha256'],'actual':a,'match':a==x['sha256']})
 assert all(x['match'] for x in out)
 return out
M=R/'T08.dual-local-closure/r1/mode-fix02/manifest-mode-fix02.json';P=R/'test-reports/T08.dual-local-closure-r1-integrated.md'
m=read(M);final=read(E/'final-verification-r1.json');ret=read(E/'return-r1.json');account=read(E/'execution-accounting-r1.json')
assert sha(M)==final['manifest_sha256']=='38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3'
assert sha(P)==final['report_sha256']=='71ef63293bd253182ad23f04ac8889a29e1d7be8bc0a7cc4869dc12bb0e472aa'
assert P.read_text(encoding='utf-8').splitlines()[0]=='### 判定：PASS' and ret['verdict']=='PASS' and ret['blocked']==[]
assert ret['stopped_modifying'] and ret['active_commands']==0 and final['verified']
for v in ret['dimension_results'].values():assert v['applicable'] and v['result']=='pass' and v['G0']==v['G1']=='pass' and v['G2']=='not_run'
bound=verify(m['files']+m['input_references']+m['tools']);assert len(bound)==314
compiled=verify(read(E/'compiled-sources.json'));assert len(compiled)==81
r0=R/'test-reports/T08.dual-local-closure-r0-integrated.md'
assert sha(r0)=='2bddce8c19cd71727609eaee04bfedc141d280f0b87b55fccc837d183aa86fa6'
suite=read(E/'suite-results.json');assert len(suite)==14
assert all(x['accepted_result'] and x['exit_code']==0 and not x['timeout'] for x in suite)
assert {x['label'] for x in suite}=={'mode-matrix','original-edges','ownership-matrix','case16','case00','case10','case11','case12','case13','case14','case15','contract','legacy','negative-b-release'}
commands=read(E/'command-inventory-r1.json');assert len(commands)==16
logs=[]
for x in commands:
 p=Path(x['log']);assert p.is_file() and p.stat().st_size>0 and not x['timeout'] and x['exit_code']==0
 logs.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size})
for x in suite:
 t=Path(x['log']).read_text(encoding='utf-8',errors='replace')
 if x['label']=='negative-b-release':assert 'MODE_FAIL B_release_routes_only_B' in t and 'MODE_MATRIX_FAIL' in t and 'MODE_MATRIX_PASS' not in t
 else:assert x['sim_pass']
overlap=read(E/'independent-overlap.json');assert overlap['pass_'] and all(x['new_sofs']>=2 and x['alternate_slot_publications']>=1 and x['recovered_good_frames']>=2 for x in overlap['cameras'])
oracles=read(E/'independent-oracle-results.json');assert len(oracles)==9 and all(x['pass_'] for x in oracles)
reuse=read(E/'reuse-decision-r1.json');assert reuse['manifest_sha256']==sha(M) and reuse['old_r0_verdict_retained']=='FAIL'
reuse_sources=[]
for x in reuse['source_mapping']:
 assert x['same'] and x['new_sha']==x['old_sha']==sha(x['current'])==sha(x['old']);reuse_sources.append({'current':x['current'],'old':x['old'],'sha256':x['new_sha']})
assert len(reuse_sources)==72 and len(reuse['parameter_mapping'])==18 and all(x['same'] and x['new']==x['old'] for x in reuse['parameter_mapping'].values())
extra=read(E/'additional-provenance-audit.json');old_oracles=verify(extra['reused_own_oracles']);assert len(old_oracles)==9
fixture=read(E/'fixture-provenance.json');assert fixture['original_edges_unchanged'] and sha(E/'tb_tester_edges.sv')==fixture['original_edges_sha256'] and sha(E/'mutant_bad_b.v')==fixture['mutant_sha256']
assert account['r1_total_after_final_verification']['conservative_calls']==29 and account['r1_total_after_final_verification']['cases']==14 and account['r1_total_after_final_verification']['original_edges_remaining']==0
evidence=[]
for p in [P,M]+[E/n for n in ['final-verification-r1.json','return-r1.json','execution-accounting-r1.json','reuse-decision-r1.json','additional-provenance-audit.json','suite-results.json','compiled-sources.json','command-inventory-r1.json','independent-oracle-results.json','independent-overlap.json','freeze-final.json','fixture-provenance.json','module-bindings.json','warning-audit-r1.json','default-boundary-r1.json','tester_r1.py','independent_oracle_r1.py']]:
 evidence.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size})
audit={'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'task_id':'T08.dual-local-closure','decision':'accept sole original integrated round1 PASS for same frozen G0/G1 offline candidate','run_finished':False,'T10_status':'first original integrated tester dispatched; no return received; not reviewed or probed',
 'manifest_path':str(M),'manifest_sha256':sha(M),'report_path':str(P),'report_sha256':sha(P),'manifest_bound_files':bound,'compiled_sources':compiled,'drift':0,
 'reused_72_source_pairs':reuse_sources,'reused_9_old_oracles':old_oracles,'current_evidence':evidence,'native_logs':logs,'counts':account,
 'actual_repair_round':1,'r0_FAIL_retained':True,'stopped_modifying':True,'active_commands':0,'planner_rebuilt_or_simulated':False,'G2':'not_run','G3_G4':'not_run/awaiting_hardware','parent_hardware_done':False}
save(O/'audit.json',audit)
record=ROOT/'workflow/records/T08/20261025-180900-dual-local-closure.md';record.parent.mkdir(parents=True,exist_ok=True)
with record.open('x',encoding='utf-8',newline='\n') as f:
 f.write('# T08.dual-local-closure — 离线G0/G1收口\n\n')
 f.write('正式round1 integrated PASS，实际修复1；原r0 FAIL与全部历史失败/超用保留。父T08硬件任务未完成，状态保持。\n\n')
 f.write('唯一manifest：'+M.relative_to(ROOT).as_posix()+'\nSHA256：'+sha(M)+'\n\n')
 f.write('独立报告：'+P.relative_to(ROOT).as_posix()+'\nSHA256：'+sha(P)+'\n\n')
 f.write('详细交接：'+(R/'T08-offline-handoff01.md').relative_to(ROOT).as_posix()+'\n\n规划复核：'+(O/'audit.json').relative_to(ROOT).as_posix()+'\n\n')
 f.write('原开发 /root/fpga_dev_dual_local_180900；唯一原测试者 /root/fpga_tester_dual_local_180900。14 fresh case、独立112数据对象、有效B-release负对照；I2C/sync旧部分由原测试者按新manifest源/参数/刺激绑定复用。\n\n')
 f.write('本轮r1总29/30调用、1/2compile、14/14case；测试者全历史73调用/3compile/34case；original_edges2次已满。开发142调用/7compile/44case及r0超用保留。无自动复跑/新增修复。\n\n')
 f.write('G2 STA/资源/物理CDC未跑；G3/G4曝光/板级恢复/稳定吞吐awaiting_hardware。未迁生产或OpenCode候选、未TD/硬件/下载/Flash。回退为停止采用隔离mode-fix02，原生产未替换。\n\n')
 f.write('本run尚未结束：T10原首次唯一综合测试者已派出，尚未收到判定；不赋PASS，不监控、不重派。\n')
entry={'status':'PASS','round':1,'actual_repair_rounds':1,'manifest_path':M.relative_to(ROOT).as_posix(),'manifest_sha256':sha(M),'integrated_report':P.relative_to(ROOT).as_posix(),'integrated_report_sha256':sha(P),'G0':'pass','G1':'pass','G2':'not_run','G3_G4':'not_run/awaiting_hardware','parent_hardware_done':False,'r0_verdict_preserved':'FAIL','record':record.relative_to(ROOT).as_posix()}
board_result={'updated':False,'strategy':'single nonblocking mandatory byte-range lock and latest read; only T08 offline evidence fields; no retry on conflict'}
board=ROOT/'workflow/tasks.json'
try:
 with board.open('r+b') as f:
  locksize=max(1,os.fstat(f.fileno()).st_size);f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_NBLCK,locksize)
  try:
   f.seek(0);oldbytes=f.read();old=json.loads(oldbytes.decode('utf-8-sig'));new=copy.deepcopy(old)
   matches=[x for x in new['tasks'] if x['id']=='T08'];assert len(matches)==1;t=matches[0];prior_state=t['state'];prior_latest=t.get('latest_run_id')
   pkgs=t.setdefault('offline_sim_packages',{});assert 'T08.dual-local-closure' not in pkgs;pkgs['T08.dual-local-closure']=entry
   refs=t.setdefault('latest_evidence',[])
   for x in [entry['manifest_path'],entry['integrated_report'],entry['record'],(R/'T08-offline-handoff01.md').relative_to(ROOT).as_posix(),(O/'audit.json').relative_to(ROOT).as_posix()]:
    if x not in refs:refs.append(x)
   marker='[20261025-180900_fpga-dual-offline-closure:T08-r1]'
   assert marker not in t.get('status_note','')
   t['status_note']=t.get('status_note','')+'\n'+marker+' T08.dual-local-closure integrated round1 PASS，实际修复1；G0/G1 pass，14 fresh case/112数据对象。r0 FAIL/历史超用与计数保留；G2 not_run，G3/G4 awaiting_hardware，未迁生产/未证曝光同步，父state不变。T10独立验收尚未返回，全run未结束。'
   t['latest_offline_sim_run_id']=R.name
   for k,v in old.items():
    if k!='tasks':assert new[k]==v
   for a,b in zip(old['tasks'],new['tasks']):
    if a['id']!='T08':assert a==b
    else:
     allowed={'offline_sim_packages','latest_evidence','status_note','latest_offline_sim_run_id'}
     assert all(a.get(k)==b.get(k) for k in set(a)|set(b) if k not in allowed)
   assert t['state']==prior_state and t.get('latest_run_id')==prior_latest and prior_state!='done'
   backup=O/'taskboard-before.json';backup.write_bytes(oldbytes)
   data=(json.dumps(new,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
   try:f.seek(0);f.write(data);f.truncate();f.flush();os.fsync(f.fileno())
   except OSError:
    f.seek(0);f.write(oldbytes);f.truncate();f.flush();os.fsync(f.fileno());raise
   board_result.update(updated=True,parent_state_before=prior_state,parent_state_after=t['state'],latest_run_id_unchanged=prior_latest,before_sha256=hashlib.sha256(oldbytes).hexdigest(),after_sha256=hashlib.sha256(data).hexdigest(),other_tasks_unchanged=True)
  finally:f.seek(0);msvcrt.locking(f.fileno(),msvcrt.LK_UNLCK,locksize)
except OSError as ex:board_result['conflict_or_io_error']=str(ex);board_result['no_retry']=True
save(O/'taskboard-update.json',board_result)
closeout={'task_id':'T08.dual-local-closure','offline_status':'PASS_closed','run_status':'active','run_finished':False,'manifest_path':str(M),'manifest_sha256':sha(M),'report_path':str(P),'report_sha256':sha(P),'record_path':str(record),'audit_path':str(O/'audit.json'),'taskboard_update':board_result,'original_roles':{'developer':'/root/fpga_dev_dual_local_180900','tester':'/root/fpga_tester_dual_local_180900'},'actual_repair_round':1,'r0_FAIL_retained':True,'T10_status':'sole first integrated tester dispatched, no return received','T10_tester':'/root/fpga_tester_dual_scheduler_180900','no_more_T08_experiments_authorized_by_this_closeout':True,'parent_hardware_done':False}
save(R/'partial-closeout-T08-01.json',closeout)
dispatch={'run_id':R.name,'project_root':str(ROOT),'output_dir':str(R),'task_ids':['T08.dual-local-closure'],'batch_size':1,'status':'ready','needs_user_input':False,'question_path':None,'user_summary_path':str(R/'user-summary-T08-pass01.md'),'input_paths':[str(R/'partial-closeout-T08-01.json'),str(R/'T08-offline-handoff01.md')],'write_scope':[],'protected':['All frozen source and evidence','Parent hardware states, OpenCode/production, T10 active original test'],'next_action':{'operation':'relay_to_user','user_summary_path':str(R/'user-summary-T08-pass01.md'),'no_permission_question':True},'scope_limits':{'T08_offline_closed':True,'run_finished':False,'T10_verdict':'not received','new_tasks_or_roles':0,'T08_additional_experiments':0},'execution_limits':{'root_no_technical_work':True,'wait_agent_max_ms':60000,'no_polling_scans_progress_questions':True},'event_wait_targets':['/root/fpga_tester_dual_scheduler_180900'],'after_T10_actual_return_or_error':{'operation':'return_to_planner','target':'/root/fpga_plan_dual_offline','pass_exact_metadata_only':True},'T08_no_retest_or_developer_followup':True}
save(R/'dispatch-T08-closed-wait-T10.json',dispatch)
print(json.dumps({'T08_offline':'PASS_closed','bound':len(bound),'compiled':len(compiled),'drift':0,'taskboard_updated':board_result['updated'],'parent_state':board_result.get('parent_state_after'),'run_finished':False,'dispatch_path':str(R/'dispatch-T08-closed-wait-T10.json')},ensure_ascii=False))
