"""Targeted tool checks; every generated pixel is a synthetic_control."""
import copy
import hashlib
import json
from pathlib import Path
import random
import struct
import sys
sys.dont_write_bytecode = True
import benchmark as b

HERE = Path(__file__).resolve().parent

def main():
    out = HERE / 'local' / (sys.argv[1] if len(sys.argv)>1 else 'controls')
    if not out.resolve().is_relative_to(HERE):raise ValueError('output outside task package')
    out.mkdir(parents=True, exist_ok=False)
    raw_values = [0, 1, 2, 3, 255, 256, 511, 1023] * 10
    raw = b.pack10(raw_values)
    (out / 'packed.raw10').write_bytes(raw)
    (out / 'little.u16').write_bytes(struct.pack('<80H', *raw_values))
    (out / 'big.u16').write_bytes(struct.pack('>80H', *(v << 6 for v in raw_values)))
    rng = random.Random(410)
    noise = b.pack10([rng.randrange(1024) for _ in range(128 * 5)])
    (out / 'noise.raw10').write_bytes(noise)
    (out / 'flat.raw10').write_bytes(b.pack10([17] * 80))
    def sample(name, fmt='packed_raw10', **extra):
        p = out / name
        s = {'sample_id':name.replace('.', '_'), 'category':'synthetic_control',
             'path':str(p), 'sha256':b.sha(p.read_bytes()), 'format':fmt,
             'width':16, 'height':5, 'stride':20 if fmt=='packed_raw10' else 32,
             'roi':{'x':0,'y':0,'width':16,'height':5,'source_width':16,'source_height':5},
             'bayer_phase':'unknown','phase_evidence':'not asserted; synthetic control',
             'normalized_raw_sha256':b.sha(raw),
             'provenance':{'source_kind':'synthetic_generator','source':'verify_controls.py deterministic samples',
                           'device':'none, generated','captured_at':'not captured',
                           'license_basis':'project-generated controls','format_basis':'explicit test vector',
                           'sensor_pixel_oracle_verified':False}, 'content_id':name}
        s.update(extra)
        return s
    baseline = sample('packed.raw10')
    le = sample('little.u16', 'u16', normalization={'byte_order':'little','valid_bits':10,'right_shift':0})
    be = sample('big.u16', 'u16', normalization={'byte_order':'big','valid_bits':10,'right_shift':6})
    ns = sample('noise.raw10', width=128, stride=160, normalized_raw_sha256=b.sha(noise),
                roi={'x':0,'y':0,'width':128,'height':5,'source_width':128,'source_height':5})
    flat = sample('flat.raw10', normalized_raw_sha256=b.sha((out/'flat.raw10').read_bytes()))
    cfg = {'schema_version':1, 'mode':{'prep':0,'pred':0}, 'samples':[baseline,le,be,ns,flat]}
    (out/'synthetic-inputs.json').write_text(json.dumps(cfg,indent=2)+'\n',encoding='utf-8')
    checks = []
    def check(name, condition):
        if not condition: raise AssertionError(name)
        checks.append({'check':name,'result':'pass'})
    for s in (baseline,le,be):
        check('normalization_'+s['sample_id'], b.validate_sample(s, cfg['mode'], out)[0]==raw)
    checks.append({'check':'known_RAW10_group','result':'pass'})
    check('known_RAW10_group_bytes',b.pack10([0,1,2,1023])==bytes([0,0,0,255,228]))
    report = b.run(cfg, out, out/'benchmark-mode00')
    check('zero_real_excludes_synthetic', report['real_sample_count']==0 and report['ratio'] is None and report['benchmark_result']=='blocked')
    check('all_controls_roundtrip', len(report['synthetic_controls'])==5 and all(r['byte_differences']==0 for r in report['synthetic_controls']))
    check('fixed_and_stored_controls', any(r['stored_blocks']>0 for r in report['synthetic_controls']) and any(r['stored_blocks']==0 for r in report['synthetic_controls']))
    phase = copy.deepcopy(baseline)
    phase.update(bayer_phase='RGGB',phase_evidence='synthetic declared phase-0')
    phase_cfg = {'schema_version':1,'mode':{'prep':1,'pred':1},'samples':[phase]}
    pr = b.run(phase_cfg,out,out/'benchmark-mode11')
    check('independent_inverse_odd_tail',pr['synthetic_controls'][0]['decoded_sha256']==b.sha(raw))
    phase_cfg['mode']={'prep':1,'pred':0}
    p10=b.run(phase_cfg,out,out/'benchmark-mode10')
    check('independent_inverse_no_prediction',p10['synthetic_controls'][0]['decoded_sha256']==b.sha(raw))
    def rejected(name, s, mode=None):
        try: b.validate_sample(s,mode or cfg['mode'],out)
        except (ValueError,KeyError,TypeError,OSError): checks.append({'check':name,'result':'reject'})
        else: raise AssertionError('not rejected: '+name)
    for field in ('sha256','width','height','stride','roi','bayer_phase','provenance','normalized_raw_sha256'):
        s=copy.deepcopy(baseline);del s[field];rejected('missing_'+field,s)
    mutations = [('bad_sha',{'sha256':'0'*64}),('width_mod4',{'width':15}),
                 ('bad_stride',{'stride':21}),('bad_normalized_sha',{'normalized_raw_sha256':'0'*64}),
                 ('bad_roi',{'roi':{'x':1,'y':0,'width':16,'height':5,'source_width':16,'source_height':5}}),
                 ('bad_category',{'category':'natural_N'}),('unknown_phase',{})]
    for name, delta in mutations:
        s=copy.deepcopy(baseline);s.update(delta);rejected(name,s,{'prep':1,'pred':1} if name=='unknown_phase' else None)
    for name, data in [('short',raw[:-1]),('long',raw+b'\0')]:
        p=out/(name+'.raw10');p.write_bytes(data);s=copy.deepcopy(baseline);s.update(path=str(p),sha256=b.sha(data));rejected(name+'_payload',s)
    for name, data in [('range',struct.pack('<80H',*([1024]+raw_values[1:]))),
                       ('padding',struct.pack('>80H',*([1]+[v<<6 for v in raw_values[1:]])))]:
        p=out/(name+'.u16');p.write_bytes(data);s=copy.deepcopy(le if name=='range' else be);s.update(path=str(p),sha256=b.sha(data));rejected(name+'_u16',s)
    s=copy.deepcopy(le);s['normalization']['byte_order']='big';rejected('wrong_endian_normalized_oracle',s)
    s=copy.deepcopy(baseline);s['category']='sensor_capture';rejected('synthetic_relabelled_real',s)
    s=copy.deepcopy(baseline);s['category']='historical_control';s['provenance']['source_kind']='real_fpga_uart_capture'
    hist=b.run({'schema_version':1,'mode':cfg['mode'],'samples':[s]},out,out/'historical-exclusion')
    check('historical_exclusion',hist['real_sample_count']==0 and len(hist['historical_controls'])==1)
    rec=(out/'benchmark-mode11'/('packed_raw10.a1u1')).read_bytes()
    def badrecord(name,data):
        try:b.decode_record(data)
        except (ValueError, b.strict.A1Error, zlib.error):checks.append({'check':name,'result':'reject'})
        else:raise AssertionError('decoder accepted '+name)
    import zlib
    badrecord('record_truncated',rec[:-1]);badrecord('record_trailing',rec+b'\0')
    mut=bytearray(rec);mut[-1]^=1;badrecord('stream_crc',mut)
    mut=bytearray(rec);mut[5]|=4;badrecord('reserved_flags',mut)
    mut=bytearray(rec);mut[32]^=1;mut[40:44]=struct.pack('<I',zlib.crc32(mut[:40])&0xffffffff);badrecord('xform_crc',mut)
    for name, stream in [('extra_zlib',rec[44:]+b'\0'),('truncated_zlib',rec[44:-1])]:
        try:b.inflate_strict(stream,len(raw))
        except (ValueError,b.strict.A1Error,zlib.error):checks.append({'check':name,'result':'reject'})
        else:raise AssertionError('inflate accepted '+name)
    result={'status':'tool_controls_pass','claims_real_benefit':False,'checks':checks,
            'real_sample_count':0,'ratio':None,'benchmark_result':'blocked'}
    (out.parent/(out.name+'-result.json')).write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print('TOOL_CONTROLS_PASS checks='+str(len(checks))+' real_sample_count=0 ratio=null benchmark_result=blocked')

if __name__=='__main__':main()
