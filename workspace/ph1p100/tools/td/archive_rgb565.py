"""Archive reviewable, exact-byte evidence after native gates; no bit/DB/netlist upload."""
from pathlib import Path
import argparse,datetime,hashlib,json,re
p=argparse.ArgumentParser();p.add_argument('project',type=Path);a=p.parse_args()
ROOT=Path(__file__).resolve().parents[2];project=a.project.resolve()
assert project.parent==Path('D:/TD/work/csi2/prj').resolve() and project.name.startswith('camera_rgb565_')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest=json.loads((project/'input_manifest.json').read_bytes())
for name,digest in manifest.items():
    source=(project/name).resolve();assert source.is_relative_to(project) and sha(source)==digest,name
evidence=ROOT/'docs/evidence/rgb565_20261014';assert not evidence.exists();evidence.mkdir()
artifacts={}
def copy(source,rel):
    target=evidence/rel;assert not target.exists();target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(source.read_bytes());assert sha(target)==sha(source)
    artifacts[rel]={'source':str(source),'bytes':target.stat().st_size,'sha256':sha(target)}

tests=[]
for run in sorted(Path('D:/TD/work/csi2/_validation').glob('rgb565_20261014_*')):
    if not (run/'result.json').is_file():continue
    obj=json.loads((run/'result.json').read_bytes());prefix='g1/'+run.name+'/'
    copy(run/'result.json',prefix+'result.json')
    for name in ['0.log','1.log','2.log']:
        if (run/name).is_file():copy(run/name,prefix+name.replace('.log','.txt'))
    # Exact independent benches, golden CRC files, and transformed negative controls.
    for name in obj.get('inputs',{}):
        if name.startswith('tb_') or name=='baseline_adapter.v':copy(run/name,prefix+name)
    if (run/'golden_crc.txt').is_file():copy(run/'golden_crc.txt',prefix+'golden_crc.txt')
    if obj.get('stats_early'):copy(run/'bayer565_capture.v',prefix+'mutated_bayer565_capture.v.txt')
    tests.append({'path':str(run),'accepted':obj['accepted'],'test':obj['test'],'baseline':obj.get('baseline'),'production':obj.get('production'),'address_fault':obj.get('address_fault'),'stats_early':obj.get('stats_early'),'error':obj.get('error'),'result':prefix+'result.json'})

phases=[]
for stage in ['build','route','inspect','audit_hdmi','bitgen','export_debug']:
    obj=json.loads((project/('native_'+stage+'.json')).read_bytes());assert obj['exit_code']==0,stage
    phases.append(obj)
    for suffix in ['json','txt']:copy(project/('native_'+stage+'.'+suffix),'g2/native_'+stage+'.'+suffix)
copy(project/'camera_ddr_display_Runs/syn_1/run.log','g2/synthesis_worker.txt')
for name in ['input_manifest.json','rgb565_overlay.json','candidate_timing.rpt','candidate_ignored.rpt','candidate_abnormal.rpt','candidate_skew.rpt','capture.area','hdmi_clocks.rpt','hdmi_targets.txt','hdmi_data_paths.rpt','hdmi_selected_audit.json','hdmi_pad_excerpt.v.txt','rgb565_connections.json','rgb565_connections_excerpt.v.txt','u_fifo_cdc_audit.json','u_display_fifo_cdc_audit.json','display_cdc_functions.json','cdc_reset_clock_review.txt','u_fifo_cdc_excerpt.v','u_display_fifo_cdc_excerpt.v','export_matching_display_debug.tcl','pre_rgb565_review_display_cdc_origins.py.txt','cdc_origin_alias_initial_rejection.txt']:
    copy(project/name,'g2/'+name)
copy(project/'frozen_prepare_rgb565.py','g2/frozen_prepare_rgb565.py.txt')
copy(project/'frozen_rgb565_support.py','g2/frozen_rgb565_support.py.txt')
for name in ['f9p_camera_display_core.v','camera_ddr_display_top.v','ddrmc_display_top.v','build_rgb565.tcl','route_rgb565.tcl','inspect_rgb565.tcl','inspect_rgb332_body.tcl','bitgen_rgb565.tcl','bitgen_rgb332_body.tcl','audit_hdmi_rgb565.tcl','timing.sdc','board.adc']:
    copy(project/name,'source/'+name)
for name in ['audit_display_cdc.py','review_display_cdc_functions.py','review_display_cdc_origins.py','audit_rgb565_connections.py','audit_display_hdmi_pad.py','test_rgb565_cdc.py']:
    copy(ROOT/'tools/td'/name,'g2/'+name)

controls=[]
for run in sorted(Path('D:/TD/work/csi2/_validation').glob('rgb565_cdc_20261014_*')):
    if not (run/'result.json').is_file():continue
    data=json.loads((run/'result.json').read_bytes());assert data['source_sha256']==sha(project/'capture_routed.v')
    copy(run/'result.json','g2/controls/'+run.name+'/result.json')
    for case in data['cases']:
        for entry in case['runs']:copy(run/entry['log'],'g2/controls/'+run.name+'/'+entry['log'])
    controls.append(data)
assert len(controls)==1 and len(controls[0]['cases'])==5

timing=(project/'candidate_timing.rpt').read_text(errors='replace')
setup=re.search(r'SWNS: ([-+0-9.]+)ns, STNS: ([-+0-9.]+)ns',timing)
hold=re.search(r'HWNS: ([-+0-9.]+)ns, HTNS: ([-+0-9.]+)ns',timing)
period=re.search(r'Period Check WNS: ([-+0-9.]+)ns',timing)
assert setup and hold and period
assert min(float(setup[1]),float(hold[1]),float(period[1]))>=0 and float(setup[2])==float(hold[2])==0
assert 'End Point:' not in (project/'candidate_abnormal.rpt').read_text()
skew=(project/'candidate_skew.rpt').read_text();skews=[float(v) for v in re.findall(r'^Slack +: ([-+0-9.]+)ns',skew,re.M)]
assert len(re.findall(r'^[0-9]+,  set_path_skew',skew,re.M))==4 and len(skews)>=4 and min(skews)>=0
cdc=[json.loads((project/(name+'_cdc_audit.json')).read_bytes()) for name in ['u_fifo','u_display_fifo']]
assert sum(v['q_drivers'] for v in cdc)==108 and sum(v['same_bit_stage_links'] for v in cdc)==72
assert len(json.loads((project/'display_cdc_functions.json').read_bytes())['rows'])==72

obj={'recorded_at':datetime.datetime.now().astimezone().isoformat(),'project':str(project),'base_project':'D:/TD/work/csi2/prj/camera_rgb332_reference_20261013_215134','input_count':len(manifest),'input_manifest_sha256':sha(project/'input_manifest.json'),
     'bit':{'path':str(project/'camera_ddr_display.bit'),'bytes':(project/'camera_ddr_display.bit').stat().st_size,'sha256':sha(project/'camera_ddr_display.bit')},
     'selected_db':{'path':str(project/'csi_checked_debug_pr.db'),'sha256':sha(project/'csi_checked_debug_pr.db')},
     'routed_netlist_sha256':sha(project/'capture_routed.v'),'debug_file':{'path':str(project/'camera_ddr_display.cwc'),'sha256':sha(project/'camera_ddr_display.cwc')},
     'format':{'preview':[960,540],'display':[1920,1080,60],'camera_fps':30,'pixel':'RGB565 little-endian','payload_bytes':1036800,'frame_words':32401,'reference_rows':0,'gray_alternation':False},
     'g1_tests':tests,'g2':{'phases':phases,'setup_ns':float(setup[1]),'hold_ns':float(hold[1]),'period_ns':float(period[1]),'tns_zero':True,'skew_groups':4,'skew_ns':skews,'q_drivers':108,'sync_functions':72,'fault_controls':controls,'connections':json.loads((project/'rgb565_connections.json').read_bytes()),'hdmi':json.loads((project/'hdmi_selected_audit.json').read_bytes())},
     'g3':'not_run','g4':'not_run','hardware_download':False,'board_feedback':'Only the previous215134 has user-confirmed recovered live image; that does not validate this new bit.',
     'review':{'independent_readonly':'No confirmed datapath bug; identified missing FE/bad FE/early FE statistics coverage, added and passed with early-publication negative control.','worker_pack_review':'Minimal packer excerpt, text-only. Retracted speculative findings independently rejected; no actionable RTL change adopted.'},
     'cwc_note':'The frozen export_rgb565_debug.tcl draft contains an unused invalid command; it was not executed. Correct post-build export_matching_display_debug.tcl uses verified export_chipwatcher and is separately hashed. Frozen manifest and all RTL remain unchanged.',
     'limits':'Bayer phase/white balance/gamma and color matrix not calibrated; RGB565 precision alone does not prove red cast fixed. Preview decimation, not full-resolution ISP. Sparkles deferred, cause unresolved. HDMI serial electrical qualification, local clock warnings, timing coverage gaps and long-run stability remain. Selected structural CDC only. RAW capacity work is independent and not part of this bit.',
     'artifacts':artifacts}
(ROOT/'docs/evidence/rgb565_20261014.json').write_bytes((json.dumps(obj,indent=2)+'\n').encode())
print(json.dumps({'input_count':obj['input_count'],'bit':obj['bit'],'setup_ns':obj['g2']['setup_ns'],'hold_ns':obj['g2']['hold_ns'],'raw_artifacts':len(artifacts),'g3':obj['g3']},indent=2))
