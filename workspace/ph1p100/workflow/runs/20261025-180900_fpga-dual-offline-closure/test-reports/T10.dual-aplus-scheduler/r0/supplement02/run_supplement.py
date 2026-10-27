from helper import *
def snapshot():
 m=S/'static-closeout02/manifest-cmp-stall-fix01.json';d=json.loads(m.read_text(encoding='utf-8-sig'));rows=[]
 for group in ('files','static_outputs','tools'):
  for f in d[group]:
   p=Path(f['path']);actual=sha(p);assert actual==f['sha256'],str(p);rows.append({'path':str(p),'sha256':actual})
 assert sha(m)=='5db2b0ddf42c60426dd5a10a72614abf2bbe2306a3464be01474f7683e87f03b'
 assert sha(R/'test-reports/T10.dual-aplus-scheduler-r0-integrated.md')=='123a68cb9b415292e5a230eda143b894093edc368133dc41055fed0256dd5855'
 (O/'input-before.json').write_text(json.dumps({'manifest':str(m),'sha256':sha(m),'rows':rows},indent=2))
def main():
 assert not (O/'execute-started.json').exists(),'No compile/case retry authorized';(O/'execute-started.json').write_text(json.dumps({'time':datetime.datetime.now().astimezone().isoformat()}))
 snapshot();src=[S/'candidate/a1_deflate_core.v',S/'candidate/a1_frame_top.v',S/'candidate/dual_aplus_scheduler.sv',O/'tb_same_edge.sv']
 for name,args in [('vmap-create',[BIN/'vmap.exe','-c']),('vlib',[BIN/'vlib.exe',O/'work']),('vmap',[BIN/'vmap.exe','-modelsimini',O/'modelsim.ini','work',O/'work'])]:
  rec,msg=run(args,O/(name+'.log'),60);assert rec['exit_code']==0,msg
 (O/'compiled-source.json').write_text(json.dumps([{'path':str(p),'sha256':sha(p)} for p in src],indent=2))
 rec,msg=run([BIN/'vlog.exe','-modelsimini',O/'modelsim.ini','-work','work','-sv']+src,O/'compile.log',300)
 assert rec['exit_code']==0 and 'Errors: 0' in msg,msg
 c=O/'matrix';c.mkdir()
 with (c/'headers.hex').open('w') as f:
  for cam in range(2):
   for seq in range(1,9):
    b=mkheader(64,8,cam,seq,0);f.write('@%x\n'%((cam*32+seq)*128));f.write(' '.join('%02x'%v for v in b)+'\n')
 (c/'run.do').write_text('onbreak {quit -code 2}\nonerror {quit -code 2}\nrun -all\nquit -code 0\n')
 (c/'parameters.json').write_text(json.dumps({'W':64,'H':8,'CASE':10,'PREP':0,'PRED':0,'expected_frames':8,'rows':[[0,0,1,1,1,2],[0,1,3,0,0,4],[1,0,5,0,1,6],[1,1,7,1,0,8]],'cycle_watchdog':90000000},indent=2))
 args=[BIN/'vsim.exe','-c','-modelsimini',O/'modelsim.ini','-wlf',c/'sim.wlf','-l',c/'transcript.log','-voptargs=+acc','work.tb_same_edge','-gW=64','-gH=8','-gCASE=10','-gPREP=0','-gPRED=0',f'+OUT={c.as_posix()}',f'+HDR={(c/"headers.hex").as_posix()}','-do','do '+(c/'run.do').as_posix()]
 rec,msg=run(args,c/'console.log',300)
 result={'status':'fail','exit_code':rec['exit_code'],'log':str(c/'console.log')}
 try:
  assert rec['exit_code']==0 and 'TB_DONE' in msg and 'ASSERT_FAIL' not in msg and '** Fatal' not in msg,'completion/assertions'
  assert msg.count('HIT DESCRIPTOR_RELEASE_SAME_EDGE row=')==4 and msg.count('HIT SAME_EDGE_ROW_CLOSED row=')==4 and 'HIT SAME_EDGE_MATRIX_ALL4_GOOD8' in msg,'exact matrix hits'
  result['decoded_frames']=oracle(c,64,8,8);result['status']='pass';result['same_edge_hits']=4
 except Exception as ex:result['reason']=str(ex);result['traceback']=traceback.format_exc()
 (c/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
 if result['status']!='pass':sys.exit(1)
if __name__=='__main__':main()
