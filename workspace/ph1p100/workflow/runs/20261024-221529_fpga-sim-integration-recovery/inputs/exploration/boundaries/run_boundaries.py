import pathlib, hashlib, json, shutil, subprocess, os, sys, re, time
ROOT=pathlib.Path(r'D:\fpga\ph1p100'); OUT=ROOT/'work/parallel-sim-20261024-2204/boundaries'; RUN=ROOT/'workflow/runs/20261020-0209_singleA_aplus_closedloop'; B5=RUN/'T10.b5-a1-htab-pipe/r0'; MS=pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
os.environ['PYTHONDONTWRITEBYTECODE']='1'; sys.dont_write_bytecode=True
src=OUT/'src'; src.mkdir(exist_ok=True)
expected={
'a1_deflate_core.v':'29b1e3e1a66abef78c228c4189322b0139a266d43bf02827dd1ebe498cdc9828',
'a1_frame_top.v':'c8b24775fa70793f682f1a640be175ec53f304722539cbd89550e0d4aefca65b',
'a1_raw_crop.v':'ca2f5d1656cd3b247707e3abd86b2d543e4b0da518cd835513308bd6ff6ebd01',
'a1_ddr_slot_store.v':'8bab440d528a192d558081ab0b52f96d9116d3bb5713c821e2fa74a97f74d09a',
'a1_ddr_arb2.v':'6513ad839dee02e932c49bdfd5afa3d62c382d4a144b8e74d5574273804afdc6',
'a1_uart_export.v':'3dad065f2ff5d8ccf5ff1b0182b4a6091476bada48a948ff4f1b09c62440c15f',
'camera_a1_uart_top.v':'b10416762bcae2de19d3ad36b73591ae607effc4667a5c8e07c6a56499c2e6eb',
'capture_async_fifo.v':'59dd6dcb5b7e7774f7d6518f50f56cafbc8be6b70e8ae1508236bac2b5af531d'}
files=[ROOT/'fpga/csi2/src/a1'/n for n in ['a1_raw_crop.v','a1_ddr_slot_store.v','a1_ddr_arb2.v','a1_uart_export.v','camera_a1_uart_top.v']]
files += [ROOT/'fpga/csi2/src/mem/capture_async_fifo.v',B5/'changed-src/a1_deflate_core.v',ROOT/'upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v']
files += [RUN/'T10.b1-a1-uart-integ/r0/sim'/n for n in ['a1_ddr_model.v','tb_camera_a1_uart_top.v']]
files += [ROOT/'tools/a1'/n for n in ['pc_decode.py','a1_pattern.py']]
report={'scope':'exploratory offline integration boundary coverage; not formal acceptance or hardware verification','input_manifest':str(B5/'CANDIDATE-MANIFEST-b5-a1-htab-pipe-r0.json'),'inputs':[],'commands':[],'cases':[],'limitations':['MODE3/4 not exercised: original TB has no independent branch.','Write-in-progress reset recovery not executed within bounded scope.','No TD, bitstream, board download, RK work, or production RTL changes.'],'status':'RUNNING'}
prior=json.loads((OUT/'result.json').read_text()) if (OUT/'result.json').exists() else {}
report['commands'] += [dict(x,reused_actual_simulation=True) for x in prior.get('commands',[]) if x.get('argv',[''])[0].endswith('vsim.exe')]
for p in files:
    h=hashlib.sha256(p.read_bytes()).hexdigest(); dst=src/p.name
    rec={'source':str(p),'snapshot':str(dst),'sha256':h,'frozen_expected':expected.get(p.name),'bytes':p.stat().st_size}
    if p.name in expected and h!=expected[p.name]: raise RuntimeError('FROZEN_HASH_MISMATCH '+str(rec))
    shutil.copyfile(p,dst); report['inputs'].append(rec)
(OUT/'input-hashes.json').write_text(json.dumps(report['inputs'],indent=2))
ini=OUT/'modelsim.ini'; ini.write_text('[Library]\nwork = '+(OUT/'lib').as_posix()+'\n[vsim]\nResolution = ps\n'); (OUT/'run.do').write_text('run -all\nquit -f\n')
env=os.environ.copy(); env['MODELSIM']=ini.as_posix()
def run(args,name,timeout=300):
    cmd=[x.as_posix() if isinstance(x,pathlib.Path) else str(x) for x in args]; log=OUT/(name+'.console.log'); entry={'argv':cmd,'cwd':str(OUT),'timeout_seconds':timeout,'console':str(log)}; report['commands'].append(entry); start=time.monotonic()
    with log.open('w') as f:
        proc=subprocess.Popen(cmd,cwd=OUT,stdout=f,stderr=subprocess.STDOUT,env=env)
        try: rc=proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT,timeout=15); entry['timed_out']=True; rc=-1
    entry.update(returncode=rc,elapsed_seconds=round(time.monotonic()-start,3))
    if rc: raise RuntimeError(name+' returncode '+str(rc)+' see '+str(log))
    return log.read_text(errors='replace')
def save():
    (OUT/'result.json').write_text(json.dumps(report,indent=2)); lines=['# Exploratory FPGA integration boundary simulation','','Status: '+report['status'],'','Frozen r5 DUT sources checked against manifest SHA256 before snapshot/compile.','Tool: ModelSim Intel FPGA 10.5b. Independent absolute-path work library and modelsim.ini.','No existing script executed; only newly authored runner/do file with no delete operations.','']
    for c in report['cases']: lines += ['## '+c['name'],'','```json',json.dumps(c,indent=2),'```','']
    lines += ['## Limits','']+['- '+x for x in report['limitations']]+['','See result.json for exact source SHA256 and commands; all evidence is under this output directory.']
    if 'error' in report: lines+=['','Error: '+report['error']]
    (OUT/'result.md').write_text('\n'.join(lines))
try:
    run([MS/'vlib.exe',OUT/'lib'],'vlib'); vlog=run([MS/'vlog.exe','-modelsimini',ini,'-work','work']+[src/p.name for p in files if p.suffix=='.v'],'vlog')
    if 'Errors: 0, Warnings: 0' not in vlog: raise RuntimeError('Compiler summary not clean; inspect vlog.console.log')
    # The original reference generator pads absent planes and inverse unconditionally reads them.
    # Frozen DUT explicitly has TAIL=H%2 and sends W samples for final odd row.
    checker=OUT/'checker'; checker.mkdir(exist_ok=True)
    pattern=(src/'a1_pattern.py').read_text()
    pattern=pattern.replace('planes.append([0] * halfw)', 'planes.append([])')
    pattern=pattern.replace('y = y0 + (p >> 1)\n                prev = 0', 'y = y0 + (p >> 1)\n                if y >= h:\n                    continue\n                prev = 0')
    (checker/'a1_pattern.py').write_text(pattern)
    shutil.copyfile(src/'pc_decode.py',checker/'pc_decode.py')
    report['checker_adaptation']={'reason':'Odd-height tail has only two planes; original expected_xform inserts nonexistent zero planes and inverse_xform indexes beyond actual 30-byte transform.','original_a1_pattern_sha256':hashlib.sha256((src/'a1_pattern.py').read_bytes()).hexdigest(),'adapted_a1_pattern_sha256':hashlib.sha256((checker/'a1_pattern.py').read_bytes()).hexdigest(),'changes':['expected_xform: absent plane -> empty, no padding','inverse_xform: skip plane whose row >= h'],'production_files_modified':False}
    sys.path.insert(0,str(checker)); import pc_decode, a1_pattern
    cases=[dict(name='odd8x3',mode=0,cam_w=16,cam_h=8,roi_x=4,roi_y=2,w=8,h=3),dict(name='random64x8',mode=1,cam_w=80,cam_h=16,roi_x=4,roi_y=2,w=64,h=8)]
    for c in cases:
        name=c['name']; geom={k:c[k] for k in ['cam_w','cam_h','roi_x','roi_y','w','h']}; args=[MS/'vsim.exe','-c','-modelsimini',ini,'-wlf',OUT/(name+'.wlf'),'-l',OUT/(name+'.transcript'),'work.tb_camera_a1_uart_top']
        args += ['-g'+k.upper()+'='+str(v) for k,v in geom.items()]; args += ['-gMAX_CYCLES=1000000','+MODE='+str(c['mode']),'+OUT='+(OUT/(name+'.dec')).as_posix(),'+STAT='+(OUT/(name+'.stats')).as_posix(),'-do','do '+(OUT/'run.do').as_posix()]
        log=(OUT/(name+'.console.log')).read_text(errors='replace') if (OUT/(name+'.dec')).exists() else run(args,name); stat=(OUT/(name+'.stats')).read_text(); stats={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',stat)}; data=pc_decode.read_bytes(OUT/(name+'.dec')); frames,tail=pc_decode.decode_stream(data,str(OUT/(name+'_decoded'))); raw=a1_pattern.expected_raw(c['mode'],geom); xf=a1_pattern.expected_xform(c['mode'],1,1,geom)
        checks={'tb_done':'TB_DONE' in log,'no_timeout':not re.search('TIMEOUT|TB_OPEN_FAIL',log),'one_frame':len(frames)==1,'no_half_frame':tail==0,'captured_length':stats.get('cap_bytes')==len(data),'one_export':stats.get('exported')==1,'raw_pub':stats.get('raw_pub')==1,'cap_enc':stats.get('cap')==stats.get('enc')==1,'no_drop_geom_errors':all(stats.get(k)==0 for k in ['raw_drop','cmp_drop','geom','err','dup_words'])}
        if frames:
            f=frames[0]; d=pathlib.Path(f['dir']); pay=(d/'stream.zlib').read_bytes(); checks.update({k:f[k] for k in ['header_crc_ok','stream_crc_ok','xform_crc_ok','raw_crc_ok','zlib_ok','raw_len_ok','xform_len_ok','worstcase_ok']})
            checks.update(raw_exact=(d/'raw.bin').read_bytes()==raw,xform_exact=(d/'xform.bin').read_bytes()==xf,header_geometry=f['width']==c['w'] and f['height']==c['h'],export_bytes=stats.get('exp_bytes')==f['stream_len'],stream_length=len(data)==44+f['stream_len'],read_words=stats.get('read_words')==((c['w']*c['h']//4+3)//4))
            c.update(first_deflate_btype=(pay[2]>>1)&3,stored_first_block=((pay[2]>>1)&3)==0,decoded=f,expected_raw_sha256=hashlib.sha256(raw).hexdigest(),expected_xform_sha256=hashlib.sha256(xf).hexdigest())
            if c['mode']==1: checks['stored_fallback_observed']=c['stored_first_block']
        c.update(stats=stats,capture_bytes=len(data),capture_sha256=hashlib.sha256(data).hexdigest(),trailing_bytes=tail,checks=checks,status='PASS' if all(checks.values()) else 'FAIL'); report['cases'].append(c); save(); print(name,c['status'],stat.strip(),flush=True)
        if c['status']!='PASS': raise RuntimeError(name+' semantic check failed; stopped without production RTL modification')
    report['status']='PASS_EXPLORATORY'; save()
except Exception as exc:
    report['status']='FAIL_OR_BLOCKED'; report['error']=str(exc); save(); print('STOP:',str(exc),flush=True); sys.exit(1)

