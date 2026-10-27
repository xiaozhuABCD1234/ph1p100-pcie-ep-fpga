"""Offline A+ v1 software benchmark. No hardware performance or provenance oracle."""
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import sys
import zlib
sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name,path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

ref = load('t04_readonly_reference', ROOT/'tools/codec/a1_ref.py')
strict = load('t04_readonly_strict', ROOT/'tools/codec/a1_inflate_strict.py')

def sha(data): return hashlib.sha256(data).hexdigest()
def crc(data): return zlib.crc32(data)&0xffffffff
def need(ok, message):
    if not ok: raise ValueError(message)
def integer(value, lo, hi, name):
    need(type(value) is int and lo<=value<=hi, 'invalid '+name)
    return value
def text_value(obj, key):
    value=obj[key]
    need(isinstance(value,str) and value.strip().lower() not in ('','unknown','tbd','todo','n/a'), 'missing/placeholder '+key)
    return value
def digest(value,name):
    need(isinstance(value,str) and re.fullmatch('[0-9a-fA-F]{64}',value) is not None,'invalid '+name)
    return value.lower()
def local_file(path,base,maxbytes=64*1024*1024):
    p=Path(path)
    if not p.is_absolute():p=base/p
    p=p.resolve(strict=True)
    need(p.is_file() and 0<p.stat().st_size<=maxbytes,'invalid file size/type: '+str(p))
    return p

def pack10(samples):
    need(len(samples)%4==0,'packing needs groups of four')
    out=bytearray()
    for i in range(0,len(samples),4):
        q=samples[i:i+4]
        need(all(type(v) is int and 0<=v<=1023 for v in q),'sample outside 10bit')
        out.extend(v>>2 for v in q)
        out.append(sum((v&3)<<(2*j) for j,v in enumerate(q)))
    return bytes(out)

def unpack10(data):
    need(len(data)%5==0,'RAW10 group length')
    return [(data[i+j]<<2)|((data[i+4]>>(2*j))&3)
            for i in range(0,len(data),5) for j in range(4)]

def validate_sample(s, mode, base):
    need(isinstance(s,dict),'sample must be object')
    sid=s['sample_id'];need(isinstance(sid,str) and re.fullmatch('[A-Za-z0-9_-]{1,80}',sid),'invalid sample_id')
    cat=s['category'];need(cat in ('sensor_capture','synthetic_control','historical_control'),'invalid category')
    w=integer(s['width'],4,1920,'width');need(w%4==0,'width must be multiple of four')
    h=integer(s['height'],2,65535,'height');need(w*h*5//4<=64*1024*1024,'frame too large')
    prep=integer(mode['prep'],0,1,'prep');pred=integer(mode['pred'],0,1,'pred')
    need(not pred or prep,'prediction requires preprocessing')
    phase=s['bayer_phase'];need(phase in ('unknown','RGGB','GRBG','GBRG','BGGR'),'invalid Bayer phase')
    if prep or pred:
        need(phase=='RGGB','phase0 preprocessing needs documented RGGB, including any normalization')
        text_value(s,'phase_evidence')
    roi=s['roi'];need(isinstance(roi,dict),'ROI must be object')
    x=integer(roi['x'],0,65535,'roi.x');y=integer(roi['y'],0,65535,'roi.y')
    need(roi['width']==w and roi['height']==h,'ROI dimensions differ from supplied frame')
    sw=integer(roi['source_width'],w,65535,'source_width');sh=integer(roi['source_height'],h,65535,'source_height')
    need(x+w<=sw and y+h<=sh,'ROI exceeds source')
    p=local_file(s['path'],base);data=p.read_bytes()
    need(sha(data)==digest(s['sha256'],'sha256'),'source SHA mismatch')
    fmt=s['format'];stride=s['stride']
    if fmt=='packed_raw10':
        need(type(stride) is int and stride==w*5//4,'packed stride must equal W*5/4; padding unsupported')
        need(len(data)==stride*h,'packed payload length mismatch')
        raw=pack10(unpack10(data))
    elif fmt=='u16':
        need(type(stride) is int and stride==w*2,'u16 stride must equal W*2; padding unsupported')
        need(len(data)==stride*h,'u16 payload length mismatch')
        n=s['normalization'];need(n['byte_order'] in ('little','big'),'u16 endian required')
        need(type(n['valid_bits']) is int and n['valid_bits']==10,'u16 valid_bits must be 10')
        shift=integer(n['right_shift'],0,6,'right_shift')
        words=struct.unpack(('<' if n['byte_order']=='little' else '>')+str(w*h)+'H',data)
        need(all((v&((1<<shift)-1))==0 and (v>>shift)<=1023 for v in words),'u16 range/padding invalid; truncation forbidden')
        raw=pack10([v>>shift for v in words])
    else:raise ValueError('unsupported format')
    need(sha(raw)==digest(s['normalized_raw_sha256'],'normalized_raw_sha256'),'normalized RAW SHA mismatch')
    prov=s['provenance'];need(isinstance(prov,dict),'provenance must be object')
    for key in ('source_kind','source','device','captured_at','license_basis','format_basis'):text_value(prov,key)
    need(type(prov['sensor_pixel_oracle_verified']) is bool,'pixel verification must be boolean')
    text_value(s,'content_id')
    if cat=='sensor_capture':
        need(prov['source_kind']=='sensor_capture','real summary requires sensor capture source')
        need(prov['sensor_pixel_oracle_verified'] is True,'sensor pixel oracle unverified')
        oracle=prov['pixel_oracle']
        for key in ('method','reviewer','correctness_basis'):text_value(oracle,key)
        ep=local_file(oracle['evidence_path'],base,1024*1024)
        need(sha(ep.read_bytes())==digest(oracle['evidence_sha256'],'evidence_sha256'),'pixel evidence SHA mismatch')
        need(digest(oracle['normalized_raw_sha256'],'pixel oracle raw SHA')==sha(raw),'pixel evidence binds different RAW')
        need(oracle['review_decision']=='qualified','independent provenance/pixel review required')
    return raw,{'path':str(p),'original_sha256':sha(data),'normalized_raw_sha256':sha(raw),'source_bytes':len(data)}

def independent_inverse(data,w,h,prep,pred):
    if not prep:return data
    # Independent flat-index scatter: no call to a1_ref.inverse_frame.
    vals=unpack10(data);out=[0]*(w*h);src=0
    for top in range(0,h,2):
        for row in range(top,min(top+2,h)):
            for parity in (0,1):
                acc=0
                for col in range(parity,w,2):
                    value=vals[src];src+=1
                    if pred:acc=(acc+value)%1024;value=acc
                    out[row*w+col]=value
    need(src==len(vals),'inverse sample length')
    return pack10(out)

def inflate_strict(stream,n):
    xf,st=strict.inflate(stream,expected_len=n)
    dec=zlib.decompressobj();native=dec.decompress(stream,n+1)+dec.flush()
    need(dec.eof and not dec.unused_data and not dec.unconsumed_tail,'zlib EOF/tail violation')
    need(native==xf and len(xf)==n,'independent DEFLATE disagreement')
    return xf,st

def record(raw,xf,stream,w,h,mode):
    flags=mode['prep']|(mode['pred']<<1)
    head=struct.pack('<4sBBHIHHIIIIII',b'A1U1',1,flags,44,0,w,h,len(raw),len(xf),len(stream),crc(raw),crc(xf),crc(stream))
    return head+struct.pack('<I',crc(head))+stream

def decode_record(data):
    need(len(data)>=44,'truncated header')
    magic,version,flags,hlen,fid,w,h,rlen,xlen,slen,rc,xc,sc,hc=struct.unpack_from('<4sBBHIHHIIIIIII',data)
    need(magic==b'A1U1' and version==1 and hlen==44 and flags&~3==0,'bad header fields')
    prep=flags&1;pred=flags>>1;need(not pred or prep,'illegal flags')
    need(w>=4 and w%4==0 and h>=2 and rlen==w*h*5//4 and rlen<=64*1024*1024,'bad record geometry')
    need(xlen==rlen and slen>0 and len(data)==44+slen,'record length/tail mismatch')
    need(crc(data[:40])==hc,'header CRC mismatch')
    stream=bytes(data[44:]);need(crc(stream)==sc,'stream CRC mismatch')
    xf,st=inflate_strict(stream,xlen);need(crc(xf)==xc,'xform CRC mismatch')
    raw=independent_inverse(xf,w,h,prep,pred);need(len(raw)==rlen and crc(raw)==rc,'raw CRC/length mismatch')
    return raw,st

def run(cfg,base,out):
    need(cfg['schema_version']==1 and type(cfg['schema_version']) is int,'unsupported schema_version')
    mode=cfg['mode'];integer(mode['prep'],0,1,'prep');integer(mode['pred'],0,1,'pred')
    need(not mode['pred'] or mode['prep'],'prediction requires preprocessing')
    samples=cfg['samples'];need(isinstance(samples,list) and len(samples)<=32,'samples must be array <=32')
    need(len({s['sample_id'] for s in samples})==len(samples),'duplicate sample IDs')
    out=out.resolve();need(out.is_relative_to(HERE),'output outside task package')
    out.mkdir(parents=True,exist_ok=False)
    rows=[];blocked=[]
    for s in samples:
        try:raw,binding=validate_sample(s,mode,base)
        except (ValueError,KeyError,TypeError,OSError) as e:
            blocked.append({'sample_id':s.get('sample_id','unknown'),'reason':str(e)});continue
        enc=ref.encode_frame(raw,s['width'],s['height'],mode['prep'],mode['pred'])
        stream=bytes(enc['stream']);rec=record(raw,bytes(enc['xform']),stream,s['width'],s['height'],mode)
        decoded,st=decode_record(rec)
        need(decoded==raw,'roundtrip differs')
        est=enc['stats'];need(est['block_count']==st['blocks'] and est['stored_blocks']==st['stored_blocks'],'block stats disagreement')
        stored=sum(size for kind,size in zip(est['block_types'],est['block_sizes']) if kind=='stored')
        need(stored==st['stored_bytes'],'stored byte statistics disagreement')
        sid=s['sample_id'];(out/(sid+'.zlib')).write_bytes(stream);(out/(sid+'.a1u1')).write_bytes(rec);(out/(sid+'.decoded.raw10')).write_bytes(decoded)
        dma=(len(rec)+4095)//4096*4096
        row={'sample_id':sid,'category':s['category'],'content_id':s['content_id'],
             **binding,'width':s['width'],'height':s['height'],'input_stride':s['stride'],
             'prep':mode['prep'],'pred':mode['pred'],'bayer_phase':s['bayer_phase'],
             'raw_bytes':len(raw),'zlib_bytes':len(stream),'a1u1_bytes':len(rec),
             'dma_bytes':dma,'header_bytes':44,'alignment_bytes':dma-len(rec),
             'ratio_raw_over_zlib':len(raw)/len(stream),'ratio_raw_over_a1u1':len(raw)/len(rec),
             'ratio_raw_over_dma':len(raw)/dma,'stored_blocks':st['stored_blocks'],
             'block_count':st['blocks'],'stored_raw_bytes':st['stored_bytes'],
             'fallback_block_ratio':st['stored_blocks']/st['blocks'],
             'fallback_raw_byte_ratio':st['stored_bytes']/len(raw),
             'decoded_sha256':sha(decoded),'byte_differences':0,
             'raw_crc32':f'{crc(raw):08x}','xform_crc32':f'{crc(enc["xform"]):08x}',
             'stream_crc32':f'{crc(stream):08x}','header_crc32':f'{crc(rec[:40]):08x}'}
        rows.append(row)
    real=[r for r in rows if r['category']=='sensor_capture'];n=len(real)
    totals={key:sum(r[key] for r in real) for key in ('raw_bytes','zlib_bytes','a1u1_bytes','dma_bytes','stored_blocks','block_count','stored_raw_bytes')}
    summary=None
    if n:
        summary={**totals,'ratio_raw_over_zlib':totals['raw_bytes']/totals['zlib_bytes'],
                 'ratio_raw_over_a1u1':totals['raw_bytes']/totals['a1u1_bytes'],
                 'ratio_raw_over_dma':totals['raw_bytes']/totals['dma_bytes'],
                 'fallback_block_ratio':totals['stored_blocks']/totals['block_count'],
                 'fallback_raw_byte_ratio':totals['stored_raw_bytes']/totals['raw_bytes']}
    different_contents=len({r['content_id'] for r in real})
    result={'schema_version':1,'model':'tools/codec/a1_ref.py A+ v1 software fixed/LZ77/stored',
            'mode':mode,'model_sha256':sha((ROOT/'tools/codec/a1_ref.py').read_bytes()),
            'strict_parser_sha256':sha((ROOT/'tools/codec/a1_inflate_strict.py').read_bytes()),
            'real_sample_count':n,'qualified_real_count':n,'distinct_real_content_count':different_contents,
            'ratio':summary['ratio_raw_over_zlib'] if summary else None,
            'benchmark_result':'blocked' if not n or blocked else ('measured_finite_dataset' if n>=3 and different_contents>=3 else 'measured_single_sample' if n==1 else 'measured_samples_not_dataset'),
            'real_summary':summary,'real_samples':real,'blocked_inputs':blocked,
            'missing_conditions':['qualified sensor RAW10, source/format declarations, independent pixel-correctness evidence'] if not n else [],
            'synthetic_controls':[r for r in rows if r['category']=='synthetic_control'],
            'historical_controls':[r for r in rows if r['category']=='historical_control'],
            'claims_hardware_performance':False,'provenance_review_boundary':'metadata and evidence SHA checked; independent reviewer remains responsible for factual authenticity',
            'dma_layout':'offline A1U1 reference: align_up(44+zlib_bytes,4096); not current hardware descriptor'}
    (out/'benchmark.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    for name,group in (('real-summary',real),('synthetic-controls',result['synthetic_controls']),('historical-controls',result['historical_controls'])):
        keys=list(rows[0]) if rows else ['sample_id','category','raw_bytes','zlib_bytes','a1u1_bytes','dma_bytes']
        with (out/(name+'.csv')).open('w',encoding='utf-8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=keys);writer.writeheader();writer.writerows(group)
    return result

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--config',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args()
    try:
        cfg=json.loads(args.config.read_text(encoding='utf-8-sig'))
        result=run(cfg,args.config.resolve().parent,args.output)
    except Exception as e:
        print('INPUT_OR_TOOL_REJECT: '+str(e),file=sys.stderr);return 2
    print(json.dumps({k:result[k] for k in ('benchmark_result','real_sample_count','ratio')}))
    return 2 if result['blocked_inputs'] else 3 if result['benchmark_result']=='blocked' else 0

if __name__=='__main__':sys.exit(main())
