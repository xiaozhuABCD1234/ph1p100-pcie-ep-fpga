import os, sys, json, time, pathlib, hashlib, subprocess, zlib, shutil

root = pathlib.Path(r'D:\fpga\ph1p100')
pkg = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw'
ev = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-evidence'
# SHORT run dir: tb_camera_a1_uart_top declares reg [1023:0] stat_path/out_path (=128 chars max)
short = pathlib.Path(r'C:\Users\czz\AppData\Local\Temp\opencode\b6t')
sim = short/'s'
sim.mkdir(parents=True, exist_ok=True)
logs = sim/'log'; logs.mkdir(exist_ok=True)
print('path lens: sim=%d, worst case=%d' % (len(str(sim)), len(str(sim/'mid64x8.stats'))), flush=True)
core = pkg/'r0/changed-src/a1_deflate_core.v'
up = root/'upstream/ph1p100-pcie-ep-fpga'
p2 = root/'work/parallel-sim-20261024-2204/codec-throughput'
ms = pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
env = os.environ.copy(); env['MODEL_TECH'] = str(ms)
ini = p2/'modelsim.ini'; env['MODELSIM'] = str(ini)
env['PATH'] = str(ms) + os.pathsep + env.get('PATH', '')
cmds = []

def run(tag, args, cwd, timeout=900):
    args = [str(a).replace(chr(92), '/') for a in args]
    t0 = time.monotonic(); rec = dict(tag=tag, argv=args, cwd=str(cwd), timeout_seconds=timeout)
    with open(logs/(tag+'.stdout.log'), 'wb') as o, open(logs/(tag+'.stderr.log'), 'wb') as e:
        pr = subprocess.Popen(args, cwd=str(cwd), env=env, stdout=o, stderr=e,
                              creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            rec['exit_code'] = pr.wait(timeout=timeout); rec['timed_out'] = False
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill', '/PID', str(pr.pid), '/T', '/F'], capture_output=True, timeout=20)
            rec['exit_code'] = 124; rec['timed_out'] = True
    rec['elapsed_seconds'] = round(time.monotonic()-t0, 2); cmds.append(rec)
    print(tag, 'exit', rec['exit_code'], rec['elapsed_seconds'], 's', flush=True)

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def stats(p):
    d = {}
    p = pathlib.Path(p)
    if not p.exists(): return {'_missing': str(p)}
    for line in p.read_text(errors='replace').splitlines():
        if line.strip():
            parts = line.split()
            try: d[parts[0]] = int(parts[1]) if len(parts) == 2 else ' '.join(parts[1:])
            except (ValueError, IndexError): d[parts[0]] = ' '.join(parts[1:])
    return d

def real_errors(logp):
    out = []
    for ln in pathlib.Path(logp).read_text(errors='replace').splitlines():
        if 'TB_OPEN_FAIL' in ln or 'Failed to open' in ln: out.append(ln.strip())
        elif '** Error' in ln or '** Fatal' in ln or 'FATAL' in ln: out.append(ln.strip())
        elif ln.strip().startswith('# Errors:') and not ln.strip().startswith('# Errors: 0'): out.append(ln.strip())
    return out

out = dict(task='T10.b6-a1-htab-nw', tester='independent integrated tester r0 (general stand-in)',
           core_sha256=sha(core), core_bytes=core.stat().st_size, run_dir=str(sim), p2={}, p1={}, commands=cmds)
print('tester core sha', out['core_sha256'], out['core_bytes'], flush=True)

# ---------------- P2
w2 = short/'w2'
run('vlib_p2', [ms/'vlib.exe', w2], short)
run('vlog_p2', [ms/'vlog.exe', '-modelsimini', ini, '-work', w2, core,
                up/'sim/tb/codec/tb_a1_deflate_core.v'], short)
for case in ['comp', 'rand']:
    cd = p2/case; logp = logs/('sim_p2_'+case+'.log')
    run('vsim_p2_'+case, [ms/'vsim.exe', '-c', '-modelsimini', ini, '-lib', w2, '-l', logp,
                          'tb_a1_deflate_core',
                          '+IN='+str(cd/'in.hex'), '+META='+str(cd/'in.meta'),
                          '+OUT='+str(sim/(case+'.out.hex')), '+STAT='+str(sim/(case+'.stats.txt')),
                          '+BP=0', '+GAP=0', '+TIMEOUT=2000000', '-do', 'run -all; quit -f'], short, timeout=900)
    st = stats(sim/(case+'.stats.txt'))
    stream = bytes(int(x, 16) for x in (sim/(case+'.out.hex')).read_text().split())
    expected = (cd/'in.xform').read_bytes()
    zok = False; zm = None; ze = ''; eof = False; zlen = 0
    try:
        dec = zlib.decompressobj(); zout = dec.decompress(stream)+dec.flush()
        eof = dec.eof; zlen = len(zout)
        zok = eof and not dec.unused_data and not dec.unconsumed_tail
        zm = sum(a != b for a, b in zip(zout, expected))+abs(len(zout)-len(expected))
    except Exception as ex:
        ze = str(ex)
    cyc = st.get('run_cycles'); n = st.get('in_bytes')
    tb_ok = (st.get('done') == 1 and st.get('out_last') == 1 and st.get('timeout_hit') == 0
             and n == len(expected) and st.get('bp') == 0 and st.get('gap') == 0)
    devstream = pkg/('r0/sim/'+case+'.out.hex')
    dev_bytes = bytes(int(x, 16) for x in devstream.read_text().split()) if devstream.exists() else b''
    out['p2'][case] = dict(stats=st, tb_pass=tb_ok, output_bytes=len(stream),
                           output_sha256=hashlib.sha256(stream).hexdigest(), zlib_ok=zok, zlib_eof=eof,
                           zlib_err=ze, zlib_mismatch=zm, zlib_out_len=zlen, xform_len=len(expected),
                           identical_to_dev_stream=(stream == dev_bytes), run_cycles=cyc,
                           MBps_at_187p5MHz=(n/cyc*187.5 if cyc else None),
                           log_errors=real_errors(logp))
    print(case, 'cycles', cyc, 'bytes', len(stream), 'sha', out['p2'][case]['output_sha256'],
          'tb', tb_ok, 'zlib', zok, zm, 'matches', st.get('stat_matches'), flush=True)

# ---------------- P1
w1 = short/'w1'
src = root/'fpga/csi2/src'
run('vlib_p1', [ms/'vlib.exe', w1], short)
run('vlog_p1', [ms/'vlog.exe', '-modelsimini', ini, '-work', w1,
                src/'a1/a1_raw_crop.v', src/'a1/a1_ddr_slot_store.v', src/'a1/a1_ddr_arb2.v',
                src/'a1/a1_uart_export.v', src/'a1/camera_a1_uart_top.v',
                src/'mem/capture_async_fifo.v', core,
                up/'rtl/ep_side/codec/a1_frame_top.v',
                root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r0/sim/a1_ddr_model.v',
                root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r0/sim/tb_camera_a1_uart_top.v'], short)
gold = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/sim/captures'
cases = [('micro8x2', ['-gW=8','-gH=2','-gCAM_W=32','-gCAM_H=4','-gROI_X=4','-gROI_Y=2','-gUART_DIV=1'], 240),
         ('mid64x8', ['-gW=64','-gH=8','-gCAM_W=128','-gCAM_H=16','-gROI_X=0','-gROI_Y=0','-gUART_DIV=1'], 240),
         ('full_grad', [], 900)]
for name, gens, tmo in cases:
    dec = sim/(name+'.dec'); stp = sim/(name+'.stats'); logp = logs/('sim_p1_'+name+'.log')
    run('vsim_p1_'+name, [ms/'vsim.exe', '-c', '-modelsimini', ini, '-lib', w1, '-l', logp,
                          'tb_camera_a1_uart_top', '+MODE=0', '+OUT='+str(dec), '+STAT='+str(stp)]
        + gens + ['-do', 'run -all; quit -f'], short, timeout=tmo)
    g = gold/(name+'.dec')
    dex = dec.exists() and dec.stat().st_size > 0
    dsha = sha(dec) if dex else None; gsha = sha(g)
    stt = stats(stp)
    out['p1'][name] = dict(dec_exists=dex, dec_bytes=(dec.stat().st_size if dex else -1), dec_sha256=dsha,
                           gold_bytes=g.stat().st_size, gold_sha256=gsha, byte_identical=(dsha == gsha),
                           stats=stt, log_errors=real_errors(logp))
    print(name, 'dec', (dec.stat().st_size if dex else 'MISSING'), dsha, 'gold', gsha,
          'identical', dsha == gsha, 'cycles', stt.get('cycles'), 'errs', real_errors(logp), flush=True)

out['commands'] = cmds
(sim/'tester-sim-run.json').write_text(json.dumps(out, indent=2))

# copy artifacts into evidence dir (tester write scope only)
dst = ev/'sim-rerun'
dst.mkdir(parents=True, exist_ok=True)
for p in sim.glob('*'):
    if p.is_file(): shutil.copy2(p, dst/p.name)
for p in logs.glob('*.log'): shutil.copy2(p, dst/p.name)
print('copied to', dst, flush=True)
print('DONE tester sim')
