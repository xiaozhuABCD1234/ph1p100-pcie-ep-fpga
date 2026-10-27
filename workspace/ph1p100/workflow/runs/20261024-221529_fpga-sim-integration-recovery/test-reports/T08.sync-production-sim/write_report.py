from pathlib import Path
import hashlib,json,re,datetime
E=Path(__file__).resolve().parent;R=E.parent.parent;T=R/'T08.sync-production-sim'
def load(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def link(p):return '['+str(p)+']('+str(p).replace('\\','/')+')'
manifest=T/'manifest-r0.json';m=load(manifest)
before,after=load(E/'audit-pre.json'),load(E/'audit-post.json')
assert before['drift_count']==after['drift_count']==0
assert before['manifest_sha256']==after['manifest_sha256']==sha(manifest)
assert load(E/'compile-binding.json')['same_sources'] and load(E/'tester-static.json')['pass']
cases=[]
for case,name in enumerate(['clean','nack','missing','global-reset','restart','pending-reset']):
    folder=E/name;sim,oracle,extra=(load(folder/p) for p in ['sim-result.json','oracle-result.json','tester-independent.json'])
    assert sim['sim_pass'] and sim['exit_code']==0 and not sim['timeout'] and oracle['pass'] and extra['pass']
    log=(folder/'vsim.log').read_text(encoding='utf-8',errors='replace')
    assert 'T08_PASS' in log and 'Errors: 0' in log and not any(x in log for x in ['** Fatal','T08_FAIL','** Error'])
    for file in ['events.log','i2c_a.log','i2c_b.log','vsim.log']:
        assert (folder/file).stat().st_size>0
    hits=[x for x in (folder/'events.log').read_text().splitlines() if any(s in x for s in ['NACK_HIT','MISSING_HIT','RESET_HIT'])]
    cases.append({'case':case,'name':name,'exit_code':0,'seconds':round(sim['elapsed_seconds'],3),
     'pin_transactions':oracle['pin_transactions'],'accepted_requests':oracle['accepted_requests'],'responses':oracle['responses'],
     'frames':len(oracle['frames']),'independent_transactions':extra['checked_transactions'],'hits':hits,'evidence':str(folder)})
negative=load(E/'role-mutation/oracle-result.json');negative_sim=load(E/'role-mutation/sim-result.json')
assert negative_sim['sim_pass'] and negative_sim['exit_code']==0 and not negative['pass']
assert negative['reason']=='ordered 14 role writes and six cleanup writes'
reuse={'manifest_path':str(manifest),'manifest_sha256':sha(manifest),'input_status':'same',
 'reused_previous_test_results':False,'decision':'All six positive/fault cases and actual role mutation were independently rebuilt/rerun. No developer or historical PASS reused.',
 'not_run':['G2 implementation/STA/physical CDC/resources','G3/G4/G5 hardware/performance/release outside frozen simulation scope']}
(E/'reuse-decision.json').write_text(json.dumps(reuse,indent=2),encoding='utf-8')
report=R/'test-reports/T08.sync-production-sim-r0-integrated.md'
dimensions={x:{'applicability':'applicable','result':'pass','gates':{'G0':'pass','G1':'pass','G2':'not_run','G3':'not_applicable','G4':'not_applicable','G5':'not_applicable'}} for x in ['functional','engineering','system']}
result={'task_id':'T08.sync-production-sim','dimension':'integrated','dimension_results':dimensions,'verdict':'PASS',
 'report_path':str(report),'manifest_path':str(manifest),'blocked':None,
 'retest':{'required_dimensions':[],'required_checks':[],'report_paths':[str(report)],'input_status':'same','reuse_decision_paths':[str(E/'reuse-decision.json')]}}
(E/'tester-result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
(E/'case-summary.json').write_text(json.dumps(cases,indent=2),encoding='utf-8')
compile_results=load(E/'build/compile-result.json')
table='\n'.join('|'+ '|'.join(str(c[k]) for k in ['case','name','seconds','accepted_requests','responses','frames'])+'|' for c in cases)
hitlines='\n'.join('- CASE'+str(c['case'])+': `'+h+'`' for c in cases for h in c['hits'])
lines=f'''### 判定：PASS

task_id=`T08.sync-production-sim`；dimension=`integrated`；round=`0`；runtime=`Codex`。本报告由一个独立于开发的综合测试者覆盖 functional、engineering、system。验收时间：{datetime.datetime.now(datetime.timezone.utc).isoformat()}。

本轮预先要求的 G0/G1 离线仿真门槛满足。仅证明冻结的生产 RAW 顶层派生 overlay；G2=not_run，G3/G4/G5=not_applicable。父硬件 T08、生产迁入、曝光同步及上板资格均不据此完成。

## 候选、输入与工具

- 实际工程根：`D:\\fpga\\ph1p100`；工作候选：{link(T/'candidate')}。
- 唯一冻结 manifest：{link(manifest)}；SHA256=`{sha(manifest)}`。
- 实际被测顶层：`ph1p_pcie_ep_top`，顶层源 SHA256=`{sha(T/'candidate/rtl/ep_side/ph1p_pcie_ep_top.v')}`。
- {link(E/'audit-pre.json')} 与 {link(E/'audit-post.json')}：302 项 manifest 文件、6 项规划控制输入、4 个工具可执行文件、108 项保护冻结输入，测试前后漂移均为 0；candidate 无未列文件。stopped_modifying=true，active_commands=0。
- {link(E/'compile-binding.json')}：独立工作库 `{E/'build/work'}`，实际 73 项编译源集合与 manifest 一致，无新增/缺失。未使用开发工作库。
- 实际工具：ModelSim Intel FPGA Edition 10.5b（vlog/vsim 原始日志），Python 3.11.5；工具可执行文件 SHA 已与 manifest 核对。

## 三维及冻结门槛

|维度|适用性/结果|本轮检查与证据|
|---|---|---|
|functional|applicable / pass|真实双路初始化与唯一 I2C 所有者；14 笔角色写和两次等待；8 帧 warmup、第9帧不从中间放行、第10帧起完整输出；六场景正例与角色变异；独立相机应答、字节、帧身份和 CRC 判据|
|engineering|applicable / pass|独立真实 top 编译/精化 Errors=0；源码/参数/legacy 分支与 CDC/reset 接线静态审计；前后 SHA 漂移0；实际每命令 deadline 与 TB watchdog；告警逐类核对|
|system|applicable / pass|完整生产来源映射、环境桩限制明确；测试仅写本任务 test-reports；不接触生产树、TD/板卡/Flash、盘符、其他进程；候选和回退边界明确|

G0/G1=pass；G2=not_run（规划冻结为隔离仿真 overlay，未生成实现候选、不写生产/约束/IP）；G3/G4/G5=not_applicable（规划明确本包无硬件、长稳性能或发布授权）。静态 CDC/reset 接线检查不等价于完整物理 CDC/STA/资源验收。

## 实际复跑

工作目录为 `{E}`。实际执行一次独立 compile，随后 CASE0—5 各一次独立 vsim 进程，再一次 CASE0 角色变异；无失败重试。入口为测试者 {link(E/'tester_verify.py')}，调用冻结 `run_t08.py` 的编译/运行函数和冻结 `check_t08.py` 的 checker，额外执行测试者独立判据。

```powershell
& 'C:\\Program Files\\Python311\\python.exe' -B -X utf8 tester_verify.py pre
& 'C:\\Program Files\\Python311\\python.exe' -B -X utf8 tester_verify.py compile
foreach ($caseId in 0..5) {{ & 'C:\\Program Files\\Python311\\python.exe' -B -X utf8 tester_verify.py case --case $caseId }}
& 'C:\\Program Files\\Python311\\python.exe' -B -X utf8 tester_verify.py case --case 0 --mutate
& 'C:\\Program Files\\Python311\\python.exe' -B -X utf8 tester_static.py
& 'C:\\Program Files\\Python311\\python.exe' -B -X utf8 tester_verify.py post
```

上表循环是实际顺序运行，执行时另带非零退出立即停止保护。底层完整 argv、cwd、PID、耗时和 exit_code 在 {link(E/'build/compile-result.json')} 及每场景 `sim-result.json` / `vsim.log` 的 COMMAND_RESULT。vlib exit={compile_results[0]['exit_code']}，vlog exit={compile_results[1]['exit_code']}，完成标记 `Errors: 0, Warnings: 1`；各正例 exit0、`T08_PASS`、mismatch0、`Errors: 0` 且无 Fatal/T08_FAIL/Error，并验证非空原始事件/引脚/帧产物。

|CASE|场景|实际秒|接受请求|响应|完整帧数|
|---|---|---:|---:|---:|---:|
{table}

逐场景证据位于 {link(E/'case-summary.json')} 中 evidence 目录，包括 `vsim.log`、`sim-result.json`、`events.log`、A/B 引脚日志、逐帧4096B dump、`oracle-result.json`、`tester-independent.json`。所有场景每路至少连续三帧；restart 包含停止前后三帧各一组。

故障实际命中记录：

{hitlines}

CASE1 的最后字节 NACK 返回失败、清理后重新 warmup；CASE2 缺B撤销 A 半帧且零发布，恢复重新 warmup；CASE3 在实际 DDR AW/W 已接受且未发布完整帧时全局复位，重新初始化/warmup；CASE4 显式停止/重启；CASE5 在已接受 I2C 且真实 busy 上升、尚无响应时 reset，仅该旧请求取消，新会话无旧应答并完成三对帧。

超时控制使用冻结 runner 的 `Popen.wait(timeout=300)`；vlib=60s。仅超时才按本命令拥有的 PID/子树安全终止；本轮 timeout 均 false、未终止任何进程。TB 同时有 2,000,000 控制拍与40ms仿真时间 watchdog。读取/搜索均在60s内完成，定向 rg 子进程显式 timeout=60；无 TD 构建。

## 独立判据与反例

开发 checker 本轮重新运行，检查引脚完整201项初始化、同步14笔/清理6笔、两个 WAIT120 下界、真实 NACK、R10F 每字节/格式/CRC/地址、padding与单次发布。两次缩放等待的静态映射另外核对 50MHz×24ms=1,200,000拍。

测试者新增 {link(E/'tester_verify.py')} 独立逻辑，不导入开发 checker 作为参考：逐个 REQ 在其真实引脚完成与 RSP 之间建立唯一关联，核对 RSP camera、ACK 与锁存字节；从捕获 payload 首字节用模256逆元反推源帧号，再逐行检查字节递进；CRC 由逐 bit IEEE 多项式实现，独立于开发 zlib 调用。它能发现开发仅计数可能遗漏的响应相机串路和源帧标签错误。六场景独立检查均通过。

独立逻辑还在内存副本将响应 camera 翻转、把 A 帧冒充 B 帧，分别被 `independent response camera mismatch` 与 `independent source ID/header size` 拒绝，不修改候选或原始证据。真实控制路径 `+MUTATE_ROLE` 将首笔 A 30C1 从0F变0E，正确编译并完整仿真后，被引脚顺序判据 `{negative['reason']}` 拒绝，见 {link(E/'role-mutation/oracle-result.json')}。负例拒绝不作坏 DUT 的正例 PASS。

## 工程、CDC/reset 与系统审计

{link(E/'tester-static.json')} 独立核对全部86项 source→overlay 映射：84项字节不变，仅 top、ui_cfg 两项差异。真实 sync_reset/SOF mailbox/pair/start、ui_i2c、checked CSI、unpack、两路 cam_r10f_writer 和 ddr_wr_arb 未改；SYNC_ENABLE=0 的 legacy cfg 主体逐字相同，gate 为直通，top 默认参数保持原值。新增 I2C 适配器仅一真实 core、握手锁存、busy上升/下降和 error_seen|core_error 应答；reset 清 pending。SOF来自门控前，门控 permit 异步撤销、目的域两级释放并仅 SOF admission；writer 原有异步 FIFO/DDR 仲裁保留。本结论为静态结构与本轮仿真范围。

生产默认 W1920/H1080/X960/Y540/SKIP37；payload=2,592,000B，头128B，DMA=2,592,768B。仿真 W8/H2/X0/Y0/SKIP0，payload20B，头128B，DMA4096B；字节地址 A=00100000/00900000，B=01100000/01900000。控制20ns、A14ns、B18ns、DDR8ns，源时钟不同相位；I2C_DIV14、WAIT120、timeout/pair窗口均按 manifest，非满尺寸或吞吐证据。

编译1条 RDGN 为未改动 pcie_ep_engine.v:127；精化37条均与已列端口省略匹配，见 {link(E/'tester-warning-audit.txt')}。TB省略物理输出/DDR脚、B cfg debug输出、B writer debug/closedloop输出；唯一省略输入 cl_release 仅用于 CLOSEDLOOP_EN 条件选中的分支，本轮参数0选原 release同步链。无未说明的目标端口、位宽或时钟告警。额外 onerror/onbreak 提示属于 vsim宏上下文提示；实际日志仍有明确完成与退出记录。

环境边界：PLL/PCIe为时钟及空闲状态模型，DDR为真实AW/W/B握手带确定性背压的四槽存储模型，无DDR训练/读或PCIe主机事务；MIPI仅使用已有包层仿真边界，传感器只开漏ACK/NACK和引脚解码。厂商环境文件实际包含于 manifest 和编译，文件开头沿用旧桩说明不覆盖此绑定。包层数据由TB生成，不能证明曝光/电气/MCLK锁定。无硬件观察者、位流、下载窗口或板级实测。

## 证据复用、未测和回退

{link(E/'reuse-decision.json')}：未复用开发/历史 PASS，所有要求场景基于同一冻结输入独立重建重跑。输入状态 same，前后漂移0。

未测：完整尺寸/持续吞吐、生产迁入、真实厂商实现/最终STA/完整CDC/资源/bit绑定、真实曝光同步、板级恢复和长稳/发布。均按预先冻结门槛保留，不外推。下一动作是回原规划记录本离线包结果；父硬件T08保持未完成。回退入口为原生产/板候选未写入，保留本run所有证据；未删除任何文件或目录。

blocked=null；本轮无待修复失败项。机器返回：{link(E/'tester-result.json')}。
'''
report.write_text(lines,encoding='utf-8')
assert report.read_text(encoding='utf-8').splitlines()[0]=='### 判定：PASS'
assert len(re.findall(r'^### 判定：',report.read_text(encoding='utf-8'),re.M))==1
print(json.dumps(result))
