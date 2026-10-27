"""Independent pin-stream and byte-level R10F/zlib.crc32 oracle."""
from pathlib import Path
import argparse, collections, json, re, struct, zlib
H=Path(__file__).resolve().parent
ROLE=[(0,0x3000,1),(0,0x3002,1),(0,0x30c1,15),
      (1,0x3000,1),(1,0x3002,1),(1,0x30c1,15),
      (1,0x3003,1),(1,0x30c0,42),(0,0x3003,0),
      (0,0x30c0,42),(0,0x30c1,0),(1,0x3000,0),(0,0x3000,0),(0,0x3002,0)]
CLEANUP=[(0,0x3000,1),(1,0x3000,1),(0,0x3002,1),(1,0x3002,1),(0,0x30c1,15),(1,0x30c1,15)]

def check_frame(blob,cam,seq,fid,base,case):
    assert len(blob)==4096,'DMA byte length'
    words=list(struct.unpack('<32I',blob[:128]))
    # Missing-B injection admitted and aborted one A frame only. Camera B's
    # private frame ordinal therefore has no aborted-frame offset.
    fseq=seq+(1 if case==2 and cam==0 else 0)
    assert base==[0x100000,0x900000,0x1100000,0x1900000][cam*2+((fseq-1)&1)],'byte-address slot/camera separation'
    payload=bytes((cam*97+fid*13+row*23+k*7)&255 for row in range(2) for k in range(10))
    assert blob[128:148]==payload,'A/B source pattern and frame identity'
    assert blob[148:]==bytes(4096-148),'DMA zero padding'
    crc=zlib.crc32(payload)
    expected=[0]*32
    expected[:14]=[0x46303152,1,128+(cam<<16),0,0,fseq,1,(2<<16)|8,10,0,10<<16,20,20,1]
    expected[20]=crc;expected[21]=crc
    expected[22]=zlib.crc32(struct.pack('<32I',*expected))
    assert words==expected,'R10F fields, raw/payload/header CRC and reserved bytes'
    return {'camera':cam,'seq':seq,'source_frame':fid,'base':f'{base:08x}','bytes':4096,'crc32':f'{crc:08x}'}

def check_case(out,case):
    rows=[l.split() for l in (out/'events.log').read_text().splitlines()]
    epochs=[(int(x[1]),int(x[2])) for x in rows if x[0]=='EPOCH']
    pins=collections.defaultdict(list)
    for cam in (0,1):
        for line in (out/('i2c_a.log' if cam==0 else 'i2c_b.log')).read_text().splitlines():
            x=line.split()
            if x[0]!='TX':continue
            t,n=int(x[1]),int(x[2]);ep=max(e for e,et in epochs if et<=t)
            pins[ep,cam].append((t,n,bytes.fromhex(x[3]),int(x[4],16)))
    # Initialization oracle is derived from the immutable table text, outside DUT hierarchy.
    source=(H.parent/'inputs/production-raw/rtl/ep_side/cam/ui_imx415_reg.v').read_text(encoding='utf-8',errors='replace')
    table={}
    for line in source.splitlines():
        idx=re.match(r'\s*(\d+):\s+REG_DATA',line)
        pairs=re.findall(r"\{16'h([0-9a-fA-F]+),\s*8'h([0-9a-fA-F]+)\}",line)
        if idx and pairs:
            a,d=map(lambda s:int(s,16),pairs[0]);table[int(idx[1])]=(a,1 if a in (0x3000,0x3002) else 15 if a==0x30c1 else d)
    assert len(table)==201,'complete immutable table oracle'
    reqs=[x for x in rows if x[0]=='REQ'];rsps=[x for x in rows if x[0]=='RSP']
    cancelled=[]
    if case==5:
        hits=[x for x in rows if x[0]=='PENDING_RESET_HIT']
        assert len(hits)==1 and 'accepts=1' in hits[0] and 'responses=0' in hits[0],'pending reset actually hit'
        cancelled=[x for x in reqs if x[1]==hits[0][1] and int(x[2])<int(hits[0][2])]
        assert len(cancelled)==1 and (int(cancelled[0][3]),int(cancelled[0][4],16),int(cancelled[0][5],16))==ROLE[0],'one accepted transaction cancelled by reset'
        assert not any(x[1]==hits[0][1] for x in rsps),'cancelled session has no response'
    assert len(reqs)==len(rsps)+len(cancelled),'request/response count including explicit reset cancellation'
    q=collections.defaultdict(list)
    for x in reqs:
        if x not in cancelled:q[int(x[1]),int(x[3])].append(x)
    for ep,_ in epochs:
        for cam in (0,1):
            tx=pins[ep,cam]
            assert len(tx)==201+len(q[ep,cam]),'no hidden second owner or periodic writer'
            for n,(_,idx,data,ack) in enumerate(tx[:201]):
                a,d=table[n]
                assert idx==n and data==bytes([0x34,a>>8,a&255,d]) and ack==15,'safe complete initialization'
            for req,tx in zip(q[ep,cam],tx[201:]):
                a,d=int(req[4],16),int(req[5],16)
                assert tx[2]==bytes([0x34,a>>8,a&255,d]),'pin stream equals accepted latched transaction'
                assert tx[0]>int(req[2]),'request precedes actual pin completion'
    # Role order comes from the frozen requirement, never from the DUT table.
    starts=[x for x in rows if x[0]=='START']
    # The NACK injection uses a manual start pulse. Its first request is the
    # recorded start boundary; validate that whole fault segment as well.
    if case==1:
        assert reqs and starts and int(reqs[0][2])<int(starts[0][2]),'recorded NACK fault segment'
        starts.insert(0,['START',reqs[0][1],str(int(reqs[0][2])-1)])
    for pos,start in enumerate(starts):
        ep,t=int(start[1]),int(start[2]);end=int(starts[pos+1][2]) if pos+1<len(starts) else 10**30
        segment=[x for x in reqs if int(x[1])==ep and t<int(x[2])<end]
        triples=[(int(x[3]),int(x[4],16),int(x[5],16)) for x in segment]
        expected=ROLE
        if case==1 and pos==0:expected=ROLE[:7]+CLEANUP
        elif case in (2,4) and pos==0:expected=ROLE+CLEANUP
        assert triples==expected,'ordered 14 role writes and six cleanup writes'
        if expected[:14]==ROLE:
            for k in (12,13):
                prior=segment[k-1]
                rsp=next(x for x in rsps if int(x[1])==ep and int(x[2])>int(prior[2]))
                assert int(segment[k][2])-int(rsp[2])>=120*20000,'explicit scaled 24ms wait lower bound'
    failed=[x for x in rsps if x[4]=='0']
    assert len(failed)==(1 if case==1 else 0),'exact NACK response count'
    pin_nacks=[tx for ts in pins.values() for tx in ts if tx[3]!=15]
    assert len(pin_nacks)==len(failed),'last-byte NACK preserved through real busy completion'
    if case==1:assert pin_nacks[0][3]==7,'target NACK is the last byte'
    pubs=[x for x in rows if x[0]=='PUB'];seen=set();frames=[]
    for x in pubs:
        ep,cam,seq=int(x[1]),int(x[3]),int(x[4]);key=ep,cam,seq
        assert key not in seen,'no duplicate publication';seen.add(key)
        assert int(x[6])==4096,'published DMA length'
        blob=bytes(int(v,16) for v in (out/f'frame_{cam}_{seq}.hex').read_text().split())
        frames.append(check_frame(blob,cam,seq,int(x[7]),int(x[5],16),case))
    expected_count=6 if case==4 else 3
    for cam in (0,1):assert sum(f['camera']==cam for f in frames)==expected_count,'three consecutive accepted complete frames'
    if case==1:assert any(x[0]=='NACK_HIT' for x in rows),'NACK actually hit'
    if case==2:assert any(x[0]=='MISSING_HIT' for x in rows),'missing B actually hit'
    if case==3:assert any(x[0]=='RESET_HIT' for x in rows) and len(epochs)==2,'reset after accepted write actually hit'
    if case==5:assert len(epochs)==2 and len(cancelled)==1,'new I2C session after accepted-request reset'
    return {'pass':True,'mismatch':0,'case':case,'pin_transactions':sum(map(len,pins.values())),
            'accepted_requests':len(reqs),'responses':len(rsps),'frames':frames}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('out',type=Path);p.add_argument('--case',type=int,required=True)
    a=p.parse_args()
    try:r=check_case(a.out,a.case)
    except (AssertionError,ValueError,KeyError,StopIteration) as ex:
        r={'pass':False,'case':a.case,'reason':str(ex)}
    (a.out/'oracle-result.json').write_text(json.dumps(r,indent=2),encoding='utf-8')
    print(json.dumps(r));raise SystemExit(0 if r['pass'] else 1)
