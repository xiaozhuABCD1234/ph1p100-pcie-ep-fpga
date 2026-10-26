"""Reproducible isolated ModelSim run; all child commands have hard deadlines."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, sys, time
H=Path(__file__).resolve().parent
TOOLS=Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')

def command(args,cwd,log,timeout=300):
    started=time.time()
    args=[a.as_posix() if isinstance(a,Path) else str(a) for a in args]
    # Deadline termination is scoped to the exact owned PID and its descendants.
    with log.open('w',encoding='utf-8') as out:
        out.write(json.dumps({'args':list(map(str,args)),'cwd':str(cwd),'timeout_seconds':timeout})+'\n');out.flush()
        try:
            p=subprocess.Popen(list(map(str,args)),cwd=cwd,stdout=out,stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW)
            code=p.wait(timeout=timeout)
            result={'exit_code':code,'timeout':False,'owned_pid':p.pid}
        except subprocess.TimeoutExpired:
            if p.poll() is None:
                subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=out,stderr=subprocess.STDOUT,
                    timeout=15,check=False,creationflags=subprocess.CREATE_NO_WINDOW)
            p.wait(timeout=15)
            result={'exit_code':p.returncode,'timeout':True,'owned_pid':p.pid}
        result.update(elapsed_seconds=time.time()-started,log=str(log),command=list(map(str,args)),cwd=str(cwd))
        out.write('\nCOMMAND_RESULT '+json.dumps(result)+'\n')
    return result

def compile_candidate(out):
    out.mkdir(parents=True,exist_ok=True)
    ini=out/'modelsim.ini'
    ini.write_text('[Library]\nwork = '+(out/'work').as_posix()+'\n',encoding='ascii')
    results=[command([TOOLS/'vlib.exe',out/'work'],out,out/'vlib.log',60)]
    excludes={'crc16_upd4.v','crc32_upd4.v'}
    files=[p for p in (H/'candidate/rtl').rglob('*.v') if 'rc_side' not in p.parts and p.name not in excludes]
    files += [H/'tb_tester_edges.sv',H/'tb_repair_matrix.sv',H/'tb_dual_contract.sv',H/'tb_production_sync_legacy.sv',H/'dual_local_closure.v',H/'sync_i2c_config.v',H/'sync_frame_gate.v',H/'vendor_env.sv',H/'sensor_i2c.sv',H/'tb_production_sync.sv']
    includes=sorted({p.parent for p in files})
    args=[TOOLS/'vlog.exe','-sv','-modelsimini',ini,'-work',out/'work','+define+MIPI_PHY_SIM_STUB']
    args += ['+incdir+'+p.as_posix() for p in includes]
    args += files
    (out/'sources.json').write_text(json.dumps([str(p) for p in files],indent=2),encoding='utf-8')
    results.append(command(args,out,out/'vlog.log'))
    (out/'compile-result.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
    assert all(r['exit_code']==0 and not r['timeout'] for r in results), 'compile command failed'
    text=(out/'vlog.log').read_text(encoding='utf-8',errors='replace')
    assert 'Errors: 0' in text and '** Error' not in text, 'compile errors or missing completion marker'
    return results

def run_case(build,out,case,mutate=False):
    out.mkdir(parents=True,exist_ok=True)
    args=[TOOLS/'vsim.exe','-c','-modelsimini',build/'modelsim.ini','-lib',build/'work',
          'tb_production_sync',f'+CASE={case}']
    if mutate:args+=['+MUTATE_ROLE']
    args+=['-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0']
    r=command(args,out,out/'vsim.log')
    text=(out/'vsim.log').read_text(encoding='utf-8',errors='replace')
    r['sim_pass']=r['exit_code']==0 and 'T08_PASS' in text and not any(x in text for x in ['** Fatal','T08_FAIL','** Error'])
    (out/'sim-result.json').write_text(json.dumps(r,indent=2),encoding='utf-8')
    return r

if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('action',choices=['compile','case']);a.add_argument('--build',type=Path,required=True)
    a.add_argument('--out',type=Path);a.add_argument('--case',type=int,default=0);a.add_argument('--mutate',action='store_true')
    p=a.parse_args()
    if p.action=='compile': print(json.dumps(compile_candidate(p.build)))
    else:
        result=run_case(p.build,p.out,p.case,p.mutate);print(json.dumps(result));sys.exit(0 if result['sim_pass'] else 1)
