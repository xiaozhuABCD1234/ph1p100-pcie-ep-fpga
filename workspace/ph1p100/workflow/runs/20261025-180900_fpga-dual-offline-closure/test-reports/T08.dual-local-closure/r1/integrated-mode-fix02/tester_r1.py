"""Original integrated tester r1 controller; no developer runner imports."""
from pathlib import Path
import sys,json,hashlib,subprocess,time,datetime,concurrent.futures
sys.dont_write_bytecode=True
R=Path(r'D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure');D=R/'T08.dual-local-closure/r1/mode-fix02';E=Path(__file__).parent;T=Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem');M=D/'manifest-mode-fix02.json';B=E/'build'
W=json.loads((E/'continue03-window.json').read_text());DEADLINE=datetime.datetime.fromisoformat(W['deadline_utc'])
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(n,o):(E/n).write_text(json.dumps(o,indent=2,ensure_ascii=False),encoding='utf-8')
def snapshot(label):
 m=json.loads(M.read_text());assert sha(M)=='38e0615341330aa5b8f1e0e1f9ecf4e169abbdc6bc4856912b9e4f929bdfcce3';rows=[]
 for group in ['files','input_references','tools']:
  for x in m[group]:
   p=Path(x['path']);actual=sha(p) if p.is_file() else None;rows.append(dict(group=group,path=str(p),expected=x['sha256'],actual=actual,match=actual==x['sha256']))
 save('freeze-'+label+'.json',dict(manifest_sha256=sha(M),count=len(rows),mismatches=[x for x in rows if not x['match']],rows=rows,utc=datetime.datetime.now(datetime.timezone.utc).isoformat()));assert all(x['match'] for x in rows);print('FREEZE',label,len(rows),'drift0',flush=True)
def command(args,cwd,log,limit=300):
 remaining=(DEADLINE-datetime.datetime.now(datetime.timezone.utc)).total_seconds();assert remaining>20,'calendar deadline; no process started'
 timeout=min(limit,remaining-15);args=[a.as_posix() if isinstance(a,Path) else str(a) for a in args];started=time.monotonic()
 with log.open('w',encoding='utf-8') as f:
  f.write(json.dumps(dict(command=args,cwd=str(cwd),timeout_seconds=timeout,absolute_deadline=DEADLINE.isoformat()))+'\n');f.flush();p=subprocess.Popen(args,cwd=cwd,stdout=f,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW);timed=False
  try:code=p.wait(timeout=timeout)
  except subprocess.TimeoutExpired:
   timed=True
   if p.poll() is None:subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT,timeout=15,creationflags=subprocess.CREATE_NO_WINDOW)
   code=p.wait(timeout=15)
  o=dict(command=args,cwd=str(cwd),log=str(log),pid=p.pid,exit_code=code,timeout=timed,elapsed_seconds=time.monotonic()-started);f.write('\nCOMMAND_RESULT '+json.dumps(o)+'\n')
 log.with_suffix('.command.json').write_text(json.dumps(o,indent=2),encoding='utf-8');return o
def compile_build():
 snapshot('before');B.mkdir(exist_ok=True);ini=B/'modelsim.ini';ini.write_text('[Library]\nwork = '+(B/'work').as_posix()+'\n',encoding='ascii')
 entries=json.loads((D/'local/build/sources.json').read_text());assert len(entries)==79
 for x in entries:assert Path(x['path']).is_file() and sha(Path(x['path']))==x['sha256']
 repl={str(D/'tb_tester_edges.sv'):E/'tb_tester_edges.sv',str(D/'fixtures/bad_b_release.v'):E/'mutant_bad_b.v'}
 files=[repl.get(x['path'],Path(x['path'])) for x in entries]+[E/'tb_repair_matrix.sv',E/'tb_dual_contract.sv']
 assert len(files)==81 and len(set(files))==81
 save('compiled-sources.json',[dict(path=str(p),sha256=sha(p)) for p in files]);definitions={}
 for p in files:
  import re
  for name in re.findall(r'\bmodule\s+(\w+)',p.read_text(encoding='utf-8',errors='replace')):definitions.setdefault(name,[]).append(str(p))
 assert all(len(v)==1 for k,v in definitions.items() if k in ['dual_local_closure','dual_local_closure_bad_b','tb_mode_matrix','tb_tester_edges','tb_repair_matrix','tb_dual_contract','cam_r10f_writer','ddr_frame_readback_checker'])
 save('module-bindings.json',definitions)
 results=[command([T/'vlib.exe',B/'work'],B,B/'vlib.log',60)]
 args=[T/'vlog.exe','-sv','-modelsimini',ini,'-work',B/'work','+define+MIPI_PHY_SIM_STUB']+['+incdir+'+p.as_posix() for p in sorted(set(x.parent for x in files))]+files
 results.append(command(args,B,B/'vlog.log'));save('compile-result.json',results);txt=(B/'vlog.log').read_text(errors='replace');assert all(x['exit_code']==0 and not x['timeout'] for x in results) and 'Errors: 0' in txt and '** Error' not in txt;print('INDEPENDENT_COMPILE_PASS sources81',flush=True)
def sim(label,top,case=0,kind=None,negative=False):
 out=E/label;out.mkdir(exist_ok=True);args=[T/'vsim.exe','-c','-modelsimini',B/'modelsim.ini','-lib',B/'work',top,'+CASE='+str(case)]
 if kind is not None:args+=['-gDUT_KIND='+str(kind)]
 args+=['-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0'];o=command(args,out,out/'vsim.log');txt=(out/'vsim.log').read_text(errors='replace')
 marker={'tb_mode_matrix':'MODE_MATRIX_PASS','tb_tester_edges':'TESTER_EDGE_PASS','tb_repair_matrix':'MATRIX_PASS','tb_dual_contract':'CONTRACT_PASS','tb_production_sync':'T08_PASS','tb_production_sync_legacy':'T08_PASS'}[top]
 good=o['exit_code']==0 and not o['timeout'] and marker in txt and not any(x in txt for x in ['** Fatal','** Error','T08_FAIL','MODE_FAIL','MATRIX_FAIL','EDGE_FAIL','CONTRACT_FAIL'])
 o.update(label=label,top=top,case=case,kind=kind,sim_pass=good)
 if negative:o['negative_rejected']=not o['timeout'] and 'MODE_FAIL B_release_routes_only_B' in txt and 'MODE_MATRIX_FAIL count=' in txt and 'MODE_MATRIX_PASS' not in txt;o['accepted_result']=o['negative_rejected']
 else:o['accepted_result']=good
 (out/'sim-result.json').write_text(json.dumps(o,indent=2),encoding='utf-8');print('CASE_RESULT',label,o['accepted_result'],'exit',o['exit_code'],'seconds',round(o['elapsed_seconds'],2),flush=True);return o
if __name__=='__main__':
 if sys.argv[1]=='compile':compile_build()
 elif sys.argv[1]=='suite':
  checks=[('mode-matrix','tb_mode_matrix',0,0,False),('original-edges','tb_tester_edges',0,None,False),('ownership-matrix','tb_repair_matrix',0,None,False),('case16','tb_production_sync',16,None,False),('case00','tb_production_sync',0,None,False),('case10','tb_production_sync',10,None,False),('case11','tb_production_sync',11,None,False),('case12','tb_production_sync',12,None,False),('case13','tb_production_sync',13,None,False),('case14','tb_production_sync',14,None,False),('case15','tb_production_sync',15,None,False),('contract','tb_dual_contract',0,None,False),('legacy','tb_production_sync_legacy',0,None,False),('negative-b-release','tb_mode_matrix',0,2,True)]
  assert len(checks)==14;save('case-dispatch.json',[dict(label=x[0],top=x[1],case=x[2],kind=x[3],negative=x[4]) for x in checks])
  with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:results=[f.result() for f in [pool.submit(sim,*x) for x in checks]]
  save('suite-results.json',results);print('SUITE_COMPLETE',len(results),sum(x['accepted_result'] for x in results),flush=True)
 elif sys.argv[1]=='snapshot':snapshot('after')
