"""Planner checks the new failed fixture evidence and freezes final bounded return."""
from pathlib import Path
import hashlib,json,datetime
R=Path(r'D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure');E=R/'test-reports/T10.dual-aplus-scheduler/r0';F=E/'supplement01';N=E/'supplement02';M=R/'T10.dual-aplus-scheduler/cmp-stall-fix01/static-closeout02/manifest-cmp-stall-fix01.json'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(n,x):
 with (R/n).open('x',encoding='utf-8',newline='\n') as f:json.dump(x,f,ensure_ascii=False,indent=2);f.write('\n')
def verify(xs):
 out=[]
 for x in xs:
  s=sha(x['path']);assert s==x['sha256'],x['path'];out.append({'path':x['path'],'sha256':s})
 return out
m=read(M);assert sha(M)=='5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b'
bindings=verify(m['files']+m['static_outputs']+m['tools']);assert len(bindings)==122
private=verify(read(F/'private-input-manifest.json')['files']);compiled=verify(read(F/'compiled-source.json'));assert len(compiled)==4
commands=[json.loads(x) for x in (F/'commands.jsonl').read_text(encoding='utf-8').splitlines() if x.strip()]
comp=[x for x in commands if Path(x['argv'][0]).name.lower()=='vlog.exe'];sim=[x for x in commands if Path(x['argv'][0]).name.lower()=='vsim.exe']
assert len(comp)==1 and comp[0]['exit_code']==2 and len(sim)==0
log=(F/'compile.log').read_text(encoding='utf-8');assert "Undefined variable: 'same_edge_manual'" in log and 'Errors: 1, Warnings: 0' in log
tb=(F/'tb_same_edge.sv').read_text(encoding='utf-8');assert tb.index('if(!same_edge_manual)')<tb.index('reg same_edge_manual=1;') and tb.count('reg same_edge_manual=1;')==1
account=read(F/'execution-accounting.json');c=account['counts'];assert c['cumulative']=={'calls':57,'compiles':3,'cases':19} and c['stopped_modifying'] and c['active_commands']==0
fv=read(F/'final-verification.json');assert fv['report_SHA']==sha(F/'T10.dual-aplus-scheduler-r0-integrated.md') and fv['one_compile_no_case']
assert sha(R/'test-reports/T10.dual-aplus-scheduler-r0-integrated.md')=='123a68cb9b415292e5a230eda143b894093edc368133dc41055fed0256dd5855'
reused=verify(read(F/'reuse-decision.json')['old_effective_results']);assert len(reused)==19
evidence=[]
for p in [F/n for n in ['T10.dual-aplus-scheduler-r0-integrated.md','compile.log','canonical-report.json','commands.jsonl','execution-accounting.json','final-verification.json','private-input-manifest.json','compiled-source.json','tb_same_edge.sv','helper.py','run_supplement.py','reuse-decision.json']]:evidence.append({'path':str(p),'sha256':sha(p)})
problem={'problem_id':'T10.dual-aplus-scheduler:LIMIT_REACHED:descriptor-release-same-edge-coverage','reason_code':'LIMIT_REACHED','new_information':True,'evidence_path':str(F/'compile.log'),'requested_action':'Original sole tester moves its same_edge_manual declaration before first reference in a new private copy, executes the one corrected compile retry and only the unconsumed twentieth case; retains all prior failures/counters and same DUT.','resume_input_path':str(R/'T10-r0-supplement02-input.md')}
audit={'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'task_id':'T10.dual-aplus-scheduler','manifest_path':str(M),'manifest_sha256':sha(M),'bound_count':122,'bindings':bindings,'drift':0,'failed_private_inputs':private,'failed_compile_inputs':compiled,'failed_compile_commands':comp,'simulator_commands_observed':0,'exact_new_information':'ModelSim vlog2730 at private TB line91: same_edge_manual reference before its line172 module declaration','minimal_correction':'Move one existing reg declaration, preserving initialization and all test semantics; private path/deadline mapping only','historical_effective_results_verified':reused,'evidence':evidence,'counts':account,'same_problem_opportunity':{'used':1,'this':2,'limit':2},'same_compile_root_attempts':{'failed':1,'corrected_retry_now':1,'total_limit':2},'round':0,'actual_repairs':0,'planner_source_edits':0,'planner_compiles_or_simulations':0}
save('T10-r0-supplement02-audit.json',audit)
d={'run_id':R.name,'project_root':r'D:\fpga\ph1p100','output_dir':str(R),'task_ids':['T10.dual-aplus-scheduler'],'batch_size':1,'status':'ready','needs_user_input':False,'question_path':None,'user_summary_path':None,'stage':'final same-problem coverage return2/2 and fixture compile corrected retry2/2; no implementation repair',
 'input_paths':[str(R/'T10-r0-supplement02-input.md'),str(R/'T10-r0-supplement02-audit.json'),str(F/'compile.log'),str(F/'execution-accounting.json'),str(F/'tb_same_edge.sv'),str(F/'reuse-decision.json'),str(M)],'manifest_path':str(M),'manifest_sha256':sha(M),'write_scope':[str(N)+'/**'],
 'protected':['All old r0/supplement01 evidence, failed sources/logs, reports and canonical indexes','All DUT/manifest/developer source and faults3/3','T08 PASS and parent states; production/OpenCode/TD/hardware/global config'],
 'next_action':{'operation':'followup_task','target':'/root/fpga_tester_dual_scheduler_180900','role':'fpga-tester','prompt_path':str(R/'T10-r0-supplement02-input.md'),'same_model':True,'no_new_role':True},
 'execution_limits':{'additional_conservative_calls':16,'minutes':15,'absolute_deadline':'record actual followup receipt/first observable entry+15min before commands, retaining prior deadlines','additional_compile_attempts':1,'additional_case_processes':1,'prior_cumulative':{'calls':57,'compiles':3,'cases':19},'new_cumulative_caps':{'calls':73,'compiles':4,'cases':20},'same_failed_fixture_compile_attempts_total_limit':2,'failed_fixture_compile_attempts_used':1,'no_third_compile_for_this_failure':True,'no_second_case_in_this_window':True,'read_search_seconds':60,'compile_case_seconds':300,'TB_watchdog_required':True,'no_progress_cycles':2,'search_rounds_per_problem':3,'fairness_additional_attempts':0,'developer_faults_additional':0,'TD':0,'build':0,'hardware':0,'download':0,'Flash':0,'mapping':0,'external_messages':0},
 'budget_basis':'Original necessary reversible offline acceptance remains authorized. Last finite same-problem opportunity, with explicit new declaration-order evidence and only one unexecuted original case. New bounded tool/compile supplement is separate history, not reset or retrospective compliance.',
 'problem':problem,'problem_opportunities':{'used_before':1,'this':2,'limit':2,'no_automatic_third_opportunity':True},'same_failure_retry':{'first_failure':str(F/'compile.log'),'new_evidence':'undefined module reg declaration order','permitted_correction':'declaration moved before first reference, same init and test expectations','attempt_now':2,'limit':2},
 'scope_limits':{'formal_round':0,'actual_post_acceptance_repairs':0,'DUT_changes':0,'full_suite_reruns':0,'developer_faults_limit':3,'developer_faults_used':3,'new_tasks':0,'new_roles':0,'T08_changes':0},
 'report_policy':{'current_path':str(N/'T10.dual-aplus-scheduler-r0-integrated.md'),'canonical_index':str(N/'canonical-report.json'),'historical_FAILs_immutable':[str(R/'test-reports/T10.dual-aplus-scheduler-r0-integrated.md'),str(F/'T10.dual-aplus-scheduler-r0-integrated.md')],'same_input_round0_only':True,'no_fake_r1':True},
 'after_any_return_or_error':{'operation':'return_to_planner','target':'/root/fpga_plan_dual_offline','pass_real_evidence_actual_counts_and_complete_problem':True,'automatic_retry_or_model_change':False},'on_actual_ID_error':{'operation':'return_to_planner','target':'/root/fpga_plan_dual_offline','preemptive_replacement':False},'run_finished':False,'T08_status':'closed offline r1 PASS unchanged'}
save('dispatch-T10-r0-supplement02.json',d)
print(json.dumps({'manifest_drift':0,'failed_compile_count':1,'new_simulations_so_far':0,'same_problem_opportunity':'2/2','corrected_compile_retry':'2/2','dispatch_path':str(R/'dispatch-T10-r0-supplement02.json')},ensure_ascii=False))
