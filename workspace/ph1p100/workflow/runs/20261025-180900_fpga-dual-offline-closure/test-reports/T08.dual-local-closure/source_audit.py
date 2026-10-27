from pathlib import Path
import sys,json,re,hashlib,collections
sys.path.insert(0,str(Path(__file__).parent));from tester_control import D,E,sha,save
m=json.loads((D.parent/'planning-input-manifest.json').read_text(encoding='utf-8-sig'))
rows=[]
for x in m['files']:
 p=Path(x['path']);actual=sha(p) if p.is_file() else None;rows.append(dict(path=str(p),expected=x['sha256'],actual=actual,match=actual==x['sha256']))
save(E/'planning-source-audit.json',dict(files=len(rows),mismatches=[x for x in rows if not x['match']],rows=rows))
print('UPSTREAM_FROZEN_SOURCES',len(rows),'mismatches',sum(not x['match'] for x in rows));assert all(x['match'] for x in rows)
old=D.parent.parent/'20261024-221529_fpga-sim-integration-recovery'/'T08.sync-production-sim'/'candidate'
changes=[]
for p in sorted((D/'candidate').rglob('*')):
 if p.is_file():
  q=old/p.relative_to(D/'candidate')
  if not q.is_file() or sha(p)!=sha(q):changes.append(dict(path=str(p),source=str(q),old_sha256=sha(q) if q.is_file() else None,new_sha256=sha(p)))
save(E/'tester-source-differences.json',changes);print('CANDIDATE_SOURCE_CHANGES',len(changes))
b10=Path(r'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b10-b9-fix\r0\td\src\camera\uisrc\03_ip\ui_imx415_cfg')
assert sha(b10/'ui_imx415_reg.v')==sha(D/'candidate/rtl/ep_side/cam/ui_imx415_reg.v'),'candidate mode table must remain exact frozen b10 input'
def mask(p):
 s=p.read_text(encoding='utf-8',errors='replace');a=s.index('function [7:0] read_mask');b=s.index('endfunction',a)+len('endfunction');return re.sub(r'\s+','',s[a:b])
assert mask(b10/'ui_cfg_imx415.v')==mask(D/'sync_i2c_config.v'),'read mask exact preservation'
compiled=json.loads((E/'build-baseline/sources.json').read_text());entries=[Path(x['path']) for x in compiled]
source_set={str(Path(x)) for x in (D/'sources.f').read_text().splitlines() if x.strip()}
assert source_set.issubset(set(map(str,entries)));assert len(compiled)==77
names=['cam_r10f_writer','ddr_frame_readback_checker','ddr_wr_arb','mipi_csi2_rx_ph1p_checked','sync_start_ctrl','sync_sof_mailbox','ui_i2c','dual_local_closure','sync_i2c_config']
definitions={n:[] for n in names}
for p in entries:
 text=p.read_text(encoding='utf-8',errors='replace')
 for n in names:
  if re.search(r'\bmodule\s+'+n+r'\b',text):definitions[n].append(str(p))
assert all(len(x)==1 for x in definitions.values()),definitions
warnings=[]
for label in ['build-baseline/vlog.log','case00/vsim.log','negative-b-release/vsim.log']:
 p=E/label
 if p.exists():
  lines=[x for x in p.read_text(errors='replace').splitlines() if 'Warning:' in x or 'Errors:' in x or '** Fatal' in x];warnings.append(dict(log=str(p),lines=lines))
save(E/'tester-warning-audit.json',warnings)
audit=dict(source_count=len(source_set),simulation_source_count=len(entries)-len(source_set),real_dut_definitions=definitions,mode_table_exact_frozen_b10=True,read_mask_exact_frozen_b10=True,cdc='writer async FIFO and sync_sof_mailbox/reset retained; new ownership/AR/R all w_ddr_dhi_clk; observations remain tl_clk_user 50MHz; no claim of physical CDC',reset='common w_ddrphy reset only; behavior model clears R queue at same reset',g2='not_run',g3_g4='not_run/awaiting_hardware',new_RTL_issues=['descriptor stall changed by higher-priority slot publication','same-cycle ext AR acceptance bypasses release exclusion'])
save(E/'tester-static-review.json',audit)
print('STATIC_AUDIT_COMPLETE',len(source_set),'source entries','no writer/checker/sync stubs')
