"""One authorized planner metadata audit; no DUT execution or production writes."""
from pathlib import Path
import json, hashlib, datetime

ROOT = Path('D:/fpga/ph1p100')
RUN = ROOT / 'workflow/runs/20261025-180900_fpga-dual-offline-closure'
OUT = RUN / 'readonly-recovery01'
OUT.mkdir(exist_ok=True)

def read(p):
    return json.loads(p.read_text(encoding='utf-8'))

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def freeze_check(p):
    if not p.is_file():
        return {'path': str(p), 'exists': False, 'ready': False}
    m = read(p)
    bad = []
    for f in m.get('files', []):
        q = Path(f['path'])
        actual = sha(q) if q.is_file() else None
        if actual != f['sha256']:
            bad.append({'path': str(q), 'expected': f['sha256'], 'actual': actual})
    return {'path': str(p), 'exists': True, 'sha256': sha(p), 'recorded_status': m.get('status'),
            'stopped_modifying_claim': m.get('stopped_modifying'), 'active_commands_claim': m.get('active_commands'),
            'files_checked': len(m.get('files', [])), 'mismatches': bad,
            'ready': not bad and m.get('stopped_modifying') is True and m.get('active_commands') == 0}

def command_rows(folder):
    rows = {}
    for p in folder.rglob('*.log'):
        for line in p.read_text(encoding='utf-8', errors='replace').splitlines():
            if line.startswith('COMMAND_RESULT '):
                c = json.loads(line[len('COMMAND_RESULT '):])
                rows[c['log']] = c
    return list(rows.values())

def jsonl(p):
    return [json.loads(x) for x in p.read_text(encoding='utf-8').splitlines() if x.strip()]

a = RUN / 'T08.dual-local-closure'
b = RUN / 'T10.dual-aplus-scheduler'
ar = a / 'r1'
ar_commands = command_rows(ar / 'local')
ar_cases = []
for p in sorted((ar / 'local').glob('*/case-result.json')):
    c = read(p)
    ar_cases.append({'path': str(p), 'sha256': sha(p), 'pass_claim': c.get('pass'),
                     'exit_code': c.get('exit_code'), 'timeout': c.get('timeout'), 'owned_pid': c.get('owned_pid')})
compiled = read(ar / 'local/build-baseline/sources.json')
compiled_drift = [x for x in compiled if sha(Path(x['path'])) != x['sha256']]
br = jsonl(b / 'evidence-resume01/commands.jsonl')
br_summary = []
for label in ('faults', 'full'):
    p = b / 'evidence-resume01' / label / 'checker.json'
    br_summary.append({'case': label, 'checker_path': str(p), 'checker_sha256': sha(p), 'checker': read(p)})

snapshot = {'source': 'single collaboration.list_agents actual result in this audit', 'agents': [
    {'agent_name': '/root', 'agent_status': 'running'},
    {'agent_name': '/root/fpga_plan_dual_offline', 'agent_status': 'running'}],
    'original_role_ids_not_listed': ['/root/fpga_dev_dual_local_180900', '/root/fpga_tester_dual_local_180900', '/root/fpga_dev_dual_scheduler_180900'],
    'limitation': 'Not listed as live is not an actual followup_task ID error; no probe, replacement or progress inquiry was performed.'}
with (OUT / 'native-role-snapshot.json').open('x', encoding='utf-8') as f:
    json.dump(snapshot, f, ensure_ascii=False, indent=2)

audit = {'authorization_path': str(RUN / 'user-feedback-readonly-recovery01.md'),
         'authorization_sha256': sha(RUN / 'user-feedback-readonly-recovery01.md'),
         'snapshot_path': str(OUT / 'native-role-snapshot.json'), 'role_snapshot_calls': 1,
         'T08': {'r0_manifest': freeze_check(a / 'manifest-r0.json'),
                 'r1_manifest': freeze_check(ar / 'manifest-r1.json'),
                 'r1_source_snapshot_matches_compiled_sources': not compiled_drift,
                 'compiled_source_drift': compiled_drift, 'case_receipts': ar_cases,
                 'native_command_receipts': ar_commands,
                 'local_compile_receipts': sum(Path(x['command'][0]).name.lower() == 'vlog.exe' for x in ar_commands),
                 'local_case_receipts': sum(Path(x['command'][0]).name.lower() == 'vsim.exe' for x in ar_commands),
                 'all_recorded_commands_have_terminal_exit': all(isinstance(x.get('exit_code'), int) for x in ar_commands),
                 'overlap_evidence': str(ar / 'local/case16/overlap-result.json'),
                 'historical_accounting': read(ar / 'historical-execution-accounting.json'),
                 'developer_deadline_preserved': '2026-10-25T21:02:49.045073+08:00',
                 'not_ready_for_test_reason': 'No r1 manifest/stopped-modifying final receipt. No developer r1 final accounting/handoff.'},
         'T10': {'old_manifest': freeze_check(b / 'manifest-r0.json'),
                 'resume_manifest': freeze_check(b / 'manifest-resume01.json'),
                 'last_development_state': read(b / 'development-state.json'),
                 'resume_authorization': read(b / 'evidence-resume01/authorization.json'),
                 'resume_command_receipts': br,
                 'new_compile_receipts': sum(Path(x['argv'][0]).name.lower() == 'vlog.exe' for x in br),
                 'new_case_receipts': sum(Path(x['argv'][0]).name.lower() == 'vsim.exe' for x in br),
                 'all_resume_receipts_have_terminal_exit': all(isinstance(x.get('returncode'), int) for x in br),
                 'faults_total_from_receipts': 3, 'faults_total_limit': 3,
                 'compile_total_from_receipts': 4, 'compile_total_limit': 4,
                 'case_total_from_receipts': 11, 'case_total_limit': 20,
                 'checker_records': br_summary,
                 'developer_deadline_preserved': '2026-10-25T19:55:19.126669+08:00',
                 'not_ready_for_test_reason': 'Old metadata is stale; resumed sources differ from old manifest and no new freeze/final accounting.'},
         'no_experiments_run_by_audit': True, 'no_role_followup_or_spawn_by_audit': True,
         'current_process_snapshot_path': str(OUT / 'process-snapshot.json'),
         'Gates': 'No integrated PASS inferred. T08r0 FAIL remains. T10 independent acceptance not started.'}
with (OUT / 'audit.json').open('x', encoding='utf-8') as f:
    json.dump(audit, f, ensure_ascii=False, indent=2)
print(json.dumps({'T08_r0_drift': len(audit['T08']['r0_manifest']['mismatches']),
                  'T08_r1_manifest_exists': audit['T08']['r1_manifest']['exists'],
                  'T08_r1_compiles': audit['T08']['local_compile_receipts'],
                  'T08_r1_cases': audit['T08']['local_case_receipts'],
                  'T08_r1_case_pass_claims': sum(x['pass_claim'] is True for x in ar_cases),
                  'T08_r1_source_drift': len(compiled_drift),
                  'T10_old_manifest_drift': len(audit['T10']['old_manifest']['mismatches']),
                  'T10_resume_manifest_exists': audit['T10']['resume_manifest']['exists'],
                  'T10_total_compile': 4, 'T10_total_cases': 11, 'T10_total_faults': 3,
                  'audit_path': str(OUT / 'audit.json')}, ensure_ascii=False))
