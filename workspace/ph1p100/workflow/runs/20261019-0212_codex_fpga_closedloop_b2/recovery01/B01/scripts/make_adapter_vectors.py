import pathlib,sys,random,json,hashlib
sys.dont_write_bytecode=True
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');REC=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools/algo'));import oracle_algo as o
v=REC/'vectors';v.mkdir(exist_ok=True);W=16;H=6;r=random.Random(20261019)
raws=[[(x*11+y*37)&1023 for y in range(H) for x in range(W)],[r.randrange(1024) for _ in range(W*H)],[512 if x<12 else (y*81+x*3)&1023 for y in range(H) for x in range(W)]]
he=o.HeSeq();outputs=[[],[],[]];rawbeats=[]
for raw in raws:
    gy=o.grayscale(raw,W,H,3);ga=o.gaussian(gy,W,H);hh=he.frame(gy,True)
    rawbeats.extend(o.frame_beats(raw,W))
    for n,px in enumerate([gy,ga,hh]):outputs[n].extend(o.pack_y8(px[i:i+4]) for i in range(0,len(px),4))
for name,data,width in [('raw.hex',rawbeats,10),('gray.hex',outputs[0],8),('gauss.hex',outputs[1],8),('he.hex',outputs[2],8)]:
    (v/name).write_text(''.join(f'{x:0{width}x}\n' for x in data),encoding='ascii')
(v/'provenance.json').write_text(json.dumps({'oracle':str(ROOT/'tools/algo/oracle_algo.py'),'sha256':hashlib.sha256((ROOT/'tools/algo/oracle_algo.py').read_bytes()).hexdigest(),'W':W,'H':H,'phase':3,'frames':3,'independent_of_rtl':True},indent=2))
print('Independent varying-image adapter vectors generated: 3 frames x3 branches')
