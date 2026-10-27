import pathlib,hashlib,json,re,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[4];OUT=pathlib.Path(__file__).resolve().parents[1];P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def run(cmd):
    a=subprocess.run(cmd,cwd=P,capture_output=True,text=True,timeout=60)
    return {'command':cmd,'cwd':str(P),'exit':a.returncode,'stdout':a.stdout,'stderr':a.stderr}
assert P.resolve().is_relative_to(ROOT.resolve())
for rel,expect in {'rtl/ep_side/img/ep_bar_win.v':'285fc9f009bd5c2481dbc25ee1c7ddd809a70b328b12dca63c0bd59baf581717','rtl/ep_side/pcie_ep_engine.v':'4c9d2e35d181929393b55047e67cfe59d389afe19d06032ac3ec95c9deca9b85','sim/tb/tb_ep_bar_win_debug.v':'3aa3e11b49ec57652efdc88f34c5d6e8b7a30e640cfcc2549e4b3dadc5a6355e'}.items():assert sha(P/rel)==expect,rel
evidence=[]
for f in sorted((OUT/'ddr-integration/g1').glob('*/vsim.log')):
    s=f.read_text(errors='replace');evidence.append({'path':str(f),'sha256':sha(f),'pass':('PASS' in s and 'FAIL' not in s and '** Error' not in s),'markers':[x for x in s.splitlines() if 'PASS' in x or 'FAIL' in x or '** Error' in x][:15]})
for f in sorted((OUT/'algo-integration/g1').glob('*/report.json')):evidence.append({'path':str(f),'sha256':sha(f),'result':json.loads(f.read_text())})
versions=[run(['D:/intelFPGA/18.1/modelsim_ase/win32aloem/vsim.exe','-version']),run(['C:/Program Files/Python311/python.exe','--version'])]
state=run(['git','status','--short']);head=run(['git','rev-parse','HEAD']);assert head['stdout'].strip()=='b0282d2a8dfdf11e6e63779510fe380dfffb5e83'
(OUT/'candidate/evidence-index.json').write_text(json.dumps({'evidence':evidence,'tool_versions':versions,'worktree_status':state,'head':head,'td':{'attempts':0,'reason':'required integrated G1 did not compile within command retry bound'},'hardware_actions':[]},indent=2))
inputs=set()
for base in [P/'rtl',P/'constraints',P/'al_ip']:
    for f in base.rglob('*'):
        if f.is_file():inputs.add(f)
for f in (P/'sim').rglob('*'):
    if f.is_file() and f.suffix.lower() in {'.v','.sv','.f','.hex','.mem'}:inputs.add(f)
for f in (P/'tools/pcie_integration').rglob('*'):
    if f.is_file() and f.suffix.lower() in {'.ps1','.py','.tcl'}:inputs.add(f)
for rel in ['request.md','input-index.md','dev-plan.md','fpga-design-guide.md','lessons-learned.md','ddr-integration/development-report.md','ddr-integration/baseline-verified.json','algo-integration/development-report.md','algo-integration/source-provenance.json','candidate/probe-map.md','candidate/evidence-index.json','candidate/development-result.json','board/two-click-checklist.md']:
    inputs.add(OUT/rel)
inputs.update((OUT/'scripts').glob('*.py'))
for f in (ROOT/'tools/algo').rglob('*'):
    if f.is_file() and f.suffix in {'.py','.sv'}:inputs.add(f)
entries=[]
for f in sorted(inputs):
    assert f.resolve().is_relative_to(ROOT.resolve()),str(f)
    entries.append({'path':str(f),'size':f.stat().st_size,'sha256':sha(f)})
manifest={'batch_id':'B01','task_ids':['T06.codex-ddr-readback-int','T09.codex-production-int'],'round':0,'frozen':True,'ready_for_test':False,'status':'blocked','manifest_kind':'blocked-development-inputs','project_root':str(ROOT),'worktree':str(P),'head':head['stdout'].strip(),'bit':None,'cwc':None,'final_database':None,'g2':'not_run','entries':entries,'blocking_problem':'T06.codex-ddr-readback-int:LIMIT_REACHED:integrated-tb-compile','note':'Partial development freeze; not a qualified production or board candidate. No further same-command retry authorized in this invocation.'}
mf=OUT/'candidate/manifest.json';mf.write_text(json.dumps(manifest,indent=2))
checks=[{'path':e['path'],'match':sha(pathlib.Path(e['path']))==e['sha256']} for e in entries]
check={'manifest_path':str(mf),'manifest_sha256':sha(mf),'entries':len(entries),'ok':all(x['match'] for x in checks),'mismatches':[x for x in checks if not x['match']],'activities_finished':True}
(OUT/'candidate/manifest-selfcheck.json').write_text(json.dumps(check,indent=2))
print(json.dumps(check))
