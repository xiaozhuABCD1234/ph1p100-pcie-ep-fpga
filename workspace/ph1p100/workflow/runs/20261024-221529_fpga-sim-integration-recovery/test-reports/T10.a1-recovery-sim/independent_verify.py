"""Direct camera tap -> forward transform bytes, DDR ownership and effective negatives.
Does not use a1_pattern.inverse_xform or developer expected()/packets() for its oracle.
"""
import hashlib,json,pathlib,re,struct,sys,time,zlib
sys.dont_write_bytecode=True
import independent_test as env
HERE=env.HERE
def kv(s):return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',s)}
def pack(q):return bytes([v>>2 for v in q]+[sum((v&3)<<(i*2) for i,v in enumerate(q))])
def unpack(b):return [(b[i]<<2)|((b[4]>>(2*i))&3) for i in range(4)]
def source_vectors(lines,w):
 taps={}
 for line in lines:
  if not line.startswith('SOURCE_PIXEL '):continue
  s=kv(line);bits=int(line.split('bits=')[1],16)
  if s['row'] in (2,3) and 1<=s['group']<=w//4:
   key=(s['row']-2,s['group']-1)
   d=taps.setdefault(s['seed'],{});assert key not in d,('duplicate source coordinate',s)
   d[key]=bits.to_bytes(5,'little')
 out={}
 for seed,cells in taps.items():
  if len(cells)!=w//2:continue
  raw=b''.join(cells[y,g] for y in (0,1) for g in range(w//4))
  rows=[[p for g in range(w//4) for p in unpack(cells[y,g])] for y in (0,1)]
  delta=[]
  for y in (0,1):
   for parity in (0,1):
    plane=rows[y][parity::2]
    delta.extend([plane[0]]+[(plane[j]-plane[j-1])%1024 for j in range(1,len(plane))])
  xf=b''.join(pack(delta[j:j+4]) for j in range(0,len(delta),4))
  out[seed]=(raw,xf)
 return out
def parse_packets(data,w,allowed,vectors):
 offset=0;frames=[];fids=set();seeds=set()
 while offset<len(data):
  assert len(data)-offset>=44,'partial header/tail'
  h=data[offset:offset+44]
  assert h[:4]==b'A1U1' and h[4:8]==bytes([1,3,44,0]),'wire identity'
  fid=int.from_bytes(h[8:12],'little');fw=int.from_bytes(h[12:14],'little');fh=int.from_bytes(h[14:16],'little')
  rawlen,xlen,slen,rawcrc,xfcrc,scrc,hcrc=struct.unpack_from('<7I',h,16)
  assert fw==w and fh==2 and rawlen==xlen==w*2*10//8,'wire geometry/length'
  assert 0<slen<=rawlen+64 and len(data)>=offset+44+slen,'payload bound'
  p=data[offset+44:offset+44+slen]
  assert zlib.crc32(h[:40])&0xffffffff==hcrc,'header CRC'
  assert zlib.crc32(p)&0xffffffff==scrc,'stream CRC'
  d=zlib.decompressobj();xf=d.decompress(p)+d.flush()
  assert d.eof and not d.unused_data and not d.unconsumed_tail,'strict zlib'
  assert len(xf)==xlen and zlib.crc32(xf)&0xffffffff==xfcrc,'transform CRC/length'
  match=[seed for seed in allowed if seed in vectors and xf==vectors[seed][1]]
  assert len(match)==1,'actual camera tap does not match transform bytes'
  seed=match[0];raw=vectors[seed][0]
  assert zlib.crc32(raw)&0xffffffff==rawcrc,'raw CRC from actual camera tap'
  assert fid not in fids and seed not in seeds,'duplicate frame/source'
  fids.add(fid);seeds.add(seed)
  frames.append(dict(fid=fid,seed=seed,raw_sha256=hashlib.sha256(raw).hexdigest(),transform_sha256=hashlib.sha256(xf).hexdigest(),stream_bytes=slen))
  offset+=44+slen
 assert offset==len(data),'tail'
 return frames
def ownership(lines,w,allowed,vectors):
 states=[0]*4;word_count=[0]*4;written=[[] for _ in range(4)];read_set=[set() for _ in range(4)]
 raw_words=w//8;commits=[];reads=0;writes=0;transitions=0;aborts=0
 for l in lines:
  if l.startswith('SLOTS '):
   q=kv(l);new=[q['r0'],q['r1'],q['c0'],q['c1']]
   for i,(a,b) in enumerate(zip(states,new)):
    if a==b:continue
    transitions+=1
    assert q['reset'] or (a,b) in {(0,1),(1,0),(1,2),(2,3),(3,0)},('illegal ownership transition',i,a,b)
    if b==1:written[i]=[];word_count[i]=0
    if b==3:read_set[i]=set()
    if a==1 and b==0 and not q['reset']:aborts+=1
    if a==1 and b==2:
     word_count[i]=len(written[i]);assert word_count[i]>0,'empty commit'
     if i<2:
      actual=b''.join(written[i]);match=[seed for seed in allowed if seed in vectors and actual==vectors[seed][0]]
      assert len(match)==1,'RAW DDR commit differs from actual source / fault frame committed'
      commits.append(match[0])
    if a==3 and b==0 and not q['reset']:
     assert len(read_set[i])==word_count[i],('incomplete/extra DDR read transaction',i,len(read_set[i]),word_count[i])
   states=new
  elif l.startswith(('READ ','WRITE ')):
   q=kv(l);addr=q['address'];base=0 if addr<131072 else 131072;stride=raw_words if base==0 else 81085
   slot=(addr-base)//stride;local=(addr-base)%stride;i=slot+(0 if base==0 else 2)
   assert slot in (0,1),'address outside both slots'
   if l.startswith('WRITE '):
    assert states[i]==1 and local==len(written[i]),'write owner/order'
    bits=int(l.split('data=')[1],16);blob=bits.to_bytes(32,'little')
    if i<2:assert not any(blob[20:]),'RAW DDR padding'
    written[i].append(blob[:20] if i<2 else blob);writes+=1
   else:
    assert states[i]==3 and addr not in read_set[i],'read owner/duplicate address within same ownership'
    read_set[i].add(addr);reads+=1
 assert states==[0,0,0,0],'RAW/CMP final slot leak'
 assert len(commits)==len(set(commits)),'RAW source committed twice'
 return dict(writes=writes,reads=reads,transitions=transitions,raw_commits=commits,aborted_write_slots=aborts,final_slots=states,duplicate_reads=0)
def verify():
 rows=[];old_ar=0
 for x in env.js(HERE/'matrix-results.json'):
  assert x['status']=='PASS'
  name=x['name'];ratio=x['ratio'];c,w=env.CASES[name];d=HERE/'combined'/(name+'-'+ratio)
  s=kv((d/'stats.txt').read_text());trace=(d/'trace.txt').read_text();tlines=trace.splitlines();olines=(d/'observer.txt').read_text().splitlines()
  vectors=source_vectors(olines,w);epoch=int(c in (1,2,6));good=list(range(1000+epoch*100,1004+epoch*100));prefix=[]
  for l in tlines:
   if l.startswith('SOURCE_END '):
    a=kv(l)
    if 100<=a['seed']<108 and a['bad']==0 and a['rejected_delta']==0:prefix.append(a['seed'])
  allowed=good+prefix
  data=bytes(map(int,(d/'capture.dec').read_text().split()));frames=parse_packets(data,w,allowed,vectors)
  own=ownership(olines,w,allowed,vectors)
  assert set(f['seed'] for f in frames)==set(good+prefix),'missing/extra complete source packet'
  assert set(own['raw_commits'])==set(good+prefix),'RAW commit/output source mismatch'
  assert s['good_sent']==4 and s['recovered']==4 and s['recovery_elapsed']<=1000000
  assert s['bytes']==len(data) and s['exported']==len(frames) and s['dup_words']==s['old_r_count']==0
  control=kv(next(l for l in tlines if l.startswith('CONTROL ')))
  assert control['token_w']==control['token_r'] and control['abort_writes']==control['abort_reads']
  fault=[kv(l) for l in tlines if 'tag=fault_observed ' in l]
  assert all(f['slots0']!=1 and f['slots1']!=1 and not f['raw_active'] for f in fault),'fault RAW ownership not released'
  if c in (1,2):
   hit=kv(next(l for l in tlines if 'tag=reset_hit ' in l));p='raw' if c==1 else 'cmp'
   assert hit[p+'_aw']>0 and hit[p+'_active']==1 and hit['aw']==hit['w'] and hit['rawpub' if c==1 else 'enc']==0
   old_ar+=int(bool(hit['pending'] or hit['rvalid']))
  if c==3:assert control['raw_aborts']==control['abort_writes']==control['abort_reads']==1 and s['fault_rawdrop']>=1
  if c==4:assert s['fifo_full']>0 and s['fifo_rejected']>0 and s['fault_err']+s['fault_rawdrop']+s['fault_cmpdrop']>0
  if c in (5,7):assert control['abort_stalls']>0 and control['abort_writes']==1
  if c==6:assert s['post_reset_zero']==1 and s['epoch']==1
  if c==7:assert control['sof_abort_hits']==1
  if c==8:assert control['last_abort_hits']==1 and s['fault_rawdrop']==1
  rows.append(dict(name=name,ratio=ratio,status='PASS',packets=len(frames),recovery_packets=4,prefix=prefix,recovery_elapsed=s['recovery_elapsed'],frames=frames,ownership=own,control=control))
 old=HERE/'old-top/bad-frame-slow';log=(old/'console.log').read_text();trace=(old/'trace.txt').read_text();command=env.js(old/'console.command.json')
 assert 'ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED' in log and 'CROP_ABORT' in trace and 'ABORT_FIFO_ACCEPT' not in trace and 'RECOVERY_BOUND_FAIL' not in log and 'Error loading design' not in log
 assert not command.get('timed_out') and command['returncode']==0
 env.save(HERE/'old-top-independent-evaluation.json',dict(status='EXPECTED_REJECTION',target='ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED',returncode=command['returncode'],effective=True,initial_harness_result='FAIL solely because initial wrapper incorrectly required exitcode=2; raw run retained; no DUT/test stimulus edit or rerun'))
 result=dict(status='PASS',cases=rows,total_packets=sum(r['packets'] for r in rows),recovery_packets=80,max_recovery_elapsed=max(r['recovery_elapsed'] for r in rows),old_AR_at_reset=dict(hits=old_ar,status='covered' if old_ar else 'not_covered'),independent_oracle='direct camera tap + forward plane/pred transform; no inverse_xform; external DDR ownership/read session/address/commit checks')
 env.save(HERE/'independent-source-slot-result.json',result)
 env.audit('post-verify');print(json.dumps({k:v for k,v in result.items() if k!='cases'},indent=2));return result
def negatives():
 d=HERE/'combined/clean-slow';data=bytes(map(int,(d/'capture.dec').read_text().split()));w=8
 vectors=source_vectors((d/'observer.txt').read_text().splitlines(),w);allow=list(range(1000,1004));size=44+int.from_bytes(data[24:28],'little');first=data[:size];out=[]
 def reject(name,b,allowed=allow):
  try:parse_packets(b,w,allowed,vectors)
  except (AssertionError,ValueError,zlib.error,IndexError,struct.error) as e:out.append(dict(name=name,rejected=True,reason=str(e)))
  else:raise AssertionError('negative unexpectedly accepted: '+name)
 reject('tail-byte',data+b'\xff');reject('duplicate-source',data+first);reject('truncated-stream',data[:-1]);reject('CRC-valid-stale-epoch',data,list(range(1100,1104)))
 for name,offset in [('header-CRC',40),('stream-CRC',36),('transform-CRC',32),('raw-CRC',28)]:
  b=bytearray(first);b[offset]^=1
  if offset!=40:struct.pack_into('<I',b,40,zlib.crc32(b[:40])&0xffffffff)
  reject(name,bytes(b))
 b=bytearray(first[:44]);p=first[44:]+zlib.compress(b'nonempty second stream')
 struct.pack_into('<I',b,24,len(p));struct.pack_into('<I',b,36,zlib.crc32(p)&0xffffffff);struct.pack_into('<I',b,40,zlib.crc32(b[:40])&0xffffffff)
 reject('CRC-valid-concatenated-zlib',bytes(b)+p)
 for n,(c,w) in env.CASES.items():
  if not c:continue
  r=env.checker.check(HERE/'combined'/(n+'-slow'),c,inject_override=0)
  assert 'fault trigger absent' in r['errors'];out.append(dict(name='deleted-inject-hit-'+n,rejected=True,reason='fault trigger absent'))
 assert len(out)==17;env.save(HERE/'checker-negatives.json',out);print('INDEPENDENT_NEGATIVES_REJECTED',len(out))
if __name__=='__main__':verify();negatives()
