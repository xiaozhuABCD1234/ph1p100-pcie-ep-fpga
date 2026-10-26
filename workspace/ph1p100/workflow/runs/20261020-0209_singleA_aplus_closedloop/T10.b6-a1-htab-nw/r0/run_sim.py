import os, sys, json, time, pathlib, hashlib, subprocess, zlib

root = pathlib.Path(r'D:\fpga\ph1p100')
pkg = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw'
sim = pkg/'r0/sim'
core = pkg/'r0/changed-src/a1_deflate_core.v'
up = root/'upstream/ph1p100-pcie-ep-fpga'
p2 = root/'work/parallel-sim-20261024-2204/codec-throughput'
ms = pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
sim.mkdir(parents=True, exist_ok=True)
logs = sim/'logs'; logs.mkdir(exist_ok=True)
caps = sim/'captures'; caps.mkdir(exist_ok=True)
env = os.environ.copy()
env['MODEL_TECH'] = str(ms)
ini = p2/'modelsim.ini'
env['MODELSIM'] = str(ini)
env['PATH'] = str(ms) + os.pathsep + env.get('PATH', '')
cmds = []

def run(tag, args, cwd, timeout=1800):
    args = [str(a).replace(chr(92), '/') for a in args]
    t0 = time.monotonic()
    rec = dict(tag=tag, argv=args, cwd=str(cwd), timeout_seconds=timeout)
    with open(logs/(tag+'.stdout.log'), 'wb') as o, open(logs/(tag+'.stderr.log'), 'wb') as e:
        pr = subprocess.Popen(args, cwd=str(cwd), env=env, stdout=o, stderr=e,
                              creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            rec['exit_code'] = pr.wait(timeout=timeout); rec['timed_out'] = False
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill', '/PID', str(pr.pid), '/T', '/F'], capture_output=True, timeout=20)
            rec['exit_code'] = 124; rec['timed_out'] = True
    rec['elapsed_seconds'] = round(time.monotonic()-t0, 2)
    cmds.append(rec)
    print(tag, 'exit', rec['exit_code'], rec['elapsed_seconds'], 's', flush=True)
    if rec['exit_code'] != 0:
        raise SystemExit('tool failed: ' + tag)
    return rec

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def stats(p):
    d = {}
    for line in pathlib.Path(p).read_text().splitlines():
        if line.strip():
            parts = line.split()
            try:
                d[parts[0]] = int(parts[1]) if len(parts) == 2 else ' '.join(parts[1:])
            except (ValueError, IndexError):
                d[parts[0]] = ' '.join(parts[1:])
    return d

out = dict(task='T10.b6-a1-htab-nw', core_sha256=sha(core), core_bytes=core.stat().st_size,
           modelsim='10.5b win32aloem', p2={}, p1={}, commands=cmds)

# ------------------------------------------------------------------ P2 core-level
w2 = sim/'work-p2'
run('vlib_p2', [ms/'vlib.exe', w2], sim)
run('vlog_p2', [ms/'vlog.exe', '-modelsimini', ini, '-work', w2, core,
                up/'sim/tb/codec/tb_a1_deflate_core.v'], sim)
sys.path.insert(0, str(up/'tools/codec'))
import a1_inflate_strict as strict

for case in ['comp', 'rand']:
    cd = p2/case
    logp = logs/('sim_p2_'+case+'.log')
    run('vsim_p2_'+case, [ms/'vsim.exe', '-c', '-modelsimini', ini, '-lib', w2, '-l', logp,
                          'tb_a1_deflate_core',
                          '+IN='+str(cd/'in.hex'), '+META='+str(cd/'in.meta'),
                          '+OUT='+str(sim/(case+'.out.hex')), '+STAT='+str(sim/(case+'.stats.txt')),
                          '+BP=0', '+GAP=0', '+TIMEOUT=2000000', '-do', 'run -all; quit -f'], sim)
    st = stats(sim/(case+'.stats.txt'))
    stream = bytes(int(x, 16) for x in (sim/(case+'.out.hex')).read_text().split())
    expected = (cd/'in.xform').read_bytes()
    zok = sok = False; zm = sm = None; ze = se = ''
    try:
        dec = zlib.decompressobj(); zout = dec.decompress(stream)+dec.flush()
        zok = dec.eof and not dec.unused_data and not dec.unconsumed_tail
        zm = sum(a != b for a, b in zip(zout, expected))+abs(len(zout)-len(expected))
    except Exception as ex:
        ze = str(ex)
    try:
        sout, ss = strict.inflate(stream, expected_len=len(expected)); sok = True
        sm = sum(a != b for a, b in zip(sout, expected))+abs(len(sout)-len(expected))
    except Exception as ex:
        se = str(ex)
    cyc = st['run_cycles']; n = st['in_bytes']
    tb_ok = (st['done'] == 1 and st['out_last'] == 1 and st['timeout_hit'] == 0
             and n == len(expected) and st['bp'] == 0 and st['gap'] == 0)
    out['p2'][case] = dict(stats=st, tb_pass=tb_ok, output_bytes=len(stream),
                           output_sha256=hashlib.sha256(stream).hexdigest(),
                           zlib_ok=zok, zlib_err=ze, zlib_mismatch=zm,
                           strict_ok=sok, strict_err=se, strict_mismatch=sm,
                           run_cycles=cyc, MBps_at_187p5MHz=(n/cyc*187.5 if cyc else None))
    print(case, 'cycles', cyc, 'bytes', len(stream), 'sha', out['p2'][case]['output_sha256'],
          'tb', tb_ok, 'zlib', zok, zm, 'strict', sok, sm, flush=True)

(sim/'p2-regression.json').write_text(json.dumps(out['p2'], indent=2))

# ------------------------------------------------------------------ P1 three cases
w1 = sim/'work-p1'
src = root/'fpga/csi2/src'
run('vlib_p1', [ms/'vlib.exe', w1], sim)
run('vlog_p1', [ms/'vlog.exe', '-modelsimini', ini, '-work', w1,
                src/'a1/a1_raw_crop.v', src/'a1/a1_ddr_slot_store.v', src/'a1/a1_ddr_arb2.v',
                src/'a1/a1_uart_export.v', src/'a1/camera_a1_uart_top.v',
                src/'mem/capture_async_fifo.v', core,
                up/'rtl/ep_side/codec/a1_frame_top.v',
                root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r0/sim/a1_ddr_model.v',
                root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r0/sim/tb_camera_a1_uart_top.v'], sim)
gold = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/sim/captures'
cases = [
    ('micro8x2',  ['-gW=8',  '-gH=2', '-gCAM_W=32',  '-gCAM_H=4',  '-gROI_X=4', '-gROI_Y=2', '-gUART_DIV=1']),
    ('mid64x8',   ['-gW=64', '-gH=8', '-gCAM_W=128', '-gCAM_H=16', '-gROI_X=0', '-gROI_Y=0', '-gUART_DIV=1']),
    ('full_grad', []),
]
for name, gens in cases:
    dec = caps/(name+'.dec'); stp = caps/(name+'.stats')
    logp = logs/('sim_p1_'+name+'.log')
    run('vsim_p1_'+name, [ms/'vsim.exe', '-c', '-modelsimini', ini, '-lib', w1, '-l', logp,
                          'tb_camera_a1_uart_top', '+MODE=0', '+OUT='+str(dec), '+STAT='+str(stp)]
        + gens + ['-do', 'run -all; quit -f'], sim)
    g = gold/(name+'.dec')
    out['p1'][name] = dict(dec_bytes=dec.stat().st_size, dec_sha256=sha(dec),
                           gold_bytes=g.stat().st_size, gold_sha256=sha(g),
                           byte_identical=(sha(dec) == sha(g)),
                           stats=stats(stp))
    print(name, out['p1'][name]['dec_bytes'], out['p1'][name]['dec_sha256'],
          'identical', out['p1'][name]['byte_identical'], flush=True)

(sim/'p1-regression.json').write_text(json.dumps(out['p1'], indent=2))
out['commands'] = cmds
(sim/'sim-run.json').write_text(json.dumps(out, indent=2))
print('DONE')
