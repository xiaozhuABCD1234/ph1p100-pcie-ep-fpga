"""Run DDR frame RTL regressions; retain every run and explicit RED evidence."""
from pathlib import Path
import argparse, datetime, subprocess, uuid
p=argparse.ArgumentParser()
p.add_argument('--red',action='store_true')
p.add_argument('--probe',action='store_true')
p.add_argument('--words',type=int,default=8)
a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
out=Path(r'D:/TD/work/csi2/_validation/ddr_frame')/(datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'_'+uuid.uuid4().hex[:8])
out.mkdir(parents=True,exist_ok=False)
binpath=Path(r'D:/intelFPGA/18.1/modelsim_ase/win32aloem')
top='tb_ddr_frame_probe' if a.probe else 'tb_ddr_frame_store'
sources=[repo/'fpga/csi2/tb'/f'{top}.sv']
if a.red and a.probe:sources.append(repo/'fpga/csi2/tb/ddr_frame_probe_stub.v')
else:
    sources += [repo/'fpga/csi2/tb/ddr_frame_store_stub.v'] if a.red else [repo/'fpga/csi2/src/mem/ddr_frame_store.v']
    if a.probe:sources.append(repo/'fpga/csi2/src/mem/ddr_frame_probe.v')
(out/'run.do').write_text('onerror {quit -code 1 -f}\nvsim -voptargs=+acc '
    + (f'-gFRAME_WORDS={a.words} ' if a.probe else '')
    + f'work.{top}\nrun -all\nquit -f\n',encoding='ascii')
commands=[[str(binpath/'vlib.exe'),'work'],[str(binpath/'vlog.exe'),'-sv',*[str(x) for x in sources]],
          [str(binpath/'vsim.exe'),'-c','-do','do run.do']]
logs=[]
for cmd in commands:
    r=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
    s=r.stdout.decode('utf-8',errors='replace');logs.append(s)
    (out/'regression.log').write_text('\n'.join(logs),encoding='utf-8')
    print(s[-3000:])
    if r.returncode:raise SystemExit(r.returncode)
prefix='DDR_PROBE' if a.probe else 'DDR_FRAME'
last=logs[-1]
ok=f'{prefix}_FAIL' in last and f'{prefix}_PASS' not in last if a.red else f'{prefix}_PASS' in last and f'{prefix}_FAIL' not in last
print('DDR_EVIDENCE',out)
if not ok:raise SystemExit('Expected result marker missing')
print('EXPECTED_RED' if a.red else 'REGRESSION_PASS')
