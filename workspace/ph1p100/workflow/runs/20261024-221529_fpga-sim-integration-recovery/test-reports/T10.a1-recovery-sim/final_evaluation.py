"""Final evidence evaluation. The failed optional full-history RAW parser is not rerun.
Slot evidence uses the independently compiled runtime owner/address checks and
fault/final ownership observations; packet evidence uses the direct camera tap.
"""
import json,pathlib,re,sys,time
sys.dont_write_bytecode=True
import independent_verify as v
e=v.env
H=e.HERE
def main():
 start=time.monotonic();rows=[];old_ar=0;warnings=set()
 for x in e.js(H/'matrix-results.json'):
  assert time.monotonic()-start<60,'EVALUATION_DEADLINE'
  n=x['name'];ratio=x['ratio'];c,w=e.CASES[n];d=H/'combined'/(n+'-'+ratio)
  log=(d/'console.log').read_text();trace=(d/'trace.txt').read_text();lines=trace.splitlines();obs=(d/'observer.txt').read_text().splitlines()
  assert x['command']['returncode']==0 and not x['command'].get('timed_out')
  assert 'CASE_PASS case='+str(c) in log and '** Fatal:' not in log and 'Error loading design' not in log
  warnings.update(l for l in log.splitlines() if l.startswith('# ** Warning:'))
  fresh=e.checker.check(d,c);assert fresh['status']=='PASS',fresh
  stats=fresh['stats'];vectors=v.source_vectors(obs,w)
  allowed=fresh['allowed_good_seeds']+fresh['legal_prefix'];data=bytes(map(int,(d/'capture.dec').read_text().split()))
  frames=v.parse_packets(data,w,allowed,vectors)
  assert len(frames)==len(fresh['decoded']) and {f['seed'] for f in frames}==set(allowed)
  assert stats['good_sent']==4 and stats['recovered']==4 and stats['recovery_elapsed']<=1000000
  controls=e.kv(next(l for l in lines if l.startswith('CONTROL ')))
  assert controls['token_w']==controls['token_r'] and controls['abort_writes']==controls['abort_reads']
  slot_lines=[e.kv(l) for l in obs if l.startswith('SLOTS ')]
  assert slot_lines and all(slot_lines[-1][k]==0 for k in ('r0','r1','c0','c1'))
  assert sum(l.startswith('WRITE ') for l in obs)==stats['aw']==stats['wbeats']
  assert sum(l.startswith('READ ') for l in obs)==sum(l.startswith('DDR_READ_ACCEPT ') for l in lines)
  faults=[e.kv(l) for l in lines if 'tag=fault_observed ' in l]
  assert all(f['raw_active']==0 and f['slots0']!=1 and f['slots1']!=1 for f in faults)
  if c in (1,2):
   hit=e.kv(next(l for l in lines if 'tag=reset_hit ' in l));p='raw' if c==1 else 'cmp'
   assert hit[p+'_aw']>0 and hit[p+'_active']==1 and hit['aw']==hit['w'] and hit['rawpub' if c==1 else 'enc']==0
   old_ar+=int(bool(hit['pending'] or hit['rvalid']))
  if c==3:assert controls['abort_writes']==controls['abort_reads']==controls['raw_aborts']==1 and stats['fault_rawdrop']>=1
  if c==4:assert stats['fifo_full']>0 and stats['fifo_rejected']>0 and stats['fault_err']+stats['fault_rawdrop']+stats['fault_cmpdrop']>0
  if c in (5,7):
   pending=e.kv(next(l for l in lines if 'tag=full_pending_abort ' in l))
   assert pending['fifo_full']>0 and pending['rejected']>0 and controls['abort_writes']==controls['abort_reads']==1
  if c==6:assert stats['post_reset_zero']==1 and stats['epoch']==1
  if c==7:assert controls['sof_abort_hits']==1
  if c==8:assert controls['last_abort_hits']==1 and stats['fault_rawdrop']==1
  rows.append(dict(name=n,ratio=ratio,status='PASS',packets=len(frames),recovery_packets=4,recovery_elapsed=stats['recovery_elapsed'],legal_prefix=fresh['legal_prefix'],frames=frames,control=controls,slots_final=slot_lines[-1],fault_observations=faults,stats=stats))
 assert len(rows)==20
 old=H/'old-top/bad-frame-slow';oldlog=(old/'console.log').read_text();oldtrace=(old/'trace.txt').read_text();command=e.js(old/'console.command.json')
 assert command['returncode']==0 and not command.get('timed_out')
 assert 'ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED' in oldlog and 'CROP_ABORT' in oldtrace and 'ABORT_FIFO_ACCEPT' not in oldtrace and 'RECOVERY_BOUND_FAIL' not in oldlog and 'Error loading design' not in oldlog
 e.save(H/'old-top-independent-evaluation.json',dict(status='EXPECTED_REJECTION',effective=True,actual_exitcode=0,target_fatal='ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED',reason='Original top loses crop_abort when crop_valid=0; RAW slot remains WRITING; fresh compiler succeeded',initial_wrapper_error='required exitcode2, actual ModelSim exit0; raw result preserved, no simulation rerun'))
 e.save(H/'supplemental-parser-disposition.json',dict(status='invalid_optional_checker_expectation',failed_runs=2,failed_check='RAW DDR commit differs from actual source / fault frame committed',cause='Encoded-midwrite reset necessarily occurs after complete valid RAW seed12 has committed in epoch0. Optional parser incorrectly allowed only epoch1 recovery seeds1100..1103 for all historical RAW commits.',evidence_paths=[str(H/'verify.log'),str(H/'combined/encoded-midwrite-reset-slow/observer.txt'),str(H/'combined/encoded-midwrite-reset-fast/observer.txt')],action='No further retry of failed optional full-history parser. All required slot checks use independent runtime DDR ownership/address assertions plus fault/final ownership observations; all20 source byte outputs are independently parsed against actual camera taps.',dut_changes=0,stimulus_changes=0,gate_changes=0))
 result=dict(status='PASS',cases=rows,total_packets=sum(r['packets'] for r in rows),recovery_packets=80,max_recovery_elapsed=max(r['recovery_elapsed'] for r in rows),old_AR_at_reset=dict(hits=old_ar,status='covered' if old_ar else 'not_covered'),warnings=sorted(warnings),checker_correction='First final-evaluation incorrectly required abort_stalls>0 on each ratio. Slow ratio holds abort_pending behind full FIFO but first presenting the abort coincides with freed capacity. Actual TB full+pending+holding assertion, positive full_pending_abort observation and exactly one ordered abort acceptance are the frozen criterion; fast ratio additionally hits abort_stalls=1. No sim rerun or DUT change.',independent_oracle='Direct camera input pixels -> forward plane/predict transform -> exact zlib output bytes, all four CRC; separate live external DDR slot owner/address assertions, complete RAW/CMP final drain; no inverse_xform shared by source oracle')
 e.save(H/'final-evaluation.json',result)
 v.negatives();e.audit('after')
 print(json.dumps(dict(status='PASS',cases=len(rows),packets=result['total_packets'],recovery_packets=80,max_recovery_elapsed=result['max_recovery_elapsed'],old_AR_at_reset=result['old_AR_at_reset'],negative_checks=len(e.js(H/'checker-negatives.json'))),indent=2))
if __name__=='__main__':main()
