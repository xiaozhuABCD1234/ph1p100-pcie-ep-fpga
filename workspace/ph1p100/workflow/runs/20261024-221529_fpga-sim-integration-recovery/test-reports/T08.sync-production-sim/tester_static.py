from pathlib import Path
import hashlib,json,re,sys
E=Path(__file__).resolve().parent;R=E.parent.parent;T=R/'T08.sync-production-sim'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
mapping=json.loads((T/'source-to-overlay.json').read_text())
changed=[]
for x in mapping:
    source,overlay=Path(x['source']),Path(x['overlay'])
    a,b=sha(source),sha(overlay)
    assert a==x['source_sha256'] and b==x['overlay_sha256']
    assert (a!=b)==x['changed']
    if a!=b:changed.append(str(overlay.relative_to(T/'candidate')))
assert set(changed)=={r'rtl\ep_side\cam\ui_cfg_imx415.v',r'rtl\ep_side\ph1p_pcie_ep_top.v'}
original=(R/'inputs/production-raw/rtl/ep_side/cam/ui_cfg_imx415.v').read_text(encoding='utf-8')
overlay=(T/'candidate/rtl/ep_side/cam/ui_cfg_imx415.v').read_text(encoding='utf-8')
legacy_original=original[original.index('localparam CAM_ID'):]
legacy_overlay=overlay[overlay.index('localparam CAM_ID'):].replace('end endgenerate\n','')
assert legacy_original==legacy_overlay, 'SYNC_ENABLE=0 legacy configuration body changed'
top=(T/'candidate/rtl/ep_side/ph1p_pcie_ep_top.v').read_text(encoding='utf-8')
checks={
 'sync_default_off':"parameter SYNC_ENABLE = 1'b0" in top,
 'production_wait_24ms':re.search(r'SYNC_WAIT_CYCLES\s*=\s*1200000',top) is not None and 50_000_000*24//1000==1_200_000,
 'production_divider':re.search(r'CAM_I2C_DIV\s*=\s*624',top) is not None,
 'production_roi_default':all(re.search(k+r'\s*=\s*'+str(v)+r'\b',top) is not None for k,v in
     {'CAMDDR_W':1920,'CAMDDR_H':1080,'CAMDDR_X0':960,'CAMDDR_Y0':540,'CAMDDR_SKIP_ROWS':37}.items()),
 'unique_request_routing':all(x in top for x in ['sync_camera ? sync_b_ready : sync_a_ready',
     "sync_req_valid && sync_req_ready && (sync_camera==1'b0)",
     "sync_req_valid && sync_req_ready && (sync_camera==1'b1)"]),
 'pre_gate_sof_measurement':'.sof_a(w_a_vsync),.sof_b(w_b_vsync)' in top,
 'warmup_eight':'.WARMUP_FRAMES(8)' in top,
 'real_dual_writer':all(x in top for x in ['u_cam_r10f_writer (','u_cam_r10f_writer_b (']),
 'legacy_config_body_exact':legacy_original==legacy_overlay,
}
assert all(checks.values()),checks
assert (1920*10+7)//8*1080==2_592_000
assert ((2_592_000+128+4095)//4096)*4096==2_592_768
vlog=(E/'build/vlog.log').read_text(encoding='utf-8',errors='replace')
vsim=(E/'clean/vsim.log').read_text(encoding='utf-8',errors='replace')
cw=[x for x in vlog.splitlines() if '** Warning:' in x]
ew=[x for x in vsim.splitlines() if '** Warning:' in x]
assert len(cw)==1 and 'pcie_ep_engine.v(127)' in cw[0] and '[RDGN]' in cw[0]
assert len(ew)==37 and all('Too few port connections' in x or 'Missing connection for port' in x for x in ew)
ports=re.findall(r"Missing connection for port '([^']+)'",vsim)
expected={'pcie_tx_p','pcie_tx_n','cam_a_mclk','cam_a_xclr_n','cam_b_mclk','cam_b_xclr_n','txd','debug_led',
 'ddr_ck_p','ddr_ck_n','ddr_reset_n','ddr_cke','ddr_odt','ddr_cs_n','ddr_ras_n','ddr_cas_n','ddr_we_n','ddr_ba','ddr_addr',
 'ddr_dqs_p','ddr_dqs_n','ddr_dq','ddr_dm','O_dbg_idx','O_dbg_busy','dbg_drop','cl_release','cl_pub_valid','cl_pub_seq',
 'cl_pub_base','cl_pub_session','cl_pub_len','cl_good_count','cl_bad_count'}
assert set(ports)==expected
writer=(T/'candidate/rtl/ep_side/ddr/cam_r10f_writer.v').read_text(encoding='utf-8')
cl=[{'line':n,'text':line.strip()} for n,line in enumerate(writer.splitlines(),1) if 'cl_release' in line]
result={'pass':True,'mapping_entries':len(mapping),'unchanged_copies':len(mapping)-len(changed),'changed_copies':changed,
 'checks':checks,'compile_warning_count':len(cw),'elaboration_warning_count':len(ew),'missing_ports':ports,
 'cl_release_uses':cl,'production_payload_bytes':2_592_000,'production_dma_bytes':2_592_768,
 'simulation_payload_bytes':20,'simulation_dma_bytes':4096,'python_version':sys.version,
 'scope':'static wiring/default/manifest audit only; no STA/CDC implementation qualification'}
(E/'tester-static.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
(E/'tester-warning-audit.txt').write_text('\n'.join(cw+ew),encoding='utf-8')
print(json.dumps(result))
