import pathlib, json, hashlib, time, re, subprocess, sys, importlib.util, os
ROOT=pathlib.Path(__file__).resolve().parents[4]
# Resolve from the known test-reports parent rather than a worker installation.
RUN=pathlib.Path(__file__).resolve().parents[2]
ROOT=RUN.parents[2]
OUT=pathlib.Path(__file__).resolve().parent
DEV=RUN/'recovery01/B01/timing-continuation01/remaining-attempts01'
MAN=DEV/'candidate/manifest.json'
def sha(p):
    h=hashlib.sha256()
    with pathlib.Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest()
def read(p):
    b=pathlib.Path(p).read_bytes()
    return b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig',errors='replace').replace('\r\n','\n')
def save(name,v):
    (OUT/name).write_text(json.dumps(v,indent=2,ensure_ascii=False),encoding='utf-8')
def audit():
    start=time.time();m=json.loads(read(MAN));drift=[]
    for e in m['entries']:
        if time.time()-start>60:raise TimeoutError('60s manifest audit deadline')
        p=pathlib.Path(e['path'])
        if not p.is_file() or p.stat().st_size!=e['size'] or sha(p)!=e['sha256'].lower():drift.append(str(p))
    reuse=json.loads(read(DEV/'reuse-evidence.json'));checks=[]
    for c in reuse['checks']:
        rr=pathlib.Path(c['previous_result']);result=json.loads(read(rr));log=pathlib.Path(result['log'])
        errs=[]
        if sha(rr)!=c['previous_result_sha256']:errs.append('result hash')
        if sha(log)!=c['vsim_log_sha256']:errs.append('log hash')
        txt=read(log)
        if result['exit'] or result['timeout'] or result['sim_error'] or not result['pass_marker']:errs.append('result failure')
        loaded=re.findall(r'Loading work\.([^\s(]+)',txt)
        if set(loaded)!=set(c['loaded_modules']):errs.append('loaded closure mismatch')
        for e in c['elaborated_file_closure']:
            if sha(e['path'])!=e['old_sha256'] or e['old_sha256']!=e['current_sha256']:errs.append(e['path'])
        checks.append({'tb':c['tb'],'errors':errs,'loaded':loaded,'log':str(log),'markers':[l for l in txt.splitlines() if any(k in l for k in ['PASS','648192','FAULT','CASE'])][-30:]})
    git=subprocess.run(['git','-C',str(ROOT/'upstream/ph1p100-pcie-ep-fpga'),'status','--short'],capture_output=True,text=True,timeout=60)
    save('git-status.json',{'exit':git.returncode,'stdout':git.stdout,'stderr':git.stderr})
    v={'manifest':str(MAN),'sha256':sha(MAN),'entries':len(m['entries']),'drift':drift,'reuse_checks':checks,'seconds':time.time()-start}
    save('input-audit.json',v);print(json.dumps(v,ensure_ascii=False));assert not drift and not any(c['errors'] for c in checks)
if __name__=='__main__':audit()
