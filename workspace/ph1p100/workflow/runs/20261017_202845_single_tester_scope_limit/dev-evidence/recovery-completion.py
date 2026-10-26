import difflib
import hashlib
import json
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道')
RUN = ROOT / 'workflow/runs/20261017_202845_single_tester_scope_limit'
EV = RUN / 'dev-evidence'
REPORT = EV / 'recovery-static-c-completion.json'
START = time.time()
DEADLINE = START + 180
checks = []

def utc():
    return datetime.now(timezone.utc).isoformat()

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

result = {'task_id':'CFG-SINGLE-TESTER-LIMITS','plan_revision':2,'recovery_revision':2,
          'return_opportunity':2,'actual_repair_round':0,'started_utc':utc(),
          'deadline_seconds':180,'verdict':'RUNNING','checks':checks,'commands':[]}

def save():
    result['last_result_utc'] = utc()
    write_json(REPORT,result)

def check(name, condition, detail=None):
    if time.time() >= DEADLINE:
        raise TimeoutError('REMAINING_STATIC_DEADLINE_180_SECONDS')
    checks.append({'name':name,'pass':bool(condition),'detail':detail})
    save()
    print(name+': '+('PASS' if condition else 'FAIL'),flush=True)
    if not condition:
        raise AssertionError(name)

def bound(path,role):
    return {'path':str(path),'sha256':sha(path),'bytes':path.stat().st_size,'role':role}

save()
try:
    dispatch = read_json(RUN/'dispatch.json')
    baseline = read_json(RUN/'config-baseline.json')
    updates = read_json(EV/'config-updates.json')
    old_a = read_json(EV/'recovery-static-a.json')
    old_b = read_json(EV/'recovery-static-b.json')
    old_c = read_json(EV/'recovery-static-c.json')
    allowed = dispatch['write_scope']['configuration_paths']
    check('RECOVERY_2_AUTHORIZED',dispatch.get('recovery_revision')==2 and dispatch['return_opportunity']['used']==2)
    check('REUSED_A_B_PASS',old_a['verdict']=='PASS' and old_b['verdict']=='PASS')
    prior_commands = old_c['commands']
    check('REUSED_C_COMPLETED_COMMANDS',len(prior_commands)==4 and
          [entry['exit_code'] for entry in prior_commands]==[0,0,0,1] and
          not any(entry['timed_out'] for entry in prior_commands))
    previous_elapsed = 300.0-float(old_c['remaining_seconds'])
    check('WITHIN_ORIGINAL_ACTIVE_STATIC_BUDGET',previous_elapsed+180.0<=300.0,previous_elapsed)
    verbose = prior_commands[3]
    check('EXISTING_VERBOSE_NOT_IGNORED_EVIDENCE',not Path(verbose['stdout_path']).read_bytes() and
          not Path(verbose['stderr_path']).read_bytes() and verbose['argv'][-3:]==[
          '.agents/skills/fpga-tester/SKILL.md','.agents/skills/fpga-orchestrator/references/work-limits.md',
          '.agents/skills/fpga-orchestrator/agents/openai.yaml'])
    result['old_c_interpretation'] = {
        'old_report_verdict_unchanged':'FAIL',
        'old_check_ignore_exit_code':1,
        'meaning':'The three queried leaf files were not ignored; empty verbose output does not require a parent directory negation match.',
        'invalid_extra_assertion':'NEW_TESTER_EXACT_NEGATED_WHITELIST required the directory exception to appear in leaf verbose output.',
        'authority':str(RUN/'recovery-opportunity-2.md'),
        'criteria_preserved':'Exact .gitignore exception, not-ignored evidence and precise ls-files visibility are all retained.'}
    byte_binding=[]
    current_bytes={}
    original_bytes={}
    for relative in allowed:
        expected = updates[relative].encode('utf-8')
        before_path = EV/'before'/relative
        if before_path.is_file():
            original_bytes[relative]=before_path.read_bytes()
        if relative=='AGENTS.md':
            marker='## 后续任务的默认工作流'
            expected=original_bytes[relative][:baseline['agents_protected_prefix']['byte_length']]+updates[relative][updates[relative].index(marker):].encode('utf-8')
        actual=(ROOT/relative).read_bytes()
        check('SAME_CANDIDATE_BYTES:'+relative,actual==expected)
        current_bytes[relative]=actual
        byte_binding.append({'path':str(ROOT/relative),'sha256':hashlib.sha256(actual).hexdigest(),
                             'expected_sha256':hashlib.sha256(expected).hexdigest(),'same':actual==expected})
    result['same_input_binding']={'method':'Exact bytes determined by original config-updates.json and apply-config.ps1, including original AGENTS protected prefix; no candidate configuration writes.',
                                  'updates':bound(EV/'config-updates.json','application_target_snapshot'),
                                  'apply_script':bound(EV/'apply-config.ps1','application_byte_semantics'),
                                  'files':byte_binding}
    save()
    new_paths=['.agents/skills/fpga-tester/SKILL.md','.agents/skills/fpga-orchestrator/references/work-limits.md',
               '.agents/skills/fpga-orchestrator/agents/openai.yaml']
    argv=['git','-c','core.fsmonitor=false','-c','core.quotepath=false','--no-pager',
          'ls-files','--others','--exclude-standard','--',*new_paths]
    stdout_path=EV/'recovery-completion-ls-files.stdout.txt'
    stderr_path=EV/'recovery-completion-ls-files.stderr.txt'
    entry={'argv':argv,'cwd':str(ROOT),'started_utc':utc(),'deadline_seconds':min(60,DEADLINE-time.time()-2),
           'stdout_path':str(stdout_path),'stderr_path':str(stderr_path),'exit_code':None,'timed_out':False}
    result['commands'].append(entry)
    save()
    with stdout_path.open('wb') as stdout,stderr_path.open('wb') as stderr:
        process=subprocess.Popen(argv,cwd=ROOT,stdout=stdout,stderr=stderr,creationflags=subprocess.CREATE_NO_WINDOW)
        entry['owned_pid']=process.pid
        try:
            entry['exit_code']=process.wait(timeout=entry['deadline_seconds'])
        except subprocess.TimeoutExpired:
            entry['timed_out']=True
            process.kill()
            try:
                entry['exit_code']=process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                entry['termination_incomplete']=True
            raise TimeoutError('OWN_VISIBILITY_QUERY_DEADLINE')
        finally:
            entry['ended_utc']=utc()
            save()
    visible={line.replace('\\','/').strip() for line in stdout_path.read_text(encoding='utf-8').splitlines() if line.strip()}
    check('ONLY_NEW_VISIBILITY_COMMAND_EXIT',entry['exit_code']==0,entry)
    check('EXACT_NEW_FILE_SET_VISIBLE',visible==set(new_paths),sorted(visible))
    diffs=[]
    changed=[]
    for relative in allowed:
        before=original_bytes.get(relative,b'').decode('utf-8')
        after=current_bytes[relative].decode('utf-8')
        if before==after:
            continue
        changed.append(relative)
        diffs.append('diff --git a/'+relative+' b/'+relative+'\n')
        if relative in new_paths:
            diffs.append('new file mode 100644\n')
        diffs.extend(difflib.unified_diff(before.splitlines(keepends=True),after.splitlines(keepends=True),
                    fromfile='/dev/null' if relative in new_paths else 'a/'+relative,tofile='b/'+relative))
    check('ALL_AND_ONLY_19_CONFIG_DIFFS',set(changed)==set(allowed))
    (RUN/'candidate.diff').write_text(''.join(diffs),encoding='utf-8')
    result['verdict']='PASS'
    result['completed_utc']=utc()
    result['elapsed_seconds']=time.time()-START
    save()
    summary={'task_id':'CFG-SINGLE-TESTER-LIMITS','plan_revision':2,'recovery_revision':2,
             'return_opportunity':2,'actual_repair_round':0,'verdict':'PASS',
             'scope':'Developer local static verification only; independent integrated test remains pending.',
             'reused_pass_reports':[bound(EV/'recovery-static-a.json','reused_stage_a'),bound(EV/'recovery-static-b.json','reused_stage_b')],
             'preserved_failed_reports':[bound(EV/'static-timeout.json','preserved_timeout'),bound(EV/'recovery-static-c.json','preserved_extra_assertion_failure')],
             'completion':bound(REPORT,'remaining_stage_c_checks_and_interpretation'),
             'prior_active_static_seconds':previous_elapsed,'completion_seconds':time.time()-START,
             'total_active_static_seconds':previous_elapsed+time.time()-START,'total_static_ceiling_seconds':300,
             'full_repository_status_run':False,'candidate_configuration_modified_during_recovery':False}
    write_json(EV/'recovery-static-summary.json',summary)
    previous_notes=(RUN/'dev-notes.md').read_text(encoding='utf-8')
    (RUN/'dev-notes.md').write_text('''# 开发交接（冻结候选）

task_id：CFG-SINGLE-TESTER-LIMITS；plan_revision=2；recovery_revision=2；返回补充机会2/2；actual_repair_round=0；status=ready_for_test。

19份配置已经落实显式Skill执行/恢复及关闭隐式调用、单综合tester、按范围/风险保留必要三维检查、有限拆分、主不监控、子角色防循环和返回问题最多2次机会。开发已停止修改，唯一候选为candidate-manifest.json，差异为candidate.diff，正式综合验收尚未运行。

局部验证A/B通过，HEAD/分支及19路径diff --check通过。首次整段检查超时与C的额外输出断言FAIL保持原证据；原规划依据Git官方语义确认check-ignore exit1/空输出表明三个叶文件未被忽略，无需出现父目录否定规则。最后机会只补一条精确ls-files查询，实际exit0且输出集合恰为三新增配置。未重跑已通过范围、check-ignore、全仓库status或旧脚本，未修改任何19份候选配置。

同输入复用依据为原config-updates.json及apply-config.ps1确定的实际目标字节，逐个与当前19文件完全相等，AGENTS保护前缀采用原before字节。新旧证据/解释、唯一新命令真实退出与日志、SHA及总静态预算见dev-evidence/recovery-static-c-completion.json和recovery-static-summary.json；原失败未改为PASS。manifest绑定当前规划/测试输入、两个恢复清单、19配置、差异和所有相关实际证据。

G0/G1开发自检满足；G2—G5因无RTL/构建/板卡/发布改动按规划不适用。未运行客户端选择器加载、普通聊天触发或完整多agent行为验证，未实现/安装MCP；不宣称正式测试PASS或token百分比。原其他dirty状态只引用baseline，不读取/重新哈希或声称其全局内容不变。没有任务板/生产/全局/外部写入、文件删除、提交推送或硬件操作。

主可按dispatch.after_development只派一个与开发独立的综合tester，读取最新tester-input与manifest。回退只针对本包原16配置before副本及明确范围，不reset/clean、不覆盖他人dirty、不删除新文件。该返回问题已用尽2次机会，不再自行续第3次；独立测试之后发现真实实现缺陷按原修复round1—3另账。

## 以下为保留的历史开发记录（其中未冻结/阻塞状态已经由上述最终交接替代）

'''+previous_notes,encoding='utf-8')
    with (RUN/'lessons-learned.md').open('a',encoding='utf-8') as stream:
        stream.write('\n最后机会按官方Git语义解释原exit1/空verbose证据，保留原FAIL而不篡改；只补精确ls-files真实可见性查询并做19目标字节绑定即可完成剩余静态检查。目录白名单、not-ignored及可列出三个条件分别取证，不要求工具额外输出。恢复与实现修复分账，已用尽的返回机会不重置。\n')
    planning=['request.md','dev-plan.md','fpga-design-guide.md','input-index.md','config-baseline.json',
              'tester-input.md','trigger-docs.md','recovery-opportunity-1.md','recovery-opportunity-2.md','dispatch.json']
    evidence=[EV/'recovery-static-a.json',EV/'recovery-static-b.json',EV/'recovery-static-c.json',REPORT,
              EV/'recovery-static-summary.json',EV/'static-timeout.json',EV/'recovery-owned-process-check.json',
              EV/'config-updates.json',EV/'apply-config.ps1',EV/'recovery-static.py',EV/'recovery-launch.ps1',
              EV/'recovery-completion.py',EV/'recovery-completion-launch.ps1',EV/'recovery-budget.json',
              stdout_path,stderr_path,RUN/'candidate.diff',RUN/'dev-notes.md',RUN/'lessons-learned.md']
    for command in prior_commands:
        evidence.extend([Path(command['stdout_path']),Path(command['stderr_path'])])
    for relative in original_bytes:
        evidence.append(EV/'before'/relative)
    head=Path(prior_commands[0]['stdout_path']).read_text(encoding='utf-8').strip()
    branch=Path(prior_commands[1]['stdout_path']).read_text(encoding='utf-8').strip()
    if time.time()>=DEADLINE:
        raise TimeoutError('FREEZE_DEADLINE')
    manifest={'task_id':'CFG-SINGLE-TESTER-LIMITS','plan_revision':2,'recovery_revision':2,'round':0,
              'actual_repair_round':0,'return_opportunity':2,'status':'ready_for_test','candidate_frozen':True,
              'frozen_at_utc':utc(),'project_root':str(ROOT),'worktree':str(ROOT),'head':head,'branch':branch,
              'configuration_paths':allowed,'write_list':changed,'files':[bound(ROOT/p,'current_configuration') for p in allowed],
              'planning_inputs':[bound(RUN/p,'current_frozen_planning_input') for p in planning],
              'evidence':[bound(path,'developer_static_or_preserved_evidence') for path in evidence],
              'dirty':{'candidate':{p:('untracked_new' if p in new_paths else 'modified_from_baseline') for p in changed},
                       'preexisting_status_source':str(RUN/'config-baseline.json'),'preexisting_status':baseline['protected_dirty_status'],
                       'full_repository_status_run':False,'limitation':'Other preexisting contents not read or rehashed; no global immutability claim.'},
              'required_validation':['G0','G1'],'not_applicable':{'G2':'No RTL/build change','G3':'No board change',
                       'G4':'No stability/performance change','G5':'No integration/release change'},
              'formal_integrated_verdict':None,'tester_input_path':str(RUN/'tester-input.md')}
    write_json(RUN/'candidate-manifest.json',manifest)
    print('FROZEN_READY_FOR_TEST: '+str(RUN/'candidate-manifest.json'),flush=True)
except Exception as error:
    result['verdict']='FAIL'
    result['error']=repr(error)
    save()
    print('BLOCKED: '+repr(error),flush=True)
    sys.exit(1)
