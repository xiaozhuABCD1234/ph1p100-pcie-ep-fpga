import os,sys,pathlib,json,hashlib,subprocess,time,re,struct,zlib,importlib.util,difflib,concurrent.futures
sys.dont_write_bytecode=True
ROOT=pathlib.Path(r'D:\fpga\ph1p100')
RUN=ROOT/'workflow/runs/20261024-221529_fpga-sim-integration-recovery'
DEV=RUN/'T10.a1-abort-cdc-fix'
HERE=pathlib.Path(__file__).resolve().parent
MS=pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
MAN=DEV/'manifest-r0.json'
INDEX=DEV/'corrected-dut-index.json'
manifest=json.loads(MAN.read_text(encoding='utf-8-sig'))
index=json.loads(INDEX.read_text(encoding='utf-8-sig'))
CASES={'clean':(0,8),'clean32':(0,32),'raw-midwrite-reset':(1,32),'encoded-midwrite-reset':(2,32),'bad-frame':(3,8),'overflow':(4,8),'full-abort':(5,8),'pending-reset':(6,8),'sof-abort':(7,8),'last-skid-abort':(8,8)}
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def save(name,obj): (HERE/name).write_text(json.dumps(obj,ensure_ascii=False,indent=2),encoding='utf-8')
def gather(obj,found):
 if isinstance(obj,dict):
  if 'sha256' in obj:
   p=obj.get('path',obj.get('frozen'))
   if p:
    assert pathlib.Path(p).is_file(),('missing frozen file',p)
    k=str(pathlib.Path(p).resolve()); expected=obj['sha256'].lower()
    if k in found: assert found[k]==expected,(k,'conflicting frozen hash')
    found[k]=expected
  for v in obj.values(): gather(v,found)
 elif isinstance(obj,list):
  for v in obj:gather(v,found)
def snapshot(label):
 expected={};gather(manifest,expected);gather(index,expected)
 inputs=json.loads((RUN/'planning-input-manifest.json').read_text(encoding='utf-8-sig'))
 gather(inputs,expected)
 for n in ['recovery-dut-binding-resume01.json','T10.a1-recovery-sim/manifest-r0.json','T10.a1-recovery-sim/resume01/manifest-resume01.json','T10.a1-uart-descriptor-fix/manifest-r0.json','T10.a1-abort-cdc-fix/protection-before.json']:
  p=RUN/n;gather(json.loads(p.read_text(encoding='utf-8-sig')),expected);expected[str(p.resolve())]=sha(p)
 for p in [MAN,INDEX,RUN/'dispatch-abort-cdc-fix-r0.json',RUN/'planner-abort-cdc-fix.md']:
  expected[str(p.resolve())]=sha(p)
 # Original source locations are separately protected in addition to frozen copies.
 for row in inputs['files']:
  p=pathlib.Path(row['source'])
  if p.is_file(): expected.setdefault(str(p.resolve()),sha(p))
 actual={p:sha(p) for p in expected}
 mismatches=[dict(path=p,expected=h,actual=actual[p]) for p,h in expected.items() if h!=actual[p]]
 save('hashes-'+label+'.json',dict(files=actual,expected=expected,mismatches=mismatches,count=len(actual)))
 assert not mismatches,mismatches
 if label=='after':
  before=json.loads((HERE/'hashes-before.json').read_text(encoding='utf-8'))['files']
  drift=[p for p,h in before.items() if actual.get(p)!=h]
  save('input-drift.json',dict(before_count=len(before),after_count=len(actual),drift=drift))
  assert not drift,drift
 return len(actual)
def execute(argv,folder,label,timeout=300):
 folder.mkdir(parents=True,exist_ok=True)
 argv=[p.as_posix() if isinstance(p,pathlib.Path) else str(p) for p in argv]
 env=os.environ.copy();env['PYTHONDONTWRITEBYTECODE']='1';env['PYTHONIOENCODING']='utf-8'
 rec=dict(argv=argv,cwd=str(HERE),timeout_seconds=timeout)
 start=time.monotonic()
 with (folder/(label+'.log')).open('w',encoding='utf-8') as log:
  p=subprocess.Popen(argv,cwd=HERE,env=env,stdout=log,stderr=subprocess.STDOUT);rec['owned_pid']=p.pid
  try: rec['exit_code']=p.wait(timeout=timeout)
  except subprocess.TimeoutExpired:
   rec['timed_out']=True
   subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=log,stderr=subprocess.STDOUT,timeout=15)
   p.wait(timeout=15);rec['exit_code']=p.returncode
 rec['elapsed_seconds']=round(time.monotonic()-start,3)
 (folder/(label+'.command.json')).write_text(json.dumps(rec,indent=2),encoding='utf-8')
 return rec
OBSERVER=r'''
`ifdef CORRECTED
 integer tester_slot_releases=0;
 integer tester_abort_events=0;
 integer tester_begin_blocks=0;
 integer tester_abort_slot;
 always @(posedge clk_a1) if(rst_n) begin
  if(dut.fifo_valid&&dut.e_abort) begin
   tester_abort_events=tester_abort_events+1;
   if(dut.u_raw_store.wr_valid||dut.u_raw_store.wr_begin) $fatal(1,"TESTER_ABORT_NOT_DOMINANT");
  end
  if(dut.raw_abort) begin
   if(dut.u_raw_store.wr_active) begin
    tester_abort_slot=dut.u_raw_store.wr_slot;
    if(dut.u_raw_store.slot_st[tester_abort_slot]!==2'd1) $fatal(1,"TESTER_ABORT_SLOT_NOT_WRITING");
    #0.001;
    if(dut.u_raw_store.wr_active||dut.u_raw_store.slot_st[tester_abort_slot]!==2'd0||dut.skid_valid) $fatal(1,"TESTER_SLOT_NOT_RELEASED");
    tester_slot_releases=tester_slot_releases+1;
    $fwrite(ft,"TESTER_SLOT_RELEASE cycles=%0d slot=%0d count=%0d\n",cycles,tester_abort_slot,tester_slot_releases);
   end
  end
 end
`endif
'''
def prepare():
 assert manifest['stopped_modifying'] and manifest['active_commands']==0 and manifest['frozen']
 assert len(index['files'])==8 and sum(x['sha256']!=x['preserved_binding_sha256'] for x in index['files'])==1
 snapshot('before')
 original=pathlib.Path(next(x['source_path'] for x in index['files'] if x['logical_name']=='camera_a1_uart_top.v'))
 candidate=pathlib.Path(index['rtl_paths']['camera_a1_uart_top.v'])
 diff=''.join(difflib.unified_diff(original.read_text().splitlines(True),candidate.read_text().splitlines(True),fromfile=str(original),tofile=str(candidate)))
 (HERE/'independent-top.diff').write_text(diff,encoding='utf-8')
 tb=(DEV/'tb_recovery.sv').read_text();assert tb.count('endmodule')==1
 (HERE/'tb_tester.sv').write_text(tb.replace('endmodule',OBSERVER+'\nendmodule'),encoding='utf-8')
 (HERE/'run.do').write_text('onerror {quit -code 2 -f}\nrun -all\nquit -f\n')
 save('tester-input-binding.json',dict(manifest_path=str(MAN),manifest_sha256=sha(MAN),index_path=str(INDEX),index_sha256=sha(INDEX),original_tb_sha256=sha(DEV/'tb_recovery.sv'),compiled_tb_sha256=sha(HERE/'tb_tester.sv'),observer_only_addition=True))
 tools=[]
 for exe in ['vlib.exe','vlog.exe','vsim.exe']:
  tools.append(dict(path=str(MS/exe),sha256=sha(MS/exe)))
 tools.append(dict(python=sys.version,zlib=zlib.ZLIB_VERSION,zlib_runtime=zlib.ZLIB_RUNTIME_VERSION))
 save('tool-identity.json',tools)
 execute([MS/'vsim.exe','-version'],HERE,'vsim-version',60)
 execute(['git','status','--short','--untracked-files=no'],HERE,'git-status-before',60)
 print('PREPARED',flush=True)
def compile(mode):
 folder=HERE/mode;folder.mkdir(exist_ok=True)
 ini=folder/'modelsim.ini';ini.write_text('[Library]\nwork = '+(folder/'lib').as_posix()+'\n[vsim]\nResolution = ps\n')
 a=execute([MS/'vlib.exe',folder/'lib'],folder,'vlib');assert a['exit_code']==0,a
 paths=dict(index['rtl_paths'])
 if mode=='old': paths['camera_a1_uart_top.v']=next(x['source_path'] for x in index['files'] if x['logical_name']=='camera_a1_uart_top.v')
 args=[MS/'vlog.exe','-sv','-modelsimini',ini,'-work','work']
 if mode=='corrected':args+=['+define+CORRECTED']
 args += [pathlib.Path(p) for p in paths.values()]+[DEV/'ddr_recovery_model.sv',HERE/'tb_tester.sv']
 b=execute(args,folder,'vlog');log=(folder/'vlog.log').read_text(errors='replace')
 assert b['exit_code']==0 and 'Errors: 0, Warnings: 0' in log,log[-4000:]
 (folder/'compile-result.json').write_text(json.dumps(dict(status='PASS',source_paths=paths,source_hashes={n:sha(p) for n,p in paths.items()},tb_sha256=sha(HERE/'tb_tester.sv'),commands=[a,b]),indent=2))
 print('COMPILE_PASS',mode,flush=True)
def camera_rows(seed,w):
 state=seed^0x12345678;rows=[]
 for y in range(4):
  row=[]
  for g in range((w+8)//4):
   for amount,left in [(13,True),(17,False),(5,True)]:state=(state ^ (state<<amount if left else state>>amount))&0xffffffff
   row.extend((state>>shift)&1023 for shift in (0,10,20,22))
  if y>=2:rows.append(row[4:w+4])
 return rows
def pack(samples):
 out=bytearray()
 for start in range(0,len(samples),4):
  q=samples[start:start+4];out.extend(v//4 for v in q);out.append(sum((v%4)<<(2*j) for j,v in enumerate(q)))
 return bytes(out)
def source_vectors(seed,w):
 rows=camera_rows(seed,w);raw=pack([v for row in rows for v in row]);diff=[]
 for y,parity in [(0,0),(0,1),(1,0),(1,1)]:
  plane=rows[y][parity::2];diff += [plane[0]]+[(plane[j]-plane[j-1])%1024 for j in range(1,len(plane))]
 return raw,pack(diff)
def independent_packets(data,w,allowed):
 off=0;seeds=[];ids=[];frames=[]
 while off<len(data):
  assert len(data)-off>=44,'independent partial/tail header'
  h=data[off:off+44];f=struct.unpack('<IBBHIHHIIIIIII',h)
  magic,ver,flags,hlen,fid,fw,fh,rawlen,xlen,slen,rawcrc,xfcrc,scrc,hcrc=f
  assert (magic,ver,flags,hlen,fw,fh,rawlen,xlen)==(0x31553141,1,3,44,w,2,w*5//2,w*5//2),'independent header'
  assert 0<slen<=rawlen+64 and off+44+slen<=len(data),'independent payload length'
  p=data[off+44:off+44+slen]
  assert zlib.crc32(h[:40])==hcrc and zlib.crc32(p)==scrc,'independent transport CRC'
  dec=zlib.decompressobj();xf=dec.decompress(p)+dec.flush()
  assert dec.eof and not dec.unused_data and not dec.unconsumed_tail,'independent zlib trailing/EOF'
  match=[]
  for seed in allowed:
   raw,forward=source_vectors(seed,w)
   if forward==xf and zlib.crc32(raw)==rawcrc:match.append(seed)
  assert len(match)==1,'independent source/forward transform bytes/RAW CRC'
  seed=match[0];assert len(xf)==xlen and zlib.crc32(xf)==xfcrc,'independent transform CRC'
  assert seed not in seeds and fid not in ids,'independent duplicate'
  assert not ids or fid>ids[-1],'independent out-of-order ID'
  seeds.append(seed);ids.append(fid);frames.append(dict(seed=seed,frame_id=fid,packet_bytes=44+slen,raw_sha256=hashlib.sha256(source_vectors(seed,w)[0]).hexdigest()))
  off+=44+slen
 return frames
def checker():
 spec=importlib.util.spec_from_file_location('frozen_checker',DEV/'check_recovery.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
def run(mode,name,ratio):
 case,w=CASES[name];folder=HERE/mode/(name+'-'+ratio);folder.mkdir(exist_ok=True)
 args=[MS/'vsim.exe','-c','-modelsimini',HERE/mode/'modelsim.ini','-wlf',folder/'case.wlf','-l',folder/'transcript.log','work.tb_recovery','-gW='+str(w),'-gH=2','-gFIFO_AW='+str(4 if w==32 else 2),'-gCAM_HALF='+('7.0' if ratio=='slow' else '1.85'),'-gA1_PHASE='+('1.7' if ratio=='slow' else '0.91'),'-gMAX_CYCLES=1500000','+CASE='+str(case),'+OUT='+(folder/'capture.dec').as_posix(),'+TRACE='+(folder/'trace.txt').as_posix(),'+STAT='+(folder/'stats.txt').as_posix(),'-do','do '+(HERE/'run.do').as_posix()]
 command=execute(args,folder,'console');log=(folder/'console.log').read_text(errors='replace');trace=(folder/'trace.txt').read_text(errors='replace')
 if mode=='old':
  effective=command['exit_code']==0 and 'ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED' in log and 'CROP_ABORT' in trace and 'ABORT_FIFO_ACCEPT' not in trace and 'Error loading design' not in log and 'CASE_PASS' not in log
  result=dict(status='EXPECTED_REJECTION' if effective else 'FAIL',effective_original_top_negative=effective,command=command,trace_tail=trace[-2500:])
 else:
  try:
   result=checker().check(folder,case)
   assert result['status']=='PASS',result['errors']
   assert command['exit_code']==0 and 'Error loading design' not in log
   data=bytes(map(int,(folder/'capture.dec').read_text().split()))
   frames=independent_packets(data,w,result['allowed_good_seeds']+result['legal_prefix'])
   assert len(frames)==result['stats']['exported']
   ctl={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',next(l for l in trace.splitlines() if l.startswith('CONTROL ')))}
   assert ctl['token_w']==ctl['token_r'],'FIFO tokens left after drain'
   if case in (3,5,7,8):assert ctl['abort_writes']==ctl['abort_reads']==ctl['raw_aborts']==1,ctl
   if case in (3,8):assert 'TESTER_SLOT_RELEASE' in trace,'no independently observed actual slot release'
   if case in (4,5,7):assert result['stats']['fifo_full']>0 and result['stats']['fifo_rejected']>0
   if case==4:assert ctl['abort_writes']==ctl['abort_reads'] and ctl['abort_writes']>=1
   if case==6:assert ctl['abort_writes']==ctl['abort_reads']==ctl['raw_aborts']==0 and result['stats']['post_reset_zero']==1
   if case==7:assert ctl['sof_abort_hits']==1
   if case==8:assert ctl['last_abort_hits']==1
   result.update(independent_forward_packets=frames,control=ctl,independent_slot_releases=trace.count('TESTER_SLOT_RELEASE'),command=command)
  except Exception as e:result=dict(status='FAIL',error=repr(e),command=command)
 result.update(mode=mode,name=name,ratio=ratio)
 (folder/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
 print(mode,name,ratio,result['status'],result.get('error',''),flush=True)
 return result
def matrix():
 jobs=[(n,r) for r in ('slow','fast') for n in CASES]
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
  results=list(pool.map(lambda job:run('corrected',*job),jobs))
 save('matrix-results.json',dict(results=results,status='PASS' if all(x['status']=='PASS' for x in results) else 'FAIL'))
 print('MATRIX_COMPLETE',len(results),flush=True)
def negatives():
 import shutil
 base=HERE/'corrected/clean-slow'
 data=bytes(map(int,(base/'capture.dec').read_text().split()))
 fields=list(struct.unpack('<IBBHIHHIIIIIII',data[:44]));packet_end=44+fields[9]
 def header_change(offset):
  changed=bytearray(data);value=struct.unpack_from('<I',changed,offset)[0]^1
  struct.pack_into('<I',changed,offset,value)
  if offset!=40:struct.pack_into('<I',changed,40,zlib.crc32(changed[:40]))
  return bytes(changed)
 f=fields[:];pay=data[44:packet_end]+zlib.compress(b'x');f[9]=len(pay);f[12]=zlib.crc32(pay)
 h=bytearray(struct.pack('<IBBHIHHIIIIIII',*f));struct.pack_into('<I',h,40,zlib.crc32(h[:40]));concat=bytes(h)+pay+data[packet_end:]
 variants=[('tail-byte',data+b'\xaa','tail/partial header'),('duplicate-packet',data+data[:packet_end],'duplicate frame/source'),('truncated-payload',data[:-1],'truncated payload'),('header-CRC',header_change(40),'header CRC'),('stream-CRC',header_change(36),'stream CRC'),('transform-CRC',header_change(32),'transform length/CRC'),('raw-CRC',header_change(28),'raw length/CRC'),('valid-zlib-concatenation',concat,'strict zlib end/tail')]
 results=[]
 for name,mutated,expected_error in variants:
  folder=HERE/'negatives'/name;folder.mkdir(parents=True,exist_ok=True)
  for n in ['stats.txt','console.log','trace.txt']:shutil.copy2(base/n,folder/n)
  (folder/'capture.dec').write_text('\n'.join(map(str,mutated))+'\n')
  stat=(folder/'stats.txt').read_text();stat=re.sub(r'bytes=\d+','bytes='+str(len(mutated)),stat);(folder/'stats.txt').write_text(stat)
  result=checker().check(folder,0);assert result['status']=='FAIL' and expected_error in result['errors'],(name,result)
  independent_rejected=False
  try: independent_packets(mutated,8,[1000,1001,1002,1003])
  except (AssertionError,zlib.error,struct.error,IndexError):independent_rejected=True
  assert independent_rejected,name
  result.update(name=name,expected_error=expected_error,independent_rejected=True)
  (folder/'result.json').write_text(json.dumps(result,indent=2));results.append(result)
 reset=HERE/'corrected/raw-midwrite-reset-slow';old=HERE/'corrected/clean32-slow'
 folder=HERE/'negatives/CRC-valid-old-epoch';folder.mkdir(parents=True,exist_ok=True)
 for n in ['stats.txt','console.log','trace.txt']:shutil.copy2(reset/n,folder/n)
 shutil.copy2(old/'capture.dec',folder/'capture.dec')
 result=checker().check(folder,1);assert result['status']=='FAIL' and 'wrong source / stale epoch / corrupt bytes' in result['errors'],result
 independent_rejected=False
 try:independent_packets(bytes(map(int,(folder/'capture.dec').read_text().split())),32,[1100,1101,1102,1103])
 except AssertionError:independent_rejected=True
 assert independent_rejected
 result.update(name='CRC-valid-old-epoch',independent_rejected=True);(folder/'result.json').write_text(json.dumps(result,indent=2));results.append(result)
 for name,(case,w) in CASES.items():
  if case==0:continue
  result=checker().check(HERE/'corrected'/(name+'-slow'),case,inject_override=0)
  assert result['status']=='FAIL' and 'fault trigger absent' in result['errors'],(name,result)
  result.update(name=name+'-trigger-deleted');results.append(result)
 assert len(results)==17
 save('checker-negatives.json',dict(status='PASS',count=len(results),results=results))
 print('CHECKER_NEGATIVES_PASS',len(results),flush=True)
if __name__=='__main__':
 action=sys.argv[1]
 if action=='prepare':prepare()
 elif action=='compile':compile(sys.argv[2])
 elif action=='matrix':matrix()
 elif action=='run':run(*sys.argv[2:])
 elif action=='after':snapshot('after')
 elif action=='negatives':negatives()
