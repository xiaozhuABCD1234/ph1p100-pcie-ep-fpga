import csv, hashlib, json, pathlib, sys, subprocess, datetime, re
ROOT=pathlib.Path('D:/fpga/ph1p100')
RUN=ROOT/'workflow/runs/20261026-144617_fpga-chain-detail-review'
PKG=RUN/'T10.chain-transform-review'
OUT=RUN/'test-reports/T10.chain-transform-review'
def read(p): return json.loads(pathlib.Path(p).read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def save(n,o): (OUT/n).write_text(json.dumps(o,ensure_ascii=False,indent=2),encoding='utf-8')
def scan():
    manifest=read(PKG/'manifest-r0.json'); errors=[]; checked=[]
    manifests=[PKG/'manifest-r0.json',RUN/'T02.chain-input-review/manifest-r0.json',RUN/'T06.chain-storage-review/manifest-r0.json']
    for m in manifests:
        for f in read(m)['files']:
            p=pathlib.Path(f['path']); h=sha(p)
            if h!=f['sha256'].lower() or p.stat().st_size!=f['size']: errors.append(str(p))
            checked.append({'path':str(p),'sha256':h})
    base=read(RUN/'baseline/source-manifest.json')
    for f in base['files']:
        if sha(f['snapshot_path'])!=f['sha256']: errors.append(f['snapshot_path'])
    bindings=[]
    for n in ['control-bindings.json','recovery-control-bindings.json']:
        for b in read(PKG/n):
            snap=sha(b['snapshot_path']); src=sha(b['source_path']); allowed=b['source_path'].endswith('dispatch.json') and n=='control-bindings.json'
            if snap!=b['sha256'] or (src!=snap and not allowed): errors.append(b['snapshot_path'])
            bindings.append({'path':b['snapshot_path'],'snapshot_sha256':snap,'source_sha256':src,'historical_dispatch':allowed})
    for d in read(RUN/'dispatch.json')['completed_dependencies']:
        for n in ['manifest','report']:
            if sha(d[n+'_path'])!=d[n+'_sha256']: errors.append(d[n+'_path'])
    ended=read(PKG/'activity-ended-r0.json')
    assert ended['stopped_modifying'] and manifest['development_modification_stopped']
    assert ended['activity_ended_utc']<=manifest['frozen_utc'] and ended['pending_worker_operations']==0 and ended['owned_build_sim_hardware_processes']==0
    refs=[]; checkpoints=list(csv.DictReader((PKG/'checkpoints.csv').open(encoding='utf-8-sig',newline='')))
    findings=read(PKG/'findings.json')['findings']
    for c in checkpoints:
        if any(v is None or str(v).strip()=='' for v in c.values()): errors.append('empty checkpoint '+str(c))
    for f in findings:
        for x in f['evidence_refs']:
            p=pathlib.Path(x['snapshot_path']); lines=p.read_text(encoding='utf-8-sig').splitlines()
            ok=sha(p)==x['sha256'] and 1<=x['line_start']<=x['line_end']<=len(lines)
            if not ok: errors.append(f['finding_id']+':ref')
            refs.append({'finding_id':f['finding_id'],**x,'ok':ok})
    # All checkpoint references have one frozen source and range.
    for c in checkpoints:
        pathkey=next(k for k in c if 'path' in k); p=pathlib.Path(c[pathkey]); sk=next(k for k in c if 'sha' in k)
        lk=[k for k in c if 'line' in k]
        ok=sha(p)==c[sk] and 1<=int(c[lk[0]])<=int(c[lk[1]])<=len(p.read_text(encoding='utf-8-sig').splitlines())
        if not ok: errors.append('checkpoint ref '+str(c))
    status=subprocess.run(['git','status','--short','--untracked-files=no'],cwd=ROOT,capture_output=True,timeout=60).stdout
    head=subprocess.run(['git','rev-parse','HEAD'],cwd=ROOT,capture_output=True,text=True,timeout=60).stdout.strip()
    branch=subprocess.run(['git','branch','--show-current'],cwd=ROOT,capture_output=True,text=True,timeout=60).stdout.strip()
    result={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'manifest_sha256':sha(PKG/'manifest-r0.json'),'frozen_entry_checks':len(checked),'unique_paths':len({x['path'] for x in checked}),'baseline_entries':len(base['files']),'bindings':bindings,'errors':errors,'stopped_record':ended,'manifest_frozen_utc':manifest['frozen_utc'],'checkpoints':len(checkpoints),'finding_refs':len(refs),'findings':len(findings),'head':head,'branch':branch,'tracked_status_sha256':hashlib.sha256(status).hexdigest(),'tracked_status_lines':len(status.splitlines()),'file_hashes':checked}
    save('references.json',refs)
    save(sys.argv[1] if len(sys.argv)>1 else 'integrity-before.json',result)
    print(json.dumps({k:v for k,v in result.items() if k not in ['file_hashes','bindings']},ensure_ascii=False))
    assert not errors,errors
    print('T10_INDEPENDENT_INTEGRITY_COMPLETE')
if __name__=='__main__': scan()
