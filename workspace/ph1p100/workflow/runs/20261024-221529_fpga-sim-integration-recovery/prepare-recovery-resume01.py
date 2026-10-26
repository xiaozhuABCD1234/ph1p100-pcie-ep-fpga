"""Planner-only binding/dispatch/evidence update; does not run DUT or tests."""
from pathlib import Path
import hashlib, json, os

root = Path(r'D:\fpga\ph1p100')
run = root / 'workflow/runs/20261024-221529_fpga-sim-integration-recovery'
task = 'T10.a1-recovery-sim'
def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

fix_manifest = run / 'T10.a1-uart-descriptor-fix/manifest-r0.json'
index_path = run / 'T10.a1-uart-descriptor-fix/corrected-dut-index.json'
assert sha(fix_manifest) == 'fd0cb6e7f920ba136049fdadd395f029bcd9df3d58dc2d14a2312e9a0d3c33e1'
manifest = json.loads(fix_manifest.read_text(encoding='utf-8'))
index = json.loads(index_path.read_text(encoding='utf-8'))
for row in manifest['files']:
    assert sha(row['path']) == row['sha256'], row['path']
assert index['frozen'] and len(index['files']) == 8
assert sum(row['changed'] for row in index['files']) == 1
for row in index['files']:
    assert sha(row['path']) == row['sha256'], row['path']
changed = next(row for row in index['files'] if row['changed'])
assert changed['logical_name'] == 'a1_uart_export.v'
assert changed['sha256'] == '0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097'
binding = {
    'task_id': task, 'resume_sequence': 1, 'input_status': 'changed', 'frozen': True,
    'source_fix_manifest': str(fix_manifest), 'source_fix_manifest_sha256': sha(fix_manifest),
    'source_corrected_dut_index': str(index_path), 'source_corrected_dut_index_sha256': sha(index_path),
    'independent_report_path': str(run / 'test-reports/T10.a1-uart-descriptor-fix-r0-integrated.md'),
    'independent_verdict': 'PASS', 'files': index['files'], 'rtl_paths': index['rtl_paths'],
    'original_blocked_manifest_path': str(run / 'T10.a1-recovery-sim/manifest-r0.json'),
    'original_blocked_manifest_sha256': sha(run / 'T10.a1-recovery-sim/manifest-r0.json'),
    'not_production_qualified': True,
}
(run / 'recovery-dut-binding-resume01.json').write_text(json.dumps(binding, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
d = json.loads((run / 'dispatch-t10-r0.json').read_text(encoding='utf-8'))
d.update(task_ids=[task], run_task_ids=['T08.sync-production-sim', task, 'T10.a1-uart-descriptor-fix'], status='ready', needs_user_input=False, resume_sequence=1, input_status='changed')
d['input_paths'] = [str(run / name) for name in [
    'request.md', 'user-feedback-01-continue.md', 'dev-plan.md', 'fpga-design-guide.md',
    'planner-amendment-authorized-dq-fix.md', 'planner-resume01-recovery.md',
    'recovery-dut-binding-resume01.json', 'T10.a1-recovery-sim/relay-metadata.json',
    'T10.a1-uart-descriptor-fix/corrected-dut-index.json',
    'test-reports/T10.a1-uart-descriptor-fix-r0-integrated.md', 'dispatch-recovery-resume01.json',
]]
d['write_scope'] = [str(run / 'T10.a1-recovery-sim/resume01')]
d['protected'] = [
    'all prior r0 artifacts/manifests of this task', 'all eight corrected DUT files from binding',
    'passed descriptor-fix/T08 candidates and reports', 'all paths outside current resume01 write_scope',
    'production/upstream/fpga/tools/old runs/work/docs junction', 'D:\\TD', 'D:\\fpga_work',
    'board bit/CWC/DB, shared drive mappings and other worktrees',
]
d['next_action'] = {
    'operation': 'followup_task', 'target_agent_id': '/root/fpga_dev_recovery_221529',
    'role': 'fpga-dev', 'skill_path': str(root / '.agents/skills/fpga-dev/SKILL.md'),
    'task_ids': [task], 'round': 0,
    'instruction': 'Resume original T10.a1-recovery-sim, not a new task. Read planner-resume01-recovery.md and all input_paths. Use exactly the corrected immutable eight RTL from recovery-dut-binding-resume01.json; never compile original bad exporter. Copy old TB/model/checker/runner into allowed resume01 only, preserving all old r0 artifacts. Run clean W8/H2 with >=4 complete frames, clean W32/H2, raw/encoded external-AW/W midwrite-reset W32/H2, bad-frame and real overflow. Keep injection/epoch/strict zlib/four CRC/bounded recovery/zero duplicate/zero tail and negative-control thresholds. Original counters and planner scope supplement1 remain; changed-input continuation before first integrated round0. No DUT/TD/hardware/production changes. Freeze resume01/manifest-resume01.json, stopped_modifying=true, active_commands=0, complete original+resume ledger and changed-input retest. Return relay-contract metadata only. Do not spawn agents.',
}
d['after_development'].update(
    operation='spawn_single_tester', round=0,
    when='New resume01 manifest ready_for_test, stopped_modifying=true, active_commands=0; old blocked manifest is not sufficient',
    instruction='One new independent integrated tester for original recovery task (none existed). Read current resume plan/binding/dispatch and new unique resume01 manifest. Independently rebuild exact corrected eight RTL, rerun both clean geometries and all four fault classes with actual injection/bounded recovery, epoch/source bytes, strict zlib/four CRC/zero duplicate/tail and meaningful negatives. No descriptor-fix clean or original two-frame success reused as recovery proof. Hash check before/after. One r0 integrated report; G0/G1 required, G2 not_run, G3/4/5 N/A. No candidate mutation/TD/hardware.',
)
d['after_test'] = {
    'operation': 'return_to_planner',
    'instruction': 'Return to original planner /root/fpga_planner_sim_221529 with actual tester ID, report/manifest/retest/verdict and original+resume counts for three-package closeout. True unblocked FAIL follows original developer/new tester for actual repairs1-3. Missing conditions or protected RTL changes go to planner; no fourth package or counter reset.',
}
d['scope_limits'].update(formal_packages=3, maximum_packages=4, td=0, synthesis=0, route=0, bitgen=0, cwc=0, download=0, flash=0, production_writeback=False)
d['execution_limits'].update(
    developer_tool_calls=45, developer_minutes=60, tester_tool_calls=40, tester_minutes=45,
    full_compiles_this_dispatch=2, historical_full_compiles=1,
    maximum_cumulative_full_compiles_after_this_dispatch=3,
    reason='Changed corrected DUT and explicit midwrite geometry require a fresh build; prior compile and clean retained, not reset.',
)
d['preserved_counters'] = {
    'T08_actual_repair_rounds': 0, 'descriptor_fix_actual_repair_rounds': 0,
    'recovery_actual_repair_rounds': 0, 'recovery_historical_tool_calls': 21,
    'recovery_historical_compile_count': 1, 'recovery_historical_clean_simulations': 1,
    'recovery_historical_pre_elaboration_launch_failures': 1, 'recovery_historical_fault_simulations': 0,
    'planner_scope_supplement_opportunities': 1,
}
d['completed_tasks'] = [
    {'task_id': 'T08.sync-production-sim', 'verdict': 'PASS', 'round': 0},
    {'task_id': 'T10.a1-uart-descriptor-fix', 'verdict': 'PASS', 'round': 0, 'manifest_path': str(fix_manifest), 'manifest_sha256': sha(fix_manifest)},
]
d['question_path'] = None
d['user_summary_path'] = None
(run / 'dispatch-recovery-resume01.json').write_text(json.dumps(d, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

task_path = root / 'workflow/tasks.json'
before = task_path.read_bytes()
board = json.loads(before.decode('utf-8-sig'))
original = json.loads(before.decode('utf-8-sig'))
task_record = next(row for row in board['tasks'] if row['id'] == 'T10')
task_record['status_note'] = task_record.get('status_note', '') + '\n[20261025_descriptor-PASS_recovery-resume01] Descriptor-fix r0 integrated PASS, actual repairs0; changed exporter SHA0f3ae49e, seven original RTL unchanged, G0/G1 pass, G2 not_run. Original recovery task resumes same developer with unique corrected binding; only resume01 writable. Original blocked/compile1/clean1/pre-elaboration failure1/actual repairs0/planner supplement1 retained. Total3 packages; no production/TD/download/Flash.'
packages = task_record.setdefault('offline_sim_packages', {})
packages['T10.a1-uart-descriptor-fix'] = {'status': 'PASS', 'round': 0, 'actual_repair_rounds': 0, 'manifest_sha256': sha(fix_manifest), 'G0': 'pass', 'G1': 'pass', 'G2': 'not_run', 'parent_hardware_done': False}
packages[task] = {'status': 'ready_resuming', 'resume_sequence': 1, 'input_status': 'changed', 'integrated_test_started': False, 'actual_repair_rounds': 0, 'historical_compile_count': 1, 'historical_clean_simulations': 1, 'historical_pre_elaboration_failure_count': 1, 'planner_scope_supplement_opportunities': 1, 'dut_binding': 'workflow/runs/20261024-221529_fpga-sim-integration-recovery/recovery-dut-binding-resume01.json', 'parent_hardware_done': False}
for name in ['test-reports/T10.a1-uart-descriptor-fix-r0-integrated.md', 'T10.a1-uart-descriptor-fix/manifest-r0.json', 'T10.a1-uart-descriptor-fix/corrected-dut-index.json', 'planner-resume01-recovery.md', 'recovery-dut-binding-resume01.json', 'dispatch-recovery-resume01.json']:
    relative = 'workflow/runs/20261024-221529_fpga-sim-integration-recovery/' + name
    if relative not in task_record.setdefault('latest_evidence', []):
        task_record['latest_evidence'].append(relative)
old_by_id = {row['id']: row for row in original['tasks']}
for row in board['tasks']:
    if row['id'] != 'T10':
        assert row == old_by_id[row['id']]
    else:
        assert row['state'] == old_by_id[row['id']]['state']
        assert {key for key in set(row) | set(old_by_id[row['id']]) if row.get(key) != old_by_id[row['id']].get(key)} <= {'status_note', 'latest_evidence', 'offline_sim_packages'}
assert task_path.read_bytes() == before, 'Concurrent task board change'
newline = '\r\n' if b'\r\n' in before else '\n'
encoded = (json.dumps(board, ensure_ascii=False, indent=2) + '\n').replace('\n', newline).encode('utf-8')
if before.startswith(b'\xef\xbb\xbf'):
    encoded = b'\xef\xbb\xbf' + encoded
temporary = run / 'tasks-recovery-resume01.tmp'
temporary.write_bytes(encoded)
assert root.resolve() in task_path.resolve().parents and run.resolve() in temporary.resolve().parents
os.replace(temporary, task_path)
assert all(Path(path).is_file() for path in d['input_paths'])
for row in manifest['files']:
    assert sha(row['path']) == row['sha256'], row['path']
audit = {'status': 'ready', 'task_ids': [task], 'dispatch_path': str(run / 'dispatch-recovery-resume01.json'), 'needs_user_input': False, 'manifest_files_verified': len(manifest['files']), 'corrected_DUT_files_verified': 8, 'changed_DUT_files': 1, 'mismatches': 0, 'formal_packages': 3, 'original_developer': '/root/fpga_dev_recovery_221529', 'recovery_actual_repair_rounds': 0, 'planner_scope_supplement_opportunities': 1, 'planning_command_correction': 'Prior piped -c wrapper failed before executing child source due Windows stdin encoding; native file invocation with UTF8 corrects it once.'}
(run / 'planner-recovery-resume01-audit.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(audit, ensure_ascii=False))
