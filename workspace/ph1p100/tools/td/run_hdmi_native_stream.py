"""Functional PH1P DDRX5 experiment; never programs hardware."""
from pathlib import Path
import argparse,datetime,subprocess
p=argparse.ArgumentParser()
p.add_argument('--reverse-mutant',action='store_true')
p.add_argument('--production',action='store_true')
a=p.parse_args()
if a.production and a.reverse_mutant: p.error('mutant is limited to diagnostic source')
repo=Path(__file__).resolve().parents[2]
models=Path(r'D:/downlaod/sim_release/ph1p')
binpath=Path(r'D:/intelFPGA/18.1/modelsim_ase/win32aloem')
out=Path(r'D:/TD/work/csi2/prj/camera_peer/_sim')/('hdmi_native_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
sources=[models/'ph1p_phy_gsr.v',models/'ph1p_phy_hr_pad.v',models/'ph1p_logic_hrio.v',repo/'fpga/csi2/prj/camera_peer/uisrc/02_sim/tb_hdmi_native_stream.sv']
native=(repo/'fpga/csi2/prj/camera_peer/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v') if a.production else (repo/'fpga/csi2/diagnostics/hdmi/lane_lvds_native_x5.v')
if native.exists():
    if a.reverse_mutant:
        mutant=out/'native_wrong_order.v'
        original=native.read_text()
        assert 'I_data_in[9-b]' in original
        mutant.write_text(original.replace('I_data_in[9-b]','I_data_in[b]'))
        native=mutant
    sources.append(native)
commands=[[str(binpath/'vlib.exe'),'work'],[str(binpath/'vlog.exe'),'-sv',*(['+define+PRODUCTION_LANE'] if a.production else []),*[str(x) for x in sources]]]
commands += [[str(binpath/'vsim.exe'),'-c','-t','1fs','+notimingchecks','-voptargs=+acc','-gPHASE_PS='+str(phase),'work.tb_hdmi_native_stream','work.PH1P_PHY_GSR','-do','run -all; quit -f'] for phase in ([0] if a.reverse_mutant else [0,250,750])]
logs=[]
for i,cmd in enumerate(commands):
    r=subprocess.run(cmd,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
    t=r.stdout.decode(errors='replace');logs.append(t);(out/'regression.log').write_text('\n'.join(logs),encoding='utf-8');print(t[-2200:],flush=True)
    expected=('NATIVE_FAIL phase=0 restart=0 no continuous MSB-first stream' in t and 'NATIVE_PASS' not in t) if a.reverse_mutant else ('NATIVE_PASS' in t and 'NATIVE_FAIL' not in t)
    if r.returncode or (i>=2 and not expected):
        print('NATIVE_CHECK_INCOMPLETE',out);raise SystemExit(1)
print('NATIVE_MUTANT_REJECTED' if a.reverse_mutant else 'NATIVE_LOG',out)
