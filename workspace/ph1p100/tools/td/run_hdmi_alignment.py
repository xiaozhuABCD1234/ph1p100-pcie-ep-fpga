"""Check RGB/DE/HS/VS cycles at the encrypted HDMI controller boundary."""
from pathlib import Path
import argparse,datetime,subprocess
p=argparse.ArgumentParser();p.add_argument('--expect-fail',action='store_true');a=p.parse_args()
repo=Path(__file__).resolve().parents[2];live=Path(r'D:\TD\work\csi2\prj\camera_peer')
out=live/'_sim'/('hdmi_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir(parents=True,exist_ok=False)
b=Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
commands=[[str(b/'vlib.exe'),'work'],[str(b/'vlog.exe'),'-sv',str(live/'uisrc/03_ip/alip/ui_HDMI_TX/ui_HDMI_TX.v'),str(repo/'fpga/csi2/prj/camera_peer/uisrc/02_sim/tb_hdmi_video_alignment.sv')],
 [str(b/'vsim.exe'),'-c','-voptargs=+acc','work.tb_hdmi_video_alignment','-do','run -all; quit -f']]
logs=[]
for i,cmd in enumerate(commands):
 r=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);s=r.stdout.decode('utf-8',errors='replace');logs.append(s)
 (out/'regression.log').write_text('\n'.join(logs),encoding='utf-8');print(s[-2100:])
 if r.returncode and not(a.expect_fail and i==2 and 'HDMI_ALIGNMENT_FAIL' in s):raise SystemExit(r.returncode)
print('HDMI_ALIGNMENT_EVIDENCE',out)
if a.expect_fail:
 if 'HDMI_ALIGNMENT_FAIL' not in logs[-1]:raise SystemExit('Negative control did not fail')
 print('HDMI_ALIGNMENT_RED_EXPECTED_FAILURE')
elif 'HDMI_ALIGNMENT_PASS' not in logs[-1] or 'HDMI_ALIGNMENT_FAIL' in logs[-1]:raise SystemExit(1)
