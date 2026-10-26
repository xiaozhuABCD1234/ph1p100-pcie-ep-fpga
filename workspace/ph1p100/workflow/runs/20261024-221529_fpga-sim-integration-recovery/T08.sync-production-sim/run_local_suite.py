from pathlib import Path
import json, sys
from run_t08 import run_case
from check_t08 import check_case
H=Path(__file__).resolve().parent
summary=[]
for case,name in [(1,'nack'),(2,'missing'),(3,'global-reset'),(4,'restart'),(0,'role-mutation')]:
    out=H/'local'/name
    # Historical build1 developer checks. The canonical final checks are in
    # run_final_suite.py/build2; testers use the documented fresh-build entry.
    result=json.loads((out/'sim-result.json').read_text()) if (out/'sim-result.json').exists() else run_case(H/'local/build1',out,case,mutate=name=='role-mutation')
    assert result['sim_pass'],(name,result)
    try:oracle=check_case(out,case)
    except AssertionError as e:oracle={'pass':False,'reason':str(e)}
    (out/'oracle-result.json').write_text(json.dumps(oracle,indent=2),encoding='utf-8')
    if name=='role-mutation':
        assert not oracle['pass'] and 'ordered 14 role writes' in oracle['reason'],'mutation must reach pin order assertion'
    else:assert oracle['pass'],(name,oracle)
    summary.append({'case':case,'name':name,'simulation_pass':True,'oracle':oracle})
    (H/'local/suite-result.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    print(name,'EXPECTED_REJECTION' if name=='role-mutation' else 'PASS',flush=True)
