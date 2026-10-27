"""Retain ModelSim positive and no-function negative DDR display evidence."""
from pathlib import Path
import argparse,datetime,subprocess,uuid,hashlib,json
p=argparse.ArgumentParser();p.add_argument('--guarded',action='store_true');p.add_argument('--red',action='store_true');p.add_argument('--production',action='store_true');p.add_argument('--address-fault',action='store_true');a=p.parse_args()
if a.guarded and a.red:p.error('guarded mode requires real RTL')
if a.red and a.address_fault:p.error('Use either stub red or address fault, not both')
repo=Path(__file__).resolve().parents[2]
out=Path('D:/TD/work/csi2/_validation/ddr_display')/(datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'_'+uuid.uuid4().hex[:6]);out.mkdir(parents=True)
sources=[repo/'fpga/csi2/tb/tb_ddr_display.sv']
if a.red:sources.append(repo/'fpga/csi2/tb/ddr_display_stub.v')
else:sources += [repo/'fpga/csi2/src/mem'/f for f in ['capture_async_fifo.v','gray_frame_pack.v','ddr_frame_store.v','ddr_display_read.v','gray_display_pixels.v','camera_ddr_display.v']]
if a.guarded:sources += [repo/'fpga/csi2/src/mem'/n for n in ['gray_frame_pack_guarded.v','camera_ddr_display_guarded.v']]
# Compile immutable ASCII-path snapshots so later edits cannot change the
# meaning of retained evidence or depend on the old simulator's path encoding.
snapshot=out/'sources';snapshot.mkdir();manifest={};copied=[]
for f in sources:
 b=f.read_bytes();q=snapshot/f.name;q.write_bytes(b);copied.append(q)
 manifest[f.relative_to(repo).as_posix()]={'snapshot':q.relative_to(out).as_posix(),'sha256':hashlib.sha256(b).hexdigest()}
(out/'inputs.json').write_bytes((json.dumps(manifest,indent=2)+'\n').encode())
sources=copied
params='-gSW=960 -gSH=540 -gPRODUCTION=1 ' if a.production else ''
if a.address_fault:params+='-gADDRESS_FAULT=1 '
(out/'run.do').write_bytes(('onerror {quit -code 1 -f}\nvsim -voptargs=+acc '+params+'work.tb_ddr_display\nrun -all\nquit -f\n').encode())
bin=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem');logs=[]
for cmd in [[str(bin/'vlib.exe'),'work'],[str(bin/'vlog.exe'),'-sv']+(['+define+GUARDED'] if a.guarded else [])+[str(f) for f in sources],[str(bin/'vsim.exe'),'-c','-do','do run.do']]:
 r=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240);s=r.stdout.decode(errors='replace');logs.append(s);(out/'regression.log').write_bytes(('\n'.join(logs)).encode());print(s[-1800:])
 if r.returncode:raise SystemExit(r.returncode)
last=logs[-1];negative=a.red or a.address_fault;ok=('DDR_DISPLAY_FAIL' in last and 'DDR_DISPLAY_PASS' not in last) if negative else ('DDR_DISPLAY_PASS' in last and 'DDR_DISPLAY_FAIL' not in last)
print('DDR_DISPLAY_EVIDENCE',out)
if not ok:raise SystemExit('Expected result marker missing')
print('EXPECTED_RED' if negative else 'REGRESSION_PASS')
