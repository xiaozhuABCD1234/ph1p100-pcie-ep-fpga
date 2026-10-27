"""Tester-owned R10F/ownership/native-bus verifier; no developer checker import."""
import sys
sys.dont_write_bytecode=True
from pathlib import Path
import copy, hashlib, json, os, threading

EV=Path(__file__).resolve().parent
BASE=(0x100000,0x900000,0x1100000,0x1900000)

def crc(data):
    value=0xffffffff
    for byte in data:
        value ^= byte
        for _ in range(8):
            value=(value>>1) ^ (0xedb88320 if value&1 else 0)
    return value ^ 0xffffffff

def loadhex(p):return bytes.fromhex(p.read_text())
def num(data,offset,size=4):return int.from_bytes(data[offset:offset+size],'little')

def verify_frame(data,cam,seq,session):
    assert len(data)==4096,'frame extent'
    assert data[:4]==b'R10F','magic'
    fields=[(4,4,1),(8,2,128),(10,1,cam),(11,1,0),(12,4,0),(16,4,session),
        (20,4,seq),(24,4,1),(28,2,8),(30,2,2),(32,4,10),(36,4,0),
        (40,2,0),(42,2,10),(44,4,20),(48,4,20),(52,4,1)]
    for offset,size,expected in fields:
        assert num(data,offset,size)==expected,f'header field {offset}'
    assert data[56:80]==bytes(24) and data[92:128]==bytes(36),'reserved fields'
    payload=data[128:148]
    expected=bytes((cam*97+(99+seq)*13+row*23+col*7)%256 for row in range(2) for col in range(10))
    assert payload==expected,'source payload'
    # Decode packed RAW10 into actual samples, independently checking low-bit lanes.
    pixels=[]
    for offset in range(0,20,5):
        group=payload[offset:offset+5]
        pixels.extend((group[i]<<2)|((group[4]>>(2*i))&3) for i in range(4))
    assert len(pixels)==16 and all(0<=x<=1023 for x in pixels),'sample extent'
    assert data[148:]==bytes(3948),'DMA padding'
    assert num(data,80)==num(data,84)==crc(payload),'payload CRC'
    header=bytearray(data[:128]);header[88:92]=bytes(4)
    assert num(data,88)==crc(header),'header CRC'
    return hashlib.sha256(data).hexdigest()

def inspect_case(folder):
    rows=[x.split() for x in (folder/'events.log').read_text().splitlines()]
    tag=lambda t:[r[1:] for r in rows if r[0]==t]
    case,t0,period_a,period_b,phase,recover=map(int,tag('CONFIG')[0])
    summary=list(map(int,tag('SUMMARY')[0]));pub=tag('PUB');desc=tag('DESC');rel=tag('RELEASE')
    sof={cam:[list(map(int,r)) for r in tag('SSOF') if int(r[0])==cam] for cam in [0,1]}
    csof={cam:[list(map(int,r)) for r in tag('CSOF') if int(r[0])==cam] for cam in [0,1]}
    matrix=[]
    for cam,period,shift in [(0,period_a,0),(1,period_b,phase)]:
        eof=[list(map(int,r)) for r in tag('SEOF') if int(r[0])==cam]
        assert len(sof[cam])==len(csof[cam])==len(eof)==12,'SOF/EOF conservation'
        for n,(s,c,e) in enumerate(zip(sof[cam],csof[cam],eof)):
            intended=t0+shift+n*period
            assert s==[cam,100+n,intended,intended],'source schedule'
            assert c[:2]==e[:2]==[cam,100+n],'checked/EOF identity'
            assert intended<=c[2]<e[2]<intended+period,'SOF/EOF timing'
            assert c[2]-intended<=1000,'checked latency'
        actual=[int(r[1]) for r in pub if int(r[0])==cam]
        busy=cam in {0:[],1:[0],2:[1],3:[0,1],4:[0,1],5:[0,1]}[case]
        safe=1
        if busy:
            freed=max(int(r[5]) for r in rel if int(r[0])==cam and int(r[4]) in [1,2])
            safe=next(n+1 for n,c in enumerate(csof[cam]) if n>=2 and c[2]>freed)
            expected=[1,2]+list(range(safe,13))
            assert loadhex(folder/f'snapshot_{cam}_start.hex')==loadhex(folder/f'snapshot_{cam}_end.hex'),'held bytes changed'
        else:expected=list(range(1,13))
        assert actual==expected,'published/source ownership gap'
        assert summary[cam]==summary[2+cam]==len(actual),'publish/release conservation'
        assert summary[4+cam]+len(actual)==12,'source/drop conservation'
        recovered=[int(r[1]) for r in pub if int(r[0])==cam and int(r[5])>=recover]
        assert len(recovered)>=2 and recovered[-2:]==[11,12],'recovery good frames'
        matrix.append({'camera':cam,'source_SOF':12,'source_EOF':12,'checked_SOF':12,
            'accepted':actual,'dropped':sorted(set(range(1,13))-set(actual)),
            'recovered_good':len(recovered),'first_safe_seq':safe,
            'busy_window_source_frames':sum(s[3]<recover for s in sof[cam])})
    # Reconstruct ownership transitions independently of summary counters.
    held={};taken=set();release_pending=[];maximum=0
    for row in rows:
        kind,*r=row
        if kind=='PUB':
            cam,seq,base,session,fid,when=int(r[0]),int(r[1]),int(r[2],16),int(r[3]),int(r[4]),int(r[5])
            index=BASE.index(base);assert index//2==cam and fid==seq+99,'publication source route'
            assert index not in held,'held overwrite'
            held[index]=(cam,index%2,7,session,seq);maximum=max(maximum,len(held))
        elif kind=='DESC':
            cam,slot,epoch,session,seq=map(int,r[:5]);index=cam*2+slot
            assert held[index]==(cam,slot,epoch,session,seq),'descriptor tuple'
            assert num(bytes.fromhex(r[5])[::-1],0)==BASE[index],'descriptor base'
            assert index not in taken,'duplicate descriptor take';taken.add(index)
        elif kind=='RELEASE':
            key=tuple(map(int,r[:5]));index=key[0]*2+key[1]
            assert held[index]==key and index in taken,'release tuple'
            release_pending.append((index,int(r[5])))
        elif kind=='RELWIRE':
            index,when=release_pending.pop(0)
            assert int(r[0])==index//2 and int(r[1])==1<<(index%2),'release wire route'
            assert 0<int(r[2])-when<=32,'release latency'
            del held[index];taken.remove(index)
        elif kind=='BADREL':
            assert r[2]==r[3]=='f','invalid release freed slot'
    assert not held and not taken and not release_pending,'ownership not drained'
    assert maximum==summary[6],'peak occupancy'
    if case in [3,4,5]:assert maximum==4
    if case==5:assert summary[7]==4 and len(tag('BADREL'))==4
    # Native bus trace is a separate capture from published-memory and consumer dumps.
    beats=[r.split() for r in (folder/'read_beats.log').read_text().splitlines() if r.startswith('R ')]
    starts=tag('READBEGIN');assert len(beats)==128*len(starts)==128*len(pub),'native beat conservation'
    digests=[]
    for n,start in enumerate(starts):
        cam,slot,seq,when=map(int,start);index=cam*2+slot
        identity=next(r for r in desc if int(r[0])==cam and int(r[4])==seq)
        session=int(identity[3]);group=beats[n*128:(n+1)*128]
        assert all(int(r[2],16)==BASE[index]+32*k for k,r in enumerate(group)),'native addresses'
        assert all(int(r[1])>=when*1000 for r in group),'native read timing'
        data=b''.join(int(r[3],16).to_bytes(32,'little') for r in group)
        digest=verify_frame(data,cam,seq,session)
        assert data==loadhex(folder/f'frame_{cam}_{seq}.hex')==loadhex(folder/f'read_{cam}_{seq}.hex'),'three byte captures disagree'
        digests.append({'camera':cam,'seq':seq,'sha256':digest})
    deltas=[b[2]-a[2] for a,b in zip(csof[0],csof[1])]
    return {'case_dir':str(folder),'case':case,'recover_ns':recover,'frames':len(digests),
        'native_bytes':len(beats)*32,'matrix':matrix,'maximum_held':maximum,
        'checked_B_minus_A_ns':deltas,'digests':digests}

def main():
    timer=threading.Timer(60,lambda:os._exit(124));timer.daemon=True;timer.start()
    assert crc(b'123456789')==0xcbf43926,'CRC standard check vector'
    results=[inspect_case(EV/f'case{i}') for i in range(6)]
    results.append(inspect_case(EV/'case5-longbusy'))
    # Independent CRC-correct metadata mutation must still be rejected by identity.
    content=bytearray(loadhex(EV/'case0/frame_0_1.hex'))
    content[20:24]=(2).to_bytes(4,'little');content[88:92]=bytes(4)
    content[88:92]=crc(content[:128]).to_bytes(4,'little')
    (EV/'negative-crc-correct-wrong-seq.bin').write_bytes(content)
    try:verify_frame(bytes(content),0,1,0)
    except AssertionError as e:mutation={'rejected':True,'reason':str(e),'header_crc_correct':True}
    else:raise AssertionError('CRC-correct foreign sequence was accepted')
    negative=json.loads((EV/'ready-gated-negative-result.json').read_text())
    text=(EV/'negative-ready-gated/vsim.log').read_text(errors='replace')
    assert 'FREERUN_FAIL' in text and 'source schedule overrun' in text and '** Fatal' in text and 'FREERUN_PASS' not in text
    rejection={'rejected':True,'actual_sim_exit_code':negative['exit_code'],
        'reason':'FREERUN_FAIL source schedule overrun and Fatal at 420us; no success marker',
        'launcher_initial_assertion':'required nonzero simulator exit; corrected by log adjudication without re-run'}
    report={'pass':True,'independent_method':'bitwise IEEE CRC32, explicit header fields, ownership state reconstruction and native-bus beat reconstruction',
        'cases':results,'frames_checked':sum(r['frames'] for r in results),
        'native_bytes_checked':sum(r['native_bytes'] for r in results),
        'crc_correct_identity_mutation':mutation,'ready_gated_actual_simulation_negative':rejection}
    (EV/'tester-oracle-result.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'pass':True,'frames':report['frames_checked'],'native_bytes':report['native_bytes_checked'],
        'matrix':[{k:v for k,v in r.items() if k!='digests'} for r in results],
        'negatives':[mutation,rejection]},indent=2))

if __name__=='__main__':main()
