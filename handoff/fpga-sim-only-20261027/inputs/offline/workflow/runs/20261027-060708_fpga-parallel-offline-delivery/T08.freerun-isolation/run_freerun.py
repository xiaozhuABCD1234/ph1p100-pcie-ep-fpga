"""T08-only isolated runner. No RTL copying, device use or global library mapping."""
from pathlib import Path
import argparse, datetime, hashlib, json, os, subprocess, sys, time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
OLD = ROOT/'workspace/ph1p100/workflow/runs/20261025-180900_fpga-dual-offline-closure/T08.dual-local-closure/r1/mode-fix02'
TOOLS = Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def save(path, data): path.write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')
def mapped(path):
    name = path.replace('\\', '/')
    assert name.startswith('D:/fpga/ph1p100/')
    result = (ROOT/'workspace/ph1p100'/name[len('D:/fpga/ph1p100/'):]).resolve()
    assert result.is_relative_to(OLD.resolve())
    return result

def prepare():
    (HERE/'inputs').mkdir(exist_ok=True)
    manifest = json.loads((OLD/'manifest-mode-fix02.json').read_text(encoding='utf-8-sig'))
    lookup = {e['path'].replace('\\', '/'):e for e in manifest['files']}
    sources = [mapped(x) for x in (OLD/'sources.f').read_text().splitlines() if x.strip()]
    sources += [OLD/'vendor_env.sv']
    headers = [OLD/'candidate/rtl/checked/crc16_upd4.v', OLD/'candidate/rtl/ep_side/ddr/crc32_upd4.v']
    rows = []
    for q in sorted(set(sources+headers)):
        old_name = 'D:/fpga/ph1p100/'+q.relative_to(ROOT/'workspace/ph1p100').as_posix()
        entry = lookup[old_name]
        digest = sha(q)
        assert digest == entry['sha256'], ('source drift', str(q))
        rows.append({'old_path':old_name, 'path':str(q), 'sha256':digest, 'bytes':q.stat().st_size,
                     'role':'simulation_vendor_model' if q.name=='vendor_env.sv' else 'frozen_dut_or_include',
                     'compiled':q in sources, 'old_manifest_sha256':sha(OLD/'manifest-mode-fix02.json')})
    refs=[]
    for name in ['request.md','dev-plan.md','fpga-design-guide.md','input-index.md']:
        q=HERE.parent/name;refs.append({'path':str(q),'sha256':sha(q),'bytes':q.stat().st_size})
    p3=ROOT/'workspace/ph1p100/fpga/csi2/src/integrated_delivery/dual_channel_capture_scheduler.v'
    refs.append({'path':str(p3),'sha256':sha(p3),'bytes':p3.stat().st_size,'role':'interface_reference_only_not_compiled'})
    dispatch=json.loads((HERE.parent/'dispatch.json').read_text(encoding='utf-8-sig'))
    task=next(x for x in dispatch['next_action']['task_dispatches'] if x['task_id']=='T08.freerun-isolation')
    save(HERE/'inputs/task-dispatch.json',task)
    save(HERE/'inputs/source-binding.json', {'project_root':str(ROOT),'frozen_candidate':str(OLD),
         'old_manifest_path':str(OLD/'manifest-mode-fix02.json'),'old_manifest_sha256':sha(OLD/'manifest-mode-fix02.json'),
         'old_results_not_reused':True, 'source_count':len(rows),'sources':rows,'references':refs})
    (HERE/'inputs/sources.f').write_text('\n'.join(x.as_posix() for x in sources)+'\n'+(HERE/'tb_freerun.sv').as_posix()+'\n')
    return sources

def command(args, cwd, log, timeout=300):
    args=[p.as_posix() if isinstance(p,Path) else str(p) for p in args]
    start=time.time(); p=None
    with log.open('w',encoding='utf-8') as out:
        out.write(json.dumps({'command':args,'cwd':str(cwd),'timeout_seconds':timeout})+'\n');out.flush()
        p=subprocess.Popen(args,cwd=cwd,stdout=out,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
        expired=False
        try: code=p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            expired=True
            if p.poll() is None:
                subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=out,stderr=subprocess.STDOUT,
                               timeout=15,check=False,creationflags=subprocess.CREATE_NO_WINDOW)
            code=p.wait(timeout=15)
        result={'command':args,'cwd':str(cwd),'exit_code':code,'timeout':expired,'owned_pid':p.pid,
                'timeout_seconds':timeout,'elapsed_seconds':round(time.time()-start,3),'log':str(log)}
        out.write('\nCOMMAND_RESULT '+json.dumps(result)+'\n')
    journal=HERE/'commands.jsonl' if cwd.is_relative_to(HERE) else cwd/'commands.jsonl'
    with journal.open('a',encoding='utf-8') as out:out.write(json.dumps(result)+'\n')
    return result

def compile_at(build):
    binding=json.loads((HERE/'inputs/source-binding.json').read_text(encoding='utf-8'))
    for row in binding['sources']:assert sha(Path(row['path']))==row['sha256'],'source drift'
    sources=[Path(row['path']) for row in binding['sources'] if row['compiled']]
    build.mkdir(parents=True,exist_ok=False)
    ini=build/'modelsim.ini';ini.write_text('[Library]\nwork = '+(build/'work').as_posix()+'\n',encoding='ascii')
    r=command([TOOLS/'vlib.exe',build/'work'],build,build/'vlib.log',60)
    assert r['exit_code']==0 and not r['timeout'], 'vlib failed'
    files=sources+[HERE/'tb_freerun.sv']
    args=[TOOLS/'vlog.exe','-sv','-modelsimini',ini,'-work',build/'work','+define+MIPI_PHY_SIM_STUB']
    args+=['+incdir+'+x.as_posix() for x in sorted({x.parent for x in sources})]
    args+=files
    r=command(args,build,build/'vlog.log');text=(build/'vlog.log').read_text(errors='replace')
    assert r['exit_code']==0 and not r['timeout'] and 'Errors: 0' in text and '** Error' not in text,'compile failed'
    save(build/'compile-result.json',r);print('COMPILE_OK',flush=True)

def run_case(build, out, case):
    out.mkdir(parents=True,exist_ok=False)
    args=[TOOLS/'vsim.exe','-c','-modelsimini',build/'modelsim.ini','-lib',build/'work','tb_freerun',f'+CASE={case}',
          '-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0']
    r=command(args,out,out/'vsim.log');t=(out/'vsim.log').read_text(errors='replace')
    r['sim_pass']=r['exit_code']==0 and not r['timeout'] and 'FREERUN_PASS' in t and not any(v in t for v in ['** Fatal','** Error','FREERUN_FAIL'])
    save(out/'sim-result.json',r);print(json.dumps({'case':case,**r}),flush=True)
    assert r['sim_pass'],'simulation failed'

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','compile','case'])
    parser.add_argument('--build',type=Path,default=HERE/'local/build-r0')
    parser.add_argument('--out',type=Path);parser.add_argument('--case',type=int,default=0)
    a=parser.parse_args()
    for q in [a.build,a.out]:
        if q is not None:assert q.resolve().is_relative_to(HERE) or q.resolve().is_relative_to(HERE.parent/'test-reports/T08.freerun-isolation'), 'output outside T08 evidence scopes'
    if a.action=='prepare':prepare();print('PREPARE_OK')
    elif a.action=='compile':compile_at(a.build)
    else:run_case(a.build,a.out,a.case)
