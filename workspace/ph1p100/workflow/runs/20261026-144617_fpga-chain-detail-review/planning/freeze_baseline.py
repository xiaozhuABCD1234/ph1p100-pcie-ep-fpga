"""One-shot read-only-source audit snapshot; never edits/deletes source files."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import threading
from datetime import datetime, timezone

deadline = threading.Timer(55, lambda: os._exit(124))
deadline.daemon = True
deadline.start()
root = Path('D:/fpga/ph1p100').resolve()
out = root / 'workflow/runs/20261026-144617_fpga-chain-detail-review'
assert out.resolve().is_relative_to(root)
base = out / 'baseline'
assert not (base / 'source-manifest.json').exists(), 'Never overwrite frozen baseline'
snap = base / 'snapshot'
snap.mkdir(parents=True, exist_ok=True)
b15 = 'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b15-ddr-pace'
b17 = 'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b17-paxi-native'
sync = 'workflow/runs/20261024-221529_fpga-sim-integration-recovery'
ss = 'workflow/runs/20261025-233401_fpga-steady-state-reverdict'
selected = set()
missing = []

def add(rel):
    p = root / rel
    if p.is_file():
        selected.add(p)
    else:
        missing.append(rel)

def tree(rel, extensions, recursive=True):
    folder = root / rel
    if not folder.is_dir():
        missing.append(rel)
        return
    for p in folder.rglob('*') if recursive else folder.iterdir():
        if p.is_file() and p.suffix.lower() in extensions:
            selected.add(p)

for rel in [
    'AGENTS.md', 'README.md', 'CODEX_HANDOFF.md', 'workflow/README.md', 'workflow/tasks.json',
    'docs/项目成果整合与进度复核_2026-10-25.md',
    'docs/OpenCode_b15根因审计与定位建议_2026-10-26.md',
    'docs/DeepSeek独立检测与现行方案整合_2026-10-16.md',
    'docs/双目首版_整链路方案与团队交付.md',
    'docs/superpowers/plans/2026-10-15-fpga-remaining-strategy.md',
    'tools/a1/pc_decode.py', 'parallel/frame/frame_contract.py',
    f'{b15}/CANDIDATE-MANIFEST-b15-ddr-pace-r0.json', f'{b15}/result-r0.md',
    f'{b15}/r0/td/a1_board.al', f'{b15}/r0/td/p2_board.sdc', f'{b15}/r0/td/board_p2.adc',
    f'{b15}/r0/sim/p2_paxi_model_b15.v', f'{b15}/r0/board/captures/status_v5.txt',
    f'{b15}/r0/td/src/vendor/rtl/mtest/paxi_stg_cmd_gen.v',
    f'{b15}/r0/td/src/vendor/rtl/mtest/ph1p_ddrmc_mtest.v',
    f'{b15}/r0/td/src/vendor/ip/ddrmc_x32/src/rtl/top/ph1p_ddrmc_top.v',
    f'{b17}/dev-plan.md', f'{b17}/fpga-design-guide.md', f'{b17}/input-index.md',
    f'{sync}/delivery-index.md',
    'workflow/runs/20261025-180900_fpga-dual-offline-closure/delivery-index.md',
    f'{ss}/user-summary.md', f'{ss}/final-summary.md',
    f'{ss}/T10.ss-4run-matrix/r0/manifest-r0.json',
    f'{ss}/test-reports/T10.ss-4run-matrix-r0-integrated.md',
    'workflow/runs/20261019-0212_codex_fpga_closedloop_b2/test-reports/T06.codex-ddr-readback-int-r0-integrated.md',
    'workflow/runs/20261019-0212_codex_fpga_closedloop_b2/test-reports/T09.codex-production-int-r0-integrated.md',
    'workflow/runs/20261026-143924_fpga-1080p30-g0-production/request.md',
]:
    add(rel)

for rel, ext, recursive in [
    ('fpga/csi2/src', {'.v', '.sv'}, True),
    ('upstream/ph1p100-pcie-ep-fpga/rtl', {'.v', '.sv'}, True),
    (f'{b15}/r0/changed-src', {'.v', '.sv'}, False),
    (f'{b15}/r0/td/src', {'.v', '.sv'}, False),
    (f'{sync}/T08.sync-production-sim', {'.v', '.sv', '.md', '.json'}, False),
    (f'{sync}/inputs/production-raw', {'.v', '.sv', '.f', '.sdc'}, True),
    (f'{ss}/T10.ss-4run-matrix/r0/out', {'.csv', '.json'}, False),
]:
    tree(rel, ext, recursive)

assert len(selected) <= 500, 'Bounded snapshot file count exceeded'
assert sum(p.stat().st_size for p in selected) <= 20_000_000, 'Bounded snapshot bytes exceeded'
items = []
for n, src in enumerate(sorted(selected, key=lambda p: p.as_posix()), 1):
    before = src.read_bytes()
    digest = hashlib.sha256(before).hexdigest()
    target = snap / f'{n:04d}{src.suffix.lower()}'
    assert not target.exists(), f'Will not overwrite {target}'
    target.write_bytes(before)
    after = hashlib.sha256(src.read_bytes()).hexdigest()
    assert after == digest, f'Source drift while copying: {src}'
    assert hashlib.sha256(target.read_bytes()).hexdigest() == digest
    items.append({'source_path': str(src), 'source_relative': src.relative_to(root).as_posix(),
                  'snapshot_path': str(target), 'sha256': digest, 'size': len(before),
                  'copy_drift_check': 'pass'})

for name, args in [('git-status.txt', ['status', '--short', '--untracked-files=no']),
                   ('git-worktrees.txt', ['worktree', 'list', '--porcelain'])]:
    result = subprocess.run(['git', '-c', 'core.quotepath=false', *args], cwd=root,
                            capture_output=True, timeout=10, check=True)
    (base / name).write_bytes(result.stdout)
head = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=root, capture_output=True,
                      text=True, timeout=10, check=True).stdout.strip()
(base / 'missing-inputs.json').write_text(json.dumps(missing, ensure_ascii=False, indent=2), encoding='utf-8')
manifest = {'schema_version': 1, 'purpose': 'read-only audit snapshot; not a build candidate',
            'project_root': str(root), 'git_head': head,
            'created_utc': datetime.now(timezone.utc).isoformat(),
            'files': items, 'missing_inputs': missing,
            'source_files_modified': 0, 'hardware_actions': 0,
            'baseline_policy': 'immutable; later active-run changes excluded'}
(base / 'source-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps({'file_count': len(items), 'bytes': sum(x['size'] for x in items),
                  'missing': missing, 'head': head}, ensure_ascii=False))
deadline.cancel()
