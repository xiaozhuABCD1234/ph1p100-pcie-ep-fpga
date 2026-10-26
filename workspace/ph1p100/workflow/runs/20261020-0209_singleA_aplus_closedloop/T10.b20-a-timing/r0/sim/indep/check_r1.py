"""Independent source/RAW10/transform/CRC/zlib/wire and loss-precondition checks."""
import hashlib,json,pathlib,re,struct,sys,zlib
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent
def pack(samples):
    out=bytearray()
    for i in range(0,len(samples),4):
        a,b,c,d=samples[i:i+4]
        out.extend([a>>2,b>>2,c>>2,d>>2,(a&3)|((b&3)<<2)|((c&3)<<4)|((d&3)<<6)])
    return bytes(out)
def expected(seed,w=32,h=2):
    rows=[];st=0x12345678^seed
    for y in range(2+h):
        row=[]
        for _ in range((w+8)//4):
            st^=(st<<13)&0xffffffff;st^=st>>17;st^=(st<<5)&0xffffffff;st&=0xffffffff
            row.extend([st&1023,(st>>10)&1023,(st>>20)&1023,(st>>22)&1023])
        if y>=2:rows.append(row[4:4+w])
    raw=pack(sum(rows,[]));xf=[]
    for y in range(0,h,2):
        for yp in range(2):
            for xp in range(2):
                plane=rows[y+yp][xp::2]
                xf.extend([plane[0]]+[(b-a)&1023 for a,b in zip(plane,plane[1:])])
    return raw,pack(xf)
def packets(data):
    off=0;frames=[]
    while off<len(data):
        assert len(data)-off>=44,'partial header'
        hdr=data[off:off+44]
        magic,ver,flags,hlen,fid,w,h,rawlen,xlen,slen,rawcrc,xfcrc,scrc,hcrc=struct.unpack('<IBBHIHHIIIIIII',hdr)
        assert (magic,ver,flags,hlen,w,h)==(0x31553141,1,3,44,32,2),'header protocol/geometry'
        assert rawlen==xlen==80 and 0<slen<200,'lengths'
        pay=data[off+44:off+44+slen];assert len(pay)==slen,'partial payload'
        assert zlib.crc32(hdr[:40])&0xffffffff==hcrc,'header CRC'
        assert zlib.crc32(pay)&0xffffffff==scrc,'stream CRC'
        dec=zlib.decompressobj();xf=dec.decompress(pay)+dec.flush()
        assert dec.eof and not dec.unused_data and not dec.unconsumed_tail,'zlib EOF/tail'
        assert len(xf)==xlen and zlib.crc32(xf)&0xffffffff==xfcrc,'transform length/CRC'
        matches=[]
        for seed in [11,100,1000,1001]:
            raw,expectxf=expected(seed)
            if xf==expectxf and zlib.crc32(raw)&0xffffffff==rawcrc:matches.append(seed)
        assert len(matches)==1,'RAW source CRC / reference transform mismatch'
        frames.append(dict(frame_id=fid,seed=matches[0],offset=off,bytes=44+slen,stream_len=slen,
                           four_crcs=True,reference_raw_and_xform=True,strict_zlib=True))
        off+=44+slen
    return frames
def check(case_dir):
    case_dir=pathlib.Path(case_dir);errors=[]
    stat_path=case_dir/'stats.txt'
    stats={k:int(v)for k,v in re.findall(r'(\w+)=(-?\d+)',stat_path.read_text()if stat_path.exists()else '')}
    needed={'case','bytes','uart_bytes','clean_done','geom','dups','exp','rawpub','enc','rejects','aborts'}
    if not needed.issubset(stats):
        result=dict(status='INVALID',valid_test=False,classification='INVALID_CONTROL',
                    errors=['TB ended without complete final stats; no DUT conclusion'],stats=stats,
                    missing_stats=sorted(needed-set(stats)))
        (case_dir/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        return result
    log=(case_dir/'console.log').read_text(errors='replace')
    debug=bytes(map(int,(case_dir/'capture.dec').read_text().split()))
    wire=bytes(map(int,(case_dir/'uart.dec').read_text().split()))
    trace=(case_dir/'trace.txt').read_text()
    def require(ok,why):
        if not ok:errors.append(why)
    require('CASE_RESULT case='+str(stats['case']) in log and 'Fatal' not in log,'TB did not complete normally')
    require(debug==wire and len(wire)==stats['bytes']==stats['uart_bytes'],'actual UART wire/debug accounting')
    require(stats['clean_done']==1 and stats['geom']==0 and stats['dups']==0,'clean/geometry/duplicate control')
    decoded=[]
    try:decoded=packets(wire)
    except (AssertionError,zlib.error,ValueError,struct.error)as e:errors.append(str(e))
    require(len(decoded)==stats['exp'],'packet/export count mismatch')
    require(bool(decoded)and decoded[0]['seed']==11,'complete clean packet absent')
    require(len({p['frame_id']for p in decoded})==len(decoded),'duplicate frame ID')
    failure_evidence={}
    if stats['case']==0:
        require(stats['exp']==stats['rawpub']==stats['enc']==1 and stats['rejects']==stats['aborts']==0,'clean counts')
    else:
        require(stats['fault_crop']==16 and stats['fault_sof_accept']==stats['fault_writer_begin']==stats['fault_last_reject']==1,'loss preconditions')
        require(stats['fault_full']>0 and stats['fault_rejects']>0 and stats['fault_aborts']==0,'finite FIFO/normal crop precondition')
        require('tag=last_rejected 'in trace and 'tag=released_drained 'in trace,'trace preconditions')
        require(stats['recovery_inputs']==2,'subsequent good-frame budget')
        require(all(p['seed']!=100 for p in decoded),'damaged frame published')
        slot=stats['fault_slot'];slot_state=stats['slot'+str(slot)]
        failure_evidence=dict(last_rejected=stats['fault_last_reject'],sof_accepted=stats['fault_sof_accept'],
            writer_began=stats['fault_writer_begin'],fault_crop_groups=stats['fault_crop'],
            recovered_packets=sum(p['seed']in(1000,1001)for p in decoded),writer_final=stats['writer_final'],
            fault_slot=slot,fault_slot_final_state=slot_state,raw_abort_count=stats['raw_abort_cnt'],
            begin_denials=stats['begin_deny'],rawpub=stats['rawpub'],exported=stats['exp'])
        require(stats['result_fail']==0,'recovery criterion failed')
        require(stats['exp']==3 and stats['rawpub']==3 and stats['writer_final']==0,'RAW-slot release / good-frame recovery')
        require([p['seed']for p in decoded]==[11,1000,1001],'exact recovery source sequence')
        require(slot_state==0 and stats['writer_final']==0,'fault RAW slot not FREE')
    valid=(stats['case']==0 and not errors)or(stats['case']==1 and
          not [e for e in errors if e not in ['recovery criterion failed','RAW-slot release / good-frame recovery',
                                             'exact recovery source sequence','fault RAW slot not FREE']])
    status='PASS'if not errors else ('DUT_FAIL_VALID'if valid and stats['case']==1 else 'INVALID')
    result=dict(status=status,errors=errors,valid_test=valid,stats=stats,decoded=decoded,
                failure_evidence=failure_evidence,uart_sha256=hashlib.sha256(wire).hexdigest(),bytes=len(wire))
    (case_dir/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    return result
if __name__=='__main__':
    result=check(sys.argv[1]);print(json.dumps(result,indent=2));sys.exit(0 if result['status']=='PASS' else 2)
