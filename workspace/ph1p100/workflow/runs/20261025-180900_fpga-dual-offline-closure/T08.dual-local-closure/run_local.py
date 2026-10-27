"""Finite developer suite: one named compile, explicit scenario list; no retries."""
from pathlib import Path
import argparse,json,sys,time
import run_t08
from check_t08 import check
H=Path(__file__).resolve().parent
def main():
 a=argparse.ArgumentParser();a.add_argument('--build',required=True);a.add_argument('--compile',action='store_true');a.add_argument('--cases',nargs='*',type=int,default=[]);p=a.parse_args()
 build=H/'local'/p.build
 if p.compile:
  run_t08.compile_candidate(build);print('COMPILE_OK '+p.build,flush=True)
 results=[]
 for case in p.cases:
  out=H/'local'/(p.build+'-case'+str(case));r=run_t08.run_case(build,out,case)
  if r['sim_pass']:
   try:o=check(out,case)
   except Exception as e:o={'pass':False,'error':repr(e)}
  else:o={'pass':False,'error':'simulation did not reach required clean marker'}
  (out/'oracle-result.json').write_text(json.dumps(o,indent=2),encoding='utf-8')
  results.append({'case':case,'simulation':r['sim_pass'],'oracle':o['pass'],'seconds':r['elapsed_seconds'],'out':str(out),'error':o.get('error')})
  print(json.dumps(results[-1]),flush=True)
  (H/'local'/('suite-'+p.build+'.json')).write_text(json.dumps(results,indent=2),encoding='utf-8')
  if not r['sim_pass'] or not o['pass']:return 1
 return 0
if __name__=='__main__':sys.exit(main())
