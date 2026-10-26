import pathlib, hashlib, json, shutil, subprocess, ctypes, time, sys
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道').resolve()
P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
TC=pathlib.Path(__file__).resolve().parents[1]; OLD=TC.parent
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def safe(p):
    p=p.resolve(); assert p.is_relative_to(ROOT),str(p); return p
manifest=OLD/'candidate/manifest.json'; m=json.loads(manifest.read_text(encoding='utf-8'))
print('MANIFEST_KEYS',list(m)); print('ENTRY_COUNT',len(m.get('entries',[])))
drift=[]
entries=m.get('entries',m.get('files',[]))
for e in entries:
    f=pathlib.Path(e['path']).resolve()
    if sha(f)!=e['sha256']: drift.append(str(f))
assert not drift,drift
protected=json.loads((OLD/'protected-T08.json').read_text(encoding='utf-8'))
(TC/'historical-manifest.json').write_bytes(manifest.read_bytes())
(TC/'historical-protected-T08.json').write_bytes((OLD/'protected-T08.json').read_bytes())
snap=[]
for rel in ['rtl/ep_side/img/algo/img_algo_parallel_top.v','tools/pcie_integration/td/00_all_closedloop.tcl']:
    f=safe(P/rel); dst=safe(TC/'prechange'/rel); dst.parent.mkdir(parents=True,exist_ok=True)
    assert not dst.exists(); shutil.copyfile(f,dst)
    snap.append({'path':str(f),'snapshot':str(dst),'sha256':sha(f)})
(TC/'prechange-index.json').write_text(json.dumps(snap,indent=2))
for name in ['run_checks.py','run_algo_g1.py','check_build.py','run_build.py']:
    src=OLD/'scripts'/name; dst=TC/'scripts'/name; assert not dst.exists(); shutil.copyfile(src,dst)
shutil.copytree(OLD/'vectors',TC/'vectors')
(TC/'bootstrap-result.json').write_text(json.dumps({'previous_manifest_sha256':sha(manifest),'entries':len(entries),'drift':drift,'snapshot':snap,'time':time.time()},indent=2))
print('SNAPSHOT_OK',len(entries),sha(manifest))
