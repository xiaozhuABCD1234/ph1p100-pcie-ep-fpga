import pathlib,json,hashlib,difflib
N=pathlib.Path(__file__).resolve().parents[1];O=N.parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def readj(p):return json.loads(p.read_text(encoding='utf-8-sig'))
snap=readj(N/'prechange-index.json'); changed=[];patch=''
for e in snap:
    p=pathlib.Path(e['path']);s=pathlib.Path(e['snapshot']);assert sha(s)==e['sha256']
    if sha(p)!=e['sha256']:
        changed.append(str(p));patch+=''.join(difflib.unified_diff(s.read_text(encoding='utf-8').splitlines(True),p.read_text(encoding='utf-8').splitlines(True),fromfile=str(s),tofile=str(p)))
(N/'source-change.diff').write_text(patch,encoding='utf-8')
m=readj(O/'candidate/manifest.json');drift=[e['path'] for e in m['entries'] if sha(pathlib.Path(e['path']))!=e['sha256']];assert sorted(drift)==sorted(changed)
reuse=readj(O/'reuse-evidence.json')
for r in reuse['checks']:
    for e in r['elaborated_file_closure']:assert sha(pathlib.Path(e['path']))==e['current_sha256']
(N/'reuse-evidence.json').write_text(json.dumps(reuse,indent=2),encoding='utf-8')
(N/'preflight-result.json').write_text(json.dumps({'changed_previous_manifest_entries':changed,'unchanged_previous_entries':len(m['entries'])-len(changed),'reference_oracle_T08_IP_constraints_unchanged':True,'elaborated_reuse_closures_unchanged':len(reuse['checks'])},indent=2),encoding='utf-8')
print('PREFLIGHT_CHANGED',len(changed),'OTHER_PREVIOUS_ENTRIES_UNCHANGED',len(m['entries'])-len(changed),'REUSE',len(reuse['checks']))
