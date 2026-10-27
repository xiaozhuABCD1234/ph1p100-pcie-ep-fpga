import pathlib,json,hashlib,shutil,time,datetime
N=pathlib.Path(__file__).resolve().parents[1];O=N.parent;R=O.parents[2];ROOT=next(p for p in N.parents if (p/'AGENTS.md').exists());P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
m=readj(O/'candidate/manifest.json');assert len(m['entries'])==527
assert all(sha(pathlib.Path(e['path']))==e['sha256'] for e in m['entries'])
start=1792408201.0
window={'start_epoch':start,'start_utc':'2026-10-19T11:10:01Z','deadline_epoch':start+9000,'deadline_utc':'2026-10-19T13:40:01Z','new_minutes_cap':150,'new_tools_cap':150,'old_window_preserved':readj(R/'production-remaining-attempts01-ledger.json')['old_role_window'],'cumulative_minutes_cap':390,'cumulative_engineering_tools_cap':300,'production_used_at_start':4,'production_max':6,'old_exact_tools':'not fabricated; old conservative reserve100 at audit plus final collection. Preserve original records.','new_tool_inventory':'Count all native tool calls in this followup; no reset of earlier windows.'}
(N/'role-window-ledger.json').write_text(json.dumps(window,indent=2),encoding='utf-8')
(N/'historical-manifest.json').write_bytes((O/'candidate/manifest.json').read_bytes())
paths=['rtl/ep_side/img/algo/img_algo_parallel_top.v','rtl/ep_side/img/algo/bayer_raw10_demosaic4.v','rtl/ep_side/img/algo/rgb8_gray_stream.v','rtl/ep_side/img/algo/algo_rowwin3.v','tools/pcie_integration/td/00_all_closedloop.tcl']
snap=[]
for rel in paths:
    f=(P/rel).resolve();dst=(N/'prechange'/rel).resolve();assert f.is_relative_to(ROOT) and dst.is_relative_to(N)
    dst.parent.mkdir(parents=True,exist_ok=True);assert not dst.exists();shutil.copyfile(f,dst);snap.append({'path':str(f),'snapshot':str(dst),'sha256':sha(f)})
(N/'prechange-index.json').write_text(json.dumps(snap,indent=2),encoding='utf-8')
for name in ['run_checks.py','run_algo_g1.py','check_build.py','run_build.py','run_sram.py']:
    shutil.copyfile(O/'scripts'/name,N/'scripts'/name)
shutil.copytree(O/'vectors',N/'vectors');shutil.copytree(O/'board',N/'board')
records={}
for f in readj(R/'dispatch-production-remaining-attempts01.json')['input_paths']:
    p=pathlib.Path(f); data=p.read_bytes();records[str(p)]={'sha256':sha(p),'bytes':len(data)}
    if p.suffix=='.md' and p.name not in ['production-timing-continuation01-plan.md']: print(p.name,data.decode('utf-8-sig')[:900])
(N/'input-read-index.json').write_text(json.dumps(records,indent=2),encoding='utf-8')
print('BOOTSTRAP527_OK',sha(O/'candidate/manifest.json'),'SNAPSHOTS',len(snap))
