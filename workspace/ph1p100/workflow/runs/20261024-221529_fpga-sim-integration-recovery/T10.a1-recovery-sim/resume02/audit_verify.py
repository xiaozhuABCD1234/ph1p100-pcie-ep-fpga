"""Current-run evidence audit and bounded checker mutations; no DUT writes."""
import hashlib,json,pathlib,re,struct,sys,zlib,datetime
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import run_abort,check_recovery

def kv(line):return {k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
def sha(p):return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def verify():
    matrix=json.loads((HERE/'matrix-results-resume02.json').read_text())['final_TB_results']
    assert len(matrix)==20
    expected={(n,r+'-final') for n in run_abort.CASES for r in ('slow','fast')}
    assert {(x['name'],x['ratio']) for x in matrix}==expected
    rows=[];total=0;recovery=0;old_ar_hits=0
    for x in matrix:
        d=HERE/'corrected'/(x['name']+'-'+x['ratio'])
        fresh=check_recovery.check(d,x['case_id'])
        assert fresh['status']=='PASS',fresh
        s=fresh['stats'];trace=(d/'trace.txt').read_text();lines=trace.splitlines()
        assert s['good_sent']==4 and s['recovered']==4 and s['recovery_elapsed']<=1000000
        assert len([f for f in fresh['decoded'] if f['seed'] in fresh['allowed_good_seeds']])==4
        control=kv(next(l for l in lines if l.startswith('CONTROL ')))
        assert control['token_w']==control['token_r'],'outstanding FIFO tokens'
        assert control['abort_writes']==control['abort_reads'],'abort count mismatch'
        final=kv(next(l for l in lines if 'tag=final ' in l))
        assert final['raw_active']==final['cmp_active']==0
        assert final['slots0']==final['slots1']==0,'RAW slots leaked after drain'
        fault=[kv(l) for l in lines if 'tag=fault_observed ' in l]
        for f in fault:
            assert f['slots0']!=1 and f['slots1']!=1,'WRITING slot not released at fault observation'
        if x['case_id']==3:
            assert control['abort_writes']==control['abort_reads']==control['raw_aborts']==1
            assert s['fault_rawdrop']>=1
        if x['case_id']==8:
            assert control['last_abort_hits']==1 and s['fault_rawdrop']==1
        if x['case_id']==7:assert control['sof_abort_hits']==1
        if x['case_id'] in (1,2):
            hit=kv(next(l for l in lines if 'tag=reset_hit ' in l))
            old_ar_hits+=int(bool(hit['pending'] or hit['rvalid']))
        total+=len(fresh['decoded']);recovery+=4
        rows.append(dict(name=x['name'],ratio=x['ratio'],status='PASS',packets=len(fresh['decoded']),
                         recovery_packets=4,good_sent=4,recovery_elapsed=s['recovery_elapsed'],
                         legal_prefix=fresh['legal_prefix'],stats=s,control=control,fault_slot_observations=fault))
    old=json.loads((HERE/'old/bad-frame-slow/result.json').read_text())
    old_log=(HERE/'old/bad-frame-slow/console.log').read_text(errors='replace')
    assert old['effective_negative'] and old['status']=='EXPECTED_REJECTION'
    assert 'ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED' in old_log and 'Error loading design' not in old_log
    assert 'RECOVERY_BOUND_FAIL' not in old_log
    copied=json.loads((HERE/'copy-source-map.json').read_text())
    for x in copied:
        assert sha(x['source'])==x['source_sha256']
        assert sha(x['copy'])==x['adapted_sha256']
    result=dict(status='LOCAL_PASS',cases=rows,total_packets=total,recovery_packets=recovery,
                max_recovery_elapsed=max(x['recovery_elapsed'] for x in rows),
                old_top_effective_negative=True,old_AR_at_reset=dict(hits=old_ar_hits,
                status='covered' if old_ar_hits else 'not_covered',scope='Only raw/encoded midwrite reset hit observations'),
                protected=run_abort.protect(),active_commands=0)
    (HERE/'local-result-resume02.json').write_text(json.dumps(result,indent=2))
    return result

def negatives():
    d=HERE/'corrected/clean-slow-final'
    good=bytes(map(int,(d/'capture.dec').read_text().split()))
    first_len=44+struct.unpack_from('<I',good,24)[0]
    first=good[:first_len];allowed=list(range(1000,1004));out=[]
    def check(name,data,allow=allowed):
        try:
            check_recovery.packets(data,8,2,allow)
            item=dict(name=name,rejected=False,reason='unexpected acceptance')
        except (AssertionError,ValueError,zlib.error,IndexError) as e:
            item=dict(name=name,rejected=True,reason=str(e))
        out.append(item);assert item['rejected'],name
    check('tail-byte',good+b'\xff')
    check('duplicate-packet',good+first)
    check('truncated-payload',good[:-1])
    check('CRC-valid-old-epoch-source',good,list(range(1100,1104)))
    for name,index in [('header-CRC',40),('stream-CRC',36),('transform-CRC',32),('raw-CRC',28)]:
        b=bytearray(first);b[index]^=1
        if index!=40:struct.pack_into('<I',b,40,zlib.crc32(b[:40])&0xffffffff)
        check(name,bytes(b))
    b=bytearray(first[:44]);pay=first[44:]+zlib.compress(b'unused-second-stream')
    struct.pack_into('<I',b,24,len(pay));struct.pack_into('<I',b,36,zlib.crc32(pay)&0xffffffff)
    struct.pack_into('<I',b,40,zlib.crc32(b[:40])&0xffffffff)
    check('CRC-valid-concatenated-zlib',bytes(b)+pay)
    for name,(case_id,w) in run_abort.CASES.items():
        if case_id==0:continue
        result=check_recovery.check(HERE/'corrected'/(name+'-slow-final'),case_id,inject_override=0)
        item=dict(name='deleted-trigger-'+name,rejected='fault trigger absent' in result['errors'],errors=result['errors'])
        out.append(item);assert item['rejected'],item
    assert len(out)==17
    (HERE/'checker-negatives-resume02.json').write_text(json.dumps(out,indent=2))
    return out

if __name__=='__main__':
    result=verify();neg=negatives()
    print(json.dumps(dict(status=result['status'],cases=len(result['cases']),packets=result['total_packets'],
                         recovery_packets=result['recovery_packets'],max_recovery_elapsed=result['max_recovery_elapsed'],
                         negatives=len(neg),old_AR_at_reset=result['old_AR_at_reset'],protected=result['protected']),indent=2))
