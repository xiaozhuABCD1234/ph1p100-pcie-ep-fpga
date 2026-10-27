"""Confirm16 distinct sampled bits survived top-level implicit-net redeclaration."""
from pathlib import Path
import argparse,hashlib,json,re
p=argparse.ArgumentParser();p.add_argument('project',type=Path);a=p.parse_args();r=a.project
raw=(r/'capture_routed.v').read_bytes();s=raw.decode().replace('\r\n','\n')
blocks=list(re.finditer(r'(?m)^  PH1P_PHY_[LM]SLICE #\(\n.*?\);',s,re.S))
rows=[];selected={}
prefix='u_ddrmc_test_top/u_capture/u_pack/pixel'
assert 'wire [15:0] \\'+prefix+' ;' in s
for bit in range(16):
    net='\\'+prefix+' ['+str(bit)+']'
    outputs=[];uses=[]
    for m in blocks:
        pins=dict(re.findall(r'\.(\w+)\(([^)]+)\)',m[0]))
        for key,value in pins.items():
            if value==net:
                if key in ['oqa','oqb']:outputs.append((m,key,pins))
                elif key.startswith('i'):uses.append((m,key))
    assert len(outputs)==1 and len(uses)>=2,(bit,len(outputs),len(uses))
    m,q,pins=outputs[0];assert '../../bayer565_capture.v' in m[0] or 'u_cam_preview' in m[0]
    assert '.LATCHMODE("DFF")' in m[0]
    rows.append({'bit':bit,'q_port':q,'clock':pins['clk'],'netlist_line':s.count('\n',0,m.start())+1,'input_uses_in_slices':len(uses)})
    selected[m.start()]=m[0]
obj={'netlist_sha256':hashlib.sha256(raw).hexdigest(),'sampled_bits':16,'rows':rows,'boundary':'Confirms16 distinct sampled Q drivers and downstream uses; source/behavioral verification covers packing semantics, not a formal end-to-end netlist equivalence proof.'}
(r/'rgb565_connections.json').write_bytes((json.dumps(obj,indent=2)+'\n').encode())
(r/'rgb565_connections_excerpt.v.txt').write_bytes(('\n\n'.join('NETLIST_LINE '+str(s.count('\n',0,k)+1)+'\n'+selected[k] for k in sorted(selected))+'\n').encode())
print('RGB565_ROUTED_CONNECTIONS_PASS sampled_bits=16')
