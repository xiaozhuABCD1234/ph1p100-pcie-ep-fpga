from pathlib import Path, PurePosixPath, PureWindowsPath
import collections, datetime, hashlib, io, json, os, stat, subprocess, tarfile, zipfile

ROOT = Path.cwd().resolve()
RUN = ROOT / 'workflow/runs/20261017-011744-rk-fpga-align'
OUT = RUN / 'test-reports/engineering-r0-evidence'
EXPECTED_MANIFEST = '9662167a4af6fcea43a76491a9507b191552fa52209648147de02f91cfd877c5'
assert OUT.resolve().is_relative_to(RUN.resolve())
RESULT = {'started_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'errors': [], 'commands': []}

def digest(data): return hashlib.sha256(data).hexdigest()
def filehash(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''): h.update(chunk)
    return h.hexdigest()
def load(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def check(ok, message):
    if not ok: RESULT['errors'].append(message)
def relative(name):
    p, w = PurePosixPath(name), PureWindowsPath(name)
    if not name or '\\' in name or ':' in name or p.is_absolute() or w.is_absolute() or '..' in p.parts:
        raise ValueError('unsafe member: ' + name)
    return Path(*p.parts)
def extended(path): return Path('\\\\?\\' + str(path.resolve()))
def command(args, cwd=ROOT, binary=False):
    p = subprocess.run(args, cwd=cwd, capture_output=True, timeout=60)
    entry = {'argv': [str(a) for a in args], 'cwd': str(cwd), 'exit_code': p.returncode}
    n = len(RESULT['commands'])
    if binary:
        entry.update(stdout_bytes=len(p.stdout), stdout_sha256=digest(p.stdout), stderr=p.stderr.decode('utf-8', 'replace'))
    else:
        for label, data in [('stdout', p.stdout), ('stderr', p.stderr)]:
            log = OUT / ('command-%02d-%s.log' % (n, label))
            log.write_bytes(data)
            entry[label + '_log'] = str(log)
            entry[label] = data.decode('utf-8', 'replace')
    RESULT['commands'].append(entry)
    check(p.returncode == 0, 'command failed: ' + str(args))
    return p

manifest_path = RUN / 'candidate-manifest.json'
check(filehash(manifest_path) == EXPECTED_MANIFEST, 'manifest hash mismatch at start')
manifest, baseline = load(manifest_path), load(RUN/'backup/baseline-manifest.json')
RESULT['manifest_sha256_start'] = filehash(manifest_path)
RESULT['manifest_files'] = len(manifest['files'])
seen = set()
for row in manifest['files']:
    p = RUN / relative(row['relative_path'])
    check(p.resolve().is_relative_to(RUN.resolve()), 'candidate path escapes run: ' + row['relative_path'])
    check(p.resolve() == Path(row['path']).resolve(), 'candidate absolute/relative mismatch: ' + row['relative_path'])
    check(not p.is_symlink(), 'candidate symlink: ' + row['relative_path'])
    check(row['relative_path'].casefold() not in seen, 'candidate duplicate: ' + row['relative_path'])
    seen.add(row['relative_path'].casefold())
    check(p.is_file() and p.stat().st_size == row['bytes'] and filehash(p) == row['sha256'], 'candidate bytes/hash mismatch: ' + row['relative_path'])

RESULT['archives'] = []
total_restored = 0
all_root_names = []
for archive_name in ['tracked-worktree.zip', 'untracked-worktree.zip', 'rollback-002820.zip']:
    archive = RUN / 'backup' / archive_name
    rows = baseline['rollback'] if archive_name.startswith('rollback') else [r for r in baseline['files'] if r['archive'] == archive_name]
    reference = next(r for r in baseline['artifacts'] if r['path'] == archive_name)
    check(filehash(archive) == reference['sha256'] and archive.stat().st_size == reference['bytes'], 'archive hash/length mismatch: ' + archive_name)
    target = OUT / ('restored-' + archive_name.removesuffix('.zip'))
    dest = extended(target)
    dest.mkdir(exist_ok=False)
    with zipfile.ZipFile(archive) as z:
        infos = z.infolist()
        names = [i.filename for i in infos]
        check(len(names) == len(set(n.casefold() for n in names)), 'ZIP duplicate/case collision: ' + archive_name)
        check(set(names) == {r['path'] for r in rows}, 'ZIP members differ from baseline: ' + archive_name)
        check(z.testzip() is None, 'ZIP CRC failed: ' + archive_name)
        info_by_name = {i.filename: i for i in infos}
        for row in rows:
            rel = relative(row['path'])
            info = info_by_name[row['path']]
            check(not stat.S_ISLNK(info.external_attr >> 16), 'ZIP contains symlink: ' + row['path'])
            data = z.read(info)
            check(len(data) == row['bytes'] and digest(data) == row['sha256'], 'ZIP bytes mismatch: ' + row['path'])
            p = dest / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            with p.open('xb') as f: f.write(data)
            check(filehash(p) == row['sha256'] and p.stat().st_size == row['bytes'], 'restored bytes mismatch: ' + row['path'])
            total_restored += 1
    RESULT['archives'].append({'archive': archive_name, 'sha256': filehash(archive), 'members': len(rows), 'restore_target': str(target), 'status': 'verified'})
    if not archive_name.startswith('rollback'): all_root_names += [r['path'] for r in rows]
check(len(all_root_names) == len(set(n.casefold() for n in all_root_names)), 'root archive sets overlap')
RESULT['restored_files'] = total_restored
RESULT['root_archive_files'] = len(all_root_names)

tracked = command(['git', 'ls-files', '-z']).stdout.decode('utf-8').split('\0')[:-1]
tracked_archive = {r['path'] for r in baseline['files'] if r['archive'] == 'tracked-worktree.zip'}
RESULT['tracked_coverage'] = {'git_tracked': len(tracked), 'archived_tracked': len(tracked_archive), 'missing': sorted(set(tracked)-tracked_archive), 'extra': sorted(tracked_archive-set(tracked))}
check(set(tracked) == tracked_archive, 'tracked coverage differs from current index')
RESULT['root_drift'] = []
for row in baseline['files']:
    p = ROOT / relative(row['path'])
    if not p.is_file() or filehash(p) != row['sha256']:
        RESULT['root_drift'].append(row['path'])
RESULT['rollback_drift'] = []
for row in baseline['rollback']:
    p = Path(row['source_path'])
    if not p.is_file() or filehash(p) != row['sha256']: RESULT['rollback_drift'].append(row['path'])
    if 'original_manifest_sha256' in row:
        check(row['sha256'] == row['original_manifest_sha256'], 'original rollback manifest differs: ' + row['path'])
check(not RESULT['rollback_drift'], 'protected external rollback changed')
for row in baseline['stable_retakes']:
    check(filehash(Path(row['backup_path'])) == row['sha256'], 'stable retake mismatch: ' + row['path'])

RESULT['dirty_patch_match'] = digest(command(['git', 'diff', '--binary', 'HEAD'], binary=True).stdout) == filehash(RUN/'backup/dirty.patch')
check(RESULT['dirty_patch_match'], 'current tracked dirty diff differs from backed-up dirty.patch')
for ref, expected in [('HEAD', baseline['head']), ('origin/main', manifest['upstream_inputs']['origin_main'])]:
    check(command(['git', 'rev-parse', ref]).stdout.decode().strip() == expected, 'root Git identity changed: ' + ref)
check(command(['git','branch','--show-current']).stdout.decode().strip() == baseline['branch'], 'root branch changed')
check(command(['git','remote','-v']).stdout.decode().strip() == baseline['remotes'], 'root remotes changed')
command(['git','--version'])
command(['python','--version'])

bundle = RUN/'backup/all-refs.bundle'
check(filehash(bundle) == baseline['bundle']['sha256'], 'bundle hash mismatch')
p = command(['git','bundle','verify',str(bundle)])
RESULT['bundle_complete_history'] = b'The bundle records a complete history.' in p.stdout
check(RESULT['bundle_complete_history'], 'bundle complete-history marker missing')
heads = command(['git','bundle','list-heads',str(bundle)]).stdout.decode('utf-8')
check(baseline['head'] + ' refs/heads/' + baseline['branch'] in heads, 'baseline branch missing from bundle')
restored_git = OUT/'restored-git'
command(['git','-c','core.longpaths=true','clone','--no-checkout',str(bundle),str(restored_git)])
check(command(['git','rev-parse','HEAD'],cwd=restored_git).stdout.decode().strip() == baseline['head'], 'bundle clone HEAD mismatch')
command(['git','fsck','--full','--no-reflogs'],cwd=restored_git)

RESULT['upstreams'] = []
provenance = load(RUN/'references/provenance.json')
for upstream in provenance['upstreams']:
    repo, commit = Path(upstream['source_git']), upstream['commit']
    check(command(['git','rev-parse',commit+'^{commit}'],cwd=repo).stdout.decode().strip() == commit, 'upstream commit pin invalid')
    tar_path = Path(upstream['archive'])
    check(filehash(tar_path) == upstream['archive_sha256'], 'upstream archive hash mismatch')
    archive = command(['git','archive','--format=tar',commit],cwd=repo,binary=True).stdout
    check(digest(archive) == upstream['archive_sha256'], 'upstream archive differs from exact Git commit')
    with tarfile.open(tar_path,'r:') as tar:
        members = [m for m in tar.getmembers() if m.isfile()]
        check({m.name for m in members} == {r['path'] for r in upstream['files']}, 'upstream file coverage differs')
        check(all(not m.issym() and not m.islnk() for m in tar.getmembers()), 'upstream links not allowed')
        for row in upstream['files']:
            relative(row['path'])
            data = tar.extractfile(row['path']).read()
            check(digest(data)==row['sha256'] and len(data)==row['bytes'], 'upstream tar content mismatch: '+row['path'])
            p = RUN/'references'/upstream['name']/row['path']
            check(filehash(p)==row['sha256'], 'pinned tree bytes mismatch: '+row['path'])
    RESULT['upstreams'].append({'name':upstream['name'],'commit':commit,'files':len(upstream['files']),'exact_git_archive':True})

local_prov = load(RUN/'references/local-provenance.json')
RESULT['local_snapshots'] = len(local_prov['files'])
for row in local_prov['files']:
    check(filehash(Path(row['source_path'])) == row['sha256'], 'local production source drift: '+row['source_path'])
    check(filehash(Path(row['snapshot_path'])) == row['sha256'], 'local snapshot mismatch: '+row['snapshot_path'])
bayer = baseline['bayer_worktree']
check(command(['git','rev-parse','HEAD'],cwd=Path(bayer['path'])).stdout.decode().strip()==bayer['head'], 'Bayer HEAD changed')
check(command(['git','status','--porcelain=v1','-uall'],cwd=Path(bayer['path'])).stdout.decode('utf-8')==bayer['status'], 'Bayer dirty list changed')

tools = load(RUN/'evidence/tool-inventory.json')
RESULT['tools'] = []
for row in tools['tools']:
    p = Path(row['path'])
    ok = p.is_file() and p.stat().st_size==row['bytes'] and filehash(p)==row['sha256']
    check(ok, 'installed tool differs from frozen inventory: '+row['path'])
    RESULT['tools'].append({'path':str(p),'sha256':row['sha256'],'verified':ok})
reuse = load(RUN/'evidence/tool-success-reuse.json')
check(filehash(Path(reuse['source_path']))==reuse['source_sha256'], 'reused tool evidence source SHA mismatch')

RESULT['manifest_sha256_end'] = filehash(manifest_path)
check(RESULT['manifest_sha256_end']==EXPECTED_MANIFEST, 'manifest changed during testing')
for row in manifest['files']:
    p=RUN/row['relative_path']
    check(p.is_file() and p.stat().st_size==row['bytes'] and filehash(p)==row['sha256'], 'candidate changed during testing: '+row['relative_path'])
RESULT['finished_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
RESULT['completion_marker'] = 'ENGINEERING_INDEPENDENT_RESTORE_AND_HASH_CHECK_COMPLETE'
(OUT/'verification-result.json').write_text(json.dumps(RESULT,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:RESULT[k] for k in ['manifest_files','restored_files','root_archive_files','root_drift','rollback_drift','dirty_patch_match','local_snapshots','errors','completion_marker']},ensure_ascii=True))
raise SystemExit(1 if RESULT['errors'] else 0)
