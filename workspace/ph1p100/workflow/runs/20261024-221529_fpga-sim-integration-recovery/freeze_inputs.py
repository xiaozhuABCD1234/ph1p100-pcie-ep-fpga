"""Freeze bounded planning inputs; never modify or delete source files."""
from pathlib import Path
import hashlib, json, shutil

ROOT = Path(r'D:\fpga\ph1p100')
OUT = ROOT / 'workflow/runs/20261024-221529_fpga-sim-integration-recovery'
rows = []

def freeze(source, target):
    source, target = Path(source), Path(target)
    raw = source.read_bytes()
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_bytes() != raw:
        raise RuntimeError(f'Frozen target differs; refusing overwrite: {target}')
    target.write_bytes(raw)
    rows.append({'source': str(source), 'frozen': str(target), 'sha256': hashlib.sha256(raw).hexdigest(), 'bytes': len(raw)})

prod = ROOT / 'upstream/ph1p100-pcie-ep-fpga'
for source in sorted((prod / 'rtl').rglob('*')):
    if source.is_file() and source.suffix.lower() in {'.v', '.sv', '.vh', '.vhd', '.hex', '.mem'}:
        freeze(source, OUT / 'inputs/production-raw' / source.relative_to(prod))
for name in ['compile_checked.f', 'tb/top_elab_stubs.v', 'tb/tb_sync_offline.sv']:
    freeze(prod / 'sim' / name, OUT / 'inputs/production-raw/sim' / name)
for folder in ['src', 'checker']:
    base = ROOT / 'work/parallel-sim-20261024-2204/boundaries' / folder
    for source in sorted(base.rglob('*')):
        if source.is_file() and source.suffix.lower() in {'.v', '.sv', '.py'}:
            freeze(source, OUT / 'inputs/a1-r5' / folder / source.relative_to(base))
for name in ['summary.md', 'sync/inputs.json', 'sync/tb_sync_pair_boundaries.sv', 'boundaries/result.json', 'boundaries/run_boundaries.py', 'boundaries/run.do']:
    freeze(ROOT / 'work/parallel-sim-20261024-2204' / name, OUT / 'inputs/exploration' / name)
freeze(ROOT / 'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r4/sim/tb_camera_a1_uart_top.v', OUT / 'inputs/legacy-recovery/tb_camera_a1_uart_top.v')
freeze(ROOT / 'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r4/result-r4.md', OUT / 'inputs/legacy-recovery/result-r4.md')
manifest = {'purpose': 'planning input freeze, not tested candidate or hardware qualification', 'project_root': str(ROOT), 'frozen': True, 'files': rows}
(OUT / 'planning-input-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'files': len(rows), 'manifest': str(OUT / 'planning-input-manifest.json'), 'bytes': sum(r['bytes'] for r in rows)}))
