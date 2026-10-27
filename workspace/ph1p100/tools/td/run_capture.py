"""Retained ModelSim evidence for the real-camera DDR capture adapters."""
from pathlib import Path
import argparse, datetime, subprocess, uuid,hashlib,json
p=argparse.ArgumentParser();p.add_argument('--test',choices=['pack','chain','tap'],default='pack');p.add_argument('--red',action='store_true');p.add_argument('--bytes',type=int,default=256);p.add_argument('--address-fault',action='store_true');a=p.parse_args()
if a.address_fault and (a.test!='chain' or a.red or a.bytes<=512):p.error('Address alias requires chain, bytes >512, without --red')
repo=Path(__file__).resolve().parents[2]
out=Path('D:/TD/work/csi2/_validation/capture')/(datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'_'+uuid.uuid4().hex[:6]);out.mkdir(parents=True)
top='tb_capture_'+a.test;sources=[repo/'fpga/csi2/tb'/f'{top}.sv']
if a.red and a.test=='tap':
    t=(repo/'fpga/csi2/prj/camera_peer/uisrc/01_rtl/cam_preview.v').read_text(encoding='utf-8')
    t=t.replace('module cam_preview #(', 'module cam_preview_capture #(')
    t=t.replace('output wire          O_cam_alive', 'output wire O_gray_sof,O_gray_valid,O_gray_last,output wire[7:0] O_gray_data,\n    output wire          O_cam_alive')
    t=t.replace('endmodule','assign O_gray_sof=0;assign O_gray_valid=0;assign O_gray_last=0;assign O_gray_data=0;\nendmodule')
    (out/'tap_stub.v').write_text(t,encoding='utf-8');sources.append(out/'tap_stub.v')
elif a.red:sources.append(repo/'fpga/csi2/tb'/f'capture_{a.test}_stub.v')
else:
    sources += [repo/'fpga/csi2/src/mem'/f for f in ['capture_async_fifo.v','gray_frame_pack.v']]
    if a.test=='chain':sources += [repo/'fpga/csi2/src/mem'/f for f in ['ddr_frame_store.v','ddr_capture_check.v','camera_ddr_capture.v']]
    if a.test=='tap':sources=[repo/'fpga/csi2/tb'/f'{top}.sv',repo/'fpga/csi2/src/cam/cam_preview_capture.v']
params=f'-gFRAME_BYTES={a.bytes} ' if a.test=='chain' else ''
if a.address_fault:params+='-gADDRESS_FAULT=1 '
snapshot=out/'sources';snapshot.mkdir();copied=[];manifest={}
for f in sources:
    b=f.read_bytes();q=snapshot/f.name;q.write_bytes(b);copied.append(q)
    key=f.relative_to(repo).as_posix() if f.is_relative_to(repo) else f.name
    manifest[key]={'sha256':hashlib.sha256(b).hexdigest(),'snapshot':q.relative_to(out).as_posix()}
(out/'inputs.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='ascii');sources=copied
(out/'run.do').write_text(f'onerror {{quit -code 1 -f}}\nvsim -voptargs=+acc {params}work.{top}\nrun -all\nquit -f\n',encoding='ascii')
bin=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem');logs=[]
for command in [[str(bin/'vlib.exe'),'work'],[str(bin/'vlog.exe'),'-sv',*[str(x) for x in sources]],[str(bin/'vsim.exe'),'-c','-do','do run.do']]:
    r=subprocess.run(command,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180);s=r.stdout.decode(errors='replace');logs.append(s);(out/'regression.log').write_text('\n'.join(logs),encoding='utf-8');print(s[-1800:])
    if r.returncode:raise SystemExit(r.returncode)
prefix='CAPTURE_'+a.test.upper();last=logs[-1];ok=(prefix+'_FAIL' in last and prefix+'_PASS' not in last) if a.red else (prefix+'_PASS' in last and prefix+'_FAIL' not in last)
print('CAPTURE_EVIDENCE',out)
if not ok:raise SystemExit('Expected result marker missing')
print('EXPECTED_RED' if a.red else 'REGRESSION_PASS')
