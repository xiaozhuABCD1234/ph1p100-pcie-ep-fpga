"""Snapshot and simulate the HDMI gray probe; never programs hardware."""
from pathlib import Path
import argparse, datetime, hashlib, json, subprocess

p=argparse.ArgumentParser()
p.add_argument('--baseline',action='store_true')
a=p.parse_args()
repo=Path(__file__).resolve().parents[2]
binpath=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
out=Path('D:/TD/work/csi2/_validation')/('gray_probe_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir()
names=['tb_gray_pattern_probe.sv']+([] if a.baseline else ['gray_pattern_probe.v'])
for name in names:
    (out/name).write_bytes((repo/'fpga/csi2/diagnostics/hdmi'/name).read_bytes())
commands=[['vlib.exe','work'],['vlog.exe','-sv']+(['+define+BASELINE_PASS_THROUGH'] if a.baseline else [])+names,
          ['vsim.exe','-c','work.tb_gray_pattern_probe','-do','run -all; quit -f']]
results=[]
for index,cmd in enumerate(commands):
    run=subprocess.run([str(binpath/cmd[0]),*cmd[1:]],cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
    text=run.stdout.decode(errors='replace')
    (out/f'{index}.log').write_bytes(run.stdout)
    results.append({'command':cmd,'returncode':run.returncode})
    print(text[-1800:],flush=True)
    if index<2 and (run.returncode or '** Error' in text):
        raise SystemExit('Compilation failed; not a behavioral test result: '+str(out))
passed=run.returncode==0 and 'GRAY_PROBE_PASS' in text and 'GRAY_PROBE_FAIL' not in text and '** Error' not in text and '** Fatal' not in text
negative='GRAY_PROBE_FAIL boundary count/toggle' in text and 'GRAY_PROBE_PASS' not in text
accepted=(negative if a.baseline else passed)
(out/'result.json').write_bytes((json.dumps({'baseline':a.baseline,'accepted':accepted,'behavior_passed':passed,
    'commands':results,'inputs':{n:hashlib.sha256((out/n).read_bytes()).hexdigest() for n in names}},indent=2)+'\n').encode())
print('PROBE_BASELINE_REJECTED' if a.baseline and accepted else ('PROBE_PASS' if accepted else 'PROBE_INCOMPLETE'),out)
if not accepted:raise SystemExit(1)
