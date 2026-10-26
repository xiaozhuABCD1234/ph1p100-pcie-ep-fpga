import pathlib,subprocess,sys,json,time,os
ROOT=pathlib.Path(__file__).resolve().parents[4];OUT=pathlib.Path(__file__).resolve().parents[1];P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
env=os.environ.copy();env['MSIM_BIN']='D:/intelFPGA/18.1/modelsim_ase/win32aloem'
cases=['tb_ep_bar_win_debug','tb_ddr_frame_readback_checker','tb_closedloop_writer_checker','tb_ddr_frame_pusher_rka1','tb_ddr_wr_arb_peer','tb_ep_bar_win_rka1','tb_csi_checked','tb_t11_csi_enable_corner','tb_csi_integrity_diff','tb_t11_r10f_e2e']
if len(sys.argv)>1: cases=sys.argv[1:]
results=[]
for tb in cases:
    od=OUT/'ddr-integration/g1'/(tb+'-'+time.strftime('%Y%m%dT%H%M%S'));od.mkdir(parents=True,exist_ok=False)
    top={'tb_ddr_wr_arb_peer':'tb_ddr_wr_arb'}.get(tb,tb)
    cmd=['powershell','-NoProfile','-ExecutionPolicy','Bypass','-File',str(P/'tools/pcie_integration/run_sim.ps1'),'-Root',str(P),'-Tb',top,'-OutDir',str(od),'-TbFiles','tb/'+tb+'.v','-Defines','MIPI_PHY_SIM_STUB']
    t=time.time()
    with (od/'deadline.log').open('w',encoding='utf-8') as log:
        log.write(json.dumps({'command':cmd,'cwd':str(P),'seconds':300})+'\n');log.flush()
        proc=subprocess.Popen(cmd,cwd=P,env=env,stdout=log,stderr=subprocess.STDOUT)
        try: code=proc.wait(timeout=300);timeout=False
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=log,stderr=log,timeout=20);code=proc.wait(timeout=20);timeout=True
    text=(od/'vsim.log').read_text(encoding='utf-8',errors='replace') if (od/'vsim.log').exists() else ''
    vlog=(od/'vlog.log').read_text(encoding='utf-8',errors='replace') if (od/'vlog.log').exists() else ''
    result={'tb':tb,'exit':code,'timeout':timeout,'seconds':time.time()-t,'pass_marker':('ALL PASS' in text or 'PASS' in text) and 'FAIL' not in text,'sim_error':'** Error' in text or '** Fatal' in text or '** Error' in vlog,'log':str(od/'vsim.log'),'vlog_log':str(od/'vlog.log')}
    results.append(result);print(json.dumps(result),flush=True)
    (OUT/'ddr-integration/g1-summary.json').write_text(json.dumps(results,indent=2))
    if code or timeout or result['sim_error'] or not result['pass_marker']:sys.exit(1)
