import audit, pathlib, json, time, subprocess, os, sys, shutil, importlib.util, re
sys.dont_write_bytecode=True
ROOT,OUT,DEV=audit.ROOT,audit.OUT,audit.DEV
P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
def checks(names):
    env=os.environ.copy();env['MSIM_BIN']='D:/intelFPGA/18.1/modelsim_ase/win32aloem'
    for tb in names:
        od=OUT/'g1'/tb;od.mkdir(parents=True,exist_ok=False)
        if 'oracle' in tb:
            for v in (DEV/'vectors').glob('*.hex'):shutil.copyfile(v,od/v.name)
        cmd=['powershell','-NoProfile','-File',str(P/'tools/pcie_integration/run_sim.ps1'),'-Root',str(P),'-Tb',tb,'-OutDir',str(od),'-TbFiles','tb/'+tb+'.v','-Defines','MIPI_PHY_SIM_STUB']
        t=time.time()
        with (od/'deadline.log').open('w',encoding='utf-8') as log:
            log.write(json.dumps({'command':cmd,'cwd':str(P),'deadline_seconds':300})+'\n');log.flush()
            proc=subprocess.Popen(cmd,cwd=P,env=env,stdout=log,stderr=subprocess.STDOUT)
            log.write('OWN_PID='+str(proc.pid)+'\n');log.flush()
            try:code=proc.wait(timeout=300);timeout=False
            except subprocess.TimeoutExpired:
                subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=log,stderr=log,timeout=20);code=proc.wait(timeout=20);timeout=True
        txt=audit.read(od/'vsim.log');vlog=audit.read(od/'vlog.log')
        negative=tb.endswith('_negative')
        markers=[l for l in txt.splitlines() if re.search('PASS|FAIL|MISMATCH|1080|overflow|recover',l,re.I)]
        ok=('ADAPTER_ORACLE_MISMATCH' in txt and 'ADAPTER_ORACLE_PASS' not in txt) if negative else ('PASS' in txt and 'FAIL' not in txt and 'MISMATCH' not in txt)
        err=bool(re.search(r'\*\* (?:Error|Fatal)|Errors:\s*[1-9]',txt+'\n'+vlog))
        result={'tb':tb,'command':cmd,'cwd':str(P),'exit':code,'timeout':timeout,'seconds':time.time()-t,'markers':markers,'sim_error':err,'negative_control':negative,'pass':ok and code==0 and not timeout and not err,'log':str(od/'vsim.log')}
        (od/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps(result),flush=True)
        if not result['pass']:raise SystemExit(1)
def algo(case,mutation):
    source=DEV/'scripts/run_algo_g1.py'
    spec=importlib.util.spec_from_file_location('frozen_algo_runner',source);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    m.OUTROOT=OUT/'algo-g1'
    code=m.run_case(case,mutation,'independent-r0',300)
    raise SystemExit(code)
if __name__=='__main__':
    if sys.argv[1]=='checks':checks(sys.argv[2:])
    else:algo(sys.argv[2],sys.argv[3])
