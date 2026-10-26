"""Planner metadata readiness and dispatch, never runs the candidate tools."""
from pathlib import Path
import hashlib,json,datetime
R=Path(r'D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure')
P=R/'T10.dual-aplus-scheduler/cmp-stall-fix01';S=P/'static-closeout02';M=S/'manifest-cmp-stall-fix01.json'
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(n,obj):
 with (R/n).open('x',encoding='utf-8',newline='\n') as f:json.dump(obj,f,ensure_ascii=False,indent=2);f.write('\n')
def verify(items):
 out=[]
 for x in items:
  p=Path(x['path']);a=sha(p) if p.is_file() else None
  out.append({'path':str(p),'expected_sha256':x['sha256'],'actual_sha256':a,'match':a==x['sha256']})
 return out
m=read(M);bound=verify(m['files']+m['static_outputs']+m['tools']);assert all(x['match'] for x in bound)
assert m['status']=='ready_for_test' and m['stopped_modifying'] and m['active_commands']==0
author=read(S/'author-stop.json');assert author['stopped_modifying'] and author['active_commands']==0 and author['all_owned_experiments_complete']
compiled=verify(read(P/'evidence/compiled-source.json'));assert all(x['match'] for x in compiled)
production=[Path(x) for x in (P/'sources.f').read_text(encoding='utf-8').splitlines() if x.strip()]
assert len(production)==3 and all(x.is_file() for x in production)
expected=['6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb','c8b24775fa70793f682f1a640be175ec53f304722539cbd89550e0d4aefca65b','8d6c2517966466df62cdcac2ede29a931f2ddf350c453fba9f5ae9f2da93100a']
assert [sha(p) for p in production]==expected
account=read(S/'execution-accounting.json');assert account['static_window']['new_compiles']==0 and account['static_window']['new_cases']==0 and account['historical']['developer_faults_used']==3
refs=[]
for name in ['fpga-design-guide.md','dev-plan.md','inputs/T10.dual-aplus-scheduler-tester.md','descriptor-corrections01-plan.md','dispatch-T10-continue03-static.json']:
 p=R/name;refs.append({'path':str(p),'sha256':sha(p)})
for name in ['.agents/skills/fpga-tester/SKILL.md','.agents/skills/fpga-orchestrator/references/work-limits.md','.agents/skills/fpga-orchestrator/references/report-contract.md']:
 p=Path(r'D:\fpga\ph1p100')/name;refs.append({'path':str(p),'sha256':sha(p)})
assert not (R/'test-reports/T10.dual-aplus-scheduler-r0-integrated.md').exists()
audit={'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'task_id':'T10.dual-aplus-scheduler','manifest_path':str(M),'manifest_sha256':sha(M),
 'bound_file_count':len(bound),'bound_files':bound,'compiled_source_count':len(compiled),'compiled_sources':compiled,'drift_count':0,
 'production_sources':[{'path':str(x),'sha256':sha(x)} for x in production],'author_stop':author,'control_references':refs,
 'actual_counts':account,'independent_integrated_round0_started':False,'post_acceptance_repair_rounds':0,'planner_experiments':0,
 'ready_for_independent_test':True,'independent_PASS_assigned':False,
 'developer_evidence_is_not_independent_acceptance':True,
 'known_gaps_to_first_acceptance':['fresh independent complete geometry/prep/fairness/ownership/fault/reset/default full-size/CMP matrix/mutation checks'],
 'runner_restriction':'do not execute frozen run.py or finish.py in place; fresh private library/harness/source mapping required'}
save('T10-round0-readiness01.json',audit)
d={'run_id':R.name,'project_root':r'D:\fpga\ph1p100','output_dir':str(R),'task_ids':['T10.dual-aplus-scheduler'],'batch_size':1,'status':'ready','needs_user_input':False,
 'question_path':None,'user_summary_path':None,'stage':'first independent integrated round0 after actual CMP correction freeze',
 'input_paths':[str(R/'T10-integrated-r0-input.md'),str(R/'inputs/T10.dual-aplus-scheduler-tester.md'),str(M),str(R/'T10-round0-readiness01.json'),str(S/'result-cmp-stall-fix01.md'),str(S/'retest.json'),str(S/'source-map.json'),str(S/'reuse-proposal.json')],
 'manifest_path':str(M),'manifest_sha256':sha(M),
 'write_scope':[str(R/'test-reports/T10.dual-aplus-scheduler')+'/**',str(R/'test-reports/T10.dual-aplus-scheduler-r0-integrated.md')],
 'protected':['Entire developer T10 candidates, scripts, manifests, evidence and previous static deliveries','T08 and all other runs/production/OpenCode candidate','Planning controls, global taskboard/config, Git, TD/hardware/drive mappings'],
 'next_action':{'operation':'spawn_single_tester','runtime':'codex','role':'fpga-tester','tool':'collaboration.spawn_agent','task_name':'fpga_tester_dual_scheduler_180900','fork_turns':'none','skill_path':r'D:\fpga\ph1p100\.agents\skills\fpga-tester\SKILL.md','prompt_path':str(R/'T10-integrated-r0-input.md'),'new_single_tester_only_for_this_task':True,'record_real_tool_returned_ID':True,'do_not_reuse_T08_tester':True,'model_override':None},
 'execution_limits':{'conservative_tool_calls':45,'minutes':60,'absolute_deadline':'record actual first receipt time +60 minutes before commands','compiles':2,'case_processes':20,'same_failed_command_total_attempts':2,'retry_requires_new_evidence':True,'search_rounds_per_problem':3,'no_progress_stop_cycles':2,'read_search_seconds':60,'compile_local_small_case_seconds':300,'default_full_AB_case_seconds':600,'top_TB_cycle_watchdog_required':True,'TD':0,'synthesis':0,'build':0,'download':0,'Flash':0,'hardware':0,'external_messages':0,'mapping_changes':0},
 'budget_basis':{'path':str(R/'dev-plan.md'),'section':'公共检查、工具与预算','prior_T10_independent_consumption':{'calls':0,'compiles':0,'cases':0},'reason':'Original reserved first acceptance needs real core full AB plus all required fault/geometry/interface checks; no developer budget reset'},
 'scope_limits':{'formal_tasks_in_run':2,'batch_size':1,'task_new_developer_roles':0,'task_single_integrated_tester_total':1,'round':0,'post_acceptance_repairs_before_test':0,'offline_G0_G1_only':True},
 'readiness':{'bound_files_verified':len(bound),'actual_compiled_sources':len(compiled),'drift':0,'stopped_modifying':True,'active_commands':0,'independent_PASS':False},
 'history_preserved':{'developer_faults_used':3,'developer_faults_limit':3,'fourth_developer_faults_authorized':False,'known_developer_cumulative_compiles':5,'known_developer_cumulative_cases':16,'cmp_stage_known_visible_calls':24,'cmp_stage_complete_calls':'unknown at capacity boundary','historical_complete_calls':'unknown','latest_static_calls':6,'old_absolute_deadlines_unchanged':True,'capacity_failure_preserved':True},
 'experimental_boundary':'Fresh first independent checks are this tester own original reserved budget; never resume developer faults suite or borrow/reset developer counters. Developer local24 frames cannot replace fresh necessary independent checks.',
 'after_any_test_return_or_error':{'operation':'return_to_planner','target':'/root/fpga_plan_dual_offline','payload':'Actual task/integrated dimensions/verdict/report/manifest/blocked/retest/counters. No automatic repair, model switch, replacement or experiment retry.'},
 'on_quota_capacity_or_tool_error':{'operation':'return_to_planner','target':'/root/fpga_plan_dual_offline','automatic_retry':False,'automatic_model_change':False},
 'other_task':{'task_id':'T08.dual-local-closure','state':'original tester resumed under dispatch-T08-continue03.json; no return received','no_monitoring_or_new_action':True}}
save('dispatch-T10-integrated-r0.json',d)
control={'dispatch_path':str(R/'dispatch-T10-integrated-r0.json'),'dispatch_sha256':sha(R/'dispatch-T10-integrated-r0.json'),'prompt_path':str(R/'T10-integrated-r0-input.md'),'prompt_sha256':sha(R/'T10-integrated-r0-input.md'),'manifest_sha256':sha(M),'readiness_path':str(R/'T10-round0-readiness01.json'),'first_independent_tester_not_yet_spawned_by_planner':True}
save('T10-integrated-r0-control.json',control)
print(json.dumps({'bound_files':len(bound),'compiled_sources':len(compiled),'drift':0,'manifest_sha256':sha(M),'dispatch_path':str(R/'dispatch-T10-integrated-r0.json')},ensure_ascii=False))
