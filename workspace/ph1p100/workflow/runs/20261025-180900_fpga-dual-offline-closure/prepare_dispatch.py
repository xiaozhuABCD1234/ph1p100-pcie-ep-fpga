"""Planner-only metadata freeze. Does not develop, compile, simulate or touch hardware."""
from pathlib import Path
import hashlib
import json
import subprocess
import datetime

RUN = Path(__file__).resolve().parent
ROOT = RUN.parents[2]
assert ROOT == Path('D:/fpga/ph1p100')
OLD = ROOT / 'workflow/runs/20261024-221529_fpga-sim-integration-recovery'
SYNC = OLD / 'T08.sync-production-sim'
BASE = ROOT / 'work/b10-gap-sim-20261025-132023'
CFG = ROOT / 'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix/r0/td/src/camera/uisrc/03_ip/ui_imx415_cfg'
CONTROL = [RUN / p for p in ('request.md', 'input-index.md', 'fpga-design-guide.md', 'dev-plan.md')]

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def write_new(p, text):
    p.parent.mkdir(parents=True, exist_ok=True)
    assert p.resolve().is_relative_to(RUN)
    with p.open('x', encoding='utf-8', newline='\n') as f:
        f.write(text)

def write_json(p, data):
    write_new(p, json.dumps(data, ensure_ascii=False, indent=2) + '\n')

assert sha(SYNC / 'manifest-r0.json') == '6d9d980566997b74945066a8b015308962dcb58cd525ce868ef5837a0b482838'
assert sha(BASE / 'inputs/rtl/a1_frame_top.v') == 'c8b24775fa70793f682f1a640be175ec53f304722539cbd89550e0d4aefca65b'
assert sha(BASE / 'inputs/rtl/a1_deflate_core.v') == '6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb'
task_board_snapshot = RUN / 'inputs/task-board-at-plan.json'
write_new(task_board_snapshot, (ROOT / 'workflow/tasks.json').read_text(encoding='utf-8'))
paths = CONTROL + sorted(p for p in (SYNC / 'candidate').rglob('*') if p.is_file())
paths += [SYNC / p for p in ('manifest-r0.json', 'sync_i2c_config.v', 'sync_frame_gate.v', 'sensor_i2c.sv', 'vendor_env.sv', 'tb_production_sync.sv', 'run_t08.py', 'check_t08.py', 'README.md')]
paths += sorted(CFG.glob('*.v'))
paths += [BASE / 'inputs/rtl/a1_frame_top.v', BASE / 'inputs/rtl/a1_deflate_core.v', BASE / 'input-manifest.json', BASE / 'README.md']
paths += [task_board_snapshot]
paths += [ROOT / p for p in ('AGENTS.md', 'docs/并行工作再评估_2026-10-25.md', 'tools/pcie_integration/r10f_strict.py', 'tools/a1/a1_pattern.py', 'tools/a1/pc_decode.py', '.agents/skills/fpga-planner/SKILL.md', '.agents/skills/fpga-design-guide/SKILL.md', '.agents/skills/fpga-dev/SKILL.md', '.agents/skills/fpga-tester/SKILL.md', '.agents/skills/fpga-orchestrator/references/work-limits.md', '.agents/skills/fpga-orchestrator/references/relay-contract.md', '.agents/skills/fpga-orchestrator/references/report-contract.md', 'workflow/runs/20261020-0209_singleA_aplus_closedloop/test-reports/T10.b6-a1-htab-nw-r0-integrated.md')]
paths += [OLD / 'test-reports/T08.sync-production-sim-r0-integrated.md']
unique = sorted(set(paths), key=lambda p: str(p))
missing = [str(p) for p in unique if not p.is_file()]
assert not missing, 'Missing frozen inputs: ' + repr(missing)
frozen = [{'path': str(p), 'resolved_path': str(p.resolve()), 'bytes': p.stat().st_size, 'sha256': sha(p), 'access': 'read_only'} for p in unique]
status = subprocess.run(['git', 'status', '--porcelain=v1', '-uno'], cwd=ROOT, check=True, text=True, capture_output=True, timeout=60, encoding='utf-8').stdout
write_new(RUN / 'git-status-before.txt', status)
write_json(RUN / 'planning-input-manifest.json', {'schema': 'dual-offline-planning-v1', 'project_root': str(ROOT), 'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'files': frozen, 'input_policy': 'Verify sha before copying; no active b11 sources. No test or hardware claim.', 'source_config_files': [str(p) for p in sorted(CFG.glob('*.v'))]})

role_limits = {'read_search_timeout_seconds': 60, 'compile_static_small_case_timeout_seconds': 300, 'full_size_t10_case_timeout_seconds': 600, 'max_search_rounds_per_problem': 3, 'same_failed_command_total_attempts': 2, 'retry_requires_new_evidence': True, 'no_progress_cycles_before_stop': 2, 'development_calls': 60, 'development_minutes': 90, 'development_compiles': 4, 'tester_calls': 45, 'tester_minutes': 60, 'tester_compiles': 2, 'max_case_processes_per_role_per_dispatch': 20, 'max_actual_repair_rounds': 3, 'td': 0, 'hardware': 0, 'download': 0, 'flash': 0, 'reason': 'Real production top/I2C readback and real codec full-size two-frame runs require bounded additional offline preparation; limits frozen before dispatch.'}
protected = ['D:/TD/**', 'D:/fpga_work/**', 'D:/fpga/ph1p100/upstream/**', 'D:/fpga/ph1p100/fpga/**', 'D:/fpga/ph1p100/tools/**', 'D:/fpga/ph1p100/docs/** (junction to OneDrive)', 'D:/fpga/ph1p100/work/**', 'D:/fpga/ph1p100/workflow/runs/20261020-0209_singleA_aplus_closedloop/** (including OpenCode b11)', 'D:/fpga/ph1p100/workflow/runs/20261024-221529_fpga-sim-integration-recovery/**', 'all other worktrees, production/bit/CWC/BID/DB, shared drive mappings', 'workflow/tasks.json: developer/tester read-only; planner minimum closeout append with concurrency check only', 'this run planning/control files, sibling task directories and sibling evidence']
common_inputs = [str(p) for p in CONTROL] + [str(RUN / 'planning-input-manifest.json')]
scope = {'primary_goals': 1, 'formal_work_packages': 2, 'max_formal_work_packages': 4, 'levels': 2, 'max_semantic_steps_per_package': 5, 'batch_size': 1, 'requested_packages_authority': {'quote': '上述两者尝试使用工作流技能派好分配下去做理线闭环', 'source': str(RUN / 'request.md'), 'meaning': 'two explicitly referenced work packages, no batch-size override'}, 'scope_count_overrides': [], 'parallelism': 'two independent one-task dispatches; do not share developer or tester'}
tasks = [('T08.dual-local-closure', 'dual_local', str(SYNC), 'T08'), ('T10.dual-aplus-scheduler', 'dual_scheduler', str(BASE), 'T10')]
actions, after = [], []
for task, name, reference, parent in tasks:
    task_root = str(RUN / task)
    dev_input = RUN / 'inputs' / (task + '-developer.md')
    test_input = RUN / 'inputs' / (task + '-tester.md')
    prompt = f'''# {task}：唯一新开发输入

实际 PROJECT_ROOT=`{ROOT}`；OUTPUT_DIR=`{RUN}`；task_id=`{task}`；父任务={parent}；BATCH_SIZE=1，不跨任务复用，不派生代理。

先读根AGENTS和 `.agents/skills/fpga-dev/SKILL.md`，再读本run `request.md`、`input-index.md`、`fpga-design-guide.md`、`dev-plan.md` 本任务部分、`planning-input-manifest.json` 和现行有界/报告/传输合同。独立参考入口 `{reference}` 只读。

只写 `{task_root}/**`；引用路径先验证planning清单SHA、复制到自身candidate再改；不得改指南/共享控制/兄弟目录、生产/旧run、OpenCode活动候选、docs junction、其他工作树。冻结输入只读。禁止TD、硬件、COM、盘符映射、下载/Flash、RK/外部消息、git提交及批量删除。若需DeepSeek仅有界低风险辅助并按根AGENTS使用实际根，不能取代本角色。

本任务仅实现dev-plan的五步和冻结门槛。每次派发最多90分钟/60次实际工具调用、4次compile、20个case进程；单问题搜索3轮、同失败命令首次+1次有新证据重试，连续2次无进展即停。实际读搜60s/局部300s；T10全尺寸case600s，其余不能套用。启动前实现可控超时并只安全终止自己进程。若缺条件/到限返回blocked/problem，不自行扩权限、预算、需求或拆新包。

产物和manifest字段见dev-plan。必须保存真实命令/返回/日志/场景命中、环境stub边界、实际差异、接口映射/源闭包与lessons。完成局部检查后停止全部修改和活动，manifest `stopped_modifying=true, active_commands=0` 才ready_for_test。开发不宣称独立验收PASS。

返回只含task_ids、status、artifact_paths、manifest_path、test_input_paths、lessons_path、blocked（必要时problem/retest），详细技术内容留文件；如就技术需要澄清，按稳定problem_id/固定reason_code/证据/恢复路径返回原规划。
'''
    write_new(dev_input, prompt)
    write_new(test_input, f'''# {task}：本任务唯一新综合测试者输入

PROJECT_ROOT=`{ROOT}`；OUTPUT_DIR=`{RUN}`；task_id=`{task}`；BATCH_SIZE=1。你独立于开发，不派生，不跨任务复用。先读根AGENTS、`.agents/skills/fpga-tester/SKILL.md`、本run `request.md`、`fpga-design-guide.md`、`dev-plan.md`本任务及公共验收、现行report/relay/work-limits和开发实际返回的唯一manifest/test_input_paths。开发必须已停改且active_commands=0。

只写 `{RUN}/test-reports/{task}/**` 和 `{RUN}/test-reports/{task}-r<round>-integrated.md`；禁止修改候选或兄弟证据、规划输入、生产/旧run/活动b11，不执行TD/硬件/盘符/COM/下载/Flash/RK/消息/批量删除。每次60分钟/45调用，2次compile、20个case进程；搜索和重试/停止条件同dev-plan。须实际落实读搜60s、局部300s、仅T10全尺寸600s超时和cycle watchdog。

独立重编译/重跑计划中必须正常/故障/全尺寸适用项；至少一个与开发不同的判据及有效变异负对照；不能只读开发自述。G0/G1必要；G2/3/4按事先离线边界not_run，不能声称旧G2或板测属于当前候选。前后核对manifest与全部实际参与SHA，无输入漂移。三维functional/engineering/system统一报告且保留所有未测项。

报告首行唯一 `### 判定：PASS` 或 `### 判定：FAIL`，实际命令/版本/退出码/标记/原日志/候选身份/边界齐备。缺必需条件为FAIL+blocked，不能改不适用来PASS。只回task_id、dimension=integrated、dimension_results、verdict、report_path、manifest_path、blocked、retest；细节留报告。round0首次，原任务修复才续本会话，最多round1—3。
''')
    action = {'operation': 'spawn_agent', 'role': 'fpga-dev', 'skill_path': str(ROOT / '.agents/skills/fpga-dev/SKILL.md'), 'task_id': task, 'task_name': 'fpga_dev_' + name + '_180900', 'fork_turns': 'none', 'prompt_path': str(dev_input), 'input_paths': common_inputs, 'write_scope': [task_root + '/**'], 'no_cross_task_reuse': True}
    following = {'task_id': task, 'when': 'ready_for_test AND actual manifest provided AND stopped_modifying=true AND active_commands=0', 'operation': 'spawn_single_tester', 'role': 'fpga-tester', 'skill_path': str(ROOT / '.agents/skills/fpga-tester/SKILL.md'), 'task_name': 'fpga_tester_' + name + '_180900', 'fork_turns': 'none', 'prompt_path': str(test_input), 'inputs_from_developer_return': ['manifest_path', 'test_input_paths', 'artifact_paths', 'lessons_path'], 'write_scope': [str(RUN / 'test-reports' / task) + '/**', str(RUN / 'test-reports' / (task + '-r<round>-integrated.md'))], 'one_new_tester_only': True}
    data = {'run_id': RUN.name, 'project_root': str(ROOT), 'output_dir': str(RUN), 'task_ids': [task], 'batch_size': 1, 'status': 'ready', 'needs_user_input': False, 'input_paths': common_inputs, 'write_scope': action['write_scope'], 'protected': protected, 'next_action': action, 'after_development': following, 'scope_limits': scope, 'execution_limits': role_limits}
    write_json(RUN / ('dispatch-' + task + '.json'), data)
    actions.append(action | {'dispatch_path': str(RUN / ('dispatch-' + task + '.json'))})
    after.append(following)

write_json(RUN / 'dispatch.json', {'run_id': RUN.name, 'runtime': 'Codex', 'project_root': str(ROOT), 'output_dir': str(RUN), 'task_ids': [t[0] for t in tasks], 'batch_size': 1, 'status': 'ready', 'needs_user_input': False, 'input_paths': common_inputs, 'write_scope': {t[0]: [str(RUN / t[0]) + '/**'] for t in tasks}, 'protected': protected, 'scope_limits': scope, 'execution_limits': role_limits, 'next_action': actions, 'parallel_dispatch': 'Execute each listed spawn separately with a new developer, no shared write domain. Both ready; no technical dependency. If host has no free slot, queue the second operation until a real completion event. No monitoring or substitute agent.', 'after_development': after, 'after_test': {'PASS': {'operation': 'return_to_planner', 'target': '/root/fpga_plan_dual_offline', 'payload': 'Actual task_id, dimension_results, verdict, report_path, manifest_path, round, real role IDs. Original planner reads detail and updates closeout.'}, 'FAIL_without_blocked_and_repairs_lt_3': {'operation': 'followup_task', 'target': 'same task original actual developer ID', 'then': 'Stop/refreeze then followup_task same task original actual integrated tester ID; never spawn another tester.'}, 'blocked_or_external_error_or_limit': {'operation': 'return_to_planner', 'target': '/root/fpga_plan_dual_offline', 'payload': 'Exact task return/problem/evidence paths. Other independent task may continue under its unchanged dispatch.'}}, 'role_id_registration': 'Root records IDs from actual tool returns only, no guesses, progress polling or role reuse.', 'question_path': None, 'user_summary_path': None})
print(json.dumps({'status': 'ready', 'task_ids': [t[0] for t in tasks], 'frozen_files': len(frozen), 'config_files': [p.name for p in sorted(CFG.glob('*.v'))], 'dispatch_path': str(RUN / 'dispatch.json')}, ensure_ascii=False))
