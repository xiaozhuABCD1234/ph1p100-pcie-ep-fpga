"""Planner-only bounded dispatch and records; no DUT development or testing."""
from pathlib import Path
import hashlib, json, os
root = Path(r'D:\fpga\ph1p100')
run = root / 'workflow/runs/20261024-221529_fpga-sim-integration-recovery'
task = 'T10.a1-abort-cdc-fix'
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
resume_manifest = run / 'T10.a1-recovery-sim/resume01/manifest-resume01.json'
resume = json.loads(resume_manifest.read_text(encoding='utf-8'))
seen = set()
for row in resume.get('test_inputs', []) + resume.get('files', []):
    if isinstance(row, dict) and 'path' in row and 'sha256' in row:
        assert sha(row['path']) == row['sha256'], row['path']
        seen.add(row['path'])
binding_path = run / 'recovery-dut-binding-resume01.json'
binding = json.loads(binding_path.read_text(encoding='utf-8'))
for row in binding['files']: assert sha(row['path']) == row['sha256'], row['path']
assert len(binding['files']) == 8
exporter = next(row for row in binding['files'] if row['logical_name'] == 'a1_uart_export.v')
assert exporter['sha256'] == '0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097'
base = json.loads((run / 'dispatch-dq-fix-r0.json').read_text(encoding='utf-8'))
d = {key: base[key] for key in ['run_id', 'runtime', 'project_root', 'output_dir', 'batch_size']}
d.update(task_ids=[task], run_task_ids=['T08.sync-production-sim', 'T10.a1-recovery-sim', 'T10.a1-uart-descriptor-fix', task], status='ready', needs_user_input=False)
d['input_paths'] = [str(run / name) for name in [
    'request.md', 'user-feedback-01-continue.md', 'planner-abort-cdc-fix.md',
    'recovery-dut-binding-resume01.json', 'planning-input-manifest.json',
    'T10.a1-recovery-sim/resume01/dev-report-resume01.md',
    'T10.a1-recovery-sim/resume01/defect-evidence-resume01.json',
    'T10.a1-recovery-sim/resume01/execution-ledger-resume01.json',
    'T10.a1-recovery-sim/resume01/relay-metadata-resume01.json',
    'T10.a1-recovery-sim/resume01/manifest-resume01.json',
    'test-reports/T10.a1-uart-descriptor-fix-r0-integrated.md',
    'dispatch-abort-cdc-fix-r0.json',
]]
d['write_scope'] = [str(run / task)]
d['protected'] = ['all paths outside developer write_scope', 'all original eight RTL and all passed/blocked candidate inputs and manifests', 'passed exporter must remain byte-identical', 'production/upstream/fpga/tools and old runs/work', 'docs junction', 'D:\\TD', 'D:\\fpga_work', 'board bit/CWC/DB, shared drive mappings and other worktrees']
d['next_action'] = {
    'operation': 'spawn_agent', 'role': 'fpga-dev', 'fork_turns': 'none',
    'skill_path': str(root / '.agents/skills/fpga-dev/SKILL.md'), 'task_ids': [task], 'round': 0,
    'instruction': 'Read AGENTS, fpga-dev skill, input_paths and planner-abort-cdc-fix.md. Execute only fourth package T10.a1-abort-cdc-fix under existing continuation authorization, no repeated scope approval. One new candidate camera_a1_uart_top.v only: source holding/pending abort and real FIFO w_ready/whole-frame loss handling, ordered abort delivery, destination RAW/skid/admission abort priority and directly required statistics. Seven other RTL including passed exporter remain SHA-identical. Reproduce original abort-only loss, handle full-FIFO abort/overflow without losing control or creating half frames, test asynchronous clock ratios, stall/reset/fresh-SOF boundaries and original-top effective negative control. Re-run complete clean/reset/bad-frame/overflow recovery matrix. No protocol/core/store/FIFO module edits, production/TD/hardware changes or fifth package. Freeze one unique manifest plus full corrected-dut-index.json (new top + passed exporter + original six), stopped_modifying=true, active_commands=0; return relay metadata only, no agents.',
}
d['after_development'] = {
    'operation': 'spawn_single_tester', 'role': 'fpga-tester',
    'skill_path': str(root / '.agents/skills/fpga-tester/SKILL.md'),
    'when': 'ready_for_test, unique new manifest, stopped_modifying=true, active_commands=0',
    'dimension': 'integrated', 'round': 0,
    'write_scope': [str(run / 'test-reports' / task), str(run / 'test-reports' / f'{task}-r0-integrated.md')],
    'instruction': 'One new independent integrated tester. Read same plan/dispatch and developer unique manifest. Independently rebuild real corrected top/eight RTL, inspect narrow diff and CDC token/stall/reset/RAW ownership logic. Independently rerun required abort-only/full-FIFO/overflow/reset/SOF boundaries with two asynchronous ratios and complete clean/reset/recovery matrix; verify actual abort acceptance/slot release, strict bytes/zlib/four CRC/epoch/no duplicate/tail, effective old-top failure and checker negatives. No historical input PASS reuse. Input/protected hashes before/after. One integrated report, functional/engineering/system, G0/G1 required; G2 not_run, G3/G4/G5 N/A. No candidate edits/TD/hardware.',
}
d['after_test'] = {
    'operation': 'return_to_planner',
    'instruction': 'Return to original planner /root/fpga_planner_sim_221529 with actual role IDs, verdict/report/manifest/corrected-dut-index, all counters and retest. PASS permits planner to bind combined immutable top+exporter+six originals and resume original recovery developer /root/fpga_dev_recovery_221529 in resume02; do not create fifth task or reset original history. True unblocked FAIL uses this task original developer/tester max3 actual repairs; new required file/module beyond scope or missing conditions returns planner for closeout within4 packages.',
}
d['scope_limits'] = {'major_goals': 1, 'formal_packages': 4, 'maximum_packages': 4, 'levels': 2, 'max_semantic_steps_per_package': 5, 'batch_size': 1, 'max_actual_repair_rounds': 3, 'allowed_changed_RTL_files_this_package': ['candidate/camera_a1_uart_top.v'], 'td': 0, 'synthesis': 0, 'route': 0, 'bitgen': 0, 'cwc': 0, 'download': 0, 'flash': 0, 'production_writeback': False}
d['execution_limits'] = {'developer_tool_calls': 60, 'developer_minutes': 75, 'tester_tool_calls': 45, 'tester_minutes': 60, 'read_search_seconds': 60, 'local_compile_or_single_sim_seconds': 300, 'full_compiles_per_dispatch': 2, 'same_failed_command_max_attempts': 2, 'same_issue_search_rounds': 3, 'consecutive_no_progress_cycles': 2, 'reason': 'Source holding and reliable ordered abort across a full real FIFO, RAW ownership boundaries, two-clock positive/negative cases and full recovery matrix need bounded environment preparation.'}
d['preserved_state'] = {
    'T08.sync-production-sim': {'verdict': 'PASS', 'round': 0, 'actual_repair_rounds': 0},
    'T10.a1-uart-descriptor-fix': {'verdict': 'PASS', 'round': 0, 'actual_repair_rounds': 0},
    'T10.a1-recovery-sim': {'status': 'blocked_awaiting_abort_CDC_corrected_input', 'developer_id': '/root/fpga_dev_recovery_221529', 'tester_id': None, 'integrated_test_started': False, 'actual_repair_rounds': 0, 'cumulative_tool_calls': 42, 'cumulative_full_compiles': 2, 'cumulative_clean_simulations': 3, 'cumulative_fault_simulations': 3, 'pre_elaboration_launch_failures': 1, 'resume01_manifest_path': str(resume_manifest), 'resume01_manifest_sha256': sha(resume_manifest)},
}
d['problem_opportunities'] = {'T10.a1-recovery-sim:SCOPE_CLARIFICATION:fixed-r5-descriptor-index': 1, 'T10.a1-recovery-sim:SCOPE_CLARIFICATION:crop-abort-cdc-loss': 0}
d['question_path'] = None
d['user_summary_path'] = None
(run / 'dispatch-abort-cdc-fix-r0.json').write_text(json.dumps(d, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

task_path = root / 'workflow/tasks.json'
before = task_path.read_bytes()
board = json.loads(before.decode('utf-8-sig'))
original = json.loads(before.decode('utf-8-sig'))
t = next(row for row in board['tasks'] if row['id'] == 'T10')
t['status_note'] = t.get('status_note', '') + '\n[20261025_abort-cdc-fourth-package] Original recovery resume01 blocked by distinct crop-abort valid-gating loss: bad frame produced no RAW abort, four good frames yielded zero recovery; two clean/two reset local cases passed, overflow not_run. Cumulative calls42/compile2/clean3/fault3/pre-elaboration failure1/actual repairs0 retained. Fourth and final allowed package T10.a1-abort-cdc-fix ready: isolated top-only ordered abort/full-FIFO/frame rejection and RAW release, no change to passed exporter or six originals. Total4/4; no production/TD/download/Flash; prior problem opportunity1, new abort problem0.'
packages = t.setdefault('offline_sim_packages', {})
packages['T10.a1-recovery-sim'] = d['preserved_state']['T10.a1-recovery-sim']
packages[task] = {'status': 'ready', 'actual_repair_rounds': 0, 'scope': 'isolated camera_a1_uart_top abort/overflow CDC recovery', 'G0_G1': 'required', 'G2': 'not_run', 'parent_hardware_done': False}
for name in ['T10.a1-recovery-sim/resume01/dev-report-resume01.md', 'T10.a1-recovery-sim/resume01/defect-evidence-resume01.json', 'T10.a1-recovery-sim/resume01/manifest-resume01.json', 'planner-abort-cdc-fix.md', 'dispatch-abort-cdc-fix-r0.json']:
    relative = 'workflow/runs/20261024-221529_fpga-sim-integration-recovery/' + name
    if relative not in t.setdefault('latest_evidence', []): t['latest_evidence'].append(relative)
old_by = {row['id']: row for row in original['tasks']}
for row in board['tasks']:
    if row['id'] != 'T10': assert row == old_by[row['id']]
    else:
        assert row['state'] == old_by[row['id']]['state']
        assert {key for key in set(row) | set(old_by[row['id']]) if row.get(key) != old_by[row['id']].get(key)} <= {'status_note', 'latest_evidence', 'offline_sim_packages'}
assert task_path.read_bytes() == before, 'Concurrent task board change'
newline = '\r\n' if b'\r\n' in before else '\n'
raw = (json.dumps(board, ensure_ascii=False, indent=2) + '\n').replace('\n', newline).encode('utf-8')
if before.startswith(b'\xef\xbb\xbf'): raw = b'\xef\xbb\xbf' + raw
tmp = run / 'tasks-abort-cdc-update.tmp'
tmp.write_bytes(raw)
assert root.resolve() in task_path.resolve().parents and run.resolve() in tmp.resolve().parents
os.replace(tmp, task_path)
assert all(Path(path).is_file() for path in d['input_paths'])
for row in binding['files']: assert sha(row['path']) == row['sha256'], row['path']
for row in resume.get('test_inputs', []) + resume.get('files', []):
    if isinstance(row, dict) and 'path' in row and 'sha256' in row: assert sha(row['path']) == row['sha256'], row['path']
audit = {'status': 'ready', 'task_ids': [task], 'dispatch_path': str(run / 'dispatch-abort-cdc-fix-r0.json'), 'needs_user_input': False, 'formal_packages': 4, 'maximum_packages': 4, 'verified_resume_manifest_entries': len(seen), 'verified_binding_DUT_files': 8, 'mismatches': 0, 'source_resume01_manifest_sha256': sha(resume_manifest), 'original_recovery_actual_repair_rounds': 0, 'problem_opportunities': d['problem_opportunities']}
(run / 'planner-abort-cdc-audit.json').write_text(json.dumps(audit, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(audit, ensure_ascii=False))
