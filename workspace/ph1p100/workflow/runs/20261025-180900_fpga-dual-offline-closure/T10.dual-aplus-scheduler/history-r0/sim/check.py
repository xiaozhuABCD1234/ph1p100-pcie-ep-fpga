"""Strict standard-zlib decoder plus independent packed sample formula."""
import csv,json,pathlib,zlib,sys,hashlib
sys.dont_write_bytecode=True
def inverse_xform(data,prep,pred,w,h):
 samples=[]
 for k in range(0,len(data),5):
  b=data[k:k+5];assert len(b)==5
  samples.extend((b[j]<<2)|((b[4]>>(2*j))&3) for j in range(4))
 if not prep:return bytes(data)
 raster=[0]*(w*h);pos=0
 for by in range(0,h,2):
  for plane in range(4 if by+1<h else 2):
   prev=0
   for x in range(w//2):
    v=samples[pos];pos+=1
    if pred and x:v=(v+prev)&1023
    prev=v;raster[(by+plane//2)*w+x*2+plane%2]=v
 assert pos==len(samples),'unexpected transformed tail'
 result=bytearray()
 for k in range(0,len(raster),4):
  a=raster[k:k+4];result.extend(v>>2 for v in a);result.append(sum((v&3)<<(2*j) for j,v in enumerate(a)))
 return bytes(result)
def raw(w,h,cam,seq):
 out=bytearray()
 for y in range(h):
  for x in range(0,w,4):
   a=[(cam*211+seq*73+(x+k)*3+y*17+(((x+k)^y)&7)*29)&1023 for k in range(4)]
   out.extend([v>>2 for v in a]);out.append(sum((v&3)<<(2*k) for k,v in enumerate(a)))
 return bytes(out)
def verify(case,w,h,expected):
 fields='camera slot epoch session seq raw_len xform_len stream_len raw_crc xform_crc stream_crc prep pred'.split();results=[]
 for row in csv.reader((case/'metadata.csv').open()):
  m=dict(zip(fields,map(int,row)));stream=(case/f"c{m['camera']}_q{m['seq']}.zlib").read_bytes()
  d=zlib.decompressobj();xf=d.decompress(stream)+d.flush()
  assert d.eof and not d.unused_data and not d.unconsumed_tail,'strict EOF'
  restored=inverse_xform(xf,m['prep'],m['pred'],w,h)
  assert restored==raw(w,h,m['camera'],m['seq']),'packed pattern mismatch'
  for label,data in [('raw',restored),('xform',xf),('stream',stream)]:
   assert len(data)==m[label+'_len'],label+' length';assert zlib.crc32(data)&0xffffffff==m[label+'_crc'],label+' CRC'
  assert len(stream)<=w*h*5//4+5*((h+1)//2)+6,'worst stored capacity'
  results.append(dict(**m,raw_sha256=hashlib.sha256(restored).hexdigest()))
 assert len(results)==expected,(len(results),expected)
 r=dict(status='local_check_pass',frames=len(results),decoded=results,eof=True,unused_data=0,unconsumed_tail=0)
 (case/'checker.json').write_text(json.dumps(r,indent=2));return r
if __name__=='__main__':print(json.dumps(verify(pathlib.Path(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3]),int(sys.argv[4]))))
