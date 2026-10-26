"""Final developer checks against build2. One bounded process per case; no retries."""
from pathlib import Path
import hashlib,json
from run_t08 import run_case
from check_t08 import check_case,check_frame
H=Path(__file__).resolve().parent
sources=[Path(p) for p in json.loads((H/'local/build2/sources.json').read_text())]
# Include all compilation inputs and Verilog includes, including environment models.
sources+=list((H/'candidate/rtl').rglob('*.v'))
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(set(sources))}
(H/'local/build2/final-input-hashes.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
results=[]
for case,name in [(5,'pending-reset'),(0,'clean'),(1,'nack'),(2,'missing'),(3,'global-reset'),(4,'restart'),(0,'role-mutation')]:
    out=H/'local/pending-reset' if case==5 else H/'local/final'/name
    if case==5:
        simulation=json.loads((out/'sim-result.json').read_text())
    else:simulation=run_case(H/'local/build2',out,case,mutate=name=='role-mutation')
    assert simulation['sim_pass'],(name,simulation)
    try:oracle=check_case(out,case)
    except AssertionError as ex:oracle={'pass':False,'reason':str(ex)}
    (out/'oracle-result.json').write_text(json.dumps(oracle,indent=2),encoding='utf-8')
    if name=='role-mutation':
        assert not oracle['pass'] and 'ordered 14 role writes' in oracle['reason'],'real role mutation must reach independent pin assertion'
    else:assert oracle['pass'],(name,oracle)
    results.append({'case':case,'name':name,'simulation':simulation,'oracle':oracle,'input_build':'build2'})
    (H/'local/final-suite-result.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    print(name,'EXPECTED_REJECTION' if name=='role-mutation' else 'PASS',flush=True)
assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==s for p,s in hashes.items()),'source drift during final run'
print('FINAL_SUITE_COMPLETE source_drift=0',flush=True)
