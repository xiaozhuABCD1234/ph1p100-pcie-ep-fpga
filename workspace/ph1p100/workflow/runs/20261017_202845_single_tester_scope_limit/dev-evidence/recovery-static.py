import difflib
import hashlib
import json
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道')
RUN = ROOT / 'workflow/runs/20261017_202845_single_tester_scope_limit'
EV = RUN / 'dev-evidence'
MODE = sys.argv[1]
REPORT = EV / ('recovery-static-' + MODE.lower() + '.json')
checks = []
commands = []

def utc():
    return datetime.now(timezone.utc).isoformat()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

budget = read_json(EV / 'recovery-budget.json')
deadline = budget['deadline_epoch_seconds']
started = utc()

def save(verdict='RUNNING'):
    write_json(REPORT, {'task_id': 'CFG-SINGLE-TESTER-LIMITS', 'plan_revision': 2,
               'recovery_revision': 1, 'stage': MODE, 'started_utc': started,
               'last_result_utc': utc(), 'verdict': verdict, 'checks': checks,
               'commands': commands, 'remaining_seconds': deadline-time.time()})

def remaining():
    value = deadline - time.time()
    if value <= 0:
        raise TimeoutError('TOTAL_STATIC_DEADLINE_300_SECONDS')
    return value

def check(name, condition, detail=None):
    remaining()
    checks.append({'name': name, 'pass': bool(condition), 'detail': detail})
    save('RUNNING' if condition else 'FAIL')
    print(name + ': ' + ('PASS' if condition else 'FAIL'), flush=True)
    if not condition:
        raise AssertionError(name)

dispatch = read_json(RUN / 'dispatch.json')
baseline = read_json(RUN / 'config-baseline.json')
allowed = dispatch['write_scope']['configuration_paths']
files = {p: (ROOT / p).read_text(encoding='utf-8') for p in allowed}
old = {p: (EV / 'before' / p).read_text(encoding='utf-8') for p in allowed if (EV / 'before' / p).is_file()}
new_paths = [p for p in allowed if p not in old]
save()

def git(arguments, accepted=(0,)):
    limit = min(60.0, remaining()-2.0)
    if limit <= 0:
        raise TimeoutError('NO_SAFE_GIT_DEADLINE_REMAINING')
    number = len(commands)+1
    out = EV / ('recovery-git-%02d.stdout.txt' % number)
    err = EV / ('recovery-git-%02d.stderr.txt' % number)
    argv = ['git', '-c', 'core.fsmonitor=false', '-c', 'core.quotepath=false', '--no-pager', *arguments]
    entry = {'argv': argv, 'cwd': str(ROOT), 'started_utc': utc(), 'deadline_seconds': limit,
             'stdout_path': str(out), 'stderr_path': str(err), 'exit_code': None, 'timed_out': False}
    commands.append(entry)
    save()
    with out.open('wb') as stdout, err.open('wb') as stderr:
        process = subprocess.Popen(argv, cwd=ROOT, stdout=stdout, stderr=stderr,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
        entry['owned_pid'] = process.pid
        save()
        try:
            entry['exit_code'] = process.wait(timeout=limit)
        except subprocess.TimeoutExpired:
            entry['timed_out'] = True
            process.kill()
            try:
                entry['exit_code'] = process.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                entry['termination_incomplete'] = True
            entry['ended_utc'] = utc()
            save('FAIL')
            raise TimeoutError('OWN_GIT_DEADLINE')
    entry['ended_utc'] = utc()
    save()
    check('GIT_%02d_EXIT' % number, entry['exit_code'] in accepted, entry)
    return out.read_text(encoding='utf-8', errors='replace')

try:
    if MODE == 'A':
        check('REVISION_AND_PREVIOUS_JOB_TERMINATION', dispatch.get('plan_revision') == 2 and
              dispatch.get('recovery_revision') == 1 and
              read_json(EV / 'recovery-owned-process-check.json')['original_jobs_terminated'])
        check('EXACT_19_INPUTS', len(allowed) == 19 and len(old) == 16 and len(new_paths) == 3)
        for item in baseline['files']:
            relative = Path(item['path']).relative_to(ROOT).as_posix()
            check('BEFORE_SHA:' + relative, sha(EV / 'before' / relative) == item['sha256'])
        for relative in allowed:
            resolved = (ROOT / relative).resolve(strict=True)
            check('CONTAINED_FILE:' + relative, resolved.is_relative_to(ROOT.resolve()) and resolved.is_file())
        prefix = baseline['agents_protected_prefix']
        actual = (ROOT / 'AGENTS.md').read_bytes()[:prefix['byte_length']]
        check('AGENTS_PROTECTED_PREFIX', hashlib.sha256(actual).hexdigest() == prefix['sha256'])
        expected = old['.gitignore'].replace('!/.agents/skills/fpga-dev/\n', '!/.agents/skills/fpga-dev/\n!/.agents/skills/fpga-tester/\n')
        check('GITIGNORE_ONE_PRECISE_EXCEPTION', files['.gitignore'] == expected)
        check('YAML_MINIMAL_BOOLEAN_FALSE', files['.agents/skills/fpga-orchestrator/agents/openai.yaml'] == 'policy:\n  allow_implicit_invocation: false\n')
        for relative, text in files.items():
            if relative.endswith('/SKILL.md'):
                match = re.match(r'\A---\nname: ([^\n]+)\ndescription: ([^\n]+)\n---\n', text)
                check('FRONTMATTER:' + relative, bool(match) and match[1] == Path(relative).parent.name)
    elif MODE == 'B':
        check('STAGE_A_PASSED', read_json(EV / 'recovery-static-a.json')['verdict'] == 'PASS')
        missing = []
        count = 0
        for relative, text in files.items():
            if not relative.endswith('.md'):
                continue
            for target in re.findall(r'\[[^\]]+\]\(([^)]+)\)', text):
                if re.match(r'^(https?://|#|app://|codex://)', target):
                    continue
                target = target.strip('<>').split('#', 1)[0]
                if not target:
                    continue
                count += 1
                if not (ROOT / relative).parent.joinpath(target).exists():
                    missing.append(relative + ' -> ' + target)
        check('RELATIVE_LINKS_EXIST', not missing, {'count': count, 'missing': missing})
        for dimension in ('functional', 'engineering', 'system'):
            relative = '.agents/skills/fpga-tester-' + dimension + '/SKILL.md'
            def body(text):
                return text[text.index('\n\n', text.index('# FPGA')):]
            original_body = body(old[relative])
            current_body = re.sub(r'\A\n\n> \*\*历史参考，当前不独立派发。\*\*[^\n]*', '', body(files[relative]))
            check('LEGACY_BODY_PRESERVED:' + dimension, current_body == original_body)
            check('LEGACY_REFERENCE_NOTICE:' + dimension, '旧角色调度' in files[relative] and '无现行执行效力' in files[relative])
        previous = old['workflow/README.md']
        current = files['workflow/README.md']
        pattern = r'(?s)## 1\. 我们要完成什么.*?(?=## 5\. 每次验证绑定到什么)'
        check('README_PROTECTED_SECTIONS_1_TO_4', re.search(pattern, previous)[0] == re.search(pattern, current)[0])
        def protected_tail(text):
            return re.sub(r'(?m)^6\. .*\n', '', text[text.index('## 5. 每次验证绑定到什么'):])
        check('README_ONLY_5_1_ITEM_6_CHANGED', protected_tail(previous) == protected_tail(current))
        limits = files['.agents/skills/fpga-orchestrator/references/work-limits.md']
        required = ['1个主要可验收目标','4个正式工作包','两级','5项语义实现步骤','3条后续主题',
                    '30次实际工具调用','15分钟','45分钟','3轮有目标','连续2次','60000ms','60秒',
                    '5分钟','30分钟','最多2次','round1—3','TOOL_CONTROL_MISSING',
                    'new_information=false','转交重置','原授权范围','不能自行再试']
        check('FROZEN_LIMIT_AND_STOP_RULES', all(value in limits for value in required), [x for x in required if x not in limits])
        reasons = ['RETURN_FORMAT','INPUT_CONFLICT','SCOPE_CLARIFICATION','REPRO_DETAIL','TOOL_UNAVAILABLE',
                   'DEVICE_MISSING','PERMISSION_MISSING','API_ERROR','QUOTA','TOOL_CONTROL_MISSING','NO_PROGRESS','LIMIT_REACHED']
        check('FIXED_REASON_ENUM', all(value in limits for value in reasons))
        conflicts = []
        for relative, text in files.items():
            if not relative.endswith('.md') or re.search(r'fpga-tester-(functional|engineering|system)/', relative):
                continue
            for phrase in ('spawn_three_testers','新三测试','三测试并行','三个新测试','三个独立测试完成','必要时`list_agents`'):
                if phrase in text:
                    conflicts.append(relative + ':' + phrase)
        check('NO_ACTIVE_OLD_DISPATCH_OR_MONITORING', not conflicts, conflicts)
        entry_paths = ['AGENTS.md','.agents/skills/fpga-orchestrator/SKILL.md','workflow/README.md',
                       'workflow/FPGA多智能体工作流_使用说明.md','workflow/AI协作与工具接入.md','workflow/AGENTS接入片段.md']
        for relative in entry_paths:
            text = files[relative]
            check('EXPLICIT_ENTRY_AND_NON_TRIGGER:' + relative, '$fpga-orchestrator' in text and '执行' in text and
                  '恢复' in text and ('不触发' in text or '不启动' in text) and '规则' in text)
        check('SINGLE_INTEGRATED_REPORT_AND_RETEST', all(value in files['.agents/skills/fpga-orchestrator/references/relay-contract.md']
              for value in ('spawn_single_tester','一次原生spawn_agent','dimension=integrated','dimension_results','required_checks','reuse_decision_paths')))
        check('NO_UNREQUESTED_MCP_AND_STATIC_LIMITATION', all(value in files['workflow/FPGA多智能体工作流_使用说明.md']
              for value in ('无需安装MCP','静态复核配置','https://learn.chatgpt.com/docs/build-skills','https://learn.chatgpt.com/docs/extend/mcp?surface=cli')))
    elif MODE == 'C':
        check('STAGES_A_B_PASSED', all(read_json(EV / ('recovery-static-'+x+'.json'))['verdict'] == 'PASS' for x in ('a','b')))
        head = git(['rev-parse','HEAD']).strip()
        check('HEAD_MATCH', head == baseline['head'])
        branch = git(['symbolic-ref','--short','HEAD']).strip()
        check('BRANCH_MATCH', branch == baseline['branch'])
        git(['diff','--no-ext-diff','--check','--', *allowed])
        verbose = git(['check-ignore','-v','--no-index', *new_paths], accepted=(0,1))
        check('NEW_TESTER_EXACT_NEGATED_WHITELIST', '!/.agents/skills/fpga-tester/' in verbose)
        for relative in new_paths:
            git(['check-ignore','-q','--no-index',relative], accepted=(1,))
        visible = git(['ls-files','--others','--exclude-standard','--',*new_paths])
        check('THREE_NEW_FILES_TRACKING_VISIBLE', set(visible.splitlines()) == set(new_paths), visible.splitlines())
        diffs = []
        changed_paths = []
        for relative in allowed:
            before = old.get(relative, '')
            after = files[relative]
            if before == after:
                continue
            changed_paths.append(relative)
            diffs.append('diff --git a/'+relative+' b/'+relative+'\n')
            if relative in new_paths:
                diffs.append('new file mode 100644\n')
            diffs.extend(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True),
                         fromfile='/dev/null' if relative in new_paths else 'a/'+relative, tofile='b/'+relative))
        (RUN / 'candidate.diff').write_text(''.join(diffs), encoding='utf-8')
        check('CONFIG_ONLY_DIFF_ALL_19', set(changed_paths) == set(allowed), changed_paths)
        save('PASS')
        summary = {'task_id':'CFG-SINGLE-TESTER-LIMITS','plan_revision':2,'recovery_revision':1,
                   'actual_repair_round':0,'return_opportunity':1,'verdict':'PASS',
                   'stages':{x: str(EV / ('recovery-static-'+x+'.json')) for x in ('a','b','c')},
                   'elapsed_seconds':time.time()-budget['start_epoch_seconds'], 'total_deadline_seconds':300,
                   'scope':'developer static checks only; independent integrated test not yet run',
                   'previous_timeout_retained':str(EV / 'static-timeout.json'), 'full_repository_status_run':False}
        write_json(EV / 'recovery-static-summary.json', summary)
        (RUN / 'dev-notes.md').write_text('''# 开发交接（冻结候选）

task_id：CFG-SINGLE-TESTER-LIMITS；plan_revision=2；recovery_revision=1；实际修复round0前，返回补充机会1/2。

已同步19个明确允许配置路径，落实显式Skill执行/恢复、关闭隐式调用、一个综合测试者、按范围/风险的必要三维检查、1目标/4包/两级/5步骤、主不监控、子角色有限执行及问题最多2次机会。三个旧领域技能保留原专业正文并标历史参考；.gitignore仅追加新tester精确目录白名单。MCP未实现/安装，生产/任务板/全局/旧证据未写入，无文件删除、提交/推送或硬件操作。

首次整段静态检查300秒超时证据保留于dev-evidence/static-timeout.json；未声称已知其具体根因。原规划明确恢复机会后改为三个精确检查段，原作业身份已确认终止；未重复旧Start-Job整段或全仓库status。A逐文件保护/格式，B合同/链接/历史清单与README边界，C精确pathspec Git检查/可见性及冻结。每项实际结果即时保存，所有子进程有最多60秒和总300秒剩余预算控制，退出/日志见recovery-static-a/b/c.json及recovery-git输出。三段均通过，汇总见recovery-static-summary.json；这是开发局部自检，不是独立综合验收。

实际工作树/HEAD/分支及19配置SHA、当前需求/规划/恢复输入、局部证据均绑定candidate-manifest.json；candidate.diff只含本包19路径。未重新扫描或逐字证明其他既有dirty内容不变：原脏状态只引用config-baseline.json，候选dirty界限逐文件列出。AGENTS工作流之前3688字节SHA匹配基线，README第1—4节及第5节后除5.1第6项均保护，旧专业检查正文保留。

G0/G1局部静态自检满足；G2—G5按规划不适用，本包无RTL/构建/板卡/发布改动。未验证客户端选择器实际加载、普通聊天触发行为、完整多agent链或MCP执行，不作token百分比承诺。停止修改，供主按dispatch.after_development只派一个与开发独立的综合tester读tester-input.md及冻结输入；不得将此开发自检当正式PASS。

回退只针对本包自行修改的19配置，原16份字节副本在dev-evidence/before；不reset/clean、不覆盖其他dirty、不删除新文件。必要回退由规划限定明确范围后执行。当前恢复输入recovery-opportunity-1.md，正式测试仍为round0。
''', encoding='utf-8')
        (RUN / 'lessons-learned.md').write_text('''# 本包开发经验

首次整段自检只有末尾结果，300秒超时后不能定位语句，已保存真实失败并停止。原规划给同范围恢复机会后，改为精确命名文件、A/B/C小段及每条即时结果；Git输出直接重定向文件，有限wait/kill，不再用旧异步.Result包装或全仓库status。恢复不增加任务、角色、上限或实际实现修复轮数。自检与独立综合验收分账，完成冻结后才派测试。
''', encoding='utf-8')
        def bound(path, role):
            return {'path':str(path), 'sha256':sha(path), 'bytes':path.stat().st_size, 'role':role}
        planning_names = ['request.md','dev-plan.md','fpga-design-guide.md','input-index.md','config-baseline.json',
                          'tester-input.md','trigger-docs.md','recovery-opportunity-1.md','dispatch.json']
        evidence_paths = [EV / ('recovery-static-'+x+'.json') for x in ('a','b','c')]
        evidence_paths += [EV / 'recovery-static-summary.json', EV / 'recovery-owned-process-check.json',
                           EV / 'recovery-budget.json', EV / 'recovery-static.py', EV / 'recovery-launch.ps1',
                           EV / 'static-timeout.json', RUN / 'candidate.diff', RUN / 'dev-notes.md', RUN / 'lessons-learned.md']
        for command in commands:
            evidence_paths += [Path(command['stdout_path']),Path(command['stderr_path'])]
        remaining()
        manifest = {'task_id':'CFG-SINGLE-TESTER-LIMITS','plan_revision':2,'recovery_revision':1,
                    'round':0,'actual_repair_round':0,'return_opportunity':1,'status':'ready_for_test',
                    'candidate_frozen':True,'frozen_at_utc':utc(),'project_root':str(ROOT),'worktree':str(ROOT),
                    'head':head,'branch':branch,'configuration_paths':allowed,'write_list':changed_paths,
                    'files':[bound(ROOT / p, 'current_configuration') for p in allowed],
                    'planning_inputs':[bound(RUN / p, 'frozen_planning_input') for p in planning_names],
                    'evidence':[bound(p,'developer_static_evidence') for p in evidence_paths],
                    'dirty':{'candidate':{p:('untracked_new' if p in new_paths else 'modified_from_baseline') for p in changed_paths},
                             'preexisting_status_source':str(RUN / 'config-baseline.json'),
                             'preexisting_status':baseline['protected_dirty_status'], 'full_repository_status_run':False,
                             'limitation':'Preexisting unrelated contents were not read or rehashed; no global immutability claim.'},
                    'required_validation':['G0','G1'],'not_applicable':{'G2':'No RTL/build change','G3':'No board change',
                    'G4':'No stability/performance change','G5':'No integrated release change'},
                    'formal_integrated_verdict':None,'tester_input_path':str(RUN / 'tester-input.md')}
        write_json(RUN / 'candidate-manifest.json',manifest)
        print('FROZEN_READY_FOR_TEST: '+str(RUN / 'candidate-manifest.json'),flush=True)
        sys.exit(0)
    else:
        raise ValueError('Unknown stage')
    save('PASS')
except Exception as error:
    checks.append({'name':'UNHANDLED_OR_STOP_CONDITION','pass':False,'detail':repr(error)})
    save('FAIL')
    print('BLOCKED: '+repr(error),flush=True)
    sys.exit(1)
