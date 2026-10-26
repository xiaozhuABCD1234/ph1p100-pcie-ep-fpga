import csv, hashlib, json, pathlib, re, sys, math
ROOT=pathlib.Path('D:/fpga/ph1p100'); RUN=ROOT/'workflow/runs/20261026-144617_fpga-chain-detail-review'; PKG=RUN/'T10.chain-transform-review'; OUT=RUN/'test-reports/T10.chain-transform-review'; BASE=RUN/'baseline/snapshot'
def js(p):return json.loads(pathlib.Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def save(n,x):(OUT/n).write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')
basemap={f['source_relative'].replace('\\','/'):f for f in js(RUN/'baseline/source-manifest.json')['files']}
# .al contains unescaped ampersands in vendor attribute text; parse only the explicit File Path attributes.
paths=re.findall(r'<File Path="([^"]+)">',(BASE/'0155.al').read_text(encoding='utf-8-sig'))
checks=[]
for dep in ['T02.chain-input-review','T06.chain-storage-review']:
    for s in js(RUN/dep/'source-map.json')['sources'].values():
        path=s['source_path'].replace('\\','/')
        if path.lower().startswith(str(ROOT).replace('\\','/').lower()+'/'):
            basemap[path[len(str(ROOT))+1:]]=s
for p in paths:
    rel=p[3:] if p.startswith('Y:/') else 'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b15-ddr-pace/r0/td/'+p
    checks.append({'path':p,'snapshot_exists':rel in basemap})
assert len(paths)==59 and all(x['snapshot_exists'] for x in checks)
assert not any(any(s in p.lower() for s in ['gray8','img_algo','rgb8_gray','rice','bpr1']) for p in paths)
sources=js(PKG/'source-map.json')['sources']; supplement=js(PKG/'supplemental-sources.json'); known=js(RUN/'baseline/source-manifest.json')['files']+supplement
for sid,s in sources.items():
    assert sha(s['snapshot_path'])==s['sha256']
    assert any(x['snapshot_path']==s['snapshot_path'] and x['sha256']==s['sha256'] for x in known)
old=js(BASE/'0141.json'); binding=js(PKG/'candidate-binding.json')['b15_selected_changed_src_sha256']
assert all(x in old['changed_src_sha256'].values() for x in binding.values())
checkpoints=list(csv.DictReader((PKG/'checkpoints.csv').open(encoding='utf-8-sig',newline=''))); findings=js(PKG/'findings.json')['findings']
assert {x['checkpoint'] for x in checkpoints}=={'C%02d'%i for i in range(1,34)} and len(checkpoints)==33
assert {x['finding_id'] for x in findings}=={'T10-F%02d'%i for i in range(1,12)} and len(findings)==11
allowed={'confirmed_issue','redundancy_candidate','evidence_gap','no_issue_found'}
assert all(x['result'] in allowed and all(str(v).strip() for v in x.values()) for x in checkpoints)
assert all(x['kind'] in allowed and all(x.get(k) for k in ['claim','evidence_refs','reproduction','impact','recommendation','expected_benefit','tradeoff','validation']) for x in findings)
for c in checkpoints:
    assert any(s['snapshot_path']==c['source_path'] and s['sha256']==c['source_sha256'] for s in sources.values())
    for fid in c['evidence'].split('/'):assert 'T10-'+fid in {x['finding_id'] for x in findings}
refs=js(OUT/'references.json'); excerpt=[]
for f in refs:
    l=pathlib.Path(f['snapshot_path']).read_text(encoding='utf-8-sig').splitlines()
    excerpt.append('%s %s:%d-%d SHA=%s'%(f['finding_id'],f['snapshot_path'],f['line_start'],f['line_end'],f['sha256']))
    excerpt.extend('%d: %s'%(i,l[i-1]) for i in range(f['line_start'],f['line_end']+1))
(OUT/'source-review-excerpts.txt').write_text('\n'.join(excerpt),encoding='utf-8')
table=list(csv.DictReader((BASE/'0277.csv').open(encoding='utf-8-sig',newline=''))); throughput=[]
for row in table[:4]:
    capacity=2592000*187500000/float(row['S_ss'])/1000000
    assert abs(capacity-float(row['capacity_MBps']))<1e-8
    throughput.append({'row':row['row'],'capacity_MBps':capacity,'S_ss':row['S_ss'],'L_cold':row['L_cold'],'sink_limited':row['sink_limited'],'qualification':row['G0']})
arith={'gray_max':255*(77+150+29)+128,'gaussian_max':255*16+8,'HE_max_pixels':2048*2048,'HE_max_CDF_times255':2048*2048*255,'HE_nonconstant_LUT_cycles_only':14*256,'tag_wrap_blocks':1<<16,'tag_wrap_frames':(1<<16)/540,'tag_wrap_seconds_30fps':(1<<16)/540/30,'RAW_per_stream_MBps':2592000*30/1e6,'Aplus_ideal_per_stream_MBps':2594706*30/1e6,'Aplus_ideal_dual_MBps':2594706*60/1e6,'cycles_per_frame_at_187_5MHz':187500000/30,'P4_rows':throughput}
assert arith['gray_max']==65408 and arith['gaussian_max']==4088
save('independent-arithmetic.json',arith)
versions={'main_gray':sha(BASE/'0031.v'),'upstream_gray':sha(BASE/'0117.v'),'main_top':sha(BASE/'0029.v'),'upstream_top':sha(BASE/'0116.v')}
assert versions['main_gray']!=versions['upstream_gray'] and versions['main_top']!=versions['upstream_top']
variants={'gray':'main 0031 is 2 enabled stages; upstream 0117 is 3 enabled stages','top':'0029 direct broadcast and 2-cycle markers; 0116 RGB and branch queues and 3-cycle markers','same_algorithm_sources':[],'boundary':'review separates old upstream T09 STA/test qualification from current main copies; no old test PASS reused for modified copy'}
for a,b in [('0026.v','0113.v'),('0027.v','0114.v'),('0028.v','0115.v')]:
    assert sha(BASE/a)==sha(BASE/b); variants['same_algorithm_sources'].append([a,b,sha(BASE/a)])
save('independent-sources.json',{'compile_paths':checks,'mapped_source_ids':list(sources),'selected_codec_source_binding':binding,'candidate_manifest_sha256':sha(BASE/'0141.json'),'source_versions':versions,'variant_qualification':variants})
# Reuse already-produced, independent semantic evidence instead of rerunning its stopped harness.
geometry=js(OUT/'independent-geometry.json'); timing=js(OUT/'independent-cancel-timing.json'); capacity=js(OUT/'independent-capacity.json'); streams=js(OUT/'independent-streams.json')
assert len(geometry)==96 and sum(x['consumer']!='equal' for x in geometry)==48
assert sum(not t['matches'] for t in timing['all_final_word_cases'])==3 and capacity['ideal_bound']==2594706
assert streams[0]['consumer_all_checks'] and all(x['consumer_all_checks'] for x in streams[1:3]) and not streams[3]['consumer_all_checks']
result={'checkpoints':len(checkpoints),'findings':len(findings),'finding_refs':len(refs),'checkpoint_refs':len(checkpoints),'compile_paths':len(paths),'mapped_sources':len(sources),'geometry_cases':len(geometry),'geometry_consumer_failures':48,'semantic_harness_failure_qualification':'first expected-geometry classification corrected once; second run completed semantic artifacts but stopped at XML parser. The original command was not run a third time. This targeted qualification checks explicit vendor File attributes and remaining schema/arithmetic. No DUT assertion failure is suppressed.','no_RTL_simulation':True,'no_hardware':True,'marker':'T10_INDEPENDENT_QUALIFICATION_COMPLETE'}
save('qualification-result.json',result)
print(json.dumps(result,ensure_ascii=True));print(result['marker'])
