from pathlib import Path
import hashlib, json, subprocess, zipfile, tarfile, io, datetime

ROOT = Path(__file__).resolve().parents[4]
RUN = Path(__file__).resolve().parents[1]
BACK = RUN / 'backup'
REF = RUN / 'references'
for directory in (BACK, REF):
    directory.mkdir(parents=True, exist_ok=True)

def sha(data): return hashlib.sha256(data).hexdigest()
def cmd(args, cwd=ROOT):
    done = subprocess.run(args, cwd=cwd, capture_output=True)
    if done.returncode:
        raise RuntimeError(str(args) + '\n' + done.stderr.decode('utf-8', errors='replace'))
    return done.stdout
def dump(path, obj): path.write_text(json.dumps(obj, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def listing(args): return [x.decode('utf-8') for x in cmd(args).split(b'\0') if x]

tracked = set(listing(['git','ls-files','--cached','-z']))
initial_run_files = {'dev-plan.md','dispatch.json','fpga-design-guide.md','input-index.md','main-log.md','progress-01.md','request.md','task-T03.rk-align-freeze.md','user-feedback-01.md'}
all_paths = sorted(set(listing(['git','ls-files','--cached','--others','--exclude-standard','-z'])))
all_paths = [n for n in all_paths if not (ROOT/n).is_relative_to(RUN) or (ROOT/n).relative_to(RUN).as_posix() in initial_run_files]
rows, exclusions, drifting = [], [], []
exclusions += [{'path':(RUN/x).relative_to(ROOT).as_posix(),'reason':'this-task output subtree excluded from original baseline; no recursive self-backup'} for x in ('backup','references','contract','artifacts','evidence','test-reports')]
archives = {}
for label in ('tracked','untracked'):
    archive = BACK / (label + '-worktree.zip')
    archives[label] = archive.as_posix()
    if archive.exists():
        with zipfile.ZipFile(archive) as z:
            for member in z.infolist():
                data=z.read(member.filename)
                rows.append({'path':member.filename,'bytes':len(data),'sha256':sha(data),'archive':archive.name,'ownership':'original baseline archive retained after restore long-path failure'})
        continue
    with zipfile.ZipFile(archive, 'x', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name in all_paths:
            if ('tracked' if name in tracked else 'untracked') != label: continue
            p = ROOT / name
            reason = None
            if p.is_relative_to(RUN) and p.relative_to(RUN).as_posix() not in initial_run_files:
                reason = 'this-task newly created outputs; excluded to avoid recursive self-backup'
            elif p.name.lower().startswith('.env') or p.suffix.lower() in {'.pem','.p12','.pfx','.key'} or p.name.lower() in {'credentials','credentials.json','id_rsa','id_ed25519'}:
                reason = 'credential/environment path excluded without reading'
            elif p.is_symlink(): reason = 'symlink excluded; no traversal outside scope'
            elif not p.is_file(): reason = 'tracked path absent/non-regular at baseline'
            if reason:
                exclusions.append({'path':name,'reason':reason}); continue
            data = p.read_bytes()
            z.writestr(name, data)
            row = {'path':name,'bytes':len(data),'sha256':sha(data),'archive':archive.name,'ownership':'tracked baseline or previous run' if not p.is_relative_to(RUN) else 'current planner input at baseline'}
            rows.append(row)
            if sha(p.read_bytes()) != row['sha256']: drifting.append(name)

bundle = BACK/'all-refs.bundle'
if not bundle.exists(): cmd(['git','bundle','create',str(bundle),'--all'])
verified = subprocess.run(['git','bundle','verify',str(bundle)], cwd=ROOT,capture_output=True)
(BACK/'bundle-verify.log').write_bytes(verified.stdout+verified.stderr)
if verified.returncode: raise RuntimeError('bundle verify failed')
if not (BACK/'dirty.patch').exists(): (BACK/'dirty.patch').write_bytes(cmd(['git','diff','--binary','HEAD']))
if not (BACK/'git-status-before.txt').exists(): (BACK/'git-status-before.txt').write_bytes(cmd(['git','status','--porcelain=v1','-uall']))
external = Path('D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820')
manifest = json.loads((external/'input_manifest.json').read_text(encoding='utf-8-sig'))
external_rows, original_mismatches = [], []
external_names = set(manifest) | {'input_manifest.json','camera_ddr_display.al','camera_ddr_display.bit','camera_ddr_display.cwc','native_build.json','native_route.json','native_bitgen.json','native_export_debug.json'}
rollback_exists=(BACK/'rollback-002820.zip').exists()
with zipfile.ZipFile(BACK/'rollback-002820.zip','r' if rollback_exists else 'x',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for name in sorted(external_names):
        p=external/name
        if not p.is_file(): raise RuntimeError('missing rollback dependency: '+name)
        data=z.read(name) if rollback_exists else p.read_bytes()
        if not rollback_exists: z.writestr(name,data)
        row={'path':name,'source_path':p.as_posix(),'bytes':len(data),'sha256':sha(data),'archive':'rollback-002820.zip'}
        if name in manifest:
            row['original_manifest_sha256']=manifest[name]
            if row['sha256'] != manifest[name]: original_mismatches.append(name)
        external_rows.append(row)

# New restoration directory; never overwrite the live worktree or external project.
restore = Path('\\\\?\\'+str((BACK/'restore-check-v2').resolve()))
restore.mkdir(exist_ok=False)
for label, selected in [('tracked',rows),('untracked',rows),('rollback',external_rows)]:
    archive = BACK/('rollback-002820.zip' if label=='rollback' else label+'-worktree.zip')
    target=restore/label; target.mkdir()
    with zipfile.ZipFile(archive) as z:
        for row in selected:
            if row['archive']!=archive.name: continue
            rel=Path(row['path'])
            if rel.is_absolute() or '..' in rel.parts: raise RuntimeError('unsafe archive path')
            p=target/rel; p.parent.mkdir(parents=True,exist_ok=True)
            p.write_bytes(z.read(row['path']))
            if sha(p.read_bytes())!=row['sha256']: raise RuntimeError('restoration SHA mismatch')

peer_rows=[]
for name,repo,commit in [
 ('peer-fpga-2a4b253','C:/Users/czz/AppData/Local/Temp/opencode/ref_ph1p100_fpga','2a4b253d9f2e56a943f1667b2a7a366824dcba34'),
 ('peer-driver-a0215c5','C:/Users/czz/AppData/Local/Temp/opencode/ref_ph1p100_driver','a0215c5a2fcb95bfc867a4768d4831d68edf64a2')]:
    actual=cmd(['git','rev-parse',commit+'^{commit}'],repo).decode().strip()
    if actual!=commit: raise RuntimeError('commit pin mismatch')
    tar_data=cmd(['git','archive','--format=tar',commit],repo)
    (REF/(name+'.tar')).write_bytes(tar_data)
    target=REF/name; target.mkdir(exist_ok=False)
    entries=[]
    with tarfile.open(fileobj=io.BytesIO(tar_data),mode='r:') as tar:
        for member in tar.getmembers():
            rel=Path(member.name)
            if rel.is_absolute() or '..' in rel.parts or member.issym() or member.islnk(): raise RuntimeError('unsafe upstream archive member')
            if not member.isfile(): continue
            data=tar.extractfile(member).read(); p=target/rel
            p.parent.mkdir(parents=True,exist_ok=True); p.write_bytes(data)
            entries.append({'path':member.name,'bytes':len(data),'sha256':sha(data)})
    peer_rows.append({'name':name,'commit':commit,'source_git':repo,'commit_metadata':cmd(['git','show','-s','--format=%H%n%aI%n%cI%n%s',commit],repo).decode('utf-8',errors='replace').strip(),'archive':(REF/(name+'.tar')).as_posix(),'archive_sha256':sha(tar_data),'files':entries,'license':'No repository LICENSE/COPYING in pinned tree. Vendor IP/encrypted cores and reference documents retain their owners rights; private local use only; redistribution permission not established.'})
dump(REF/'provenance.json',{'schema_version':1,'upstreams':peer_rows})

drift_end=[]
for row in rows:
    p=ROOT/row['path']
    if not p.is_file() or sha(p.read_bytes())!=row['sha256']: drift_end.append(row['path'])
stable_retakes=[]
for name in sorted(set(drifting+drift_end)):
    p=ROOT/name
    if not p.is_file(): continue
    data=p.read_bytes(); digest=sha(data)
    if sha(p.read_bytes()) != digest: raise RuntimeError('baseline file remains unstable: '+name)
    target=BACK/'stable-retake'/name; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(data)
    stable_retakes.append({'path':name,'backup_path':target.as_posix(),'sha256':digest,'bytes':len(data)})
dump(BACK/'baseline-manifest.json',{
 'schema_version':1,'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'project_root':ROOT.as_posix(),
 'head':cmd(['git','rev-parse','HEAD']).decode().strip(),'branch':cmd(['git','branch','--show-current']).decode().strip(),
 'remotes':cmd(['git','remote','-v']).decode().strip(),'worktrees':cmd(['git','worktree','list','--porcelain']).decode().strip(),
 'scope':'tracked + pre-existing nonignored untracked, including previous runs and nine initial planner run files; git ignored paths are outside baseline scope; new output trees excluded explicitly',
 'files':rows,'excluded':exclusions,'rollback':external_rows,'original_rollback_manifest_mismatches':original_mismatches,
 'drift_during_copy':drifting,'drift_at_end':drift_end,'stable_retakes':stable_retakes,
 'bundle':{'path':bundle.as_posix(),'sha256':sha(bundle.read_bytes()),'verify_exit_code':verified.returncode,'log':(BACK/'bundle-verify.log').as_posix()},
 'restore_check':{'path':restore.as_posix(),'files_verified':len(rows)+len(external_rows),'result':'all listed archived bytes restored and SHA256 verified'},
 'artifacts':[{'path':p.name,'bytes':p.stat().st_size,'sha256':sha(p.read_bytes())} for p in BACK.glob('*.zip')],
 'bayer_worktree':{'path':'C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道','head':cmd(['git','rev-parse','HEAD'],'C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道').decode().strip(),'status':cmd(['git','status','--porcelain=v1','-uall'],'C:/Users/czz/.codex/worktrees/bayer-codec-reference/FPGA创新设计赛道').decode('utf-8',errors='replace'),'policy':'read-only; not copied/merged; branch refs included in all-refs.bundle'}
})
print(json.dumps({'root_files':len(rows),'rollback_files':len(external_rows),'original_rollback_mismatches':original_mismatches,'drift_at_end':drift_end,'stable_retakes':len(stable_retakes),'peer_files':[len(x['files']) for x in peer_rows],'restore_verified':len(rows)+len(external_rows)},ensure_ascii=False))
