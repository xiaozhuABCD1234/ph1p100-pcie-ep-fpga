"""RAW10 capture/display functional regression; every run preserves evidence."""
from pathlib import Path
import argparse, datetime, subprocess
parser=argparse.ArgumentParser()
parser.add_argument('--expect-fail',action='store_true')
args=parser.parse_args()
repo=Path(__file__).resolve().parents[2]
live=Path(r'D:\TD\work\csi2\prj\camera_peer')
stamp=datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
out=live/'_sim'/('sequence_'+stamp)
out.mkdir(parents=True,exist_ok=False)
bin_dir=Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
tb=repo/'fpga/csi2/prj/camera_peer/uisrc/02_sim/tb_cam_preview_sequence.sv'
commands=[
 [str(bin_dir/'vlib.exe'),'work'],
 [str(bin_dir/'vlog.exe'),'-sv',str(live/'uisrc/01_rtl/cam_preview.v'),str(tb)],
 *[[str(bin_dir/'vsim.exe'),'-c','-voptargs=+acc','-gREAD_ONLY='+str(mode),
    'work.tb_cam_preview_sequence','-do','run -all; quit -f'] for mode in (0,1)]
]
logs=[]
for i,cmd in enumerate(commands):
 r=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
 s=r.stdout.decode('utf-8',errors='replace');logs.append(s)
 (out/'regression.log').write_text('\n'.join(logs),encoding='utf-8')
 print(s[-2600:])
 if r.returncode and not (args.expect_fail and i>=2 and 'SEQUENCE_FAIL' in s):
  raise SystemExit(r.returncode)
print('RAW10_SEQUENCE_EVIDENCE',out)
if args.expect_fail:
 if not all('SEQUENCE_FAIL' in s and 'SEQUENCE_PASS' not in s for s in logs[2:]):
  raise SystemExit('Both negative tests must fail')
 print('RAW10_SEQUENCE_RED_EXPECTED_FAILURE')
elif not all('SEQUENCE_PASS' in s and 'SEQUENCE_FAIL' not in s for s in logs[2:]):
 raise SystemExit('RAW10 sequence regression failed')
