"""Fault-inject the observed RGB332 routed mapping; never alter the candidate."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,subprocess,sys

parser=argparse.ArgumentParser()
parser.add_argument('project',type=Path)
a=parser.parse_args();repo=Path(__file__).resolve().parents[2]
source=a.project.resolve();net=(source/'capture_routed.v').read_text()
out=Path('D:/TD/work/csi2/_validation')/('rgb332_cdc_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir();scripts=['audit_display_cdc.py','review_display_cdc_functions.py','review_display_cdc_origins.py']
for name in scripts:(out/name).write_bytes((repo/'tools/td'/name).read_bytes())
blocks=list(re.finditer(r'(?m)^  PH1P_PHY_[LM]SLICE #\(\n.*?\);',net,re.S))
def choose(token):
    found=[m for m in blocks if token in m[0]];assert len(found)==1,(token,len(found))
    return found[0]
gate=choose('\\u_ddrmc_test_top/u_capture/u_fifo/rq2_wgray_b[4]_syn_2  (')
reset=choose('.oqb(\\u_ddrmc_test_top/u_capture/u_display_fifo/wr_reset [1])')
assert '32\'b11111111000000000000000000000000' in gate[0]
assert '.imb(\\u_ddrmc_test_top/u_capture/u_fifo/rq1_wgray [4])' in gate[0]
cap=json.loads((source/'u_fifo_cdc_audit.json').read_bytes())
capture_clock=cap['rows']['wgray[0]']['pins']['clk']
def splice(m,changed):assert changed!=m[0];return net[:m.start()]+changed+net[m.end():]
cases=[
 ('valid',net,None),
 ('wrong_truth',splice(gate,gate[0].replace("32'b11111111000000000000000000000000","32'b11111111000000000000000000000001")),'Reset AND truth table/selectors'),
 ('wrong_bit',splice(gate,gate[0].replace('.imb(\\u_ddrmc_test_top/u_capture/u_fifo/rq1_wgray [4])','.imb(\\u_ddrmc_test_top/u_capture/u_fifo/rq1_wgray [5])')),'Reset gate source bit'),
 ('wrong_reset_domain',splice(reset,re.sub(r'(?m)^    \.clk\([^\n]+',lambda _: '    .clk(\\'+capture_clock+' ),',reset[0])),'Reset domain mismatch')]
results=[]
for label,data,expected in cases:
    root=out/label;root.mkdir();(root/'capture_routed.v').write_bytes(data.encode())
    commands=[('audit_display_cdc.py',['--fifo','u_fifo']),('audit_display_cdc.py',['--fifo','u_display_fifo']),('review_display_cdc_functions.py',[]),('review_display_cdc_origins.py',[])]
    runs=[]
    for index,(name,args) in enumerate(commands):
        command=[sys.executable,'-X','utf8',str(out/name),str(root),*args]
        result=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
        (root/f'{index}.txt').write_bytes(result.stdout)
        runs.append({'command':command,'exit_code':result.returncode,'log':f'{label}/{index}.txt'})
        if result.returncode:break
    if expected:
        assert runs[-1]['exit_code']!=0 and expected.encode() in result.stdout,(label,result.stdout.decode())
    else:assert len(runs)==4 and all(x['exit_code']==0 for x in runs)
    results.append({'case':label,'expected':'pass' if expected is None else 'rejection','accepted':True,'netlist_sha256':hashlib.sha256(data.encode()).hexdigest(),'runs':runs})
obj={'source':str(source),'source_netlist_sha256':hashlib.sha256((source/'capture_routed.v').read_bytes()).hexdigest(),
     'checker_hashes':{name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in scripts},'cases':results,
     'boundary':'Observed single-LUT RGB332 mapping only; mutated netlists are deliberately invalid, not candidate implementations.'}
(out/'result.json').write_bytes((json.dumps(obj,indent=2)+'\n').encode())
print('RGB332_CDC_CONTROLS_PASS valid=1 rejected=3',out)
