from pathlib import Path
import datetime,hashlib,json,shutil,difflib
H=Path(__file__).resolve().parent;R1=H.parent;R0=R1.parent;RUN=R0.parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
frozen=R1/'static-closeout01/manifest-r1.json'
assert sha(frozen)=='1b14a2201403389d4ae085e3c5f3141e382d600c9d3d50988527ad5eb617f544'
m=json.loads(frozen.read_text());assert all(Path(f['path']).is_file() and sha(Path(f['path']))==f['sha256'] for f in m['files'])
for p in (R1/'candidate').rglob('*'):
 if p.is_file():
  q=H/'candidate'/p.relative_to(R1/'candidate');q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
for n in ['run_t08.py','check_t08.py','r10f_oracle.py','vendor_env.sv','sensor_i2c.sv','sync_i2c_config.v','sync_frame_gate.v','tb_production_sync.sv','tb_production_sync_legacy.sv','tb_tester_edges.sv']:
 shutil.copyfile(R1/n,H/n)
old=(R1/'dual_local_closure.v').read_text()
s=old.replace(' wire ext_take=ext_arvalid&&ext_arready;', ''' wire ext_take=ext_arvalid&&ext_arready;
 // A publication or current-cycle request cannot be hidden by old registered idle state.
 wire mode_quiescent=(held==0)&&(sent==0)&&!a_offer&&!b_offer&&
   !a_pub_valid&&!b_pub_valid&&!ar_pending&&(outstanding==0)&&
   (state==WAIT)&&!c_busy&&!c_arvalid&&!ext_take&&!rvalid;''')
s=s.replace('if(held==0 && !ar_pending && outstanding==0 && state==WAIT) active_mode<=requested_mode;', 'if(mode_quiescent) active_mode<=requested_mode;')
s=s.replace('   a_release<=0;b_release<=0;\n   if(requested_mode', '''   a_release<=0;b_release<=0;
   // Offers belong only to mode2; an inactive consumer cannot retain a future valid.
   if(active_mode!=2) begin a_offer<=0;b_offer<=0;a_index<=0;b_index<=2;end
   if(requested_mode''')
assert s!=old and 'if(mode_quiescent)' in s and 'if(active_mode!=2)' in s
(H/'dual_local_closure.v').write_text(s)
(H/'mode-fix.diff').write_text(''.join(difflib.unified_diff(old.splitlines(True),s.splitlines(True),fromfile=(R1/'dual_local_closure.v').as_posix(),tofile=(H/'dual_local_closure.v').as_posix())))
fixtures=H/'fixtures';fixtures.mkdir(exist_ok=True)
(fixtures/'old_mode.v').write_text(old.replace('module dual_local_closure #(','module dual_local_closure_old_mode #(',1))
needle='if(rel_camera_id) b_release<=rel_slot_id?2:1;else a_release<=rel_slot_id?2:1;'
assert s.count(needle)==1
(fixtures/'bad_b_release.v').write_text(s.replace('module dual_local_closure #(','module dual_local_closure_bad_b #(',1).replace(needle,'if(rel_camera_id) a_release<=rel_slot_id?2:1;else a_release<=rel_slot_id?2:1;'))
dump={'start_shanghai_observed':'2026-10-25T21:44:22.2021802+08:00','conservative_deadline_shanghai':'2026-10-25T22:44:20+08:00','historical_calls':125,'historical_compiles':6,'historical_cases':32,'actual_implementation_repair_round':1,'r0_integrated':'FAIL','r1_integrated_started':False,'static_windows_experiments_added':0,'protected_manifest':str(frozen),'protected_manifest_sha256':sha(frozen),'protected_files_verified':len(m['files']),'protected_drift':0,'old_module_sha256':sha(R1/'dual_local_closure.v'),'new_module_sha256':sha(H/'dual_local_closure.v'),'tester_edges_used':1,'tester_edges_remaining':1}
(H/'start-and-baseline.json').write_text(json.dumps(dump,indent=2))
print('MODE_FIX_PREPARED protected_files='+str(len(m['files'])))
