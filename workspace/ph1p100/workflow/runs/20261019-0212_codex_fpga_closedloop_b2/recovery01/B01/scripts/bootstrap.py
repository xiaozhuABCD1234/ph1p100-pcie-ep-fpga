import pathlib,hashlib,json,shutil,subprocess
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道')
RUN=ROOT/'workflow/runs/20261019-0212_codex_fpga_closedloop_b2'
REC=RUN/'recovery01/B01';P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert REC.resolve().is_relative_to(ROOT.resolve()) and P.resolve().is_relative_to(ROOT.resolve())
old=RUN/'candidate/manifest.json'; m=json.loads(old.read_text())
ledger=[]
for e in m['entries']:
    src=pathlib.Path(e['path']);assert src.resolve().is_relative_to(ROOT.resolve())
    actual=sha(src);assert actual==e['sha256'],str(src)
    dest=RUN/'recovery01/prechange'/src.relative_to(ROOT)
    dest.parent.mkdir(parents=True,exist_ok=True)
    if dest.exists():assert sha(dest)==actual
    else:shutil.copyfile(src,dest)
    ledger.append({'path':str(src),'sha256':actual,'backup':str(dest)})
shutil.copyfile(old,REC/'historical-manifest.json')
(REC/'prechange-index.json').write_text(json.dumps({'historical_manifest':str(old),'historical_manifest_sha256':sha(old),'entries':ledger},indent=2))
sync=RUN/'sync-offline/manifest.json'
protected=[]
if sync.exists():
    sm=json.loads(sync.read_text(encoding='utf-8-sig'))
    for e in sm.get('entries',[]):
        path=pathlib.Path(e.get('path',e.get('absolute_path','')))
        if not path.is_absolute():path=ROOT/path
        if path.is_file():protected.append({'path':str(path),'sha256':sha(path)})
(REC/'protected-T08.json').write_text(json.dumps({'manifest':str(sync),'manifest_sha256':sha(sync) if sync.exists() else None,'entries':protected},indent=2))
f=P/'sim/tb/tb_closedloop_writer_checker.v';s=f.read_text(encoding='utf-8')
beg=s.index('    wire [1:0] rb_release;');end=s.index('    always @(posedge clk_ddr)',beg)
declarations=s[beg:end];s=s[:beg]+s[end:]
instance=s.index(') u_wr3 (');where=s.rfind('    cam_r10f_writer #(',0,instance)
assert where>=0 and 'always' not in declarations
s=s[:where]+declarations+'\n'+s[where:]
f.write_text(s,encoding='utf-8',newline='\n')
print(json.dumps({'backed_up':len(ledger),'protected_T08':len(protected),'fixed':str(f),'historical_attempts':2,'next_attempt':3}))
