#!/usr/bin/env python3
"""Bounded file-only local checks. All outputs are restricted to --out.

prepare creates offline samples; rtl runs one compile + one simulation process;
check uses independent strict DEFLATE plus the historical decoder APIs.
"""
import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import time
import zlib
sys.dont_write_bytecode = True
import replay as R
ROOT=R.ROOT
PACKAGE=Path(__file__).resolve().parent
PYTHON=Path(sys.executable)
MODELSIM=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
SNAP=ROOT/'workspace/ph1p100'
OLD=SNAP/'workflow/runs/20261026-2138_fpga-integrated-delivery'

def dump(p, data): p.parent.mkdir(parents=True, exist_ok=True);p.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
def load_module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def run(out,args,log,timeout=300):
    started=time.time()
    # subprocess.run terminates only this directly owned child on timeout.
    # No shells, device processes, background workers or foreign PIDs are used.
    try:
        args=[a.as_posix() if isinstance(a,Path) else str(a) for a in args]
        p=subprocess.run(args,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
            timeout=timeout,encoding='utf-8',errors='replace',env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'))
        rc=p.returncode; text=p.stdout
    except subprocess.TimeoutExpired as e:
        rc=124;text=(e.stdout or b'').decode('utf-8',errors='replace') if isinstance(e.stdout,bytes) else (e.stdout or '')
        text+='\nOWNED_CHILD_TIMEOUT\n'
    (out/log).write_text(text,encoding='utf-8')
    with (out/'commands.jsonl').open('a',encoding='utf-8') as f:
        f.write(json.dumps(dict(argv=[str(a) for a in args],cwd=str(out),timeout_seconds=timeout,
            exit_code=rc,seconds=time.time()-started,log=str(out/log)))+'\n')
    R.require(rc==0,'command failed: '+log)
    return text

def metadata(stream,raw,xf,frame_id,w,h,flags,camera,kind,source):
    return dict(schema=1,offline_header_reconstruction=True,identity_transport_status='sidecar_only_not_on_A1U1_wire',
        camera_id=camera,slot_id=0,epoch=1,session=7,capture_seq=frame_id,frame_id=frame_id,
        mode=0,prep=flags&1,pred=flags>>1,flags=flags,width=w,height=h,stride=w*5//4,
        raw_bytes=len(raw),xform_bytes=len(xf),raw_crc32=f'{R.crc(raw):08x}',
        xform_crc32=f'{R.crc(xf):08x}',slot_sha256=R.sha(stream),raw_sha256=R.sha(raw),
        source_kind=kind,source=source,source_sha256=R.sha(stream),
        camera_session_provenance='explicit offline context; not recovered from A1U1 header',
        sensor_pixel_oracle_verified=(kind=='synthetic_control'),physical_bayer_phase='synthetic_phase0' if kind=='synthetic_control' else 'unknown')

def prepare(out):
    out.mkdir(parents=True,exist_ok=False)
    bindings=[]
    for mf in ['INT.P2-r0-manifest.json','INT.P3-r1-manifest.json']:
        mp=OLD/mf;m=json.loads(mp.read_text(encoding='utf-8'))
        for e in m['production_inputs']:
            p=SNAP/e['path'];actual=R.sha(p.read_bytes());R.require(actual==e['sha256'],'frozen source drift: '+str(p))
            bindings.append(dict(path=str(p),sha256=actual,size=p.stat().st_size,original_manifest=str(mp),original_path=e['path'],sha_matches=True))
    extra=[ROOT/'AGENTS.md', ROOT/'docs/PROJECT_SYNC_20261027.md',
        SNAP/'fpga/csi2/src/a1/a1_ddr_slot_store.v',ROOT/'rtl/ep_side/ddr/ddr_frame_pusher.v',
        SNAP/'tools/integrated_delivery/a1u1_decode.py',R.REF/'decode_sample.py',
        R.REF/'reference/a1_ref.py',R.REF/'reference/a1_inflate_strict.py',
        R.REF/'samples/b18_b_1080p.a1u1',R.REF/'expected.json',R.REF/'provenance.json',
        OLD/'INT.P2-r0-manifest.json',OLD/'INT.P3-r1-manifest.json',
        OLD/'test-reports/INT.P2-r0-integrated.md',OLD/'test-reports/INT.P3-r1-integrated.md',
        Path('D:/fpga/ph1p100/workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4-protocol.md')]
    extra += [PACKAGE.parent/x for x in ['request.md','dev-plan.md','fpga-design-guide.md','input-index.md','dispatch.json']]
    for p in extra: bindings.append(dict(path=str(p),sha256=R.sha(p.read_bytes()),size=p.stat().st_size,role='read_only_source_or_contract'))
    dump(out/'source-binding.json',dict(project_root=str(ROOT),source_entries=bindings,
        compiled_sources=[str(SNAP/'fpga/csi2/src/a1/a1_ddr_slot_store.v'),str(SNAP/'fpga/csi2/src/integrated_delivery/aplus_pcie_egress_adapter.v'),str(PACKAGE/'tb_byte_replay.v')],
        p4_scope='protocol only, no P4 RTL read or compiled',pusher_scope='static review only, not instantiated'))
    # Construct packed bytes independently of a1_ref.pack_samples.
    w,h=16,4;pix=[(x*197+y*311+(x*y*23))%1024 for y in range(h) for x in range(w)]
    raw=bytes(b for i in range(0,len(pix),4) for b in ([pix[i+j]>>2 for j in range(4)]+[sum((pix[i+j]&3)<<(2*j) for j in range(4))]))
    cases=[]
    for flags in [0,1,3]:
        encoded=R.a1_ref.encode_frame(raw,w,h,flags&1,flags>>1)
        stream=encoded['stream'];xf=encoded['xform'];name='synthetic-flags'+str(flags)
        meta=metadata(stream,raw,xf,123,w,h,flags,0,'synthetic_control','deterministic packed RAW10 formula in runner.py')
        dump(out/(name+'-input-metadata.json'),meta)
        info=R.reconstruct(stream,meta,out/name,0,7,8192)
        cases.append(dict(name=name,expected_camera=0,expected_session=7,**info))
    decoder=load_module('historical_decoder',R.REF/'decode_sample.py')
    original=(R.REF/'samples/b18_b_1080p.a1u1').read_bytes();raw,oldinfo=decoder.decode_record(original)
    sn=struct.unpack_from('<I',original,24)[0];stream=original[44:44+sn];xf=zlib.decompress(stream)
    meta=metadata(stream,raw,xf,1,1920,1080,3,1,'historical_real_fpga_uart_control',str(R.REF/'samples/b18_b_1080p.a1u1'))
    meta.update(original_record_sha256=R.sha(original),sensor_pixel_oracle_verified=False,source_sha256=R.sha(original))
    dump(out/'historical-b18-input-metadata.json',meta)
    info=R.reconstruct(stream,meta,out/'historical-b18',1,7,4194304)
    R.require((out/'historical-b18/reconstructed.a1u1').read_bytes()==original,'historical header differs')
    cases.append(dict(name='historical-b18',expected_camera=1,expected_session=7,**info))
    dump(out/'expected.json',dict(offline_only=True,real_pcie_connected=False,cases=cases))
    stimulus=(out/'synthetic-flags3/current-slot.bin').read_bytes()
    (out/'stream.mem').write_text(''.join(f'{x:02x}\n' for x in stimulus),encoding='ascii')
    (out/'fixture-config.vh').write_text(f'`define STREAM_N {len(stimulus)}\n',encoding='ascii')
    (out/'sources.f').write_text('\n'.join('"'+str(p).replace('\\','/')+'"' for p in [SNAP/'fpga/csi2/src/a1/a1_ddr_slot_store.v',SNAP/'fpga/csi2/src/integrated_delivery/aplus_pcie_egress_adapter.v',PACKAGE/'tb_byte_replay.v'])+'\n',encoding='utf-8')
    print('PREPARE PASS cases=4 frozen_P2_P3_SHA_match=true')

def rtl(out, skip_compile=False):
    if not skip_compile:
        run(out,[MODELSIM/'vlib.exe','work'],'vlib.log',60)
        (out/'modelsim.ini').write_text('[Library]\nwork = work\n[vsim]\n',encoding='ascii')
        text=run(out,[MODELSIM/'vlog.exe','-modelsimini',out/'modelsim.ini','-work','work','+incdir+.', '-f','sources.f'],'compile.log')
        R.require('Errors: 0' in text,'missing clean compile marker')
    simlog='simulation-retry.log' if skip_compile else 'simulation.log'
    text=run(out,[MODELSIM/'vsim.exe','-c','-modelsimini',out/'modelsim.ini','-wlf',out/'rtl.wlf','work.tb_byte_replay','-do','run -all; quit -f'],simlog)
    R.require('BYTE_REPLAY_RTL PASS' in text and 'BYTE_REPLAY_RTL FAIL' not in text,'RTL check failed')
    actual=(out/'rtl-slot-read.bin').read_bytes();expected=(out/'synthetic-flags3/current-slot.bin').read_bytes()
    R.require(actual==expected,'real slot differs from exact zlib')
    wordpad=(out/'rtl-slot-word-padding.bin').read_bytes();R.require(len(wordpad)==(len(actual)+31)//32*32 and not any(wordpad[len(actual):]),'slot word padding')
    desc=[json.loads(x) for x in (out/'p2-descriptors.jsonl').read_text().splitlines()]
    R.require(len(desc)==48,'descriptor count')
    for x in desc: R.require(x['frame_bytes']==R.align(x['zlib_bytes']),'actual P2 length differs')
    boundary=[dict(**x,proposed_a1u1_bytes=44+x['zlib_bytes'],proposed_dma_bytes=R.align(44+x['zlib_bytes']),changed=(x['frame_bytes']!=R.align(44+x['zlib_bytes'])),fixture_kind='length_only_not_compressor_output') for x in desc if x['kind']==1]
    R.require(sum(x['changed'] for x in boundary)==44,'boundary count: mod0 and4053..4095')
    dump(out/'rtl-results.json',dict(status='pass',real_slot_byte_differences=0,slot_bytes=len(actual),
        actual_word_padding_bytes=len(wordpad)-len(actual),dma_tail_to_4096_proven=False,descriptor_count=len(desc),
        boundary=boundary,insufficient_capacity_descriptor=desc[-1],
        backend='missing_not_instantiated',p2_cam_sel='hardwired_0',ack_checks='wrong-session rejected, matching session/seq released for all48'))
    print('RTL_LOCAL PASS actual_slot_diff=0 descriptors=48 boundary_changed=44')

def check(out):
    legacy=load_module('legacy_decoder',SNAP/'tools/integrated_delivery/a1u1_decode.py')
    historical=load_module('handoff_decoder',R.REF/'decode_sample.py')
    positives=[]
    for c in json.loads((out/'expected.json').read_text())['cases']:
        p=out/c['name'];info=R.verify_case(p,c['expected_camera'],7,4194304)
        raw,hinfo=historical.decode_record((p/'reconstructed.a1u1').read_bytes())
        R.require(raw==(p/'expected.raw10').read_bytes(),'historical strict inverse disagreement')
        old=legacy.parse((p/'proposed-a1u1-dma.bin').read_bytes())
        R.require(old['raw_len_ok'] and old['payload_bytes']==info['zlib_bytes'],'legacy compatibility')
        positives.append(dict(name=c['name'],status='pass',byte_differences=0,four_crc_match=True,
            strict_eof=True,unused_data_bytes=0,unconsumed_tail_bytes=0,legacy_decoder='compatible',**info))
    p=out/'synthetic-flags3';valid=(p/'reconstructed.a1u1').read_bytes();negative=[];negdir=out/'negatives';negdir.mkdir(exist_ok=True)
    def reject(name,fn,reason):
        try: fn()
        except (ValueError,R.a1_inflate_strict.A1Error,zlib.error) as e:
            R.require(reason.lower() in str(e).lower(),'wrong rejection for '+name+': '+str(e))
            negative.append(dict(name=name,status='reject',error=str(e)));return
        raise AssertionError('negative accepted: '+name)
    def change(name,offset,payload,reason,fix=True):
        d=bytearray(valid);d[offset:offset+len(payload)]=payload
        if fix: struct.pack_into('<I',d,40,R.crc(d[:40]))
        (negdir/(name+'.a1u1')).write_bytes(d);reject(name,lambda:R.decode_record(bytes(d)),reason)
    change('header-crc',40,b'\0\0\0\0','header CRC',False)
    change('stream-crc',36,b'\0\0\0\0','stream CRC')
    change('xform-crc',32,b'\0\0\0\0','xform CRC')
    change('raw-crc',28,b'\0\0\0\0','raw CRC')
    change('version',4,b'\2','unsupported')
    change('reserved-flags',5,b'\x83','reserved')
    change('raw-length',16,struct.pack('<I',81),'raw_len')
    change('xform-length',20,struct.pack('<I',81),'raw/xform')
    for name,data in [('truncated-header',valid[:43]),('truncated-stream',valid[:-1])]:
        (negdir/(name+'.a1u1')).write_bytes(data);reject(name,lambda d=data:R.decode_record(d),'truncated' if name=='truncated-header' else 'record length')
    extra=valid[44:]+zlib.compress(b'extra');meta=json.loads((p/'replay-metadata.json').read_text())
    data=R.make_record(extra,meta);(negdir/'extra-zlib.a1u1').write_bytes(data)
    reject('extra-zlib',lambda:R.decode_record(data),'strict zlib')
    short=R.make_record(valid[44:-1],meta);(negdir/'truncated-zlib-reframed.a1u1').write_bytes(short)
    reject('truncated-zlib-reframed',lambda:R.decode_record(short),'strict zlib')
    reject('wrong-camera',lambda:R.verify_case(p,1,7,4194304),'camera sidecar')
    reject('wrong-session',lambda:R.verify_case(p,0,8,4194304),'session sidecar')
    reject('insufficient-capacity',lambda:R.verify_case(p,0,7,4095),'capacity')
    for filename in ['current-dma.bin','proposed-a1u1-dma.bin']:
        np=negdir/filename.replace('.bin','-nonzero');np.mkdir(exist_ok=True)
        for f in p.iterdir():
            if f.is_file(): shutil.copyfile(f,np/f.name)
        d=bytearray((np/filename).read_bytes());d[-1]=1;(np/filename).write_bytes(d)
        reject('nonzero-tail-'+filename,lambda q=np:R.verify_case(q,0,7,4194304),'nonzero tail')
    dump(out/'positive-results.json',positives);dump(out/'negative-results.json',negative)
    # Bind the real slot to this exact independent RAW10 oracle, not only a fixture hash.
    actual=(out/'rtl-slot-read.bin').read_bytes()
    R.require(actual==valid[44:],'DUT zlib differs')
    actual_record=R.make_record(actual,meta);raw,_=R.decode_record(actual_record)
    R.require(raw==(p/'expected.raw10').read_bytes(),'DUT replay inverse mismatch')
    print(f'SOFTWARE_LOCAL PASS positives={len(positives)} negatives={len(negative)} byte_differences=0 four_crc_match=true')

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('action',choices=['prepare','rtl','check']);ap.add_argument('--out',type=Path,required=True);ap.add_argument('--skip-compile',action='store_true');a=ap.parse_args()
    out=a.out.resolve();tester_root=PACKAGE.parent/'test-reports/T03.pcie-byte-replay'
    R.require(out.is_relative_to(PACKAGE.resolve()) or out.is_relative_to(tester_root.resolve()),'output outside task developer/tester scope')
    if a.action=='rtl': rtl(out,a.skip_compile)
    else: {'prepare':prepare,'check':check}[a.action](out)
if __name__=='__main__':main()
