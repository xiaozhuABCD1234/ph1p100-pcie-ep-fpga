import json,os,sys,zlib
root=sys.argv[1]; run=sys.argv[2]
sys.path.insert(0,os.path.join(root,'tools','a1'))
from a1_pattern import expected_raw
from pc_decode import decode_stream, read_bytes, WORST_CASE_EXPANSION
cases=[('micro8x2',dict(cam_w=32,cam_h=4,roi_x=4,roi_y=2,w=8,h=2),1),
       ('mid64x8',dict(cam_w=128,cam_h=16,roi_x=0,roi_y=0,w=64,h=8),32),
       ('full_grad',dict(cam_w=3840,cam_h=2160,roi_x=960,roi_y=540,w=1920,h=1080),129600)]
def stats(p):
    d={}
    for line in open(p):
        if line.startswith('STAT'):
            for tok in line.split()[1:]:
                k,v=tok.split('='); d[k]=int(v)
    return d
out={'cases':[]}
for name,geom,words in cases:
    cap=os.path.join(run,'captures',name+'.dec'); st=stats(os.path.join(run,'captures',name+'.stats'))
    data=read_bytes(cap); dec=os.path.join(run,'decoded',name); frames,tail=decode_stream(data,dec)
    exp=expected_raw(0,geom); rec={'name':name,'frames':len(frames),'trailing':tail,'stats':st,'fails':[]}
    if tail!=0: rec['fails'].append('trailing=%d'%tail)
    if len(frames)!=1: rec['fails'].append('frames=%d'%len(frames))
    for f in frames:
        fi={k:f[k] for k in ('frame_id','width','height','raw_len','xform_len','stream_len','prep','pred','zlib_ok','header_crc_ok','stream_crc_ok','xform_crc_ok','raw_crc_ok','worstcase_ok','raw_sha256','stream_sha256')}
        rec['frame']=fi
        for k in ('zlib_ok','header_crc_ok','stream_crc_ok','xform_crc_ok','raw_crc_ok','worstcase_ok'):
            if not f[k]: rec['fails'].append(k)
        if f['width']!=geom['w'] or f['height']!=geom['h']: rec['fails'].append('geom')
        if f['raw_len']!=len(exp): rec['fails'].append('raw_len=%d'%f['raw_len'])
        if f['stream_len']>WORST_CASE_EXPANSION: rec['fails'].append('stream_len')
        got=open(os.path.join(f['dir'],'raw.bin'),'rb').read()
        if got!=exp:
            n=sum(1 for a,b in zip(got,exp) if a!=b)+abs(len(got)-len(exp)); rec['fails'].append('mismatch=%d'%n)
    if st.get('exported')!=1: rec['fails'].append('exported')
    for k,v in (('geom',0),('err',0),('dup_words',0),('raw_drop',0),('cmp_drop',0)):
        if st.get(k)!=v: rec['fails'].append('%s=%s'%(k,st.get(k)))
    if st.get('read_words')!=words: rec['fails'].append('read_words=%s'%st.get('read_words'))
    rec['verdict']='PASS' if not rec['fails'] else 'FAIL'
    out['cases'].append(rec)
out['verdict']='PASS' if all(c['verdict']=='PASS' for c in out['cases']) else 'FAIL'
json.dump(out,open(os.path.join(run,'p1_regression.json'),'w'),indent=1)
for c in out['cases']: print(c['name'],c['verdict'],c.get('fails'),c.get('frame',{}).get('stream_len'),c.get('frame',{}).get('raw_sha256','')[:16])
print('VERDICT',out['verdict'])
