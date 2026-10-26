"""Private ModelSim library; every owned subprocess has a hard deadline."""
import datetime,hashlib,json,pathlib,subprocess,sys,os,struct,zlib
sys.dont_write_bytecode=True
from check import raw,verify
HERE=pathlib.Path(__file__).resolve().parent;TASK=HERE.parent;E=TASK/'evidence';LIB=TASK/'evidence';BIN=pathlib.Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
def run(argv,cwd,log,timeout=300):
 argv=[x.as_posix() if isinstance(x,pathlib.Path) else str(x) for x in argv];record=dict(time=datetime.datetime.now().isoformat(),argv=argv,cwd=str(cwd),timeout=timeout)
 try:
  child=subprocess.Popen(argv,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
  stdout,stderr=child.communicate(timeout=timeout)
  if log.exists():log=log.with_name(log.stem+'-'+datetime.datetime.now().strftime('%H%M%S')+log.suffix)
  log.write_bytes(stdout+stderr);record['returncode']=child.returncode
 except subprocess.TimeoutExpired as ex:
  subprocess.run(['taskkill','/PID',str(child.pid),'/T','/F'],capture_output=True,timeout=15)
  stdout,stderr=child.communicate(timeout=15);log.write_bytes(stdout+stderr);record['returncode']='TIMEOUT'
 record['log']=str(log)
 with (E/'commands.jsonl').open('a')as f:f.write(json.dumps(record)+'\n')
 if record['returncode']!=0:raise RuntimeError(record)
 return log.read_text(errors='replace')
def header(w,h,camera,seq):
 payload=raw(w,h,camera,seq);b=bytearray(128);b[:4]=b'R10F'
 for off,fmt,v in [(4,'H',1),(8,'H',128),(10,'B',camera),(16,'I',0x20261025),(20,'I',seq),(24,'I',1),(28,'H',w),(30,'H',h),(32,'I',w*5//4),(40,'B',0),(42,'B',10),(44,'I',len(payload)),(48,'I',len(payload)),(52,'I',1),(80,'I',zlib.crc32(payload)&0xffffffff),(84,'I',zlib.crc32(payload)&0xffffffff)]:struct.pack_into('<'+fmt,b,off,v)
 struct.pack_into('<I',b,88,zlib.crc32(b)&0xffffffff);return b
def compile_all():
 E.mkdir(exist_ok=True);run([sys.executable,'-B',HERE/'make_tb.py'],HERE,E/'make_tb.log',60)
 src=[TASK/'candidate/a1_deflate_core.v',TASK/'candidate/a1_frame_top.v',TASK/'candidate/dual_aplus_scheduler.sv',HERE/'tb_dual.sv',TASK/'fixture/dual_aplus_scheduler_old.sv',HERE/'tb_dual_old.sv']
 if not (LIB/'modelsim.ini').is_file():
  run([BIN/'vmap.exe','-c'],LIB,E/'vmap-create.log',60)
  run([BIN/'vlib.exe',LIB/'work'],LIB,E/'vlib.log',60)
  run([BIN/'vmap.exe','-modelsimini',LIB/'modelsim.ini','work',LIB/'work'],LIB,E/'vmap.log',60)
 snapshot=[dict(path=str(f),sha256=hashlib.sha256(f.read_bytes()).hexdigest())for f in src]
 (E/'compiled-source.json').write_text(json.dumps(snapshot,indent=2))
 run([BIN/'vlog.exe','-modelsimini',LIB/'modelsim.ini','-work','work','-sv']+src,LIB,E/'compile.log')
 (TASK/'sources.f').write_text('\n'.join(p.as_posix() for p in src[:3])+'\n')
 (TASK/'integration-sources.tcl').write_text('\n'.join('read_verilog {'+p.as_posix()+'}' for p in src[:3])+'\n')
def case(name,w,h,which=0,prep=0,cap=None,mut=0,old=False):
 c=E/name
 if (c/'metadata.csv').exists():c=E/(name+'-retry');assert not c.exists(),'bounded retry already used'
 c.mkdir(exist_ok=True);hdr=c/'headers.hex'
 seqs=range(1,22) if which==1 else (range(1,8)if which in (0,5) else [1])
 with hdr.open('w')as f:
  for cam in range(2):
   for seq in seqs:
    b=bytearray(header(w,h,cam,seq));b[40]=0 if prep else 3;struct.pack_into('<I',b,88,0);struct.pack_into('<I',b,88,zlib.crc32(b)&0xffffffff)
    f.write('@%x\n'%((cam*32+seq)*128));f.write(' '.join('%02x'%v for v in b)+'\n')
 (c/'run.do').write_text('onbreak {quit -code 2}\nonerror {quit -code 2}\nrun -all\nquit -code 0\n')
 for required in [c/'metadata.csv',c/'events.log',c/'c1_q21.zlib']:
  assert required.parent.is_dir() and len(str(required))<32760
 args=[BIN/'vsim.exe','-c','-modelsimini',LIB/'modelsim.ini','-wlf',c/'sim.wlf','-l',c/'transcript.log','-voptargs=+acc',('work.tb_dual_old' if old else 'work.tb_dual'),f'-gW={w}',f'-gH={h}',f'-gCASE={which}',f'-gPREP={prep}',f'-gMUT={mut}',f'+OUT={c.as_posix()}',f'+HDR={hdr.as_posix()}','-do','do '+(c/'run.do').as_posix()]
 if cap is not None:args.append(f'-gCAP={cap}')
 console=run(args,LIB,c/'console.log',600 if which==2 and w==1920 else 300)
 if old:
  assert 'ASSERT_FAIL CMP descriptor changed under stall' in console and 'TB_DONE' not in console,'old defect did not reproduce'
  (c/'expected-rejection.json').write_text(json.dumps(dict(expected_rejection=True,assertion='CMP descriptor changed under stall',actual_source='old renamed immutable fixture')))
  return dict(frames=0)
 if mut:
  assert 'ASSERT_FAIL good RAW release status' in console and 'TB_DONE' not in console,'negative control not rejected'
  (c/'negative-control.json').write_text(json.dumps(dict(expected_rejection=True,mutation='flip byte0 only for groups crossing a 32-byte word',assertion='good RAW release status')))
  return dict(frames=0)
 assert 'TB_DONE' in console and 'ASSERT_FAIL' not in console,'completion marker'
 return verify(c,w,h,14 if which==0 else(4 if which==1 else(2 if which==2 else(8 if which==5 else 0))))
if __name__=='__main__':
 op=sys.argv[1]
 if op=='compile':compile_all()
 elif op=='targeted':
  case('old-cmp-counterexample',64,8,5,old=True)
  case('cmp-matrix',64,8,5)
  case('small-nominal',64,8,0)
  case('crossword-negative',64,8,2,mut=1)
  print('TARGETED_CASES_OK old1 matrix8 nominal14 mutant1')
 elif op=='full':
  r=case('full-nominal',1920,1080,2);print('FULL_NOMINAL_OK',r['frames'])
 else:raise ValueError('only planned nominal/CMP/negative cases are authorized')
