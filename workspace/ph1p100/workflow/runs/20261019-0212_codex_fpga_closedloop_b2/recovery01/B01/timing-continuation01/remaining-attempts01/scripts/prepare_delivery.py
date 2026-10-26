import pathlib,json,hashlib,sys,shutil,re,time
N=pathlib.Path(__file__).resolve().parents[1];O=N.parent;BASE=O.parent;RUN=BASE.parents[1]
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
old=readj(O/'quota-resume01/attempt-reconciliation.json')['g1_cumulative'];counts={k:dict(v) for k,v in old.items()};records=[]
for f in sorted((N/'g1').glob('*/result.json')):
    r=readj(f);records.append({'key':r['tb'],'path':str(f),'pass':r['exit']==0 and not r['timeout'] and not r['sim_error'] and r['pass_marker']})
for f in sorted((N/'algo-g1').glob('*/report.json')):
    r=readj(f);records.append({'key':'algorithm_'+r['case']+'/'+r['mutation'],'path':str(f),'pass':r['verdict']=='PASS'})
for k,v in counts.items():
    v['historical_used_before_this_window']=v['cumulative_used'];v['new_window_used']=sum(r['key']==k for r in records);v['cumulative_used']+=v['new_window_used']
    if k.startswith('algorithm_') or k in ['tb_cam_algo_oracle','tb_cam_algo_oracle_negative','tb_cam_algo_adapter_big','tb_closedloop_raw_algo','tb_closedloop_injection']:v['max']=8
    assert v['cumulative_used']<=v['max']
production=[]
for a in [5,6]:
    d=N/'build'/f'attempt{a}'
    if d.exists():production.append({'attempt':a,'state':'ended' if (d/'execution-result.json').is_file() else 'active','execution_result':readj(d/'execution-result.json') if (d/'execution-result.json').is_file() else None})
(N/'attempt-counts.json').write_text(json.dumps({'production_historical_used':4,'production_max':6,'production_cumulative_used':4+len(production),'production_new_records':production,'G1_cumulative':counts,'new_records':records,'actual_repair_rounds':0,'integrated_round0':'not_started','role_window':str(N/'role-window-ledger.json')},indent=2),encoding='utf-8')
# Clone/adapt the reviewed last-finalization code; never edit old frozen scripts.
dst=N/'scripts/freeze.py'
if not dst.exists():
    s=(O/'scripts/freeze.py').read_text(encoding='utf-8')
    s=s.replace('OLD=TC.parent;RUN=OLD.parents[1]','OLD=TC.parent;BASE=OLD.parent;RUN=BASE.parents[1]')
    s=s.replace("attempt in [4,5,6]","attempt in [5,6]")
    s=s.replace("OLD/'protected-T08.json'","BASE/'protected-T08.json'")
    s=s.replace("OLD/'attempt-counts-verified.json'","BASE/'attempt-counts-verified.json'")
    s=s.replace("OLD/'cdc-review.md'","BASE/'cdc-review.md'")
    s=s.replace("'request.md','request-followup-01.md'","'dispatch-production-remaining-attempts01.json','production-remaining-attempts01-plan.md','production-remaining-attempts01-ledger.json','request.md','request-followup-01.md'")
    s=s.replace("Two-slot RGB/sideband elasticity cuts backward ready and forward payload path; all four pixel lanes and SOF/EOL/EOF/abort stay atomic. Arithmetic and oracle/vector bytes unchanged.","Production variants are recorded in rtl/ep_side/img/algo/PROVENANCE-production.md: conservative front enable, registered capacity, three-stage exact grayscale partial sums, independent branch token queues and transfer-gated abort notifications. Pixel mathematics/oracle/vector bytes remain unchanged; source byte equivalence is not claimed.")
    s=s.replace("'recovery_phase':'recovery01/timing-continuation01'","'recovery_phase':'recovery01/timing-continuation01/remaining-attempts01'")
    dst.write_text(s,encoding='utf-8')
dst=N/'scripts/run_sram.py'
s=dst.read_text(encoding='utf-8');s=s.replace('RUN=REC.parents[2]','RUN=REC.parents[3]');dst.write_text(s,encoding='utf-8')
print('PRODUCTION',4+len(production),'/6','G1_CUMULATIVE',{k:v['cumulative_used'] for k,v in counts.items()})
