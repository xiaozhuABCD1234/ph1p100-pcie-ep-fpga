"""Independent verifier for T10.a1-enc-rtl (tester-authored; no developer code imported).
- zlib 1.2.13 decompressobj (third-party)
- own strict DEFLATE/zlib parser (stored + fixed only)
- own Bayer inverse per format-v1.md
- negative mutation tests
"""
import json, os, sys, zlib, hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))))
P2 = os.path.join(ROOT, r"workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\p2")
TR = os.path.join(ROOT, r"workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\tester-r0")

LEN_BASE = [3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258]
LEN_EXTRA= [0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0]
DIST_BASE= [1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577]
DIST_EXTRA=[0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13]

class E(Exception):
    def __init__(self, code): self.code = code
    def __str__(self): return self.code

def canon(lengths):
    maxb = max(lengths)
    bl = [0]*(maxb+1)
    for l in lengths:
        if l: bl[l]+=1
    code = 0; nxt = [0]*(maxb+1)
    for bits in range(1, maxb+1):
        code = (code + bl[bits-1]) << 1
        nxt[bits] = code
    tab = {}
    for sym,l in enumerate(lengths):
        if l:
            tab[(nxt[l], l)] = sym
            nxt[l]+=1
    return tab

FIX_LITLEN_LEN = [8]*144 + [9]*112 + [7]*24 + [8]*8
FIX_DIST_LEN = [5]*32
TAB_LL = canon(FIX_LITLEN_LEN)
TAB_D = canon(FIX_DIST_LEN)

class Bits:
    def __init__(self, data): self.d=data; self.p=0
    def bit(self):
        if self.p >= len(self.d)*8: raise E('E_TRUNCATED')
        b = (self.d[self.p>>3] >> (self.p&7)) & 1
        self.p += 1
        return b
    def bits(self,n):
        v=0
        for i in range(n): v |= self.bit()<<i
        return v
    def align_zero(self):
        while self.p & 7:
            if self.bit()!=0: raise E('E_BAD_PADDING')
    def bytepos(self): return (self.p+7)//8

def huff(b, tab):
    code=0
    for l in range(1,16):
        code=(code<<1)|b.bit()
        if (code,l) in tab: return tab[(code,l)]
    raise E('E_INVALID_HUFFMAN_CODE')

def parse_zlib_stream(data, expect_len=None, limit=4_000_000):
    if len(data) < 6: raise E('E_TRUNCATED')
    cmf, flg = data[0], data[1]
    if (cmf & 0x0f) != 8: raise E('E_BAD_ZLIB_HEADER')
    if (cmf >> 4) > 7: raise E('E_BAD_ZLIB_HEADER')
    if ((cmf<<8)|flg) % 31 != 0: raise E('E_BAD_ZLIB_HEADER')
    if flg & 0x20: raise E('E_FDICT_SET')
    b = Bits(data); b.p = 16
    out = bytearray()
    nblocks=0; nfixed=0; nstored=0; lits=0; matches=0; maxlen=0; maxdist=0
    minlen=999; dists=set(); pairs=set()
    while True:
        if nblocks > 10000: raise E('E_OUTPUT_LIMIT')
        bfinal = b.bit(); btype = b.bits(2)
        nblocks += 1
        if btype == 0:
            b.align_zero()
            p = b.bytepos()
            if p+4 > len(data): raise E('E_TRUNCATED')
            L = data[p] | (data[p+1]<<8); NL = data[p+2] | (data[p+3]<<8)
            if (L ^ 0xFFFF) != NL: raise E('E_BAD_STORED_NLEN')
            if L > 4800: raise E('E_BAD_STORED_LEN')
            p += 4
            if p+L > len(data): raise E('E_TRUNCATED')
            out += data[p:p+L]; b.p = (p+L)*8
            nstored += 1
        elif btype == 1:
            nfixed += 1
            while True:
                sym = huff(b, TAB_LL)
                if sym < 256:
                    out.append(sym); lits += 1
                    if len(out) > limit: raise E('E_OUTPUT_LIMIT')
                elif sym == 256:
                    break
                elif 257 <= sym <= 285:
                    i = sym-257
                    L = LEN_BASE[i] + b.bits(LEN_EXTRA[i])
                    ds = huff(b, TAB_D)
                    if ds > 29: raise E('E_BAD_DISTANCE_CODE')
                    D = DIST_BASE[ds] + b.bits(DIST_EXTRA[ds])
                    if D > 2048: raise E('E_DISTANCE_WINDOW')
                    if D > len(out): raise E('E_BAD_DISTANCE')
                    for _ in range(L):
                        out.append(out[-D])
                    matches += 1
                    if L > maxlen: maxlen = L
                    if L < minlen: minlen = L
                    if D > maxdist: maxdist = D
                    dists.add(D); pairs.add((L,D))
                    if len(out) > limit: raise E('E_OUTPUT_LIMIT')
                else:
                    raise E('E_BAD_LENGTH_CODE')
        elif btype == 2:
            raise E('E_BAD_BTYPE_DYNAMIC')
        else:
            raise E('E_BAD_BTYPE_RESERVED')
        if bfinal: break
    b.align_zero()
    p = b.bytepos()
    if p+4 > len(data): raise E('E_TRUNCATED')
    adler = int.from_bytes(data[p:p+4], 'big')
    calc = 1
    for x in out:
        calc = (calc + x) % 65521
        calc = (calc * 256) % 65521
    # adler combine over bytes: do proper
    a=1; bb=0
    for x in out:
        a=(a+x)%65521; bb=(bb+a)%65521
    calc=(bb<<16)|a
    if adler != calc: raise E('E_BAD_ADLER')
    if expect_len is not None and len(out) != expect_len: raise E('E_LENGTH_MISMATCH')
    p += 4
    if p != len(data): raise E('E_TRAILING_BYTES')
    return bytes(out), dict(blocks=nblocks, fixed=nfixed, stored=nstored, literals=lits,
                            matches=matches, maxlen=maxlen, maxdist=maxdist, stream_len=len(data),
                            minlen=(0 if matches==0 else minlen), has3_4=((3,4) in pairs),
                            has_dist1=(1 in dists), ndists=len(dists))

def zlib_decode_strict(data, expect_len):
    d = zlib.decompressobj()
    try:
        out = d.decompress(data)
        out += d.flush()
    except zlib.error as e:
        return None, 'ZLIB:' + str(e)
    if not d.eof: return None, 'E_TRUNCATED'
    if d.unused_data: return None, 'E_TRAILING_BYTES'
    if d.unconsumed_tail: return None, 'E_UNCONSUMED'
    if len(out) != expect_len: return None, 'E_LENGTH_MISMATCH'
    return out, 'OK'

def unpack_samples(buf, n):
    s=[]; i=0
    while len(s) < n:
        b0,b1,b2,b3,b4 = buf[i:i+5]; i+=5
        s += [(b0<<2)|(b4&3), (b1<<2)|((b4>>2)&3), (b2<<2)|((b4>>4)&3), (b3<<2)|((b4>>6)&3)]
    return s[:n]

def pack_samples(s):
    out=bytearray(); i=0
    while i < len(s):
        p0,p1,p2,p3 = s[i:i+4]; i+=4
        out += bytes([p0>>2,p1>>2,p2>>2,p3>>2,
                      (p0&3)|((p1&3)<<2)|((p2&3)<<4)|((p3&3)<<6)])
    return bytes(out)

def bayer_inverse(xform, w, h, pred_en):
    assert w%4==0 and h>=2 and len(xform)==w*5//4*h
    stride = w*5//4
    img = [[0]*w for _ in range(h)]
    off = 0
    for by in range((h+1)//2):
        y0=2*by; y1=y0+1 if y0+1<h else None
        rows = 2 if y1 is not None else 1
        ns = w*rows; nb = ns*5//4
        blk = xform[off:off+nb]; off += nb
        s = unpack_samples(blk, ns)
        assert len(s)==ns
        npl = w//2
        planes = []
        for pl in range(4 if rows==2 else 2):
            seq = s[pl*npl:(pl+1)*npl]
            if pred_en:
                acc=0; res=[]
                for dv in seq:
                    acc=(acc+dv)%1024; res.append(acc)
                seq=res
            planes.append(seq)
        for j in range(npl):
            img[y0][2*j]   = planes[0][j]
            img[y0][2*j+1] = planes[1][j]
            if rows==2:
                img[y1][2*j]   = planes[2][j]
                img[y1][2*j+1] = planes[3][j]
    flat=[p for row in img for p in row]
    return pack_samples(flat)

def load_hex(p):
    return bytes(int(x,16) for x in open(p).read().split())

def main():
    idx = json.load(open(os.path.join(P2,'cases','index.json'), encoding='utf-8'))
    rows=[]; failures=[]
    for c in idx['cases']:
        nm=c['name']
        outp=os.path.join(TR,'runs',nm,'out.hex')
        if not os.path.exists(outp):
            failures.append((nm,'NO_SIM_OUTPUT')); continue
        try: dut=load_hex(outp)
        except Exception as e:
            failures.append((nm,'OUT_PARSE:'+str(e))); continue
        xf=open(c['xform'],'rb').read()
        r = {}
        try:
            o,info = parse_zlib_stream(dut, len(xf))
            r['own']='OK' if o==xf else 'MISMATCH'
            r['info']=info
        except E as e:
            r['own']='ERR:'+e.code; r['info']={}
        zo, zc = zlib_decode_strict(dut, len(xf))
        r['zlib']= zc if zo is None else ('OK' if zo==xf else 'MISMATCH')
        r['out_bytes']=len(dut); r['xform_len']=len(xf)
        r['bayer']='n/a'; r['raw']='n/a'
        if ('raw' in c) and c.get('prep_en') is not None and c['w']>0:
            try:
                raw=open(c['raw'],'rb').read()
                if c['prep_en']==0:
                    inv = xf
                else:
                    inv = bayer_inverse(xf, c['w'], c['h'], c['pred_en'])
                r['bayer']='OK' if inv==raw else 'MISMATCH'
                r['raw']=hashlib.sha256(inv).hexdigest()[:12]
            except Exception as e:
                r['bayer']='ERR:'+str(e)
        ok = r['own']=='OK' and r['zlib']=='OK' and r['bayer'] in ('OK','n/a')
        rows.append((nm, r, ok))
        if not ok: failures.append((nm, r))
    print('=== POSITIVE CASES ===')
    for nm,r,ok in rows:
        inf=r.get('info',{})
        print(f"{nm:34s} {'PASS' if ok else 'FAIL'} zlib={r['zlib']:4s} own={r['own']:4s} bayer={r['bayer']:4s} "
              f"out={r['out_bytes']} xf={r['xform_len']} blocks={inf.get('blocks')} fix={inf.get('fixed')} sto={inf.get('stored')} "
              f"lit={inf.get('literals')} match={inf.get('matches')} maxlen={inf.get('maxlen')} maxdist={inf.get('maxdist')}")
    # boundary evidence
    try:
        _,i1 = parse_zlib_stream(load_hex(os.path.join(TR,'runs','p2_dist2048_len258','out.hex')),4800)
        _,i2 = parse_zlib_stream(load_hex(os.path.join(TR,'runs','p2_len3_dist4','out.hex')),4800)
        print('BOUNDARY dist2048_len258 maxlen/maxdist', i1['maxlen'], i1['maxdist'], 'minlen', i1['minlen'], 'ndists', i1['ndists'],
              '| len3_dist4 maxlen/maxdist', i2['maxlen'], i2['maxdist'], 'minlen', i2['minlen'], 'has(3,4)', i2['has3_4'], 'has_dist1', i2['has_dist1'])
    except Exception as e: print('BOUNDARY parse err', e)
    # negatives
    base = load_hex(os.path.join(TR,'runs','p2_frame_16x8','out.hex'))
    xf = open(os.path.join(P2,'cases','p2_frame_16x8.xform'),'rb').read()
    rand = load_hex(os.path.join(TR,'runs','p2_random_4800','out.hex'))
    xfr = open(os.path.join(P2,'cases','p2_random_4800.xform'),'rb').read()
    def expect_reject(name, data, expect_len, want=None, require_zlib=True):
        try:
            o,inf=parse_zlib_stream(data, expect_len); own='ACCEPTED'
        except E as e:
            own=e.code
        zo,zc=zlib_decode_strict(data, expect_len)
        zres='ACCEPTED' if zo is not None else zc
        ok = own!='ACCEPTED' and (zres!='ACCEPTED' or not require_zlib)
        if want: ok = ok and own==want
        print(f"NEG {name:28s} own={own:24s} zlib={zres:22s} {'PASS' if ok else 'FAIL'}")
        if not ok: failures.append((name, own, zres))
        return ok
    print('=== NEGATIVE / MUTATION ===')
    expect_reject('truncate_1B', base[:-1], len(xf), 'E_TRUNCATED')
    expect_reject('truncate_5B', base[:-5], len(xf), 'E_TRUNCATED')
    comp = load_hex(os.path.join(TR,'runs','p2_perf_1920x64_comp','out.hex'))
    expect_reject('truncate_mid_5000B', comp[:5000], 153600, 'E_TRUNCATED')
    bad_adler = base[:-1]+bytes([base[-1]^0x01])
    expect_reject('bad_adler', bad_adler, len(xf), 'E_BAD_ADLER')
    expect_reject('trailing_byte', base+b'\x00', len(xf), 'E_TRAILING_BYTES')
    expect_reject('bad_zlib_header', bytes([base[0], base[1]^0x01])+base[2:], len(xf), 'E_BAD_ZLIB_HEADER')
    dyn = bytes([0x78,0x9C,0x05,0,0,0,0,0,0,1])
    expect_reject('dynamic_btype', dyn, 0, 'E_BAD_BTYPE_DYNAMIC')
    res = bytes([0x78,0x9C,0x07,0,0,0,0,0,0,1])
    expect_reject('reserved_btype', res, 0, 'E_BAD_BTYPE_RESERVED')
    # stored NLEN corrupt: first block of random case is stored
    nl = bytearray(rand)
    # 2 zlib + 1 hdr byte; LEN at 3..4, NLEN 5..6
    assert nl[2] & 0x06 == 0, ('first block not stored?', hex(nl[2]))
    nl[5] ^= 0xFF
    expect_reject('bad_stored_nlen', bytes(nl), len(xfr), 'E_BAD_STORED_NLEN')
    # invalid fixed length symbol 286: craft code bits
    tab286 = None
    for (code,l),sym in TAB_LL.items():
        if sym==286: tab286=(code,l)
    def putbits(acc, val, n):
        for i in range(n-1,-1,-1): acc.append((val>>i)&1)
    bits=[]
    putbits(bits,1,1)  # BFINAL
    bits.append(1); bits.append(0)  # BTYPE=01, LSB-first bit order
    putbits(bits,tab286[0],tab286[1])
    by=bytearray()
    for i in range(0,len(bits),8):
        v=0
        for j,bit in enumerate(bits[i:i+8]): v|=bit<<j
        by.append(v)
    badlen = bytes([0x78,0x9C])+bytes(by)+b'\x00\x00\x00\x01'
    expect_reject('bad_length_code_286', badlen, 0, 'E_BAD_LENGTH_CODE')
    # strict-format-only negatives (zlib is more permissive; parser is the format gate)
    sym2code = {v:(k[0],k[1]) for k,v in TAB_LL.items()}
    def mkstream(bits, plain):
        while len(bits) % 8: bits.append(0)
        by=bytearray()
        for i in range(0,len(bits),8):
            v=0
            for j,bit in enumerate(bits[i:i+8]): v|=bit<<j
            by.append(v)
        a=1; bb=0
        for x in plain:
            a=(a+x)%65521; bb=(bb+a)%65521
        return bytes([0x78,0x9C])+bytes(by)+(((bb<<16)|a).to_bytes(4,'big'))
    # distance 2049 > 2048 window: 2049 literals + len3/dist2049
    bits=[]; bits.append(1); bits.append(1); bits.append(0)
    for _ in range(2049): putbits(bits, sym2code[65][0], sym2code[65][1])
    putbits(bits, sym2code[257][0], sym2code[257][1])
    putbits(bits, 22, 5); putbits(bits, 0, 10)
    putbits(bits, sym2code[256][0], sym2code[256][1])
    expect_reject('distance_2049_window', mkstream(bits, b'A'*2049), 2052, 'E_DISTANCE_WINDOW', require_zlib=False)
    # distance 32768 (zlib max) is outside the A+ 2048-byte window
    bits=[]; bits.append(1); bits.append(1); bits.append(0)
    for _ in range(32768): putbits(bits, sym2code[65][0], sym2code[65][1])
    putbits(bits, sym2code[257][0], sym2code[257][1])
    putbits(bits, 29, 5); putbits(bits, 8191, 13)
    putbits(bits, sym2code[256][0], sym2code[256][1])
    expect_reject('distance_32768_window', mkstream(bits, b'A'*32768), 32771, 'E_DISTANCE_WINDOW', require_zlib=False)
    # nonzero padding after final EOB: 1 literal + EOB = 3+8+7=18 bits; set bit23
    bits=[]; bits.append(1); bits.append(1); bits.append(0)
    putbits(bits, sym2code[65][0], sym2code[65][1])
    putbits(bits, sym2code[256][0], sym2code[256][1])
    while len(bits) % 8: bits.append(0)
    bits[23]=1
    expect_reject('bad_padding_tail', mkstream(bits, b'A'), 1, 'E_BAD_PADDING', require_zlib=False)
    print('=== SUMMARY ===')
    print('positive', sum(1 for _,_,ok in rows if ok), '/', len(rows), 'failures', len(failures))
    for f in failures[:20]: print(' FAIL', f)
    print('VERDICT', 'PASS' if not failures else 'FAIL')

if __name__=='__main__':
    main()

