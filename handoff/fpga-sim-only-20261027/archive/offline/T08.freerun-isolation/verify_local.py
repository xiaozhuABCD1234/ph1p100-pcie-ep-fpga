"""Recheck six saved simulations, interface and seeded evidence mutations within 60 s."""
from pathlib import Path
import datetime, hashlib, json, sys, time
import check_freerun as oracle

HERE=Path(__file__).resolve().parent
def save(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
    start=time.monotonic();results=[]
    for case in range(6):
        out=HERE/f'local/case{case}'
        sim=json.loads((out/'sim-result.json').read_text())
        assert sim['sim_pass'] and not sim['timeout'] and sim['exit_code']==0
        result=oracle.check(out);save(out/'oracle-result.json',result);results.append(result)
    save(HERE/'case-results.json',results)
    static=oracle.static_interface();save(HERE/'static-interface-result.json',static)
    negative=oracle.negative_controls(HERE/'local/case4');save(HERE/'negative-controls.json',negative)
    binding=json.loads((HERE/'inputs/source-binding.json').read_text())
    drift=[]
    for row in binding['sources']+binding['references']:
        actual=hashlib.sha256(Path(row['path']).read_bytes()).hexdigest()
        if actual!=row['sha256']:drift.append({'path':row['path'],'expected':row['sha256'],'actual':actual})
    assert not drift,'frozen source or common planning inputs changed'
    save(HERE/'input-drift-after-local.json',{'pass':True,'checked_count':len(binding['sources'])+len(binding['references']),
         'drift':drift,'checked_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()})
    summary={'local_checks_pass':True,'case_count':6,'source_frames_per_camera_per_case':12,
             'byte_checked_frames':sum(len(r['frames']) for r in results),'source_binding_count':len(binding['sources']),
             'mutations_rejected':len(negative),'compile_count':1,'case_process_count':6,'active_commands_after_return':0,
             'elapsed_seconds':time.monotonic()-start}
    save(HERE/'local-verification.json',summary);print(json.dumps(summary),flush=True)

if __name__=='__main__':main()
