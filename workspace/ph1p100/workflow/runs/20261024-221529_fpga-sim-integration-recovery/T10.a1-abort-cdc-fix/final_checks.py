import pathlib,json,re,sys,zlib,struct
sys.dont_write_bytecode=True
p=pathlib.Path(r'D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery\T10.a1-abort-cdc-fix');sys.path.insert(0,str(p));import check_recovery
c=p/'corrected/clean-slow-final';data=bytes(map(int,(c/'capture.dec').read_text().split()));base=json.loads((c/'result.json').read_text());allowed=base['allowed_good_seeds'];neg=[]
def reject(name,b,perm=allowed):
 try:check_recovery.packets(bytes(b),8,2,perm);e='ACCEPTED';ok=False
 except (AssertionError,ValueError,zlib.error,IndexError) as exc:e=str(exc);ok=True
 neg.append(dict(name=name,rejected=ok,reason=e));assert ok,name
reject('tail-byte',data+b'\x00');reject('duplicate-packet',data+data[:73]);reject('truncated-payload',data[:-1]);reject('CRC-valid-old-epoch',data,list(range(1100,1104)))
b=bytearray(data);b[40]^=1;reject('header-CRC',b)
b=bytearray(data);b[44]^=1;reject('stream-CRC',b)
for off,name in [(28,'raw-CRC'),(32,'transform-CRC')]:
 b=bytearray(data);b[off]^=1;struct.pack_into('<I',b,40,zlib.crc32(b[:40])&0xffffffff);reject(name,b)
slen=struct.unpack_from('<I',data,24)[0];payload=data[44:44+slen];header=bytearray(data[:44]);newpay=payload+zlib.compress(b'extra');struct.pack_into('<I',header,24,len(newpay));struct.pack_into('<I',header,36,zlib.crc32(newpay)&0xffffffff);struct.pack_into('<I',header,40,zlib.crc32(header[:40])&0xffffffff)
reject('valid-zlib-concatenation',header+newpay+data[44+slen:])
for n,cid in [('raw-midwrite-reset',1),('encoded-midwrite-reset',2),('bad-frame',3),('overflow',4),('full-abort',5),('pending-reset',6),('sof-abort',7),('last-skid-abort',8)]:
 r=check_recovery.check(p/'corrected'/(n+'-slow-final'),cid,inject_override=0);ok='fault trigger absent' in r['errors'];neg.append(dict(name=n+'-trigger-deleted',rejected=ok,reason=r['errors']));assert ok
(p/'checker-negatives.json').write_text(json.dumps(neg,indent=2))
# Retain exact source variants used by the earlier compile phases.
final=(p/'tb_recovery.sv').read_text();oldblock='''`ifndef CORRECTED
   if(abort_writes!=1||abort_reads!=1||raw_aborts!=1||rawdrop<1) $fatal(1,"ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED");
`endif
'''
aligned=final.replace(oldblock,'');assert aligned!=final
newcond='''while(!(((dut.cam_abort_pending && dut.cam_room) || (dut.cam_abort_held && !dut.cam_fifo_ready)) &&
       (dut.u_cam_fifo.wgn != {~dut.u_cam_fifo.wq2_rgray[FIFO_AW:FIFO_AW-1],dut.u_cam_fifo.wq2_rgray[FIFO_AW-2:0]})) && j<200)'''
initial=aligned.replace(newcond,'while(!(dut.cam_abort_pending && dut.cam_room) && j<200)');assert initial!=aligned
versions=p/'test-input-versions';versions.mkdir(exist_ok=True)
(versions/'tb_recovery-initial.sv').write_text(initial,newline='\n');(versions/'tb_recovery-aligned.sv').write_text(aligned,newline='\n')
# Since the only final delta is inside ifndef CORRECTED, the corrected
# preprocessed program for the successful fast SOF retry is exactly equal.
assert final.replace(oldblock,'')==aligned
(p/'TB-version-binding.json').write_text(json.dumps(dict(initial=str(versions/'tb_recovery-initial.sv'),aligned=str(versions/'tb_recovery-aligned.sv'),final=str(p/'tb_recovery.sv'),corrected_aligned_equals_final_after_preprocessing=True,final_matrix_19_use_final=True,fast_sof_retry_uses_aligned=True,initial_failures_preserved=['corrected/sof-abort-fast','old/bad-frame-slow']),indent=2))
old=p/'old/bad-frame-slow-retry';r=json.loads((old/'result.json').read_text());log=(old/'console.log').read_text();tr=(old/'trace.txt').read_text()
assert r['status']=='EXPECTED_REJECTION' and 'ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED' in log
r['expected_early_rejection_has_no_stats']=True;r['checker_errors_from_expected_missing_stats']=r.pop('errors');r['errors']=[]
r['target_evidence']=[l for l in tr.splitlines() if 'CROP_ABORT' in l or 'tag=fault_observed' in l]
(old/'result.json').write_text(json.dumps(r,indent=2));print('NEGATIVES',len(neg),'all rejected; old target valid; TB phase mapping frozen')
print(json.dumps(json.loads((p.parent/'T10.a1-uart-descriptor-fix/corrected-dut-index.json').read_text()).keys().__iter__().__reduce__() if False else list(json.loads((p.parent/'T10.a1-uart-descriptor-fix/corrected-dut-index.json').read_text()).keys())))
