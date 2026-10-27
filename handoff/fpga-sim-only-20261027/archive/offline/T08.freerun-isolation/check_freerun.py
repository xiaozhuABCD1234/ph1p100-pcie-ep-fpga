"""Independent trace + byte oracle. No imports from the RTL or old T08 checker."""
from pathlib import Path
import argparse, copy, hashlib, json, re, struct, zlib

HERE=Path(__file__).resolve().parent
BASES=[0x00100000,0x00900000,0x01100000,0x01900000]
THEMES=['simultaneous_sof','A_busy_B_active','B_busy_A_active_and_skew',
        'consumer_native_AR_long_busy','four_slots_full_new_SOF','stale_identity_reject_and_recovery']

def raw_bytes(camera, fid):
    return bytes((camera*97+fid*13+row*23+k*7)&255 for row in range(2) for k in range(10))

def hexbytes(path): return bytes(int(x,16) for x in path.read_text().split())
def u32(data,offset): return struct.unpack_from('<I',data,offset)[0]

def frame(data, camera, seq, session, fid):
    assert len(data)==4096,'DMA length'
    assert data[:4]==b'R10F' and data[4:8]==b'\x01\0\0\0','magic/version'
    assert struct.unpack_from('<H',data,8)[0]==128,'header size'
    assert data[10]==camera and data[11]==0 and u32(data,12)==0,'camera/format/codec'
    assert (u32(data,16),u32(data,20),u32(data,24))==(session,seq,1),'session/seq/mode'
    assert struct.unpack_from('<HHI',data,28)==(8,2,10),'geometry/stride'
    assert data[36:40]==bytes(4) and data[40:44]==b'\0\0\x0a\0','ROI/phase/packing'
    assert (u32(data,44),u32(data,48),u32(data,52))==(20,20,1),'length/block count'
    assert data[56:80]==bytes(24) and data[92:128]==bytes(36),'reserved/flags'
    payload=raw_bytes(camera,fid)
    assert data[128:148]==payload,'source pixel byte oracle'
    assert data[148:]==bytes(4096-148),'nonzero DMA tail'
    payload_crc=zlib.crc32(payload)&0xffffffff
    assert u32(data,80)==payload_crc and u32(data,84)==payload_crc,'raw/payload CRC'
    header=bytearray(data[:128]);header[88:92]=bytes(4)
    header_crc=zlib.crc32(header)&0xffffffff
    assert u32(data,88)==header_crc,'header CRC'
    return {'camera':camera,'capture_seq':seq,'source_fid':fid,'session':session,
            'raw_crc32':f'{payload_crc:08x}','payload_crc32':f'{payload_crc:08x}',
            'header_crc32':f'{header_crc:08x}','dma_sha256':hashlib.sha256(data).hexdigest()}

def check(out, rows=None, mutations=None):
    rows=rows if rows is not None else [line.split() for line in (out/'events.log').read_text().splitlines()]
    mutations=mutations or {}
    get=lambda tag:[r[1:] for r in rows if r[0]==tag]
    cfg=list(map(int,get('CONFIG')[0]));case,t0,pa,pb,phase,busyend=cfg
    summary=list(map(int,get('SUMMARY')[0]));pubs=get('PUB');descs=get('DESC');releases=get('RELEASE')
    assert 0<=case<6
    matrix=[];frame_checks=[]
    for camera,period,shift in [(0,pa,0),(1,pb,phase)]:
        sources=[list(map(int,r)) for r in get('SSOF') if int(r[0])==camera]
        checked=[list(map(int,r)) for r in get('CSOF') if int(r[0])==camera]
        eofs=[list(map(int,r)) for r in get('SEOF') if int(r[0])==camera]
        assert len(sources)==len(checked)==len(eofs)==12,'free-run source/checked SOF/EOF count'
        assert [r[1] for r in sources]==list(range(100,112)),'source identity order'
        for index,r in enumerate(sources):
            target=t0+shift+index*period
            assert r[2]==r[3]==target,'source schedule was gated or delayed'
            assert checked[index][1]==r[1] and target<=checked[index][2]<=target+1000,'checked SOF missing/delayed'
            assert eofs[index][1]==r[1] and target<eofs[index][2]<target+period,'source EOF/schedule'
        busy=camera in ({1:[0],2:[1],3:[0,1],4:[0,1],5:[0,1]}.get(case,[]))
        cp=[r for r in pubs if int(r[0])==camera]
        seqs=[int(r[1]) for r in cp]
        assert len(seqs)==len(set(seqs)) and seqs==sorted(seqs),'publication sequence duplicate/order'
        first_recovery_seq=7
        if busy:
            initial_releases=[int(r[5]) for r in releases if int(r[0])==camera and int(r[4]) in [1,2]]
            assert len(initial_releases)==2,'original held frames were not released'
            first_recovery_seq=next(i+1 for i,r in enumerate(checked) if i>=6 and r[2]>max(initial_releases))
            assert first_recovery_seq in [7,8],'recovery stalled beyond one boundary frame'
        assert seqs==([1,2]+list(range(first_recovery_seq,13)) if busy else list(range(1,13))),'drop gaps do not match busy source frames and observed release boundary'
        assert summary[camera]==summary[2+camera]==len(cp),'publish/release counts'
        assert summary[4+camera]==12-len(cp),'whole-frame drop counter/source conservation'
        after=[r for r in cp if int(r[5])>=busyend]
        assert len(after)>=2 and [int(r[1]) for r in after][-2:]==[11,12],'two complete recovery good frames missing'
        before_sofs=[r for r in sources if r[3]<busyend]
        if case:assert len(before_sofs)>=6,'busy interval shorter than six complete SOFs'
        if busy:
            assert [int(r[1]) for r in cp if int(r[5])<busyend]==[1,2],'rejected full-slot frame published'
            start=hexbytes(out/f'snapshot_{camera}_start.hex');end=hexbytes(out/f'snapshot_{camera}_end.hex')
            if mutations.get('held_memory')==camera:end=bytes([end[0]^1])+end[1:]
            assert len(start)==8192 and start==end,'held slot memory changed during busy/full'
        for r in cp:
            cam,seq,base,session,fid,when=int(r[0]),int(r[1]),int(r[2],16),int(r[3]),int(r[4]),int(r[5])
            assert fid==99+seq and base in BASES[cam*2:cam*2+2],'source/camera/slot mapping'
            content=hexbytes(out/f'frame_{cam}_{seq}.hex')
            if mutations.get('camera_byte')==(cam,seq):content=content[:10]+bytes([content[10]^1])+content[11:]
            frame_checks.append(frame(content,cam,seq,session,fid))
            assert hexbytes(out/f'read_{cam}_{seq}.hex')==content,'native port read differs from published bytes'
        matrix.append({'camera':camera,'scheduled_sof':12,'actual_source_sof':len(sources),'checked_sof':len(checked),
                       'source_eof':len(eofs),'accepted_sequences':seqs,'dropped_sequences':sorted(set(range(1,13))-set(seqs)),
                       'good_after_recovery':len(after),'busy_interval_sof_count':len(before_sofs),
                       'first_recovery_seq':first_recovery_seq,'drops':summary[4+camera],'releases':summary[2+camera]})
    expected={}
    for r in pubs:
        cam,seq,base,session=int(r[0]),int(r[1]),int(r[2],16),int(r[3])
        slot=BASES.index(base)%2;expected[(cam,slot,7,session,seq)]=1
    actual={}
    for r in descs:
        cam,slot,epoch,session,seq=int(r[0]),int(r[1]),int(r[2]),int(r[3]),int(r[4])
        assert int(r[5],16)==BASES[cam*2+slot],'descriptor base routing'
        key=(cam,slot,epoch,session,seq);actual[key]=actual.get(key,0)+1
    assert actual==expected,'thin A/B descriptor identity does not match real writer publication'
    actual={}
    for r in releases:
        key=tuple(map(int,r[:5]));actual[key]=actual.get(key,0)+1
    assert actual==expected,'release identity or count differs from consumed descriptor'
    wires=get('RELWIRE')
    assert len(wires)==len(releases),'unexpected/missing release wire pulse'
    for rel,wire in zip(releases,wires):
        assert int(wire[0])==int(rel[0]) and int(wire[1])==1<<int(rel[1]),'release wire routed to wrong camera/slot'
        assert 0<int(wire[2])-int(rel[5])<=32,'release wire timing'
    assert summary[6]==4 if case in [3,4,5] else summary[6]<=4,'peak slot occupancy'
    if case==0:assert summary[:6]==[12,12,12,12,0,0],'simultaneous case lost a frame'
    if case==3:
        first=min(int(r[3]) for r in get('READBEGIN'))
        assert first<t0+pa and min(int(r[5]) for r in releases)>=busyend,'long-busy read was not outstanding across source SOFs'
        native=[r.split() for r in (out/'read_beats.log').read_text().splitlines() if r.startswith('R ')]
        assert native and min(int(r[1]) for r in native)>=busyend*1000,'native read incorrectly bypassed busy model'
    if case==5:
        bad=get('BADREL');assert len(bad)==4 and summary[7]==4,'stale epoch/session/camera/sequence rejection coverage'
        assert [int(r[0]) for r in bad]==list(range(4)) and all(r[2]==r[3]=='f' for r in bad),'bad identity freed a held slot'
    return {'local_check_pass':True,'case':case,'theme':THEMES[case],'matrix':matrix,'peak_occupancy':summary[6],
            'identity_rejects':summary[7],'frames':frame_checks}

def negative_controls(out):
    rows=[x.split() for x in (out/'events.log').read_text().splitlines()]
    results=[]
    for name in ['ready_gated_source','camera_byte','held_memory','wrong_camera_release']:
        changed=copy.deepcopy(rows);mut={}
        if name=='ready_gated_source':
            changed.remove(next(r for r in changed if r[:3]==['SSOF','0','103']))
        elif name=='camera_byte':mut={'camera_byte':(0,1)}
        elif name=='held_memory':mut={'held_memory':0}
        else:
            rel=next(r for r in changed if r[0]=='RELWIRE');rel[1]=str(1-int(rel[1]))
        try:check(out,changed,mut)
        except AssertionError as e:results.append({'control':name,'rejected':True,'reason':str(e)})
        else:raise AssertionError('negative control was accepted: '+name)
    return results

def static_interface():
    binding=json.loads((HERE/'inputs/source-binding.json').read_text())
    p3=Path(next(r['path'] for r in binding['references'] if r.get('role')=='interface_reference_only_not_compiled'))
    text=p3.read_text(encoding='utf-8-sig')
    closure=Path(next(r['path'] for r in binding['sources'] if Path(r['path']).name=='dual_local_closure.v')).read_text(encoding='utf-8-sig')
    def port_bits(content,name):
        header=re.sub(r'//[^\n]*','',content).split(');',1)[0]
        for match in re.finditer(r'\b(input|output|inout)\b(.*?)(?=\b(?:input|output|inout)\b|$)',header,re.S):
            block=match.group(2);width=re.search(r'\[(\d+)\s*:\s*(\d+)\]',block)
            bits=abs(int(width.group(1))-int(width.group(2)))+1 if width else 1
            for segment in block.split(','):
                words=re.findall(r'[A-Za-z_]\w*',segment)
                if words and words[-1]==name:return bits
        raise AssertionError('missing interface declaration '+name)
    fields=['camera_id','slot_id','epoch','session','capture_seq']
    checks=[]
    for prefix in ['a_desc_','b_desc_','rel_']:
        for field in fields:
            name=prefix+field
            expected=1 if field in ['camera_id','slot_id'] else 32
            assert port_bits(text,name)==port_bits(closure,name)==expected,'interface identity width '+name
            if prefix!='rel_':assert port_bits(text,'o_'+field)==expected,'selected identity width '+field
            checks.append({'name':name,'bits':expected})
    tb=(HERE/'tb_freerun.sv').read_text()
    source=tb.split('task automatic source(',1)[1].split('endtask',1)[0]
    assert not re.search(r'\b(ready_a|ready_b|pending|local_held|consume|wait)\b',source),'source depends on consumer state'
    assert not re.search(r'\b(force|release)\s+dut\.',tb),'force on real DUT is forbidden'
    assert '1920' in closure and '1080' in closure
    assert all(a+8388608<=b for a,b in zip(BASES,BASES[1:])) and BASES[3]+8388608<2**29
    return {'pass':True,'matched_identity_names':checks,'p3_role':'interface reference only; P3/P4 not instantiated',
            'source_no_ready_or_occupancy_dependency':True,'no_DUT_force':True,'slot_ranges_nonoverlap':True,
            'default_W':1920,'default_H':1080,'packed_bytes_per_camera':2592000,
            'dual_30fps_raw_MB_s':155.520,'runtime_W':8,'runtime_H':2,'runtime_raw_bytes':20,'runtime_DMA_bytes':4096}

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--case-dir',type=Path);p.add_argument('--negative',action='store_true');p.add_argument('--static',action='store_true');a=p.parse_args()
    if a.static:result=static_interface()
    elif a.negative:result={'negative_controls':negative_controls(a.case_dir)}
    else:result=check(a.case_dir)
    print(json.dumps(result,ensure_ascii=False,indent=2))
