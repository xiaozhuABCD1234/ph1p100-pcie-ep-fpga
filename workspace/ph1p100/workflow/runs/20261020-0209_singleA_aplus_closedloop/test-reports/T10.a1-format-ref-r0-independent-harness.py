# Independent integrated test for T10.a1-format-ref (does not import a1_ref / a1_inflate_strict)
import json, zlib, struct, binascii, hashlib, sys, os
from pathlib import Path

VD = Path(r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-format-ref\p1\vectors")
DOC = json.loads((VD / "vectors.json").read_text(encoding="utf-8"))

class E(Exception):
    def __init__(self, code, detail=""):
        self.code = code; self.detail = detail
        super().__init__(code + (": " + detail if detail else ""))

LEN_BASE = (3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258)
LEN_EXTRA = (0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0)
DIST_BASE = (1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577)
DIST_EXTRA = (0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13)

def revbits(v, n):
    r = 0
    for _ in range(n):
        r = (r << 1) | (v & 1); v >>= 1
    return r

def canon(lengths):
    mb = max(lengths); cnt = [0]*(mb+1)
    for l in lengths:
        if l: cnt[l] += 1
    code = 0; nxt = [0]*(mb+1)
    for b in range(1, mb+1):
        code = (code + cnt[b-1]) << 1; nxt[b] = code
    tab = {}
    for s, l in enumerate(lengths):
        if l:
            tab[(l, revbits(nxt[l], l))] = s; nxt[l] += 1
    return tab, mb

LIT_TAB, LIT_MAX = canon([8]*144 + [9]*112 + [7]*24 + [8]*8)
DST_TAB, DST_MAX = canon([5]*32)

class Reader:
    def __init__(self, data):
        self.d = data; self.p = 0; self.n = len(data)*8
    def bits(self, k):
        if k == 0: return 0
        if self.p + k > self.n: raise E("E_TRUNCATED", "bits")
        v = 0
        for i in range(k):
            v |= ((self.d[(self.p+i) >> 3] >> ((self.p+i) & 7)) & 1) << i
        self.p += k
        return v
    def align_zero(self):
        pad = (-self.p) & 7
        if pad and self.bits(pad) != 0: raise E("E_BAD_PADDING", "pad")
    def bytes(self, k):
        if self.p & 7: raise AssertionError("align")
        if self.p + 8*k > self.n: raise E("E_TRUNCATED", "bytes")
        b = self.p >> 3; self.p += 8*k
        return self.d[b:b+k]

def dsym(r, tab, mb):
    v = 0
    for l in range(1, mb+1):
        v |= r.bits(1) << (l-1)
        s = tab.get((l, v))
        if s is not None: return s
    raise E("E_INVALID_HUFFMAN_CODE", "huff")

def decode_stream(data, expected_len=None, max_out=64*1024*1024):
    r = Reader(data)
    cmf = r.bits(8); flg = r.bits(8)
    if (cmf & 0x0F) != 8 or (cmf >> 4) > 7: raise E("E_BAD_ZLIB_HEADER", "CM")
    if ((cmf << 8) | flg) % 31: raise E("E_BAD_ZLIB_HEADER", "FCHECK")
    if flg & 0x20: raise E("E_FDICT_SET", "FDICT")
    if cmf != 0x78 or flg != 0x9C: raise E("E_BAD_ZLIB_HEADER", "non-frozen CMF/FLG")
    out = bytearray(); blocks = []
    while True:
        start = r.p
        bfinal = r.bits(1); btype = r.bits(2)
        bi = {"start_bit": start, "btype": btype, "out_start": len(out)}
        if btype == 0:
            r.align_zero()
            ln = r.bits(16); nlen = r.bits(16)
            if (ln ^ 0xFFFF) != nlen: raise E("E_BAD_STORED_NLEN", "LEN=%d" % ln)
            if ln > 4800: raise E("E_BAD_STORED_LEN", "LEN=%d" % ln)
            out += r.bytes(ln); bi.update(stored_len=ln, nlit=0, nmatch=0)
        elif btype == 1:
            nlit = nmatch = 0; lens = []; dsts = []
            while True:
                s = dsym(r, LIT_TAB, LIT_MAX)
                if s < 256:
                    out.append(s); nlit += 1
                    if len(out) > max_out: raise E("E_OUTPUT_LIMIT")
                    continue
                if s == 256: break
                if s > 285: raise E("E_BAD_LENGTH_CODE", "sym=%d" % s)
                k = s - 257; ln = LEN_BASE[k]; eb = LEN_EXTRA[k]
                if eb: ln += r.bits(eb)
                d = dsym(r, DST_TAB, DST_MAX)
                if d > 29: raise E("E_BAD_DISTANCE_CODE", "dsym=%d" % d)
                dist = DIST_BASE[d]; eb = DIST_EXTRA[d]
                if eb: dist += r.bits(eb)
                if dist > 2048: raise E("E_DISTANCE_WINDOW", "dist=%d" % dist)
                if dist > len(out): raise E("E_BAD_DISTANCE", "dist=%d out=%d" % (dist, len(out)))
                for _ in range(ln):
                    out.append(out[-dist])
                nmatch += 1; lens.append(ln); dsts.append(dist)
                if len(out) > max_out: raise E("E_OUTPUT_LIMIT")
            bi.update(nlit=nlit, nmatch=nmatch, lengths=lens, dists=dsts)
        elif btype == 2:
            raise E("E_BAD_BTYPE_DYNAMIC", "btype2")
        else:
            raise E("E_BAD_BTYPE_RESERVED", "btype3")
        bi.update(out_end=len(out), out_len=len(out)-bi["out_start"], bfinal=bfinal, end_bit=r.p)
        blocks.append(bi)
        if bfinal: break
        if len(blocks) > 100000: raise E("E_OUTPUT_LIMIT", "blocks")
    r.align_zero()
    adler = int.from_bytes(r.bytes(4), "big")
    if r.p != r.n: raise E("E_TRAILING_BYTES", "pos=%d n=%d" % (r.p, r.n))
    calc = zlib.adler32(bytes(out)) & 0xFFFFFFFF
    if adler != calc: raise E("E_BAD_ADLER", "%08X != %08X" % (adler, calc))
    if expected_len is not None and len(out) != expected_len:
        raise E("E_LENGTH_MISMATCH", "%d != %d" % (len(out), expected_len))
    return bytes(out), {"blocks": blocks, "adler": adler, "final_pad": (-blocks[-1]["out_end"]) and 0}

def zlib_exact(data):
    d = zlib.decompressobj(); out = d.decompress(data); out += d.flush()
    if not d.eof: raise E("ZLIB_INCOMPLETE")
    if d.unused_data: raise E("ZLIB_UNUSED_DATA")
    if d.unconsumed_tail: raise E("ZLIB_UNCONSUMED")
    return out

# independent packed RAW10
def unpack(buf):
    if len(buf) % 5: raise E("E_BAD_RAW_LEN")
    s = []
    for o in range(0, len(buf), 5):
        b0,b1,b2,b3,b4 = buf[o:o+5]
        s += [(b0<<2)|(b4&3), (b1<<2)|((b4>>2)&3), (b2<<2)|((b4>>4)&3), (b3<<2)|((b4>>6)&3)]
    return s

def pack(samples):
    if len(samples) % 4: raise E("E_BAD_XFORM_LEN")
    out = bytearray()
    for i in range(0, len(samples), 4):
        p0,p1,p2,p3 = samples[i:i+4]
        out += bytes([p0>>2, p1>>2, p2>>2, p3>>2,
                      ((p3&3)<<6)|((p2&3)<<4)|((p1&3)<<2)|(p0&3)])
    return bytes(out)

def validate_geom(w,h,prep,pred):
    if w < 4 or w % 4: raise E("E_BAD_GEOMETRY", "W")
    if h < 2: raise E("E_BAD_GEOMETRY", "H")
    if pred and not prep: raise E("E_BAD_GEOMETRY", "pred")
    return w*5//4

def bayer_fwd(raw,w,h,prep,pred):
    stride = validate_geom(w,h,prep,pred)
    if not prep: return bytes(raw)
    out = bytearray(); y = 0
    while y < h:
        nr = 2 if y+1 < h else 1
        blk = raw[y*stride:(y+nr)*stride]
        rows = [unpack(blk[r*stride:(r+1)*stride]) for r in range(nr)]
        planes = [rows[0][0::2], rows[0][1::2]]
        if nr == 2: planes += [rows[1][0::2], rows[1][1::2]]
        seq = []
        for p in planes:
            prev = 0
            for s in p:
                seq.append(((s - prev) & 0x3FF) if pred else s); prev = s
        out += pack(seq); y += nr
    return bytes(out)

def bayer_inv(xf,w,h,prep,pred):
    stride = validate_geom(w,h,prep,pred)
    if not prep: return bytes(xf)
    out = bytearray(); y = 0
    while y < h:
        nr = 2 if y+1 < h else 1
        blk = xf[y*stride:(y+nr)*stride]
        seq = unpack(blk); np = 4 if nr == 2 else 2; plen = w//2
        if len(seq) != np*plen: raise E("E_BAD_XFORM_LEN", "samples")
        planes = []
        for k in range(np):
            p = seq[k*plen:(k+1)*plen]
            if pred:
                acc = 0; q = []
                for d in p:
                    acc = (acc+d) & 0x3FF; q.append(acc)
                p = q
            planes.append(p)
        rows = [[0]*w for _ in range(nr)]
        rows[0][0::2] = planes[0]; rows[0][1::2] = planes[1]
        if nr == 2: rows[1][0::2] = planes[2]; rows[1][1::2] = planes[3]
        for row in rows: out += pack(row)
        y += nr
    return bytes(out)

def rec_check(rec,w,h):
    if len(rec) < 32: return "E_RECORD_TRUNCATED"
    magic, ver, flags, raw_len, xf_len, sl, raw_crc, xf_crc, hcrc = struct.unpack_from("<4sHHIIIIII", rec, 0)
    if magic != b"A1T1": return "E_BAD_MAGIC"
    if ver != 1: return "E_BAD_VERSION"
    if flags & ~0x3: return "E_BAD_FLAGS"
    if (binascii.crc32(rec[:0x1C]) & 0xFFFFFFFF) != hcrc: return "E_BAD_HEADER_CRC"
    try: stride = validate_geom(w,h,flags&1,(flags>>1)&1)
    except E as e: return e.code
    if raw_len != stride*h: return "E_BAD_RAW_LEN"
    if xf_len != raw_len: return "E_BAD_XFORM_LEN"
    if len(rec) != 32+sl: return "E_STREAM_LEN_MISMATCH"
    try: xf, _ = decode_stream(rec[32:], expected_len=xf_len)
    except E as e: return e.code
    if (binascii.crc32(xf) & 0xFFFFFFFF) != xf_crc: return "E_BAD_XFORM_CRC"
    try: raw = bayer_inv(xf,w,h,flags&1,(flags>>1)&1)
    except E as e: return e.code
    if (binascii.crc32(raw) & 0xFFFFFFFF) != raw_crc: return "E_BAD_RAW_CRC"
    return None

def sha(b): return hashlib.sha256(b).hexdigest()

fails = []; notes = []
pos_ok = 0; neg_ok = 0

for p in DOC["positives"]:
    name = p["name"]
    try:
        if p["kind"] == "frame":
            raw = (VD/p["files"]["raw"]).read_bytes()
            xf = (VD/p["files"]["xform"]).read_bytes()
            stream = (VD/p["files"]["stream"]).read_bytes()
            rec = (VD/p["files"]["record"]).read_bytes()
            assert sha(raw)==p["sha256"]["raw"] and sha(xf)==p["sha256"]["xform"]
            assert sha(stream)==p["sha256"]["stream"] and sha(rec)==p["sha256"]["record"]
            w,h,prep,pred = p["w"],p["h"],p["prep_en"],p["pred_en"]
            zout = zlib_exact(stream)
            dout, meta = decode_stream(stream, expected_len=len(xf))
            if zout != xf: raise AssertionError("zlib output != .xform")
            if dout != xf: raise AssertionError("own decoder != .xform")
            myxf = bayer_fwd(raw,w,h,prep,pred)
            if myxf != xf: raise AssertionError("independent forward transform != .xform")
            myraw = bayer_inv(zout,w,h,prep,pred)
            if myraw != raw: raise AssertionError("independent inverse != .raw")
            # sample-level mismatch
            sa, sb = unpack(raw), unpack(myraw)
            mism = sum(1 for a,b in zip(sa,sb) if a!=b)
            if mism: raise AssertionError("sample mismatch=%d" % mism)
            # record fields
            magic,ver,flags,rl,xl,sl,rc,xc,hc = struct.unpack_from("<4sHHIIIIII", rec, 0)
            assert magic==b"A1T1" and ver==1 and flags==(prep|(pred<<1))
            assert (rl,xl,sl)==(len(raw),len(xf),len(stream))
            assert (rc,xc)==(binascii.crc32(raw)&0xFFFFFFFF, binascii.crc32(xf)&0xFFFFFFFF)
            assert (binascii.crc32(rec[:0x1C])&0xFFFFFFFF)==hc
            assert rec[32:]==stream and len(rec)==32+len(stream)
            # block structure
            blocks = meta["blocks"]
            if len(blocks) != p["block_count"]: raise AssertionError("block count %d != %d" % (len(blocks), p["block_count"]))
            nfix = sum(1 for b in blocks if b["btype"]==1); nsto = sum(1 for b in blocks if b["btype"]==0)
            if nfix != p["fixed_blocks"] or nsto != p["stored_blocks"]:
                raise AssertionError("block types %d/%d != %d/%d" % (nfix,nsto,p["fixed_blocks"],p["stored_blocks"]))
            # per-block expected sizes (2*stride, tail stride)
            stride = w*5//4; exp_sizes = []
            yy=0
            while yy<h:
                nr=2 if yy+1<h else 1; exp_sizes.append(stride*nr); yy+=nr
            got_sizes=[b["out_len"] for b in blocks]
            if got_sizes != exp_sizes: raise AssertionError("block sizes %s != %s" % (got_sizes[:6],exp_sizes[:6]))
            if any(b["btype"]==1 and (b["nlit"]+b["nmatch"])==0 for b in blocks):
                raise AssertionError("empty fixed block")
            if any(b["btype"]==0 and b["stored_len"]>4800 for b in blocks):
                raise AssertionError("stored >4800")
            if blocks[-1]["bfinal"] != 1: raise AssertionError("last not final")
            if sum(1 for b in blocks if b["bfinal"]) != 1: raise AssertionError("multiple final")
            if (blocks[-1]["end_bit"] % 8) != p["tail_bit_offset"]:
                raise AssertionError("tail bit offset %d != %d" % (blocks[-1]["end_bit"] % 8, p["tail_bit_offset"]))
            if meta["adler"] != (zlib.adler32(xf)&0xFFFFFFFF): raise AssertionError("adler")
            if "max_match_len" in p and nsto == 0:
                ml = max([max(b.get("lengths") or [0]) for b in blocks] or [0])
                md = max([max(b.get("dists") or [0]) for b in blocks] or [0])
                if ml != p["max_match_len"] or md != p["max_match_dist"]:
                    raise AssertionError("max len/dist %d/%d != %d/%d" % (ml,md,p["max_match_len"],p["max_match_dist"]))
            if "literal_count" in p and nsto == 0:
                tl = sum(b.get("nlit",0) for b in blocks); tm = sum(b.get("nmatch",0) for b in blocks)
                if (tl,tm) != (p["literal_count"],p["match_count"]):
                    raise AssertionError("token counts %d/%d != %d/%d" % (tl,tm,p["literal_count"],p["match_count"]))
            pos_ok += 1
            print("POS OK %-40s %dx%d prep=%d pred=%d blocks=%d fixed=%d stored=%d mismatch=0 stream=%d"
                  % (name,w,h,prep,pred,len(blocks),nfix,nsto,len(stream)))
        else:
            stream=(VD/p["files"]["stream"]).read_bytes(); exp=(VD/p["files"]["out"]).read_bytes()
            assert sha(stream)==p["sha256"]["stream"] and sha(exp)==p["sha256"]["out"]
            zout=zlib_exact(stream); dout,meta=decode_stream(stream, expected_len=len(exp))
            if zout!=exp or dout!=exp: raise AssertionError("boundary output mismatch")
            if len(meta["blocks"])!=1 or meta["blocks"][0]["btype"]!=1: raise AssertionError("boundary block type")
            b = meta["blocks"][0]
            lens = set(b["lengths"]); dists = set(b["dists"])
            if not ({3,258} <= lens): raise AssertionError("length boundary missing: %s" % sorted(lens))
            if not ({1,2048} <= dists): raise AssertionError("distance boundary missing: %s" % sorted(dists))
            if b["nlit"] < 2048: raise AssertionError("literal run <2048")
            pos_ok += 1
            print("POS OK %-40s stream-only out=%d blocks=%d lit=%d match=%d len{%s} dist{%s} maxlen=%d maxdist=%d"
                  % (name,len(exp),len(meta["blocks"]),b["nlit"],b["nmatch"],sorted(lens),sorted(dists),max(b["lengths"]),max(b["dists"])))
    except Exception as e:
        fails.append((name, "%s: %s" % (type(e).__name__, e)))
        print("POS FAIL", name, type(e).__name__, e)

for n in DOC["negatives"]:
    name=n["name"]; data=(VD/n["file"]).read_bytes()
    try:
        assert sha(data)==n["sha256"]
        if n["kind"]=="stream":
            try: decode_stream(data); actual="ACCEPTED"
            except E as e: actual=e.code
            try: zlib_exact(data); zl="ok"
            except E as e: zl=e.code
            except zlib.error as e: zl="error"
            ok = actual==n["expected_reason"]
            if n.get("zlib_expectation")=="must_fail": ok = ok and zl in ("error","ZLIB_INCOMPLETE","ZLIB_UNUSED_DATA")
            if n.get("zlib_expectation")=="unused_data": ok = ok and zl=="ZLIB_UNUSED_DATA"
        else:
            actual=rec_check(data,n["w"],n["h"]); ok = actual==n["expected_reason"]; zl="n/a"
        if ok: neg_ok+=1; print("NEG OK   %-32s expected=%-22s actual=%-22s zlib=%s" % (name,n["expected_reason"],actual,zl))
        else:
            fails.append((name,"expected %s actual %s zlib %s" % (n["expected_reason"],actual,zl)))
            print("NEG FAIL %-32s expected=%-22s actual=%-22s zlib=%s" % (name,n["expected_reason"],actual,zl))
    except Exception as e:
        fails.append((name,"%s: %s" % (type(e).__name__,e))); print("NEG EXC",name,e)

print("SUMMARY positives=%d/%d negatives=%d/%d failures=%d" % (pos_ok,len(DOC["positives"]),neg_ok,len(DOC["negatives"]),len(fails)))
if fails:
    for f in fails: print("FAILITEM",f)
    sys.exit(1)
print("INDEPENDENT_PASS mismatch=0")
