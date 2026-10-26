from pathlib import Path
import csv,json,hashlib,sys
OUT=Path(__file__).resolve().parent
def j(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def csvread(p):return list(csv.DictReader(Path(p).open(encoding='utf-8-sig',newline='')))
checks=csvread(OUT/'checkpoints.csv'); cov=csvread(OUT/'coverage.csv'); f=j(OUT/'findings.json')['findings']; chain=j(OUT/'chain-findings.json')
assert len(checks)==28 and len(cov)==15 and len(f)==9
assert all(all(str(v).strip() for v in row.values()) for row in checks+cov)
assert set(x['result'] for x in checks)<={'confirmed_issue','evidence_gap','redundancy_candidate','no_issue_found'}
count=0
for e in [dict(snapshot_path=r['source_path'],sha256=r['source_sha256'],line_start=int(r['line_start']),line_end=int(r['line_end'])) for r in checks]+[e for x in f for e in x['evidence_refs']]+[json.loads(r['source_binding']) for r in cov]:
    p=Path(e['snapshot_path']); assert sha(p)==e['sha256'],p
    n=len(p.read_text(encoding='utf-8-sig').splitlines()); assert 1<=e['line_start']<=e['line_end']<=n,(p,n,e)
    count+=1
allids=[i for g in chain['groups'] for i in g['original_finding_ids']]
assert len(allids)==len(set(allids))==45
assert len(chain['groups'])==14
rootids=[i for g in chain['root_index'] for i in g['original_finding_ids']]
assert len(chain['root_index'])==39 and len(rootids)==len(set(rootids))==44
assert set(rootids)|{x['original_finding_id'] for x in chain['inherited_composite_summaries']}==set(allids)
for d in j(OUT/'dependency-bindings.json'):
    assert sha(d['manifest_path'])==d['manifest_sha256']
    assert sha(d['report_path'])==d['report_sha256']
    for e in j(d['manifest_path'])['files']: assert sha(e['path'])==e['sha256'],e['path']
w=j(OUT/'witness/result-r0.json');assert w['status']=='local_witness_pass'
assert w['budget']['r10f_TLP_total_B']==2916884 and w['budget']['ddr_dual_MBps']==809.0304
required=['review.md','checkpoints.csv','findings.json','source-map.json','commands.json','lessons.md','chain-review.md','chain-map.mmd','coverage.csv','chain-findings.json','optimization.csv','budget.csv']
assert all((OUT/p).is_file() and (OUT/p).stat().st_size for p in required)
result=dict(status='local_structure_pass',not_independent_integrated_acceptance=True,checkpoints=28,edges=15,new_findings=9,original_findings=45,dedup_groups=14,new_source_references_checked=count,required_files=required,dependency_hashes='matched',witness='passed',no_hardware_claim=True)
(OUT/'local-check-r0.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result,ensure_ascii=False))
