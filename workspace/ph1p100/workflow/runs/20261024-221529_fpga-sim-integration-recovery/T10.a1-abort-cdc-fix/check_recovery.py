"""Strict, independent packet/zlib/CRC, source identity and recovery checks."""
import hashlib, json, pathlib, re, struct, sys, zlib
sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
FROZEN = HERE.parent / 'inputs/a1-r5'
sys.path.insert(0, str(FROZEN / 'checker'))
from a1_pattern import inverse_xform

def expected(seed, w, h=2):
    rows=[]; st=0x12345678 ^ seed
    for y in range(2+h):
        row=[]
        for g in range((w+8)//4):
            st ^= (st << 13) & 0xffffffff
            st ^= st >> 17
            st ^= (st << 5) & 0xffffffff
            st &= 0xffffffff
            row += [st&1023,(st>>10)&1023,(st>>20)&1023,(st>>22)&1023]
        if y >= 2: rows.append(row[4:4+w])
    out=bytearray()
    for row in rows:
        for x in range(0,w,4):
            a,b,c,d=row[x:x+4]
            out.extend([a>>2,b>>2,c>>2,d>>2,(a&3)|((b&3)<<2)|((c&3)<<4)|((d&3)<<6)])
    return bytes(out)

def packets(data,w,h,allowed):
    off=0; result=[]; ids=set(); seen_seeds=set()
    while off<len(data):
        assert len(data)-off>=44, 'tail/partial header'
        hdr=data[off:off+44]
        magic,ver,flags,hlen,fid,fw,fh,rawlen,xlen,slen,rawcrc,xfcrc,scrc,hcrc=struct.unpack('<IBBHIHHIIIIIII',hdr)
        assert (magic,ver,flags,hlen,fw,fh)==(0x31553141,1,3,44,w,h), 'header protocol/geometry'
        assert rawlen==xlen==w*h*10//8, 'declared raw/transform length'
        assert slen>0 and slen<=rawlen+64, 'payload size bound'
        pay=data[off+44:off+44+slen]
        assert len(pay)==slen, 'truncated payload'
        assert zlib.crc32(hdr[:40])&0xffffffff==hcrc, 'header CRC'
        assert zlib.crc32(pay)&0xffffffff==scrc, 'stream CRC'
        dec=zlib.decompressobj(); xf=dec.decompress(pay)+dec.flush()
        assert dec.eof and not dec.unused_data and not dec.unconsumed_tail, 'strict zlib end/tail'
        assert len(xf)==xlen and zlib.crc32(xf)&0xffffffff==xfcrc, 'transform length/CRC'
        raw=inverse_xform(xf,1,1,w,h)
        assert len(raw)==rawlen and zlib.crc32(raw)&0xffffffff==rawcrc, 'raw length/CRC'
        matching=[s for s in allowed if expected(s,w,h)==raw]
        assert len(matching)==1, 'wrong source / stale epoch / corrupt bytes'
        seed=matching[0]
        assert fid not in ids and seed not in seen_seeds, 'duplicate frame/source'
        ids.add(fid);seen_seeds.add(seed)
        result.append(dict(frame_id=fid,seed=seed,bytes=44+slen,raw_sha256=hashlib.sha256(raw).hexdigest(),
                           header_crc=True,stream_crc=True,xform_crc=True,raw_crc=True,strict_zlib=True))
        off+=44+slen
    assert off==len(data), 'tail garbage'
    return result

def check(case_dir, case_id, *, inject_override=None, allowed_override=None):
    case_dir=pathlib.Path(case_dir)
    stats={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',(case_dir/'stats.txt').read_text())}
    if inject_override is not None: stats['inject_hit']=inject_override
    log=(case_dir/'console.log').read_text(errors='replace')
    data=bytes(int(x) for x in (case_dir/'capture.dec').read_text().split())
    epoch=1 if case_id in (1,2,6) else 0
    good=list(range(1000+epoch*100,1004+epoch*100))
    trace=(case_dir/'trace.txt').read_text()
    # Complete frames buffered before an overflow can legitimately drain.
    # A frame with any rejected crop beat may never be exported.
    legal_prefix=[]
    if case_id in (4,5,7):
        for line in trace.splitlines():
            if line.startswith('SOURCE_END '):
                v={k:int(x) for k,x in re.findall(r'(\w+)=(\d+)',line)}
                if 100<=v['seed']<108 and v['bad']==0 and v['rejected_delta']==0: legal_prefix.append(v['seed'])
    allowed=good+legal_prefix if allowed_override is None else allowed_override
    errors=[]; decoded=[]
    def require(ok,why):
        if not ok: errors.append(why)
    require('CASE_PASS case='+str(case_id) in log, 'missing CASE_PASS / DUT assertion failed')
    require('Fatal' not in log and 'CYCLE_WATCHDOG' not in log, 'fatal/watchdog')
    require(stats['good_sent']<=4 and stats['good_sent']>0, 'good input budget')
    require(stats['recovered']>=2 and stats['recovery_elapsed']<=1000000, 'bounded recovery')
    if case_id==0:
        require(stats['recovered']>=4 and stats['exported']==4, 'clean must export all four good frames')
    require(stats['dup_words']==0 and stats['old_r_count']==0, 'duplicate/old epoch read')
    require(stats['bytes']==len(data), 'capture byte accounting')
    require(stats['epoch']==epoch, 'reset epoch')
    if case_id:
        require(stats['inject_hit']==1, 'fault trigger absent')
    if case_id in (1,2):
        require(stats['post_reset_zero']==1, 'reset counter/ownership clear')
        hits=[l for l in trace.splitlines() if 'tag=reset_hit ' in l]
        require(len(hits)==1, 'unique reset hit')
        if hits:
            s={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',hits[0])}
            p='raw' if case_id==1 else 'cmp'
            require(s[p+'_aw']>0 and s[p+'_active']==1 and s['rawpub' if case_id==1 else 'enc']==0,
                    'reset was not after a real partial DDR write')
            require(s['aw']==s['w'], 'paired AW/W accounting')
    if case_id==3:
        require(stats['fault_geom']>0 and stats['abort_seen']>0, 'bad frame fault counter')
    if case_id==4:
        require(stats['fifo_full']>0 and stats['fifo_rejected']>0, 'real finite FIFO overflow')
        require(stats['fault_rawdrop']+stats['fault_cmpdrop']+stats['fault_err']>0, 'overflow drop/error counter absent')
    try:
        decoded=packets(data,stats['w'],stats['h'],allowed)
        require(sum(f['seed'] in good for f in decoded)>=2, 'fewer than two complete recovery packets')
        if case_id==0:
            require(len(decoded)==4 and {f['seed'] for f in decoded}==set(good), 'clean all four complete source packets')
        require(len(decoded)==stats['exported'], 'packet/export counter mismatch')
    except (AssertionError,ValueError,zlib.error,IndexError) as exc:
        errors.append(str(exc))
    return dict(case_id=case_id,status='PASS' if not errors else 'FAIL',errors=errors,
                stats=stats,decoded=decoded,bytes=len(data),capture_sha256=hashlib.sha256(data).hexdigest(),
                legal_prefix=legal_prefix,allowed_good_seeds=good)

if __name__=='__main__':
    result=check(sys.argv[1],int(sys.argv[2]));print(json.dumps(result,indent=2));sys.exit(result['status']!='PASS')
