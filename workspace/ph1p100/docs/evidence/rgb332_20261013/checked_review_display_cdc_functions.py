"""Check selected synchronous-reset AND functions in routed FIFO sync FFs.

PH1P slice selectors/defaults: local TD arch/ph1p_macro.v, PH1P_PHY_MSLICE.
This supplements Q/input-presence audit; it is not formal CDC or MTBF analysis.
"""
from pathlib import Path
import argparse,itertools,json,re,hashlib
p=argparse.ArgumentParser();p.add_argument('project',type=Path);a=p.parse_args()
root=a.project.resolve();text=(root/'capture_routed.v').read_text()
blocks=list(re.finditer(r'(?m)^  (PH1P_PHY_[LM]SLICE) #\(\n(.*?)\)\n    (\\\S+)  \(\n(.*?)\);',text,re.S))
by_name={m[3].lstrip('\\'):m for m in blocks}
prefix='u_ddrmc_test_top/u_capture/'

def and_inputs(truth):
    matches=[]
    for i,j in itertools.combinations(range(5),2):
        expected=sum((((n>>i)&1)&((n>>j)&1))<<n for n in range(32))
        if truth==expected:matches.append((i,j))
    assert len(matches)==1,('Not a two-input AND',f'{truth:08X}')
    return matches[0]

# Negative controls: altered truth table must reject; source-bit mismatch must
# also reject in the final equality check, independent of the presence audit.
try:and_inputs(0xCCCC0001)
except AssertionError:pass
else:raise AssertionError('Altered LUT truth table escaped')
rows=[]
for fifo in ['u_fifo','u_display_fifo']:
    d=json.loads((root/(fifo+'_cdc_audit.json')).read_text())
    links={x['to']:x for x in d['links']}
    for key,link in links.items():
        row=d['rows'][key];params=row['params'];pins=row['pins'];q=row['q_port']
        sel=params['REGA_SD' if q=='oqa' else 'REGB_SD']
        assert params.get('LUTMODE')=='DLUT5'
        assert params.get('ASRMUX')=='INV' and params.get('SSRMUX')=='0'
        assert params.get('CLKMUX')=='SIG'
        assert params.get('CEAMUX' if q=='oqa' else 'CEBMUX')=='1'
        assert params.get('REGA_REGSET_ASYNC' if q=='oqa' else 'REGB_REGSET_ASYNC')=='RESET'
        if sel in ['IMA','IMB']:
            assert link['kind']=='single_local_reset_and'
            source=prefix+fifo+'/'+link['from'];reset=link['local_reset'];truth=link['gate_lut_init']
            # Independently inspect the selected FF port and unique gate,
            # rather than trusting the presence audit's metadata.
            m=by_name[link['gate_instance']]
            gp={k:v.replace('\\','').replace(' ','') for k,v in re.findall(r'\.(\w+)\(([^)]+)\)',m[4])}
            ps=dict(re.findall(r'(?m)^    \.(\w+)\("([^"\n]+)"\)',m[2]))
            letter=link['gate_table'];output=link['gate_output']
            assert ps['LUTMODE']=='DLUT5' and ps['OFA_SD' if letter=='A' else 'OFB_SD']==('LUT5A' if letter=='A' else 'LUTX')
            assert pins[sel.lower()]==gp[output]
            value=int(re.search(r'\.INIT_LUT5'+letter+r"\(32'b([01]{32})\)",m[2])[1],2)
            i,j=and_inputs(value)
            ports=['ia','ib',ps.get('LUT5A_SD0','IC').lower(),'id',ps.get('LUT5A_SD1','IE').lower()] if letter=='A' else ['ia','ib','ic',ps.get('LUT5B_SD2','ID').lower(),'ie']
            assert {gp.get(ports[i]),gp.get(ports[j])}=={source,reset}
            assert f'{value:08X}'==truth
        else:
            assert sel in ['LUT5A','LUT6'],(key,sel)
            letter='A' if sel=='LUT5A' else 'B'
            m=by_name[row['instance']]
            match=re.search(r'\.INIT_LUT5'+letter+r"\(32'b([01]{32})\)",m[2]);assert match
            value=int(match[1],2);truth=f'{value:08X}';i,j=and_inputs(value)
            if letter=='A':
                c=params.get('LUT5A_SD0','IC');e=params.get('LUT5A_SD1','IE')
                assert c in ['IC','IMA'] and e in ['IE','IMF']
                ports=['ia','ib',c.lower(),'id',e.lower()]
            else:
                ds=params.get('LUT5B_SD2','ID');assert ds in ['ID','IMB']
                ports=['ia','ib','ic',ds.lower(),'ie']
            actual={pins.get(ports[i]),pins.get(ports[j])}
            source=prefix+fifo+'/'+link['from'];assert source in actual,(fifo,key,truth,actual,source)
            reset=next(v for v in actual if v!=source)
        assert re.fullmatch(re.escape(prefix)+r'(u_fifo/(?:rd|wr)_reset\[1\]|u_display_fifo/(?:rd|wr)_reset\[1\]|u_pack/rst_n(?:_dup_\d+)?|u_pixels/rst_n(?:_dup_\d+)?)',reset),(fifo,key,reset)
        rows.append({'fifo':fifo,'to':key,'source':source,'local_reset':reset,'select':sel,'truth':truth,'clock':pins['clk'],'asr':pins['asr'],'netlist_line':row['netlist_line']})
assert len(rows)==72
result={'checked_sync_ff_functions':len(rows),'negative_truth_table_rejected':True,'netlist_sha256':hashlib.sha256((root/'capture_routed.v').read_bytes()).hexdigest(),'selector_reference':'D:/downlaod/arch/ph1p_macro.v:420-422; DLUT5 LUT6 selects B table','rows':rows,'boundary':'Exact numeric two-input AND and selected FF input review. Reset alias origins, clock domains, skew and request/ack synchronizers must be separately checked. No formal CDC/MTBF claim.'}
(root/'display_cdc_functions.json').write_bytes((json.dumps(result,indent=2)+'\n').encode())
print('DISPLAY_CDC_FUNCTIONS',len(rows),'NEGATIVE_TRUTH_REJECTED')
