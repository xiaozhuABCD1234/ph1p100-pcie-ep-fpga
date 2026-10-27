from pathlib import Path
import csv, hashlib, json, re, sys, platform, subprocess
from collections import deque
from datetime import datetime, timezone
ROOT = Path('D:/fpga/ph1p100')
RUN = ROOT/'workflow/runs/20261026-144617_fpga-chain-detail-review'
PKG = RUN/'T06.chain-storage-review'
OUT = RUN/'test-reports/T06.chain-storage-review'
MAN = PKG/'manifest-r0.json'
def read(p): return Path(p).read_text(encoding='utf-8-sig')
def jread(p): return json.loads(read(p))
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def save(name, value): (OUT/name).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
def must(value, message):
    if not value: raise AssertionError(message)
def hashes(mode):
    m=jread(MAN); b=jread(RUN/'baseline/source-manifest.json')
    checks=[]
    for e in m['files']:
        p=Path(e['path']); actual=sha(p)
        checks.append({'path':str(p),'expected':e['sha256'],'actual':actual,'size':p.stat().st_size})
        must(actual==e['sha256'], 'manifest drift: '+str(p))
        must(p.stat().st_size==e['size'], 'size mismatch: '+str(p))
    base=[]
    for e in b['files']:
        actual=sha(e['snapshot_path']);must(actual==e['sha256'],'baseline drift')
        base.append({'path':e['snapshot_path'],'sha256':actual})
    controls=[]
    for e in m['controls']:
        a=sha(e['original_path']); f=sha(e['frozen_path'])
        must(a==f==e['sha256'], 'control drift '+e['original_path'])
        controls.append({'original':e['original_path'],'frozen':e['frozen_path'],'sha256':a})
    dep=RUN/'T02.chain-input-review/manifest-r0.json'
    must(sha(dep)=='af32567395a3083b3b5005df40cfc37857f54b133293a644782eca9d6a34b997','dependency manifest drift')
    must(sha(RUN/'test-reports/T02.chain-input-review-r0-integrated.md')=='c96751cda203daf4c53a47909760f7d5b2edd3b88abdedbda0e625d67d2fb920','dependency report drift')
    dm=jread(dep)
    for e in dm['files']: must(sha(e['path'])==e['sha256'],'T02 dependency drift')
    ended=jread(PKG/'activity-ended-r0.json')
    must(ended['stopped_modifying'] and ended['active_build_simulation_worker_processes']==0,'active development')
    must(ended['development_activities_ended_utc']<m['frozen_utc'],'freeze before stop')
    value={'marker':'INDEPENDENT_HASH_'+mode.upper(),'utc':datetime.now(timezone.utc).isoformat(),'manifest_sha256':sha(MAN),'files':checks,'baseline':base,'controls':controls,'T02_file_count':len(dm['files']),'python':platform.python_version()}
    if mode=='post':
        pre=jread(OUT/'hash-pre.json')
        must(pre['manifest_sha256']==value['manifest_sha256'],'manifest changed')
        must(pre['files']==checks and pre['baseline']==base and pre['controls']==controls,'input drift')
    save('hash-'+mode+'.json',value)
    print(value['marker'], 'files',len(checks),'baseline',len(base),'controls',len(controls),'T02',len(dm['files']),'manifest',value['manifest_sha256'])
def refs():
    sm=jread(PKG/'source-map.json'); sources={x['source_id']:x for x in sm['sources']}
    fs=jread(PKG/'findings.json')['findings']
    cps=list(csv.DictReader(read(PKG/'checkpoints.csv').splitlines()))
    cp_fields='checkpoint stage parent_task producer consumer source_path source_sha256 line_start line_end input_output_units clock_reset acceptance_event ownership invariant failure_recovery result evidence optimization verification_next'.split()
    f_fields='finding_id severity kind claim evidence_refs reproduction impact recommendation expected_benefit tradeoff validation disposition'.split()
    kinds={'confirmed_issue','redundancy_candidate','evidence_gap','no_issue_found'}
    must({x['checkpoint'] for x in cps}=={'C%02d'%i for i in range(1,36)},'coverage labels')
    must(len(cps)==35 and len({x['finding_id'] for x in fs})==len(fs)==15,'count/duplicate')
    refs=[]
    for s in sources.values():
        must(sha(s['snapshot_path'])==s['sha256'],'source map sha')
        must(len(read(s['snapshot_path']).splitlines())==s['line_count'],'source map lines')
    bypath={str(Path(s['snapshot_path'])).lower():s for s in sources.values()}
    def checkref(e,owner):
        p=Path(e.get('snapshot_path',e.get('source_path')))
        s=bypath[str(p).lower()]
        h=e.get('sha256',e.get('source_sha256'))
        lo=int(e['line_start']);hi=int(e['line_end'])
        must(h==s['sha256'] and 1<=lo<=hi<=s['line_count'],'reference invalid '+owner)
        if 'source_id' in e: must(e['source_id']==s['source_id'],'source id mismatch')
        refs.append({'owner':owner,'source_id':s['source_id'],'path':str(p),'sha256':h,'line_start':lo,'line_end':hi})
    for c in cps:
        must(all(c.get(k,'').strip() for k in cp_fields),'blank checkpoint '+c['checkpoint'])
        must(c['result'] in kinds,'unreviewed result');checkref(c,c['checkpoint'])
        ids=re.findall(r'T06-F\d+',c['evidence'])
        must(ids and all(i in {f['finding_id'] for f in fs} for i in ids),'missing finding crossref')
    for f in fs:
        must(all(f.get(k) for k in f_fields),'blank finding '+f['finding_id'])
        must(f['kind'] in kinds,'invalid finding kind')
        for e in f['evidence_refs']:checkref(e,f['finding_id'])
    al=read(RUN/'baseline/snapshot/0155.al')
    paths=re.findall(r'<File\s+Path="([^"]+)"',al)
    must(paths==sm['compile_paths'],'compile paths differ')
    must('p2_a1_board_top' in al and sm['compiled_top']=='p2_a1_board_top','top')
    changed=[]
    baseline_sources=jread(RUN/'baseline/source-manifest.json')['files']
    for name,h in sm['candidate_changed_src_sha256'].items():
        # source-map intentionally lists the task-relevant subset; bind other
        # candidate sources to the complete, immutable common baseline.
        c=[s for s in baseline_sources if s['source_path'].replace('\\','/').endswith('/changed-src/'+name)]
        must(len(c)==1 and c[0]['sha256']==h,'changed source binding '+name)
        changed.append(name)
    save('references.json',{'marker':'INDEPENDENT_REFERENCE_COMPLETE','checkpoints':cps,'findings_summary':[{k:f[k] for k in ['finding_id','severity','kind','claim','reproduction']} for f in fs],'sources':len(sources),'references':refs,'compiled_paths':paths,'changed_sources':changed})
    print('INDEPENDENT_REFERENCE_COMPLETE checkpoints',len(cps),'findings',len(fs),'sources',len(sources),'refs',len(refs),'compile_paths',len(paths),'changed_src',len(changed))
def ordering():
    src=read(RUN/'baseline/snapshot/0144.v')
    anchors=['slot_seq[free_slot] <= pub_tgl;','pub_tgl   <= ~pub_tgl;','rd_expect <= ~rd_expect;']
    must(all(a in src for a in anchors),'ordering RTL anchors')
    def search(commit_toggle=False,depth=12,stop_on_error=True):
        # State: (slot state, seq, frame identity) x2, begin counter, pub bit,
        # expected bit, FIFO of successful publications. One writer/reader each.
        initial=((('F',0,-1),('F',0,-1)),0,0,0,())
        q=deque([(initial,[])])
        seen={initial};checked=0;maxdepth=0
        while q:
            (slots,n,pub,exp,fifo),trace=q.popleft();maxdepth=max(maxdepth,len(trace))
            ready=[i for i,s in enumerate(slots) if s[0]=='Q']
            if ready and not any(s[0]=='R' for s in slots):
                preferred=[i for i in ready if slots[i][1]==exp]
                selected=(preferred or ready)[0];checked+=1
                if slots[selected][2]!=fifo[0]:
                    return {'counterexample':trace+[{'event':'open','selected':slots[selected][2],'fifo_expected':fifo[0],'state':slots,'pub':pub,'rd_expect':exp,'fifo':fifo}],'states_explored':len(seen),'open_checks':checked,'depth':len(trace)+1}
            if len(trace)>=depth: continue
            moves=[]
            free=[i for i,s in enumerate(slots) if s[0]=='F']
            if free and not any(s[0]=='W' for s in slots):
                i=free[0];ss=list(slots);ss[i]=('W',pub,n)
                moves.append(((tuple(ss),n+1,pub if commit_toggle else pub^1,exp,fifo),{'event':'begin','slot':i,'id':n}))
            for i,s in enumerate(slots):
                if s[0]=='W':
                    ss=list(slots);ss[i]=('Q',s[1],s[2])
                    moves.append(((tuple(ss),n,pub^1 if commit_toggle else pub,exp,fifo+(s[2],)),{'event':'publish','slot':i,'id':s[2]}))
                    ss=list(slots);ss[i]=('F',s[1],s[2])
                    moves.append(((tuple(ss),n,pub,exp,fifo),{'event':'abort','slot':i,'id':s[2]}))
                if s[0]=='R':
                    ss=list(slots);ss[i]=('F',s[1],s[2])
                    moves.append(((tuple(ss),n,pub,exp,fifo),{'event':'close_after_read_complete','slot':i,'id':s[2]}))
            if ready and not any(s[0]=='R' for s in slots):
                preferred=[i for i in ready if slots[i][1]==exp];i=(preferred or ready)[0]
                ss=list(slots);s=ss[i];ss[i]=('R',s[1],s[2])
                moves.append(((tuple(ss),n,pub,exp^1,fifo[1:]),{'event':'open','slot':i,'id':s[2]}))
            for st,event in moves:
                if st not in seen: seen.add(st);q.append((st,trace+[event]))
        return {'counterexample':None,'states_explored':len(seen),'open_checks':checked,'max_depth':maxdepth}
    actual=search(False);control=search(True)
    must(actual['counterexample'] is not None,'failed to expose order bug')
    must(control['counterexample'] is None,'commit-only negative control failed')
    save('independent-ordering.json',{'marker':'INDEPENDENT_ORDER_COMPLETE','method':'Breadth-first generation of legal two-slot transactions; chronological successful-publication FIFO oracle; no imported developer trace/result. Abstract reads may take arbitrary finite time before close. Not cycle-accurate RTL simulation.','production_semantics':actual,'commit_toggle_mutation':control,'source':str(RUN/'baseline/snapshot/0144.v'),'source_sha256':sha(RUN/'baseline/snapshot/0144.v'),'descriptor_effect':'If CMP consumer has deferred claim, chosen id differs from queued descriptor. Full-size top scheduling reachability remains unproven.'})
    print('INDEPENDENT_ORDER_COMPLETE',json.dumps({'bug_depth':actual['depth'],'states_actual':actual['states_explored'],'states_control':control['states_explored'],'control_open_checks':control['open_checks']}))
def budget():
    raw=1920*1080//4//4
    cmp=81085
    moves=2*raw+2*cmp
    v={'marker':'INDEPENDENT_BUDGET_COMPLETE','raw_words':raw,'packed_words':1920*1080*10//8//32,'raw_slot_bytes':raw*32,'cmp_slot_bytes':cmp*32,'slot_ranges':[(0,raw-1),(raw,2*raw-1),(262144,262144+cmp-1),(262144+cmp,262144+2*cmp-1)],'word_moves_per_frame':moves,'single_Bps':moves*32*30,'dual_Bps':moves*32*60,'payload_Bps':1920*1080*10//8*30,'mean_200MHz_cycles_per_move_dual':200000000/(moves*60),'limits':'CMP capacity budgeting only; no proven compressed expansion bound, no hardware service measurement, no command/refresh/retry/fence overhead.'}
    must(v['single_Bps']==404515200 and v['dual_Bps']==809030400,'arithmetic')
    save('independent-budget.json',v);print(v['marker'],json.dumps(v))
def metadata(mode):
    results=[]
    for args in [['--version'],['rev-parse','HEAD'],['branch','--show-current'],['status','--porcelain','--untracked-files=no']]:
        p=subprocess.run(['git']+args,cwd=ROOT,text=True,encoding='utf-8',capture_output=True,timeout=60)
        results.append({'command':['git']+args,'exit_code':p.returncode,'stdout':p.stdout,'stderr':p.stderr})
        must(p.returncode==0,'git metadata failed')
    save('metadata-'+mode+'.json',{'python':sys.version,'commands':results})
    print('INDEPENDENT_METADATA_'+mode.upper(),'head',results[1]['stdout'].strip(),'branch',results[2]['stdout'].strip(),'tracked_dirty',len(results[3]['stdout'].splitlines()),'git',results[0]['stdout'].strip())
    if mode=='post':
        prior=jread(OUT/'metadata-pre.json')
        must(prior['commands'][1]['stdout']==results[1]['stdout'],'HEAD changed')
        must(prior['commands'][3]['stdout']==results[3]['stdout'],'tracked worktree changed')
def static_contracts():
    store=read(RUN/'baseline/snapshot/0144.v');bridge=read(RUN/'baseline/snapshot/0153.v')
    top=read(RUN/'baseline/snapshot/0150.v'); model=read(RUN/'baseline/snapshot/0154.v')
    blocks={n:store.split(n+': begin',1)[1].split('\n                end',1)[0] for n in ['R_AR','R_HOLD']}
    timeout=re.search(r'assign rd_timeout\s*=.*?;',store,re.S).group()
    argate=re.search(r'assign paxi_arvalid\s*=.*?;',bridge,re.S).group()
    evidence={'R_AR':blocks['R_AR'],'R_HOLD':blocks['R_HOLD'],'timeout':timeout,'ar_gate':argate,
      'native_addr_reference':re.search(r'assign cmd_addr\s*=.*?;',read(RUN/'baseline/snapshot/0166.v'),re.S).group(),
      'mask_reference':"assign wmask_phase[p*DX_NUM+n] = 1'b0;",
      'raw_address':re.search(r'assign paxi_awaddr\s*=.*?;',bridge,re.S).group(),
      'raw_mask':re.search(r'assign paxi_wstrb\s*=.*?;',bridge,re.S).group(),
      'tagless_push':re.search(r'wire\s+rf_push\s*=.*?;',bridge,re.S).group()}
    must('rd_close' not in blocks['R_AR'] and 'if (rd_close)' in blocks['R_HOLD'],'F08 state branch')
    must('(rd_state == R_RW)' in timeout and 'ddr_arready' in blocks['R_AR'],'F08 timeout gap')
    must('wf_' not in argate and 'wstate' not in argate,'unexpected write fence')
    must('mem[awaddr[18:0]] <= wdata;' in model and 'awvalid && awready && wvalid && wready' in model,'model contract')
    must("assign paxi_wstrb   = 32'hFFFF_FFFF;" in bridge,'mask')
    must(evidence['mask_reference'] in read(RUN/'baseline/snapshot/0167.v'),'native mask ref')
    must('slot_st[wr_slot] <= S_READY;' in store and 'wire abort_now = wr_abort && wr_active;' in store,'late verdict')
    must("raw_rd_close_r <= 1'b1;" in top and 'else if (fwait_cycles >= WD_LIMIT)' in top,'watchdog')
    evidence['marker']='INDEPENDENT_STATIC_CONTRACTS_COMPLETE'
    evidence['qualification']='Source predicates/absence scoped to exact parsed gates/states; neither encrypted MC nor dynamic RTL execution.'
    save('static-contracts.json',evidence); print(evidence['marker'])
def qualify():
    candidate=jread(RUN/'baseline/snapshot/0141.json'); sm=jread(PKG/'source-map.json')
    must(candidate['changed_src_sha256']==sm['candidate_changed_src_sha256'],'old candidate source map mismatch')
    must(candidate['build']==sm['candidate_build'],'old candidate build mismatch')
    build_checks=[]
    for name,num in [('a1_board.al','0155.al'),('board_p2.adc','0156.adc'),('p2_board.sdc','0157.sdc'),('src/p2_ddrmc_shell.v','0164.v')]:
        actual=sha(RUN/'baseline/snapshot'/num)
        must(candidate['build'][name]==actual,'candidate build sha mismatch '+name)
        build_checks.append({'name':name,'snapshot':num,'sha256':actual})
    witness=jread(OUT/'developer-witness-stdout.txt')
    must(witness==jread(PKG/'witness/result-r0.json'),'developer witness rerun differs')
    must(witness['marker']=='STORAGE_WITNESS_COMPLETE','witness completion marker')
    depmap=jread(RUN/'T02.chain-input-review/source-map.json')
    for s in depmap['sources'].values(): must(sha(s['snapshot_path'])==s['sha256'],'T02 source map mismatch')
    save('candidate-and-reuse.json',{'marker':'INDEPENDENT_QUALIFICATION_COMPLETE','candidate_manifest':str(RUN/'baseline/snapshot/0141.json'),'changed_src_bindings':11,'build_bindings':build_checks,'T02_source_map_count':len(depmap['sources']),'developer_witness_reproduced_exactly':True,'reuse':'T02 accepted audit remains a dependency, not new execution; no old dynamic test/STA/hardware result used as current PASS; independent ordering oracle and recomputation are newly executed.','old_G_layers':{'G2':'reported diagnostic thin +0.012ns; not full production STA/CDC qualification','G3':'historical one SRAM download/150s observation only','G4':'blocked H4_UNRESOLVED; enc/exported=0','G5':'not_run production throughput/stability'},'new_G2_G5':'not_applicable per frozen pure-read-only review scope'})
    print('INDEPENDENT_QUALIFICATION_COMPLETE candidate_changed_src=11 build_bindings=4 T02_sources='+str(len(depmap['sources']))+' developer_witness_exact=1')
if __name__=='__main__':
    {'pre':lambda:hashes('pre'),'post':lambda:hashes('post'),'refs':refs,'ordering':ordering,'budget':budget,'metapre':lambda:metadata('pre'),'metapost':lambda:metadata('post'),'contracts':static_contracts,'qualify':qualify}[sys.argv[1]]()
