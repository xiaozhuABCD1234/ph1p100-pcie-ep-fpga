"""Private ModelSim library; every owned subprocess has a hard deadline."""
import datetime,hashlib,json,pathlib,subprocess,sys,os,struct,zlib
sys.dont_write_bytecode=True
from check import raw,verify
HERE=pathlib.Path(__file__).resolve().parent;TASK=HERE.parent;E=TASK/'evidence';BIN=pathlib.Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
def run(argv,cwd,log,timeout=300):
 argv=[x.as_posix() if isinstance(x,pathlib.Path) else str(x) for x in argv];record=dict(time=datetime.datetime.now().isoformat(),argv=argv,cwd=str(cwd),timeout=timeout)
 try:
  p=subprocess.run(argv,cwd=cwd,capture_output=True,timeout=timeout,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
  if log.exists():log=log.with_name(log.stem+'-'+datetime.datetime.now().strftime('%H%M%S')+log.suffix)
  log.write_bytes(p.stdout+p.stderr);record['returncode']=p.returncode
 except subprocess.TimeoutExpired as ex:
  log.write_bytes((ex.stdout or b'')+(ex.stderr or b''));record['returncode']='TIMEOUT'
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
 if not (E/'modelsim.ini').exists():
  run([BIN/'vmap.exe','-c'],E,E/'vmap-create.log',60);run([BIN/'vlib.exe',E/'work'],E,E/'vlib.log',60)
  run([BIN/'vmap.exe','-modelsimini',E/'modelsim.ini','work',E/'work'],E,E/'vmap.log',60)
 src=[TASK/'candidate/a1_deflate_core.v',TASK/'candidate/a1_frame_top.v',TASK/'candidate/dual_aplus_scheduler.sv',HERE/'tb_dual.sv']
 run([BIN/'vlog.exe','-modelsimini',E/'modelsim.ini','-work','work','-sv']+src,E,E/'compile.log')
 (TASK/'sources.f').write_text('\n'.join(p.as_posix() for p in src[:3])+'\n')
 (TASK/'integration-sources.tcl').write_text('\n'.join('read_verilog {'+p.as_posix()+'}' for p in src[:3])+'\n')
def case(name,w,h,which=0,prep=0,cap=None):
 c=E/name
 if (c/'metadata.csv').exists():c=E/(name+'-retry');assert not c.exists(),'bounded retry already used'
 c.mkdir(exist_ok=True);hdr=c/'headers.hex'
 seqs=range(1,22) if which==1 else (range(1,8)if which==0 else [1])
 with hdr.open('w')as f:
  for cam in range(2):
   for seq in seqs:
    b=bytearray(header(w,h,cam,seq));b[40]=0 if prep else 3;struct.pack_into('<I',b,88,0);struct.pack_into('<I',b,88,zlib.crc32(b)&0xffffffff)
    f.write('@%x\n'%((cam*32+seq)*128));f.write(' '.join('%02x'%v for v in b)+'\n')
 (c/'run.do').write_text('onbreak {quit -code 2}\nonerror {quit -code 2}\nrun -all\nquit -code 0\n')
 args=[BIN/'vsim.exe','-c','-modelsimini',E/'modelsim.ini','-wlf',c/'sim.wlf','-l',c/'transcript.log','-voptargs=+acc','work.tb_dual',f'-gW={w}',f'-gH={h}',f'-gCASE={which}',f'-gPREP={prep}',f'+OUT={c.as_posix()}',f'+HDR={hdr.as_posix()}','-do','do '+(c/'run.do').as_posix()]
 if cap is not None:args.append(f'-gCAP={cap}')
 console=run(args,E,c/'console.log',600 if which==2 else 300)
 assert 'TB_DONE' in console and 'ASSERT_FAIL' not in console,'completion marker'
 return verify(c,w,h,14 if which==0 else(4 if which==1 else(2 if which==2 else 0)))
if __name__=='__main__':
 op=sys.argv[1]
 if op=='compile':compile_all()
 else:
  specs={'small8x2':(8,2,0,0,None),'odd8x3':(8,3,0,0,None),'small64x8':(64,8,0,0,None),'prep8x3':(8,3,0,1,None),'faults':(64,8,1,0,None),'capacity':(8,2,3,0,8),'phase':(8,2,4,1,None),'full':(1920,1080,2,0,None)}
  result=case(op,*specs[op]);print('LOCAL_CASE_OK',op,result['frames'])
