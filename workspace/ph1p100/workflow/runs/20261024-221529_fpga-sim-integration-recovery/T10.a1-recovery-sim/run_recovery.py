"""Reproducible fixed-DUT local verification; each command has a real deadline."""
import hashlib,json,os,pathlib,subprocess,sys,time
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent
RUN=HERE.parent
SRC=RUN/'inputs/a1-r5/src'
MS=pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
RTL=['a1_deflate_core.v','a1_frame_top.v','a1_raw_crop.v','a1_ddr_slot_store.v',
     'a1_ddr_arb2.v','a1_uart_export.v','camera_a1_uart_top.v','capture_async_fifo.v']
CASES=[('clean',0,8),('raw-midwrite-reset',1,16),('encoded-midwrite-reset',2,16),('bad-frame',3,8),('overflow',4,8)]
INI=HERE/'modelsim.ini'
ENV=os.environ.copy();ENV['MODELSIM']=INI.as_posix();ENV['PYTHONDONTWRITEBYTECODE']='1'
def protect():
    m=json.loads((RUN/'planning-input-manifest.json').read_text(encoding='utf-8-sig'))
    entries=m['files']; drift=[]
    for x in entries:
        p=pathlib.Path(x['frozen'])
        actual=hashlib.sha256(p.read_bytes()).hexdigest()
        if actual!=x['sha256']: drift.append(str(p))
    assert not drift,'PROTECTED_INPUT_DRIFT '+str(drift)
    return dict(checked=len(entries),drift=drift)
def execute(args,folder,name,timeout=300):
    folder.mkdir(exist_ok=True)
    args=[a.as_posix() if isinstance(a,pathlib.Path) else str(a) for a in args];start=time.monotonic();log=folder/(name+'.log')
    record=dict(argv=args,cwd=str(HERE),timeout_seconds=timeout,log=str(log))
    with log.open('w',encoding='utf-8') as f:
        p=subprocess.Popen(args,cwd=HERE,env=ENV,stdout=f,stderr=subprocess.STDOUT)
        record['owned_pid']=p.pid
        try: rc=p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            record['timed_out']=True
            subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT,timeout=15)
            p.wait(timeout=15);rc=-1
    record.update(returncode=rc,elapsed_seconds=round(time.monotonic()-start,3))
    (folder/(name+'.command.json')).write_text(json.dumps(record,indent=2))
    return record
def compile_all():
    before=protect()
    INI.write_text('[Library]\nwork = '+(HERE/'lib').as_posix()+'\n[vsim]\nResolution = ps\n')
    (HERE/'run.do').write_text('onerror {quit -code 2 -f}\nrun -all\nquit -f\n')
    a=execute([MS/'vlib.exe',HERE/'lib'],HERE,'vlib')
    assert a['returncode']==0,'vlib failed'
    b=execute([MS/'vlog.exe','-sv','-modelsimini',INI,'-work','work']+[SRC/n for n in RTL]+[HERE/'ddr_recovery_model.sv',HERE/'tb_recovery.sv'],HERE,'vlog')
    text=(HERE/'vlog.log').read_text(errors='replace')
    assert b['returncode']==0 and 'Errors: 0, Warnings: 0' in text,'compile failed or warnings'
    (HERE/'compile-result.json').write_text(json.dumps(dict(status='PASS',before=before,after=protect(),commands=[a,b]),indent=2))
    print('COMPILE_PASS',flush=True)
def run_case(name):
    c=next(c for c in CASES if c[0]==name);out=HERE/name;out.mkdir(exist_ok=True)
    before=protect()
    cmd=[MS/'vsim.exe','-c','-modelsimini',INI,'-wlf',out/'case.wlf','-l',out/'transcript.log',
         'work.tb_recovery','-gW='+str(c[2]),'-gH=2','-gMAX_CYCLES=1500000',
         '+CASE='+str(c[1]),'+OUT='+(out/'capture.dec').as_posix(),
         '+TRACE='+(out/'trace.txt').as_posix(),'+STAT='+(out/'stats.txt').as_posix(),'-do','do '+(HERE/'run.do').as_posix()]
    command=execute(cmd,out,'console')
    import check_recovery
    try: result=check_recovery.check(out,c[1])
    except Exception as exc: result=dict(case_id=c[1],status='FAIL',errors=[type(exc).__name__+': '+str(exc)])
    result.update(name=name,command=command,protection_before=before,protection_after=protect())
    (out/'result.json').write_text(json.dumps(result,indent=2))
    print(name,result['status'],result.get('errors',[]),flush=True)
    return result
def collect():
    import check_recovery
    results=[json.loads((HERE/c[0]/'result.json').read_text()) for c in CASES if (HERE/c[0]/'result.json').exists()]
    negatives=[]
    clean=HERE/'clean'
    if (clean/'result.json').exists():
        stale=check_recovery.check(clean,0,allowed_override=list(range(1100,1104)))
        negatives.append(dict(name='valid-old-epoch-packet-as-recovery',rejected=stale['status']=='FAIL',errors=stale['errors']))
    for n,c,w in CASES[1:3]:
        if (HERE/n/'stats.txt').exists():
            absent=check_recovery.check(HERE/n,c,inject_override=0)
            negatives.append(dict(name=n+'-deleted-trigger',rejected='fault trigger absent' in absent['errors'],errors=absent['errors']))
    result=dict(task_id='T10.a1-recovery-sim',round=0,status='LOCAL_PASS' if len(results)==5 and all(x['status']=='PASS' for x in results) and all(n['rejected'] for n in negatives) else 'LOCAL_FAIL',
                cases=results,negative_controls=negatives,protected_inputs=protect(),active_commands=0)
    (HERE/'local-result.json').write_text(json.dumps(result,indent=2))
    print(result['status'],[(x['name'],x['status']) for x in results],flush=True)
if __name__=='__main__':
    action=sys.argv[1]
    if action=='compile':compile_all()
    elif action=='collect':collect()
    else:run_case(action)
