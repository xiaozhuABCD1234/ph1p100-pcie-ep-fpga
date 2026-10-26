from pathlib import Path
import json,hashlib,sys,re,subprocess
sys.path.insert(0,r'D:\fpga\ph1p100\workflow\runs\20261025-180900_fpga-dual-offline-closure\test-reports\T08.dual-local-closure')
from tester_control import D,E,command,T,sha,save
# Verify upstream inputs separately from development's source claims.
m=json.loads((D.parent/'planning-input-manifest.json').read_text(encoding='utf-8-sig')); print('PLANNING_MANIFEST_KEYS',list(m))
print('NEGATIVE',json.loads((E/'negative-result.json').read_text())['negative_rejected'])
for exe,arg,log in [(T/'vsim.exe','-version','vsim-version.log'),(Path(sys.executable),'--version','python-version.log')]:print(command([exe,arg],E,E/log,60))
W,H=1920,1080;raw=W*H*5//4;content=raw+128;dma=(content+4095)//4096*4096
bases=[0x100000,0x900000,0x1100000,0x1900000]
assert (raw,content,dma)==(2592000,2592128,2592768)
assert all(b+dma<=b+8*1024*1024 and b+8*1024*1024<2**29 and b%4096==0 for b in bases)
assert all(bases[i]+8*1024*1024<=bases[i+1] for i in range(3))
# Enumerate default read bursts, checking exact byte coverage and every 4KiB boundary.
last=[]
for b in bases:
 addr=b;left=dma;bursts=[]
 while left:
  n=min(left//32,128,(4096-(addr%4096))//32);assert n>0 and n<=128 and addr//4096==(addr+n*32-1)//4096
  bursts.append((addr,n));addr+=n*32;left-=n*32
 assert addr==b+dma;last.append(dict(base=b,beats=dma//32,bursts=len(bursts),last=bursts[-1],end=addr))
save(E/'tester-default-boundary.json',dict(W=W,H=H,raw=raw,content=content,dma=dma,slot_bytes=8388608,bases=bases,reads=last,raw_MBps_1080p30_dual=155.52,write_read_min_MBps=311.04,physical_throughput='not_run'))
