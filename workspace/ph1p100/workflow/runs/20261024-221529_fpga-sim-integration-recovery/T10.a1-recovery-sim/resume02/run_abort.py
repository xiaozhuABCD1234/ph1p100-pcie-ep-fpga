"""Bounded ModelSim reproduction: corrected eight RTL and effective original-top negative."""
import pathlib,json,hashlib,subprocess,sys,time,os,re
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent; RUN=HERE.parents[1]
MS=pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
BIND=json.loads((RUN/'recovery-dut-binding-resume02.json').read_text(encoding='utf-8-sig'))
RTL=list(BIND['rtl_paths']); TIMEOUT=300
CASES={'clean':(0,8),'clean32':(0,32),'raw-midwrite-reset':(1,32),'encoded-midwrite-reset':(2,32),'bad-frame':(3,8),'overflow':(4,8),'full-abort':(5,8),'pending-reset':(6,8),'sof-abort':(7,8),'last-skid-abort':(8,8)}
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def protect():
 before=json.loads((HERE/'protection-before.json').read_text()); checked=0
 for x in before['inputs']+before['planning_frozen']:
  p=x.get('path',x.get('frozen'));assert sha(p)==x['sha256'],str(p);checked+=1
 for x in BIND['files']:
  assert sha(x['path'])==x['sha256'];checked+=1
 # Protect all frozen old artifacts and passed exporter artifacts as well.
 for n in ['T10.a1-recovery-sim/resume01/manifest-resume01.json','T10.a1-uart-descriptor-fix/manifest-r0.json']:
  d=json.loads((RUN/n).read_text(encoding='utf-8-sig'))
  for x in d.get('artifacts',[]):
   assert sha(x['path'])==x['sha256'],x['path'];checked+=1
 return dict(checked=checked,drift=0)
def execute(args,folder,name):
 folder.mkdir(exist_ok=True);args=[a.as_posix() if isinstance(a,pathlib.Path) else str(a) for a in args]
 ini=folder if name=='vlib' else HERE # unused; each command has explicit ini
 env=os.environ.copy();env['PYTHONDONTWRITEBYTECODE']='1'
 rec=dict(argv=args,cwd=str(HERE),timeout_seconds=TIMEOUT);start=time.monotonic()
 with (folder/(name+'.log')).open('w',encoding='utf-8') as f:
  p=subprocess.Popen(args,cwd=HERE,env=env,stdout=f,stderr=subprocess.STDOUT);rec['owned_pid']=p.pid
  try:rc=p.wait(timeout=TIMEOUT)
  except subprocess.TimeoutExpired:
   rec['timed_out']=True;subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT,timeout=15);p.wait(timeout=15);rc=-1
 rec.update(returncode=rc,elapsed_seconds=round(time.monotonic()-start,3));(folder/(name+'.command.json')).write_text(json.dumps(rec,indent=2));return rec
def compile(mode):
 before=protect();d=HERE/mode;d.mkdir(exist_ok=True);ini=d/'modelsim.ini'
 ini.write_text('[Library]\nwork = '+(d/'lib').as_posix()+'\n[vsim]\nResolution = ps\n')
 (HERE/'run.do').write_text('onerror {quit -code 2 -f}\nrun -all\nquit -f\n')
 a=execute([MS/'vlib.exe',d/'lib'],d,'vlib');assert a['returncode']==0
 paths=dict(BIND['rtl_paths'])
 if mode=='old': paths['camera_a1_uart_top.v']=str(RUN/'inputs/a1-r5/src/camera_a1_uart_top.v')
 cmd=[MS/'vlog.exe','-sv','-modelsimini',ini,'-work','work']
 if mode=='corrected':cmd+=['+define+CORRECTED']
 b=execute(cmd+[pathlib.Path(paths[n]) for n in RTL]+[HERE/'ddr_recovery_model.sv',HERE/'tb_recovery.sv'],d,'vlog')
 log=(d/'vlog.log').read_text(errors='replace');assert b['returncode']==0 and 'Errors: 0, Warnings: 0' in log,log[-4000:]
 (d/'compile-result.json').write_text(json.dumps(dict(status='PASS',before=before,after=protect(),RTL=paths,commands=[a,b]),indent=2));print('COMPILE_PASS',mode,flush=True)
def run(mode,name,ratio):
 c,w=CASES[name];d=HERE/mode;out=d/(name+'-'+ratio);out.mkdir(exist_ok=True);before=protect()
 cam='7.0' if ratio.startswith('slow') else '1.85';phase='1.7' if ratio.startswith('slow') else '0.91'
 args=[MS/'vsim.exe','-c','-modelsimini',d/'modelsim.ini','-wlf',out/'case.wlf','-l',out/'transcript.log','work.tb_recovery','-gW='+str(w),'-gH=2','-gFIFO_AW='+str(4 if w==32 else 2),'-gCAM_HALF='+cam,'-gA1_PHASE='+phase,'-gMAX_CYCLES=1500000','+CASE='+str(c),'+OUT='+(out/'capture.dec').as_posix(),'+TRACE='+(out/'trace.txt').as_posix(),'+STAT='+(out/'stats.txt').as_posix(),'-do','do '+(HERE/'run.do').as_posix()]
 command=execute(args,out,'console');import check_recovery
 try: result=check_recovery.check(out,c)
 except Exception as e:result=dict(case_id=c,status='FAIL',errors=[repr(e)])
 log=(out/'console.log').read_text(errors='replace');trace=(out/'trace.txt').read_text(errors='replace') if (out/'trace.txt').exists() else ''
 if mode=='old':
  result['effective_negative']='ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED' in log and 'RECOVERY_BOUND_FAIL' not in log and 'Error loading design' not in log and 'CROP_ABORT' in trace and 'ABORT_FIFO_ACCEPT' not in trace
  result['status']='EXPECTED_REJECTION' if result['effective_negative'] else 'FAIL'
 result.update(name=name,ratio=ratio,command=command,protection_before=before,protection_after=protect())
 (out/'result.json').write_text(json.dumps(result,indent=2));print(mode,name,ratio,result['status'],result.get('errors',[]),flush=True)
 print(log[-900:] if result['status']=='FAIL' else '',flush=True)
 return result
if __name__=='__main__':
 if sys.argv[1]=='compile':compile(sys.argv[2])
 elif sys.argv[1]=='run':run(*sys.argv[2:5])
