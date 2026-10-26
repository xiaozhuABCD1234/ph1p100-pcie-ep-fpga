import json,os,re,sys,zlib,hashlib,struct
ev=r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\test-reports\evidence\T10.b2-a1-uart-impl-r3"
cases={"micro8x2":dict(cam_w=32,cam_h=4,roi_x=4,roi_y=2,w=8,h=2),
       "mid64x8":dict(cam_w=128,cam_h=16,roi_x=0,roi_y=0,w=64,h=8),
       "full_grad":dict(cam_w=3840,cam_h=2160,roi_x=960,roi_y=540,w=1920,h=1080)}
dev_sha={"micro8x2":("19ede2c945c3ba5ecd3d8b77c68bf40dd80168264434193c7c2258f6b32a3ee3","3f2b091437daea2af0562b10fb31c37ea8fa7a1fc49ed038130917302bde3480"),
 "mid64x8":("e991cd0de32ad52f88f8008a2def3fd8a85cec4fc352ca98986ee512438b0e47","b2022acbe13f161aa9baacb107196f7ecf70caa13c825d89b37521f73e773e54"),
 "full_grad":("2f34e2536590b891539604eea7a40f9f68fe3154e5b0b0ffa77d5656d355e830","eb845cc2c4428185e26421e48f716fc4efda0c566d5d2554e01363d68f7bff49")}
def smp(y,x): return (x*3+y*5+((x^y)&7)*17)&1023
def expected(g,order):
    out=bytearray()
    for py in range(g["h"]):
        y=g["roi_y"]+py
        for gx in range(g["w"]//4):
            s=[smp(y,g["roi_x"]+gx*4+i) for i in range(4)]
            msb=bytes([v>>2 for v in s]); lsb=(s[0]&3)|((s[1]&3)<<2)|((s[2]&3)<<4)|((s[3]&3)<<6)
            out+= (msb+bytes([lsb])) if order=="msb_first" else (bytes([lsb])+msb)
    return bytes(out)
def read_dec(p):
    b=bytearray()
    for ln in open(p):
        ln=ln.strip()
        if ln: b.append(int(ln)&0xFF)
    return bytes(b)
def find_zlib(buf):
    for o in range(0,min(len(buf),300)):
        if o+2>len(buf): break
        if buf[o]&0x0F==8 and ((buf[o]<<8)|buf[o+1])%31==0:
            try:
                d=zlib.decompressobj(); out=d.decompress(buf[o:]); out+=d.flush()
                if d.eof and len(out)>0: return o,out,len(buf[o:])-len(d.unused_data)
            except Exception: pass
    return None,None,None
res={"cases":{}}
for name,g in cases.items():
    buf=read_dec(os.path.join(ev,"captures",name+".dec"))
    off,inf,used=find_zlib(buf)
    r={"bytes_total":len(buf),"zlib_off":off,"inflated_len":None if inf is None else len(inf),"stream_consumed":used,
       "geometry":g,"expected_len":g["w"]*g["h"]*5//4,"head48":buf[:48].hex(),"tail8":buf[-8:].hex()}
    if inf is not None:
        r["inflated_sha256"]=hashlib.sha256(inf).hexdigest()
        r["stream_sha256"]=hashlib.sha256(buf[off:off+used]).hexdigest()
        r["raw_crc32"]="%08x"%(zlib.crc32(inf)&0xffffffff)
        r["stream_crc32"]="%08x"%(zlib.crc32(buf[off:off+used])&0xffffffff)
        r["dev_raw_sha_match"]= r["inflated_sha256"]==dev_sha[name][0]
        r["dev_stream_sha_match"]= r["stream_sha256"]==dev_sha[name][1]
        for order in ("msb_first","lsb_first"):
            exp=expected(g,order)
            if len(exp)==len(inf):
                diff=sum(1 for a,b in zip(exp,inf) if a!=b)+abs(len(exp)-len(inf))
                r["mismatch_"+order]=diff
            else: r["mismatch_"+order]="len %d vs %d"%(len(exp),len(inf))
        # negative control: deliberately wrong reference must fail
        wr=bytearray(expected(g,"msb_first")); wr[0]^=0x55
        r["negctl_mismatch"]=sum(1 for a,b in zip(wr,inf) if a!=b) if len(wr)==len(inf) else "len"
        # locate raw CRC field in framing region (header 0:off and trailer)
        want=struct.pack("<I",zlib.crc32(inf)&0xffffffff)
        r["raw_crc_in_header"]= buf[:off].find(want)
        r["raw_crc_in_tail"]= buf[off+used:].find(want)
        # header CRC brute force: crc32(head[0:k]) == LE32 at k
        hdr=buf[:off]; hc=[]
        for k in range(4,len(hdr)-3):
            v=struct.unpack("<I",hdr[k:k+4])[0]
            if (zlib.crc32(hdr[:k])&0xffffffff)==v: hc.append(k)
        r["header_crc_field_offsets"]=hc
        st_crc=[]
        for k in range(4,len(hdr)-3):
            v=struct.unpack("<I",hdr[k:k+4])[0]
            if (zlib.crc32(buf[off:off+used])&0xffffffff)==v: st_crc.append(k)
        r["stream_crc_field_offsets"]=st_crc
    res["cases"][name]=r
json.dump(res,open(os.path.join(ev,"independent_check.json"),"w"),indent=1)
for k,v in res["cases"].items():
    print(k, {kk:vv for kk,vv in v.items() if kk not in ("head48","geometry")})
