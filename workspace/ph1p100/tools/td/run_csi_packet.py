"""Freeze and run RAW10 packet boundary regression; legacy must fail."""
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess,uuid
p=argparse.ArgumentParser();p.add_argument('--legacy',action='store_true');p.add_argument('--production',action='store_true');p.add_argument('--unpack',action='store_true');a=p.parse_args()
if a.unpack and (a.legacy or a.production):p.error('--unpack is a standalone integrated regression')
repo=Path(__file__).resolve().parents[2]
out=Path('D:/TD/work/csi2/_validation/csi_packet')/(datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'_'+uuid.uuid4().hex[:6]);out.mkdir(parents=True)
vendor=repo/'fpga/csi2/prj/camera_peer/uisrc/03_ip/mipi_csi_2'
top='tb_csi_unpack_checked' if a.unpack else 'tb_csi_packet_checked'
sources=[repo/'fpga/csi2/tb'/f'{top}.sv',vendor/'csi_rx_hdr_ecc.v',vendor/'csi_rx_packet_handler.v' if a.legacy else repo/'fpga/csi2/src/csi/csi_rx_packet_handler_checked.v']
if a.unpack:sources.append(repo/'fpga/csi2/src/csi/csi_rx_10bit_unpack_checked.v')
snapshot=out/'sources';snapshot.mkdir();copied=[];manifest={}
for f in sources:
 b=f.read_bytes();q=snapshot/f.name;q.write_bytes(b);copied.append(q)
 manifest[f.relative_to(repo).as_posix()]={'sha256':hashlib.sha256(b).hexdigest(),'snapshot':q.relative_to(out).as_posix()}
(out/'inputs.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='ascii')
params='-gLINE_BYTES=4800 ' if a.production else ''
(out/'run.do').write_text('onerror {quit -code 1 -f}\nvsim -voptargs=+acc '+params+'work.'+top+'\nrun -all\nquit -f\n',encoding='ascii')
bin=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem');logs=[]
compile=[str(bin/'vlog.exe'),'-sv']+(['+define+LEGACY'] if a.legacy else [])+[str(f) for f in copied]
for cmd in [[str(bin/'vlib.exe'),'work'],compile,[str(bin/'vsim.exe'),'-c','-do','do run.do']]:
 r=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120);s=r.stdout.decode(errors='replace');logs.append(s)
 (out/'regression.log').write_bytes('\n'.join(logs).encode());print(s[-2000:])
 if r.returncode:raise SystemExit(r.returncode)
last=logs[-1];ok=('CSI_PACKET_FAIL' in last and 'CSI_PACKET_PASS' not in last) if a.legacy else ('CSI_PACKET_PASS' in last and 'CSI_PACKET_FAIL' not in last)
print('CSI_PACKET_EVIDENCE',out)
if not ok:raise SystemExit('Expected result marker missing')
print('EXPECTED_LEGACY_FAILURE' if a.legacy else 'REGRESSION_PASS')
