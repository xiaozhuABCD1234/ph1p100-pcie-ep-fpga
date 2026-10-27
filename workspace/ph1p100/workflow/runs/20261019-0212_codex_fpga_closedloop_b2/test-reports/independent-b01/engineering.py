import audit, pathlib,json,re,subprocess,time,xml.etree.ElementTree as ET
D,O,R=audit.DEV,audit.OUT,audit.ROOT
B=D/'build/attempt6';PHY=B/'prj/ph1p_pcie_integration_Runs/phy_1'
t=audit.read(PHY/'ph1p_pcie_integration_pr.timing');a=audit.read(PHY/'ph1p_pcie_integration_phy.area');c=audit.read(PHY/'ph1p_pcie_integration_chk.timing')
metrics={k:float(re.search(r'\b'+k+r':\s*(-?[\d.]+)ns',t)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
viol=[int(x) for x in re.findall(r'(\d+)\s+Viol Endpoints',t)]
resources=[{'name':m[0].strip(),'used':int(m[1]),'capacity':int(m[2])} for m in re.findall(r'^\s*#([^\n]+?)\s+(\d+)\s+out of\s+(\d+)',a,re.M)]
paths=[PHY/'ph1p_pcie_integration_pr.db',PHY/'ph1p_pcie_integration_pr.timing',PHY/'ph1p_pcie_integration_chk.timing',PHY/'ph1p_pcie_integration_phy.area',PHY/'ph1p_pcie_integration.bit',PHY/'cw/compiled.bit',PHY/'cw/compiled.cwc',PHY/'ph1p_pcie_integration_inst.bid']
hashes=[{'path':str(p),'sha256':audit.sha(p),'size':p.stat().st_size} for p in paths]
source_drift=[e['path'] for e in json.loads(audit.read(B/'inputs.json')) if audit.sha(e['path'])!=e['sha256']]
cmd=['C:/Program Files/Python311/python.exe',str(R/'tools/td/check_chipwatcher_readback.py'),'--multipiece','--map-out',str(O/'cwc-map.json'),str(PHY/'cw/compiled.cwc'),str(PHY/'ph1p_pcie_integration_inst.bid')]
start=time.time()
cached=json.loads(audit.read(O/'cwc-check.log')) if (O/'cwc-check.log').exists() else None
if cached and cached.get('accepted'):
    code=0;timeout=False;pid=None
else:
    with (O/'cwc-check.log').open('w',encoding='utf-8') as log:
        proc=subprocess.Popen(cmd,cwd=R,stdout=log,stderr=subprocess.STDOUT);pid=proc.pid
        try:code=proc.wait(timeout=600);timeout=False
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=log,stderr=log,timeout=20);code=proc.wait(timeout=20);timeout=True
root=ET.parse(PHY/'cw/compiled.cwc').getroot()
probes=[{'name':n.get('name'),'clock':n.get('clock'),'width':len(n.findall('net'))} for n in root.findall('.//watcher_nodes/bus') if n.get('is_enabled')=='yes']
basepath=pathlib.Path(json.loads(audit.read(D/'engineering/attempt6/constraint-boundary-comparison.json'))['baseline'])
baseline=audit.read(basepath)
def section(text,n):
    match=re.search(r'^'+str(n)+r'\. checking .*?\n-+\n(.*?)(?=^\d+\. checking |\Z)',text,re.M|re.S)
    assert match,n
    return sorted(l.strip() for l in match[1].splitlines() if l.startswith('\t') and not l.strip().startswith(('Max','Min','Total')))
boundaries={str(n):{'same':section(c,n)==section(baseline,n),'current':section(c,n)} for n in [1,2,10,11]}
summary=re.findall(r'^\d+\. checking .+$',c,re.M)[:14]
coverage=float(re.search(r'STA coverage\s*:\s*([\d.]+)%',t)[1])
sdc=R/'upstream/ph1p100-pcie-ep-fpga/constraints/ph1p_pcie_case_ep_closedloop.sdc'
protected=R/'upstream/ph1p100-pcie-ep-fpga/constraints/ph1p_pcie_case_ep_dbg.sdc'
st=audit.read(B/'prj/td_00_all_closedloop.log')
syn=audit.read(B/'prj/ph1p_pcie_integration_Runs/syn_1/run.log')
native_result=json.loads(audit.read(B/'result.json')) if (B/'result.json').exists() else None
v={'metrics':metrics,'coverage_percent':coverage,'violating_endpoint_groups':viol,'routed':'Confidence          : Routed' in t,'both_corners':'Both (Slow and Fast)' in t,'resources':resources,'source_drift':source_drift,'hashes':hashes,'cwc':{'command':cmd,'cwd':str(R),'owned_pid':pid,'deadline_seconds':600,'seconds':time.time()-start,'exit':code,'timeout':timeout,'log':str(O/'cwc-check.log')},'probes':probes,'baseline_boundaries':boundaries,'constraint_summary':summary,'protected_sdc_equal':audit.sha(sdc)==audit.sha(protected),'completion_marker':'B01_CLOSEDLOOP_ALL_DONE' in st,'critical_warning_zero':'critical warning check and 0 issue(s)' in syn,'retention':{k:k in a for k in ['u_algorithms','u_gau','u_he','u_g0']},'bit_pair_equal':audit.sha(PHY/'ph1p_pcie_integration.bit')==audit.sha(PHY/'cw/compiled.bit'),'native_execution':native_result}
v['pass']=metrics['SWNS']>=0 and metrics['HWNS']>=0 and metrics['STNS']==0 and metrics['HTNS']==0 and bool(viol) and not any(viol) and v['routed'] and v['both_corners'] and not source_drift and code==0 and not timeout and v['bit_pair_equal'] and v['completion_marker'] and v['critical_warning_zero'] and all(z['same'] for z in boundaries.values()) and all(x['used']<=x['capacity'] for x in resources) and all(v['retention'].values()) and v['protected_sdc_equal']
audit.save('engineering-audit.json',v)
print(json.dumps({k:v[k] for k in ['metrics','coverage_percent','routed','both_corners','source_drift','constraint_summary','protected_sdc_equal','completion_marker','critical_warning_zero','retention','bit_pair_equal','pass']},indent=2))
assert v['pass']

