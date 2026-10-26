"""Third/final production attempt, only if attempt2 timed out with a checkpoint.
No RTL recompile or place repeat: finish the native route/post-route stage,
reports/bit/CWC from the exact
unchanged candidate checkpoint. All attempt2 artifacts remain preserved.
"""
import pathlib,json,hashlib,shutil,subprocess,time,ctypes,sys
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');P=ROOT/'upstream/ph1p100-pcie-ep-fpga';REC=pathlib.Path(__file__).resolve().parents[1]
B2=REC/'build/attempt2';B=REC/'build/attempt3';S=B2/'prj/ph1p_pcie_integration_Runs/phy_1';D=B/'prj/ph1p_pcie_integration_Runs/phy_1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
r=json.loads((B2/'execution-result.json').read_text());assert r['timed_out'] and r['elapsed_seconds']>=1800
inputs=json.loads((B2/'inputs.json').read_text());assert all(sha(pathlib.Path(e['path']))==e['sha256'] for e in inputs),'cannot resume a changed source'
checkpoint=next((S/name for name in ['ph1p_pcie_integration_pr.db','ph1p_pcie_integration_place.db'] if (S/name).is_file()),None)
assert checkpoint is not None,'no complete physical checkpoint'
finish_stage='phys_opt -post_route -effort low' if checkpoint.name.endswith('_pr.db') else 'route'
assert D.resolve().is_relative_to(ROOT.resolve()) and REC.resolve().is_relative_to(ROOT.resolve())
assert not B.exists();D.mkdir(parents=True)
shutil.copyfile(B2/'inputs.json',B/'inputs.json')
for name in ['ph1p_pcie_integration.prj',checkpoint.name]:
    src=(S/name).resolve();assert src.is_relative_to(B2.resolve());shutil.copyfile(src,D/name)
def devtarget(letter):
    buf=ctypes.create_unicode_buffer(32768)
    return buf.value if ctypes.windll.kernel32.QueryDosDeviceW(letter+':',buf,len(buf)) else None
maps=[]
tcl='''if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 open_project ./ph1p_pcie_integration.prj -noanalyze
 import_db ./__SOURCE_DB__
 __FINISH_STAGE__
 update_timing -mode final
 report_timing_status -file ph1p_pcie_integration_phy.ts
 report_timing_summary -file ph1p_pcie_integration_pr.timing
 report_timing_exception -file ph1p_pcie_integration_exception.timing
 check_timing -verbose -file ph1p_pcie_integration_chk.timing
 report_area -io_info -file ph1p_pcie_integration_phy.area
 report_clock_utilization -file route_clock_utilization.txt
 export_db ph1p_pcie_integration_pr.db
 bitgen -bit ph1p_pcie_integration.bit
 setup_debugger -prj ph1p_pcie_integration
 if {![file exists ./cw/compiled.cwc] || ![file exists ./cw/compiled.bit] || ![file exists ./ph1p_pcie_integration_inst.bid]} {error "missing native paired debugger artifacts"}
 puts "B01_CLOSEDLOOP_ALL_DONE"
} msg]} {puts stderr "B01_CHECKPOINT_FINISH_ERROR: $msg";exit 1}
exit 0
'''.replace('__SOURCE_DB__',checkpoint.name).replace('__FINISH_STAGE__',finish_stage)
(D/'finish.tcl').write_text(tcl,encoding='ascii')
assert all(devtarget(letter) is None for letter in ['S','T']),'do not replace an existing mapping'
for letter,target in [('S',P),('T',B/'prj')]:
    try:subprocess.run(['subst',letter+':',str(target)],check=True,timeout=10)
    except BaseException:
        for old,want in maps:
            if devtarget(old)==want:subprocess.run(['subst',old+':','/D'],check=True,timeout=10)
        raise
    maps.append((letter,'\\??\\'+str(target)))
command=['D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe','finish.tcl'];start=time.time();timed=False
try:
    with (B/'deadline.log').open('w',encoding='utf-8') as log:
        log.write(json.dumps({'command':command,'cwd':'T:/ph1p_pcie_integration_Runs/phy_1','deadline_seconds':1800,'attempt':3,'source_attempt':2,'source_checkpoint':str(checkpoint),'source_checkpoint_sha256':sha(checkpoint),'scope':'same RTL candidate; finish only missing physical backend stage, reports/bit/CWC'})+'\n');log.flush()
        proc=subprocess.Popen(command,cwd='T:/ph1p_pcie_integration_Runs/phy_1',stdout=log,stderr=subprocess.STDOUT)
        log.write('OWN_PID='+str(proc.pid)+'\n');log.flush()
        try:code=proc.wait(timeout=1800)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=log,stderr=log,timeout=20);code=proc.wait(timeout=20);timed=True
    shutil.copyfile(B/'deadline.log',D/'run.log');shutil.copyfile(B/'deadline.log',B/'prj/td_00_all_closedloop.log')
    (B/'execution-result.json').write_text(json.dumps({'attempt':3,'exit':code,'timed_out':timed,'elapsed_seconds':time.time()-start,'checkpoint_continuation_of':2,'source_checkpoint':str(checkpoint),'source_checkpoint_sha256':sha(checkpoint),'finish_stage':finish_stage},indent=2),encoding='utf-8')
    print('checkpoint finish exit='+str(code));sys.exit(124 if timed else code)
finally:
    for letter,target in maps:
        if devtarget(letter)==target:subprocess.run(['subst',letter+':','/D'],check=True,timeout=10)
