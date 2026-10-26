"""Prepared board entry; never called by B01 offline development."""
import pathlib,argparse,json,hashlib,subprocess,time,sys,os
REC=pathlib.Path(__file__).resolve().parents[1];RUN=REC.parents[2]
p=argparse.ArgumentParser();p.add_argument('--report',action='append');p.add_argument('--execute',action='store_true');a=p.parse_args()
mf=REC/'candidate/manifest.json';m=json.loads(mf.read_text(encoding='utf-8'));mh=hashlib.sha256(mf.read_bytes()).hexdigest()
if not a.report:
    a.report=[]
    for task in ['T06.codex-ddr-readback-int','T09.codex-production-int']:
        matches=[]
        for f in (RUN/'test-reports').rglob('*.md'):
            if task not in f.name:continue
            text=f.read_text(encoding='utf-8-sig')
            if text.splitlines() and text.splitlines()[0]=='### 判定：PASS' and mh in text.lower() and 'integrated' in text.lower():matches.append(str(f))
        assert len(matches)==1,(task,'requires exactly one integrated PASS report with this task_id in filename and this manifest SHA',matches)
        a.report.extend(matches)
assert m['frozen'] and m['ready_for_test'] and len(a.report)==2
assert len(set(str(pathlib.Path(r).resolve()) for r in a.report))==2,'two distinct integrated reports required'
for task,r in zip(['T06.codex-ddr-readback-int','T09.codex-production-int'],a.report):
    report=pathlib.Path(r).resolve();assert report.is_relative_to((RUN/'test-reports').resolve())
    text=report.read_text(encoding='utf-8-sig');assert text.splitlines()[0]=='### 判定：PASS' and mh in text.lower() and task in text and 'integrated' in text.lower(),str(report)
for entry in m['entries']:
    path=pathlib.Path(entry['path']).resolve()
    assert path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256'],str(path)
bit=REC/'candidate/current.bit';cwc=REC/'candidate/current.cwc'
for path in [bit,cwc]:
    entry=next(e for e in m['entries'] if pathlib.Path(e['path']).resolve()==path.resolve())
    assert hashlib.sha256(path.read_bytes()).hexdigest()==entry['sha256']
if not a.execute:print('Validated reports and candidate; --execute required by separately dispatched board task.');sys.exit(0)
drive=next((d for d in 'ZYXWVUTSR' if not pathlib.Path(d+':/').exists()),None);assert drive,'no free owned ASCII mapping'
subprocess.run(['subst',drive+':',str(REC)],check=True,timeout=10)
out=RUN/'board'/('sram-b01-'+time.strftime('%Y%m%dT%H%M%S'));assert out.resolve().is_relative_to(RUN.resolve());out.mkdir(parents=True,exist_ok=False)
cmd=['D:/anlogic/TD_Release_2026.2/bin/bw.exe','board/download_sram.tcl'];t=time.time()
try:
    with (out/'download.log').open('w',encoding='utf-8') as log:
        log.write(json.dumps({'command':cmd,'cwd':drive+':/','manifest_sha256':mh,'deadline_seconds':120})+'\n');log.flush()
        proc=subprocess.Popen(cmd,cwd=drive+':/',stdout=log,stderr=subprocess.STDOUT,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
        log.write('OWN_PID='+str(proc.pid)+'\n');log.flush()
        try:code=proc.wait(timeout=120);timeout=False
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=log,stderr=log,timeout=20);code=proc.wait(timeout=20);timeout=True
    text=(out/'download.log').read_text(encoding='utf-8',errors='replace');ok=code==0 and not timeout and 'B01_SRAM_PASS' in text
    result={'exit':code,'timeout':timeout,'pass':ok,'elapsed_seconds':time.time()-t,'manifest_sha256':mh}
    (out/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result));sys.exit(0 if ok else 1)
finally:subprocess.run(['subst',drive+':','/D'],check=False,timeout=10)
