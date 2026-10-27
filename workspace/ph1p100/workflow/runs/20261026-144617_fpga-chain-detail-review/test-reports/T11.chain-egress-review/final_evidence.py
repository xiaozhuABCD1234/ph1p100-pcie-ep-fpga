import json,sys,subprocess,runpy,hashlib
from pathlib import Path
from datetime import datetime,timezone
RUN=Path(r'D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review'); O=RUN/'test-reports'/'T11.chain-egress-review'
sys.argv=[str(O/'independent_audit.py'),'final']; runpy.run_path(str(O/'independent_audit.py'),run_name='__main__')
j=json.loads((O/'integrity-final.json').read_text(encoding='utf-8')); s=json.loads((O/'manual-structure-and-reuse.json').read_text(encoding='utf-8-sig'))
assert not j['errors'] and not j['drift'] and not j['baseline_errors']
assert all(d['bindings_ok'] and not d['entry_errors'] for d in j['dependencies'])
assert s['status']=='pass' and not s['errors']
assert (O/'independent-export-control.json').is_file() and (O/'independent-address-budget.json').is_file()
git={}
for name,args in [('head',['rev-parse','HEAD']),('branch',['branch','--show-current']),('version',['--version']),('tracked_status',['status','--porcelain','--untracked-files=no'])]:
    p=subprocess.run(['git','-C',r'D:\fpga\ph1p100']+args,capture_output=True,text=True,timeout=60)
    assert p.returncode==0,(name,p.stderr)
    git[name]=p.stdout.strip() if name!='tracked_status' else {'entries':len(p.stdout.splitlines()),'sha256_utf8':hashlib.sha256(p.stdout.encode()).hexdigest()}
assert git['head']=='27c596b01cd961dfa9d0850e4fbf879fe249de90'
commands=[
 {'command':'python -X utf8 independent_audit.py initial','exit_code':0,'stdout':'integrity-initial-stdout.txt','stderr':'integrity-initial-stderr.txt'},
 {'command':'python -B -X utf8 validate_structure.py (first run)','exit_code':1,'stdout':'validate_structure-stdout.txt','stderr':'validate_structure-stderr.txt','cause':'tester UTF-8 assumption for legacy HDL comment bytes'},
 {'command':'python -B -X utf8 independent_semantics.py','exit_code':0,'stdout':'independent_semantics-stdout.txt','stderr':'independent_semantics-stderr.txt','completion':'T11_INDEPENDENT_SEMANTICS_COMPLETE'},
 {'command':'python -B -X utf8 validate_structure.py (one corrected retry)','exit_code':1,'stdout':'validate_structure-attempt2-stdout.txt','stderr':'validate_structure-attempt2-stderr.txt','cause':'tester assumed an original_findings field; actual format stores original_finding_ids + claims; script stopped and was not rerun'},
 {'command':'Start-Job -FilePath manual-structure.ps1; Wait-Job -Timeout 60; Receive-Job or Stop-Job only own job','exit_code':0,'completion':'manual-structure-and-reuse.json status=pass errors=[]','note':'native PowerShell job completed; exit_code denotes successful shell wrapper, not a third Python retry'},
 {'command':'python -B -X utf8 final_evidence.py (runpy independent_audit.py final plus bounded read-only git)','exit_code':0,'completion':'T11_FINAL_EVIDENCE_COMPLETE','stdout':'final-evidence-stdout.txt','stderr':'final-evidence-stderr.txt'}]
result={'timestamp':datetime.now(timezone.utc).isoformat(),'git':git,'python':sys.version,'powershell':'7.6.5','manifest_sha256':j['manifest_sha256'],'manifest_entries':j['entries'],'dependency_entry_checks':sum(d['entry_count'] for d in j['dependencies']),'frozen_drift':j['drift'],'test_scope':'independent read-only document/source/contract audit G0/G1','TD_RTL_sim_hardware_deletions_production_writes':0,'deepseek':'not delegated: the separable hash/arithmetic tasks did not justify dispatch/review overhead; no worker output used as independent verification','commands':commands,'deadline':'Python: own hidden Process WaitForExit(240000); initial/semantic/failed aggregate scripts had no subprocess active and timeout Kill() targets own process only. Final wrapper uses Kill(true) for own tree, git child timeout60. Later reads use own Job timeout60. First AGENTS/skill read completed in1.1s but lacked explicit deadline.'}
(O/'commands-and-final.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(result,ensure_ascii=False,indent=2)); print('T11_FINAL_EVIDENCE_COMPLETE')
