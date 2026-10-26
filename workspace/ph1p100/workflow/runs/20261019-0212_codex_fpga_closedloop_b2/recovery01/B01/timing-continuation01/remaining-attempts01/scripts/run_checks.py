import pathlib,subprocess,sys,json,time,os,hashlib,shutil
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');P=ROOT/'upstream/ph1p100-pcie-ep-fpga';REC=pathlib.Path(__file__).resolve().parents[1]
env=os.environ.copy();env['MSIM_BIN']='D:/intelFPGA/18.1/modelsim_ase/win32aloem'
for tb in sys.argv[1:]:
    od=REC/'g1'/(tb+'-'+time.strftime('%Y%m%dT%H%M%S'));od.mkdir(parents=True,exist_ok=False)
    if 'oracle' in tb:
        for v in (REC/'vectors').glob('*.hex'):shutil.copyfile(v,od/v.name)
    top={'tb_ddr_wr_arb_peer':'tb_ddr_wr_arb'}.get(tb,tb)
    cmd=['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(P/'tools/pcie_integration/run_sim.ps1'),'-Root',str(P),'-Tb',top,'-OutDir',str(od),'-TbFiles','tb/'+tb+'.v','-Defines','MIPI_PHY_SIM_STUB']
    sources=[]
    for base in [P/'rtl',P/'sim']:
        for f in sorted(base.rglob('*')):
            if f.is_file() and f.suffix in {'.v','.sv','.vh','.f'}:sources.append({'path':str(f),'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
    (od/'inputs.json').write_text(json.dumps(sources,indent=2))
    t=time.time()
    with (od/'deadline.log').open('w',encoding='utf-8') as log:
        log.write(json.dumps({'command':cmd,'cwd':str(P),'seconds':300})+'\n');log.flush()
        proc=subprocess.Popen(cmd,cwd=P,env=env,stdout=log,stderr=subprocess.STDOUT)
        log.write('OWN_PID='+str(proc.pid)+'\n');log.flush()
        try:code=proc.wait(timeout=300);timeout=False
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=log,stderr=log,timeout=20);code=proc.wait(timeout=20);timeout=True
    text=(od/'vsim.log').read_text(errors='replace') if (od/'vsim.log').exists() else ''
    vlog=(od/'vlog.log').read_text(errors='replace') if (od/'vlog.log').exists() else ''
    passed=('ADAPTER_ORACLE_MISMATCH' in text and 'ADAPTER_ORACLE_PASS' not in text) if tb.endswith('_negative') else ('PASS' in text and 'FAIL' not in text)
    result={'tb':tb,'exit':code,'timeout':timeout,'seconds':time.time()-t,'pass_marker':passed,'negative_rejection':tb.endswith('_negative'),'sim_error':'** Error' in text or '** Fatal' in text or '** Error' in vlog,'log':str(od/'vsim.log'),'vlog_log':str(od/'vlog.log'),'input_sha256':hashlib.sha256((od/'inputs.json').read_bytes()).hexdigest()}
    (od/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True)
    if code or timeout or result['sim_error'] or not result['pass_marker']:sys.exit(1)
