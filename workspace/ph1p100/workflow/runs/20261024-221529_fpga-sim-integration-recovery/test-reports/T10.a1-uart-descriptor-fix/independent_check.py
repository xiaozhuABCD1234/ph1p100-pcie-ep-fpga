"""Independent bitwise CRC, forward RAW transform, UART pin and packet oracle.

No imports of developer checker, expected-vector module, or RTL implementation.
"""
import collections, hashlib, json, pathlib, re, struct, sys, zlib
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent
DEV=HERE.parent.parent/'T10.a1-uart-descriptor-fix'

def demand(ok,reason):
    if not ok: raise AssertionError(reason)

def crc(data):
    c=0xffffffff
    for b in data:
        c^=b
        for _ in range(8): c=(c>>1) ^ (0xedb88320 if c&1 else 0)
    return c ^ 0xffffffff

def pack10(row):
    result=bytearray()
    for x in range(0,len(row),4):
        q=row[x:x+4]
        result.extend(v//4 for v in q)
        result.append(sum((v%4)<<(2*i) for i,v in enumerate(q)))
    return bytes(result)

def source(seed):
    state=0x12345678 ^ seed; rows=[]
    for y in range(4):
        row=[]
        for g in range(4):
            for shift,left in [(13,True),(17,False),(5,True)]:
                state=(state ^ ((state<<shift) if left else (state>>shift))) & 0xffffffff
            row.extend((state>>s)&1023 for s in [0,10,20,22])
        if y>=2: rows.append(row[4:12])
    raw=b''.join(pack10(row) for row in rows)
    xf=bytearray()
    for row in rows:
        for parity in [0,1]:
            samples=row[parity::2]
            delta=[samples[0]]+[(samples[i]-samples[i-1])%1024 for i in range(1,len(samples))]
            xf+=pack10(delta)
    return raw,bytes(xf)

def fixture(fid):
    return bytes(((fid*7+13*x) ^ x**2)%256 for x in range(20))

def parse(data, expected, flags):
    offset=0; result=[]
    for fid,raw,xf,payload_exact in expected:
        demand(len(data)-offset>=44,'missing/partial header')
        header=data[offset:offset+44]
        magic,ver,f,hlen,got_id,w,h,rl,xl,sl,rc,xc,sc,hc=struct.unpack('<IBBHIHHIIIIIII',header)
        demand((magic,ver,f,hlen,got_id,w,h,rl,xl)==(0x31553141,1,flags,44,fid,8,2,20,20),'header/order/epoch/geometry')
        demand(0<sl<=84,'stream length bound')
        payload=data[offset+44:offset+44+sl]
        demand(len(payload)==sl,'truncated payload')
        demand(crc(header[:40])==hc,'header CRC')
        demand(crc(payload)==sc,'stream CRC')
        decoder=zlib.decompressobj()
        decoded=decoder.decompress(payload)+decoder.flush()
        demand(decoder.eof and decoder.unused_data==b'' and decoder.unconsumed_tail==b'','strict zlib end/tail')
        demand(len(decoded)==xl and crc(decoded)==xc,'transform CRC/length')
        demand(decoded==xf,'independent forward transform/source bytes')
        demand(crc(raw)==rc,'raw CRC/source identity')
        if payload_exact is not None: demand(payload==payload_exact,'serialized payload bytes')
        result.append(dict(frame_id=fid,bytes=44+sl,raw_sha256=hashlib.sha256(raw).hexdigest(),transform_sha256=hashlib.sha256(xf).hexdigest(),wire_packet_sha256=hashlib.sha256(data[offset:offset+44+sl]).hexdigest(),crc_header=hc,crc_stream=sc,crc_transform=xc,crc_raw=rc,strict_zlib=True))
        offset+=44+sl
    demand(offset==len(data),'duplicate packet/tail garbage')
    demand(len({r['frame_id'] for r in result})==len(result),'duplicate ID')
    return result

def read_tagged(path):
    result={0:bytearray(),1:bytearray()}
    for line in path.read_text().splitlines():
        cols=line.split(); demand(len(cols)==2 and all(x.isdecimal() for x in cols),'X/non-decimal wire byte')
        e,b=map(int,cols); demand(e in result and 0<=b<256,'epoch/byte range')
        result[e].append(b)
    return {k:bytes(v) for k,v in result.items()}

def stats(folder):
    return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',(folder/'stats.txt').read_text().splitlines()[0])}

def trace_check(folder, indexes):
    queue=collections.deque(); offered=0;rejected=0;popped=[];transition_events=collections.Counter()
    reset=False
    for line in (folder/'trace.txt').read_text().splitlines():
        d={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
        if line.startswith('QUEUED_RESET '):
            demand(d['queued']==2 and list(queue)==[15,16] and d['active_index']==14,'reset pending queue identity')
            queue.clear();reset=True;continue
        if not line.startswith('EVENT '): continue
        demand(len(queue)==d['count'],'independent trace occupancy')
        transition_events[(d['count'],d['request'],d['pop'])]+=1
        demand(d['accepted_push']==int(d['request'] and d['count']<2),'old-count admission policy')
        if d['pop']:
            demand(queue and queue.popleft()==d['active_index'],'independent FIFO order')
            popped.append(d['active_index'])
        if d['accepted_push']: queue.append(d['offered_index']);offered+=1
        if d['request'] and not d['accepted_push']: rejected+=1
        demand(len(queue)==d['next_count'],'independent next occupancy')
    demand(reset and not queue,'queued reset/empty final')
    demand(popped==indexes+[14,12,13],'trace descriptor sequence including withdrawn active')
    s=stats(folder)
    demand((s['accepted'],s['rejected'],s['popped'],s['resets'],s['epoch'],s['final_exported'],s['final_errors'],s['queued'])==(offered,rejected,len(popped),1,1,2,0,0),'transition/counter accounting')
    coverage={int(k):int(v) for k,v in re.findall(r'COV bin=(\d+) hits=(\d+)',(folder/'stats.txt').read_text())}
    if folder.name=='boundaries':
        demand(all(coverage[b]>0 for b in [0,2,4,5,6,7,8,9,10,11]),'all ten frozen legal transitions')
        demand(coverage[1]==coverage[3]==0,'empty pop impossible')
        demand(rejected==2 and transition_events[(2,1,1)]>0 and transition_events[(2,1,0)]>0,'full reject with/without pop')
    return dict(statistics=s,coverage=coverage,event_tuples={str(k):v for k,v in transition_events.items()},popped_indexes=popped)

def descriptor(case):
    out=HERE/'corrected'/case
    expected_indexes=list(range(12)) if case=='wrap' else [0,1,2,5]
    raw_data=read_tagged(out/'capture.tsv'); serial=read_tagged(out/'wire.tsv')
    demand(serial==raw_data,'physical UART/debug byte mismatch')
    vectors=json.loads((DEV/'fixtures.json').read_text())
    all_desc=[bytes.fromhex(x)[::-1] for x in (DEV/'descriptors.hex').read_text().split()]
    all_payload=[bytes.fromhex(x)[::-1] for x in (DEV/'payloads.hex').read_text().split()]
    for i,v in enumerate(vectors):
        fid=v['frame_id'];raw=fixture(fid);payload=bytes.fromhex(v['payload_hex'])
        demand(raw.hex()==v['raw_hex'],'fixture source construction')
        demand(crc(raw)==v['raw_crc'] and crc(payload)==v['stream_crc'],'fixture CRC')
        demand(all_desc[i]==struct.pack('<8I',fid,20,20,len(payload),crc(raw),crc(raw),crc(payload),0),'fixture descriptor source bytes')
        demand(all_payload[i]==payload.ljust(32,b'\0'),'fixture store words')
    decoded={}
    for epoch,indexes in {0:expected_indexes,1:[12,13]}.items():
        expected=[(vectors[i]['frame_id'],fixture(vectors[i]['frame_id']),fixture(vectors[i]['frame_id']),bytes.fromhex(vectors[i]['payload_hex'])) for i in indexes]
        decoded[epoch]=parse(serial[epoch],expected,0)
    result=dict(status='PASS',mismatch=0,packets=sum(len(d) for d in decoded.values()),bytes=sum(len(d) for d in serial.values()),wire_matches_debug=True,decoded=decoded,queue=trace_check(out,expected_indexes))
    (out/'independent-result.json').write_text(json.dumps(result,indent=2))
    return result

def full():
    out=HERE/'corrected/full-clean';s=stats(out)
    tokens=(out/'capture.dec').read_text().split()
    demand(all(x.isdecimal() and 0<=int(x)<256 for x in tokens),'full capture X/non-byte')
    data=bytes(map(int,tokens));serial=read_tagged(out/'wire.tsv')
    demand(serial[0]==data and not serial[1],'full physical UART/debug mismatch')
    expected=[(i+1,*source(1000+i),None) for i in range(4)]
    decoded=parse(serial[0],expected,3)
    demand(all(s[k]==4 for k in ['good_sent','recovered','cap','enc','exported','raw_pub']),'four complete clean frames/counters')
    zero=['raw_drop','cmp_drop','geom','err','dup_words','old_r_count','fifo_rejected','fifo_full','abort_seen','fault_geom','fault_rawdrop','fault_cmpdrop','fault_err','epoch']
    demand(all(s[k]==0 for k in zero),'clean error/drop/epoch')
    demand(s['bytes']==len(data)==292 and s['aw']==s['wbeats']==8 and s['raw_aw']==s['cmp_aw']==s['read_words']==4,'DDR/byte accounting')
    demand(s['recovery_elapsed']<=1000000,'full bounded completion')
    trace=(out/'trace.txt').read_text()
    source_lines=[line for line in trace.splitlines() if line.startswith('SOURCE ')]
    demand(len(source_lines)==4 and all('epoch=0 bad=0' in line for line in source_lines),'clean source count/epoch')
    result=dict(status='PASS',packets=len(decoded),bytes=len(data),wire_matches_debug=True,independent_forward_transform=True,decoded=decoded,stats=s)
    (out/'independent-result.json').write_text(json.dumps(result,indent=2))
    return result

def checker_negatives():
    v=json.loads((DEV/'fixtures.json').read_text())[0]
    payload=bytes.fromhex(v['payload_hex']);raw=fixture(1001)
    base=bytearray(struct.pack('<IBBHIHHIIIIIII',0x31553141,1,0,44,1001,8,2,20,20,len(payload),crc(raw),crc(raw),crc(payload),0)+payload)
    def seal(b): b[40:44]=struct.pack('<I',crc(b[:40]));return bytes(b)
    base=seal(base);expected=[(1001,raw,raw,None)]
    demand(len(parse(base,expected,0))==1,'negative source baseline')
    tests=[]
    def reject(name,data,want=expected):
        try: parse(data,want,0)
        except (AssertionError,zlib.error) as e: tests.append(dict(name=name,rejected=True,reason=str(e)));return
        raise AssertionError('ineffective checker negative '+name)
    reject('tail byte',base+b'\x55')
    reject('duplicate packet',base+base)
    for field,offset in [('header CRC',40),('stream CRC',36),('transform CRC',32),('raw CRC',28)]:
        b=bytearray(base);b[offset]^=1
        reject(field,bytes(b) if offset==40 else seal(b))
    b=bytearray(base);b+=payload;b[24:28]=struct.pack('<I',len(payload)*2);b[36:40]=struct.pack('<I',crc(bytes(b[44:])));reject('valid concatenated zlib stream',seal(b))
    b=bytearray(base);b[8:12]=struct.pack('<I',2001)
    reject('CRC-valid old source relabeled as new epoch',seal(b),[(2001,fixture(2001),fixture(2001),None)])
    reject('partial packet',base[:-1])
    (HERE/'checker-negatives.json').write_text(json.dumps(tests,indent=2))
    return tests

if __name__=='__main__':
    result=dict(task_id='T10.a1-uart-descriptor-fix',round=0,python=sys.version,zlib=zlib.ZLIB_VERSION,crc_oracle='independent reflected bitwise CRC-32',descriptor_boundaries=descriptor('boundaries'),descriptor_wrap=descriptor('wrap'),full_clean=full(),checker_negatives=checker_negatives())
    (HERE/'independent-results.json').write_text(json.dumps(result,indent=2))
    print('INDEPENDENT_BYTES_PASS',[(k,result[k]['packets'],result[k]['bytes']) for k in ['descriptor_boundaries','descriptor_wrap','full_clean']], 'negative_checks='+str(len(result['checker_negatives'])))
