from pathlib import Path
import argparse,datetime,hashlib,json,sys
import run_t08
from check_t08 import check
from r10f_oracle import check_r10f
H=Path(__file__).resolve().parent
DEADLINE=datetime.datetime.fromisoformat('2026-10-25T13:02:49.045073+00:00')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def command(args,cwd,log,timeout=300):
 remaining=(DEADLINE-datetime.datetime.now(datetime.timezone.utc)).total_seconds()
 if remaining<=10:raise RuntimeError('absolute repair deadline reached')
 return original_command(args,cwd,log,min(timeout,remaining))
original_command=run_t08.command;run_t08.command=command
def compile_variant(build,mutant=False):
 build.mkdir(parents=True,exist_ok=True);ini=build/'modelsim.ini';ini.write_text('[Library]\nwork = '+(build/'work').as_posix()+'\n')
 files=[p for p in (H/'candidate/rtl').rglob('*.v') if 'rc_side' not in p.parts and p.name not in {'crc16_upd4.v','crc32_upd4.v'}]
 files +=[H/n for n in ['dual_local_closure.v','sync_i2c_config.v','sync_frame_gate.v','vendor_env.sv','sensor_i2c.sv','tb_production_sync.sv','tb_production_sync_legacy.sv','tb_dual_contract.sv','tb_tester_edges.sv','tb_repair_matrix.sv']]
 if mutant:
  p=H/'dual_local_closure.v';s=p.read_text();old='if(rel_camera_id) b_release<=rel_slot_id?2:1;else a_release<=rel_slot_id?2:1;'
  assert s.count(old)==1;s=s.replace(old,'if(rel_camera_id) a_release<=rel_slot_id?2:1;else a_release<=rel_slot_id?2:1;')
  q=H/'fixtures/mutant_b_release_to_a.v';q.parent.mkdir(exist_ok=True);q.write_text(s);files=[q if f==p else f for f in files]
  (H/'fixtures/mutation.json').write_text(json.dumps({'base_sha256':sha(p),'mutant_sha256':sha(q),'intent':'negative fixture only; mode2 B release misrouted to A'},indent=2))
 inputs=[{'path':str(p),'sha256':sha(p)} for p in files]
 (build/'sources.json').write_text(json.dumps(inputs,indent=2))
 a=[run_t08.TOOLS/'vlog.exe','-sv','-modelsimini',ini,'-work',build/'work','+define+MIPI_PHY_SIM_STUB']+['+incdir+'+p.as_posix() for p in sorted({p.parent for p in files})]+files
 rs=[command([run_t08.TOOLS/'vlib.exe',build/'work'],build,build/'vlib.log',60),command(a,build,build/'vlog.log')]
 (build/'compile-result.json').write_text(json.dumps(rs,indent=2))
 t=(build/'vlog.log').read_text(errors='replace');assert all(r['exit_code']==0 and not r['timeout'] for r in rs) and 'Errors: 0' in t and '** Error' not in t,'compile failed'
 print('COMPILE_OK '+str(build),flush=True)
def top(build,name,out,marker,case=0,negative=False):
 out.mkdir(parents=True,exist_ok=True)
 args=[run_t08.TOOLS/'vsim.exe','-c','-modelsimini',build/'modelsim.ini','-lib',build/'work',name,f'+CASE={case}','-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0']
 r=command(args,out,out/'vsim.log');t=(out/'vsim.log').read_text(errors='replace')
 r['sim_pass']=r['exit_code']==0 and not r['timeout'] and marker in t and '** Fatal' not in t and '** Error' not in t and 'T08_FAIL' not in t
 if negative:r['negative_rejected']='CONTRACT_FAIL B release routes only to B' in t and '** Fatal' in t and 'CONTRACT_PASS' not in t;r['pass']=r['negative_rejected']
 else:r['pass']=r['sim_pass']
 (out/'sim-result.json').write_text(json.dumps(r,indent=2))
 if r['pass'] and name=='tb_production_sync':
  o=check(out,case)
  if case==16:o['overlap']=overlap(out)
  (out/'oracle-result.json').write_text(json.dumps(o,indent=2));r['pass']=o['pass']
 if r['pass'] and name=='tb_production_sync_legacy':
  pubs=[x.split() for x in (out/'events.log').read_text().splitlines() if x.startswith('PUB ')];assert len(pubs)==6
  for x in pubs:
   cam,seq,fid=int(x[3]),int(x[4]),int(x[7]);b=bytes(int(v,16) for v in (out/f'frame_{cam}_{seq}.hex').read_text().split());check_r10f(b,cam,seq,fid)
  r['independent_frames']=6
 (out/'case-result.json').write_text(json.dumps(r,indent=2));print(json.dumps({'name':name,'case':case,'pass':r['pass'],'seconds':r['elapsed_seconds'],'out':str(out)}),flush=True)
 assert r['pass'],'case failed '+str(out)
 return r
def overlap(out):
 rows=[x.split() for x in (out/'events.log').read_text().splitlines()];spans=[];pending=None
 for x in rows:
  if x[0]=='DAR':assert pending is None;pending={'epoch':int(x[1]),'start':int(x[2]),'base':int(x[3],16),'beats':int(x[4])}
  elif x[0]=='DRLAST':assert pending is not None;pending['end']=int(x[2]);spans.append(pending);pending=None
 assert pending is None
 hits=[]
 for cam in [0,1]:
  sofs=[x for x in rows if x[0]=='OSOF' and int(x[3])==cam and any(s['epoch']==int(x[1]) and s['start']<=int(x[2])<s['end'] for s in spans)]
  pubs=[x for x in rows if x[0]=='CLPUB' and int(x[3])==cam and int(x[7])==61 and any(s['epoch']==int(x[1]) and s['base']!=int(x[5],16) and s['start']<=int(x[2])<s['end'] for s in spans)]
  assert len(sofs)>=2 and len(pubs)>=1,'required actual AR-to-final-R overlap missing'
  assert not any(x[0]=='CLPUB' and int(x[3])==cam and int(x[7]) in [62,63] for x in rows),'full held slots must reject entire new frames'
  seqs={int(x[7]):int(x[4]) for x in rows if x[0]=='CLPUB' and int(x[3])==cam}
  assert seqs[10]>seqs[61]+1,'rejected source capture sequence gaps retained'
  hits.append({'camera':cam,'new_sofs':sofs,'other_slot_publications':pubs,'post_drop_first_capture_seq':seqs[10]})
 assert any(x[0]=='OVERLAP_FULL_HIT' for x in rows) and any(x[0]=='OVERLAP_DROP_HIT' for x in rows)
 result={'pass':True,'actual_AR_R_spans':spans,'hits':hits,'recovery_good_pairs':6}
 (out/'overlap-result.json').write_text(json.dumps(result,indent=2));return result
def main():
 p=argparse.ArgumentParser();p.add_argument('phase',choices=['early','regression']);a=p.parse_args();build=H/'local/build-baseline'
 if a.phase=='early':
  compile_variant(build)
  top(build,'tb_tester_edges',H/'local/original-edges','TESTER_EDGE_PASS')
  top(build,'tb_repair_matrix',H/'local/matrix','MATRIX_PASS')
  top(build,'tb_production_sync',H/'local/case16','T08_PASS',16)
 else:
  for case in [0,10,11,12,13,14,15]:top(build,'tb_production_sync',H/f'local/case{case:02d}','T08_PASS',case)
  top(build,'tb_dual_contract',H/'local/contract','CONTRACT_PASS')
  top(build,'tb_production_sync_legacy',H/'local/legacy','T08_PASS')
  mutant=H/'local/build-mutant';compile_variant(mutant,True);top(mutant,'tb_dual_contract',H/'local/negative','CONTRACT_PASS',negative=True)
 print('PHASE_PASS '+a.phase,flush=True)
if __name__=='__main__':main()
