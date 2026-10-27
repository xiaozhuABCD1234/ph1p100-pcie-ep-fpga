"""Tester-owned, standard-library audit. No production writes or child processes."""
import argparse
import csv
import hashlib
import json
import re
import sys
from pathlib import Path
from datetime import datetime, timezone

RUN = Path('D:/fpga/ph1p100/workflow/runs/20261026-144617_fpga-chain-detail-review')
TASK = RUN / 'T02.chain-input-review'
OUT = RUN / 'test-reports/T02.chain-input-review'


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def read(p):
    return Path(p).read_text(encoding='utf-8-sig', errors='replace')


def obj(p):
    return json.loads(read(p))


def compact(p):
    return re.sub(r'\s+', '', re.sub(r'//[^\n]*', '', read(p)))


def save(name, data):
    target = OUT / name
    assert target.resolve().is_relative_to(OUT.resolve())
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def verify_hashes(phase):
    manifest_path = TASK / 'manifest-r0.json'
    m = obj(manifest_path)
    baseline = obj(RUN / 'baseline/source-manifest.json')
    issues = []
    checks = []
    for entry in m['files']:
        p = Path(entry['path'])
        actual = sha(p)
        checks.append({'path': str(p), 'expected': entry['sha256'], 'actual': actual})
        if actual.lower() != entry['sha256'].lower() or p.stat().st_size != entry['size']:
            issues.append(str(p))
    for entry in baseline['files']:
        if sha(entry['snapshot_path']) != entry['sha256']:
            issues.append(entry['snapshot_path'])
    control_checks = []
    for e in m['controls']:
        row = {k: e[k] for k in ['original_path', 'frozen_path', 'sha256']}
        row['original_actual'] = sha(e['original_path'])
        row['frozen_actual'] = sha(e['frozen_path'])
        control_checks.append(row)
        if row['original_actual'] != e['sha256'] or row['frozen_actual'] != e['sha256']:
            issues.append(e['original_path'])
    assert sha(RUN / 'baseline/source-manifest.json') == m['baseline_manifest_sha256']
    result = {'marker': 'INDEPENDENT_HASH_'+phase.upper(), 'utc': datetime.now(timezone.utc).isoformat(),
              'manifest_sha256': sha(manifest_path), 'manifest_files': len(checks),
              'baseline_files': len(baseline['files']), 'control_checks': control_checks,
              'issues': issues, 'checks': checks, 'python': sys.version}
    save('hash-'+phase+'.json', result)
    assert not issues, issues
    print(f'INDEPENDENT_HASH_{phase.upper()} files={len(checks)} baseline={len(baseline["files"])} controls={len(control_checks)} drift=0')


def references():
    findings = obj(TASK / 'findings.json')['findings']
    source_map = obj(TASK / 'source-map.json')
    sources = source_map['sources']
    rows = list(csv.DictReader(read(TASK / 'checkpoints.csv').splitlines()))
    fields = 'checkpoint stage parent_task producer consumer source_path source_sha256 line_start line_end input_output_units clock_reset acceptance_event ownership invariant failure_recovery result evidence optimization verification_next'.split()
    required = 'finding_id severity kind claim evidence_refs reproduction impact recommendation expected_benefit tradeoff validation disposition'.split()
    issues = []
    checked_refs = []
    def check_ref(path, h, a, b, label):
        p = Path(path)
        lines = read(p).splitlines()
        assert 1 <= int(a) <= int(b) <= len(lines), label
        assert sha(p) == h, label
        assert any(s.strip() for s in lines[int(a)-1:int(b)]), label
        checked_refs.append({'label': label, 'path': str(p), 'sha256':h, 'lines':[int(a),int(b)]})
    for k, v in sources.items():
        assert sha(v['snapshot_path']) == v['sha256'], k
    for row in rows:
        assert all(row.get(k, '').strip() for k in fields), row['checkpoint']
        assert row['result'] in {'confirmed_issue','redundancy_candidate','evidence_gap','no_issue_found'}
        check_ref(row['source_path'], row['source_sha256'], row['line_start'], row['line_end'], row['checkpoint'])
        for sid, a, b in re.findall(r'([SP][A-Z0-9_]+):(\d+)-(\d+)', row['evidence']):
            assert sid in sources, (row['checkpoint'], sid)
            s = sources[sid]
            check_ref(s['snapshot_path'], s['sha256'], a, b, row['checkpoint']+':'+sid)
    for f in findings:
        assert all(f.get(k) for k in required), f['finding_id']
        assert f['kind'] in {'confirmed_issue','redundancy_candidate','evidence_gap','no_issue_found'}
        for e in f['evidence_refs']:
            assert e['source_id'] in sources
            assert e['snapshot_path'] == sources[e['source_id']]['snapshot_path']
            assert e['sha256'] == sources[e['source_id']]['sha256']
            check_ref(e['snapshot_path'],e['sha256'],e['line_start'],e['line_end'],f['finding_id'])
    coverage = obj(TASK/'coverage-r0.json')
    declared = [c for step in coverage['five_steps'] for c in step['checkpoints']]
    assert sorted(declared) == sorted(row['checkpoint'] for row in rows)
    assert len(set(declared)) == len(rows) == 28
    al = read(sources['S0155']['snapshot_path'])
    actual_compile = re.findall(r'<File Path="([^"]+)"', al)
    assert actual_compile == source_map['compile_paths']
    assert 'p2_a1_board_top' in al
    assert not any('sync_offline' in x or 'sync_frame_gate' in x for x in actual_compile)
    candidate_text = read(sources['S0141']['snapshot_path']).lower()
    for binding in source_map['candidate_changed_source_binding']:
        h = sources[binding['source_id']]['sha256']
        assert h == binding['candidate_expected_sha256'] and h in candidate_text
    supplements = [v for k,v in sources.items() if k.startswith('P_')]
    assert len(supplements) == 13
    assert all(v['compile_reference'] in actual_compile and v['temporal_qualification'] for v in supplements)
    result = {'marker':'INDEPENDENT_REFERENCE_COMPLETE','checkpoints':len(rows), 'findings':len(findings),
              'source_map_entries':len(sources), 'supplements':len(supplements), 'citation_checks':len(checked_refs),
              'compile_paths':len(actual_compile), 'checks':checked_refs,
              'coverage':{str(step['step']):step['checkpoints'] for step in coverage['five_steps']},
              'all_fields_nonempty':True,'all_hashes_and_line_ranges_valid':True,'issues':issues}
    save('references.json',result)
    print('INDEPENDENT_REFERENCE_COMPLETE checkpoints=28 findings='+str(len(findings))+' sources='+str(len(sources))+' citations='+str(len(checked_refs)))


def provenance():
    """Bit labels and permutation composition, no numerical RAW10 pack/decode loop."""
    sm = obj(TASK/'source-map.json')['sources']
    producer = compact(sm['P_UNPACK']['snapshot_path'])
    match = re.search(r'O_data_out<=\{([^}]+)\};',producer)
    assert match
    slices = [tuple(map(int,m)) for m in re.findall(r'group_data\[(\d+):(\d+)\]',match[1])]
    # Concatenation lists MSB first; map each output bit to its input bit label.
    output_msb = [n for hi,lo in slices for n in range(hi,lo-1,-1)]
    output_lsb = output_msb[::-1]
    assert sorted(output_lsb)==list(range(40))
    # Decoder's output bit j selects these packed-byte input positions.
    def expected_input(lane,bit):
        return 32+2*lane+bit if bit<2 else 8*lane+bit-2
    consumer = compact(sm['S0146']['snapshot_path'])
    assert "b_t=(pix_r>>(byte_k*8))&8'hFF;" in consumer
    assert "samp_t={b_t,2'b00}|((pix_r>>(32+2*byte_k))&2'b11);" in consumer
    trace=[]
    for lane in range(4):
        for bit in range(10):
            expected = expected_input(lane,bit)
            # Check producer lane definition separately before composing consumers.
            assert output_lsb[10*lane+bit] == expected
            actual = output_lsb[expected]
            trace.append({'lane':lane,'sample_bit':bit,'expected_wire_bit':expected,'actual_wire_bit':actual,'equal':actual==expected})
    failed = [x for x in trace if not x['equal']]
    assert failed
    # Construct only a bit-index adapter and verify provenance identity, then mutate it.
    adapter = [None]*40
    for lane in range(4):
        for bit in range(10): adapter[expected_input(lane,bit)] = 10*lane+bit
    def mismatches(mapping):
        return sum(output_lsb[mapping[expected_input(i,j)]] != expected_input(i,j) for i in range(4) for j in range(10))
    assert mismatches(adapter)==0
    mutant=adapter.copy(); mutant[0],mutant[1]=mutant[1],mutant[0]
    assert mismatches(mutant)>0
    save('bit-provenance.json',{'marker':'INDEPENDENT_BIT_PROVENANCE_COMPLETE','scope':'symbolic interface audit; not RTL simulation',
          'method':'compose source bit labels against downstream-required bit positions; independent from developer numerical sample sweeps',
          'bits':40,'wrong_bit_origins':len(failed),'trace':trace,'explicit_adapter_wrong_bits':0,
          'swapped_two_bit_mutation_wrong_bits':mismatches(mutant), 'detects':'missing repack and bit/lane permutation; flat equal-bit vectors cannot hide identity mismatch'})
    print('INDEPENDENT_BIT_PROVENANCE_COMPLETE wrong_origins='+str(len(failed))+'/40 adapter=0 mutation='+str(mismatches(mutant)))


if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('mode',choices=['pre','post','refs','bits']);args=ap.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    if args.mode in ['pre','post']: verify_hashes(args.mode)
    elif args.mode=='refs': references()
    elif args.mode=='bits': provenance()
