import json, csv, hashlib, sys, re, platform
from pathlib import Path
from collections import Counter
from datetime import datetime, timezone
RUN=Path(r'D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review')
PKG=RUN/'T11.chain-egress-review'
OUT=RUN/'test-reports'/'T11.chain-egress-review'
def read(p): return Path(p).read_text(encoding='utf-8-sig')
def load(p): return json.loads(read(p))
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def csvread(n): return list(csv.DictReader(read(PKG/n).splitlines()))
def save(n,v): (OUT/n).write_text(json.dumps(v,ensure_ascii=False,indent=2),encoding='utf-8')
m=load(PKG/'manifest-r0.json'); sm=load(PKG/'source-map.json')
mode=sys.argv[1] if len(sys.argv)>1 else 'initial'
if mode in ('initial','final'):
    errors=[]; state={}; unique={}; roles=Counter()
    for f in m['files']:
        p=Path(f['path']); roles[f['role']]+=1
        h=sha(p) if p.is_file() else None; state[str(p)]=h
        if h!=f['sha256']: errors.append({'path':str(p),'expected':f['sha256'],'actual':h})
        if p in unique and unique[p]!=f['sha256']: errors.append({'conflicting_path':str(p)})
        unique[p]=f['sha256']
        if p.is_file() and p.stat().st_size!=f['size']: errors.append({'size_mismatch':str(p)})
    state[str(PKG/'manifest-r0.json')]=sha(PKG/'manifest-r0.json')
    # Dependency manifests may legitimately freeze old controls; validate their own entries,
    # never compare their old controls to today's planner controls.
    deps=[]
    for d in m['dependencies']:
        dm=load(d['manifest_path']); failed=[]
        for f in dm['files']:
            p=Path(f.get('path',f.get('snapshot_path','')))
            if not p.is_file() or sha(p)!=f['sha256']: failed.append(str(p))
        report=read(d['report_path'])
        ok=sha(d['manifest_path'])==d['manifest_sha256'] and sha(d['report_path'])==d['report_sha256'] and report.splitlines()[0]=='### 判定：PASS' and report.count('### 判定：')==1
        deps.append({'task_id':d['task_id'],'bindings_ok':ok,'entry_count':len(dm['files']),'entry_errors':failed})
    act=load(PKG/'activity-ended-r0.json')
    control=[]
    for p in (PKG/'controls').iterdir():
        origin=RUN/'planning'/p.name if p.name.startswith('task-') else RUN/p.name
        control.append({'file':p.name,'current_control_matches_frozen':sha(p)==sha(origin)})
    snap=load(RUN/'baseline'/'source-manifest.json')
    base_errors=[f['snapshot_path'] for f in snap['files'] if sha(f['snapshot_path'])!=f['sha256']]
    result={'timestamp':datetime.now(timezone.utc).isoformat(),'python':sys.version,'platform':platform.platform(),'manifest_sha256':state[str(PKG/'manifest-r0.json')],'entries':len(m['files']),'unique_paths':len(unique),'role_counts':dict(roles),'errors':errors,'dependencies':deps,'baseline_entries':len(snap['files']),'baseline_errors':base_errors,'controls':control,'activity':act}
    if mode=='final':
        before=load(OUT/'hash-state-initial.json'); result['drift']=[p for p,h in before.items() if state.get(p)!=h]
    save('hash-state-'+mode+'.json',state); save('integrity-'+mode+'.json',result)
    print(json.dumps(result,ensure_ascii=False,indent=2))
elif mode=='inspect':
    findings=load(PKG/'findings.json')['findings']
    print('FINDINGS',json.dumps(findings,ensure_ascii=False,indent=2))
    cf=load(PKG/'chain-findings.json')
    print('CHAIN_SCHEMAS',json.dumps({k:(v if not isinstance(v,(list,dict)) else {'type':type(v).__name__,'count':len(v),'first':next(iter(v.values())) if isinstance(v,dict) else v[0]}) for k,v in cf.items()},ensure_ascii=False,indent=2))
    print('SOURCE_SCHEMA',json.dumps({'source_count':len(sm['sources']),'alias_count':len(sm['inherited_source_aliases']),'source_example':next(iter(sm['sources'].values()))},ensure_ascii=False))
    for n in ('checkpoints.csv','coverage.csv','budget.csv'):
        print(n,json.dumps(csvread(n),ensure_ascii=False,indent=2))
