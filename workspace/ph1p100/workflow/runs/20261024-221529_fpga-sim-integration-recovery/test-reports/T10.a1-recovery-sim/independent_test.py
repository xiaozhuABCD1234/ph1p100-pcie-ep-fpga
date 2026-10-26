"""Independent tester execution; all writes confined to this evidence directory."""
import concurrent.futures, hashlib, importlib.util, json, os, pathlib, re, struct, subprocess, sys, time, zlib
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent
RUN=HERE.parents[1]
DEV=RUN/'T10.a1-recovery-sim/resume02'
MS=pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
MANIFEST=DEV/'manifest-resume02.json'
def js(p):return json.loads(pathlib.Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def save(p,x):pathlib.Path(p).write_text(json.dumps(x,indent=2),encoding='utf-8')
M=js(MANIFEST);B=js(RUN/'recovery-dut-binding-resume02.json')
CASES={'clean':(0,8),'clean32':(0,32),'raw-midwrite-reset':(1,32),'encoded-midwrite-reset':(2,32),'bad-frame':(3,8),'overflow':(4,8),'full-abort':(5,8),'pending-reset':(6,8),'sof-abort':(7,8),'last-skid-abort':(8,8)}
spec=importlib.util.spec_from_file_location('frozen_checker',DEV/'check_recovery.py')
checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker)
def kv(line):return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
def audit(stage):
 if stage=='before':
  entries={};conflicts=[]
  def gather(x):
   if isinstance(x,dict):
    p=x.get('path',x.get('frozen'));h=x.get('sha256')
    if p and h:
     if p in entries and entries[p]!=h:conflicts.append(p)
     entries[p]=h
    for v in x.values():gather(v)
   elif isinstance(x,list):
    for v in x:gather(v)
  gather(M);gather(js(DEV/'protection-before.json'));gather(B)
  for n in ['T10.a1-recovery-sim/manifest-r0.json','T10.a1-recovery-sim/resume01/manifest-resume01.json','T10.a1-uart-descriptor-fix/manifest-r0.json','T10.a1-abort-cdc-fix/manifest-r0.json']:
   p=RUN/n;entries[str(p)]=sha(p);gather(js(p))
  entries[str(MANIFEST)]=sha(MANIFEST)
  entries[str(DEV/'relay-metadata-resume02.json')]=sha(DEV/'relay-metadata-resume02.json')
  assert not conflicts,conflicts
  assert M['status']=='ready_for_test' and M['stopped_modifying'] and M['active_commands']==0
  assert len(M['test_input_paths'])==37 and set(M['test_input_paths'])==set(js(DEV/'relay-metadata-resume02.json')['test_input_paths'])
  save(HERE/'frozen-hash-index.json',entries)
 else:entries=js(HERE/'frozen-hash-index.json')
 failures=[]
 for p,h in entries.items():
  if not pathlib.Path(p).is_file() or sha(p)!=h:failures.append(p)
 result=dict(stage=stage,manifest_sha256=sha(MANIFEST),checked=len(entries),drift=failures,time_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()))
 save(HERE/('audit-'+stage+'.json'),result);assert not failures,failures
 print('AUDIT',stage,len(entries),'DRIFT',len(failures),flush=True);return result
def execute(args,folder,label,timeout=300):
 folder.mkdir(exist_ok=True);args=[p.as_posix() if isinstance(p,pathlib.Path) else str(p) for p in args]
 env=os.environ.copy();env['PYTHONDONTWRITEBYTECODE']='1'
 rec=dict(argv=args,cwd=str(HERE),timeout_seconds=timeout);start=time.monotonic()
 with (folder/(label+'.log')).open('w',encoding='utf-8') as f:
  p=subprocess.Popen(args,cwd=HERE,env=env,stdout=f,stderr=subprocess.STDOUT);rec['owned_pid']=p.pid
  try:rec['returncode']=p.wait(timeout=timeout)
  except subprocess.TimeoutExpired:
   rec['timed_out']=True
   subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT,timeout=15)
   p.wait(timeout=15);rec['returncode']=-1
 rec['elapsed_seconds']=round(time.monotonic()-start,3)
 save(folder/(label+'.command.json'),rec);return rec
def compile_all():
 audit('before');save(HERE/'tester-tool-versions.json',dict(python=sys.version,zlib=zlib.ZLIB_VERSION,manifest_tool_hashes=M['tool_files']))
 (HERE/'run.do').write_text('onerror {quit -code 2 -f}\nrun -all\nquit -f\n',encoding='ascii')
 for mode in ('combined','old-top'):
  d=HERE/mode;d.mkdir(exist_ok=True)
  ini=d/'modelsim.ini';ini.write_text('[Library]\nwork = '+(d/'lib').as_posix()+'\n[vsim]\nResolution = ps\n',encoding='ascii')
  a=execute([MS/'vlib.exe',d/'lib'],d,'vlib');assert a['returncode']==0
  paths=dict(B['rtl_paths'])
  if mode=='old-top':paths['camera_a1_uart_top.v']=str(RUN/'inputs/a1-r5/src/camera_a1_uart_top.v')
  cmd=[MS/'vlog.exe','-sv','-modelsimini',ini,'-work','work']
  if mode=='combined':cmd+=['+define+CORRECTED']
  cmd+=[pathlib.Path(p) for p in paths.values()]+[DEV/'ddr_recovery_model.sv',DEV/'tb_recovery.sv',HERE/'independent_observer.sv']
  b=execute(cmd,d,'vlog');log=(d/'vlog.log').read_text(errors='replace')
  save(d/'compile-result.json',dict(RTL=paths,commands=[a,b],source_hashes=[dict(path=str(p),sha256=sha(p)) for p in cmd if isinstance(p,pathlib.Path) and p.is_file()]))
  assert b['returncode']==0 and 'Errors: 0, Warnings: 0' in log,log[-4000:]
  print('INDEPENDENT_COMPILE_PASS',mode,flush=True)
 audit('post-compile')
def run(mode,name,ratio):
 c,w=CASES[name];d=HERE/mode;out=d/(name+'-'+ratio);out.mkdir(exist_ok=True)
 args=[MS/'vsim.exe','-c','-modelsimini',d/'modelsim.ini','-wlf',out/'case.wlf','-l',out/'transcript.log','work.tb_recovery','work.independent_observer','-g/tb_recovery/W='+str(w),'-g/tb_recovery/H=2','-g/tb_recovery/FIFO_AW='+str(4 if w==32 else 2),'-g/tb_recovery/CAM_HALF='+('7.0' if ratio=='slow' else '1.85'),'-g/tb_recovery/A1_PHASE='+('1.7' if ratio=='slow' else '0.91'),'-g/tb_recovery/MAX_CYCLES=1500000','+CASE='+str(c),'+OUT='+(out/'capture.dec').as_posix(),'+TRACE='+(out/'trace.txt').as_posix(),'+STAT='+(out/'stats.txt').as_posix(),'+OBS='+(out/'observer.txt').as_posix(),'-do','do '+(HERE/'run.do').as_posix()]
 command=execute(args,out,'console');log=(out/'console.log').read_text(errors='replace')
 if mode=='old-top':
  trace=(out/'trace.txt').read_text(errors='replace') if (out/'trace.txt').exists() else ''
  valid=command['returncode']==2 and 'ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED' in log and 'CROP_ABORT' in trace and 'ABORT_FIFO_ACCEPT' not in trace and 'Error loading design' not in log and 'RECOVERY_BOUND_FAIL' not in log
  result=dict(status='EXPECTED_REJECTION' if valid else 'FAIL',effective_negative=valid)
 else:
  result=checker.check(out,c)
  assert command['returncode']==0,log[-4000:]
 result.update(name=name,ratio=ratio,case_id=c,command=command)
 save(out/'result.json',result);print(mode,name,ratio,result['status'],flush=True)
 if result['status']=='FAIL':print(log[-2000:],flush=True)
 return result
def matrix():
 jobs=[(n,r) for r in ('slow','fast') for n in CASES]
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
  rows=list(pool.map(lambda x:run('combined',*x),jobs))
 save(HERE/'matrix-results.json',rows)
 assert len(rows)==20 and all(x['status']=='PASS' for x in rows)
 old=run('old-top','bad-frame','slow');assert old['effective_negative']
 audit('post-matrix');print('INDEPENDENT_20_PLUS_OLD_TOP_PASS',flush=True)
if __name__=='__main__':
 if sys.argv[1]=='compile':compile_all()
 elif sys.argv[1]=='matrix':matrix()
