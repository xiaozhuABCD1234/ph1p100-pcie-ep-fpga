"""One-time local fixture preparation. All writes stay in this task folder."""
import hashlib,json,pathlib,struct,sys,zlib
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent
RUN=HERE.parent
assert HERE.name=='T10.a1-uart-descriptor-fix' and HERE==HERE.resolve()
for name in ['ddr_recovery_model.sv','check_recovery.py']:
    (HERE/name).write_bytes((RUN/'T10.a1-recovery-sim'/name).read_bytes())
tb=(RUN/'T10.a1-recovery-sim/tb_recovery.sv').read_text()
tb=tb.replace('module tb_recovery #','module tb_full_clean #')
tb=tb.replace('while((exp-start_exp<2)&&t<1000000)','while((exp-start_exp<4)&&t<1000000)')
tb=tb.replace('if(recovered<2||recovery_elapsed>1000000)','if(recovered!=4||recovery_elapsed>1000000)')
tb=tb.replace('if(case_id!=0 && inject_hit!=1)', 'if(case_id!=0) $fatal(1,"ONLY_CLEAN_AUTHORIZED_IN_THIS_PACKAGE");\n  if(case_id!=0 && inject_hit!=1)')
(HERE/'tb_full_clean.sv').write_text(tb)
vectors=[];ds=[];ps=[]
for i in range(20):
    fid=1001+i if i<12 else (2001+i-12 if i<14 else 7001+i-14)
    raw=bytes(((fid*7+j*13) ^ (j*j))&255 for j in range(20))
    payload=zlib.compress(raw)
    assert len(payload)<=32
    rc=zlib.crc32(raw)&0xffffffff;sc=zlib.crc32(payload)&0xffffffff
    fields=[fid,len(raw),len(raw),len(payload),rc,rc,sc,0]
    descriptor=struct.pack('<8I',*fields)
    ds.append(descriptor[::-1].hex());ps.append(payload.ljust(32,b'\0')[::-1].hex())
    vectors.append(dict(index=i,frame_id=fid,raw_hex=raw.hex(),payload_hex=payload.hex(),raw_crc=rc,stream_crc=sc))
(HERE/'descriptors.hex').write_text('\n'.join(ds)+'\n')
(HERE/'payloads.hex').write_text('\n'.join(ps)+'\n')
(HERE/'fixtures.json').write_text(json.dumps(vectors,indent=2))
manifest=json.loads((RUN/'planning-input-manifest.json').read_text(encoding='utf-8-sig'))
before=[]
for x in manifest['files']:
    p=pathlib.Path(x['frozen']);actual=hashlib.sha256(p.read_bytes()).hexdigest()
    assert actual==x['sha256'],str(p)
    before.append(dict(path=str(p),sha256=actual))
(HERE/'protected-before.json').write_text(json.dumps(dict(files=before,drift=[]),indent=2))
print('PREPARED fixtures=20 protected='+str(len(before)))
