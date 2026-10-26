"""Independent byte/release and pin oracle: imports no developer checker."""
from pathlib import Path
import json,zlib,struct,collections,re,hashlib,sys
D=Path('D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure\T08.dual-local-closure\r1\mode-fix02');E=Path(__file__).parent
B10=Path(r'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b10-b9-fix\r0\td\src\camera\uisrc\03_ip\ui_imx415_cfg')
BASE=[0x100000,0x900000,0x1100000,0x1900000]
ROLE=[(0,0x3000,1),(0,0x3002,1),(0,0x30c1,15),(1,0x3000,1),(1,0x3002,1),(1,0x30c1,15),(1,0x3003,1),(1,0x30c0,42),(0,0x3003,0),(0,0x30c0,42),(0,0x30c1,0),(1,0x3000,0),(0,0x3000,0),(0,0x3002,0)]
def rows(p):return [x.split() for x in p.read_text().splitlines() if x.strip()]
def frame(blob,cam,seq,fid):
 assert len(blob)==4096,'dma length'
 assert blob[0:4]==b'R10F','magic'
 u=lambda off:struct.unpack_from('<I',blob,off)[0]
 assert u(4)==1 and struct.unpack_from('<H',blob,8)[0]==128 and blob[10]==cam and blob[11]==0,'version/header/codec/camera'
 assert u(12)==0 and u(16)==0 and u(20)==seq and u(24)==1,'flags/session/sequence/mode'
 assert struct.unpack_from('<HH',blob,28)==(8,2) and u(32)==10 and u(36)==0,'geometry/stride/ROI'
 assert struct.unpack_from('<HH',blob,40)==(0,10),'phase and depth'
 assert u(44)==20 and u(48)==20 and u(52)==1,'raw/payload/format'
 assert blob[56:80]==bytes(24) and blob[92:128]==bytes(36),'unknown time and reserved fields'
 header=bytearray(blob[:128]);header[88:92]=bytes(4)
 assert zlib.crc32(header)==u(88),'header standard CRC'
 payload=blob[128:148]
 expected=bytes((cam*97+fid*13+y*23+x*7)%256 for y in range(2) for x in range(10))
 assert payload==expected,'independent source byte pattern'
 # Also unpack 10-bit pixels using the MIPI low-bit-plane layout and compare
 # against values reconstructed from mathematical source bytes.
 pixels=[];reference=[]
 for off in range(0,20,5):
  for pix in range(4):
   pixels.append(payload[off+pix]*4+((payload[off+4]>>(2*pix))&3))
   reference.append(expected[off+pix]*4+((expected[off+4]>>(2*pix))&3))
 assert pixels==reference and len(pixels)==16,'RAW10 inverse sample mismatch'
 assert zlib.crc32(payload)==u(80)==u(84),'raw/payload standard CRC'
 assert not any(blob[148:]),'zero DMA tail'
 return dict(camera=cam,seq=seq,fid=fid,raw_crc=u(80),header_crc=u(88),pixels=len(pixels))
def check_case(label,case=None,legacy=False):
 out=E/label;ev=rows(out/'events.log');epochs=[(int(x[2]),int(x[1])) for x in ev if x[0]=='EPOCH']
 epoch_at=lambda t:max((x for x in epochs if x[0]<=t),default=(0,0))[1]
 pubtag='PUB' if legacy else 'CLPUB'
 pubs=[dict(epoch=int(x[1]),t=int(x[2]),cam=int(x[3]),seq=int(x[4]),base=int(x[5],16),length=int(x[6]),fid=int(x[7])) for x in ev if x[0]==pubtag]
 assert len({(p['epoch'],p['cam'],p['seq']) for p in pubs})==len(pubs),'duplicate identity'
 for p in pubs:assert p['base'] in BASE[p['cam']*2:p['cam']*2+2] and p['length']==4096,'publication bounds'
 final_epoch=epochs[-1][1] if epochs else 0
 if legacy:
  frames=[]
  for p in pubs:
   b=bytes.fromhex((out/('frame_%d_%d.hex'%(p['cam'],p['seq']))).read_text());frames.append(frame(b,p['cam'],p['seq'],p['fid']))
  assert len(frames)==6,'original normal six output frames'
  return dict(pass_=True,label=label,frames=frames)
 reads=[];partial=[]
 for x in rows(out/'read_beats.log'):
  t,addr,beat=int(x[1]),int(x[2],16),int(x[3],16).to_bytes(32,'little')
  if not partial or epoch_at(t)!=epoch_at(partial[-1][0]):partial=[]
  if addr%4096==0:
   assert not partial,'truncated earlier burst within same epoch';partial=[]
  partial.append((t,addr,beat))
  if addr%4096==4064:
   assert len(partial)==128 and [x[1] for x in partial]==list(range(partial[0][1],partial[0][1]+4096,32)),'actual R address sequence'
   origin=max((p for p in pubs if p['epoch']==epoch_at(t) and p['base']==partial[0][1] and p['t']<partial[0][0]),key=lambda p:p['t'])
   b=b''.join(x[2] for x in partial);meta=dict(origin,first_r=partial[0][0],last_r=t)
   if case==10 and origin['fid']==70:
    assert zlib.crc32(b[128:148])!=struct.unpack_from('<I',b,84)[0],'CRC fault must physically reach AXI R';meta['expected_corruption']=True
   else:meta['check']=frame(b,origin['cam'],origin['seq'],origin['fid'])
   reads.append(meta);partial=[]
 assert not partial,'incomplete read at clean finish'
 assert any(p['base']>=BASE[2] for p in reads),'actual high B address'
 for cam in [0,1]:assert sum(x['epoch']==final_epoch and x['cam']==cam and 'check' in x for x in reads)>=6,'six complete good actual R frames per camera after faults'
 # Independent release attribution uses completed physical address spans and epoch;
 # a release without a matching drained read is rejected even if all CRCs agree.
 pending=list(reads);release_checks=[]
 for x in ev:
  if x[0]!='REL':continue
  ep,t=int(x[1]),int(x[2])
  for cam,bits in enumerate(map(int,x[3:5])):
   for slot in [0,1]:
    if bits&(1<<slot):
     hits=[p for p in pending if p['epoch']==ep and p['cam']==cam and p['base']==BASE[cam*2+slot] and p['last_r']<t]
     assert hits,'release before completion, wrong camera/slot, or duplicate release'
     p=min(hits,key=lambda p:p['last_r']);pending.remove(p);release_checks.append(dict(epoch=ep,t=t,cam=cam,slot=slot,seq=p['seq']))
 assert not pending,'complete read lacks release'
 if case==0:
  use=collections.Counter((p['cam'],p['base']) for p in reads)
  assert len(use)==4 and min(use.values())>=2,'reuse every camera slot at least twice'
 table=[]
 for line in (B10/'ui_imx415_reg.v').read_text(encoding='utf-8',errors='replace').splitlines():
  if re.match(r'\s*\d+:\s*REG_DATA',line):
   pairs=re.findall(r"\{16'h([0-9a-fA-F]+),\s*8'h([0-9a-fA-F]+)\}",line)
   if pairs:
    a,d=map(lambda v:int(v,16),pairs[0]);table.append((a,1 if a in [0x3000,0x3002] else 15 if a==0x30c1 else d))
 assert len(table)==201,'frozen original mode1 table size'
 req=[(int(x[3]),int(x[4],16),int(x[5],16)) for x in ev if x[0]=='REQ' and int(x[1])==final_epoch]
 assert any(req[i:i+14]==ROLE for i in range(len(req)-13)),'exact ordered role sequence'
 pins=[]
 for cam in [0,1]:
  pin=rows(out/('i2c_a.log' if cam==0 else 'i2c_b.log'))
  tx=[x for x in pin if x[0]=='TX' and epoch_at(int(x[1]))==final_epoch]
  rd=[x for x in pin if x[0]=='READ' and epoch_at(int(x[1]))==final_epoch]
  assert len(tx)>=201 and len(rd)==49,'all pin read-mask probes present'
  for n,(a,d) in enumerate(table):assert int(tx[n][3],16)==(0x34<<24)|(a<<8)|d and tx[n][4]=='f','frozen table write or ACK differs'
  exp=dict(table)
  for x in rd:
   a,d=int(x[2],16),int(x[3],16);assert d==exp[a]^(2 if case==7 and a==0x3000 else 0),'pin readback differs from frozen source table'
  roles=[x for x in req if x[0]==cam];assert len(tx)==201+len(roles),'shared I2C owner, stray automatic start or AE'
  for x,(_,a,d) in zip(tx[201:],roles):assert int(x[3],16)==(0x34<<24)|(a<<8)|d,'accepted sync command differs from actual pin bytes'
  pins.append(dict(camera=cam,writes=len(tx),reads=len(rd)))
 hits={1:'NACK_HIT',2:'MISSING_HIT',3:'RESET_HIT',5:'PENDING_RESET_HIT',6:'MASK_REJECT_HIT',8:'I2C_TIMEOUT_HIT',9:'I2C_TIMEOUT_HIT',10:'DRAIN_HIT',11:'DRAIN_HIT',12:'DRAIN_HIT',13:'LOCK_HIT',14:'SATURATION_HIT',15:'STALE_REL_HIT'}
 if case in hits:assert any(x[0]==hits[case] for x in ev),'required scenario hit absent'
 return dict(pass_=True,label=label,actual_read_frames=len(reads),good_frames=sum('check' in p for p in reads),frames=reads,releases=release_checks,pins=pins)
def main():
 result=[]
 for name,n,legacy in [('case%02d'%n,n,False) for n in [16,0,10,11,12,13,14,15]]+[('legacy',0,True)]:
  try:o=check_case(name,n,legacy)
  except Exception as ex:o=dict(pass_=False,label=name,error=repr(ex))
  (E/name/'tester-oracle.json').write_text(json.dumps(o,indent=2),encoding='utf-8');result.append(o)
 print(json.dumps([dict(label=x['label'],pass_=x['pass_'],frames=x.get('actual_read_frames',len(x.get('frames',[]))),error=x.get('error')) for x in result]),flush=True)
 (E/'independent-oracle-results.json').write_text(json.dumps(result,indent=2),encoding='utf-8')


def independent_overlap():
 out=E/'case16';ev=rows(out/'events.log');spans=[];pending=None
 for x in ev:
  if x[0]=='DAR':
   assert pending is None,'second accepted AR while first active'
   pending=dict(epoch=int(x[1]),start=int(x[2]),base=int(x[3],16),beats=int(x[4]));assert pending['beats']<=128
  elif x[0]=='DRLAST':
   assert pending is not None and pending['epoch']==int(x[1]);pending['end']=int(x[2]);spans.append(pending);pending=None
 assert pending is None,'unclosed accepted AR'
 actual_r=rows(out/'read_beats.log')
 for span in spans:
  transfers=[x for x in actual_r if span['start']<=int(x[1])<=span['end']]
  assert len(transfers)==span['beats'],'AR actual beat count mismatch'
  assert [int(x[2],16) for x in transfers]==list(range(span['base'],span['base']+span['beats']*32,32)),'AR response address attribution'
  assert span['base']//4096==(span['base']+span['beats']*32-1)//4096,'burst crosses4KiB'
 results=[]
 for cam in [0,1]:
  sof=[x for x in ev if x[0]=='OSOF' and int(x[3])==cam and any(p['epoch']==int(x[1]) and p['start']<=int(x[2])<p['end'] for p in spans)]
  alt=[x for x in ev if x[0]=='CLPUB' and int(x[3])==cam and int(x[7])==61 and any(p['epoch']==int(x[1]) and p['base']!=int(x[5],16) and p['start']<=int(x[2])<p['end'] for p in spans)]
  assert len(sof)>=2 and len(alt)>=1,'both-camera new SOF and alternate-slot complete pub must really overlap accepted read'
  pubs=[x for x in ev if x[0]=='CLPUB' and int(x[3])==cam]
  assert not any(int(x[7]) in [62,63] for x in pubs),'protected-full rejected frames were published'
  seq_by_fid={int(x[7]):int(x[4]) for x in pubs}
  assert seq_by_fid[10]>seq_by_fid[61]+1,'source capture_seq gap after drops must remain'
  result=json.loads((out/'tester-oracle.json').read_text());recover=[x for x in result['frames'] if x['cam']==cam and x['fid'] in range(10,16) and 'check' in x]
  assert len(recover)>=2,'at least two complete post-drop good frames per camera'
  results.append(dict(camera=cam,new_sofs=len(sof),alternate_slot_publications=len(alt),actual_source_sequence_gap=seq_by_fid[10]-seq_by_fid[61]-1,recovered_good_frames=len(recover)))
 drop=[x for x in ev if x[0]=='OVERLAP_DROP_HIT'];assert drop and int(drop[0][2].split('=')[1])>0 and int(drop[0][3].split('=')[1])>0,'both full-drop counters hit'
 result=dict(pass_=True,accepted_AR_to_actual_last_R_spans=spans,cameras=results,source='testers independent actual native handshake/address and data oracle; no developer checker import')
 (E/'independent-overlap.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print('INDEPENDENT_OVERLAP_PASS',results)
if __name__=='__main__':
 main()
 independent_overlap()
