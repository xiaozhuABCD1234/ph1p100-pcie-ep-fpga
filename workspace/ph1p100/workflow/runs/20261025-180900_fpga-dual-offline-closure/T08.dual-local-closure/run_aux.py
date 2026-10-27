from pathlib import Path
import argparse,json
import run_t08
from r10f_oracle import check_r10f
def main():
 p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--out',type=Path,required=True);p.add_argument('--compile',action='store_true');a=p.parse_args()
 if a.compile:run_t08.compile_candidate(a.build);print('AUX_COMPILE_OK',flush=True)
 all_results=[]
 for top,marker in [('tb_dual_contract','CONTRACT_PASS'),('tb_production_sync_legacy','T08_PASS')]:
  out=a.out/top;out.mkdir(parents=True,exist_ok=True)
  args=[run_t08.TOOLS/'vsim.exe','-c','-modelsimini',a.build/'modelsim.ini','-lib',a.build/'work',top,'+CASE=0','-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0']
  r=run_t08.command(args,out,out/'vsim.log',300)
  text=(out/'vsim.log').read_text(encoding='utf-8',errors='replace')
  r['pass']=r['exit_code']==0 and not r['timeout'] and marker in text and '** Fatal' not in text and '** Error' not in text
  if r['pass'] and top.endswith('legacy'):
   pubs=[x.split() for x in (out/'events.log').read_text().splitlines() if x.startswith('PUB ')]
   assert len(pubs)==6,'default-disabled original normal case publishes three per camera'
   for x in pubs:
    cam,seq,fid=int(x[3]),int(x[4]),int(x[7]);blob=bytes(int(v,16) for v in (out/f'frame_{cam}_{seq}.hex').read_text().split());check_r10f(blob,cam,seq,fid)
   r['independent_frames']=len(pubs)
  (out/'aux-result.json').write_text(json.dumps(r,indent=2),encoding='utf-8');all_results.append(r)
  print(json.dumps({'top':top,'pass':r['pass'],'seconds':r['elapsed_seconds']}),flush=True)
  if not r['pass']:break
 (a.out/'aux-results.json').write_text(json.dumps(all_results,indent=2),encoding='utf-8')
 return 0 if len(all_results)==2 and all(r['pass'] for r in all_results) else 1
if __name__=='__main__':raise SystemExit(main())
