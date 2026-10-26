import json,pathlib,sys,time,hashlib
sys.dont_write_bytecode=True
import independent_test as e
H=e.HERE;R=e.RUN
def main():
 start=time.monotonic();f=e.js(H/'final-evaluation.json');assert f['status']=='PASS' and len(f['cases'])==20
 assert len(e.js(H/'checker-negatives.json'))==17 and all(x['rejected'] for x in e.js(H/'checker-negatives.json'))
 assert e.js(H/'old-top-independent-evaluation.json')['effective']
 audit=e.audit('final');assert audit['checked']==855 and not audit['drift']
 manifest_sha=e.sha(e.MANIFEST);now=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
 commands=[dict(path=str(p),**e.js(p)) for p in H.rglob('*.command.json')]
 e.save(H/'actual-command-index.json',commands)
 dev=e.js(e.DEV/'execution-ledger-resume02.json')
 ledger=dict(task_id='T10.a1-recovery-sim',dimension='integrated',round=0,runtime='Codex',tester_id='/root/fpga_tester_recovery_221529',actual_repair_rounds=0,
  before_usage_limit=dict(native_tool_calls=9,full_compiles=0,simulations=0,earliest_recorded_utc='2026-10-24T18:29:57Z',last_artifact_write_local='2026-10-25T02:32:27+08:00',exact_role_start_instrumented=False,stop='Actual usage-limit failure reported by parent; no tester verdict'),
  explicit_resume=dict(authorization_path=str(R/'user-feedback-02-continue.md'),earliest_recorded_local='2026-10-25T09:30:43+08:00',native_tool_calls_including_closeout=20,tool_call_limit=45,minutes_limit=60,finished_utc=now,full_compiles=2,full_compile_limit_total_this_tester=2,clean_positive_simulations=4,fault_positive_simulations=16,old_top_negative_simulations=1,simulation_retries=0,pre_elaboration_failures=0,recorded_child_commands=len(commands),modelsim_invocations=25,optional_parser_failed_attempts=2,final_evaluation_attempts=2,corrected_final_evaluation_exitcode=0,active_commands=0),
  cumulative_tester=dict(native_tool_calls=29,full_compiles=2,positive_scenarios=20,negative_scenarios=1,checker_mutations=17,actual_repair_rounds=0),
  developer_history_preserved=dev,problem_opportunities=dev['problem_opportunities'],limits=dict(read_search_seconds=60,compile_single_sim_seconds=300,same_failed_command_max_attempts=2,bulk_deletions=0,candidate_changes=0,production_changes=0,hardware_actions=0,shared_drive_changes=0))
 e.save(H/'tester-execution-ledger.json',ledger)
 reuse=dict(manifest_path=str(e.MANIFEST),manifest_sha256=manifest_sha,input_status='same',old_success_evidence_reused=False,dependency_PASS_inherited=False,fresh_independent_compiles=2,fresh_matrix_cases=20,fresh_old_top_negative=1,fresh_checker_negatives=17,before_after_protected_hashes=855,drift=0,scope='One frozen resume02 candidate; historical artifacts retained solely as provenance/guarded input. Optional invalid checker assertions are documented, not substituted for DUT results.')
 e.save(H/'reuse-decision.json',reuse)
 table=['|case|ratio|packets|recovery good|FE后 A1 cycles|合法前缀|','|---|---|---:|---:|---:|---|']
 for x in f['cases']:table.append('|'+ '|'.join([x['name'],x['ratio'],str(x['packets']),str(x['recovery_packets']),str(x['recovery_elapsed']),','.join(map(str,x['legal_prefix']))])+'|')
 rtl='\n'.join('- '+x['logical_name']+'：`'+x['sha256']+'`；`'+x['path']+'`。' for x in e.M['DUT_files'])
 report=f'''### 判定：PASS

task_id=T10.a1-recovery-sim；dimension=integrated；round=0；runtime=Codex。
测试者=/root/fpga_tester_recovery_221529，为本任务首次且唯一独立综合测试者；未派生代理。
实际工程根：D:\\fpga\\ph1p100。完成时间 UTC：{now}。
唯一被测 manifest：`{e.MANIFEST}`，SHA256=`{manifest_sha}`。
开发冻结状态已核验 ready_for_test、stopped_modifying=true、active_commands=0、blocked=null。测试前后 manifest、37项 test_input_paths 及全部索引保护输入同 SHA；唯一文件并集855项，drift=0。用户新增继续记录不改变被测 manifest。

## 三维与 G 层

|dimension|适用性|结果|必要 G 层与证据|
|---|---|---|---|
|functional|applicable|pass|G0/G1 pass；本次真实重建8RTL，20项全部实跑；直接相机源字节/严格zlib/四CRC/epoch/唯一帧与尾部检查、有效原top及17检查器负例|
|engineering|applicable|pass|G0/G1 pass；独占工作库、精化、真实超时、输入与保护SHA、CDC/stall/reset/槽所有权观察；Errors0|
|system|applicable|pass|G0/G1 pass；故障命中与恢复门槛、环境模型/旧AR未测限制明确，候选/生产/板工程隔离|

G2=not_run：规划明确本包只交付隔离固定RTL恢复仿真，不生成/发布实现候选，不改变生产时钟/约束/IP；STA、实现CDC、资源与最终数据库绑定未执行。G3/G4/G5=not_applicable：本离线包无硬件、长稳性能或发布授权。父T08/T10硬件任务不因此置done。依据为 planner-resume02-recovery.md、fpga-design-guide.md 和 dispatch-recovery-resume02.json，未临场降低门槛。

## DUT、环境与独立性

正向编译路径直接来自 recovery-dut-binding-resume02.json 的完整8RTL；未从活动生产树按同名取文件。原top负例只将 camera_a1_uart_top.v 换成冻结 original，保留当前 exporter 和六项原RTL。两个工作库位于 `{H}\\combined\\lib` 与 `{H}\\old-top\\lib`。真实源身份如下：

{rtl}

ModelSim Intel FPGA Edition vlog 10.5b Compiler 2016.10；Python {sys.version.split()[0]}，zlib {e.zlib.ZLIB_VERSION}；工具4项SHA同 manifest。编译输入包括冻结 tb_recovery.sv、ddr_recovery_model.sv，外加本测试者 independent_observer.sv；观察器仅采样和断言，无force、源驱动或DUT修改。CAM/A1 两异步比例为14ns/5.333ns、3.7ns/5.333ns，A1 phase分别1.7ns/0.91ns；UART与A1同网、UART_DIV4、PREP/PRED1、HB_DIV0、ROI(4,2)、CAM_W=W+8/H8。clean32与两中写复位 W32/H2、FIFO_AW4，其余W8/H2、FIFO_AW2。RAW_BASE0/CMP_BASE131072均为256bit word地址；W32 RAW80B实际4个DDR字，每字有效20B。

独立判据与开发不同：观察器直接记录相机引脚侧每个有效40bit像素group及row/group坐标；Python从实际源tap截取ROI，正向构建平面+预测变换字节，直接比较标准zlib解压输出，并从源RAW字节核验raw CRC。该判据不调用 a1_pattern.inverse_xform 或开发 expected()/packets()作为oracle，可抓取预测/平面映射、旧源、源字节、payload错位等缺陷。全88包同时核验协议44B头、长度、header/stream/transform/raw四CRC、zlib EOF、unused_data=空、unconsumed_tail=空、源唯一性、帧ID唯一性、无旧epoch/尾垃圾。

另一个独立运行时槽判据在每次外部AW/W接受时确认真实RAW/CMP槽为WRITING且地址等于所属槽基址+偏移，在每次AR接受时确认对应槽为READING。所有20正例均无其Fatal，全部RAW/CMP四槽最终FREE；故障观测RAW WRITING释放。真实FIFO token逐项顺序、valid/data stall保持、abort sideband/优先级由冻结TB断言命中，并用独立日志复核token_w=token_r、abort写读一致；未以静态CDC审计冒充实现CDC。

## 本次实际20项矩阵

{chr(10).join(table)}

合计88完整包，其中80为故障后/clean的四个good输入；8个先前合法前缀单列，未计入恢复数。每case最多送4个good，均恢复4完整包，最大10,042 A1周期，门槛为至少2包且最后good FE后≤1,000,000周期。四个RAW/encoded中写reset均在对应外部AW/W已接受、真实WRITING active且相应完整帧未发布时触发；reset后计数与所有权清零，恢复源使用epoch1 seed1100..1103，旧seed11/12未导出。

bad-frame命中crop_abort且crop_valid=0，单abort按真实FIFO顺序到达，RAW drop/error真实增加，坏帧无发布。overflow命中真实有限FIFO满/拒收，释放后恢复；full-abort/pending-reset/sof-abort/last-skid-abort分别命中full+pending+holding、pending复位清除、abort/SOF同拍、last skid未提交时abort。slow比例full/sof例的abort_stalls=0：abort先在pending位置等候full解除，首次实际提出abort时FIFO已有空间；fast比例额外命中abort_stalls=1。两比例冻结TB对full/pending/holding前置均有真实断言，且各恰一有序abort，不把abort_stalls计数误作唯一命中判据。

## 有效负例与原始失败记录

原top已独立正确编译，实际 bad-frame/slow 触发 `ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED`；trace显示 CROP_ABORT、无ABORT_FIFO_ACCEPT，RAW槽仍WRITING；没有加载/编译失败，也没有RECOVERY_BOUND_FAIL替代目标断言。ModelSim实际退出0；目标Fatal是拒绝判据，exit0从未作为PASS依据。负例评价见 old-top-independent-evaluation.json。

17项检查器负例全部拒绝：尾字节、重复源包、截断payload、CRC合法但旧epoch源、四CRC分别破坏（必要时重算header CRC）、CRC合法拼接第二zlib流、8个故障case分别删除inject_hit。前9项使用本测试者独立直接源tap解析器，后8项使用新实跑trace/stats上的触发删除检查。未改原始capture/trace；没有复用依赖包PASS或resume01成功日志。

保留三项测试者自身纠正记录，不隐去失败：①matrix外层最初错误要求原top负例exit2，实际目标Fatal已命中但exit0；原始result.json与日志保留，重新评价原日志，不重跑仿真。②可选的全历史RAW提交解析器两次执行均把encoded-reset前合法RAW seed12提交误当epoch1恢复候选；其断言不符合该用例前置，verify.log与 supplemental-parser-disposition.json保留，未再重试该失败解析器；当前必需槽判据为独立运行时所有权/地址断言和故障/终态观察。③final-evaluation首次过度要求两比例均abort_stalls>0，依据full_pending_abort及原TB前置纠正为冻结门槛，保留final-evaluation.log，唯一一次有新证据纠正重试final-evaluation-corrected.log退出0。无DUT、刺激或验收门槛修改，实际实现修复轮数仍0。

## 命令、退出码、告警和可复现入口

实际工作目录均为 `{H}`。本测试者实际执行入口为：

```text
"C:\\Program Files\\Python311\\python.exe" -B "{H}\\independent_test.py" compile
"C:\\Program Files\\Python311\\python.exe" -B "{H}\\independent_test.py" matrix
"C:\\Program Files\\Python311\\python.exe" -B "{H}\\independent_verify.py"
"C:\\Program Files\\Python311\\python.exe" -B "{H}\\final_evaluation.py"
```

compile退出0，两个vlib/vlog均退出0且Errors0/Warnings0。matrix内20正向vsim全部退出0、明确CASE_PASS且严格独立解码通过；原top目标Fatal后退出0，matrix外层最初因此错误期望而退出1。可选independent_verify两次失败仅作上段无效附加检查记录，不再作为成功入口。final_evaluation首次退出1、纠正后退出0并产生INDEPENDENT_NEGATIVES_REJECTED17、AUDIT after855 DRIFT0和20/88/80结果。准确argv、参数、cwd、owned PID、退出码、时长均在 actual-command-index.json 及各 *.command.json。现有compile/matrix入口会写已有测试库，复现时应由本任务测试者选新隔离子目录，不要求他人盲目覆盖本次证据。

ModelSim共25次真实子命令=2vlib+2vlog+21vsim；均由subprocess wait(timeout=300)控制，超时时仅可结束该自建PID树，本次无超时/终止/仿真重试。TB同时有cycle和绝对时间watchdog；静态验证由60秒真实子进程上限或PowerShell Job控制，最初快速读取调用未设Job封装但实际均<2秒，该过程限制记为流程偏差，后续所有读搜采用60秒封装。最长已记录子命令10.671秒。所有ModelSim进程已wait返回，active_commands=0。

每正向精化出现3条既有告警：u_cmp_store少连st_read_words/st_dup_words两个观察输出（vsim-3017及两条3722）；没有目标数据、时钟或位宽端口告警，未屏蔽。这两未接输出不参与功能握手；本测试者直接观察CMP槽和外部读写，未将其统计当作被连接信号。

## 证据、漂移、未测与回退

核心证据：`{H}\\final-evaluation.json`；`checker-negatives.json`；`old-top-independent-evaluation.json`；`audit-before.json`、`audit-post-compile.json`、`audit-after.json`、`audit-final.json`；`frozen-hash-index.json`；`tester-execution-ledger.json`；`reuse-decision.json`。combined和old-top下每case保留console、transcript、stats、trace、capture、observer、WLF及真实命令。报告和测试脚本SHA另见 tester-artifact-index.json。

DDR模型保留已接受内存及延迟AR/R，DUT reset只阻止新接受，不暗清pending或held response。但四个中写reset命中时pending=0且rvalid=0，因此额外“reset瞬间仍有旧AR未完成”边界 hits=0、not_covered。没有宣称覆盖所有复位交错。小几何与行为DDR证据不证明1080p满速、真实容量/DDR IP、STA/资源/实现CDC、板级恢复、长稳或吞吐。

保护并集855文件前后一致，manifest SHA一致；生产、依赖候选、原r0/resume01、TD、板候选、共享盘符均未写。TD/综合/route/bitgen/CWC/download/Flash=0；无删除、无其他进程操作。回退为停止使用本隔离仿真证据目录，原生产/板候选从未变化；全部失败日志保留。下一动作回原规划四包收束；本任务无需实际修复或复测。

本测试者历史9次工具调用、0compile/0sim因实际usage-limit中断；用户新增“接着做”及条件变化明确续本ID。此次含收尾20次调用/45上限，累计29，两个compile上限已用2；4clean+16fault+1原top负例，17检查器变异，实际修复0。原开发历史/本次/累计60calls、4compile、27sim等原账完整嵌入tester-execution-ledger.json，不与测试者账相互覆盖；两个稳定problem机会仍1/0。间隔额度等待不计为本次活动60分钟，准确开始未仪表化，仅给实际观测时间。当前无blocked。
'''
 report_path=R/'test-reports/T10.a1-recovery-sim-r0-integrated.md'
 report_path.write_text(report,encoding='utf-8')
 retest=dict(required_dimensions=[],required_checks=[],report_paths=[str(report_path),str(H/'final-evaluation.json')],input_status='same',reuse_decision_paths=[str(H/'reuse-decision.json')])
 dimensions={k:dict(applicability='applicable',result='pass',G0='pass',G1='pass',G2='not_run',G3='not_applicable',G4='not_applicable',G5='not_applicable') for k in ('functional','engineering','system')}
 relay=dict(task_id='T10.a1-recovery-sim',dimension='integrated',dimension_results=dimensions,verdict='PASS',report_path=str(report_path),manifest_path=str(e.MANIFEST),blocked=None,retest=retest,budget_counts=dict(tool_call_limit_this_resume=45,tool_calls_this_resume=20,tester_tool_calls_before_resume=9,tester_tool_calls_total=29,full_compiles=2,full_compile_limit=2,positive_simulations=20,negative_simulations=1,checker_negatives=17,simulation_retries=0,actual_repair_rounds=0,active_commands=0,ledger_path=str(H/'tester-execution-ledger.json')))
 e.save(H/'relay-metadata.json',relay)
 artifacts=[dict(path=str(p),sha256=e.sha(p),bytes=p.stat().st_size) for p in H.rglob('*') if p.is_file() and p.name!='tester-artifact-index.json']
 artifacts.append(dict(path=str(report_path),sha256=e.sha(report_path),bytes=report_path.stat().st_size))
 e.save(H/'tester-artifact-index.json',artifacts)
 assert report.splitlines()[0]=='### 判定：PASS' and report.count('### 判定：')==1
 assert report_path.stat().st_size>1000 and e.sha(e.MANIFEST)==manifest_sha
 assert time.monotonic()-start<60
 print('REPORT_VERIFIED',report_path,'ARTIFACTS',len(artifacts),'FINAL_SHA_DRIFT0')
 print(json.dumps(relay,indent=2))
if __name__=='__main__':main()
