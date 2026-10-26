"""Test frozen sampler/TB with WB parameters extracted from the actual core."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys

if not __debug__:
    raise RuntimeError('Run this verifier without Python -O.')

parser = argparse.ArgumentParser()
parser.add_argument('project', type=Path)
args = parser.parse_args()
project = args.project.resolve()
assert project.parent == Path('D:/TD/work/csi2/prj').resolve()
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
manifest_path = project/'input_manifest.json'
manifest = json.loads(manifest_path.read_bytes())
for rel, digest in manifest.items():
    path = (project/rel).resolve()
    assert path.is_relative_to(project) and sha(path) == digest, rel
core = (project/'f9p_camera_display_core.v').read_bytes()
instances = re.findall(rb'bayer565_capture\s*#\((.*?)\)\s+u_preview\s*\(', core, re.S)
# The core's instance name is checked explicitly; do not silently test defaults.
if not instances:
    instances = re.findall(rb'bayer565_capture\s*#\((.*?)\)\s+\w+\s*\(', core, re.S)
assert len(instances) == 1
params = {}
for name in ('SW', 'SH', 'BAYER_PHASE', 'WB_R_GAIN_Q10', 'WB_B_GAIN_Q10', 'WB_BLACK_LEVEL'):
    found = re.findall(rb'\.'+name.encode()+rb'\((\d+)\)', instances[0])
    assert len(found) == 1, name
    params[name] = int(found[0])
assert params['SW'] == 960 and params['SH'] == 540 and params['BAYER_PHASE'] == 3
assert 0 <= params['WB_R_GAIN_Q10'] <= 4096 and 0 <= params['WB_B_GAIN_Q10'] <= 4096
assert 0 <= params['WB_BLACK_LEVEL'] <= 1023
out = Path('D:/TD/work/csi2/_validation')/('wb565_candidate_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir()
for source, destination in [('bayer565_capture.v', 'bayer565_capture.v'), ('frozen_tb_bayer565_white_balance.sv', 'tb_bayer565_white_balance.sv')]:
    (out/destination).write_bytes((project/source).read_bytes())
(out/'selected_core.v.snapshot').write_bytes(core)
(out/'runner.py.snapshot').write_bytes(Path(__file__).read_bytes())
bin_path = Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
r, b, black = (params[name] for name in ('WB_R_GAIN_Q10','WB_B_GAIN_Q10','WB_BLACK_LEVEL'))
result = {'project':str(project), 'manifest_sha256':sha(manifest_path), 'selected_core_sha256':sha(project/'f9p_camera_display_core.v'), 'actual_core_parameters':params, 'commands':[], 'accepted':False, 'hardware_verified':False,
          'scope':'Frozen sampler arithmetic, fixed GBRG fixture, all RAW10 values, original raw statistics and framing at reduced 16x8 geometry; no board or full-system timing claim.'}
try:
    commands = [
        ['vlib.exe','work'],
        ['vlog.exe','-sv','+define+WB_GAIN_PARAMS','bayer565_capture.v','tb_bayer565_white_balance.sv'],
        ['vsim.exe','-c',f'-gR_GAIN={r}',f'-gB_GAIN={b}',f'-gBLACK_LEVEL={black}','work.tb_bayer565_white_balance','-do','run -all; quit -f'],
    ]
    for i, argv in enumerate(commands):
        command = [str(bin_path/argv[0]), *argv[1:]]
        run = subprocess.run(command, cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
        (out/f'{i}.log').write_bytes(run.stdout)
        output = run.stdout.decode(errors='replace')
        errors = [int(v) for v in re.findall(r'Errors:\s*(\d+)',output)]
        warnings = [int(v) for v in re.findall(r'Warnings:\s*(\d+)',output)]
        result['commands'].append({'command':command,'exit_code':run.returncode,'errors':errors,'warnings':warnings,'log':f'{i}.log'})
        print(output[-1600:])
        assert run.returncode == 0 and not any(errors) and not any(warnings)
        assert not re.search(r'\*\*\s*(?:Fatal|Error|Warning)',output)
        if i == 1: assert errors == [0]
    expected = f'WB565_PASS gains={r},{b} black_level={black} frames=9 outputs=1152 output_checks=1152 stats_checks=13347 identity_checks=2048 raw_levels_R=1024 raw_levels_B=1024 fixture=GBRG'
    result['accepted'] = expected in output and 'WB565_FAIL' not in output
except Exception as error:
    result['error'] = repr(error)
finally:
    result['inputs'] = {name:sha(out/name) for name in ('bayer565_capture.v','tb_bayer565_white_balance.sv','selected_core.v.snapshot','runner.py.snapshot')}
    (out/'result.json').write_bytes((json.dumps(result,indent=2)+'\n').encode())
print('WB565_CANDIDATE_ACCEPTED' if result['accepted'] else 'WB565_CANDIDATE_REJECTED', out)
sys.exit(0 if result['accepted'] else 1)
