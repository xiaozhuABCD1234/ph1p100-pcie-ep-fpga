import os,sys,time,json,datetime,subprocess,hashlib,struct,zlib,csv,re,traceback
from pathlib import Path
sys.dont_write_bytecode=True
O=Path(__file__).resolve().parent
R=O.parents[2]
S=R/'T10.dual-aplus-scheduler/cmp-stall-fix01'
BIN=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
DEADLINE=datetime.datetime.fromisoformat('2026-10-26T02:09:00+08:00').timestamp()
LEDGER=O/'commands.jsonl'
def run(args,log,limit):
 if time.time()+limit+60>DEADLINE: raise RuntimeError('insufficient reserved deadline for command and report')
 args=[str(a).replace('\\','/') for a in args]
 rec={'started':datetime.datetime.now().astimezone().isoformat(),'argv':args,'cwd':str(O),'timeout_seconds':limit}
 c=subprocess.Popen(args,cwd=O,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NEW_PROCESS_GROUP,env={**os.environ,'PYTHONDONTWRITEBYTECODE':'1'})
 try: data,_=c.communicate(timeout=limit);rec['exit_code']=c.returncode
 except subprocess.TimeoutExpired:
  kill=subprocess.run(['taskkill','/PID',str(c.pid),'/T','/F'],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=15)
  data,_=c.communicate(timeout=15);rec['exit_code']='TIMEOUT';rec['owned_tree_termination']=kill.returncode
 log.write_bytes(data);rec['log']=str(log);rec['finished']=datetime.datetime.now().astimezone().isoformat()
 with LEDGER.open('a',encoding='utf-8') as f:f.write(json.dumps(rec)+'\n')
 return rec,data.decode(errors='replace')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def pattern(w,h,cam,seq):
 out=bytearray()
 for y in range(h):
  for x in range(0,w,4):
   vals=[(211*cam+73*seq+3*xx+17*y+29*((xx^y)&7))%1024 for xx in range(x,x+4)]
   out.extend(v//4 for v in vals)
   out.append(sum((v%4)*4**j for j,v in enumerate(vals)))
 return bytes(out)
def mkheader(w,h,cam,seq,prep,isolated=False):
 raw=pattern(w,h,cam,seq);b=bytearray(128);b[:4]=b'R10F'
 for off,fmt,v in [(4,'H',1),(8,'H',128),(10,'B',cam),(16,'I',0x20261025),(20,'I',seq),(24,'I',1),(28,'H',w),(30,'H',h),(32,'I',w*5//4),(40,'B',0 if prep else 3),(42,'B',10),(44,'I',len(raw)),(48,'I',len(raw)),(52,'I',1),(80,'I',zlib.crc32(raw)),(84,'I',zlib.crc32(raw))]:struct.pack_into('<'+fmt,b,off,v)
 if isolated and cam==0:
  if seq==3:b[10]=1
  if seq==22:struct.pack_into('<I',b,16,0x20261026)
  if seq==23:struct.pack_into('<I',b,20,seq+1)
  if seq==24:struct.pack_into('<H',b,28,w+4)
  if seq==25:struct.pack_into('<H',b,30,h+1)
 struct.pack_into('<I',b,88,zlib.crc32(b));return bytes(b)
def inv(data,w,h,prep,pred):
 if not prep:return data
 assert len(data)==w*h*5//4
 values=[]
 for k in range(0,len(data),5):
  high=data[k:k+4];lo=data[k+4]
  values.extend(4*high[j]+((lo//4**j)%4) for j in range(4))
 raster=[0]*(w*h);n=0
 for top in range(0,h,2):
  for parity_y in range(min(2,h-top)):
   for parity_x in range(2):
    acc=0
    for x in range(parity_x,w,2):
     val=values[n];n+=1
     if pred and x>=2:val=(val+acc)%1024
     acc=val;raster[(top+parity_y)*w+x]=val
 result=bytearray()
 for k in range(0,len(raster),4):
  vals=raster[k:k+4];result.extend(v//4 for v in vals);result.append(sum(v%4*4**j for j,v in enumerate(vals)))
 return bytes(result)
FIELDS='camera slot epoch session seq raw_len xform_len stream_len raw_crc xform_crc stream_crc prep pred'.split()
def oracle(c,w,h,count,negative=False):
 rows=list(csv.reader((c/'metadata.csv').open()));answers=[]
 assert len(rows)==count,('frame count',len(rows),count)
 seen=set()
 for row in rows:
  assert len(row)==13
  m=dict(zip(FIELDS,map(int,row)));key=(m['camera'],m['seq']);assert key not in seen;seen.add(key)
  assert m['session']==0x20261025
  wire=(c/f"c{m['camera']}_q{m['seq']}.zlib").read_bytes()
  dec=zlib.decompressobj();xf=dec.decompress(wire)+dec.flush()
  assert dec.eof and not dec.unused_data and not dec.unconsumed_tail,'strict exact zlib consumption'
  restored=inv(xf,w,h,m['prep'],m['pred'])
  assert restored==pattern(w,h,m['camera'],m['seq']),'INDEPENDENT_CAMERA_PATTERN_MISMATCH'
  for name,data in [('raw',restored),('xform',xf),('stream',wire)]:
   assert len(data)==m[name+'_len'],name+' length';assert zlib.crc32(data)==m[name+'_crc'],name+' CRC'
  assert len(wire)<=w*h*5//4+5*((h+1)//2)+6
  answers.append({**m,'strict_eof':True,'raw_sha256':sha_bytes(restored),'wire_sha256':sha_bytes(wire)})
 # Check received native words against an independent byte oracle; full normal streams exact ascending reads.
 if not negative:
  seen_ddr={};heads={}
  with (c/'ddr.log').open() as f:
   for line in f:
    _,ix,sq,off,rid,resp,hexdata=line.split();ix,sq,off,rid,resp=map(int,[ix,sq,off,rid,resp]);key=(ix//2,sq)
    if key not in seen:continue
    assert rid==3 and resp==0
    payload=seen_ddr.setdefault(key,bytearray());expected_off=len(payload);assert off==expected_off,('DDR address/order',key,off,expected_off)
    payload.extend(int(hexdata,16).to_bytes(32,'little'))
  for m in answers:
   key=(m['camera'],m['seq']);wire=seen_ddr[key];raw=pattern(w,h,*key);dma=((128+len(raw)+4095)//4096)*4096
   assert len(wire)==dma and wire[128:128+len(raw)]==raw and not any(wire[128+len(raw):]),'actual native DDR payload/tail'
   hdr=bytearray(wire[:128]);hcrc=int.from_bytes(hdr[88:92],'little');hdr[88:92]=b'\0'*4;assert zlib.crc32(hdr)==hcrc,'actual native header CRC'
   m['native_words']=dma//32;m['native_bytes']=dma;m['groups']=w*h//4
  events=(c/'events.log').read_text();frames=re.findall(r'FRAME cam=(\d+) seq=(\d+) status=(\d+) cycles=(\d+) words=(\d+) groups=(\d+)',events)
  stats=[]
  for cam,sq,status,cyc,words,groups in frames:
   if status=='0' and (int(cam),int(sq)) in seen:
    assert int(words)==((128+w*h*5//4+4095)//4096)*128 and int(groups)==w*h//4
    stats.append({'camera':int(cam),'seq':int(sq),'cycles':int(cyc),'words':int(words),'groups':int(groups),'MBps_at_TB100MHz':w*h*5/4*100/int(cyc)})
  assert len(stats)==count
  (c/'service.json').write_text(json.dumps(stats,indent=2))
 (c/'independent-oracle.json').write_text(json.dumps({'frames':answers,'eof':True,'unused_data':0,'unconsumed_tail':0,'data_mismatch':0},indent=2))
 return len(answers)
def sha_bytes(b):return hashlib.sha256(b).hexdigest()
def compile_all():
 src=[S/'candidate/a1_deflate_core.v',S/'candidate/a1_frame_top.v',S/'candidate/dual_aplus_scheduler.sv',O/'dual_aplus_scheduler_old.sv',O/'dual_aplus_scheduler_swap.sv',O/'tb_integrated.sv',O/'tb_old.sv',O/'tb_swap.sv']
 for tool,args in [('vmap-create',[BIN/'vmap.exe','-c']),('vlib',[BIN/'vlib.exe',O/'work']),('vmap',[BIN/'vmap.exe','-modelsimini',O/'modelsim.ini','work',O/'work'])]:
  rec,msg=run(args,O/(tool+'.log'),60);assert rec['exit_code']==0,msg
 (O/('compiled-source2.json' if sys.argv[1]=='compile2' else 'compiled-source.json')).write_text(json.dumps([{'path':str(p),'sha256':sha(p)} for p in src],indent=2))
 rec,msg=run([BIN/'vlog.exe','-modelsimini',O/'modelsim.ini','-work','work','-sv']+src,O/('compile2.log' if sys.argv[1]=='compile2' else 'compile.log'),300)
 print(json.dumps({'compile_exit':rec['exit_code'],'log':str(O/'compile.log')}),flush=True)
 assert rec['exit_code']==0 and 'Errors: 0' in msg,msg
 (O/'tool-identities.json').write_text(json.dumps({'vlog_banner':msg[:500],'python':sys.version,'zlib':zlib.ZLIB_VERSION},indent=2))
def case(name,w,h,which,prep=0,cap=None,old=False,swap=False,pred=-1,expect=0):
 c=O/name;assert not c.exists(), 'case cannot overwrite/retry same name';c.mkdir()
 # Header generation is a fixture, with identity mutations CRC-correct and isolated.
 seqs=list(range(1,26)) if which==1 else list(range(1,9))
 with (c/'headers.hex').open('w') as f:
  for cam in range(2):
   for seq in seqs:
    b=mkheader(w,h,cam,seq,prep,which==1);f.write('@%x\n'%((cam*32+seq)*128));f.write(' '.join('%02x'%v for v in b)+'\n')
 (c/'run.do').write_text('onbreak {quit -code 2}\nonerror {quit -code 2}\nrun -all\nquit -code 0\n')
 args=[BIN/'vsim.exe','-c','-modelsimini',O/'modelsim.ini','-wlf',c/'sim.wlf','-l',c/'transcript.log','-voptargs=+acc','work.'+('tb_old' if old else 'tb_swap' if swap else 'tb_dual'),f'-gW={w}',f'-gH={h}',f'-gCASE={which}',f'-gPREP={prep}',f'-gPRED={pred}',f'+OUT={c.as_posix()}',f'+HDR={(c/"headers.hex").as_posix()}','-do','do '+(c/'run.do').as_posix()]
 if cap is not None:args.append(f'-gCAP={cap}')
 (c/'parameters.json').write_text(json.dumps(dict(W=w,H=h,CASE=which,PREP=prep,PRED=pred,CAP=cap,expected_frames=expect,old=old,swap=swap),indent=2))
 rec,msg=run(args,c/'console.log',600 if w==1920 and h==1080 else 300)
 result={'name':name,'process_exit':rec['exit_code'],'status':'fail','expected_frames':expect,'log':str(c/'console.log')}
 try:
  if old:
   assert 'ASSERT_FAIL CMP descriptor changed under stall' in msg and 'TB_DONE' not in msg,'old fixture must hit target stall checker'
   result['status']='expected_rejection';result['reason']='CMP descriptor changed under stall'
  else:
   assert rec['exit_code']==0 and 'TB_DONE' in msg and 'ASSERT_FAIL' not in msg and '** Fatal' not in msg,'simulation completion/assertions'
   if swap:
    try:oracle(c,w,h,expect,True)
    except AssertionError as ex:
     assert str(ex)=='INDEPENDENT_CAMERA_PATTERN_MISMATCH',str(ex);result['status']='expected_rejection';result['reason']=str(ex)
    else:raise AssertionError('independent decoder accepted camera swap mutant')
   else:
    result['decoded_frames']=oracle(c,w,h,expect);result['status']='pass'
 except Exception as ex:result['reason']=str(ex);result['traceback']=traceback.format_exc()
 result['hits']=re.findall(r'HIT [^\r\n]+',msg)
 (c/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,ensure_ascii=True),flush=True)
 return result
CASES={
 'nom-8x2-off':(8,2,0,0,None,False,False,-1,14),'nom-8x2-aplus':(8,2,0,1,None,False,False,-1,14),
 'nom-8x3-off':(8,3,0,0,None,False,False,-1,14),'nom-8x3-aplus':(8,3,0,1,None,False,False,-1,14),
 'nom-64x8-off':(64,8,0,0,None,False,False,-1,14),'nom-64x8-aplus':(64,8,0,1,None,False,False,-1,14),
 'full-ab':(1920,1080,2,0,None,False,False,-1,2),'fault-matrix':(64,8,1,0,None,False,False,-1,4),
 'capacity-below':(64,8,3,0,665,False,False,-1,0),'capacity-equal':(64,8,2,0,666,False,False,-1,2),
 'phase-reject':(64,8,4,1,None,False,False,-1,0),'phase-recovery':(64,8,4,1,None,False,False,-1,2),'cmp-matrix':(64,8,5,0,None,False,False,-1,8),
 'old-counterexample':(64,8,5,0,None,True,False,-1,0),'camera-swap-mutant':(64,8,2,0,None,False,True,-1,2),
 'interface-matrix':(64,8,8,0,None,False,False,-1,4),'continuous-fairness':(64,8,6,0,None,False,False,-1,16),'continuous-fairness-retry':(64,8,6,0,None,False,False,-1,16),
 'pred-without-prep':(64,8,9,0,None,False,False,1,0)}
# RAW640 +20+6 =666 for W64/H8.
if __name__=='__main__':
 if sys.argv[1] in ('compile','compile2'):compile_all()
 else:
  results=[]
  for name in sys.argv[1:]:results.append(case(name,*CASES[name]))
  (O/('batch-'+sys.argv[1]+'.json')).write_text(json.dumps(results,indent=2))
  if any(x['status']=='fail' for x in results):sys.exit(1)
