import sys, pathlib, json, math, itertools, importlib.util, struct, zlib, hashlib, csv, xml.etree.ElementTree as ET
sys.dont_write_bytecode=True
ROOT=pathlib.Path('D:/fpga/ph1p100'); RUN=ROOT/'workflow/runs/20261026-144617_fpga-chain-detail-review'; PKG=RUN/'T10.chain-transform-review'; OUT=RUN/'test-reports/T10.chain-transform-review'; BASE=RUN/'baseline/snapshot'
def load(n,p):
    s=importlib.util.spec_from_file_location(n,p); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
def js(p): return json.loads(pathlib.Path(p).read_text(encoding='utf-8-sig'))
def save(n,x): (OUT/n).write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
def sha(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
sys.path.insert(0,str(PKG/'inputs'))
consumer=load('actual_pc',BASE/'0054.py'); pattern=sys.modules['a1_pattern']
def pack(samples):
    b=bytearray()
    for j in range(0,len(samples),4):
        q=samples[j:j+4]; assert len(q)==4
        b.extend(x//4 for x in q); b.append(sum((x%4)<<(2*i) for i,x in enumerate(q)))
    return bytes(b)
def unpack(b):
    return [((b[j+i]<<2)|((b[j+4]>>(2*i))&3)) for j in range(0,len(b),5) for i in range(4)]
def transform(rows,prep,pred):
    w=len(rows[0]); out=[]
    for y in range(0,len(rows),2):
        ys=list(range(y,min(y+2,len(rows))))
        coords=[(yy,x) for yy in ys for parity in range(2) for x in range(parity,w,2)] if prep else [(yy,x) for yy in ys for x in range(w)]
        prev=None
        for yy,x in coords:
            anchor=(x<2) if prep else (x==0)
            value=rows[yy][x]
            out.append(value if not(prep and pred) or anchor else (value-prev)%1024)
            prev=value
    return pack(out)
def independent_inverse(b,w,h,prep,pred):
    q=iter(unpack(b)); rows=[[0]*w for _ in range(h)]
    for y in range(0,h,2):
        for yy in range(y,min(y+2,h)):
            for parity in (range(2) if prep else [None]):
                prev=0
                for x in (range(parity,w,2) if prep else range(w)):
                    d=next(q); v=(prev+d)%1024 if prep and pred and x>=2 else d
                    rows[yy][x]=v; prev=v
    assert next(q,None) is None
    return pack([v for row in rows for v in row])
geometry=[]
for w,h,prep,pred in itertools.product(range(4,33,4),range(2,6),range(2),range(2)):
    if pred and not prep: continue
    rows=[[(x*173+y*419+x*y*31+7)%1024 for x in range(w)] for y in range(h)]
    raw=pack(sum(rows,[])); xf=transform(rows,prep,pred)
    assert len(xf)==len(raw) and independent_inverse(xf,w,h,prep,pred)==raw
    try:
        got=pattern.inverse_xform(xf,prep,pred,w,h); outcome='equal' if got==raw else 'wrong_pixels'
    except Exception as e: outcome=type(e).__name__
    consumer_samples=(w//8)*16*((h+1)//2)
    expected='equal' if not prep or (w%8==0 and h%2==0) else ('IndexError' if consumer_samples>w*h else 'wrong_pixels')
    assert outcome==expected,(w,h,prep,pred,outcome,expected)
    geometry.append({'w':w,'h':h,'prep':prep,'pred':pred,'consumer':outcome,'oracle_roundtrip':True})
save('independent-geometry.json',geometry)
# Abstract timing check uses source-derived combinational expressions and a separately stated abort-priority oracle.
frame=(BASE/'0146.v').read_text()
assert 'assign frame_commit = svalid && out_ready && slast && !killed;' in frame
assert '!(svalid && out_ready && slast && !killed)) begin' in frame
timing=[]
for ready,cancel,restart,killed in itertools.product(range(2),repeat=4):
    commit=bool(ready and not killed); abort_branch=bool((cancel or restart) and not commit)
    expected=bool(ready and not killed and not cancel and not restart)
    timing.append({'svalid':1,'slast':1,'frame_active':1,'ready':ready,'abort':cancel,'repeat_sof':restart,'killed':killed,'actual_commit':commit,'abort_branch':abort_branch,'abort_priority_oracle':expected,'matches':commit==expected})
assert sum(not t['matches'] for t in timing)==3
save('independent-cancel-timing.json',{'all_final_word_cases':timing,'earlier_abort_before_ready':'kill is set before final handshake, then commit=0','same_edge_abort_and_ready':'commit=1 and abort branch suppressed','qualification':'static event model, no cycle-accurate RTL or top-level reachability claim'})
# Capacity: dynamic program over all exact starting bit offsets; all allowed fixed costs form a conservative superset.
def stored(off,n): return 3+(-(off+3)%8)+32+8*n
states={0:0}
for block in range(540):
    nxt={}
    for off,total in states.items():
        costs=range(1,stored(off,4800)+1)
        # Only top 8 costs matter: same residue with smaller cost cannot increase any future maximum.
        for cost in range(stored(off,4800)-7,stored(off,4800)+1):
            t=total+cost; o=t%8; nxt[o]=max(nxt.get(o,-1),t)
    states=nxt
ideal=math.ceil(max(states.values())/8)+6
assert ideal==2594706 and math.ceil(ideal/4)*4==2594708
off_pairs=[]
for consumed,pending in itertools.product(range(8),repeat=2):
    actual=(consumed+pending)%8
    calc=stored(consumed,32); real=stored(actual,32)
    if calc>real:
        off_pairs.append({'consumed':consumed,'pending_bits_mod8':pending,'actual':actual,'estimated_cost':calc,'actual_stored_cost':real,'allowed_fixed_cost':calc-1})
assert any(x['allowed_fixed_cost']>x['actual_stored_cost'] for x in off_pairs)
save('independent-capacity.json',{'dp_blocks':540,'dp_offset_states':states,'ideal_bound':ideal,'output32_align':math.ceil(ideal/4)*4,'CMP_slot_bytes':81085*32,'ideal_spare':81085*32-ideal,'offset_agnostic_upper_bound':2592000+math.ceil(42*540/8)+6,'mismatched_offset_counterstates':off_pairs,'RTL_reachability':'not_proven; gap classification retained'})
def adler(b):
    a=1; c=0
    for x in b: a=(a+x)%65521; c=(c+a)%65521
    return c<<16|a
def envelope(raw,payload):
    h=struct.pack('<IBBHIHHIIIIII',0x31553141,1,0,44,73,8,2,len(raw),len(raw),len(payload),zlib.crc32(raw),zlib.crc32(raw),zlib.crc32(payload))
    return h+struct.pack('<I',zlib.crc32(h))+payload
def stored_parser(payload):
    assert len(payload)>=11 and payload[:2]==b'\x78\x9c','header'
    assert payload[2]==1,'A+ v1 zero header alignment and one final stored block'
    n,nn=struct.unpack('<HH',payload[3:7]); assert n<=4800 and n^nn==65535,'LEN/NLEN'
    assert len(payload)==11+n,'exact one member with no trailing bytes'
    data=payload[7:7+n]; assert adler(data)==int.from_bytes(payload[7+n:],'big'),'Adler'
    return data
raw=pack([(j*277+19)%1024 for j in range(16)])
payload=b'\x78\x9c\x01'+struct.pack('<HH',len(raw),len(raw)^65535)+raw+adler(raw).to_bytes(4,'big')
cases={'valid':payload,'extra_zero':payload+b'\0','nonzero_stored_padding':payload[:2]+bytes([payload[2]|8])+payload[3:],'bad_adler':payload[:-1]+bytes([payload[-1]^1])}
dec=[]
for name,p in cases.items():
    framed=envelope(raw,p); (OUT/(name+'.a1u')).write_bytes(framed)
    frames,tail=consumer.decode_stream(framed,write=False); f=frames[0]; flags={k:v for k,v in f.items() if k.endswith('_ok')}
    try: assert stored_parser(p)==raw; independent='accepted'
    except AssertionError as e: independent='rejected: '+str(e)
    d=zlib.decompressobj()
    try: d.decompress(p); unused=d.unused_data.hex()
    except zlib.error: unused='zlib_rejected'
    dec.append({'case':name,'consumer_all_checks':tail==0 and all(flags.values()),'consumer_checks':flags,'independent_stored_parser':independent,'zlib_unused_data':unused})
assert dec[0]['consumer_all_checks'] and dec[0]['independent_stored_parser']=='accepted'
assert all(x['consumer_all_checks'] and x['independent_stored_parser'].startswith('rejected') for x in dec[1:3])
assert not dec[3]['consumer_all_checks']
save('independent-streams.json',dec)
# Current compile entry and candidate binding; do not touch original candidates.
basemap={f['source_relative'].replace('\\','/'):f for f in js(RUN/'baseline/source-manifest.json')['files']}
compile_paths=[e.attrib['Path'] for e in ET.fromstring((BASE/'0155.al').read_bytes()).iter('File')]
checks=[]
for p in compile_paths:
    rel=p[3:] if p.startswith('Y:/') else None
    checks.append({'path':p,'snapshot_exists':rel in basemap})
assert all(x['snapshot_exists'] for x in checks),[x for x in checks if not x['snapshot_exists']]
assert not any(any(s in p for s in ['gray8','img_algo','rgb8_gray','rice','bpr1']) for p in compile_paths)
source_checks=[]
for sid,s in js(PKG/'source-map.json')['sources'].items():
    assert sha(s['snapshot_path'])==s['sha256']; source_checks.append(sid)
old=js(BASE/'0141.json'); bound=js(PKG/'candidate-binding.json')['b15_selected_changed_src_sha256']
old_hashes=set(old['changed_src_sha256'].values())
assert all(x in old_hashes for x in bound.values())
save('independent-sources.json',{'compile_paths':checks,'mapped_source_ids':source_checks,'selected_codec_source_binding':bound,'candidate_manifest_sha256':sha(BASE/'0141.json')})
table=list(csv.DictReader((BASE/'0277.csv').open(encoding='utf-8-sig',newline='')))
throughput=[]
for row in table[:4]:
    capacity=2592000*187500000/float(row['S_ss'])/1000000
    assert abs(capacity-float(row['capacity_MBps']))<1e-8
    throughput.append({'row':row['row'],'capacity_MBps':capacity,'S_ss':row['S_ss'],'L_cold':row['L_cold'],'sink_limited':row['sink_limited'],'qualification':row['G0']})
arith={'gray_max':255*(77+150+29)+128,'gaussian_max':255*16+8,'HE_max_pixels':2048*2048,'HE_max_CDF_times255':2048*2048*255,'HE_nonconstant_LUT_cycles_only':14*256,'tag_wrap_blocks':1<<16,'tag_wrap_frames':(1<<16)/540,'tag_wrap_seconds_30fps':(1<<16)/540/30,'RAW_per_stream_MBps':2592000*30/1e6,'Aplus_ideal_per_stream_MBps':ideal*30/1e6,'Aplus_ideal_dual_MBps':ideal*60/1e6,'cycles_per_frame_at_187_5MHz':187500000/30,'P4_rows':throughput}
assert arith['gray_max']==65408 and arith['gaussian_max']==4088
save('independent-arithmetic.json',arith)
print(json.dumps({'geometry_cases':len(geometry),'consumer_geometry_failures':sum(x['consumer']!='equal' for x in geometry),'cancel_priority_mismatches':sum(not x['matches'] for x in timing),'ideal_bound':ideal,'stream_cases':dec,'compile_paths':len(checks),'mapped_sources':len(source_checks)},ensure_ascii=True))
print('T10_INDEPENDENT_SEMANTICS_COMPLETE')
