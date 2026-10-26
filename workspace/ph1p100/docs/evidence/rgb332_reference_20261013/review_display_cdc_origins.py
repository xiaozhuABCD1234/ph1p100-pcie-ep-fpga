"""Bounded routed FIFO clock/reset and toggle-origin review; not formal CDC."""
from pathlib import Path
import argparse,re,json,itertools,hashlib
p=argparse.ArgumentParser();p.add_argument('project',type=Path);a=p.parse_args();r=a.project
s=(r/'capture_routed.v').read_text()
blocks=list(re.finditer(r'(?m)^  (PH1P_PHY_[LM]SLICE) #\(\n(.*?)\)\n    (\\\S+)  \(\n(.*?)\);',s,re.S))
def pins(m):return {k:v.replace('\\','').replace(' ','') for k,v in re.findall(r'\.(\w+)\(([^)]+)\)',m[0])}
def params(m):return dict(re.findall(r'(?m)^    \.(\w+)\("([^"\n]+)"\)',m[2]))
qs={}
for m in blocks:
 for q in ['oqa','oqb']:
  if q in pins(m):
   assert pins(m)[q] not in qs
   qs[pins(m)[q]]=(m,q)
roots={}
for m in re.finditer(r'(?m)^  PH1P_PHY_SCLK\b[\s\S]*?(?=^  \w|\Z)',s):
 z=pins(m)
 if 'clkout' in z:roots[z['clkout']]=z['clkin']

# TD can retain the packet-clock name when the preview module changes.
# Accept that exact alias only after tracing its GCLK back to the PHY divider.
capture_rows=json.loads((r/'u_fifo_cdc_audit.json').read_text())['rows']
capture_roots={roots[v['pins']['clk']] for key,v in capture_rows.items() if key.startswith('wgray[')}
assert len(capture_roots)==1
capture_root=next(iter(capture_roots))
assert capture_root in ['u_camera/u_cam_preview/I_bc_clk','u_camera/u_csi_a/u_packet/I_clock']
if capture_root=='u_camera/u_csi_a/u_packet/I_clock':
 gs=[pins(m) for m in re.finditer(r'(?m)^  PH1P_PHY_GCLK\b[\s\S]*?(?=^  \w|\Z)',s) if pins(m).get('clkout')==capture_root]
 assert len(gs)==1 and gs[0]['clkin'].endswith(',u_camera/u_csi_a/u_rx_phy/w_byte_clk_div}')
 assert gs[0]['cen']=="2'b00" and gs[0]['seln']=="2'b10" and gs[0]['drct']=="2'b11"
def clk(m):return roots[pins(m)['clk']]
def direct(net):
 m,q=qs[net];z=pins(m);v=params(m);letter='A' if q=='oqa' else 'B'
 assert v['LATCHMODE']=='DFF' and v['ASRMUX']=='INV' and v['SSRMUX']=='0' and v['CLKMUX']=='SIG'
 assert v['CE'+letter+'MUX']=='1' and v['REG'+letter+'_REGSET_ASYNC']=='RESET'
 sel=v['REG'+letter+'_SD'];assert sel in ['IMA','IMB']
 return z[sel.lower()],m
pref='u_ddrmc_test_top/u_capture/';out=[];selected={};asrs=set()
def retain(m):selected[m.start()]=m[0]
f=json.loads((r/'display_cdc_functions.json').read_text())
for fifo in ['u_fifo','u_display_fifo']:
 d=json.loads((r/(fifo+'_cdc_audit.json')).read_text())
 for vec in ['wgray','rgray','rq1_wgray','rq2_wgray','wq1_rgray','wq2_rgray']:
  rr=[v for k,v in d['rows'].items() if k.startswith(vec+'[')]
  write=vec in ['wgray','wq1_rgray','wq2_rgray']
  expected=(capture_root if write else pref+'clk') if fifo=='u_fifo' else (pref+'clk' if write else 'u_camera/X_hdmi_tx/I_pixel_clk')
  assert {roots[v['pins']['clk']] for v in rr}=={expected}
  out.append(f'{fifo}/{vec}: {len(rr)} Qs, clock root={expected}')
  asrs.update(v['pins']['asr'] for v in rr)
for net in sorted({x['local_reset'] for x in f['rows']}):
 stage0,m=direct(net);one,m0=direct(stage0);assert one=="1'b1" and clk(m)==clk(m0)
 assert re.fullmatch(re.escape(pref)+r'(cap_reset|pixel_reset|u_display_fifo/wr_reset)\[0\]',stage0)
 retain(m);retain(m0);asrs.update([pins(m)['asr'],pins(m0)['asr']]);out.append(f'{net}: 1 -> {stage0} -> local reset, clock root={clk(m)}')
 # A shared reset alias is valid only within the destination clock domain.
 for row in [x for x in f['rows'] if x['local_reset']==net]:
  assert clk(m)==roots[row['clock']],('Reset domain mismatch',row['fifo'],row['to'],net)
for x,y,origin in [('u_reader/rq1','u_reader/rq2','u_pixels/expected_epoch'),('u_pixels/ack1','u_pixels/ack2','u_reader/ack_toggle')]:
 u,m=direct(pref+x);v,n=direct(pref+y);assert u==pref+origin and v==pref+x and clk(m)==clk(n)
 src,_=qs[pref+origin];assert params(src)['LATCHMODE']=='DFF' and clk(src)!=clk(m)
 for z in [m,n,src]:retain(z)
 out.append(f'{origin} (registered, {clk(src)}) -> {x} -> {y} ({clk(m)})')
for net in sorted(asrs):
 ds=[(m,port) for m in blocks for port in ['ofa','ofb'] if pins(m).get(port)==net];assert len(ds)==1,(net,len(ds))
 m,port=ds[0];z=pins(m);v=params(m);assert v['LUTMODE']=='DLUT5';letter='A' if port=='ofa' else 'B'
 assert v.get('OFA_SD' if letter=='A' else 'OFB_SD')==('LUT5A' if letter=='A' else 'LUTX')
 truth=int(re.search(r'\.INIT_LUT5'+letter+r"\(32'b([01]{32})\)",m[2])[1],2)
 comb=[inds for inds in itertools.combinations(range(5),3) if sum(int(all((k>>i)&1 for i in inds))<<k for k in range(32))==truth];assert len(comb)==1
 pp=['ia','ib',v.get('LUT5A_SD0','IC').lower(),'id',v.get('LUT5A_SD1','IE').lower()] if letter=='A' else ['ia','ib','ic',v.get('LUT5B_SD2','ID').lower(),'ie']
 actual={z[pp[i]] for i in comb[0]};assert 'u_camera/display_rst_n' in actual and len(actual)==3
 assert any(x.endswith('u_ddrphy_fiu_wrapper/rst_n') for x in actual)
 assert any(re.fullmatch(re.escape(pref)+r'ddr_ready(?:_dup_\d+)?',x) for x in actual)
 out.append(f'{net}: numeric 3-input AND {sorted(actual)}');retain(m)
text='NETLIST_SHA256='+hashlib.sha256((r/'capture_routed.v').read_bytes()).hexdigest()+'\n'+'\n'.join(out)+'\n\nBOUNDARY: structural/direct-function and named source-net checks only. DDR ready replica generation, reset recovery/removal, metastability/MTBF and all-system CDC are not formally proven.\n\n'
text+='\n\n'.join('NETLIST_LINE '+str(s.count('\n',0,k)+1)+'\n'+selected[k] for k in sorted(selected))
(r/'cdc_reset_clock_review.txt').write_bytes(text.encode());print('BOUNDARY_REVIEW_PASS',len(asrs),'COMMON_RESET_ALIASES',len(selected),'EXCERPT_CELLS')
