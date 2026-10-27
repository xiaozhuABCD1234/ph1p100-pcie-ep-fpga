"""Freeze preparation evidence; never upgrades missing real inputs to PASS."""
import hashlib
import json
from pathlib import Path
import sys
from datetime import datetime,timezone
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def put(name,value):
    p=HERE/name
    if p.exists():raise ValueError('refuse overwrite '+str(p))
    p.write_text(value if isinstance(value,str) else json.dumps(value,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

assert not (HERE/'manifest-r0.json').exists()
controls=read(HERE/'local/controls-final-result.json')
bench=read(HERE/'local/real-benchmark/benchmark.json')
assert controls['status']=='tool_controls_pass' and len(controls['checks'])==39
assert bench['real_sample_count']==0 and bench['qualified_real_count']==0 and bench['ratio'] is None
assert bench['benchmark_result']=='blocked' and bench['real_summary'] is None
assert not bench['real_samples'] and not bench['synthetic_controls'] and not bench['historical_controls']
assert 'TOOL_CONTROLS_PASS' in (HERE/'local/controls-final.stdout.log').read_text()
assert '"benchmark_result": "blocked"' in (HERE/'local/real-benchmark.stdout.log').read_text()
binding=read(HERE/'inputs/source-binding.json')
for source in binding['sources']:
    p=Path(source['path']);assert sha(p)==source['sha256'], 'source drift: '+str(p)
assert not list(HERE.rglob('__pycache__'))
commands=[
 {'command':'python.exe -B verify_controls.py','cwd':str(HERE),'rc':1,'expected':'RED: benchmark module absent before implementation','stdout':'local/red.stdout.log','stderr':'local/red.stderr.log'},
 {'command':'python.exe -B verify_controls.py','cwd':str(HERE),'rc':0,'marker':'TOOL_CONTROLS_PASS checks=39','stdout':'local/controls.stdout.log','stderr':'local/controls.stderr.log','note':'initial implementation, before unique-output-name support'},
 {'command':'python.exe -B prepare_evidence.py','cwd':str(HERE),'rc':0,'marker':'PREPARE_EVIDENCE_OK sources=19 real_sample_count=0','stdout':'local/prepare.stdout.log','stderr':'local/prepare.stderr.log'},
 {'command':'python.exe -B verify_controls.py controls-final','cwd':str(HERE),'rc':0,'marker':'TOOL_CONTROLS_PASS checks=39 real_sample_count=0 ratio=null benchmark_result=blocked','stdout':'local/controls-final.stdout.log','stderr':'local/controls-final.stderr.log'},
 {'command':'python.exe -B benchmark.py --config inputs/real-inputs.json --output local/real-benchmark','cwd':str(HERE),'rc':3,'expected':'blocked empty real input set','stdout':'local/real-benchmark.stdout.log','stderr':'local/real-benchmark.stderr.log'}]
put('execution-r0.json',{'python_executable':'C:/Program Files/Python311/python.exe','commands':commands,
 'runner_process_count_including_final_freezer':6,'test_compile_deadline_seconds':300,
 'read_search_deadline_seconds':60,'timeout_control':'Start-Process -WindowStyle Hidden; WaitForExit(300000), Kill only owned process on deadline; Start-Job/Wait-Job 60s for reads',
 'timeout_events':0,'installs':0,'network_dataset_requests':0,'TD':0,'hardware':0,
 'download':0,'COM_JTAG_Flash':0,'RK_writes':0,'commits_pushes_external_messages':0,
 'deepseek':'advice only, completed, no pending operation call_id',
 'read_control_note':'initial inherited-rule and dispatch reads completed synchronously in under 2s; subsequent reads used explicit 60s job deadlines'})
problem={'problem_id':'T04.real-raw10-benchmark:INPUT_CONFLICT:qualified-real-raw10',
 'reason_code':'INPUT_CONFLICT','new_information':True,'evidence_path':str(HERE/'inputs/inventory.json'),
 'requested_action':'原规划提供准确的原始实拍文件路径、格式/来源/许可说明及逐样本独立像素正确性证据；一幅只测单样本，至少三种内容的三幅才测有限图集。工具核验是否另派由原规划决定。',
 'resume_input_path':str(HERE/'README.md')}
blocked={'status':'blocked','category':'missing_qualified_real_input',
 'real_sample_count':0,'qualified_real_count':0,'ratio':None,'benchmark_result':'blocked',
 'raw_frame_paths_available':[],
 'missing':['至少一份准确绝对路径的传感器实拍 packed RAW10 或明确大小端/10bit有效位/移位的u16原始容器',
 '逐样本原始SHA、W/H/stride、ROI与Bayer相位记录、设备/采集/格式/来源许可依据',
 '独立像素正确性证据文件及SHA、reviewer/method/correctness_basis、绑定normalized_raw_sha256和qualified评审',
 '若需有限图集统计，至少三幅内容不同的合格帧；目前0幅'],
 'resume_input_path':str(HERE/'README.md'),'schema_path':str(HERE/'inputs/input-schema.json'),
 'frozen_empty_config_path':str(HERE/'inputs/real-inputs.json'),
 'recovery_policy':'不得编辑r0冻结件；新配置/结果目录由原规划授权后续原开发恢复。缺真实资料是外部阻塞，不自动重试，不申请真实收益PASS。'}
put('blocked-r0.json',{'blocked':blocked,'problem':problem})
put('lessons.md','''# T04 r0 lessons

- 触发：本地唯一明确的真实来源是b18 A1U1历史抓取，expected.json 明示sensor_pixel_oracle_verified=false。根因：传输可复现性与传感器像素正确性是不同证据。处理：有限inventory拒其进入real-summary，空集ratio=null、benchmark_result=blocked；复核入口inputs/inventory.json和local/real-benchmark/benchmark.json。
- 触发：u16大小端或高位容器直接当packed输入。处理：显式byte_order/valid_bits/right_shift，检查移位丢弃位全0和0..1023，核对独立规范化SHA；验证入口verify_controls.py的LE/BE/shift6和range/padding/wrong-endian负对照。
- 触发：未知Bayer相位仍启用phase0收益。处理：未知或非RGGB只允许00，RGGB模式必须有相位来源；odd-tail下独立flat-index逆变换覆盖10/11，避免调用编码器inverse自证。
- 触发：A1T1测试record或当前zlib槽长度被当成A1U1/DMA长度。处理：只取根encode_frame的stream/stats，按既有44B组装A1U1；dma统计明确是align(44+zlib,4096)离线布局。严格parser核对stored字节，两个回退比例分别统计，不混成一个值。
- 触发：重跑脚本覆盖冻结输出。处理：每次指定新的controls目录名，benchmark输出目录必须不存在；参考模块禁写pycache。恢复从README/schema新建r1输入，保留r0不动。
- 本次只有软件工具正反向39检查通过；没有真实收益、RTL吞吐、H-only/A+H或板级通过结论。DeepSeek只给低风险检查建议，最终实现和验证由Codex完成。
''')
put('result-r0.md','''# T04 r0：blocked（真实输入缺失；工具准备已交付）

task_id=T04.real-raw10-benchmark；实际根为 D:/fpga/repos/ph1p100-pcie-ep-fpga；派发绑定本run的 dispatch-t04-ready.json。只写本包；停止修改后冻结 manifest-r0.json，测试命令均已退出。未修改生产RTL/tools/constraints/al_ip/workspace/handoff、旧活动run、RK或run控制文件；未使用TD、硬件、安装、图集下载、COM/JTAG/Flash、commit/push或外部消息。

`benchmark_result=blocked`、`real_sample_count=0`、`qualified_real_count=0`、`ratio=null`、`real_summary=null`。缺少合格实拍RAW10和逐样本独立像素正确性证据。不存在真实收益PASS；没有申请真实收益综合测试。本包仅完成输入门、软件工具、合成正反向控制和准确缺项清单。

## 有限inventory与来源门

只枚举input-index中交接包根、其samples和根tools/codec的直接文件，并绑定19项真实采用的规则/派发/模型/历史证据SHA；没有全盘扫描或联网取图。b18来源是历史真实FPGA UART抓取，但其expected明确sensor_pixel_oracle_verified=false、phase unknown，540 stored块不能证明源像素正确。作为历史来源登记、排除real-summary；本轮未重跑其解码。N/L、CONTENT=2和所有生成控制均不作实拍。准确表在inputs/inventory.json，源绑定在inputs/source-binding.json。

## 软件与统计口径

输入schema支持packed RAW10、显式大小端/移位的u16，严格W/H/stride/ROI/10bit范围/原始与规范化SHA；未知相位仅00。真实类别需来源/设备/采集/格式/许可和独立像素正确性证据及其绑定SHA；代码检查声明一致性，真实性仍由原规划/独立测试复核。

只读根tools/codec/a1_ref.py的encode_frame stream/stats，未把A1T1 record当A1U1。严格DEFLATE使用根a1_inflate_strict加Python zlib交叉校验，独立flat-index scatter逆变换不调用a1_ref.inverse_frame。A1U1四CRC与几何/长度核验，逐byte等输入。每帧CSV/JSON包括raw/zlib/A1U1/dma长度、44B头/对齐开销、三种raw/bytes比率、stored_blocks/block_count和stored_raw_bytes/raw_bytes两个回退比例。汇总总字节比，每次只有一个明确模式；dma是align(44+zlib,4096)离线参考布局，不是当前硬件描述符。

## 实际本地检查

Python版本与可执行路径见inputs/runtime.json。每个命令的cwd、rc、标记和日志见execution-r0.json；局部脚本实际WaitForExit deadline=300s，后续读搜job deadline=60s，仅有权终止自身进程。共6个Python runner进程（含最初RED和最终freezer），没有超时。

初始RED rc=1（尚无benchmark模块）；实现后工具控制rc=0，最终脚本以新输出名重跑rc=0、`TOOL_CONTROLS_PASS checks=39`。39项包括已知MIPI字节组、packed与u16 LE/BE+shift6相等、00/10/11、奇数尾行、fixed/stored、严格解码CRC/截断/extra zlib、缺字段/坏SHA/几何/ROI/范围/位padding/错字节序、未知相位拒绝、合成重标签拒绝、历史分类排除、零真实summary。historical分类控制使用生成payload，只检验分类，不冒充b18复测。

真实空输入CLI已实际运行：`python.exe -B benchmark.py --config inputs/real-inputs.json --output local/real-benchmark`，rc=3，输出blocked/0/null。该返回码是预期缺输入，不是通过。合成对照结果位于local/controls-final-result.json与local/controls-final各模式结果，真实空CSV仅表头。无需安装第三方依赖。

G0/G1/G5只在软件工具准备范围有本地证据，真实收益所需G1/G5为blocked；没有独立综合验收判定。G2纯软件不适用；G3/G4 not_run（无硬件授权，不升级父任务）。没有测真实图像收益、真实PCIe、RTL资源/STA/CDC/吞吐或H/AH收益。

## 恢复与回退

blocked-r0.json给出稳定problem_id和最小缺项。准确恢复入口README.md、inputs/input-schema.json及当前派发；原规划提供至少一幅的准确原始路径、格式/来源与独立像素正确性证据。一幅只报告单样本，至少三幅不同内容才形成有限图集。新配置/新结果目录由原规划授权后续此角色；不修改r0冻结件，不空转取图，不自行申请真实收益PASS。原规划可另决定有限工具核验。

回退是停止引用本新离线包；没有生产修改需要回滚。所有失败RED与成功工具日志均保留。主只传输本报告路径和blocked元数据。
''')
files=[]
for p in sorted(HERE.rglob('*')):
    if p.is_file():files.append({'path':str(p.resolve()),'relative_path':str(p.relative_to(HERE)),'bytes':p.stat().st_size,'sha256':sha(p)})
manifest={'schema_version':1,'task_id':'T04.real-raw10-benchmark','round':0,
 'created_utc':datetime.now(timezone.utc).isoformat(),'project_root':str(ROOT),
 'dispatch_path':str(HERE.parent/'dispatch-t04-ready.json'),'write_scope':str(HERE/'**'),
 'status':'blocked','benchmark_result':'blocked','real_sample_count':0,'qualified_real_count':0,'ratio':None,
 'stopped_modifying':True,'active_commands':0,'source_binding_path':str(HERE/'inputs/source-binding.json'),
 'files':files,'external_readonly_sources':binding['sources'],
 'test_input_paths':[str(HERE/'inputs/real-inputs.json'),str(HERE/'inputs/input-schema.json'),
     str(HERE/'local/controls-final/synthetic-inputs.json')],
 'result_path':str(HERE/'result-r0.md'),'lessons_path':str(HERE/'lessons.md'),
 'blocked_path':str(HERE/'blocked-r0.json'),'recovery_entry_path':str(HERE/'README.md')}
put('manifest-r0.json',manifest)
for f in files:assert sha(Path(f['path']))==f['sha256']
for s in binding['sources']:assert sha(Path(s['path']))==s['sha256']
print('FROZEN_BLOCKED active_commands=0 files='+str(len(files))+' manifest_sha256='+sha(HERE/'manifest-r0.json'))
