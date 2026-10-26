"""Freeze and run CSI frame integrity tests; preserve every diagnostic."""
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess,uuid,zlib
p=argparse.ArgumentParser();p.add_argument('--test',choices=['pack','packet','chain','preview','frontend'],default='packet');p.add_argument('--baseline',action='store_true');p.add_argument('--production',action='store_true');a=p.parse_args()
if a.baseline and a.test in ['chain','preview']:p.error('baseline is only available for pack and packet')
if a.production and a.test=='pack':p.error('production geometry only applies to packet and chain')
if a.test=='frontend' and (a.baseline or a.production):p.error('frontend has no baseline/production options')
repo=Path(__file__).resolve().parents[2];out=Path('D:/TD/work/csi2/_validation/csi_integrity')/(datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'_'+uuid.uuid4().hex[:6]);out.mkdir(parents=True)
files=[repo/'fpga/csi2/tb'/('tb_csi_frontend_drain.sv' if a.test=='frontend' else 'tb_guarded_pack.sv' if a.test=='pack' else 'tb_csi_integrity.sv' if a.test=='packet' else 'tb_csi_preview_integrity.sv' if a.test=='preview' else 'tb_csi_integrity_chain.sv')]
if a.test=='pack':files += [repo/'fpga/csi2/src/mem'/('gray_frame_pack.v' if a.baseline else 'gray_frame_pack_guarded.v')]
else:
 files += [repo/'fpga/csi2/prj/camera_peer/uisrc/03_ip/mipi_csi_2/csi_rx_hdr_ecc.v',repo/'fpga/csi2/src/csi'/('csi_rx_packet_handler_checked.v' if a.baseline else 'csi_rx_packet_integrity.v')]
 if a.test in ['chain','preview']:files += [repo/'fpga/csi2/src/csi/csi_rx_10bit_unpack_checked.v',*[repo/'fpga/csi2/src/mem'/n for n in ['gray_frame_pack_guarded.v','capture_async_fifo.v','ddr_frame_store.v']]]
if a.test=='preview':files += [repo/'fpga/csi2/src/cam/cam_preview_capture.v']
if a.test=='frontend':files += [repo/'fpga/csi2/prj/camera_peer/uisrc/03_ip/mipi_csi_2'/n for n in ['csi_rx_byte_align.v','csi_rx_word_align.v','csi_rx_word_gear_box.v']]
snap=out/'sources';snap.mkdir();manifest={};copied=[]
for f in files:
 b=f.read_bytes();q=snap/f.name;q.write_bytes(b);copied.append(q);manifest[f.relative_to(repo).as_posix()]={'snapshot':q.relative_to(out).as_posix(),'sha256':hashlib.sha256(b).hexdigest()}
(out/'inputs.json').write_bytes((json.dumps(manifest,indent=2)+'\n').encode())
top=files[0].stem;params='-gLINE_BYTES=4800 ' if a.production else ''
if a.test in ['chain','preview']:
 wc=4800 if a.production else 80;gray=bytes((n*37+(n>>8)*13+7)&255 for n in range(0,wc,5))*2
 if a.test=='preview':
  val=lambda n:(n*37+(n>>8)*13+7)&255
  gray=bytes(((val(n)*4+(val(n+4)&3)+val(n+1)*4+((val(n+4)>>2)&3))>>3) for n in range(0,wc,5))*4
 gold=out/'golden_crc.txt';gold.write_bytes((f'{zlib.crc32(gray):08x}\n').encode())
 manifest['generated/golden_crc.txt']={'snapshot':'golden_crc.txt','sha256':hashlib.sha256(gold.read_bytes()).hexdigest(),'generator':'Python zlib.crc32; preview mode averages first two decoded RAW10 pixels then repeats four output rows; chain mode samples first high byte then repeats two rows'}
 (out/'inputs.json').write_bytes((json.dumps(manifest,indent=2)+'\n').encode())
(out/'run.do').write_bytes(('onerror {quit -code 1 -f}\nvsim -voptargs=+acc '+params+'work.'+top+'\nrun -all\nquit -f\n').encode())
bin=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem');logs=[]
for cmd in [[str(bin/'vlib.exe'),'work'],[str(bin/'vlog.exe'),'-sv']+(['+define+BASELINE'] if a.baseline else [])+[str(f) for f in copied],[str(bin/'vsim.exe'),'-c','-do','do run.do']]:
 q=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240);s=q.stdout.decode(errors='replace');logs.append(s);(out/'regression.log').write_bytes('\n'.join(logs).encode());print(s[-2400:])
 if q.returncode:raise SystemExit(q.returncode)
last=logs[-1];ok=('INTEGRITY_FAIL' in last and 'INTEGRITY_PASS' not in last) if a.baseline else ('INTEGRITY_PASS' in last and 'INTEGRITY_FAIL' not in last)
print('INTEGRITY_EVIDENCE',out)
if not ok:raise SystemExit('Expected result marker missing')
print('EXPECTED_BASELINE_FAILURE' if a.baseline else 'REGRESSION_PASS')
