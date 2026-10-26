from pathlib import Path
import hashlib,json,shutil,subprocess,time
H=Path(__file__).resolve().parent
ROOT=Path(r'D:\fpga\ph1p100')
RUN=H.parent
OLD=ROOT/'workflow/runs/20261024-221529_fpga-sim-integration-recovery/T08.sync-production-sim'
M=json.loads((RUN/'planning-input-manifest.json').read_text(encoding='utf-8-sig'))
rows=[]
for entry in M['files']:
 p=Path(entry['path']); b=p.read_bytes(); sha=hashlib.sha256(b).hexdigest()
 if sha!=entry['sha256'].lower() or len(b)!=entry['bytes']:raise RuntimeError('planning input drift: '+str(p))
 rows.append({'path':str(p),'sha256':sha,'bytes':len(b),'verified':True})
 if p.is_relative_to(OLD/'candidate'):
  q=H/'candidate'/p.relative_to(OLD/'candidate');q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
for name in ['run_t08.py','vendor_env.sv','tb_production_sync.sv','sync_frame_gate.v','sync_i2c_config.v','sensor_i2c.sv']:
 p=OLD/name
 if not any(r['path']==str(p) for r in rows):raise RuntimeError('unfrozen reference '+name)
 shutil.copyfile(p,H/name)
(H/'planning-input-audit.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
status=subprocess.run(['git','status','--short','--untracked-files=no'],cwd=ROOT,capture_output=True,timeout=60)
(H/'worktree-before.txt').write_bytes(status.stdout+status.stderr)
(H/'prepare-result.json').write_text(json.dumps({'inputs_verified':len(rows),'root':str(ROOT),'time':time.time(),'git_exit':status.returncode},indent=2),encoding='utf-8')
print('PREPARE_OK verified',len(rows))
