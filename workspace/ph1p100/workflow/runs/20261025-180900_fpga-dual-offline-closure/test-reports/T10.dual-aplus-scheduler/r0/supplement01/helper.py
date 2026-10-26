import os,sys,time,json,datetime,subprocess,hashlib,struct,zlib,csv,re,traceback
from pathlib import Path
sys.dont_write_bytecode=True
O=Path(__file__).resolve().parent
R=O.parents[3]
S=R/'T10.dual-aplus-scheduler/cmp-stall-fix01'
BIN=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
DEADLINE=datetime.datetime.fromisoformat(json.loads((O/'budget-start.json').read_text(encoding='utf-8-sig'))['absolute_deadline']).timestamp()
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
