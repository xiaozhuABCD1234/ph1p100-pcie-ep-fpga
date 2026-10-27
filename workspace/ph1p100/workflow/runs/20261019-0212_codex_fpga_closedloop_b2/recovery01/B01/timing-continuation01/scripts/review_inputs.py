import pathlib,json,hashlib,re,difflib,subprocess
TC=pathlib.Path(__file__).resolve().parents[1]; OLD=TC.parent
ROOT=next(p for p in TC.parents if (p/'AGENTS.md').exists()); P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return p.read_text(encoding='utf-8',errors='replace')
m=json.loads(read(OLD/'candidate/manifest.json'))
changed=[{'path':e['path'],'old':e['sha256'],'new':sha(pathlib.Path(e['path']))} for e in m['entries'] if sha(pathlib.Path(e['path']))!=e['sha256']]
allowed=[str((P/x).resolve()) for x in ['rtl/ep_side/img/algo/img_algo_parallel_top.v','tools/pcie_integration/td/00_all_closedloop.tcl']]
assert sorted(e['path'] for e in changed)==sorted(allowed),changed
snap=json.loads(read(TC/'prechange-index.json'))
patch=''
for e in snap:
    src=pathlib.Path(e['path']); old=pathlib.Path(e['snapshot']); assert sha(old)==e['sha256']
    patch+=''.join(difflib.unified_diff(read(old).splitlines(True),read(src).splitlines(True),fromfile=e['snapshot'],tofile=str(src)))
(TC/'source-change.diff').write_text(patch,encoding='utf-8')
baseline=ROOT/'workflow/runs/20261018-1631_runA_fpga_side_readchannel/debug-fix3/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_chk.timing'
prev=OLD/'build/attempt3/prj/ph1p_pcie_integration_Runs/phy_1/ph1p_pcie_integration_chk.timing'
def sections(s):
    pat=r'^([0-9]+)\. checking[^\n]*\n-+\n'
    matches=list(re.finditer(pat,s,re.M));return {int(x[1]):s[x.end():matches[i+1].start() if i+1<len(matches) else len(s)] for i,x in enumerate(matches)}
bs=sections(read(baseline)); ps=sections(read(prev))
comparisons={}
for key in [1,2,10,11]:
    a=sorted(re.findall(r'^\t([^\n]+)',bs[key],re.M));b=sorted(re.findall(r'^\t([^\n]+)',ps[key],re.M))
    comparisons[str(key)]={'identical_node_sets':a==b,'baseline_nodes':a,'previous_nodes':b}
assert all(e['identical_node_sets'] for e in comparisons.values())
status=subprocess.run(['git','status','--short'],cwd=P,capture_output=True,text=True,timeout=60)
(TC/'working-tree-status.txt').write_text(status.stdout,encoding='utf-8')
result={'changed_previous_manifest_entries':changed,'previous_manifest':str(OLD/'candidate/manifest.json'),'baseline_check_timing':{'path':str(baseline),'sha256':sha(baseline)},'previous_check_timing':{'path':str(prev),'sha256':sha(prev)},'inherited_check_timing_comparisons':comparisons,'protected_manifest_no_drift_except_two_allowed_sources':True}
(TC/'input-review.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({'allowed_source_changes':len(changed),'old_other_entries_unchanged':len(m['entries'])-len(changed),'inherited_ports_clocks_equal':True}))
