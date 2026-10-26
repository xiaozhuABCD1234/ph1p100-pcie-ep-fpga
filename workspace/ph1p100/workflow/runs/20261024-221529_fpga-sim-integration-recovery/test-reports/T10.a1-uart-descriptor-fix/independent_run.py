"""Tester-owned bounded commands and frozen-input audit. Never writes DUT inputs."""
import difflib, hashlib, json, os, pathlib, subprocess, sys, time
sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
RUN = HERE.parent.parent
DEV = RUN / 'T10.a1-uart-descriptor-fix'
MS = pathlib.Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')

def dump(p, obj):
    p.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding='utf-8')

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def audit(stage):
    m = json.loads((DEV/'manifest-r0.json').read_text(encoding='utf-8-sig'))
    plan = json.loads((RUN/'planning-input-manifest.json').read_text(encoding='utf-8-sig'))
    ix = json.loads((DEV/'corrected-dut-index.json').read_text(encoding='utf-8-sig'))
    rows=[]; drift=[]
    for group, records, key in [('manifest',m['files'],'path'), ('protected',plan['files'],'frozen'), ('dut',ix['files'],'path')]:
        for entry in records:
            actual=sha(entry[key]); row=dict(group=group,path=entry[key],expected=entry['sha256'],actual=actual)
            rows.append(row)
            if actual.lower()!=entry['sha256'].lower(): drift.append(row)
    extra=[DEV/'manifest-r0.json', DEV/'relay-metadata.json',DEV/'freeze-verification.json',RUN/'planning-input-manifest.json',RUN/'dispatch-dq-fix-r0.json',RUN/'planner-amendment-authorized-dq-fix.md',RUN/'dev-plan.md',RUN/'fpga-design-guide.md']
    extras={str(p):sha(p) for p in extra}
    frozen=json.loads((DEV/'freeze-verification.json').read_text(encoding='utf-8-sig'))
    assert extras[str(DEV/'manifest-r0.json')]==frozen['manifest_sha256']
    changed=[e for e in ix['files'] if e['changed']]
    assert len(changed)==1 and changed[0]['logical_name']=='a1_uart_export.v'
    assert all(e['path']==e['source_path'] and e['sha256']==e['original_sha256'] for e in ix['files'] if not e['changed'])
    source=pathlib.Path(changed[0]['source_path']).read_text(); actual=pathlib.Path(changed[0]['path']).read_text(); expected=source
    edits=[
      ('    reg [1:0]   dq_wr, dq_rd, dq_cnt;', '    reg         dq_wr, dq_rd;\n    reg [1:0]   dq_cnt;'),
      ('    reg [1:0]   estate;', "    reg [1:0]   estate;\n    wire        dq_push_accept = desc_push && (dq_cnt < 2'd2);\n    wire        dq_pop_accept = (estate == E_IDLE) && (dq_cnt != 2'd0);"),
      ("            dq_wr <= 2'd0; dq_rd <= 2'd0; dq_cnt <= 2'd0;", "            dq_wr <= 1'b0; dq_rd <= 1'b0; dq_cnt <= 2'd0;"),
      ('            // ---------------------------------------------------- descriptor in', "            // One occupancy update uses the pre-edge accepted events.\n            case ({dq_push_accept, dq_pop_accept})\n                2'b10: dq_cnt <= dq_cnt + 2'd1;\n                2'b01: dq_cnt <= dq_cnt - 2'd1;\n                default: dq_cnt <= dq_cnt;\n            endcase\n\n            // ---------------------------------------------------- descriptor in"),
      ("                if (dq_cnt == 2'd2) begin", '                if (!dq_push_accept) begin'),
      ("                    dq_wr  <= dq_wr + 2'd1;\n                    dq_cnt <= dq_cnt + 2'd1;", '                    dq_wr  <= ~dq_wr;'),
      ("                    if (dq_cnt != 2'd0) begin", '                    if (dq_pop_accept) begin'),
      ("                        dq_rd <= dq_rd + 2'd1;\n                        dq_cnt <= dq_cnt - 2'd1;", '                        dq_rd <= ~dq_rd;')]
    for old,new in edits:
        assert expected.count(old)==1, ('unexpected original',old)
        expected=expected.replace(old,new)
    assert actual==expected, 'non-queue edit in candidate'
    diff=''.join(difflib.unified_diff(source.splitlines(True),actual.splitlines(True),fromfile=changed[0]['source_path'],tofile=changed[0]['path']))
    (HERE/'independent-candidate.diff').write_text(diff)
    result=dict(stage=stage,manifest_sha256=extras[str(DEV/'manifest-r0.json')],counts={g:sum(x['group']==g for x in rows) for g in ['manifest','protected','dut']},drift=drift,extras=extras,rows=rows,narrow_diff=True,changed=1,unchanged=7)
    if stage=='after':
        before=json.loads((HERE/'audit-before.json').read_text(encoding='utf-8'))
        result['drift_from_before']=[x for x in rows if x['actual']!=next(y['actual'] for y in before['rows'] if (x['group'],x['path'])==(y['group'],y['path']))]
        result['extra_drift']=[p for p,h in extras.items() if before['extras'][p]!=h]
        assert not result['drift_from_before'] and not result['extra_drift']
    dump(HERE/('audit-'+stage+'.json'),result)
    assert not drift, drift
    print('AUDIT_PASS',stage,result['counts'],'narrow_diff=True',flush=True)

def execute(argv, folder, name):
    folder.mkdir(parents=True,exist_ok=True)
    assert not (folder/(name+'.command.json')).exists(), 'no blind retries/overwrites'
    argv=[p.as_posix() if isinstance(p,pathlib.Path) else str(p) for p in argv]
    rec=dict(argv=argv,cwd=str(folder),timeout_seconds=300,log=str(folder/(name+'.log')),timed_out=False)
    env=os.environ.copy(); env['PYTHONDONTWRITEBYTECODE']='1'
    ini=folder/'modelsim.ini'
    if not ini.exists(): ini=folder.parent/'modelsim.ini'
    env['MODELSIM']=ini.as_posix()
    start=time.monotonic()
    with (folder/(name+'.log')).open('w',encoding='utf-8') as f:
        p=subprocess.Popen(argv,cwd=folder,env=env,stdout=f,stderr=subprocess.STDOUT)
        rec['owned_pid']=p.pid
        try: rec['returncode']=p.wait(timeout=300)
        except subprocess.TimeoutExpired:
            rec['timed_out']=True
            subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],stdout=f,stderr=subprocess.STDOUT,timeout=15)
            rec['returncode']=p.wait(timeout=15)
    rec['elapsed_seconds']=round(time.monotonic()-start,3)
    dump(folder/(name+'.command.json'),rec)
    print(name,rec['returncode'],rec['elapsed_seconds'],flush=True)
    return rec

def compile_all(kind):
    ix=json.loads((DEV/'corrected-dut-index.json').read_text())
    folder=HERE/kind;folder.mkdir(exist_ok=True)
    (folder/'modelsim.ini').write_text('[Library]\nwork = '+(folder/'lib').as_posix()+'\n[vsim]\nResolution = ps\n')
    (folder/'run.do').write_text('onerror {quit -code 2 -f}\nrun -all\nquit -f\n')
    a=execute([MS/'vlib.exe',folder/'lib'],folder,'vlib');assert a['returncode']==0
    sources=[pathlib.Path(e['source_path'] if kind=='old' else e['path']) for e in ix['files']]
    b=execute([MS/'vlog.exe','-sv','-modelsimini',folder/'modelsim.ini','-work','work']+sources+[DEV/'ddr_recovery_model.sv',DEV/'tb_full_clean.sv',DEV/'tb_descriptor.sv',HERE/'independent_observers.sv'],folder,'vlog')
    text=(folder/'vlog.log').read_text()
    assert b['returncode']==0 and 'Errors: 0, Warnings: 0' in text
    dump(folder/'compile-result.json',dict(status='PASS',sources=[str(p) for p in sources],commands=[a,b]))
    print('COMPILE_PASS',kind,flush=True)

def sim(kind, case):
    root=HERE/kind; out=root/case
    out.mkdir(exist_ok=True)
    argv=[MS/'vsim.exe','-c','-modelsimini',root/'modelsim.ini','-wlf',out/'case.wlf','-l',out/'transcript.log']
    if case=='full-clean':
        argv+=['work.tester_full','+CASE=0','+OUT='+(out/'capture.dec').as_posix()]
    else:
        argv+=['work.tester_descriptor','+MODE='+str(2 if case=='wrap' else 3),'+DESCS='+(DEV/'descriptors.hex').as_posix(),'+PAYLOADS='+(DEV/'payloads.hex').as_posix(),'+OUT='+(out/'capture.tsv').as_posix()]
    argv+=['+WIRE='+(out/'wire.tsv').as_posix(),'+TRACE='+(out/'trace.txt').as_posix(),'+STAT='+(out/'stats.txt').as_posix(),'-do','do '+(root/'run.do').as_posix()]
    rec=execute(argv,out,'console')
    assert rec['returncode']==0 and not rec['timed_out']
    log=(out/'console.log').read_text()
    if kind=='old':
        target='DESCRIPTOR_ORDER_OR_X pop=3 expected_id=1003 actual_id=xxxxxxxx' if case=='wrap' else 'QUEUE_COUNT_MISMATCH old=1 push=1 pop=1 expected=1 actual=0'
        assert target in log and 'Fatal' in log, 'old DUT did not hit target'
        result=dict(status='EXPECTED_REJECTION',target=target,compiled=True,real_dut_executed=True)
    else:
        token='CASE_PASS case=0 recovered=4' if case=='full-clean' else 'DESCRIPTOR_PASS mode='+str(2 if case=='wrap' else 3)+' mismatch=0'
        assert token in log and 'Fatal' not in log and 'Errors: 0' in log
        result=dict(status='SIM_PASS_PENDING_BYTES',marker=token)
    dump(out/'sim-result.json',result)
    print(kind,case,result['status'],flush=True)

if __name__=='__main__':
    if sys.argv[1]=='audit': audit(sys.argv[2])
    elif sys.argv[1]=='compile': compile_all(sys.argv[2])
    else: sim(sys.argv[1],sys.argv[2])
