"""Independent integrated test controller. All outputs stay beneath E; no deletion."""
from pathlib import Path
import sys,os,json,hashlib,subprocess,time,datetime,concurrent.futures
sys.dont_write_bytecode=True
D=Path(r'D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure\T08.dual-local-closure')
E=D.parent/'test-reports'/'T08.dual-local-closure'
T=Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
M=D/'manifest-r0.json'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,o):p.write_text(json.dumps(o,indent=2,ensure_ascii=False),encoding='utf-8')
def snapshot(label):
 m=json.loads(M.read_text()); rows=[]
 for group in ['files','planning_inputs','tools']:
  for x in m[group]:
   p=Path(x['path']);actual=sha(p) if p.is_file() else None
   rows.append(dict(group=group,path=str(p),expected=x['sha256'],actual=actual,match=actual==x['sha256']))
 o=dict(manifest_path=str(M),manifest_sha256=sha(M),files=len(rows),mismatches=[x for x in rows if not x['match']],rows=rows,utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
 save(E/('freeze-'+label+'.json'),o);print('FREEZE',label,len(rows),'mismatches',len(o['mismatches']),flush=True)
 if o['mismatches']:raise RuntimeError('input drift')
 return o
def command(args,cwd,log,timeout=300):
 args=[str(x).replace('\\','/') if isinstance(x,Path) else str(x) for x in args];start=time.monotonic()
 with log.open('w',encoding='utf-8') as f:
  f.write(json.dumps(dict(command=args,cwd=str(cwd),timeout_seconds=timeout))+'\n');f.flush()
  p=subprocess.Popen(args,cwd=cwd,stdout=f,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
  timed=False
  try:code=p.wait(timeout=timeout)
  except subprocess.TimeoutExpired:
   timed=True
   if p.poll() is None:subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT,timeout=15,creationflags=subprocess.CREATE_NO_WINDOW)
   code=p.wait(timeout=15)
  o=dict(command=args,cwd=str(cwd),log=str(log),owned_pid=p.pid,exit_code=code,timeout=timed,elapsed_seconds=time.monotonic()-start)
  f.write('\nCOMMAND_RESULT '+json.dumps(o)+'\n')
 save(log.with_suffix('.command.json'),o)
 return o
def compile_build(name,mutant=False):
 out=E/name;out.mkdir(exist_ok=True);ini=out/'modelsim.ini';ini.write_text('[Library]\nwork = '+(out/'work').as_posix()+'\n',encoding='ascii')
 sources=[Path(x) for x in (D/'sources.f').read_text().splitlines() if x.strip()]
 for p in sources:assert p.is_file() and (p.is_relative_to(D))
 if mutant:
  original=(D/'dual_local_closure.v').read_text();old='if(rel_camera_id) b_release<=rel_slot_id?2:1;else a_release<=rel_slot_id?2:1;'
  assert original.count(old)==1
  mutated=original.replace(old,'if(rel_camera_id) a_release<=rel_slot_id?2:1;else a_release<=rel_slot_id?2:1;')
  p=E/'mutant_b_release_to_a.v';p.write_text(mutated,encoding='utf-8');sources=[p if x==D/'dual_local_closure.v' else x for x in sources]
  save(E/'mutation.json',dict(original_sha256=sha(D/'dual_local_closure.v'),mutant_sha256=sha(p),change='route valid B completion pulse to A',target=str(p),replacements=1))
 sources += [D/x for x in ['vendor_env.sv','sensor_i2c.sv','tb_production_sync.sv','tb_production_sync_legacy.sv','tb_dual_contract.sv']]+[E/'tb_tester_edges.sv']
 save(out/'sources.json',[dict(path=str(p),sha256=sha(p)) for p in sources])
 results=[command([T/'vlib.exe',out/'work'],out,out/'vlib.log',60)]
 args=[T/'vlog.exe','-sv','-modelsimini',ini,'-work',out/'work','+define+MIPI_PHY_SIM_STUB']+['+incdir+'+p.as_posix() for p in sorted(set(x.parent for x in sources))]+sources
 results.append(command(args,out,out/'vlog.log'))
 text=(out/'vlog.log').read_text(errors='replace');good=all(x['exit_code']==0 and not x['timeout'] for x in results) and 'Errors: 0' in text and '** Error' not in text
 save(out/'compile-result.json',dict(pass_=good,commands=results));print('COMPILE',name,good,flush=True)
 if not good:raise RuntimeError('compile failed')
 return out
def sim(build,label,top='tb_production_sync',case=None,negative=False):
 out=E/label;out.mkdir(exist_ok=True)
 args=[T/'vsim.exe','-c','-modelsimini',build/'modelsim.ini','-lib',build/'work',top]
 if case is not None:args += ['+CASE='+str(case)]
 args+=['-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0']
 r=command(args,out,out/'vsim.log',300);text=(out/'vsim.log').read_text(errors='replace')
 marker={'tb_production_sync':'T08_PASS','tb_production_sync_legacy':'T08_PASS','tb_dual_contract':'CONTRACT_PASS','tb_tester_edges':'TESTER_EDGE_PASS'}[top]
 r.update(label=label,top=top,case=case,sim_pass=(r['exit_code']==0 and not r['timeout'] and marker in text and not any(x in text for x in ['** Fatal','** Error','T08_FAIL','CONTRACT_FAIL','EDGE_FAIL'])))
 if negative:r['negative_rejected']='CONTRACT_FAIL B release routes only to B' in text and '** Fatal' in text and 'CONTRACT_PASS' not in text and not r['timeout']
 save(out/'sim-result.json',r);print('CASE_RESULT',label,r['sim_pass'],'exit',r['exit_code'],'seconds',round(r['elapsed_seconds'],2),flush=True);return r
if __name__=='__main__':
 mode=sys.argv[1]
 if mode=='prepare':
  snapshot('before');compile_build('build-baseline');print('PREPARE_COMPLETE',flush=True)
 elif mode=='edges':sim(E/'build-baseline','tester-edges','tb_tester_edges')
 elif mode=='suite':
  # Explicit frozen process list, no retries; 16 production + 2 auxiliary =18.
  cases=[('case%02d'%n,'tb_production_sync',n) for n in range(16)]+[('contract','tb_dual_contract',None),('legacy','tb_production_sync_legacy',0)]
  with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
   futs=[pool.submit(sim,E/'build-baseline',label,top,case) for label,top,case in cases]
   rows=[f.result() for f in futs]
  save(E/'suite-results.json',rows);print('SUITE_COMPLETE',len(rows),sum(x['sim_pass'] for x in rows),flush=True)
 elif mode=='mutant':
  b=compile_build('build-mutant',True);r=sim(b,'negative-b-release','tb_dual_contract',negative=True);save(E/'negative-result.json',r)
 elif mode=='snapshot':snapshot('after')
