"""Planner closeout only: bind existing PASS evidence; no DUT/test execution."""
from pathlib import Path
import hashlib, json, os, re

root = Path(r'D:\fpga\ph1p100')
run = root / 'workflow/runs/20261024-221529_fpga-sim-integration-recovery'
run_id = run.name
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def write_json(name, data):
    (run / name).write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
def link(label, path): return '[' + label + '](' + Path(path).as_posix() + ')'

preflight = json.loads((run / 'closeout-preflight.json').read_text(encoding='utf-8'))
assert not preflight['drift']
assert not any(preflight['root_controls_guarded'][name] for name in ['final-summary.md', 'handoff.md', 'user-summary.md', 'workflow/tasks.json'])
history = run / 'control-history/20261025-finished'
history.mkdir(parents=True, exist_ok=True)
for name in ['final-summary.md', 'handoff.md', 'user-summary.md']:
    current = run / name
    archived = history / name
    if current.exists() and not archived.exists(): archived.write_bytes(current.read_bytes())
    prepared = run / 'closeout-content' / name
    assert prepared.is_file()
    current.write_bytes(prepared.read_bytes())

specs = [
    ('T08.sync-production-sim', 'T08.sync-production-sim/manifest-r0.json', '6d9d980566997b74945066a8b015308962dcb58cd525ce868ef5837a0b482838', '/root/fpga_dev_sync_221529', '/root/fpga_tester_sync_221529'),
    ('T10.a1-uart-descriptor-fix', 'T10.a1-uart-descriptor-fix/manifest-r0.json', 'fd0cb6e7f920ba136049fdadd395f029bcd9df3d58dc2d14a2312e9a0d3c33e1', '/root/fpga_dev_descriptor_221529', '/root/fpga_tester_descriptor_221529'),
    ('T10.a1-abort-cdc-fix', 'T10.a1-abort-cdc-fix/manifest-r0.json', 'db84411dfdcf979b1fc5f6a25e11812f90f0834896a8b76787b85cd434fa5dcd', '/root/fpga_dev_abortcdc_221529', '/root/fpga_tester_abortcdc_221529'),
    ('T10.a1-recovery-sim', 'T10.a1-recovery-sim/resume02/manifest-resume02.json', '628579eae2b6b2c1afc66a477799960a6b180b213e848bdbc0e1e955437d82e1', '/root/fpga_dev_recovery_221529', '/root/fpga_tester_recovery_221529'),
]
packages = []
all_manifests = []
for task, relative, expected, developer, tester in specs:
    manifest = run / relative
    report = run / 'test-reports' / (task + '-r0-integrated.md')
    assert sha(manifest) == expected, str(manifest)
    body = report.read_text(encoding='utf-8')
    assert body.splitlines()[0] == '### 判定：PASS'
    assert body.count('### 判定：PASS') == 1 and '### 判定：FAIL' not in body
    assert expected in body, 'Report candidate binding mismatch: ' + task
    all_manifests.append(json.loads(manifest.read_text(encoding='utf-8')))
    packages.append({'task_id': task, 'verdict': 'PASS', 'round': 0, 'actual_repair_rounds': 0, 'developer_id': developer, 'tester_id': tester, 'manifest_path': str(manifest), 'manifest_sha256': expected, 'independent_report_path': str(report), 'independent_report_sha256': sha(report), 'dimension_results': {'functional': 'pass', 'engineering': 'pass', 'system': 'pass'}, 'G0': 'pass', 'G1': 'pass', 'G2': 'not_run', 'G3': 'not_applicable', 'G4': 'not_applicable', 'G5': 'not_applicable'})

binding_path = run / 'recovery-dut-binding-resume02.json'
binding = json.loads(binding_path.read_text(encoding='utf-8'))
for row in binding['files']: assert sha(row['path']) == row['sha256'], row['path']
assert len(binding['files']) == 8
top = next(row for row in binding['files'] if row['logical_name'] == 'camera_a1_uart_top.v')
exporter = next(row for row in binding['files'] if row['logical_name'] == 'a1_uart_export.v')
assert top['sha256'] == '5d0f9a001747168db39e07a10cfa417a25be797ae4013d07c3990d623310772a'
assert exporter['sha256'] == '0f3ae49ee19cc69348024e4fbe25cd3766dfec2cd8435f34f2b117bf313ba097'
candidate_index = {'run_id': run_id, 'status': 'finished', 'scope': 'Two separate offline simulation lines; never a combined board candidate', 'packages': packages, 'final_recovery_DUT_binding_path': str(binding_path), 'final_recovery_DUT_binding_sha256': sha(binding_path), 'final_recovery_DUT_files': binding['files'], 'sync_overlay_path': str(run / 'T08.sync-production-sim/candidate'), 'sync_source_mapping_path': str(run / 'T08.sync-production-sim/source-to-overlay.json'), 'production_qualified': False, 'production_written': False, 'TD_bit_download_flash': 0, 'old_AR_at_reset': 'not_covered'}
write_json('candidate-binding-final.json', candidate_index)

evaluation = json.loads((run / 'test-reports/T10.a1-recovery-sim/final-evaluation.json').read_text(encoding='utf-8'))
cases = evaluation['cases']
assert len(cases) == 20 and all(row['status'] == 'PASS' for row in cases)
packets = sum(row['packets'] for row in cases)
recovery_packets = sum(row['recovery_packets'] for row in cases)
max_cycles = max(row['recovery_elapsed'] for row in cases)
assert (packets, recovery_packets, max_cycles) == (88, 80, 10042)
assert all(row['recovery_packets'] >= 2 and row['recovery_elapsed'] <= 1000000 for row in cases)
write_json('verification-summary-final.json', {'source_path': str(run / 'test-reports/T10.a1-recovery-sim/final-evaluation.json'), 'source_sha256': sha(run / 'test-reports/T10.a1-recovery-sim/final-evaluation.json'), 'cases': [{'name': row['name'], 'ratio': row['ratio'], 'status': row['status'], 'packets': row['packets'], 'recovery_packets': row['recovery_packets'], 'recovery_elapsed': row['recovery_elapsed'], 'legal_prefix': row['legal_prefix']} for row in cases], 'positive_simulations': 20, 'packets': packets, 'recovery_packets': recovery_packets, 'max_recovery_cycles': max_cycles, 'old_AR_at_reset': 'not_covered', 'independent_checker_negatives': 17, 'independent_original_top_negative': 1, 'test_report_protected_hash_count': 855, 'test_report_hash_drift': 0})

budget_paths = [run / 'T10.a1-recovery-sim/resume02/execution-ledger-resume02.json', run / 'test-reports/T10.a1-recovery-sim/tester-execution-ledger.json']
for folder in ['T08.sync-production-sim', 'T10.a1-uart-descriptor-fix', 'T10.a1-abort-cdc-fix']:
    for path in sorted((run / folder).glob('execution*.json')):
        if path not in budget_paths: budget_paths.append(path)
for folder in ['T08.sync-production-sim', 'T10.a1-uart-descriptor-fix', 'T10.a1-abort-cdc-fix']:
    for path in sorted((run / 'test-reports' / folder).glob('*execution*ledger*.json')):
        if path not in budget_paths: budget_paths.append(path)
ledgers = [{'path': str(path), 'sha256': sha(path), 'data': json.loads(path.read_text(encoding='utf-8'))} for path in budget_paths]
recovery_developer = json.loads(budget_paths[0].read_text(encoding='utf-8'))
recovery_tester = json.loads(budget_paths[1].read_text(encoding='utf-8'))
assert recovery_developer['cumulative']['native_tool_calls'] == 60
assert recovery_developer['cumulative']['full_compiles'] == 4
assert recovery_tester['cumulative_tester']['native_tool_calls'] == 29
problem_opportunities = {'T10.a1-recovery-sim:SCOPE_CLARIFICATION:fixed-r5-descriptor-index': 1, 'T10.a1-recovery-sim:SCOPE_CLARIFICATION:crop-abort-cdc-loss': 0}
write_json('budget-ledger-final.json', {'run_id': run_id, 'formal_packages': 4, 'maximum_packages': 4, 'batch_size': 1, 'actual_repair_rounds': {row['task_id']: 0 for row in packages}, 'problem_opportunities': problem_opportunities, 'recovery_developer_cumulative': recovery_developer['cumulative'], 'recovery_tester_cumulative': recovery_tester['cumulative_tester'], 'all_available_original_ledger_sources': ledgers, 'unreported_role_totals': 'Do not invent missing exact call counts or start times; relevant independent report/actual commands remain authoritative', 'quota_history_paths': [str(run / 'relay-resume-quota.md'), str(run / 'user-feedback-01-continue.md'), str(run / 'user-feedback-02-continue.md'), str(run / 'main-log.md')], 'counters_reset': False})

lines = ['# 仿真交付索引', '', '本轮原两项仿真目标已完成，四正式包r0独立PASS。以下是隔离副本和证据入口，不是生产或上板候选。', '', '|交付|入口|', '|---|---|']
for row in packages:
    lines.append('|' + row['task_id'] + '|' + link('独立报告', row['independent_report_path']) + ' / ' + link('唯一manifest', row['manifest_path']) + '|')
lines += ['', '最终A+修正文件：', '', '- ' + link('camera_a1_uart_top.v', top['path']), '- ' + link('a1_uart_export.v', exporter['path']), '- ' + link('完整8RTL绑定', binding_path), '- ' + link('双路overlay来源映射', run / 'T08.sync-production-sim/source-to-overlay.json'), '', '交接与边界：', '', '- ' + link('最终候选/SHA索引', run / 'candidate-binding-final.json'), '- ' + link('最终指南', run / 'fpga-design-guide-final.md') + ' / ' + link('最终输入索引', run / 'input-index-final.md'), '- ' + link('完整总结', run / 'final-summary.md') + ' / ' + link('交接', run / 'handoff.md'), '- ' + link('20项实际结果', run / 'verification-summary-final.json') + ' / ' + link('全部原账', run / 'budget-ledger-final.json'), '', 'G0/G1通过，G2未运行，G3/G4/G5本离线包不适用；旧AR在reset时尚未完成的额外交错未覆盖。生产/TD/位流/下载/Flash均无操作，父硬件任务未置done。原失败日志/冻结输入保留，复现请使用新隔离输出目录。', '']
(run / 'delivery-index.md').write_text('\n'.join(lines), encoding='utf-8')

record_base = 'workflow/runs/' + run_id + '/'
for parent, selected in [('T08', [packages[0]]), ('T10', packages[1:])]:
    path = root / 'workflow/records' / parent / '20261025-sim-finished.md'
    text = '# ' + run_id + ' 离线仿真收束\n\n本轮finished，用户原两项仿真目标完成，四包r0独立PASS/实际验收后修复0。父硬件任务state保持原值，G2/硬件/性能未升级。\n\n'
    for row in selected:
        text += '- ' + row['task_id'] + ': PASS；manifest SHA ' + row['manifest_sha256'] + '；报告 ' + str(Path(row['independent_report_path']).relative_to(root)).replace('\\', '/') + '。\n'
    text += '\n最终入口：' + record_base + 'delivery-index.md、candidate-binding-final.json、final-summary.md、handoff.md；原恢复累计60calls/4compile/27sim，独立tester29calls/2compile/21sim，问题机会1/0和旧失败均保留。旧AR在reset时未完成not_covered；不生产/TD/下载/Flash，不自动第五包。\n'
    path.write_text(text, encoding='utf-8')

task_path = root / 'workflow/tasks.json'
before = task_path.read_bytes()
board = json.loads(before.decode('utf-8-sig'))
original = json.loads(before.decode('utf-8-sig'))
marker = '[20261025_sim-FINISHED_all4-r0-PASS]'
for t in board['tasks']:
    if t['id'] not in ['T08', 'T10']: continue
    selected = [packages[0]] if t['id'] == 'T08' else packages[1:]
    note = marker + ' Original two simulation goals complete; all four bounded work packages first integrated round0 PASS, actual repairs0. G0/G1 pass; G2 not_run; G3/4/5 N/A within offline scope; parent hardware state unchanged. Recovery final20 cases/88 packets/80 good recovery packets/max10042 cycles; old AR outstanding at reset not_covered. Isolated candidates only, no production/TD/download/Flash; no fifth package. Problem opportunities1/0 and all original blocked/budget history preserved.'
    if marker not in t.get('status_note', ''): t['status_note'] = t.get('status_note', '') + '\n' + note
    t['latest_offline_sim_run_id'] = run_id
    for row in selected:
        t.setdefault('offline_sim_packages', {})[row['task_id']] = {'status': 'PASS', 'round': 0, 'actual_repair_rounds': 0, 'manifest_path': str(Path(row['manifest_path']).relative_to(root)).replace('\\', '/'), 'manifest_sha256': row['manifest_sha256'], 'integrated_report': str(Path(row['independent_report_path']).relative_to(root)).replace('\\', '/'), 'G0': 'pass', 'G1': 'pass', 'G2': 'not_run', 'G3_G4_G5': 'not_applicable', 'parent_hardware_done': False}
    additions = ['delivery-index.md', 'candidate-binding-final.json', 'fpga-design-guide-final.md', 'input-index-final.md', 'final-summary.md', 'handoff.md', 'budget-ledger-final.json']
    additions += [str(Path(row['independent_report_path']).relative_to(run)).replace('\\', '/') for row in selected]
    additions += [str(Path(row['manifest_path']).relative_to(run)).replace('\\', '/') for row in selected]
    for relative in additions:
        full = record_base + relative
        if full not in t.setdefault('latest_evidence', []): t['latest_evidence'].append(full)
old_by = {row['id']: row for row in original['tasks']}
for t in board['tasks']:
    if t['id'] not in ['T08', 'T10']: assert t == old_by[t['id']]
    else:
        assert t['state'] == old_by[t['id']]['state']
        assert {key for key in set(t) | set(old_by[t['id']]) if t.get(key) != old_by[t['id']].get(key)} <= {'status_note', 'latest_evidence', 'offline_sim_packages', 'latest_offline_sim_run_id'}
assert task_path.read_bytes() == before, 'Concurrent task board change'
newline = '\r\n' if b'\r\n' in before else '\n'
raw = (json.dumps(board, ensure_ascii=False, indent=2) + '\n').replace('\n', newline).encode('utf-8')
if before.startswith(b'\xef\xbb\xbf'): raw = b'\xef\xbb\xbf' + raw
tmp = run / 'tasks-final-closeout.tmp'
tmp.write_bytes(raw)
assert root.resolve() in task_path.resolve().parents and run.resolve() in tmp.resolve().parents
os.replace(tmp, task_path)

dispatch = {'run_id': run_id, 'runtime': 'Codex', 'project_root': str(root), 'output_dir': str(run), 'task_ids': [row['task_id'] for row in packages], 'batch_size': 1, 'status': 'finished', 'needs_user_input': False, 'input_paths': [str(run / name) for name in ['candidate-binding-final.json', 'delivery-index.md', 'final-summary.md', 'handoff.md', 'user-summary.md']], 'write_scope': [], 'protected': ['all frozen DUT/candidates/inputs/reports and historical logs', 'production/upstream/fpga/tools/old runs/work', 'docs junction', 'D:\\TD', 'D:\\fpga_work', 'board bit/CWC/DB, shared drive mappings and other worktrees'], 'next_action': {'operation': 'relay_to_user', 'text_path': str(run / 'user-summary.md'), 'instruction': 'Relay the short user-summary.md verbatim and stop this run. All four original bounded packages are integrated PASS; no new developer/tester/monitor/production/TD/hardware action.'}, 'after_development': {'operation': 'relay_to_user', 'instruction': 'No development scheduled; finished. Only relay current summary.'}, 'scope_limits': {'major_goals': 1, 'formal_packages': 4, 'maximum_packages': 4, 'levels': 2, 'max_semantic_steps_per_package': 5, 'batch_size': 1, 'actual_repair_rounds_all_tasks': 0, 'td': 0, 'synthesis': 0, 'route': 0, 'bitgen': 0, 'cwc': 0, 'download': 0, 'flash': 0, 'production_writeback': False}, 'execution_limits': {'further_actions_scheduled': False, 'all_running_commands_completed': True, 'historical_budget_path': str(run / 'budget-ledger-final.json')}, 'package_results': [{key: row[key] for key in ['task_id', 'verdict', 'round', 'actual_repair_rounds', 'manifest_path', 'manifest_sha256', 'independent_report_path', 'G0', 'G1', 'G2', 'G3', 'G4', 'G5']} for row in packages], 'original_role_ids': {'planner': '/root/fpga_planner_sim_221529', **{row['task_id']: {'developer': row['developer_id'], 'tester': row['tester_id']} for row in packages}}, 'problem_opportunities': problem_opportunities, 'outstanding_in_scope_blockers': [], 'limits_preserved': ['G2 not_run', 'G3/G4/G5 not_applicable for offline tasks', 'old AR outstanding at reset not_covered', 'parent hardware task states unchanged'], 'question_path': None, 'user_summary_path': str(run / 'user-summary.md')}
write_json('dispatch-finished.json', dispatch)

for name in ['user-summary.md', 'delivery-index.md']:
    for target in re.findall(r'\]\((D:/[^)]+)\)', (run / name).read_text(encoding='utf-8')):
        assert Path(target).exists(), target
for row in packages:
    assert sha(row['manifest_path']) == row['manifest_sha256']
    assert sha(row['independent_report_path']) == row['independent_report_sha256']
final_artifacts = ['candidate-binding-final.json', 'verification-summary-final.json', 'budget-ledger-final.json', 'delivery-index.md', 'fpga-design-guide-final.md', 'input-index-final.md', 'final-summary.md', 'handoff.md', 'user-summary.md', 'dispatch-finished.json']
write_json('closeout-artifacts.json', {'status': 'finished', 'files': [{'path': str(run / name), 'sha256': sha(run / name), 'bytes': (run / name).stat().st_size} for name in final_artifacts]})
write_json('closeout-audit.json', {'status': 'finished', 'formal_packages': 4, 'all_first_integrated_round0_PASS': True, 'actual_repair_rounds_all_tasks': 0, 'verified_reports': 4, 'source_preflight_guarded_files': preflight['guarded_files'], 'source_preflight_drift': 0, 'final_manifest_sha_checks': 4, 'final_DUT_file_sha_checks': 8, 'recovery_cases': 20, 'packets': 88, 'recovery_packets': 80, 'max_recovery_cycles': 10042, 'old_AR_at_reset': 'not_covered', 'parent_states_before_and_after': {row['id']: row['state'] for row in original['tasks'] if row['id'] in ['T08', 'T10']}, 'unrelated_tasks_unchanged': True, 'tasks_before_sha256': hashlib.sha256(before).hexdigest(), 'tasks_after_sha256': sha(task_path), 'frozen_original_guide_and_index_unchanged': True, 'previous_planner_closeout_documents_archived': str(history), 'deletions': 0, 'production_TD_hardware_actions': 0, 'planning_preflight_command_correction': 'First nested shell quoting preflight failed before Python execution; one evidence-based correction used a saved script.'})
print(json.dumps({'status': 'finished', 'task_ids': dispatch['task_ids'], 'dispatch_path': str(run / 'dispatch-finished.json'), 'needs_user_input': False, 'user_summary_path': str(run / 'user-summary.md'), 'reports': 4, 'recovery_cases': 20, 'packets': 88, 'recovery_packets': 80, 'max_recovery_cycles': 10042}, ensure_ascii=False))
