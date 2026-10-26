"""Audit Q drivers and stage inputs in TD's routed PH1P slice netlist.
This is a structural preflight; LUT equations and physical skew need separate review.
"""
from pathlib import Path
import argparse,hashlib,json,re
p=argparse.ArgumentParser();p.add_argument('project',type=Path);p.add_argument('--fifo',choices=['u_fifo','u_display_fifo'],required=True);a=p.parse_args()
root=a.project.resolve();netlist=root/'capture_routed.v';text=netlist.read_text()
prefix='u_ddrmc_test_top/u_capture/'+a.fifo+'/'
pattern=r'(?m)^  (PH1P_PHY_[LM]SLICE) #\(\n(.*?)\)\n    (\\\S+)  \(\n(.*?)\);'
blocks=list(re.finditer(pattern,text,re.S))
vectors=['wgray','rgray','rq1_wgray','rq2_wgray','wq1_rgray','wq2_rgray']
rows={};selected={};cells=[]
normalize=lambda n:n.replace('\\','').replace(' ','')
for m in blocks:
    pins={k:normalize(v) for k,v in re.findall(r'\.(\w+)\(([^)]+)\)',m[4])}
    params={k:v for k,v in re.findall(r'(?m)^    \.(\w+)\("([^"\n]+)"\)',m[2])}
    cells.append((m,pins,params))
    for port in ['oqa','oqb']:
        net=pins.get(port,'')
        n=re.fullmatch(re.escape(prefix)+r'('+ '|'.join(vectors)+r')\[(\d+)\]',net)
        if not n:continue
        key=f'{n[1]}[{n[2]}]';assert key not in rows,('Multiple Q drivers',key)
        assert params.get('LATCHMODE')=='DFF',(key,params)
        assert params.get('OQAMUX' if port=='oqa' else 'OQBMUX')==('QA' if port=='oqa' else 'QB'),(key,port,params)
        rows[key]={'instance':m[3].lstrip('\\'),'q_port':port,'netlist_line':text.count('\n',0,m.start())+1,'pins':pins,'params':params}
        selected[m.start()]=m.group(0)
for v in vectors:
    for bit in range(9):assert f'{v}[{bit}]' in rows,('Missing Q driver',v,bit)
links=[]
for dst,src in [('rq1_wgray','wgray'),('rq2_wgray','rq1_wgray'),('wq1_rgray','rgray'),('wq2_rgray','wq1_rgray')]:
    for bit in range(9):
        key=f'{dst}[{bit}]';source=prefix+f'{src}[{bit}]'
        pins=[k for k,v in rows[key]['pins'].items() if v==source and k.startswith('i')]
        link={'from':f'{src}[{bit}]','to':key,'input_pins':pins,'kind':'direct_input_presence'}
        if not pins:
            # TD may place the local synchronous-reset AND in a separate LUT,
            # then use the destination FF's direct IMB input. Accept only this
            # exact one-gate topology; never traverse arbitrary logic cones.
            row=rows[key]
            assert dst in ['wq1_rgray','wq2_rgray'] and row['q_port']=='oqb' and row['params'].get('REGB_SD')=='IMB',('Missing same-bit input',key,source)
            net=row['pins'].get('imb')
            drivers=[(c,port) for c in cells for port in ['ofa','ofb'] if c[1].get(port)==net]
            assert len(drivers)==1,('Reset gate driver',key,net)
            (m,gpins,gparams),output=drivers[0]
            assert gparams.get('LUTMODE')=='DLUT5',('Reset gate mode',key)
            letter='A' if output=='ofa' else 'B'
            assert gparams.get('OFA_SD' if letter=='A' else 'OFB_SD')==('LUT5A' if letter=='A' else 'LUTX'),('Reset gate output',key)
            init=re.search(r"\.INIT_LUT5"+letter+r"\(32'b([01]{32})\)",m[2])
            assert init,('Missing reset gate truth table',key)
            truth=int(init[1],2)
            # Exact observed numeric AND mappings only; no arbitrary cone walk.
            if letter=='A':
                assert gparams.get('LUT5A_SD0','IC')=='IC',('Reset gate selector C',key)
                mapping={(0xCCCC0000,'IMF'):('ib','imf'),
                         (0xFF000000,'IE'):('id','ie'),
                         (0xFF000000,'IMF'):('id','imf')}
                selector=gparams.get('LUT5A_SD1','IE')
            else:
                mapping={(0xFF000000,'IMB'):('ie','imb')}
                selector=gparams.get('LUT5B_SD2','ID')
            assert (truth,selector) in mapping,('Reset AND truth table/selectors',key,letter)
            source_pin,reset_pin=mapping[truth,selector]
            assert gpins.get(source_pin)==source,('Reset gate source bit',key,gpins)
            reset=gpins.get(reset_pin,'')
            allowed=[prefix+'wr_reset[1]']
            if a.fifo=='u_fifo':
                assert reset in allowed or re.fullmatch(r'u_ddrmc_test_top/u_capture/u_pack/rst_n(?:_dup_\d+)?',reset),('Local reset input',key,reset)
            else:assert reset in allowed,('Local reset input',key,reset)
            link.update(kind='single_local_reset_and',input_pins=['imb'],gate_instance=m[3].lstrip('\\'),gate_lut_init=f'{truth:08X}',gate_output=output,gate_table=letter,local_reset=reset)
            selected[m.start()]=m.group(0)
        links.append(link)
excerpt=root/(a.fifo+'_cdc_excerpt.v');excerpt.write_bytes(('// Selected routed PH1P slice instances; not a standalone simulation module.\n\n'+'\n\n'.join(selected[k] for k in sorted(selected))+'\n').encode())
result={'netlist':str(netlist),'sha256':hashlib.sha256(netlist.read_bytes()).hexdigest(),'q_drivers':len(rows),'same_bit_stage_links':len(links),'selected_slice_cells':len(selected),'rows':rows,'links':links,'boundary':'Q-driver and input-presence checks, plus an exact single-LUT local-reset AND topology. Selected FF LUT equations, reset-alias origin, clocks, skew and metastability behavior require separate review.'}
(root/(a.fifo+'_cdc_audit.json')).write_bytes((json.dumps(result,indent=2)+'\n').encode())
print('CAPTURE_CDC_Q_BOUNDARIES',len(rows),'SAME_BIT_LINKS',len(links),'SLICES',len(selected))
