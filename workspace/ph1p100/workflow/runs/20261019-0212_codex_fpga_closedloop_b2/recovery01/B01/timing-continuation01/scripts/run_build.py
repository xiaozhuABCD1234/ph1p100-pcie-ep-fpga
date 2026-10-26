import pathlib,subprocess,os,json,time,sys,hashlib,ctypes
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');P=ROOT/'upstream/ph1p100-pcie-ep-fpga';REC=pathlib.Path(__file__).resolve().parents[1]
attempt=int(sys.argv[1]);assert 4<=attempt<=6
out=REC/'build'/f'attempt{attempt}';out.mkdir(parents=True,exist_ok=False)
sources=[]
for folder in ['rtl','constraints','al_ip','tools/pcie_integration/td']:
    for f in sorted((P/folder).rglob('*')):
        if f.is_file():sources.append({'path':str(f),'size':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()})
(out/'inputs.json').write_text(json.dumps(sources,indent=2))
cmd=['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(P/'tools/pcie_integration/run_td.ps1'),'-Stage','00_all_closedloop','-Root',str(P),'-OutDir',str(out/'prj'),'-TimeoutMin','60']
env=os.environ.copy();env['TD_BIN']='D:/anlogic/TD_Release_2026.2/bin'
start=time.time()
def mappings():
    result={}
    for letter in 'STUVWXYZ':
        buf=ctypes.create_unicode_buffer(32768)
        if ctypes.windll.kernel32.QueryDosDeviceW(letter+':',buf,len(buf)):
            result[letter]=buf.value
    return result
before=mappings()
with (out/'deadline.log').open('w',encoding='utf-8') as log:
    log.write(json.dumps({'command':cmd,'cwd':str(P),'deadline_seconds':3600,'attempt':attempt,'start':start})+'\n');log.flush()
    proc=subprocess.Popen(cmd,cwd=P,env=env,stdout=log,stderr=subprocess.STDOUT)
    log.write('OWN_PID='+str(proc.pid)+'\n');log.flush()
    try:code=proc.wait(timeout=3600);timed_out=False
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=log,stderr=log,timeout=20);code=proc.wait(timeout=20);timed_out=True
result={'attempt':attempt,'exit':code,'timed_out':timed_out,'elapsed_seconds':time.time()-start,'directory':str(out)}
cleanup=[]
for letter,target in mappings().items():
    if letter not in before and target.startswith('\\??\\') and pathlib.Path(target[4:]).resolve() in [P.resolve(),(out/'prj').resolve()]:
        cp=subprocess.run(['subst',letter+':','/D'],capture_output=True,text=True,timeout=10)
        cleanup.append({'drive':letter,'target':target,'exit':cp.returncode})
result['owned_mapping_cleanup']=cleanup
(out/'execution-result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result),flush=True);sys.exit(124 if timed_out else code)
