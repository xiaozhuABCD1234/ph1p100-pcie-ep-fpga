"""Bounded fault controls on this RGB565 mapping; original candidate is read-only."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,subprocess,sys
p=argparse.ArgumentParser();p.add_argument('project',type=Path);a=p.parse_args()
ROOT=Path(__file__).resolve().parents[2];src=a.project.resolve();raw=(src/'capture_routed.v').read_bytes();s=raw.decode().replace('\r\n','\n')
out=Path('D:/TD/work/csi2/_validation')/('rgb565_cdc_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
scripts=['audit_display_cdc.py','review_display_cdc_functions.py','review_display_cdc_origins.py']
for n in scripts:(out/n).write_bytes((ROOT/'tools/td'/n).read_bytes())
blocks=list(re.finditer(r'(?m)^  PH1P_PHY_[LM]SLICE #\(\n.*?\);',s,re.S))
def select(token):
    matches=[m for m in blocks if token in m[0]];assert len(matches)==1,(token,len(matches));return matches[0]
f=json.loads((src/'u_fifo_cdc_audit.json').read_bytes());link=next(x for x in f['links'] if x['to']=='rq1_wgray[0]')
gate=select('\\u_ddrmc_test_top/u_capture/u_fifo/rq1_wgray_reg[0]_syn_2  (')
# The physical cell must actually hold the destination Q and source bit.
assert '\\u_ddrmc_test_top/u_capture/u_fifo/rq1_wgray [0]' in gate[0]
assert '\\u_ddrmc_test_top/u_capture/u_fifo/wgray [0]' in gate[0]
truth=".INIT_LUT5A(32'b11111111000000000000000000000000)";assert truth in gate[0]
sourcebit='\\u_ddrmc_test_top/u_capture/u_fifo/wgray [0]'
reset=select('.oqa(\\u_ddrmc_test_top/u_capture/u_display_fifo/wr_reset [1])') if any('.oqa(\\u_ddrmc_test_top/u_capture/u_display_fifo/wr_reset [1])' in m[0] for m in blocks) else select('.oqb(\\u_ddrmc_test_top/u_capture/u_display_fifo/wr_reset [1])')
cap_clock=f['rows']['wgray[0]']['pins']['clk']
gclks=list(re.finditer(r'(?m)^  PH1P_PHY_GCLK\b[\s\S]*?(?=^  \w|\Z)',s));gclk=next(m for m in gclks if '.clkout(\\u_camera/u_cam_preview/clk )' in m[0])
assert len([m for m in gclks if '.clkout(\\u_camera/u_cam_preview/clk )' in m[0]])==1
def splice(m,changed):
    assert changed!=m[0];return s[:m.start()]+changed+s[m.end():]
cases=[('valid',s,False),
       ('wrong_truth',splice(gate,gate[0].replace(truth,truth[:-2]+'1)')),True),
       ('wrong_bit',splice(gate,gate[0].replace(sourcebit,sourcebit.replace('[0]','[1]'))),True),
       ('wrong_reset_domain',splice(reset,re.sub(r'(?m)^    \.clk\([^\n]+',lambda _:'    .clk(\\'+cap_clock+' ),',reset[0])),True),
       ('wrong_byte_clock_selector',splice(gclk,gclk[0].replace(".seln(2'b10)",".seln(2'b01)")),True)]
results=[]
for label,data,reject in cases:
    case=out/label;case.mkdir();(case/'capture_routed.v').write_bytes(data.encode());runs=[]
    for i,(name,args) in enumerate([(scripts[0],['--fifo','u_fifo']),(scripts[0],['--fifo','u_display_fifo']),(scripts[1],[]),(scripts[2],[])]):
        command=[sys.executable,'-X','utf8',str(out/name),str(case),*args]
        q=subprocess.run(command,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=90)
        (case/f'{i}.txt').write_bytes(q.stdout);runs.append({'command':command,'exit_code':q.returncode,'log':f'{label}/{i}.txt'})
        if q.returncode:break
    assert (runs[-1]['exit_code']!=0) if reject else (len(runs)==4 and all(x['exit_code']==0 for x in runs)),label
    results.append({'case':label,'expected':'rejection' if reject else 'pass','accepted':True,'mutated_net_sha256':hashlib.sha256(data.encode()).hexdigest(),'runs':runs})
assert (src/'capture_routed.v').read_bytes()==raw
(out/'result.json').write_bytes((json.dumps({'source':str(src),'source_sha256':hashlib.sha256(raw).hexdigest(),'checker_hashes':{n:hashlib.sha256((out/n).read_bytes()).hexdigest() for n in scripts},'cases':results,'boundary':'Exact observed mapping and injected fault set only; not general formal CDC.'},indent=2)+'\n').encode())
print('RGB565_CDC_CONTROLS_PASS valid=1 rejected=4',out)
