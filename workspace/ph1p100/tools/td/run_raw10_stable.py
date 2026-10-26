"""Behavioral regressions for the 891 Mbps RAW10 profile (no device model)."""
from pathlib import Path
import argparse
import datetime
import subprocess

p = argparse.ArgumentParser()
p.add_argument('suite', choices=['vtc', 'config', 'startup', 'lane_reset'])
p.add_argument('--expect-fail', action='store_true')
p.add_argument('--legacy-config', action='store_true', help='Simulation-only declaration repair for old controller negative control')
p.add_argument('--legacy-controller', type=Path, help='Archived controller source for the negative control; production is unchanged')
a = p.parse_args()
repo = Path(__file__).resolve().parents[2]
live = Path(r'D:\TD\work\csi2\prj\camera_peer')
rtl = live / 'uisrc'
tb = repo / 'fpga/csi2/prj/camera_peer/uisrc/02_sim'
groups = {
    'vtc': (['03_ip/vtc/uivtc.v'], 'tb_raw10_vtc', [0]),
    'config': (['03_ip/ui_imx415_cfg/ui_i2c.v',
                '03_ip/ui_imx415_cfg/ui_imx415_reg.v',
                '03_ip/ui_imx415_cfg/ui_cfg_imx415.v'], 'tb_raw10_config', [0, 1, 2, 3, 4, 5]),
    'startup': (['01_rtl/camera_startup.v'], 'tb_raw10_startup', [0]),
    'lane_reset': (['03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v'], 'tb_raw10_lane_reset', [0]),
}
sources, top, cases = groups[a.suite]
out = live / '_sim' / ('stable_' + a.suite + '_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir(parents=True, exist_ok=False)
b = Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
compile_sources = [str(rtl/s) for s in sources]
test_source = tb/(top+'.sv')
if a.legacy_config:
    assert a.expect_fail and a.suite == 'config'
    # Old TD accepts an implicit iic_busy; ModelSim rejects use before declaration.
    # Repair only the declaration in a temporary simulation copy, not production.
    assert a.legacy_controller and a.legacy_controller.is_file(), 'Specify an archived --legacy-controller file'
    text = a.legacy_controller.read_text(encoding='latin-1')
    assert 'ic_busy' in text and 'iic_busy' in text
    import re
    text = re.sub(r'wire\s+ic_busy\s*;', 'wire iic_busy;', text, count=1)
    fixture = out/'legacy_cfg.v'
    fixture.write_text(text, encoding='latin-1')
    compile_sources[-1] = str(fixture)
    text = test_source.read_text(encoding='utf-8')
    pattern = r'\.CLK_DIV\(CASE_ID==5 \? 499 : 7\),\s*\.START_WAIT_CYCLES\(32\),\s*\.STANDBY_WAIT_CYCLES\(80\),\.TRANSACTION_TIMEOUT_CYCLES\(CASE_ID==3 \? 32 : \(CASE_ID==5 \? 200000 : 20000\)\)'
    text, replaced = re.subn(pattern, '.CLK_DIV(CASE_ID==5 ? 499 : 7)', text, count=1)
    assert replaced == 1, 'Legacy test parameter adapter did not match'
    test_source = out/(top+'.sv')
    test_source.write_text(text, encoding='utf-8')
cmds = [[str(b/'vlib.exe'), 'work'],
        [str(b/'vlog.exe'), '-sv', *compile_sources, str(test_source)]]
cmds += [[str(b/'vsim.exe'), '-c', '-voptargs=+acc', '-gCASE_ID='+str(c),
          'work.'+top, '-do', 'run -all; quit -f'] for c in cases]
logs = []
for cmd in cmds:
    r = subprocess.run(cmd, cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    s = r.stdout.decode('utf-8', errors='replace')
    logs.append(s)
    (out/'regression.log').write_text('\n'.join(logs), encoding='utf-8')
    print(s[-2200:])
    if r.returncode:
        raise SystemExit(r.returncode)
print('STABLE_EVIDENCE', out)
if a.expect_fail:
    if not any('STABLE_FAIL' in s for s in logs[2:]):
        raise SystemExit('Negative control must fail behaviorally')
    print('STABLE_RED_EXPECTED_FAILURE')
elif not all('STABLE_PASS' in s and 'STABLE_FAIL' not in s for s in logs[2:]):
    raise SystemExit('Stable profile regression failed')
