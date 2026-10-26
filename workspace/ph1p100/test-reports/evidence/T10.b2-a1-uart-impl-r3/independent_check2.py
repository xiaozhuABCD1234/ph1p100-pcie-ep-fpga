import json,os,zlib,hashlib,struct
ev=r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道\test-reports\evidence\T10.b2-a1-uart-impl-r3"
cases={"micro8x2":dict(cam_w=32,cam_h=4,roi_x=4,roi_y=2,w=8,h=2),
       "mid64x8":dict(cam_w=128,cam_h=16,roi_x=0,roi_y=0,w=64,h=8),
       "full_grad":dict(cam_w=3840,cam_h=2160,roi_x=960,roi_y=540,w=1920,h=1080)}
devinfo={"micro8x2":("19ede2c945c3ba5ecd3d8b77c68bf40dd80168264434193c7c2258f6b32a3ee3",19),
 "mid64x8":("e991cd0de32ad52f88f8008a2def3fd8a85cec4fc352ca98986ee512438b0e47",106),
 "full_grad":("2f34e2536590b891539604eea7a40f9f68fe3154e5b0b0ffa77d5656d355e830",40032)}
def smp(y,x): return (x*3+y*5+((x^y)&7)*17)&1023
def expected(g,order="msb_first"):
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
    for o in range(0,300):
        if buf[o]&0x0F==8 and ((buf[o]<<8)|buf[o+1])%31==0:
            d=zlib.decompressobj(); out=d.decompress(buf[o:]); out+=d.flush()
            if d.eof and out: return o,out,len(buf[o:])-len(d.unused_data)
    return None,None,None
def inv(xf,rb,mode):
    raw=bytearray(len(xf)); n=len(xf)//rb
    for r in range(n):
        for i in range(rb):
            p=r*rb+i
            a=raw[p-1] if i>0 else 0
            b=raw[p-rb] if r>0 else 0
            c=raw[p-rb-1] if (r>0 and i>0) else 0
            if mode=="left": pr=a
            elif mode=="up": pr=b
            else:
                pp=a+b-c; pa=abs(pp-a); pb=abs(pp-b); pc=abs(pp-c)
                pr=a if (pa<=pb and pa<=pc) else (b if pb<=pc else c)
            raw[p]=(xf[p]+pr)&0xFF
    return bytes(raw)
res={}
for name,g in cases.items():
    buf=read_dec(os.path.join(ev,"captures",name+".dec")); off,inf,used=find_zlib(buf)
    hdr=buf[:off]; rb=g["w"]*5//4
    r={"header_len":off,"stream_len":used,"hdr_le32":[struct.unpack("<I",hdr[i:i+4])[0] for i in range(0,28,4)],
       "crc_slot32":"%08x"%(struct.unpack("<I",hdr[32:36])[0]),"crc_slot36":"%08x"%(struct.unpack("<I",hdr[36:40])[0]),
       "crc_slot40":"%08x"%(struct.unpack("<I",hdr[40:44])[0]),
       "crc_xform":"%08x"%(zlib.crc32(inf)&0xffffffff),"crc_stream":"%08x"%(zlib.crc32(buf[off:off+used])&0xffffffff),
       "crc_header0_40":"%08x"%(zlib.crc32(hdr[:40])&0xffffffff)}
    exp=expected(g,"msb_first"); exl=expected(g,"lsb_first")
    for mode in ("left","up","paeth"):
        raw=inv(inf,rb,mode)
        r["mm_"+mode]={"msb":sum(1 for a,b in zip(raw,exp) if a!=b),"lsb":sum(1 for a,b in zip(raw,exl) if a!=b),
                       "len":len(raw),"sha":hashlib.sha256(raw).hexdigest()[:16],
                       "raw_crc":"%08x"%(zlib.crc32(raw)&0xffffffff)}
    # the expected raw under msb_first: does its crc appear anywhere in header?
    want=struct.pack("<I",zlib.crc32(exp)&0xffffffff)
    r["expected_raw_crc"]="%08x"%(zlib.crc32(exp)&0xffffffff); r["expected_raw_crc_in_header"]=hdr.find(want)
    r["dev_raw_sha_match"]=(r["mm_left"]["sha"]==devinfo[name][0][:16])
    r["manifest_stream_len_match"]=(used==devinfo[name][1])
    res[name]=r
json.dump(res,open(os.path.join(ev,"independent_check2.json"),"w"),indent=1)
for k,v in res.items(): print(k,json.dumps(v))
