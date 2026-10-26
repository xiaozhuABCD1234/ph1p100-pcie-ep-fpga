"""Run one explicit native TD phase, recording original bytes and identities."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,subprocess,sys
if not __debug__:
    raise RuntimeError('Run native verification without Python -O.')
p=argparse.ArgumentParser();p.add_argument('project',type=Path);p.add_argument('stage',choices=['build','route','inspect','audit_hdmi','bitgen','export_debug']);p.add_argument('--timeout',type=int,default=1800);a=p.parse_args()
assert 1 <= a.timeout <= 7200
root=a.project.resolve();assert root.parent==Path('D:/TD/work/csi2/prj').resolve() and root.name.startswith('camera_rgb565_')
name={'export_debug':'export_matching_display_debug.tcl'}.get(a.stage,a.stage+'_rgb565.tcl')
manifest=json.loads((root/'input_manifest.json').read_bytes())
for rel,digest in manifest.items():
    f=(root/rel).resolve();assert f.is_relative_to(root) and hashlib.sha256(f.read_bytes()).hexdigest()==digest,rel
record=root/('native_'+a.stage+'.json');log=root/('native_'+a.stage+'.txt')
assert not record.exists() and not log.exists(),'Do not overwrite an execution; preserve failures.'
if a.stage=='export_debug':
    # An independently tracked post-build script, not a change to frozen RTL inputs.
    src=Path(__file__).resolve().parent/name
    assert not (root/name).exists();(root/name).write_bytes(src.read_bytes())
command=['D:/downlaod/bin/td_commands_prompt.exe','./'+name]
markers={'build':'RGB565_SYNTHESIS_RETURNED','route':'RGB565_ROUTE_RETURNED_CHECK_REPORTS_NO_BIT','inspect':'CAPTURE_CDC_AUDIT_EXPORTED','audit_hdmi':'HDMI_ROUTED_AUDIT_REPORTS_READY','bitgen':'CAMERA_DDR_DISPLAY_CANDIDATE_GENERATED_NO_DOWNLOAD','export_debug':'MATCHING_DISPLAY_CWC_EXPORTED_NO_DOWNLOAD'}
artifacts={'build':['camera_ddr_display_Runs/syn_1/camera_ddr_display_gate.db'],'route':['csi_checked_debug_pr.db','capture_timing.rpt','capture_skew.rpt','capture_ignored.rpt','capture_abnormal.rpt','capture.area'],'inspect':['capture_routed.v','capture_cdc_objects.txt'],'audit_hdmi':['hdmi_clocks.rpt','hdmi_targets.txt','hdmi_data_paths.rpt'],'bitgen':['camera_ddr_display.bit','camera_ddr_display_inst.bid','candidate_timing.rpt','candidate_skew.rpt','candidate_abnormal.rpt','candidate_ignored.rpt'],'export_debug':['camera_ddr_display.cwc','cw/compiled.cwc','cw/compiled.bit']}
reserve_overlay=root/'timing_overlay.json'
reserve=float(json.loads(reserve_overlay.read_bytes()).get('implementation_setup_reserve_ns',0)) if reserve_overlay.is_file() else 0
if a.stage=='route' and reserve:
    assert reserve==0.3
    artifacts['route'].append('implementation_guard_timing.rpt')
result={'stage':a.stage,'command':command,'cwd':str(root),'script_sha256':hashlib.sha256((root/name).read_bytes()).hexdigest(),'runner_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'input_manifest_sha256':hashlib.sha256((root/'input_manifest.json').read_bytes()).hexdigest(),'timeout_seconds':a.timeout,'started_at':datetime.datetime.now().astimezone().isoformat(),'hardware_download':False,'accepted':False}
try:
    with log.open('wb') as stream:
        q=subprocess.run(command,cwd=root,stdout=stream,stderr=subprocess.STDOUT,timeout=a.timeout)
    result['exit_code']=q.returncode
except subprocess.TimeoutExpired as error:
    result.update(exit_code=None,error=str(error),timed_out=True)
output=log.read_text(errors='replace')
result['expected_marker']=markers[a.stage]
result['marker_present']=markers[a.stage] in output
result['artifacts']={rel:hashlib.sha256((root/rel).read_bytes()).hexdigest() if (root/rel).is_file() and (root/rel).stat().st_size else None for rel in artifacts[a.stage]}
if a.stage!='build' and (root/'csi_checked_debug_pr.db').is_file():
    result['selected_db_sha256']=hashlib.sha256((root/'csi_checked_debug_pr.db').read_bytes()).hexdigest()
result['accepted']=result['exit_code']==0 and result['marker_present'] and all(result['artifacts'].values())
if a.stage=='route' and reserve:
    result['implementation_setup_reserve_ns']=reserve
    result['reserve_applied_and_cleared']=all(marker in output for marker in ['IMPLEMENTATION_SETUP_RESERVE_APPLIED_NS_0.300','IMPLEMENTATION_SETUP_RESERVE_CLEARED_FOR_NOMINAL_SIGNOFF'])
    result['accepted']=result['accepted'] and result['reserve_applied_and_cleared']
if a.stage=='route' and result['accepted']:
    timing=(root/'capture_timing.rpt').read_text(errors='replace')
    checks=[re.search(pattern,timing) for pattern in [r'SWNS: ([-+0-9.]+)ns, STNS: ([-+0-9.]+)ns',r'HWNS: ([-+0-9.]+)ns, HTNS: ([-+0-9.]+)ns',r'Period Check WNS: ([-+0-9.]+)ns']]
    result['sta_summary_present']=all(checks)
    if all(checks):
        setup,hold,period=checks
        result['sta']={'setup_ns':float(setup[1]),'setup_tns_ns':float(setup[2]),'hold_ns':float(hold[1]),'hold_tns_ns':float(hold[2]),'period_ns':float(period[1])}
        result['accepted']=min(float(setup[1]),float(hold[1]),float(period[1]))>=0 and float(setup[2])==float(hold[2])==0
    else:result['accepted']=False
result.update(ended_at=datetime.datetime.now().astimezone().isoformat(),log_sha256=hashlib.sha256(log.read_bytes()).hexdigest())
record.write_bytes((json.dumps(result,indent=2)+'\n').encode())
print(json.dumps(result,indent=2));print(output[-2200:]);sys.exit(0 if result['accepted'] else 1)
