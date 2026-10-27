"""Assemble the single integrated report from independently produced evidence."""
import datetime, hashlib, json, pathlib, sys
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent
RUN=HERE.parent.parent;DEV=RUN/'T10.a1-uart-descriptor-fix'
REPORT=HERE.parent/'T10.a1-uart-descriptor-fix-r0-integrated.md'
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def dump(p,o):p.write_text(json.dumps(o,indent=2,ensure_ascii=False),encoding='utf-8')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
before=load(HERE/'audit-before.json');after=load(HERE/'audit-after.json')
assert not before['drift'] and not after['drift'] and not after['drift_from_before'] and not after['extra_drift']
assert before['manifest_sha256']==after['manifest_sha256']==sha(DEV/'manifest-r0.json')
ix=load(DEV/'corrected-dut-index.json');checks=load(HERE/'independent-results.json')
commands=[]
for kind in ['corrected','old']:
    for name in ['vlib','vlog']:commands.append(load(HERE/kind/(name+'.command.json')))
    for case in (['boundaries','wrap','full-clean'] if kind=='corrected' else ['boundaries','wrap']):
        commands.append(load(HERE/kind/case/'console.command.json'))
        result=load(HERE/kind/case/'sim-result.json')
        assert result['status']==('EXPECTED_REJECTION' if kind=='old' else 'SIM_PASS_PENDING_BYTES')
assert len(commands)==9 and all(c['returncode']==0 and not c['timed_out'] and c['elapsed_seconds']<300 for c in commands)
assert all(checks[k]['status']=='PASS' for k in ['descriptor_boundaries','descriptor_wrap','full_clean'])
assert all(t['rejected'] for t in checks['checker_negatives'])
dump(HERE/'actual-commands.json',commands)
tools={str(pathlib.Path(c['argv'][0])):sha(pathlib.Path(c['argv'][0])) for c in commands}
tools[str(pathlib.Path(sys.executable))]=sha(pathlib.Path(sys.executable))
dump(HERE/'tool-identity.json',dict(python=sys.version,modelsim='ModelSim Intel FPGA Edition 10.5b; compiler output independently captured',executables_sha256=tools))
reuse=dict(manifest_path=str(DEV/'manifest-r0.json'),manifest_sha256=before['manifest_sha256'],input_status='same',candidate_relative_to_original='changed: one exporter only',old_PASS_evidence_reused=False,developer_compiled_libraries_reused=False,test_sources='frozen TB/model/fixtures read directly and audited',independent_evidence='two new full libraries; all five simulations re-executed; new physical UART observer; independent forward-transform and bitwise-CRC checker',downstream_recovery='must use corrected-dut-index.json as changed DUT; original two-frame partial success is not promoted/reused')
dump(HERE/'reuse-decision.json',reuse)
now=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
summary=dict(task_id='T10.a1-uart-descriptor-fix',round=0,dimension='integrated',verdict='PASS',manifest_sha256=before['manifest_sha256'],full_compiles=2,simulations=5,retries=0,protected_inputs=108,manifest_entries=184,changed_rtl=1,unchanged_rtl=7,drift=0,G0='pass',G1='pass',G2='not_run',G3='not_applicable',G4='not_applicable',G5='not_applicable',stopped_modifying=True,active_commands=0,created_at=now)
dump(HERE/'test-summary.json',summary)
cmdrows=[]
for c in commands:
    path=pathlib.Path(c['log']);label=str(path.relative_to(HERE))
    cmdrows.append(f"| `{label}` | {c['returncode']} | {c['elapsed_seconds']:.3f} | 300 |")
srcrows=[f"| {e['logical_name']} | {'changed' if e['changed'] else 'original, unchanged'} | `{e['sha256']}` |" for e in ix['files']]
cov=checks['descriptor_boundaries']['queue']['coverage']
covrows=[]
for b in [0,2,4,5,6,7,8,9,10,11]:
    covrows.append(f"| {int(b)//4} | {(int(b)%4)//2} | {int(b)%2} | {cov[str(b)]} |")
report=f'''### 判定：PASS

task_id=`T10.a1-uart-descriptor-fix`；dimension=`integrated`；round=0；runtime=Codex；独立测试者 `/root/fpga_tester_descriptor_221529`。完成时间 {now}。本报告统一覆盖 functional / engineering / system；只有一名与开发独立的综合测试者，无派生代理。

本包冻结的隔离队列修复通过 G0/G1。修正版真实 exporter 的边界和多次回绕、queued reset / 新 epoch、完整管道四帧全部通过；两项旧版真实 DUT 负对照均准确触发目标断言。这里的 PASS 只适用于本冻结仿真副本。

## 输入与范围

- PROJECT_ROOT=`D:\\fpga\\ph1p100`；实际命令 cwd 为各自测试输出目录。
- 唯一冻结 manifest：`{DEV/'manifest-r0.json'}`。
- manifest SHA256：`{before['manifest_sha256']}`。
- 完整修正 DUT 索引：`{DEV/'corrected-dut-index.json'}`；开发交付已声明 frozen=true / stopped_modifying=true / active_commands=0 / blocked=null。
- 规划依据：`{RUN/'dispatch-dq-fix-r0.json'}` 的 after_development 及 `{RUN/'planner-amendment-authorized-dq-fix.md'}`。原 dev-plan / fpga-design-guide 中恢复包的五故障用例留在原任务；本包只要求队列修复、队列 reset 与 clean 集成四帧。
- 测试者全部新文件位于 `{HERE}`，本报告位于授权的 test-reports 根；未修改候选、原 inputs、生产、其他任务、TD、docs junction、位流或板卡。未删除文件、映射盘符、操作他人进程或发送外部消息。

## 三维与 G 层

| 维度 | 适用项 | 结果 |
|---|---|---|
| functional | 真实8 RTL重建；10种合法队列转换；>=12个ID多次回绕；满拒收策略；queued reset/new epoch；严格封包/源字节/zlib/四CRC；四帧真实top；旧DUT有效负对照 | pass |
| engineering | 狭窄单文件差异；7项原始SHA；184项manifest及108项保护输入前后SHA；编译/精化、独占工作库、实际仿真超时、时钟/reset/接口审查 | pass |
| system | 隔离副本、协议与两项容量策略保持、真实延迟DDR/CDC路径、原生产与板候选隔离、恢复交接身份清晰 | pass（仿真范围） |

G0=pass，G1=pass。G2=not_run；G3/G4/G5=not_applicable。理由沿规划：本轮是可逆的隔离 RTL 仿真修复，无生产迁入、实现/位流发布、硬件、长稳性能或下载授权。TD/综合/route/bitgen/CWC/download/Flash 全部0；未运行 STA/CDC 实现数据库/资源/硬件资格，不能用本报告升级父硬件任务。

## 独立重建、工具与实际命令

Python `{sys.version.splitlines()[0]}`；标准 zlib `{checks['zlib']}`。ModelSim Intel FPGA Edition 10.5b；两个新库的 vlog 原始日志均 Errors:0 / Warnings:0，真实 camera_a1_uart_top 和 exporter 被编译/精化。工具可执行文件独立 SHA 见 `{HERE/'tool-identity.json'}`。

旧版、修正版各一次全量 compile（2/2），每项case各一次实际仿真，无重试。完整 argv / cwd / 拥有PID / 实际耗时 / 返回码保存在 `{HERE/'actual-commands.json'}` 和对应 *.command.json。命令形式实际为 `vlib <测试者库>`、`vlog -sv -modelsimini <测试者INI> -work work <索引8RTL> <冻结模型/两个TB> <测试者观察器>`，以及 `vsim -c -modelsimini <测试者INI> -wlf <case.wlf> -l <transcript> work.tester_descriptor|tester_full <plusargs> -do <独占run.do>`；所有具体路径/参数以原始 argv 为准。

| 实际原始日志（相对本证据目录） | 退出码 | 实际秒数 | 子进程硬超时秒 |
|---|---:|---:|---:|
{chr(10).join(cmdrows)}

每条编译/仿真在启动前落实 subprocess.wait(timeout=300)，超时只结束本次拥有的 PID 树；本轮没有触发终止。TB watchdog 分别为500000 / 1500000周期。读取/静态检查后续使用拥有的 PowerShell Job 60s 控制；最初四次小型文本读取实际约1.4–1.8s返回，未额外包60s硬限制，此过程偏差如实保留，不将exec yield冒充超时。所有已启动子进程均已wait，无后台活动。

三项修正版仿真均 Errors:0，无Fatal/watchdog；单模块无告警。full-clean 保留3条原有警告：u_cmp_store端口数38/36及两个漏接观察输出 st_read_words / st_dup_words（top第265行；slot_store第68/69行明确为output）。它们不参与控制/数据握手，未屏蔽；未发现本修复新增的目标端口、宽度或时钟告警。

## 真实 DUT 功能与独立判据

冻结参数：standalone W8/H2、UART_DIV4、HB_DIV0、profile0、20B RAW；full W8/H2、CAM_W16/CAM_H8、ROI(4,2)、FIFO_AW2、UART_DIV4、HB_DIV0、PREP/PRED1。相机与A1周期均5.333ns而相位差1.7ns，经真实capture_async_fifo；UART与A1为同一net，符合导出器明示合同。

| 实跑case | 完整包 | 物理UART/调试字节数 | 结果 |
|---|---:|---:|---|
| corrected/boundaries | 6 | 437 / 437 | PASS，mismatch0 |
| corrected/wrap | 14 | 1021 / 1021 | PASS，mismatch0 |
| corrected/full-clean | 4 | 292 / 292 | PASS，mismatch0 |
| old/boundaries | 目标断言拒绝 | 不作成功包判据 | EXPECTED_REJECTION |
| old/wrap | 第3次pop目标断言拒绝 | 不作成功包判据 | EXPECTED_REJECTION |

与开发不同的判据：测试者新增 `{HERE/'independent_observers.sv'}` 从真实 txd 引脚按8N1位中心采样，而非依赖debug tap；所有修正版物理串行字节与debug capture逐字节相同。另有 `{HERE/'independent_check.py'}`，不导入开发checker或原inverse_xform：独立逐位CRC-32、独立xorshift相机源、RAW10打包及正向相位重排/预测差分，直接对照严格zlib解压的transform。单模块从frame_id公式独立生成20B源并核对冻结descriptor/payload存储字；四项CRC分别计算，包顺序/源ID/epoch/无X/无重复/尾垃圾全部检查。

boundaries输出 epoch0 IDs1001/1002/1003/1006，1004与1005因满拒收且不会输出；该epoch拒收计数2，包括 full+pop仍按旧count拒收。queued reset实际处于E_OPEN、活动7001、队列7002/7003；同步reset清索引/计数/状态/统计，三项未导出描述符被撤销，epoch1只输出2001/2002。独立trace队列重放确认接受/出队/拒收和计数一致。

| 旧count | request push | accepted pop | 实际周期hits |
|---:|---:|---:|---:|
{chr(10).join(covrows)}

count0+pop1两种不可发生组合hits0。其余10类冻结合法转换均实际命中，含single push/pop同拍、full+pop有/无request、空/单项/满闲置。wrap真实依次输出1001..1012，随后相同queued reset与2001/2002；每个接受事件使1bit读/写索引模2回绕，原2bit占用数范围保持0..2。

full-clean四个good输入种子1000..1003，对应IDs1..4，四包各73B。cap/enc/exported/raw_pub/good_sent/recovered均4；raw_drop/cmp_drop/geom/err/dup_words/old_r_count/fifo_rejected/fifo_full/abort_seen均0；AW=W=8，其中raw/cmp各4；最后FE后10015个A1周期已完成四帧（<=1000000）。DDR模型保留真实paired AW/W接受、周期stall与延迟AR/R；DUT reset只门控新请求，不暗中清除内存或已接受响应。本包full-top仅clean，故障恢复没有被冒充为本次覆盖。

独立结果 `{HERE/'independent-results.json'}`；逐case还各有 independent-result.json、capture、wire、trace、stats、console、transcript。

## 有效负对照

旧DUT与其余7RTL正确编译后独立执行：boundaries在95.001ns命中 `QUEUE_COUNT_MISMATCH old=1 push=1 pop=1 expected=1 actual=0`；wrap在62075.001ns第3次pop命中 `DESCRIPTOR_ORDER_OR_X pop=3 expected_id=1003 actual_id=xxxxxxxx`。各日志Errors1/Fatal为期望拒绝，不能因进程exit0视为旧DUT成功；并非用编译失败充反例。

独立checker另外9项变异均被拒：尾字节、重复包、四项CRC逐项破坏（其余头CRC按需重算）、有效zlib流拼接、CRC有效旧源改标新epoch、截断包。旧源反例在新ID及合法CRC下仍因独立源/正向变换不匹配被拒；zlib拼接因unused_data被拒。见 `{HERE/'checker-negatives.json'}`。这些变异仅在内存，不修改候选或冻结输入。

## 单文件范围、输入绑定与交接

测试者从原始文件在内存重建仅队列相关的八处替换，与候选全文精确相等；没有协议/CRC/DDR/时钟/UART/编码核改动。独立差异见 `{HERE/'independent-candidate.diff'}`。dq_wr/dq_rd为1bit，dq_cnt为2bit；accepted push使用旧count<2，pop使用旧estate IDLE且旧count非0；count唯一集中case处理10/01/00/11；reset清零，满拒收st_err策略保留。

| RTL | 身份 | SHA256 |
|---|---|---|
{chr(10).join(srcrows)}

184项manifest文件、108项规划保护输入以及8个完整DUT映射均在测试前后逐项SHA通过；manifest、dispatch/amendment、开发冻结/relay元数据及计划/指南额外绑定前后不变，drift0。证据 `{HERE/'audit-before.json'}`、`{HERE/'audit-after.json'}`。实际使用原7项绝对路径，无复制/覆盖；候选仅该新exporter路径。未复用开发工作库或旧成功日志，不把原恢复任务前两包拼成PASS；同manifest的冻结TB/模型/fixture作为输入重用，经本轮全部重跑和新增独立判据验证。复用决定见 `{HERE/'reuse-decision.json'}`。

未测：生产默认1920x1080、满速持续服务率、真实DDR/IP适配、STA/CDC实现库/资源、硬件复位/下载/长稳；原恢复任务的raw/encoded中写reset、bad-frame、overflow由原规划续原任务验收，本包不升级其状态。后续原恢复任务必须绑定本 corrected-dut-index 作为changed DUT并重跑全部冻结case。本包无必需未满足项、blocked=null，当前冻结r0无要求再测项。

回退：原只读 inputs/a1-r5/src、生产与板候选从未改动，保留全部新旧库/正反例/日志，无清理删除。全部测试命令结束，测试者停止修改后以relay-metadata.json返回；候选唯一身份仍为上述manifest。完整测试证据SHA索引见本目录 evidence-index.json。
'''
REPORT.write_text(report,encoding='utf-8')
dimensions={
 'functional':dict(applicable=True,result='pass',gates=dict(G0='pass',G1='pass')),
 'engineering':dict(applicable=True,result='pass',gates=dict(G0='pass',G1='pass',G2='not_run')),
 'system':dict(applicable=True,result='pass',scope='isolated offline simulation',gates=dict(G0='pass',G1='pass',G3='not_applicable',G4='not_applicable',G5='not_applicable'))}
relay=dict(task_id='T10.a1-uart-descriptor-fix',dimension='integrated',dimension_results=dimensions,verdict='PASS',report_path=str(REPORT),manifest_path=str(DEV/'manifest-r0.json'),blocked=None,retest=dict(required_dimensions=[],required_checks=[],report_paths=[str(REPORT)],input_status='same',reuse_decision_paths=[str(HERE/'reuse-decision.json')]),corrected_dut_index_path=str(DEV/'corrected-dut-index.json'))
dump(HERE/'relay-metadata.json',relay)
files=[]
for p in sorted(HERE.rglob('*')):
    if not p.is_file() or 'lib' in p.parts or p.suffix=='.wlf' or p.name=='evidence-index.json':continue
    files.append(dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p)))
files.append(dict(path=str(REPORT),bytes=REPORT.stat().st_size,sha256=sha(REPORT)))
dump(HERE/'evidence-index.json',dict(manifest_sha256=before['manifest_sha256'],derived_library_and_wlf_excluded=True,files=files))
print('REPORT_READY',str(REPORT), 'commands=9 full_compiles=2 simulations=5 drift=0')
