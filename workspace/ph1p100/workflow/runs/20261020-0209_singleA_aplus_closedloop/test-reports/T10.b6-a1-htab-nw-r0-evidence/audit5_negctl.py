import os, sys, json, time, pathlib, hashlib, subprocess, zlib, re, shutil
sys.stdout.reconfigure(encoding='utf-8', errors='replace')
root = pathlib.Path(r'D:\fpga\ph1p100')
runs = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop'
pkg = runs/'T10.b6-a1-htab-nw'
b5 = runs/'T10.b5-a1-htab-pipe/r0'
ev = runs/'test-reports/T10.b6-a1-htab-nw-r0-evidence'
short = pathlib.Path(r'C:\Users\czz\AppData\Local\Temp\opencode\b6t')
sim = short/'neg'; sim.mkdir(parents=True, exist_ok=True)
core_r5 = b5/'changed-src/a1_deflate_core.v'
up = root/'upstream/ph1p100-pcie-ep-fpga'
p2 = root/'work/parallel-sim-20261024-2204/codec-throughput'
ms = pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
ini = p2/'modelsim.ini'
env = os.environ.copy(); env['MODEL_TECH'] = str(ms); env['MODELSIM'] = str(ini)
env['PATH'] = str(ms) + os.pathsep + env.get('PATH', '')

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def run(tag, args, cwd, timeout=600):
    args = [str(a).replace(chr(92), '/') for a in args]
    t0 = time.monotonic()
    with open(sim/(tag+'.out.log'), 'wb') as o, open(sim/(tag+'.err.log'), 'wb') as e:
        pr = subprocess.Popen(args, cwd=str(cwd), env=env, stdout=o, stderr=e,
                              creationflags=subprocess.CREATE_NO_WINDOW)
        rc = pr.wait(timeout=timeout)
    print(tag, 'exit', rc, round(time.monotonic()-t0, 2), 's', flush=True)
    return rc

print('=== negative control: r5 core (per-match wait) on the SAME P2 comp vectors ===')
print('r5 core', sha(core_r5), core_r5.stat().st_size)
w = short/'wneg'
run('vlib', [ms/'vlib.exe', w], short)
run('vlog', [ms/'vlog.exe', '-modelsimini', ini, '-work', w, core_r5,
             up/'sim/tb/codec/tb_a1_deflate_core.v'], short)
cd = p2/'comp'
run('vsim', [ms/'vsim.exe', '-c', '-modelsimini', ini, '-lib', w, '-l', sim/'comp_r5.log',
             'tb_a1_deflate_core', '+IN='+str(cd/'in.hex'), '+META='+str(cd/'in.meta'),
             '+OUT='+str(sim/'comp_r5.out.hex'), '+STAT='+str(sim/'comp_r5.stats.txt'),
             '+BP=0', '+GAP=0', '+TIMEOUT=2000000', '-do', 'run -all; quit -f'], short)
st = {}
for ln in (sim/'comp_r5.stats.txt').read_text().splitlines():
    parts = ln.split()
    if len(parts) == 2:
        try: st[parts[0]] = int(parts[1])
        except ValueError: st[parts[0]] = parts[1]
stream = bytes(int(x, 16) for x in (sim/'comp_r5.out.hex').read_text().split())
expected = (cd/'in.xform').read_bytes()
dec = zlib.decompressobj(); zout = dec.decompress(stream)+dec.flush()
mism = sum(a != b for a, b in zip(zout, expected))+abs(len(zout)-len(expected))
res = dict(core='r5', sha=sha(core_r5), cycles=st.get('run_cycles'), done_cycle=st.get('done_cycle'),
           first_cycle=st.get('first_cycle'), matches=st.get('stat_matches'), out_bytes=len(stream),
           out_sha256=hashlib.sha256(stream).hexdigest(), zlib_mismatch=mism,
           equals_b6_stream=(hashlib.sha256(stream).hexdigest() ==
                             '2601d57cd98d1fe69b2e46fe8423779a5d44bd14c00e1fe2d5faab6ff15a7c05'),
           delta_vs_b6=(st.get('run_cycles') - 355261) if st.get('run_cycles') else None)
print(json.dumps(res, indent=2))
(sim/'negative-control.json').write_text(json.dumps(res, indent=2))
for f in ['comp_r5.stats.txt', 'negative-control.json', 'comp_r5.log']:
    shutil.copy2(sim/f, ev/'sim-rerun'/('negctl_'+f))
print('copied negative control artifacts')

print('\n=== b5 r0 result claims for P2 (context) ===')
t = (b5/'result-r0.md').read_text(errors='replace')
for ln in t.splitlines():
    if re.search(r'P2|374|76\.9|cycles|MB/s', ln): print('  ', ln.strip()[:180])

print('\n=== b6 boundary evidence (reuse candidate) ===')
bj = pkg/'r0/sim/boundaries/result.json'
if bj.exists():
    d = json.loads(bj.read_text(errors='replace'))
    print('keys', list(d.keys())[:12])
    print('scope', str(d.get('scope'))[:200])
    for c in d.get('cases', [])[:4]:
        print('  case', c.get('name'), c.get('status'), 'checks_all', all(v for v in c.get('checks', {}).values()) if c.get('checks') else None)
    print('hashes', d.get('hashes', 'n/a'))
