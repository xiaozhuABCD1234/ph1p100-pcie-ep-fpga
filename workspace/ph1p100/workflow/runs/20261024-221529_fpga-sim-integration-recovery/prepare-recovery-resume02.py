"""Freeze the passed combined DUT and resume existing recovery task only."""
from pathlib import Path
import hashlib, json, os
root = Path(r'D:\fpga\ph1p100')
run = root / 'workflow/runs/20261024-221529_fpga-sim-integration-recovery'
task = 'T10.a1-recovery-sim'
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
fix_manifest = run / 'T10.a1-abort-cdc-fix/manifest-r0.json'
index_path = run / 'T10.a1-abort-cdc-fix/corrected-dut-index.json'
assert sha(fix_manifest) == 'db84411dfdcf979b1fc5f6a25e11812f90f0834896a8b76787b85cd434fa5dcd'
assert sha(index_path) == '804bd7139e11337f537100bc1f0f573ea302cc14ffe7959430aae3168af606ae'
manifest = json.loads(fix_manifest.read_text(encoding='utf-8'))
index = json.loads(index_path.read_text(encoding='utf-8'))
checked = set()
def verify_tree(value):
    if isinstance(value, dict):
        if isinstance(value.get('path'), str) and isinstance(value.get('sha256'), str):
            assert sha(value['path']) == value['sha256'], value['path']
            checked.add(value['path'])
        for child in value.values(): verify_tree(child)
    elif isinstance(value, list):
        for child in value: verify_tree(child)
verify_tree(manifest)
assert index['frozen'] and len(index['files']) == 8
previous = json.loads((run / 'recovery-dut-binding-resume01.json').read_text(encoding='utf-8'))
prev_by_name = {row['logical_name']: row for row in previous['files']}
files = []
for row in index['files']:
    assert sha(row['path']) == row['sha256'], row['path']
    row = dict(row)
    row['changed_vs_original'] = row['sha256'] != row['original_sha256']
    row['changed_vs_resume01'] = row['sha256'] != prev_by_name[row['logical_name']]['sha256']
    files.append(row)
assert sum(row['changed_vs_original'] for row in files) == 2
assert sum(row['changed_vs_resume01'] for row in files) == 1
assert next(row for row in files if row['logical_name'] == 'camera_a1_uart_top.v')['sha256'] == '5d0f9a001747168db39e07a10cfa417a25be797ae4013d07c3990d623310772a'
assert next(row for row in files if row['logical_name'] == 'a1_uart_export.v')['sha256'] == '0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097'
assets = [run / 'T10.a1-abort-cdc-fix' / name for name in ['tb_recovery.sv', 'ddr_recovery_model.sv', 'check_recovery.py', 'run_abort.py', 'run_final_matrix.py', 'run.do', 'TB-version-binding.json']]
binding = {
    'task_id': task, 'resume_sequence': 2, 'input_status': 'changed', 'frozen': True,
    'purpose': 'Combined passed simulation DUT; no production/implementation qualification',
    'source_fix_manifest': str(fix_manifest), 'source_fix_manifest_sha256': sha(fix_manifest),
    'source_corrected_dut_index': str(index_path), 'source_corrected_dut_index_sha256': sha(index_path),
    'independent_report_path': str(run / 'test-reports/T10.a1-abort-cdc-fix-r0-integrated.md'),
    'independent_verdict': 'PASS', 'files': files, 'rtl_paths': index['rtl_paths'],
    'changed_vs_original_count': 2, 'changed_vs_resume01_count': 1,
    'previous_binding': str(run / 'recovery-dut-binding-resume01.json'),
    'previous_binding_sha256': sha(run / 'recovery-dut-binding-resume01.json'),
    'test_asset_sources': [{'path': str(path), 'sha256': sha(path)} for path in assets],
    'not_production_qualified': True,
}
(run / 'recovery-dut-binding-resume02.json').write_text(json.dumps(binding, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
d = json.loads((run / 'dispatch-recovery-resume01.json').read_text(encoding='utf-8'))
d.update(task_ids=[task], run_task_ids=['T08.sync-production-sim', task, 'T10.a1-uart-descriptor-fix', 'T10.a1-abort-cdc-fix'], status='ready', needs_user_input=False, resume_sequence=2, input_status='changed')
d['input_paths'] = [str(run / name) for name in [
    'request.md', 'user-feedback-01-continue.md', 'dev-plan.md', 'fpga-design-guide.md',
    'planner-abort-cdc-fix.md', 'planner-resume02-recovery.md', 'recovery-dut-binding-resume02.json',
    'T10.a1-recovery-sim/resume01/relay-metadata-resume01.json',
    'T10.a1-recovery-sim/resume01/execution-ledger-resume01.json',
    'T10.a1-abort-cdc-fix/corrected-dut-index.json', 'T10.a1-abort-cdc-fix/relay-metadata.json',
    'test-reports/T10.a1-abort-cdc-fix-r0-integrated.md', 'dispatch-recovery-resume02.json',
]]
d['write_scope'] = [str(run / 'T10.a1-recovery-sim/resume02')]
d['protected'] = ['all prior r0/resume01 artifacts and manifests', 'all eight immutable combined DUT files and passed fix/T08 candidates', 'all paths outside current resume02 write_scope', 'production/upstream/fpga/tools/old runs/work/docs junction', 'D:\\TD', 'D:\\fpga_work', 'board bit/CWC/DB, shared drive mappings and other worktrees']
d['next_action'] = {
    'operation': 'followup_task', 'target_agent_id': '/root/fpga_dev_recovery_221529',
    'role': 'fpga-dev', 'skill_path': str(root / '.agents/skills/fpga-dev/SKILL.md'), 'task_ids': [task], 'round': 0,
    'instruction': 'Resume original recovery task into resume02 only. Read planner-resume02-recovery.md and all input_paths. Exact corrected immutable eight RTL are frozen by recovery-dut-binding-resume02.json (new top+passed exporter+six originals); do not modify DUT or old artifacts. Prefer copying the passed fourth-package test assets into resume02 with before/after source mapping and path-only adapter diffs, then real rebuild/re-run all twenty prescribed cases across both asynchronous ratios, full strict recovery/source/zlib/four-CRC/epoch/slot/stall checks and effective negatives. No old success logs reused as current PASS. Preserve original 42 calls/compile2/clean3/fault3/pre-elaboration failure1/actual repairs0 and problem opportunities1/0. First integrated test still round0. No fifth package, production/TD/hardware. Freeze resume02/manifest-resume02.json, stopped_modifying=true, active_commands=0, cumulative ledger and changed-input retest; return relay-contract metadata only. No child agents.',
}
d['after_development'].update(
    when='New resume02 manifest ready_for_test, stopped_modifying=true, active_commands=0; old blocked/fix manifests alone not sufficient',
    instruction='One new independent integrated tester for original recovery task (never previously tested). Read current resume02 plan/binding/dispatch and new unique manifest. Independently rebuild exact combined eight RTL and rerun twenty-case recovery matrix across both asynchronous ratios, plus effective old-top/checker negatives and a different source/byte/slot criterion. Do not inherit dependency task PASS or resume01 partial results. Check all input/protected hashes before/after. One T10.a1-recovery-sim-r0-integrated.md, three dimensions; G0/G1 required, G2 not_run and G3/4/5 N/A. Report outstanding old-AR-at-reset boundary as not covered if not hit, rather than claiming it. No candidate edits/TD/hardware.',
)
d['after_test'] = {
    'operation': 'return_to_planner',
    'instruction': 'Return to original planner /root/fpga_planner_sim_221529 with actual tester ID, verdict/report/manifest/retest and full original/resume01/resume02 counts for four-package closeout. True unblocked FAIL follows original developer/new tester for actual repair rounds1-3 within allowed test scope. Missing conditions or required extra RTL/fifth package return planner for bounded closeout; never reset counters or create new task.',
}
d['scope_limits'].update(formal_packages=4, maximum_packages=4, td=0, synthesis=0, route=0, bitgen=0, cwc=0, download=0, flash=0, production_writeback=False)
d['execution_limits'].update(developer_tool_calls=45, developer_minutes=60, tester_tool_calls=45, tester_minutes=60, full_compiles_this_dispatch=2, historical_full_compiles=2, maximum_cumulative_full_compiles_after_this_dispatch=4, reason='Final combined changed DUT plus twenty affected recovery/CDC cases; bounded tester coverage extended for independent source/slot checks without extra roles or tasks.')
d['preserved_counters'] = {'T08_actual_repair_rounds': 0, 'descriptor_fix_actual_repair_rounds': 0, 'abort_fix_actual_repair_rounds': 0, 'recovery_actual_repair_rounds': 0, 'recovery_historical_tool_calls': 42, 'recovery_historical_compile_count': 2, 'recovery_historical_clean_simulations': 3, 'recovery_historical_fault_simulations': 3, 'recovery_historical_pre_elaboration_launch_failures': 1}
d['problem_opportunities'] = {'T10.a1-recovery-sim:SCOPE_CLARIFICATION:fixed-r5-descriptor-index': 1, 'T10.a1-recovery-sim:SCOPE_CLARIFICATION:crop-abort-cdc-loss': 0}
d['completed_tasks'] = [
    {'task_id': 'T08.sync-production-sim', 'verdict': 'PASS', 'round': 0},
    {'task_id': 'T10.a1-uart-descriptor-fix', 'verdict': 'PASS', 'round': 0},
    {'task_id': 'T10.a1-abort-cdc-fix', 'verdict': 'PASS', 'round': 0, 'manifest_path': str(fix_manifest), 'manifest_sha256': sha(fix_manifest)},
]
d['question_path'] = None
d['user_summary_path'] = None
(run / 'dispatch-recovery-resume02.json').write_text(json.dumps(d, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

p = root / 'workflow/tasks.json'
before = p.read_bytes()
board = json.loads(before.decode('utf-8-sig'))
original = json.loads(before.decode('utf-8-sig'))
t = next(row for row in board['tasks'] if row['id'] == 'T10')
t['status_note'] = t.get('status_note', '') + '\n[20261025_abort-PASS_recovery-resume02] Abort-CDC fix r0 integrated PASS, actual repairs0: 20 independently executed cases/two ratios, 88 strict packets including80 recovery packets, max10042 cycles, old-top and17 checker negatives, 764 input hashes drift0. Final combined top SHA5d0f9a00 + exporter0f3ae49e + six originals now frozen for original recovery resume02. Original calls42/compile2/clean3/fault3/pre-elaboration failure1/actual repairs0 and problem opportunities1/0 retained. Total4/4, no fifth package/production/TD/download/Flash; original recovery still requires r0 integrated report.'
packages = t.setdefault('offline_sim_packages', {})
packages['T10.a1-abort-cdc-fix'] = {'status': 'PASS', 'round': 0, 'actual_repair_rounds': 0, 'manifest_sha256': sha(fix_manifest), 'G0': 'pass', 'G1': 'pass', 'G2': 'not_run', 'parent_hardware_done': False}
packages[task] = {'status': 'ready_resuming', 'resume_sequence': 2, 'input_status': 'changed', 'integrated_test_started': False, 'actual_repair_rounds': 0, 'historical_tool_calls': 42, 'historical_compile_count': 2, 'historical_clean_simulations': 3, 'historical_fault_simulations': 3, 'historical_pre_elaboration_failure_count': 1, 'problem_opportunities': d['problem_opportunities'], 'dut_binding': 'workflow/runs/20261024-221529_fpga-sim-integration-recovery/recovery-dut-binding-resume02.json', 'parent_hardware_done': False}
for name in ['test-reports/T10.a1-abort-cdc-fix-r0-integrated.md', 'T10.a1-abort-cdc-fix/manifest-r0.json', 'T10.a1-abort-cdc-fix/corrected-dut-index.json', 'planner-resume02-recovery.md', 'recovery-dut-binding-resume02.json', 'dispatch-recovery-resume02.json']:
    rel = 'workflow/runs/20261024-221529_fpga-sim-integration-recovery/' + name
    if rel not in t.setdefault('latest_evidence', []): t['latest_evidence'].append(rel)
old_by = {row['id']: row for row in original['tasks']}
for row in board['tasks']:
    if row['id'] != 'T10': assert row == old_by[row['id']]
    else:
        assert row['state'] == old_by[row['id']]['state']
        assert {key for key in set(row) | set(old_by[row['id']]) if row.get(key) != old_by[row['id']].get(key)} <= {'status_note', 'latest_evidence', 'offline_sim_packages'}
assert p.read_bytes() == before, 'Concurrent task board update'
newline = '\r\n' if b'\r\n' in before else '\n'
raw = (json.dumps(board, ensure_ascii=False, indent=2) + '\n').replace('\n', newline).encode('utf-8')
if before.startswith(b'\xef\xbb\xbf'): raw = b'\xef\xbb\xbf' + raw
tmp = run / 'tasks-recovery-resume02.tmp'
tmp.write_bytes(raw)
assert root.resolve() in p.resolve().parents and run.resolve() in tmp.resolve().parents
os.replace(tmp, p)
assert all(Path(path).is_file() for path in d['input_paths'])
verify_tree(manifest)
for row in files: assert sha(row['path']) == row['sha256'], row['path']
audit = {'status': 'ready', 'task_ids': [task], 'dispatch_path': str(run / 'dispatch-recovery-resume02.json'), 'needs_user_input': False, 'verified_manifest_paths': len(checked), 'verified_DUT_files': 8, 'changed_vs_original': 2, 'changed_vs_resume01': 1, 'mismatches': 0, 'formal_packages': 4, 'maximum_packages': 4, 'original_developer': '/root/fpga_dev_recovery_221529', 'recovery_actual_repair_rounds': 0, 'problem_opportunities': d['problem_opportunities']}
(run / 'planner-recovery-resume02-audit.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(audit, ensure_ascii=False))
