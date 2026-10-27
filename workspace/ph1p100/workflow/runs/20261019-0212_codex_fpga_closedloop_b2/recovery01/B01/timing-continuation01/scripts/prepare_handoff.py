"""Prepare guarded board sources and current cumulative counts; never downloads."""
import pathlib,shutil,json,hashlib
TC=pathlib.Path(__file__).resolve().parents[1];OLD=TC.parent;RUN=OLD.parents[1]
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
board=TC/'board';board.mkdir(exist_ok=True)
dst=board/'download_sram.tcl'
if not dst.exists():shutil.copyfile(OLD/'board/download_sram.tcl',dst)
dst=TC/'scripts/run_sram.py'
if not dst.exists():
    s=(OLD/'scripts/run_sram.py').read_text(encoding='utf-8')
    s=s.replace('RUN=REC.parents[1]','RUN=REC.parents[2]')
    dst.write_text(s,encoding='utf-8')
old=readj(OLD/'attempt-counts-verified.json');tests=old['tests']
new=[]
for f in sorted((TC/'g1').glob('*/result.json')):
    r=readj(f);key=r['tb'];passed=r['exit']==0 and not r['timeout'] and not r['sim_error'] and r['pass_marker'];new.append({'key':key,'path':str(f),'pass':passed})
for f in sorted((TC/'algo-g1').glob('*/report.json')):
    r=readj(f);new.append({'key':'algo/'+r['case']+'/'+r['mutation'],'path':str(f),'pass':r['verdict']=='PASS'})
print('OLD_TEST_KEYS',list(tests));print('OLD_OTHER_KEYS',[k for k in old if k!='tests'])
result={'historical_verified_accounting':{'path':str(OLD/'attempt-counts-verified.json'),'sha256':hashlib.sha256((OLD/'attempt-counts-verified.json').read_bytes()).hexdigest()},'new_records':new,'production_historical_used':3,'production_max':6,'actual_repair_rounds_used':0,'independent_round0_occurred':False}
prod=[]
for n in [4,5,6]:
    d=TC/'build'/f'attempt{n}'
    if d.exists():prod.append({'attempt':n,'state':'finished' if (d/'execution-result.json').exists() else 'active','execution_result':str(d/'execution-result.json'),'result':readj(d/'execution-result.json') if (d/'execution-result.json').exists() else None})
result['new_production_records']=prod;result['production_cumulative_used']=3+len(prod)
(TC/'attempt-counts.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('NEW_G1',len(new),'PRODUCTION_USED',result['production_cumulative_used'])
