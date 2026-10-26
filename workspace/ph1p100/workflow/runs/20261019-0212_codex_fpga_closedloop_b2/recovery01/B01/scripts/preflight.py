import pathlib,ast,json,hashlib
REC=pathlib.Path(__file__).resolve().parents[1]
scripts=[]
for p in sorted((REC/'scripts').glob('*.py')):
    ast.parse(p.read_text(encoding='utf-8'),filename=str(p));scripts.append(str(p))
latest={}
for p in sorted((REC/'g1').glob('*/result.json')):
    r=json.loads(p.read_text());r['result_path']=str(p);latest[r['tb']]=r
markers=[]
for name,r in latest.items():
    p=pathlib.Path(r['log']);lines=p.read_text(encoding='utf-8',errors='replace').splitlines()
    matches=[s for s in lines if 'PASS' in s or 'FAIL' in s]
    assert r['pass_marker'] and r['exit']==0 and not r['sim_error'] and not r['timeout'],name
    markers.append({'tb':name,'last_markers':matches[-3:],'negative_rejection':r['negative_rejection']})
protected=json.loads((REC/'protected-T08.json').read_text(encoding='utf-8'))
assert all(hashlib.sha256(pathlib.Path(e['path']).read_bytes()).hexdigest()==e['sha256'] for e in protected['entries'])
result={'script_AST_pass':True,'script_count':len(scripts),'latest_G1_count':len(latest),'latest_G1_markers':markers,'protected_T08_entries_unchanged':len(protected['entries'])}
(REC/'preflight.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result,indent=2))
