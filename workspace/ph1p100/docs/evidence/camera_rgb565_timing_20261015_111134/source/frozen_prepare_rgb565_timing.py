"""Freeze one timing-only candidate from the exact accepted WB inputs."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--physical-strategy', choices=('TimingHigh', 'TimingUltra'), default='TimingHigh')
args = parser.parse_args()
ROOT = Path(__file__).resolve().parents[2]
BASE = Path('D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


require(sha(BASE/'input_manifest.json') == '8f8e4efe9b9320cbc595f94e337395744dbd957630576123576ee2c357f9a1c8', 'Baseline manifest mismatch')
require(sha(BASE/'camera_ddr_display.bit') == '4d591c31da9a71b9c261972e5089930af3e441c2096ed37736c8d2340ddd8865', 'Baseline bit mismatch')
manifest = json.loads((BASE/'input_manifest.json').read_bytes())
require(len(manifest) == 220, 'Baseline input count mismatch')
for rel, digest in manifest.items():
    path = (BASE/rel).resolve()
    require(path.is_relative_to(BASE.resolve()) and sha(path) == digest, 'Baseline input mismatch: '+rel)
OUT = BASE.parent/('camera_rgb565_timing_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
require(not OUT.exists(), 'Never overwrite a candidate')
OUT.mkdir()
changes = {}
for rel in manifest:
    path = OUT/rel
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = (BASE/rel).read_bytes()
    relocated = raw.replace(BASE.as_posix().encode(), OUT.as_posix().encode()) if path.suffix == '.v' else raw
    path.write_bytes(relocated)
    if raw != relocated:
        changes[rel] = {'reason':'Relocate ROM path; ROM contents unchanged', 'before_sha256':manifest[rel], 'sha256':sha(path)}
rel = 'camera_rgb565_display_guarded.v'
(OUT/rel).write_bytes((ROOT/'fpga/csi2/src/mem'/rel).read_bytes())
require(sha(OUT/rel) != manifest[rel], 'Optimization source is unchanged')
changes[rel] = {'reason':'Use existing synchronized user-domain release for enables; retain asynchronous ready-loss reset', 'before_sha256':manifest[rel], 'sha256':sha(OUT/rel)}
if args.physical_strategy == 'TimingUltra':
    rel = 'build_rgb565.tcl'
    raw = (OUT/rel).read_bytes()
    old = b'set_strategy -run phy_1 TimingHigh'
    require(raw.count(old) == 1, 'Ambiguous physical strategy selection')
    (OUT/rel).write_bytes(raw.replace(old, b'set_strategy -run phy_1 TimingUltra', 1))
    changes[rel] = {'reason':'Official PH1 TimingUltra physical effort; same synthesis RTL and constraints', 'before_sha256':manifest[rel], 'sha256':sha(OUT/rel)}
(OUT/'frozen_prepare_rgb565_timing.py').write_bytes(Path(__file__).read_bytes())
inputs = {p.relative_to(OUT).as_posix():sha(p) for p in sorted(OUT.rglob('*')) if p.is_file()}
require(len(inputs) == 221, 'Unexpected input count')
for rel in manifest:
    require(rel in changes or inputs[rel] == manifest[rel], 'Unexpected change: '+rel)
(OUT/'input_manifest.json').write_bytes((json.dumps(inputs,indent=2)+'\n').encode())
(OUT/'timing_overlay.json').write_bytes((json.dumps({
    'base':str(BASE),'baseline_manifest_sha256':sha(BASE/'input_manifest.json'),
    'input_count':len(inputs),'changes':changes,'required_setup_ns':0.3,
    'physical_strategy':args.physical_strategy,
    'unchanged_constraints':{rel:inputs[rel] for rel in ('board.adc','timing.sdc')},
    'hardware_verified':False,'hardware_download':False,
},indent=2)+'\n').encode())
print(OUT)
