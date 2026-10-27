"""One-time provenance collector. Reads source trees; writes only beside this file.

Historical absolute paths are intentionally retained as provenance, not run instructions.
No simulator, TD, device, network, deletion, or Git command is invoked.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OLD = Path('D:/fpga/ph1p100')
RUNS = {
    'offline': ROOT / 'workflow/runs/20261027-060708_fpga-parallel-offline-delivery',
    'board': OLD / 'workflow/runs/20261027-0726_fpga-board-integration',
    'honly': OLD / 'workflow/runs/20261027-055621_fpga-honly-td-and-ah',
    'p4': OLD / 'workflow/runs/20261026-2138_fpga-integrated-delivery',
    'route-request-only': OLD / 'workflow/runs/20261027-150010_fpga-honly-td-route',
}
SOURCE_EXT = {'.v', '.sv', '.vh', '.py', '.ps1', '.tcl', '.sdc', '.adc', '.f', '.xml'}
DENY_EXT = {'.qpg', '.qdb', '.qtl', '.wlf', '.db', '.dmp', '.pyc', '.bit', '.cwc'}
rows = {}
bindings = []


def digest(p):
    h = hashlib.sha256()
    with p.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def record(src, dest=None, purpose='', reason=''):
    src = src.resolve()
    key = (str(src), dest)
    if key in rows:
        return rows[key]
    exists = src.is_file()
    row = {'source_path': str(src), 'package_path': dest, 'purpose': purpose,
           'status': 'included' if dest and exists else ('omitted' if exists else 'missing'),
           'bytes': src.stat().st_size if exists else None,
           'sha256': None, 'not_included_reason': reason or None}
    if exists and (dest or (src.suffix.lower() in SOURCE_EXT and src.stat().st_size <= 300000)):
        row['sha256'] = digest(src)
    elif exists:
        row['sha_not_computed_reason'] = 'Excluded output; not read/copied as evidence. Declared manifest SHA is retained separately where available.'
    if dest and exists:
        out = (HERE / dest).resolve()
        if not out.is_relative_to(HERE) or src == out:
            raise ValueError('invalid destination')
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, out)
        if digest(out) != row['sha256'] or digest(src) != row['sha256']:
            raise ValueError('source changed during copy: ' + str(src))
    rows[key] = row
    return row


def safe_path(p):
    return p.suffix.lower() not in DENY_EXT and not any(
        x.lower() == '__pycache__' or re.fullmatch(r'work\d*', x.lower()) for x in p.parts)


def select_run(label, base):
    for p in sorted(base.rglob('*')):
        if not p.is_file():
            continue
        rel = p.relative_to(base)
        s = rel.as_posix()
        chosen = False
        if safe_path(rel):
            if len(rel.parts) == 1 and p.suffix.lower() in {'.json', '.md'}:
                chosen = True
            elif label == 'offline':
                # Keep small scripts, TBs, summary evidence and one final control set.
                chosen = p.suffix.lower() in SOURCE_EXT | {'.md', '.json', '.jsonl', '.log', '.csv', '.txt', '.ini'}
                if '/local/controls/' in '/' + s:
                    chosen = False  # controls-final supersedes duplicate generated set
                if p.suffix.lower() in {'.bin', '.a1u1', '.raw10', '.u16', '.zlib', '.mem', '.vh'}:
                    chosen = p.stat().st_size <= 16384 and 'historical-b18/' not in s
                if p.suffix.lower() == '.hex':
                    chosen = False
            elif label == 'board':
                chosen = (p.suffix.lower() in {'.md', '.json', '.v', '.tcl', '.sdc', '.adc', '.al'}
                          or p.name in {'g1_scen0.log', 'g1_arb.log', 'flow.status', 'gate.qor', 'brd_board_gate.area'}
                          or p.name.startswith('td_01_synth_'))
            elif label == 'honly':
                chosen = (p.suffix.lower() in {'.md', '.json', '.v', '.tcl', '.sdc'}
                          or p.name in {'n-4f.frm', 'n-4f.hdr', 'n-4f.stats', 'l-4f.frm', 'l-4f.hdr', 'l-4f.stats',
                                        'route_console.log', 'synth_console.log', 'syn_flow.status', 'syn_gate_area.rpt', 'syn_gate_timing.rpt'}
                          or ('sim/logs/' in s and p.suffix.lower() == '.log'))
            elif label == 'p4':
                chosen = (s.startswith('test-reports/') and p.suffix.lower() in {'.md', '.json', '.log'})
                chosen |= s in {'INT.P4/result-r2.md', 'INT.P4/result-r3.md'}
                chosen |= s.startswith('INT.P4/r2-timing-experiment/') and p.suffix.lower() == '.v'
                chosen |= s.startswith('INT.P4/regression/') and p.suffix.lower() in {'.log', '.txt'}
                chosen |= s.startswith('INT.P4/td/') and p.name in {'syn_gate_timing.rpt', 'syn_gate_area.rpt', 'flow.status', 'gate.qor', 'README-EVIDENCE.md'}
        chosen &= p.stat().st_size <= 300000
        reason = 'Rebuildable library/database/wave/cache, duplicate generated vectors, large output or outside selected evidence; see original manifest.'
        record(p, 'archive/' + label + '/' + s if chosen else None,
               label + ': byte-preserved historical evidence', '' if chosen else reason)


def iter_refs(value):
    if isinstance(value, dict):
        if isinstance(value.get('path'), str) and isinstance(value.get('sha256'), str):
            yield value
        for item in value.values():
            yield from iter_refs(item)
    elif isinstance(value, list):
        for item in value:
            yield from iter_refs(item)


def resolve_ref(name, label, manifest):
    q = Path(name)
    if q.is_absolute():
        return q
    if label == 'honly' and (manifest.parent / q).is_file():
        return manifest.parent / q
    if label == 'honly' and (manifest.parent.parent / q).is_file():
        return manifest.parent.parent / q
    return (ROOT if label == 'offline' else OLD) / q


def import_manifest(label, manifest):
    data = json.loads(manifest.read_text(encoding='utf-8-sig'))
    for ref in iter_refs(data):
        name = ref['path']
        src = resolve_ref(name, label, manifest)
        expected = ref['sha256'].lower()
        exists = src.is_file()
        actual = digest(src) if exists and src.stat().st_size <= 3000000 else None
        binding = {'manifest': 'archive/' + label + '/' + manifest.relative_to(RUNS[label]).as_posix(),
                   'original_reference': name, 'resolved_source_path': str(src.resolve()),
                   'expected_sha256': expected, 'observed_sha256': actual,
                   'status': 'match' if actual == expected else ('drift' if actual else 'missing_or_excluded_large'),
                   'observation_reason': ('source_not_present' if not exists else
                                          ('size_over_3MiB_not_rehashed_or_packaged' if actual is None else 'sha256_compared')),
                   'package_path': None}
        # Candidate inputs are copied only when their declared hash matches.
        # Drifted active sources are not quietly treated as the frozen candidate.
        if src.suffix.lower() in SOURCE_EXT and exists and safe_path(src) and src.stat().st_size <= 300000:
            if actual == expected:
                base = ROOT if src.resolve().is_relative_to(ROOT) else OLD
                rel = src.resolve().relative_to(base).as_posix()
                dest = 'inputs/' + label + '/' + rel
                record(src, dest, label + ': manifest-matched source/TB/tool/constraint')
                binding['package_path'] = dest
            else:
                record(src, None, label + ': declared input', 'SHA drift from this manifest; not adopted as candidate')
        # A previously synced, byte-matching copy may recover a drifted active
        # source. Check only the corresponding exact path, never guess by name.
        if binding['package_path'] is None and src.suffix.lower() in SOURCE_EXT and src.resolve().is_relative_to(OLD):
            frozen = ROOT / 'workspace/ph1p100' / src.resolve().relative_to(OLD)
            if frozen.is_file() and frozen.stat().st_size <= 300000 and digest(frozen) == expected:
                dest = 'inputs/' + label + '/synced-frozen/' + src.resolve().relative_to(OLD).as_posix()
                record(frozen, dest, label + ': exact SHA-matched existing synchronized frozen input')
                binding['package_path'] = dest
                binding['frozen_source_path'] = str(frozen)
                binding['frozen_sha_matches'] = True
        bindings.append(binding)


for label, base in RUNS.items():
    select_run(label, base)

manifest_paths = {
    'offline': [RUNS['offline'] / x / 'manifest-r0.json' for x in
                ['T03.pcie-byte-replay', 'T04.real-raw10-benchmark', 'T08.freerun-isolation']],
    'board': [RUNS['board'] / 'T11.BRD.P1/manifest-brd-p1-r0.json'],
    'honly': [RUNS['honly'] / 'T10.ah-honly-synthfix/r0/manifest-r0.json',
              RUNS['honly'] / 'T10.ah-honly-td/r1/manifest-r1.json'],
    'p4': [RUNS['p4'] / 'INT.P4-r2-manifest.json', RUNS['p4'] / 'INT.P4-r3-manifest.json'],
}
for label, manifests in manifest_paths.items():
    for manifest in manifests:
        import_manifest(label, manifest)

# Preserve exact historical policy bytes without PowerShell text recoding.
policy_commit = '9c624846'
for name, expected in {
    'AGENTS.md': '5cf4afbc4c53f4da234c5c0197c59b6b68b7a8cea1d35853a20ed706ec6b1b8e',
    'docs/PROJECT_SYNC_20261027.md': '9341c93334802e53f84aaf2ddfb93b1d4858eb289d2cbb1c8cebc0db85dac8b8',
}.items():
    blob = subprocess.run(['git', 'show', policy_commit + ':' + name], cwd=ROOT,
                          capture_output=True, check=True, timeout=60).stdout
    if hashlib.sha256(blob).hexdigest() != expected:
        raise ValueError('historical Git policy SHA mismatch: ' + name)
    dest = 'historical-policy/' + name
    out = HERE / dest
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(blob)
    origin = {'repository_path': str(ROOT), 'commit': policy_commit, 'blob_path': name,
              'method': 'git show captured as raw stdout bytes'}
    rows[('git-policy', name)] = {'source_path': str(ROOT / name), 'source_git': origin,
        'package_path': dest, 'purpose': 'Exact historical policy bytes matching T03/T04 frozen references',
        'status': 'included', 'bytes': len(blob), 'sha256': expected, 'not_included_reason': None}
    for binding in bindings:
        if binding['expected_sha256'] == expected:
            binding.update(package_path=dest, matching_copy=dest, matching_copy_source_git=origin,
                           frozen_sha_matches=True)

# Resolve the board filelist's explicit assignments without invoking Tcl or TD.
filelist = RUNS['board'] / 'T11.BRD.P1/td/filelist.tcl'
variables = {}
for line in filelist.read_text(encoding='utf-8-sig').splitlines():
    if line.startswith('set ') and not line.startswith('set FL '):
        match = re.fullmatch(r'set (\w+) "?([^"\n]+)"?', line)
        if match:
            name, value = match.groups()
            for key, val in variables.items():
                value = re.sub(r'\$' + re.escape(key) + r'(?=/|$)', lambda _: val, value)
            variables[name] = value
    if line.startswith('lappend FL '):
        value = line[len('lappend FL '):].strip()
        for key, val in variables.items():
            value = re.sub(r'\$' + re.escape(key) + r'(?=/|$)', lambda _: val, value)
        src = Path(value)
        if src.is_file() and src.suffix.lower() in SOURCE_EXT:
            dest = 'inputs/board-filelist/' + src.relative_to(OLD).as_posix()
            record(src, dest, 'Board filelist input snapshot; declared manifest binding checked separately; not new acceptance')
        else:
            record(src, None, 'Board filelist dependency', 'Missing file or non-source item; teammate must adapt/build vendor IP')

# Files authored for this package have no historical source identity.
drifts = [x for x in bindings if x['status'] == 'drift']
report = ['# 归档时观察到的引用漂移', '',
          '原 manifest 与报告未改写。此表比较原 manifest 声明与读取时的活动源；有精确 SHA 冻结副本时另列位置，否则该历史输入未恢复，不可据活动同名文件复跑原候选。', '',
          '| Manifest | 原引用 | 期望 SHA256 | 活动源 SHA256 | 包内匹配副本 |',
          '| --- | --- | --- | --- | --- |']
for x in drifts:
    package = x.get('package_path')
    report.append('| `%s` | `%s` | `%s` | `%s` | %s |' % (
        x['manifest'], x['original_reference'], x['expected_sha256'], x['observed_sha256'],
        ('[' + package + '](' + package + ')') if package else '**未恢复**'))
(HERE / 'DRIFT.md').write_text('\n'.join(report) + '\n', encoding='utf-8')

for p in sorted(HERE.iterdir()):
    if p.is_file() and p.name not in {'source-map.json', 'verification.json'}:
        rows[('generated', p.name)] = {'source_path': None, 'package_path': p.name,
            'purpose': 'New handoff documentation or standard-library verification utility',
            'status': 'generated', 'bytes': p.stat().st_size, 'sha256': digest(p), 'not_included_reason': None}

result = {'schema': 1, 'scope': 'Simulation-only handoff; archived PASS claims remain bound to original manifests.',
          'roots': {k: str(v) for k, v in RUNS.items()},
          'excluded_policy': 'No compiler libraries, databases, waves, bytecode, minidumps, bit/CWC or bulk duplicate vectors. Large omitted files are not hashed.',
          'files': list(rows.values()), 'manifest_bindings': bindings}
(HERE / 'source-map.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
included = [x for x in rows.values() if x['package_path'] and x['status'] in {'included', 'generated'}]
print(json.dumps({'included': len(included), 'bytes': sum(x['bytes'] for x in included),
                  'manifest_bindings': len(bindings), 'drift': sum(x['status'] == 'drift' for x in bindings),
                  'missing_or_excluded_large': sum(x['status'] == 'missing_or_excluded_large' for x in bindings)}, indent=2))
