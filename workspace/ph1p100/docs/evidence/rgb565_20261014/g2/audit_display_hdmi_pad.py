"""Check routed HDMI PAD configuration and all parallel input timing endpoints."""
from pathlib import Path
import argparse,hashlib,json,re
p=argparse.ArgumentParser();p.add_argument('project',type=Path);a=p.parse_args();r=a.project
source=r/'hdmi_data_paths.rpt';s=source.read_text();ends=re.findall(r'^End Point +: (\S+)',s,re.M)
for ch in range(3):
    found={int(n) for n in re.findall(r'O_hdmi_tx_p\['+str(ch)+r'\]_syn_2\.doq\[(\d+)\]',s)}
    assert found==set(range(10)),(ch,found)
assert len(ends)==68 and len(set(ends))==34
slacks=[float(v) for v in re.findall(r'^Slack +: ([-+0-9.]+)ns',s,re.M)];assert len(slacks)==68 and min(slacks)>=0
net=r/'capture_routed.v';n=net.read_text()
pads=list(re.finditer(r'(?m)^  PH1P_PHY_\w*PAD #\(\n.*?\);',n,re.S))
chosen=[m[0] for m in pads if re.search(r'\n    (?:\\)?O_hdmi_(?:tx_p\[[0-2]\]|clk_p)_syn_2 ',m[0])];assert len(chosen)==4
for z in chosen:assert '.IOTYPE("LVDS33_E")' in z and 'DDRX5' in z
obj={'report_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'netlist_sha256':hashlib.sha256(net.read_bytes()).hexdigest(),'paths':68,'endpoints':34,'channels':3,'bits_per_channel':10,'pads':4,'iotype':'LVDS33_E','serializer':'DDRX5','min_parallel_slack_ns':min(slacks),'boundary':'Parallel inputs only; does not qualify serial electrical/thermal behavior.'}
(r/'hdmi_selected_audit.json').write_bytes((json.dumps(obj,indent=2)+'\n').encode())
(r/'hdmi_pad_excerpt.v.txt').write_bytes(('\n\n'.join(chosen)+'\n').encode())
print('HDMI_SELECTED_AUDIT_PASS paths=68 endpoints=34 pads=4')
