import json,csv,hashlib,re,sys,subprocess
from pathlib import Path
from collections import Counter
RUN=Path(r'D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review'); P=RUN/'T11.chain-egress-review'; O=RUN/'test-reports'/'T11.chain-egress-review'
# Some frozen vendor HDL comments use a legacy code page. Hash bytes exactly;
# replacement decoding is used solely for line counts and readable source text.
def text(p): return Path(p).read_text(encoding='utf-8-sig',errors='replace')
def load(p): return json.loads(text(p))
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rows(p): return list(csv.DictReader(text(p).splitlines()))
errors=[]; references=[]; originals={}; deps=[]
def check(ok,msg):
    if not ok: errors.append(msg)
def walk(o,loc):
    if isinstance(o,dict):
        if 'snapshot_path' in o:
            p=Path(o['snapshot_path']); ok=p.is_file() and sha(p)==o.get('sha256'); item={'location':loc,'path':str(p),'hash_ok':ok}; check(ok,'ref hash '+loc)
            if 'line_start' in o:
                a,b=int(o['line_start']),int(o['line_end']); valid=1<=a<=b<=len(text(p).splitlines()); item['lines']=[a,b]; item['range_ok']=valid; check(valid,'ref lines '+loc)
            references.append(item)
        for k,v in o.items(): walk(v,loc+'/'+str(k))
    elif isinstance(o,list):
        for i,v in enumerate(o): walk(v,loc+'/'+str(i))
for dep in ('T02.chain-input-review','T06.chain-storage-review','T10.chain-transform-review','T11.chain-egress-review'):
    d=RUN/dep; f=load(d/'findings.json'); f=f if isinstance(f,list) else f['findings']; originals.update({x['finding_id']:x for x in f}); walk(f,dep+'/findings')
    s=load(d/'source-map.json'); walk(s,dep+'/source-map'); cp=rows(d/'checkpoints.csv'); check(len(cp)==len({x['checkpoint'] for x in cp}),dep+' duplicate checkpoints')
    for r in cp:
        check(all(v.strip() for v in r.values()),dep+' empty '+r['checkpoint']); p=Path(r['source_path']); check(p.is_file() and sha(p)==r['source_sha256'],dep+' cp source '+r['checkpoint']); check(1<=int(r['line_start'])<=int(r['line_end'])<=len(text(p).splitlines()),dep+' cp range '+r['checkpoint'])
    if dep!='T11.chain-egress-review':
        review=text(d/'review.md'); report=text(RUN/'test-reports'/(dep+'-r0-integrated.md')); deps.append({'task':dep,'review_sha256':sha(d/'review.md'),'report_sha256':sha(RUN/'test-reports'/(dep+'-r0-integrated.md')),'findings':len(f),'checkpoints':len(cp),'reuse_scope':'same frozen audit inputs and original scope only; no prior DUT/board conclusion promoted'})
fields='finding_id severity kind claim evidence_refs reproduction impact recommendation expected_benefit tradeoff validation disposition'.split()
for fid,f in originals.items():
    check(all(k in f and f[k] not in ('',None,[]) for k in fields),'missing finding field '+fid)
    check(f['kind'] in ('confirmed_issue','redundancy_candidate','evidence_gap','no_issue_found'),'kind '+fid)
c=load(P/'chain-findings.json'); grouped=[]; embedded=[]
for g in c['groups']:
    grouped+=g['original_finding_ids']; embedded+=g['original_findings']; walk(g,'chain/'+g['group_id'])
for f in embedded: check(f==originals.get(f['finding_id']),'changed inherited finding '+f['finding_id'])
check(Counter(grouped)==Counter(originals),'thematic coverage differs from originals'); check(len(embedded)==len(originals),'embedded records count')
root_ids=[r['root_id'] for r in c['root_index']]; check(len(set(root_ids))==len(root_ids),'duplicate roots'); root_members=[f for r in c['root_index'] for f in r['original_finding_ids']]
composite=[x['original_finding_id'] for x in c['inherited_composite_summaries']]
check(Counter(root_members+composite)==Counter(originals),'root/composite conservation')
for x in c['inherited_composite_summaries']: check(all(r in root_ids for r in x['references']),'unknown composite root')
coverage=rows(P/'coverage.csv'); mmd=text(P/'chain-map.mmd')
for e in coverage:
    check(all(v.strip() for v in e.values()),'empty edge '+e['edge_id']); check(e['edge_id'] in mmd,'edge absent graph '+e['edge_id']); walk(load_json:=json.loads(e['source_binding']),'edge/'+e['edge_id'])
check(len(coverage)==15 and len({r['edge_id'] for r in coverage})==15,'edge count')
opt=rows(P/'optimization.csv')
for r in opt:
    check(all(v.strip() for v in r.values()),'empty optimization '+r['group_id']); check(r['group_id'] in [g['group_id'] for g in c['groups']],'unknown opt group')
    check(all(x in root_ids for x in r['root_ids'].split(';')),'unknown opt root '+r['group_id'])
s=load(P/'source-map.json'); alias_count=0
for dep in ('T02.chain-input-review','T06.chain-storage-review','T10.chain-transform-review'):
    ds=load(RUN/dep/'source-map.json')['sources']; ds=ds if isinstance(ds,dict) else {x['source_id']:x for x in ds}
    for key,v in ds.items():
        a=s['inherited_source_aliases'].get(dep+':'+key); alias_count+=1; check(a is not None and a['sha256']==v['sha256'] and a['snapshot_path']==v['snapshot_path'],'missing inherited alias '+dep+':'+key)
required=['review.md','checkpoints.csv','findings.json','source-map.json','chain-review.md','chain-map.mmd','coverage.csv','chain-findings.json','optimization.csv','budget.csv','commands.json','local-check-r0.json','witness/result-r0.json','lessons.md','dependency-bindings.json','activity-ended-r0.json']
check(all((P/x).is_file() and (P/x).stat().st_size for x in required),'required output missing')
git={}
for name,args in [('head',['rev-parse','HEAD']),('branch',['branch','--show-current']),('tracked_status',['status','--porcelain','--untracked-files=no'])]:
    p=subprocess.run(['git','-C',r'D:\fpga\ph1p100']+args,capture_output=True,text=True,timeout=60); check(p.returncode==0,'git '+name); git[name]=p.stdout.strip() if name!='tracked_status' else {'entries':len(p.stdout.splitlines()),'sha256':hashlib.sha256(p.stdout.encode()).hexdigest()}
result={'status':'pass' if not errors else 'fail','errors':errors,'reference_objects':len(references),'references':references,'all_original_findings':len(originals),'T11_findings':len(load(P/'findings.json')['findings']),'thematic_groups':len(c['groups']),'roots':len(root_ids),'composites':len(composite),'edges':len(coverage),'optimization_rows':len(opt),'optimization_priorities':[x['priority'] for x in opt],'inherited_aliases_checked':alias_count,'dependencies':deps,'git':git}
(O/'structure-and-reuse.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='references'},ensure_ascii=False,indent=2)); sys.exit(bool(errors))
