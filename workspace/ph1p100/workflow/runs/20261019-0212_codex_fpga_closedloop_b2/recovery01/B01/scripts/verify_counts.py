import pathlib,json,collections
REC=pathlib.Path(__file__).resolve().parents[1];rows=collections.defaultdict(list)
for p in sorted((REC/'g1').glob('*/result.json')):
    r=json.loads(p.read_text());ok=r['exit']==0 and not r['timeout'] and not r['sim_error'] and r['pass_marker'];rows[r['tb']].append({'path':str(p),'pass':ok})
for p in sorted((REC/'algo-g1').glob('*/report.json')):
    r=json.loads(p.read_text());rows['algorithm_'+r['case']+'/'+r['mutation']].append({'path':str(p),'pass':r['verdict']=='PASS'})
result={k:{'recovery_attempts':len(v),'pass_runs':sum(x['pass'] for x in v),'fail_runs':sum(not x['pass'] for x in v),'latest_pass':v[-1]['pass'],'cumulative_attempts':len(v)+(2 if k=='tb_closedloop_writer_checker' else 0),'records':v} for k,v in rows.items()}
obj={'tests':result,'total_recovery_g1':sum(v['recovery_attempts'] for v in result.values()),'total_recovery_pass':sum(v['pass_runs'] for v in result.values()),'total_recovery_fail':sum(v['fail_runs'] for v in result.values()),'worker_review':'Rejected inaccurate proposal: control must be5 attempts/2PASS/3FAIL, not4/1/3; first TD timeout must remain recorded; worker sum was inconsistent. Native actual JSON files are authoritative. No worker operation requested or executed; no pending call_id.','TD':[json.loads(p.read_text()) for p in sorted((REC/'build').glob('*/execution-result.json'))]}
(REC/'attempt-counts-verified.json').write_text(json.dumps(obj,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in obj.items() if k not in ['tests','TD']},indent=2))
