"""Bind final local checks to the unchanged candidate; no simulation invocation."""
import pathlib,json,re,hashlib,datetime
P=pathlib.Path(__file__).resolve().parent.parent;E=P/'evidence-resume01'
def summarize():
 summary={};total=0
 for name,w,h,n in [('small8x2',8,2,14),('odd8x3',8,3,14),('small64x8',64,8,14),('prep8x3',8,3,14),('capacity',8,2,0),('phase',8,2,0),('faults',64,8,4),('full',1920,1080,2)]:
  c=E/name;r=json.loads((c/'checker.json').read_text());assert r['frames']==n
  txt=(c/'console.log').read_text(errors='replace');assert 'TB_DONE' in txt and 'ASSERT_FAIL' not in txt
  assert 'Warnings: 0' in txt and 'Errors: 0' in txt,name+' diagnostics'
  events=(c/'events.log').read_text();frames=[]
  for cam,seq,status,cy,words,groups in re.findall(r'FRAME cam=(\d+) seq=(\d+) status=(\d+) cycles=(\d+) words=(\d+) groups=(\d+)',events):
   record=dict(camera=int(cam),seq=int(seq),status=int(status),cycles=int(cy),ar_words=int(words),groups=int(groups));frames.append(record)
   if record['status']==0:
    raw=w*h*5//4;dma=((128+raw+4095)//4096)*4096
    assert record['ar_words']==dma//32,(name,record)
    assert record['groups']==raw//5,(name,record)
    record.update(raw_bytes=raw,dma_bytes=dma,mb_per_s_at_100mhz=raw/(record['cycles']*10e-9)/1e6)
  hit=re.findall(r'HIT (.*)',txt)
  if name=='faults':
   for required in ['PERMANENT_R_LOCK','PROTOCOL_LOCK_14','PROTOCOL_LOCK_15','OLD_EPOCH_REJECT','STALE_DUPLICATE_ACK_REJECT RECOVERY_GOOD4']:
    assert required in hit,(name,required)
  if n==14:
   for required in ['CMP_FULL_RAW_HELD','ALTERNATE8 SIMULTANEOUS_AB','HELD_WRONG_CAMERA_OLD_EPOCH_WRONG_SEQ_ACK']:
    assert required in hit,(name,required)
  summary[name]=dict(frames=n,hits=hit,services=frames,stats=re.findall(r'STATS (.*)',events),checker_sha=hashlib.sha256((c/'checker.json').read_bytes()).hexdigest());total+=n
 neg=json.loads((E/'mutant64/negative-control.json').read_text());assert neg['expected_rejection']
 journals=[P/'evidence/commands.jsonl',E/'commands.jsonl'];records=[]
 for j in journals:records.extend(json.loads(x)for x in j.read_text().splitlines())
 counts=dict(compiles=sum(pathlib.Path(r['argv'][0]).name=='vlog.exe'for r in records),case_processes=sum(pathlib.Path(r['argv'][0]).name=='vsim.exe'for r in records))
 counts['faults_attempts']=sum(pathlib.Path(r['argv'][0]).name=='vsim.exe' and any('/faults/'in str(a)or'/faults-retry/'in str(a)for a in r['argv'])for r in records)
 assert counts==dict(compiles=4,case_processes=18,faults_attempts=3),counts
 result=dict(status='developer_local_checks_complete',independent_integrated_verdict=False,time=datetime.datetime.now().isoformat(),total_good_frames=total,counts=counts,cases=summary,negative_control=neg,G0='local_checks',G1='local_checks',G2='not_run',G3='not_run-awaiting_hardware',G4='not_run-awaiting_hardware')
 (E/'summary.json').write_text(json.dumps(result,indent=2));return result
if __name__=='__main__':
 r=summarize();print(json.dumps(dict(status=r['status'],good_frames=r['total_good_frames'],counts=r['counts'],full=r['cases']['full']['services'])))
