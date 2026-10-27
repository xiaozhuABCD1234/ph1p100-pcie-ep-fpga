import pathlib,json,re,hashlib
TC=pathlib.Path(__file__).resolve().parents[1];OLD=TC.parent
ROOT=next(p for p in TC.parents if (p/'AGENTS.md').is_file());P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
mods={}
for base in [P/'rtl',P/'sim']:
    for f in base.rglob('*'):
        if f.is_file() and f.suffix in {'.v','.sv'}:
            for name in re.findall(r'^\s*module\s+(\w+)',f.read_text(encoding='utf-8',errors='replace'),re.M):mods.setdefault(name,[]).append(f.resolve())
required=['tb_closedloop_writer_checker','tb_closedloop_control','tb_ep_bar_win_debug','tb_ddr_frame_readback_checker','tb_ddr_frame_pusher_rka1','tb_ddr_wr_arb_peer','tb_ep_bar_win_rka1','tb_csi_checked','tb_t11_csi_enable_corner','tb_csi_integrity_diff','tb_t11_r10f_e2e']
results=[]
for tb in required:
    path=sorted(p for p in (OLD/'g1').glob('*/result.json') if readj(p)['tb']==tb)[-1]
    r=readj(path);assert r['pass_marker'] and not r['sim_error'] and not r['timeout'] and r['exit']==0
    log=path.parent/'vsim.log';loaded=sorted(set(re.findall(r'Loading work\.(\w+)',log.read_text(encoding='utf-8',errors='replace'))))
    old={str(pathlib.Path(e['path']).resolve()):e['sha256'] for e in readj(path.parent/'inputs.json')}
    closure=[];unknown=[];drift=[]
    for name in loaded:
        if name not in mods:unknown.append(name)
        for f in mods.get(name,[]):
            e={'module':name,'path':str(f),'old_sha256':old.get(str(f)),'current_sha256':sha(f)}
            closure.append(e)
            if e['old_sha256']!=e['current_sha256']:drift.append(e)
    assert not unknown and not drift,(tb,unknown,drift)
    results.append({'tb':tb,'previous_result':str(path),'previous_result_sha256':sha(path),'vsim_log_sha256':sha(log),'loaded_modules':loaded,'elaborated_file_closure':closure,'closure_unchanged':True,'changed_algorithm_module_elaborated':'img_algo_parallel_top' in loaded,'independent_tester_reuse_decision':'pending; author supplies binding evidence, not independent acceptance'})
(TC/'reuse-evidence.json').write_text(json.dumps({'checks':results,'rule':'Use actual ModelSim loaded modules, not every unelaborated file in compile_checked.f. Hash every resolved module file against that run inputs.json. Include/TB/runner/vector bytes are separately bound by frozen manifests; original 415-entry comparison finds only img_algo_parallel_top and closedloop stage changed.'},indent=2),encoding='utf-8')
print('REUSE_CLOSURES',len(results),'all unchanged; independent decision pending')
