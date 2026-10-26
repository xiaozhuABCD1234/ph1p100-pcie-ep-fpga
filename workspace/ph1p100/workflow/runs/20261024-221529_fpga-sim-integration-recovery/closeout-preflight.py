"""Read-only audit of frozen inputs and mutable closeout filenames."""
from pathlib import Path
import hashlib, json
root = Path(r'D:\fpga\ph1p100')
run = root / 'workflow/runs/20261024-221529_fpga-sim-integration-recovery'
sources = [run / name for name in [
    'T08.sync-production-sim/manifest-r0.json',
    'T10.a1-uart-descriptor-fix/manifest-r0.json',
    'T10.a1-abort-cdc-fix/manifest-r0.json',
    'T10.a1-recovery-sim/resume02/manifest-resume02.json',
    'test-reports/T10.a1-recovery-sim/frozen-hash-index.json',
]]
guarded = {}
def collect(data):
    if isinstance(data, dict):
        if isinstance(data.get('path'), str) and isinstance(data.get('sha256'), str):
            guarded.setdefault(data['path'], set()).add(data['sha256'])
        for key, value in data.items():
            if isinstance(key, str) and ':/' in key.replace('\\', '/'):
                digest = value if isinstance(value, str) else value.get('sha256') if isinstance(value, dict) else None
                if isinstance(digest, str) and len(digest) == 64:
                    guarded.setdefault(key, set()).add(digest)
            collect(value)
    elif isinstance(data, list):
        for item in data: collect(item)
mentions = []
for path in sources:
    text = path.read_text(encoding='utf-8')
    collect(json.loads(text))
    mentions.append({'file': str(path.relative_to(run)), 'mentions': [name for name in ['final-summary.md', 'handoff.md', 'user-summary.md', 'fpga-design-guide.md', 'input-index.md'] if name in text]})
drift = []
for name, digests in guarded.items():
    path = Path(name)
    actual = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
    if actual not in digests or len(digests) != 1:
        drift.append({'path': name, 'expected': sorted(digests), 'actual': actual})
protected_names = {str(Path(name).resolve()).lower() for name in guarded}
controls = {name: str((run / name).resolve()).lower() in protected_names for name in ['final-summary.md', 'handoff.md', 'user-summary.md', 'fpga-design-guide.md', 'input-index.md']}
controls['workflow/tasks.json'] = str((root / 'workflow/tasks.json').resolve()).lower() in protected_names
result = {'guarded_files': len(guarded), 'drift': drift, 'root_controls_guarded': controls, 'mentions': mentions}
(run / 'closeout-preflight.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'guarded_files': len(guarded), 'drift_count': len(drift), 'root_controls_guarded': controls, 'mentions': mentions}, ensure_ascii=False))
assert not drift, drift
