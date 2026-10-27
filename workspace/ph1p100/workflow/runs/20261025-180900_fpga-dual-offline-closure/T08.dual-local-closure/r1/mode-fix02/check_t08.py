"""Read actual AXI R bytes and pin traces; standard Python CRC is independent of RTL."""
from pathlib import Path
import argparse,json,re,struct,zlib,collections
from r10f_oracle import check_r10f
H=Path(__file__).resolve().parent
ROOT=Path(r'D:\fpga\ph1p100')
ROLE=[(0,0x3000,1),(0,0x3002,1),(0,0x30c1,15),(1,0x3000,1),(1,0x3002,1),(1,0x30c1,15),
      (1,0x3003,1),(1,0x30c0,42),(0,0x3003,0),(0,0x30c0,42),(0,0x30c1,0),(1,0x3000,0),(0,0x3000,0),(0,0x3002,0)]
def check(out,case):
 rows=[s.split() for s in (out/'events.log').read_text().splitlines()]
 epochs=[(int(x[1]),int(x[2])) for x in rows if x[0]=='EPOCH']
 def ep(t):return max(e for e,et in epochs if et<=t)
 pubs=[{'epoch':int(x[1]),'time':int(x[2]),'cam':int(x[3]),'seq':int(x[4]),'base':int(x[5],16),'length':int(x[6]),'fid':int(x[7])} for x in rows if x[0]=='CLPUB']
 seen=set()
 for p in pubs:
  key=p['epoch'],p['cam'],p['seq'];assert key not in seen,'duplicate full identity';seen.add(key)
  assert p['length']==4096 and p['base'] in ([0x100000,0x900000] if p['cam']==0 else [0x1100000,0x1900000]),'legal separated slots'
 reads=[];current=[]
 for line in (out/'read_beats.log').read_text().splitlines():
  x=line.split();t,a=int(x[1]),int(x[2],16);blob=int(x[3],16).to_bytes(32,'little')
  if a&4095==0:current=[]
  current.append((t,a,blob))
  if a&4095==4064:
   base=current[0][1];assert len(current)==128 and all(v[1]==base+32*i for i,v in enumerate(current)),'full contiguous read and no truncation'
   p=max((p for p in pubs if p['base']==base and p['time']<current[0][0] and p['epoch']==ep(t)),key=lambda p:p['time'])
   data=b''.join(v[2] for v in current)
   if case==10 and p['fid']==70:
    assert zlib.crc32(data[128:148])!=struct.unpack_from('<I',data,84)[0],'target payload CRC fault really observed on R'
    reads.append(dict(p,expected_corruption=True))
   else:reads.append(dict(p,oracle=check_r10f(data,p['cam'],p['seq'],p['fid'])))
 last_ep=epochs[-1][0]
 for cam in [0,1]:assert sum(p['epoch']==last_ep and p['cam']==cam and p['fid']!=70 for p in reads)>=6,'six completed good reads per camera after faults'
 assert any(p['base']>=0x1100000 for p in reads),'B high address actually read'
 # Independent source table oracle; never consult sensor memory or DUT expected register data.
 source=(H/'candidate/rtl/ep_side/cam/ui_imx415_reg.v').read_text(encoding='utf-8',errors='replace')
 table={}
 for line in source.splitlines():
  idx=re.match(r'\s*(\d+):\s+REG_DATA',line);pairs=re.findall(r"\{16'h([0-9a-fA-F]+),\s*8'h([0-9a-fA-F]+)\}",line)
  if idx and pairs:
   a,d=(int(s,16) for s in pairs[0]);table[int(idx[1])]=(a,1 if a in (0x3000,0x3002) else 15 if a==0x30c1 else d)
 assert len(table)==201,'all mode-1 initialization values included'
 pin_results=[]
 for cam in [0,1]:
  lines=[s.split() for s in (out/('i2c_a.log' if cam==0 else 'i2c_b.log')).read_text().splitlines()]
  tx=[x for x in lines if x[0]=='TX' and ep(int(x[1]))==last_ep]
  rd=[x for x in lines if x[0]=='READ' and ep(int(x[1]))==last_ep]
  assert len(tx)>=201+5 and len(rd)>40,'real pin writes and random reads present'
  for n,x in enumerate(tx[:201]):
   a,d=table[n];assert bytes.fromhex(x[3])==bytes([0x34,a>>8,a&255,d]) and int(x[4],16)==15,'all safe initialization bytes/ACKs'
  expected=dict(table.values())
  for x in rd:
   a,d=int(x[2],16),int(x[3],16);want=expected[a] ^ (2 if case==7 and a==0x3000 else 0)
   assert d==want,'independent pin-read value including allowed non-mask variation'
  reqs=[x for x in rows if x[0]=='REQ' and int(x[1])==last_ep and int(x[3])==cam]
  assert len(tx)==201+len(reqs),'exclusive I2C ownership; no AE/automatic start'
  for x,q in zip(tx[201:],reqs):assert bytes.fromhex(x[3])==bytes([0x34,int(q[4],16)>>8,int(q[4],16)&255,int(q[5],16)]),'sync accepted request matches actual pin bytes'
  pin_results.append({'camera':cam,'writes':len(tx),'reads':len(rd)})
 reqs=[(int(x[3]),int(x[4],16),int(x[5],16)) for x in rows if x[0]=='REQ' and int(x[1])==last_ep]
 # Every successful start must contain the precise frozen 14 role writes.
 assert any(reqs[i:i+14]==ROLE for i in range(len(reqs)-13)),'ordered 14 role writes'
 expected_hits={1:'NACK_HIT',2:'MISSING_HIT',3:'RESET_HIT',5:'PENDING_RESET_HIT',6:'MASK_REJECT_HIT',8:'I2C_TIMEOUT_HIT',9:'I2C_TIMEOUT_HIT',10:'DRAIN_HIT',11:'DRAIN_HIT',12:'DRAIN_HIT',13:'LOCK_HIT'}
 if case in expected_hits:assert any(x[0]==expected_hits[case] for x in rows),'explicit required fault hit'
 sim=json.loads((out/'sim-result.json').read_text());assert sim['sim_pass'],'simulation marker and assertions'
 return {'pass':True,'case':case,'read_frames':len(reads),'good_frames':sum('oracle' in p for p in reads),'frames':reads,'pins':pin_results,'mismatch':0}
if __name__=='__main__':
 a=argparse.ArgumentParser();a.add_argument('out',type=Path);a.add_argument('--case',type=int,required=True);p=a.parse_args()
 try:r=check(p.out,p.case)
 except (AssertionError,ValueError,KeyError,IndexError) as e:r={'pass':False,'case':p.case,'error':str(e)}
 (p.out/'oracle-result.json').write_text(json.dumps(r,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in r.items() if k!='frames'}));raise SystemExit(0 if r['pass'] else 1)
