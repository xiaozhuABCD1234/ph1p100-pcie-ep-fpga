"""Bounded local ModelSim rebuilds, simulations and independent byte checks."""
import hashlib,json,os,pathlib,subprocess,sys,time
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent;RUN=HERE.parent
SRC=RUN/'inputs/a1-r5/src';MS=pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
RTL=['a1_deflate_core.v','a1_frame_top.v','a1_raw_crop.v','a1_ddr_slot_store.v','a1_ddr_arb2.v','a1_uart_export.v','camera_a1_uart_top.v','capture_async_fifo.v']

def protect():
    entries=json.loads((HERE/'protected-before.json').read_text())['files'];drift=[]
    for x in entries:
        if hashlib.sha256(pathlib.Path(x['path']).read_bytes()).hexdigest()!=x['sha256']:drift.append(x['path'])
    assert not drift,'PROTECTED_INPUT_DRIFT '+str(drift)
    return dict(checked=len(entries),drift=drift)

def execute(args,folder,name):
    folder.mkdir(exist_ok=True);args=[a.as_posix() if isinstance(a,pathlib.Path) else str(a) for a in args]
    start=time.monotonic();log=folder/(name+'.log')
    env=os.environ.copy();env['PYTHONDONTWRITEBYTECODE']='1';env['MODELSIM']=(folder/'modelsim.ini').as_posix()
    record=dict(argv=args,cwd=str(HERE),timeout_seconds=300,log=str(log),timed_out=False)
    with log.open('w',encoding='utf-8') as f:
        p=subprocess.Popen(args,cwd=HERE,env=env,stdout=f,stderr=subprocess.STDOUT);record['owned_pid']=p.pid
        try:rc=p.wait(timeout=300)
        except subprocess.TimeoutExpired:
            record['timed_out']=True
            subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT,timeout=15)
            p.wait(timeout=15);rc=-1
    record.update(returncode=rc,elapsed_seconds=round(time.monotonic()-start,3))
    (folder/(name+'.command.json')).write_text(json.dumps(record,indent=2))
    return record

def compile_all(kind):
    folder=HERE/kind;folder.mkdir(exist_ok=True);before=protect();ini=folder/'modelsim.ini'
    assert not (folder/'vlog.command.json').exists(),'ONE_COMPILE_PER_KIND'
    ini.write_text('[Library]\nwork = '+(folder/'lib').as_posix()+'\n[vsim]\nResolution = ps\n')
    (folder/'run.do').write_text('onerror {quit -code 2 -f}\nrun -all\nquit -f\n')
    a=execute([MS/'vlib.exe',folder/'lib'],folder,'vlib');assert a['returncode']==0
    sources=[HERE/'candidate'/n if kind=='corrected' and n=='a1_uart_export.v' else SRC/n for n in RTL]
    b=execute([MS/'vlog.exe','-sv','-modelsimini',ini,'-work','work']+sources+[HERE/'ddr_recovery_model.sv',HERE/'tb_full_clean.sv',HERE/'tb_descriptor.sv'],folder,'vlog')
    log=(folder/'vlog.log').read_text(errors='replace')
    result=dict(status='PASS' if b['returncode']==0 and 'Errors: 0, Warnings: 0' in log else 'FAIL',before=before,after=protect(),sources=[str(p) for p in sources],commands=[a,b])
    (folder/'compile-result.json').write_text(json.dumps(result,indent=2));print(kind,'COMPILE',result['status'],flush=True)
    assert result['status']=='PASS'

def run_case(kind,case):
    folder=HERE/kind;out=folder/case;out.mkdir(exist_ok=True);before=protect()
    assert not (out/'console.command.json').exists(),'CASE_ALREADY_RUN'
    ini=folder/'modelsim.ini'
    base=[MS/'vsim.exe','-c','-modelsimini',ini,'-wlf',out/'case.wlf','-l',out/'transcript.log']
    if case=='full-clean':
        args=base+['work.tb_full_clean','-gW=8','-gH=2','-gMAX_CYCLES=1500000','+CASE=0','+OUT='+(out/'capture.dec').as_posix(),'+TRACE='+(out/'trace.txt').as_posix(),'+STAT='+(out/'stats.txt').as_posix()]
    else:
        mode=2 if case=='wrap' else 3
        args=base+['work.tb_descriptor','+MODE='+str(mode),'+DESCS='+(HERE/'descriptors.hex').as_posix(),'+PAYLOADS='+(HERE/'payloads.hex').as_posix(),'+OUT='+(out/'capture.tsv').as_posix(),'+TRACE='+(out/'trace.txt').as_posix(),'+STAT='+(out/'stats.txt').as_posix()]
    args+=['-do','do '+(folder/'run.do').as_posix()]
    command=execute(args,out,'console')
    if case=='full-clean':
        import check_recovery
        try:
            result=check_recovery.check(out,0)
            if len(result['decoded'])!=4 or result['stats']['exported']!=4 or result['stats']['recovered']!=4:result['status']='FAIL';result['errors'].append('exactly four complete clean frames required')
            if any(result['stats'][k] for k in ['raw_drop','cmp_drop','geom','err','fifo_rejected']):result['status']='FAIL';result['errors'].append('clean pipeline error/drop')
        except Exception as exc:result=dict(status='FAIL',errors=[type(exc).__name__+': '+str(exc)])
    else:
        import check_descriptor
        result=check_descriptor.check(out,mode)
    log=(out/'console.log').read_text(errors='replace')
    target='DESCRIPTOR_ORDER_OR_X' if case=='wrap' else 'QUEUE_COUNT_MISMATCH'
    result.update(kind=kind,case=case,command=command,before=before,after=protect(),target_negative_detected=target in log if kind=='old' else None)
    if command['returncode']!=0 or command['timed_out']:result['status']='FAIL';result['errors'].append('command failed/timed out')
    (out/'result.json').write_text(json.dumps(result,indent=2));print(kind,case,result['status'],'target_negative_detected='+str(result['target_negative_detected']),result.get('errors'),flush=True)
    return result

if __name__=='__main__':
    if sys.argv[1]=='compile':compile_all(sys.argv[2])
    else:run_case(sys.argv[1],sys.argv[2])
