import pathlib,hashlib,json,re,sys,subprocess,xml.etree.ElementTree as ET,shutil,time
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');REC=pathlib.Path(__file__).resolve().parents[1];attempt=int(sys.argv[1])
B=REC/'build'/f'attempt{attempt}';PHY=B/'prj/ph1p_pcie_integration_Runs/phy_1';out=REC/'engineering'/f'attempt{attempt}';out.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):
    b=p.read_bytes()
    return b.decode('utf-16' if b.startswith(b'\xff\xfe') else 'utf-8-sig',errors='replace')
timing=PHY/'ph1p_pcie_integration_pr.timing';area=PHY/'ph1p_pcie_integration_phy.area';cwc=PHY/'cw/compiled.cwc';bit=PHY/'ph1p_pcie_integration.bit';paired=PHY/'cw/compiled.bit';bid=PHY/'ph1p_pcie_integration_inst.bid';db=PHY/'ph1p_pcie_integration_pr.db'
required=[timing,area,cwc,bit,paired,bid,db]
assert all(p.is_file() and p.stat().st_size>0 for p in required),[str(p) for p in required if not p.is_file() or p.stat().st_size==0]
t=read(timing);a=read(area)
metric={k:float(re.search(r'\b'+k+r':\s*(-?[\d.]+)ns',t).group(1)) for k in ['SWNS','STNS','HWNS','HTNS']}
resources=[{'name':m[0].strip(),'used':int(m[1]),'capacity':int(m[2])} for m in re.findall(r'^\s*#([^\n]+?)\s+(\d+)\s+out of\s+(\d+)',a,re.M)]
root=ET.parse(cwc).getroot();probes=[]
for node in root.findall('.//watcher_nodes/bus'):
    if node.get('is_enabled')=='yes':probes.append({'name':node.get('name'),'clock':node.get('clock'),'instance':node.get('inst'),'width':len(node.findall('net'))})
clocks=sorted(set(p['clock'] for p in probes));names='\n'.join(p['name'] for p in probes)
retention={key:(key in a or key in names) for key in ['u_algorithms','u_gau','u_he','u_g0']}
runlog=read(PHY/'run.log');stage=read(B/'prj/td_00_all_closedloop.log')
cmd=['C:/Program Files/Python311/python.exe',str(ROOT/'tools/td/check_chipwatcher_readback.py'),'--multipiece','--map-out',str(out/'cwc-map.json'),str(cwc),str(bid)]
with (out/'cwc-check.log').open('w',encoding='utf-8') as log:
    proc=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,cwd=ROOT)
    try:code=proc.wait(timeout=600)
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],stdout=log,stderr=log,timeout=20);proc.wait(timeout=20);code=124
drift=[]
for e in json.loads((B/'inputs.json').read_text(encoding='utf-8')):
    if sha(pathlib.Path(e['path']))!=e['sha256']:drift.append(e['path'])
result={'attempt':attempt,'metrics':metric,'routed':'Confidence          : Routed' in t,'resources':resources,'resources_within_capacity':bool(resources) and all(r['used']<=r['capacity'] for r in resources),'cwc_check_command':cmd,'cwc_check_exit':code,'probes':probes,'probe_clock_domains':clocks,'retention_tokens':retention,'bit_pair_equal':bit.read_bytes()==paired.read_bytes(),'source_drift':drift,'completion_marker':'B01_CLOSEDLOOP_ALL_DONE' in stage,'artifacts':[{'path':str(p),'size':p.stat().st_size,'sha256':sha(p)} for p in required]}
result['timing_group_violating_endpoints']=[int(n) for n in re.findall(r'(\d+)\s+Viol Endpoints',t)]
syn=read(B/'prj/ph1p_pcie_integration_Runs/syn_1/run.log')
result['native_synthesis_critical_warning_zero']='critical warning check and 0 issue(s)' in syn
result['pass']=result['routed'] and metric['SWNS']>=0 and metric['HWNS']>=0 and metric['STNS']==0 and metric['HTNS']==0 and bool(result['timing_group_violating_endpoints']) and all(n==0 for n in result['timing_group_violating_endpoints']) and result['native_synthesis_critical_warning_zero'] and result['resources_within_capacity'] and code==0 and result['bit_pair_equal'] and not drift and result['completion_marker'] and len(clocks)==3 and all(retention.values())
(out/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k not in ['probes','artifacts','cwc_check_command']},indent=2))
sys.exit(0 if result['pass'] else 1)
