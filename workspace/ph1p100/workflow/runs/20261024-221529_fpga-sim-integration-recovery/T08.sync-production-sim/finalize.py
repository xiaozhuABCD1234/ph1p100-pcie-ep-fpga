"""Last operation: verify finished activities and freeze one immutable handoff manifest."""
from pathlib import Path
import argparse,datetime,difflib,hashlib,json,platform,sys
H=Path(__file__).resolve().parent;RUN=H.parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def write_json(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
p=argparse.ArgumentParser();p.add_argument('--native-tool-calls',type=int,required=True);args=p.parse_args()
assert args.native_tool_calls<=60
manifest=H/'manifest-r0.json';assert not manifest.exists(),'single freeze only'
results=json.loads((H/'local/final-suite-result.json').read_text())
assert [x['name'] for x in results]==['pending-reset','clean','nack','missing','global-reset','restart','role-mutation']
assert all(x['simulation']['sim_pass'] and x['simulation']['exit_code']==0 and not x['simulation']['timeout'] for x in results)
assert all(x['oracle']['pass'] for x in results[:-1])
assert not results[-1]['oracle']['pass'] and 'ordered 14 role writes' in results[-1]['oracle']['reason']
build_hashes=json.loads((H/'local/build2/final-input-hashes.json').read_text())
assert all(sha(Path(n))==s for n,s in build_hashes.items()),'final compile/run input drift'
planning=RUN/'planning-input-manifest.json';fixed=json.loads(planning.read_text(encoding='utf-8'))
protected=[]
for f in fixed['files']:
    actual=sha(Path(f['frozen']));assert actual==f['sha256'],f['frozen']
    protected.append({'path':f['frozen'],'sha256':actual,'matches_planning_freeze':True})
write_json(H/'protected-input-audit.json',{'drift':0,'checked_files':len(protected),'files':protected})
src=RUN/'inputs/production-raw';dst=H/'candidate';provenance=[]
for original in sorted(src.rglob('*')):
    if not original.is_file():continue
    rel=original.relative_to(src);overlay=dst/rel
    item={'source':str(original),'overlay':str(overlay),'source_sha256':sha(original),'overlay_sha256':sha(overlay)}
    item['changed']=item['source_sha256']!=item['overlay_sha256']
    if item['changed']:
        diff=H/'diffs'/(original.name+'.diff')
        diff.write_text(''.join(difflib.unified_diff(original.read_text(encoding='utf-8').splitlines(True),
            overlay.read_text(encoding='utf-8').splitlines(True),fromfile=str(original),tofile=str(overlay))),encoding='utf-8')
        item['diff_path']=str(diff)
    provenance.append(item)
assert sum(i['changed'] for i in provenance)==2
write_json(H/'source-to-overlay.json',provenance)
warnings=[]
for entry in results:
    log=Path(entry['simulation']['log']).read_text(encoding='utf-8',errors='replace')
    assert 'T08_PASS' in log and 'Errors: 0' in log
    assert not any(s in log for s in ['** Error','** Fatal','T08_FAIL'])
    warnings.extend(l for l in log.splitlines() if '** Warning' in l)
    write_json(Path(entry['simulation']['cwd'])/'input-binding.json',{
        'build':'build2','source_hashes_path':str(H/'local/build2/final-input-hashes.json'),
        'source_drift':0,'candidate_manifest':str(manifest)})
(H/'warning-audit.txt').write_text('\n'.join(sorted(set(warnings)))+'\n\nDisposition: see README.md model/warning boundary and static-audit.json.\n',encoding='utf-8')
tools=Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
tool_info={'modelsim_version':'10.5b (actual vlog/vsim logs)','python_version':platform.python_version(),
 'executables':[{'path':str(tools/(n+'.exe')),'sha256':sha(tools/(n+'.exe'))} for n in ['vlib','vlog','vsim']]
    +[{'path':sys.executable,'sha256':sha(Path(sys.executable))}]}
write_json(H/'tool-identity.json',tool_info)
budget={'native_tool_calls_including_final_freeze':args.native_tool_calls,'limit':60,'developer_minutes_limit':75,
 'full_compiles':2,'compile_limit':2,'actual_simulations_per_case':{'clean':2,'nack':2,'missing':2,'global-reset':2,'restart':2,'role-mutation':2,'pending-reset':1},
 'startup_failure_not_simulated':str(H/'local/clean-attempt1/vsim.log'),
 'repetition_reason':'Build2 added the explicit pending-I2C reset branch; final runs bind every required case to the same final TB/RTL hashes. No automatic retries.',
 'read_search_deadline_seconds':60,'each_compile_or_sim_deadline_seconds':300,
 'hardware_td_drive_mapping_operations':0,'deletions':0,'child_agents':0,'active_commands_after_exit':0}
write_json(H/'execution-budget.json',budget)
summary=[]
for entry in results:
    oracle=entry['oracle'];summary.append({'name':entry['name'],'case':entry['case'],'simulation_exit':entry['simulation']['exit_code'],
        'simulation_seconds':round(entry['simulation']['elapsed_seconds'],3),'oracle_pass':oracle['pass'],
        'frame_count':len(oracle.get('frames',[])),'oracle_reason':oracle.get('reason'),'evidence_dir':entry['simulation']['cwd']})
write_json(H/'developer-result.json',{'task_id':'T08.sync-production-sim','round':0,'local_checks':summary,
 'formal_integrated_verdict':'pending_independent_tester','input_drift':0,'stopped_modifying':True,'active_commands':0,
 'G0_G1':'developer local checks completed; independent decision pending','G2':'not_run','G3_G4_G5':'not_applicable per frozen plan'})
text='''# T08 round0 开发交付

真实生产RAW顶层派生覆盖层已完成局部检查，等待一个独立综合测试者重新编译验收。本文件不是综合测试PASS报告。唯一待测入口为manifest-r0.json。

最终build2输入：六个正例分别覆盖正常、最后字节NACK清理/恢复、缺B并中止A半帧后的恢复、写入中全局reset、显式停止/重启、I2C接受后未回应时reset。每个场景真实顶层运行完成，独立引脚/字节oracle mismatch=0，每路至少连续三帧正确发布。另一次真实30C1角色写值变异在相同编译输入下运行完成，被独立引脚顺序断言拒绝。精确数量/时间/命令/退出码见developer-result.json、local/final-suite-result.json及每case的sim-result.json/oracle-result.json/input-binding.json。

开发执行两次完整编译，Errors0。build1阶段的原始失败日志和checker纠正证据全部保留；ModelSim反斜杠路径启动失败未进入设计。build2新增pending-I2C reset用例后，按最终相同TB/RTL哈希重新运行全部必须场景，未沿用旧输入PASS。实际命令、工作目录和PID/超时记录在compile-result.json及sim-result.json；不从exit0单独判通过。

仅两份冻结生产文件有overlay差异：top接入和ui_cfg启用分支。新增两个可综合模块为独占真实I2C适配器及整帧门控；真实sync/CSI/unpack/writer/arbiter源码未改。source-to-overlay.json和diffs给出全部来源和逐行差异。static-audit.json、README.md记录默认关闭行为、50MHz/24ms=1200000拍、生产/小几何、地址单位、CRC和CDC/reset结构。protected-input-audit.json对规划108份冻结输入重新检查，漂移0。

模型边界：仅厂商PLL/PCIe/DDR和MIPI物理层为明确环境模型；真实I2C引脚事务、checked包层、解包、两路writer和仲裁器均未stub。DDR按AW/W/B接受握手存储并施加背压。传感器模型只ACK/NACK和解码引脚，不证明曝光/电气，数据源从既有包层仿真边界送入。告警完整保留在warning-audit.txt并在README.md逐类解释；无未说明的位宽或时钟告警。

G2本包not_run，G3/G4/G5按冻结规划不适用。生产迁入、完整STA/CDC/资源、真实曝光同步/硬件恢复/长稳/吞吐均未验证，父硬件T08不得置done。TD/板卡/Flash/共享盘符/其他会话进程/生产树写入/删除操作为0。回退为保留本目录和失败日志，生产候选原样。

综合测试者应在其允许写域建立独占工作库，按README运行CASE0—5及--mutate反例；使用相同manifest文件，前后SHA检查，再给出functional/engineering/system和G层判定。所有仿真命令已结束，最终冻结后开发不再修改或执行命令。
'''
(H/'developer-report.md').write_text(text,encoding='utf-8')
with (H/'lessons.md').open('a',encoding='utf-8') as f:
    f.write('\n- 额外pending-I2C reset用例在真实busy上升、accepts=1/responses=0时命中；旧会话一笔明确取消，新的epoch完整初始化和warmup后恢复。最终build2对全部必须场景重新绑定输入SHA。\n')
test_inputs=[H/'candidate']+[H/n for n in ['sync_i2c_config.v','sync_frame_gate.v','vendor_env.sv','sensor_i2c.sv','tb_production_sync.sv','run_t08.py','check_t08.py']]
test_inputs.append(RUN/'inputs/production-raw/rtl/ep_side/cam/ui_imx415_reg.v')
files=[]
for f in sorted(H.rglob('*')):
    if not f.is_file() or f==manifest or '__pycache__' in f.parts or 'work' in f.parts:continue
    if f.suffix.lower() not in {'.v','.sv','.py','.md','.json','.log','.hex','.ini','.diff','.txt','.f'}:continue
    files.append({'path':str(f),'sha256':sha(f),'bytes':f.stat().st_size})
data={'schema':'fpga-dev-unique-manifest-v1','task_ids':['T08.sync-production-sim'],'round':0,
 'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'project_root':str(RUN.parents[2]),
 'write_scope':str(H),'stopped_modifying':True,'active_commands':0,'status':'ready_for_test',
 'planning_manifest':{'path':str(planning),'sha256':sha(planning)},'test_input_paths':list(map(str,test_inputs)),
 'planning_control_inputs':[{'path':str(RUN/n),'sha256':sha(RUN/n)} for n in
    ['dispatch.json','request.md','dev-plan.md','fpga-design-guide.md','input-index.md','planning-input-manifest.json']],
 'compile_sources':json.loads((H/'local/build2/sources.json').read_text()),'files':files,
 'source_to_overlay_path':str(H/'source-to-overlay.json'),'tools':tool_info,
 'final_local_evidence':str(H/'local/final-suite-result.json'),'protected_input_drift':0,
 'exclusive_generated_work_libraries':[str(H/'local/build1/work'),str(H/'local/build2/work')],
 'generated_work_exclusion':'Compiled libraries and WLF are generated outputs, not test inputs. Independent tester must rebuild sources into its own allowed work library.',
 'parameters':json.loads((H/'static-audit.json').read_text()),
 'simulation_overrides':{'SYNC_ENABLE':1,'DBG_CTRL_DEFAULT_EN':1,'CLOSEDLOOP_EN':0,'CAM_I2C_DIV':14,
    'CAM_POWER_CYCLES':32,'CAM_CSI_RELEASE_CYCLES':8,'SYNC_WAIT_CYCLES':120,'SYNC_FRAME_TIMEOUT':30000,
    'SYNC_PAIR_WINDOW':64,'SYNC_I2C_TIMEOUT':5000,'WARMUP_FRAMES':8,'CAMDDR_W':8,'CAMDDR_H':2,
    'CAMDDR_X0':0,'CAMDDR_Y0':0,'CAMDDR_SKIP_ROWS':0,'control_period_ns':20,'camera_a_period_ns':14,
    'camera_b_period_ns':18,'ddr_period_ns':8},
 'models_and_limits_path':str(H/'README.md'),'gates':{'G0':'independent_test_required','G1':'independent_test_required','G2':'not_run','G3':'not_applicable','G4':'not_applicable','G5':'not_applicable'}}
metadata={'task_ids':['T08.sync-production-sim'],'status':'ready_for_test','stopped_modifying':True,'active_commands':0,
 'artifact_paths':[str(H/'developer-report.md'),str(H/'developer-result.json'),str(H/'source-to-overlay.json'),str(H/'README.md'),str(H/'local/final-suite-result.json')],
 'manifest_path':str(manifest),'test_input_paths':list(map(str,test_inputs)),'lessons_path':str(H/'lessons.md'),'blocked':None,'retest':None}
# Last filesystem mutation. No command, edit or verification runs after this freeze.
write_json(manifest,data)
print(json.dumps(metadata,ensure_ascii=False))
