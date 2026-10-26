import os, sys, json, time, pathlib, hashlib, subprocess, shutil

root = pathlib.Path(r'D:\fpga\ph1p100')
pkg = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag'
sim = pkg/'r0/sim'
caps = pkg/'r0/sim/caps'
caps.mkdir(parents=True, exist_ok=True)
logs = sim/'logs'; logs.mkdir(exist_ok=True)
work = pathlib.Path(r'C:\Users\czz\AppData\Local\Temp\opencode\b7\simwork')
scratch = pathlib.Path(r'C:\Users\czz\AppData\Local\Temp\opencode\b7\caps')
scratch.mkdir(parents=True, exist_ok=True)
ms = pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
ini = r'D:\fpga\ph1p100\work\parallel-sim-20261024-2204\codec-throughput\modelsim.ini'
env = os.environ.copy()
env['MODEL_TECH'] = str(ms)
env['MODELSIM'] = ini
env['PATH'] = str(ms) + os.pathsep + env.get('PATH', '')

gold_dir = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/sim/captures'
cases = [
    ('micro8x2', ['-gW=8', '-gH=2', '-gCAM_W=32', '-gCAM_H=4', '-gROI_X=4', '-gROI_Y=2', '-gUART_DIV=1'],
     'fa513a2b5a7f268be9f29d62aea6c44aaab796d0f23256b0e1049f50acceedef'),
    ('mid64x8', ['-gW=64', '-gH=8', '-gCAM_W=128', '-gCAM_H=16', '-gROI_X=0', '-gROI_Y=0', '-gUART_DIV=1'],
     'ee61e6200d9abca6'),
    ('full_grad', [], 'b992a8ad74063545'),
]
res = {}
for name, gens, gold_prefix in cases:
    dec = scratch/(name + '.dec')
    stp = scratch/(name + '.stats')
    logp = logs/('sim_p1_' + name + '.log')
    args = [str(ms/'vsim.exe'), '-c', '-lib', str(work), '-l', str(logp),
            'tb_camera_a1_uart_top', '+MODE=0', '+OUT=' + str(dec), '+STAT=' + str(stp)] + gens + \
           ['-do', 'run -all; quit -f']
    t0 = time.monotonic()
    pr = subprocess.run(args, cwd=str(work), env=env, capture_output=True, text=True, timeout=2400)
    el = round(time.monotonic() - t0, 1)
    sha = hashlib.sha256(dec.read_bytes()).hexdigest() if dec.exists() else 'MISSING'
    gsha = hashlib.sha256((gold_dir/(name + '.dec')).read_bytes()).hexdigest()
    stats = {}
    if stp.exists():
        for line in stp.read_text().splitlines():
            for tok in line.split():
                if '=' in tok:
                    k, v = tok.split('=', 1)
                    stats[k] = v
    tb_done = [l for l in pr.stdout.splitlines() if 'TB_DONE' in l or 'TB_TIMEOUT' in l]
    res[name] = dict(case=name, exit=pr.returncode, seconds=el,
                     dec_bytes=dec.stat().st_size if dec.exists() else 0,
                     dec_sha256=sha, gold_sha256=gsha,
                     golden_prefix_match=sha.startswith(gold_prefix),
                     byte_identical=(sha == gsha), stats=stats, tb=tb_done)
    shutil.copyfile(dec, caps/(name + '.dec'))
    shutil.copyfile(stp, caps/(name + '.stats'))
    print(name, 'exit', pr.returncode, el, 's', res[name]['dec_bytes'], sha,
          'identical', res[name]['byte_identical'], stats.get('err'), flush=True)
(sim/'p1-regression-b7.json').write_text(json.dumps(res, indent=2))
print('DONE')
