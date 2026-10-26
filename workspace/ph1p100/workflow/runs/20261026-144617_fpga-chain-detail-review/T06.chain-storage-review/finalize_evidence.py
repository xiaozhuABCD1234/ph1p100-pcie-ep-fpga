from pathlib import Path
import csv,hashlib,json
OUT=Path(__file__).resolve().parent;RUN=OUT.parent
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def put(p,v):Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
base=load(RUN/'baseline/source-manifest.json');candidate=next(f for f in base['files'] if Path(f['snapshot_path']).name=='0141.json')
c=load(candidate['snapshot_path']);bindings=[]
for name,expected in c['changed_src_sha256'].items():
    matches=[f for f in base['files'] if f['source_relative'].endswith('T10.b15-ddr-pace/r0/changed-src/'+name)]
    assert len(matches)==1,(name,matches)
    f=matches[0];assert sha(f['snapshot_path'])==f['sha256']==expected
    bindings.append({'source_path':f['source_path'],'snapshot_path':f['snapshot_path'],'sha256':expected,'result':'matches_candidate'})
put(OUT/'candidate-bindings-r0.json',{'candidate_manifest':candidate['snapshot_path'],'candidate_sha256':sha(candidate['snapshot_path']),'all_11_changed_source_bindings':bindings,'result':'CANDIDATE_BINDINGS_COMPLETE','boundary':'selected-source identity only; not historical bit dependency or encrypted MC certification'})
f=load(OUT/'findings.json');item=next(x for x in f['findings'] if x['finding_id']=='T06-F05')
item['claim']='slot_seq/pub_tgl在每次begin翻转，abort消耗序号；oldest_slot一位排序在合法store接口轨迹下可选新槽，违反发布顺序。'
item['reproduction']='合法store接口轨迹：A槽0发布并open；B槽1发布；close A；C槽0 begin后abort；D槽0发布，消费者在此期间未open B。此时B和D seq均1，rd_expect=1，oldest_slot优先槽0取D，发布FIFO仍B,D。'
item['impact']='模块发布顺序缺陷已见证；若CMP消费者延迟领取使此轨迹可达，可用B描述符配D内容，E_OPEN仅计错继续输出。当前默认整机调度下该完整轨迹可达性未证明，不声称板上已发生。'
item['validation']='witness顺序轨迹；测试者用独立FIFO oracle或真实store微仿真复核；整机另验消费者pacing可达性。'
put(OUT/'findings.json',f)
p=OUT/'checkpoints.csv';rows=list(csv.DictReader(p.open(encoding='utf-8-sig',newline='')))
r=next(r for r in rows if r['checkpoint']=='C02');r['invariant']='MODE0 and feeder preserve exact bit vector; no repack; external T02-F01 format issue remains';r['result']='no_issue_found';r['evidence']='T06-F13; accepted T02-F01; findings.json evidence_refs; witness/result-r0.json';r['optimization']='仅建议；不实施；见T06-F13及T02-F01'
with p.open('w',encoding='utf-8-sig',newline='') as h:
    w=csv.DictWriter(h,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
p=OUT/'review.md';text=p.read_text(encoding='utf-8');text+='\n补充资格：F05已确认的是store模块在合法接口事件轨迹中的发布顺序缺陷。描述符错配是消费者延迟领取、该轨迹在整机可达时的后果；默认全尺寸b15调度的完整可达性未在本包证明，也未声称板上实测发生。11份changed-src与旧candidate SHA全部独立核对，见candidate-bindings-r0.json。\n测试者如复跑见证，请使用`check_storage_contract.py --stdout`并把输出保存至自身测试目录，避免改写冻结的开发result-r0.json；最高风险F05仍须使用不同判据。\n';p.write_text(text,encoding='utf-8')
commands=load(OUT/'commands.json');commands['recorded_script_commands'].append({'command':'C:/Program Files/Python311/python.exe -B -X utf8 '+str(OUT/'verify_freeze.py')+' verify','exit_code':0,'deadline_seconds':300,'marker':'LOCAL_REFERENCE_CHECK_COMPLETE checkpoints=35 findings=15 refs=72','stdout':'verify-r0-stdout.txt','stderr':'verify-r0-stderr.txt'})
commands['read_search_records'].append({'command':'Owned read Job: candidate changed_src_sha256 and selected source hashes; F05 full witness trace; own artifact sizes; current time','exit_code':0,'deadline_seconds':60,'result':'11 candidate binding entries inspected; task-local scope retained'})
commands['execution_accounting']={'actual_tool_calls_through_this_script_launch':24,'limit':30,'micro_RTL_simulations':0,'Python_witness_runs':1,'actual_repairs':0,'T06_round0_acceptances':0,'capacity_interruption':'user explicitly resumed existing role; no automatic API retry; original call count retained','initial_read_timeout_exception':'first short root/role read completed without explicit wrapper; later bounded'}
put(OUT/'commands.json',commands)
print('FINAL_EVIDENCE_COMPLETE candidate_bindings=11 F05_module_scope_qualified=1')
