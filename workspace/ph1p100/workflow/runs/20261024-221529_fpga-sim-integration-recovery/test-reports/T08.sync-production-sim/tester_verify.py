"""Independent round0 test driver; writes only its own report evidence directory."""
from pathlib import Path
import argparse, collections, copy, hashlib, json, runpy, struct, sys, time

E = Path(__file__).resolve().parent
R = E.parent.parent
T = R / 'T08.sync-production-sim'
M = T / 'manifest-r0.json'

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def save(name, obj):
    (E / name).write_text(json.dumps(obj, indent=2), encoding='utf-8')

def audit(label):
    m = json.loads(M.read_text(encoding='utf-8'))
    rows = []
    groups = {'manifest_files':m['files'], 'control_inputs':m['planning_control_inputs'],
              'tool_executables':m['tools']['executables']}
    pm = json.loads((R/'planning-input-manifest.json').read_text(encoding='utf-8'))
    groups['protected_frozen_inputs'] = [{'path':x['frozen'], 'sha256':x['sha256']} for x in pm['files']]
    for group, entries in groups.items():
        for entry in entries:
            p = Path(entry['path']); actual = sha(p) if p.is_file() else None
            rows.append({'group':group,'path':str(p),'expected':entry['sha256'],
                         'actual':actual,'same':actual == entry['sha256']})
    candidate = {str(p.resolve()) for p in (T/'candidate').rglob('*') if p.is_file()}
    listed = {str(Path(x['path']).resolve()) for x in m['files']}
    unlisted = sorted(candidate-listed)
    out = {'label':label,'manifest_path':str(M),'manifest_sha256':sha(M),
           'counts':{g:len(es) for g,es in groups.items()},'unlisted_candidate_files':unlisted,
           'drift_count':sum(not x['same'] for x in rows), 'entries':rows,
           'stopped_modifying':m['stopped_modifying'],'active_commands':m['active_commands']}
    save('audit-'+label+'.json',out)
    assert out['drift_count']==0 and not unlisted, 'input drift or unlisted candidate file'
    assert m['stopped_modifying'] and m['active_commands']==0
    if label=='post':
        before=json.loads((E/'audit-pre.json').read_text())
        assert out['manifest_sha256']==before['manifest_sha256'], 'manifest drift'
    print(json.dumps({k:v for k,v in out.items() if k!='entries'}))

def crc_bitwise(data):
    c=0xffffffff
    for b in data:
        c ^= b
        for _ in range(8):
            c=(c>>1) ^ (0xedb88320 if c&1 else 0)
    return c ^ 0xffffffff

def inspect_frame(blob,cam,source_id):
    assert len(blob)==4096, 'independent DMA allocation length'
    assert blob[:4]==b'R10F', 'independent magic'
    w=struct.unpack('<32I',blob[:128])
    assert w[2]&0xffff==128 and w[2]>>16==cam, 'independent source ID/header size'
    assert w[7]&0xffff==8 and w[7]>>16==2, 'independent geometry'
    assert w[11]==w[12]==20, 'independent payload byte count'
    payload=blob[128:148]
    # Infer source frame from captured bytes instead of trusting the PUB fid tag.
    inferred=((payload[0]-cam*97)*197)&255  # 197 is inverse of 13 modulo 256.
    assert inferred in (10,11,12) and inferred==source_id, 'independent source-frame inference'
    for row in range(2):
        base=(cam*97+inferred*13+row*23)&255
        line=payload[row*10:row*10+10]
        assert all((line[k]-base)&255==7*k for k in range(10)), 'independent row byte progression'
    assert w[20]==w[21]==crc_bitwise(payload), 'independent bitwise payload CRC'
    header=bytearray(blob[:128]);header[88:92]=b'\0'*4
    assert w[22]==crc_bitwise(header), 'independent bitwise header CRC'
    assert not any(blob[148:]), 'independent padding'
    return {'camera':cam,'source_frame':inferred,'crc':f'{w[20]:08x}'}

def inspect_transactions(events,pins,case):
    reqs=[x for x in events if x[0]=='REQ']; rsps=[x for x in events if x[0]=='RSP']
    cancelled_ep=int(next(x[1] for x in events if x[0]=='PENDING_RESET_HIT')) if case==5 else None
    done=0
    for req in reqs:
        ep,t,cam=int(req[1]),int(req[2]),int(req[3])
        if ep==cancelled_ep:
            assert not any(int(x[1])==ep for x in rsps), 'cancelled epoch received response'
            continue
        candidates=[x for x in rsps if int(x[1])==ep and int(x[2])>t]
        assert candidates, 'independent missing response'
        rsp=min(candidates,key=lambda x:int(x[2])); end=int(rsp[2])
        assert int(rsp[3])==cam, 'independent response camera mismatch'
        matches=[p for p in pins if p['epoch']==ep and p['camera']==cam and t<p['time']<end]
        assert len(matches)==1, 'independent request-pin-response correspondence'
        pin=matches[0]
        assert pin['word']==(0x34<<24 | int(req[4],16)<<8 | int(req[5],16)), 'independent latched bytes'
        assert int(rsp[4])==int(pin['ack']==15), 'independent ACK response mismatch'
        assert not any(int(q[1])==ep and t<int(q[2])<end for q in reqs), 'independent one outstanding request'
        done+=1
    return done

def independent(out,case):
    events=[x.split() for x in (out/'events.log').read_text().splitlines()]
    epochs=[(int(x[1]),int(x[2])) for x in events if x[0]=='EPOCH']
    pins=[]
    for cam,name in enumerate(('i2c_a.log','i2c_b.log')):
        for line in (out/name).read_text().splitlines():
            x=line.split()
            if x[0]=='TX':
                t=int(x[1]);ep=max(e for e,et in epochs if et<=t)
                pins.append({'epoch':ep,'camera':cam,'time':t,'word':int(x[3],16),'ack':int(x[4],16)})
    n=inspect_transactions(events,pins,case)
    frames=[]
    for x in events:
        if x[0]=='PUB':
            cam,seq,source_id=int(x[3]),int(x[4]),int(x[7])
            blob=bytes.fromhex((out/f'frame_{cam}_{seq}.hex').read_text())
            frames.append(inspect_frame(blob,cam,source_id))
    want=12 if case==4 else 6
    assert len(frames)==want, 'independent exact complete publication count'
    # Self-check sensitivity using a changed response camera and swapped A/B frame bytes.
    corrupt=copy.deepcopy(events)
    rsp=next(x for x in corrupt if x[0]=='RSP');rsp[3]=str(1-int(rsp[3]))
    rejected=[]
    try:inspect_transactions(corrupt,pins,case)
    except AssertionError as ex:rejected.append(str(ex))
    else:raise AssertionError('response-camera negative control escaped')
    a=bytes.fromhex((out/'frame_0_1.hex').read_text())
    try:inspect_frame(a,1,10)
    except AssertionError as ex:rejected.append(str(ex))
    else:raise AssertionError('A/B swap negative control escaped')
    result={'pass':True,'case':case,'checked_transactions':n,'checked_frames':len(frames),
            'frames':frames,'negative_controls_rejected':rejected}
    (out/'tester-independent.json').write_text(json.dumps(result,indent=2))
    return result

def main():
    p=argparse.ArgumentParser();p.add_argument('action',choices=['pre','post','compile','case'])
    p.add_argument('--case',type=int);p.add_argument('--mutate',action='store_true');a=p.parse_args()
    if a.action in ('pre','post'):return audit(a.action)
    runner=runpy.run_path(str(T/'run_t08.py'))
    if a.action=='compile':
        runner['compile_candidate'](E/'build')
        listed=json.loads(M.read_text())['compile_sources']
        actual=json.loads((E/'build/sources.json').read_text())
        result={'same_sources':set(listed)==set(actual),'source_count':len(actual),
                'unexpected':sorted(set(actual)-set(listed)),'missing':sorted(set(listed)-set(actual))}
        save('compile-binding.json',result);assert result['same_sources'];print(json.dumps(result));return
    names=['clean','nack','missing','global-reset','restart','pending-reset']
    out=E/('role-mutation' if a.mutate else names[a.case])
    sim=runner['run_case'](E/'build',out,a.case,a.mutate)
    assert sim['sim_pass'] and not sim['timeout'], 'simulation failed'
    checker=runpy.run_path(str(T/'check_t08.py'))
    try:oracle=checker['check_case'](out,a.case)
    except (AssertionError,ValueError,KeyError,StopIteration) as ex:oracle={'pass':False,'reason':str(ex)}
    (out/'oracle-result.json').write_text(json.dumps(oracle,indent=2))
    if a.mutate:
        assert not oracle['pass'] and oracle['reason']=='ordered 14 role writes and six cleanup writes'
        print(json.dumps({'case':'role-mutation','simulation_completed':True,'target_assertion_rejected':True}));return
    assert oracle['pass'],oracle
    extra=independent(out,a.case)
    print(json.dumps({'case':a.case,'sim_pass':True,'oracle_pass':True,'tester_independent':extra}))

if __name__=='__main__':main()
