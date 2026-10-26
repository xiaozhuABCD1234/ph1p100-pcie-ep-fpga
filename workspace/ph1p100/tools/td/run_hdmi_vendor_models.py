"""Bounded HDL checks with real vendor cells (no download or production edits)."""
import argparse
import datetime
from pathlib import Path
import subprocess

p=argparse.ArgumentParser()
p.add_argument('suite', choices=['serial','pll'])
a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
live=Path(r'D:\TD\work\csi2\prj\camera_peer')
models=Path(r'D:\downlaod\sim_release\ph1p')
tb=repo/'fpga/csi2/prj/camera_peer/uisrc/02_sim'
binpath=Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
out=live/'_sim'/('hdmi_vendor_'+a.suite+'_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir(parents=True,exist_ok=False)
if a.suite=='serial':
    sources=[models/'ph1p_phy_hr_pad.v',models/'ph1p_logic_hrio.v',live/'uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v',tb/'tb_hdmi_serial_clock.sv']
    top='tb_hdmi_serial_clock'
    cases=['-gPHASE_PS='+str(x) for x in [0,250,750]]
    marker='SERIAL_PASS'
else:
    sources=[models/'ph1p_phy_pll.v',models/'ph1p_logic_bufg.v',
             live/'uisrc/03_ip/raw10_clocks/RTL/ph1p_phy_pll_wrapper_raw10_clocks.v',
             live/'uisrc/03_ip/raw10_clocks/raw10_clocks.v',tb/'tb_raw10_pll_dynamic.sv']
    top='tb_raw10_pll_dynamic';cases=[''];marker='PLL_PASS'
sources.insert(0,models/'ph1p_phy_gsr.v')
commands=[[str(binpath/'vlib.exe'),'work'],[str(binpath/'vlog.exe'),'-sv',*[str(x) for x in sources]]]
# Functional simulation only: physical timing remains the TD STA/hardware boundary.
commands += [[str(binpath/'vsim.exe'),'-c','-t','1fs','+notimingchecks','-voptargs=+acc',*([case] if case else []),'work.'+top,'work.PH1P_PHY_GSR','-do','run -all; quit -f'] for case in cases]
logs=[]
for i,cmd in enumerate(commands):
    result=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
    text=result.stdout.decode('utf-8',errors='replace');logs.append(text)
    (out/'regression.log').write_text('\n'.join(logs),encoding='utf-8')
    print(text[-4000:],flush=True)
    if result.returncode or (i>=2 and (marker not in text or '_FAIL' in text)):
        print('VENDOR_MODEL_CHECK_INCOMPLETE',out)
        raise SystemExit(1)
print('VENDOR_MODEL_EVIDENCE',out)
