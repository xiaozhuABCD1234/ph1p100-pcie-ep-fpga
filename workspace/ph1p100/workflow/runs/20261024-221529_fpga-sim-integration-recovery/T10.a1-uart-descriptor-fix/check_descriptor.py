"""Independent serialized-byte fixture and standard-library zlib/CRC oracle."""
import hashlib,json,pathlib,re,struct,zlib
HERE=pathlib.Path(__file__).resolve().parent

def check(folder,mode):
    folder=pathlib.Path(folder);log=(folder/'console.log').read_text(errors='replace')
    vectors=json.loads((HERE/'fixtures.json').read_text());errors=[];decoded=[]
    wanted={0:list(range(12)) if mode==2 else [0,1,2,5],1:[12,13]}
    def require(ok,msg):
        if not ok: raise AssertionError(msg)
    try:
        by_epoch={0:bytearray(),1:bytearray()}
        for line in (folder/'capture.tsv').read_text().splitlines():
            e,b=line.split();require(e in ('0','1'),'invalid epoch')
            require(b.isdigit() and 0<=int(b)<256,'X/non-byte token')
            by_epoch[int(e)].append(int(b))
        for epoch,indexes in wanted.items():
            data=bytes(by_epoch[epoch]);offset=0;seen=set()
            for index in indexes:
                v=vectors[index];raw=bytes.fromhex(v['raw_hex']);payload=bytes.fromhex(v['payload_hex'])
                require(len(data)-offset>=44,'missing/partial packet')
                hdr=data[offset:offset+44]
                fields=struct.unpack('<IBBHIHHIIIIIII',hdr)
                magic,ver,flags,hlen,fid,w,h,rl,xl,sl,rc,xc,sc,hc=fields
                require((magic,ver,flags,hlen,fid,w,h,rl,xl,sl)==(0x31553141,1,0,44,v['frame_id'],8,2,20,20,len(payload)),'header/order/epoch')
                pay=data[offset+44:offset+44+sl]
                require(pay==payload,'payload byte mismatch/truncation')
                dec=zlib.decompressobj();xf=dec.decompress(pay)+dec.flush()
                require(dec.eof and not dec.unused_data and not dec.unconsumed_tail,'strict zlib tail/end')
                require(xf==raw,'source byte mismatch')
                require(zlib.crc32(hdr[:40])&0xffffffff==hc,'header CRC')
                require(zlib.crc32(pay)&0xffffffff==sc,'stream CRC')
                require(zlib.crc32(xf)&0xffffffff==xc,'transform CRC')
                require(zlib.crc32(raw)&0xffffffff==rc,'raw CRC')
                require(fid not in seen,'duplicate ID');seen.add(fid)
                decoded.append(dict(epoch=epoch,index=index,frame_id=fid,strict_zlib=True,four_crc=True,bytes=44+sl))
                offset+=44+sl
            require(offset==len(data),'duplicate packet or tail garbage')
        require('DESCRIPTOR_PASS mode='+str(mode)+' mismatch=0' in log,'missing target PASS')
        require('Fatal' not in log and 'Errors: 0' in log,'DUT assertion/error')
        require('QUEUED_RESET epoch=0 queued=2' in (folder/'trace.txt').read_text(),'queued-reset trigger missing')
    except (AssertionError,ValueError,FileNotFoundError,zlib.error) as exc:
        errors.append(type(exc).__name__+': '+str(exc))
    return dict(status='PASS' if not errors else 'FAIL',mode=mode,errors=errors,packets=decoded,mismatch=0 if not errors else 1)
