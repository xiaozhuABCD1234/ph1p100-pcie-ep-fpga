from pathlib import Path
import argparse,datetime,hashlib,json,sys
import run_t08
from check_t08 import check
from r10f_oracle import check_r10f
H=Path(__file__).resolve().parent
DEADLINE=datetime.datetime.fromisoformat('2026-10-25T14:44:20+00:00')
base_command=run_t08.command
def command(args,cwd,log,timeout=300):
 remaining=(DEADLINE-datetime.datetime.now(datetime.timezone.utc)).total_seconds()
 if remaining<=10:raise RuntimeError('mode-fix window deadline reached')
 return base_command(args,cwd,log,min(timeout,remaining))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def compile_all(build):
 build.mkdir(parents=True,exist_ok=True);ini=build/'modelsim.ini';ini.write_text('[Library]\nwork = '+(build/'work').as_posix()+'\n')
 files=[p for p in (H/'candidate/rtl').rglob('*.v') if 'rc_side' not in p.parts and p.name not in {'crc16_upd4.v','crc32_upd4.v'}]
 files += [H/n for n in ['dual_local_closure.v','sync_i2c_config.v','sync_frame_gate.v','vendor_env.sv','sensor_i2c.sv','tb_production_sync.sv','tb_production_sync_legacy.sv','tb_tester_edges.sv','tb_mode_matrix.sv','fixtures/old_mode.v','fixtures/bad_b_release.v']]
 (build/'sources.json').write_text(json.dumps([{'path':str(p),'sha256':sha(p)} for p in files],indent=2))
 args=[run_t08.TOOLS/'vlog.exe','-sv','-modelsimini',ini,'-work',build/'work','+define+MIPI_PHY_SIM_STUB']+['+incdir+'+p.as_posix() for p in sorted({p.parent for p in files})]+files
 rs=[command([run_t08.TOOLS/'vlib.exe',build/'work'],build,build/'vlib.log',60),command(args,build,build/'vlog.log')]
 (build/'compile-result.json').write_text(json.dumps(rs,indent=2))
 t=(build/'vlog.log').read_text(errors='replace');assert all(r['exit_code']==0 and not r['timeout'] for r in rs) and 'Errors: 0' in t and '** Error' not in t,'compile failed'
 print('COMPILE_OK',flush=True)
def overlap(out):
 rows=[x.split() for x in (out/'events.log').read_text().splitlines()];spans=[];p=None
 for x in rows:
  if x[0]=='DAR':assert p is None;p={'epoch':int(x[1]),'start':int(x[2]),'base':int(x[3],16)}
  elif x[0]=='DRLAST':assert p is not None;p['end']=int(x[2]);spans.append(p);p=None
 assert p is None
 hits=[]
 for cam in [0,1]:
  sofs=[x for x in rows if x[0]=='OSOF' and int(x[3])==cam and any(s['epoch']==int(x[1]) and s['start']<=int(x[2])<s['end'] for s in spans)]
  pubs=[x for x in rows if x[0]=='CLPUB' and int(x[3])==cam and int(x[7])==61 and any(s['epoch']==int(x[1]) and s['base']!=int(x[5],16) and s['start']<=int(x[2])<s['end'] for s in spans)]
  assert len(sofs)>=2 and len(pubs)>=1,'actual read overlap missing'
  assert not any(x[0]=='CLPUB' and int(x[3])==cam and int(x[7]) in [62,63] for x in rows),'protected slots publish rejected frames'
  seqs={int(x[7]):int(x[4]) for x in rows if x[0]=='CLPUB' and int(x[3])==cam}
  assert seqs[10]>seqs[61]+1,'drop sequence gaps missing'
  hits.append({'camera':cam,'sofs':sofs,'other_slot_publications':pubs})
 assert any(x[0]=='OVERLAP_DROP_HIT' for x in rows)
 r={'pass':True,'actual_AR_to_last_R_spans':spans,'hits':hits};(out/'overlap-result.json').write_text(json.dumps(r,indent=2));return r
def top(build,name,label,marker,case=0,kind=None,negative=None):
 out=H/'local'/label;out.mkdir(parents=True,exist_ok=True)
 args=[run_t08.TOOLS/'vsim.exe','-c','-modelsimini',build/'modelsim.ini','-lib',build/'work',name,f'+CASE={case}']
 if kind is not None:args+=['-gDUT_KIND='+str(kind)]
 args+=['-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0']
 r=command(args,out,out/'vsim.log');t=(out/'vsim.log').read_text(errors='replace')
 r['sim_pass']=r['exit_code']==0 and not r['timeout'] and marker in t and '** Fatal' not in t and '** Error' not in t and 'T08_FAIL' not in t
 r['pass']=r['sim_pass']
 if negative=='old_mode':
  r['negative_rejected']='MODE_FAIL publication_must_keep_current_mode' in t and 'MODE_FAIL no_phantom_after_idle_roundtrip' in t and 'MODE_MATRIX_FAIL count=' in t and 'MODE_MATRIX_PASS' not in t
  r['pass']=r['negative_rejected']
 if negative=='bad_b':
  r['negative_rejected']='MODE_FAIL B_release_routes_only_B' in t and 'MODE_MATRIX_FAIL count=' in t and 'MODE_MATRIX_PASS' not in t
  r['pass']=r['negative_rejected']
 (out/'sim-result.json').write_text(json.dumps(r,indent=2))
 if r['pass'] and name=='tb_production_sync':
  o=check(out,case)
  if case==16:o['overlap']=overlap(out)
  (out/'oracle-result.json').write_text(json.dumps(o,indent=2));r['pass']=o['pass']
 if r['pass'] and name.endswith('legacy'):
  rows=[x.split() for x in (out/'events.log').read_text().splitlines() if x.startswith('PUB ')];assert len(rows)==6
  for x in rows:
   c,s,fid=int(x[3]),int(x[4]),int(x[7]);b=bytes(int(v,16) for v in (out/f'frame_{c}_{s}.hex').read_text().split());check_r10f(b,c,s,fid)
  r['captured_frames_checked']=6
 (out/'case-result.json').write_text(json.dumps(r,indent=2))
 print(json.dumps({'label':label,'pass':r['pass'],'seconds':r['elapsed_seconds']}),flush=True);assert r['pass'],'case failed '+label
def main():
 p=argparse.ArgumentParser();p.add_argument('phase',choices=['early','regression']);a=p.parse_args();build=H/'local/build'
 if a.phase=='early':
  compile_all(build)
  top(build,'tb_mode_matrix','old-mode-negative','MODE_MATRIX_PASS',kind=1,negative='old_mode')
  top(build,'tb_mode_matrix','mode-matrix','MODE_MATRIX_PASS',kind=0)
  top(build,'tb_tester_edges','original-edges','TESTER_EDGE_PASS')
 else:
  for case in [16,0,10,11,12,13,14]:top(build,'tb_production_sync',f'case{case:02d}','T08_PASS',case)
  top(build,'tb_production_sync_legacy','legacy','T08_PASS')
  top(build,'tb_mode_matrix','bad-b-negative','MODE_MATRIX_PASS',kind=2,negative='bad_b')
 print('PHASE_PASS '+a.phase,flush=True)
if __name__=='__main__':main()

