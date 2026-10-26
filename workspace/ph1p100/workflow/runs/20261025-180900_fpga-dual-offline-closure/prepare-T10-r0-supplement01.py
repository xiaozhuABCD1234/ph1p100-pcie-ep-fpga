"""Planner static audit and one-case dispatch; no tool/HDL execution."""
from pathlib import Path
import json,hashlib,datetime
R=Path(r'D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure');E=R/'test-reports/T10.dual-aplus-scheduler/r0'
M=R/'T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json';P=R/'test-reports/T10.dual-aplus-scheduler-r0-integrated.md';N=E/'supplement01'
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(n,x):
 with (R/n).open('x',encoding='utf-8',newline='\n') as f:json.dump(x,f,ensure_ascii=False,indent=2);f.write('\n')
def verify(a):
 out=[]
 for x in a:
  p=Path(x['path']);s=sha(p);assert s==x['sha256'],str(p);out.append({'path':str(p),'sha256':s})
 return out
m=read(M);assert sha(M)=='5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b'
bound=verify(m['files']+m['static_outputs']+m['tools']);assert len(bound)==122
assert P.read_text(encoding='utf-8').splitlines()[0]=='### 判定：FAIL'
ret=read(E/'return-metadata.json');acct=read(E/'execution-accounting-final.json');assert ret['stopped_modifying'] and ret['active_commands']==0
c=acct['counts'];assert c['conservative_tool_calls']==45 and c['compile_processes']==2 and c['case_processes']==19 and c['post_acceptance_repair_rounds']==0
private=verify(read(E/'private-final-manifest.json')['private_files'])
compiles=[]
for v in [1,2]:
 rows=[]
 for x in read(E/f'compiled-source{v}.json'):
  p=Path(x['path']);mapped=p
  if v==1 and p.name in ['tb_integrated.sv','tb_old.sv','tb_swap.sv']:mapped=p.with_name(p.stem+'-compile1.sv')
  assert sha(mapped)==x['sha256'];rows.append({'compiled_original_path':str(p),'preserved_exact_bytes_path':str(mapped),'sha256':x['sha256']})
 compiles.append({'compile':v,'sources':rows})
results=[]
for p in sorted(E.glob('*/result.json')):
 x=read(p);assert x['process_exit']==0
 log=Path(x['log']);assert log.is_file() and log.stat().st_size>0
 results.append({'name':x['name'],'status':x['status'],'decoded_frames':x.get('decoded_frames',0),'result_path':str(p),'result_sha256':sha(p),'log':str(log),'log_sha256':sha(log)})
assert len(results)==19 and sum(x['status']=='pass' for x in results)==16 and sum(x['status']=='expected_rejection' for x in results)==2
assert [x['name'] for x in results if x['status']=='fail']==['continuous-fairness']
assert sum(x['decoded_frames'] for x in results if x['status']=='pass')==122
after=read(E/'input-after.json');assert after['drift']==0 and after['bound_files']==122 and after['manifest_sha256']==sha(M)
problem={'problem_id':'T10.dual-aplus-scheduler:LIMIT_REACHED:descriptor-release-same-edge-coverage','reason_code':'LIMIT_REACHED','new_information':True,'evidence_path':str(R/'T10-r0-supplement01-audit.json'),'requested_action':'Original sole tester completes one previously unexecuted same-edge descriptor/release scoreboard matrix and reconsolidates same-input round0; no implementation change or developer fault rerun.','resume_input_path':str(R/'T10-r0-supplement01-input.md')}
keyfiles=[]
for p in [P,E/'reuse-decision.json',E/'execution-accounting-final.json',E/'private-final-manifest.json',E/'checker-correction.json',E/'fault-independent-audit.json',E/'commands.jsonl',E/'input-before.json',E/'input-after.json',E/'return-metadata.json']:
 keyfiles.append({'path':str(p),'sha256':sha(p)})
audit={'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'task_id':'T10.dual-aplus-scheduler','manifest_path':str(M),'manifest_sha256':sha(M),'manifest_bound_count':122,'bindings':bound,'drift':0,'private_frozen_inputs':private,'actual_compilation_provenance':compiles,'observed_case_results':results,'accepted_existing_frames':122,'source_report':str(P),'source_report_sha256':sha(P),'evidence':keyfiles,'original_budget':acct,'only_unmet_gate':'Explicit same rising edge descriptor acceptance and RAW release handshake with complete identity/ownership scoreboard','problem':problem,'opportunities':{'used_before':0,'this_dispatch':1,'limit':2},'implementation_change':False,'round':0,'actual_post_acceptance_repairs':0,'new_experiments_by_planner':0,'T08':'closed r1 PASS; no recheck or mutation','canonical_report_policy':'Old root r0 FAIL immutable; one completed current round0 report in new supplement01 with canonical-report.json explicitly mapping prior historical FAIL'}
save('T10-r0-supplement01-audit.json',audit)
dispatch={'run_id':R.name,'project_root':r'D:\fpga\ph1p100','output_dir':str(R),'task_ids':['T10.dual-aplus-scheduler'],'batch_size':1,'status':'ready','needs_user_input':False,'question_path':None,'user_summary_path':None,
 'stage':'same unchanged input, formal round0 coverage completion01; no actual implementation repair',
 'input_paths':[str(R/'T10-r0-supplement01-input.md'),str(R/'T10-r0-supplement01-plan.md'),str(R/'T10-r0-supplement01-audit.json'),str(P),str(E/'reuse-decision.json'),str(M)],
 'manifest_path':str(M),'manifest_sha256':sha(M),'write_scope':[str(N)+'/**'],
 'protected':['Entire developer candidate/manifest and original r0 evidence including root FAIL report','T08 PASS/records, production/OpenCode/TD/hardware','Original task IDs, role identity, failed-command counts and all historical budgets'],
 'next_action':{'operation':'followup_task','target':'/root/fpga_tester_dual_scheduler_180900','role':'fpga-tester','prompt_path':str(R/'T10-r0-supplement01-input.md'),'same_model':True,'original_single_tester_only':True},
 'scope_limits':{'new_tasks':0,'new_roles':0,'implementation_changes':0,'actual_repairs':0,'formal_round':0,'developer_faults_used':3,'developer_faults_total_limit':3,'new_developer_faults':0,'full_suite_reruns':0,'only_missing_same_edge_coverage':True},
 'execution_limits':{'additional_conservative_tool_calls':16,'minutes':20,'absolute_deadline':'record real followup receipt/start+20min before commands; preserve old01:09/02:09 timing history','additional_compiles':1,'additional_case_processes':1,'cumulative_tester_calls_cap':61,'cumulative_tester_compiles_cap':3,'cumulative_tester_case_processes_cap':20,'prior_tester_counts':{'calls':45,'compiles':2,'cases':19},'no_automatic_compile_or_case_retry':True,'same_failed_command_total_attempts':2,'fairness_attempts_used':2,'fairness_additional_attempts':0,'read_search_seconds':60,'compile_case_seconds':300,'TB_cycle_watchdog_required':True,'search_rounds_per_problem':3,'no_progress_cycles':2,'TD':0,'build':0,'hardware':0,'download':0,'Flash':0,'mapping':0,'external_messages':0},
 'budget_basis':'Original user two-package offline closure and continue03 remain active. Planner freezes necessary reversible same-scope supplement; old45/2 limits consumed and retained, no claim user imposed those values, no reset or retrospective compliance. Case uses original remaining twentieth process.',
 'problem':problem,'problem_opportunities':{'used_before':0,'current':1,'limit':2,'no_automatic_second_dispatch':True},
 'report_policy':{'formal_round':0,'post_acceptance_repairs':0,'old_FAIL_immutable_path':str(P),'old_FAIL_sha256':sha(P),'new_current_report_path':str(N/'T10.dual-aplus-scheduler-r0-integrated.md'),'canonical_index_path':str(N/'canonical-report.json'),'one_current_integrated_conclusion':True,'no_fake_r1':True},
 'after_any_return_or_external_error':{'operation':'return_to_planner','target':'/root/fpga_plan_dual_offline','pass_actual_metadata_counts_problem_reuse_report_paths':True,'automatic_retry_or_model_switch':False},
 'on_actual_ID_error':{'operation':'return_to_planner','target':'/root/fpga_plan_dual_offline','preemptive_replacement':False},
 'T08':{'status':'offline_G0_G1_r1_PASS_closed','no_action':True,'parent_hardware_state_unchanged':True},'run_finished':False}
save('dispatch-T10-r0-supplement01.json',dispatch)
print(json.dumps({'manifest_bindings':len(bound),'drift':0,'prior_cases':19,'prior_accepted_frames':122,'old_FAIL_sha256':sha(P),'formal_round':0,'actual_repairs':0,'dispatch_path':str(R/'dispatch-T10-r0-supplement01.json')},ensure_ascii=False))
