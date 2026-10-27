"""Tester-authored independent byte/bit oracle and negative fixtures (all generated)."""
import contextlib
import copy
import hashlib
import io
import json
from pathlib import Path
import random
import sys
import zlib
import redirect_runner as rr

sys.dont_write_bytecode = True
EV = Path(__file__).resolve().parent
PKG = rr.PACKAGE
checks = []
rows = []

def check(name, condition, **details):
    if not condition:
        raise AssertionError(name + ': ' + repr(details))
    checks.append({'check': name, 'result': 'pass', **details})

def ensure(condition, reason):
    if not condition:
        raise ValueError(reason)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def pack(values):
    result = bytearray()
    for start in range(0, len(values), 4):
        group = values[start:start + 4]
        ensure(len(group) == 4 and all(0 <= v < 1024 for v in group), 'bad tester samples')
        result += bytes([group[0] // 4, group[1] // 4, group[2] // 4, group[3] // 4,
                         group[0] % 4 + 4 * (group[1] % 4) + 16 * (group[2] % 4) + 64 * (group[3] % 4)])
    return bytes(result)

def pixels(data):
    ensure(len(data) % 5 == 0, 'RAW10 partial group')
    answer = []
    for off in range(0, len(data), 5):
        low = data[off + 4]
        answer.extend([4 * data[off + col] + (low // (4 ** col)) % 4 for col in range(4)])
    return answer

def normalize(sample):
    data = Path(sample['path']).read_bytes()
    ensure(sha(data) == sample['sha256'].lower(), 'original source SHA mismatch')
    w, h = sample['width'], sample['height']
    ensure(w % 4 == 0 and w >= 4 and h >= 2, 'input geometry')
    if sample['format'] == 'packed_raw10':
        ensure(sample['stride'] == 5 * w // 4 and len(data) == sample['stride'] * h, 'packed geometry/length')
        output = data
    else:
        n = sample['normalization']
        ensure(sample['stride'] == 2 * w and len(data) == 2 * w * h, 'u16 geometry/length')
        ensure(n['byte_order'] in ('little', 'big') and n['valid_bits'] == 10, 'u16 declaration')
        shift = n['right_shift']
        words = [int.from_bytes(data[i:i + 2], n['byte_order']) for i in range(0, len(data), 2)]
        ensure(all(v % (2 ** shift) == 0 and v // (2 ** shift) < 1024 for v in words), 'u16 range or padding')
        output = pack([v // (2 ** shift) for v in words])
    ensure(sha(output) == sample['normalized_raw_sha256'].lower(), 'normalized source SHA mismatch')
    return output

def independent_deflate(stream):
    """Sequential one-bit fixed-code walker; imports no project parser or tables."""
    ensure(len(stream) >= 6 and stream[0] & 15 == 8 and int.from_bytes(stream[:2], 'big') % 31 == 0 and not stream[1] & 32, 'zlib header')
    payload = stream[2:-4]
    position = 0
    output = bytearray()
    blocks = []
    def bit():
        nonlocal position
        ensure(position < 8 * len(payload), 'deflate truncated')
        answer = (payload[position // 8] >> (position % 8)) & 1
        position += 1
        return answer
    def little(n):
        return sum(bit() << k for k in range(n))
    def big(n):
        number = 0
        for _ in range(n):
            number = 2 * number + bit()
        return number
    def fixed_symbol():
        code = big(7)
        if code <= 23:
            return 256 + code
        code = 2 * code + bit()
        if 48 <= code <= 191:
            return code - 48
        if 192 <= code <= 199:
            return 280 + code - 192
        code = 2 * code + bit()
        ensure(400 <= code <= 511, 'fixed code')
        return 144 + code - 400
    final = 0
    while not final:
        final, kind = little(1), little(2)
        start = len(output)
        if kind == 0:
            while position % 8:
                ensure(bit() == 0, 'stored padding')
            size, complement = little(16), little(16)
            ensure(size ^ complement == 65535, 'stored LEN/NLEN')
            ensure(size <= 4800, 'stored maximum')
            output.extend(little(8) for _ in range(size))
        elif kind == 1:
            while True:
                sym = fixed_symbol()
                if sym < 256:
                    output.append(sym)
                elif sym == 256:
                    break
                else:
                    ensure(257 <= sym <= 285, 'reserved length code')
                    if sym <= 264:
                        length = sym - 254
                    elif sym == 285:
                        length = 258
                    else:
                        group = (sym - 265) // 4 + 1
                        length = [11, 19, 35, 67, 131][group - 1] + ((sym - 265) % 4) * (2 ** group) + little(group)
                    ds = big(5)
                    ensure(ds <= 29, 'reserved distance')
                    if ds <= 3:
                        distance = ds + 1
                    else:
                        extra = ds // 2 - 1
                        distance = (2 + ds % 2) * (2 ** extra) + 1 + little(extra)
                    ensure(0 < distance <= min(2048, len(output)), 'distance range')
                    for _ in range(length):
                        output.append(output[-distance])
        else:
            raise ValueError('non-v1 block type')
        blocks.append({'type': kind, 'raw_bytes': len(output) - start})
    while position % 8:
        ensure(bit() == 0, 'final padding')
    ensure(position == len(payload) * 8, 'extra deflate bytes')
    ensure(zlib.adler32(output) & 0xffffffff == int.from_bytes(stream[-4:], 'big'), 'Adler mismatch')
    native = zlib.decompressobj()
    decoded = native.decompress(stream) + native.flush()
    ensure(native.eof and not native.unused_data and not native.unconsumed_tail and decoded == output, 'native zlib disagreement')
    return bytes(output), blocks

def inverse(xform, w, h, flags):
    if flags == 0:
        return xform
    values = pixels(xform)
    result = []
    for row_no in range(h):
        row = values[row_no * w:(row_no + 1) * w]
        even, odd = row[:w // 2], row[w // 2:]
        if flags & 2:
            for part in (even, odd):
                for i in range(1, len(part)):
                    part[i] = (part[i] + part[i - 1]) % 1024
        result.extend(v for pair in zip(even, odd) for v in pair)
    return pack(result)

def record_decode(data):
    ensure(len(data) >= 44, 'header truncated')
    word = lambda off, n: int.from_bytes(data[off:off + n], 'little')
    w, h, flags = word(12, 2), word(14, 2), data[5]
    rlen, xlen, slen = word(16, 4), word(20, 4), word(24, 4)
    ensure(data[:4] == b'A1U1' and data[4] == 1 and word(6, 2) == 44 and flags in (0, 1, 3), 'header identity/flags')
    ensure(w >= 4 and w % 4 == 0 and h >= 2 and rlen == w * h * 5 // 4 and xlen == rlen, 'record geometry/length')
    ensure(len(data) == 44 + slen, 'record stream length')
    ensure(zlib.crc32(data[:40]) & 0xffffffff == word(40, 4), 'header CRC')
    stream = data[44:]
    ensure(zlib.crc32(stream) & 0xffffffff == word(36, 4), 'stream CRC')
    xf, blocks = independent_deflate(stream)
    ensure(len(xf) == xlen and zlib.crc32(xf) & 0xffffffff == word(32, 4), 'xform CRC/length')
    raw = inverse(xf, w, h, flags)
    ensure(len(raw) == rlen and zlib.crc32(raw) & 0xffffffff == word(28, 4), 'raw CRC/length')
    return raw, xf, blocks

def rejected(name, callback):
    try:
        callback()
    except (ValueError, KeyError, TypeError, OSError) as exc:
        checks.append({'check': name, 'result': 'reject', 'reason': str(exc)})
        return str(exc)
    raise AssertionError('negative accepted: ' + name)

def inspect_result(folder, samples):
    result = json.loads((folder / 'benchmark.json').read_text(encoding='utf-8'))
    check('no_real_summary_' + folder.name, result['real_sample_count'] == 0 and result['qualified_real_count'] == 0 and result['ratio'] is None and result['real_summary'] is None and not result['real_samples'] and result['benchmark_result'] == 'blocked')
    for row in result['synthetic_controls'] + result['historical_controls']:
        sample = samples[row['sample_id']]
        raw = normalize(sample)
        data = (folder / (row['sample_id'] + '.a1u1')).read_bytes()
        decoded, xf, blocks = record_decode(data)
        check('independent_roundtrip_' + folder.name + '_' + row['sample_id'], raw == decoded == (folder / (row['sample_id'] + '.decoded.raw10')).read_bytes())
        nraw, nstream, nrecord = len(raw), len(data) - 44, len(data)
        dma = ((nrecord + 4095) // 4096) * 4096
        stored = [v for v in blocks if v['type'] == 0]
        expected = {'raw_bytes': nraw, 'zlib_bytes': nstream, 'a1u1_bytes': nrecord, 'dma_bytes': dma,
                    'header_bytes': 44, 'alignment_bytes': dma - nrecord, 'block_count': len(blocks),
                    'stored_blocks': len(stored), 'stored_raw_bytes': sum(v['raw_bytes'] for v in stored),
                    'ratio_raw_over_zlib': nraw / nstream, 'ratio_raw_over_a1u1': nraw / nrecord,
                    'ratio_raw_over_dma': nraw / dma, 'fallback_block_ratio': len(stored) / len(blocks),
                    'fallback_raw_byte_ratio': sum(v['raw_bytes'] for v in stored) / nraw,
                    'decoded_sha256': sha(decoded), 'original_sha256': sha(Path(sample['path']).read_bytes()),
                    'normalized_raw_sha256': sha(raw), 'raw_crc32': f'{zlib.crc32(raw) & 0xffffffff:08x}',
                    'xform_crc32': f'{zlib.crc32(xf) & 0xffffffff:08x}', 'stream_crc32': f'{zlib.crc32(data[44:]) & 0xffffffff:08x}',
                    'header_crc32': f'{zlib.crc32(data[:40]) & 0xffffffff:08x}', 'byte_differences': 0}
        check('independent_lengths_ratios_fallback_' + folder.name + '_' + row['sample_id'], all(row[k] == v for k, v in expected.items()), expected=expected)
        rows.append({'folder': str(folder), 'sample_id': row['sample_id'], 'blocks': blocks, **expected})
    return result

def main():
    controls = EV / 'local/controls-rerun'
    cfg = json.loads((controls / 'synthetic-inputs.json').read_text(encoding='utf-8'))
    samples = {s['sample_id']: s for s in cfg['samples']}
    originals = json.loads((PKG / 'local/controls-final/synthetic-inputs.json').read_text(encoding='utf-8'))
    check('frozen_test_config_reproduced', all(s['sha256'] == samples[s['sample_id']]['sha256'] and s['normalized_raw_sha256'] == samples[s['sample_id']]['normalized_raw_sha256'] for s in originals['samples']))
    normal = [normalize(samples[k]) for k in ('packed_raw10', 'little_u16', 'big_u16')]
    check('tester_raw10_u16_LE_BE_shift6', normal[0] == normal[1] == normal[2] and pixels(normal[0]) == [0, 1, 2, 3, 255, 256, 511, 1023] * 10)
    check('tester_known_RAW10_bytes', pack([0, 1, 2, 1023]) == b'\x00\x00\x00\xff\xe4')
    for sub in ('benchmark-mode00', 'benchmark-mode10', 'benchmark-mode11', 'historical-exclusion'):
        inspect_result(controls / sub, samples)
    empty = json.loads((EV / 'empty-real-cli/benchmark.json').read_text(encoding='utf-8'))
    check('actual_empty_cli_0_null_blocked', empty['real_sample_count'] == empty['qualified_real_count'] == 0 and empty['ratio'] is None and empty['real_summary'] is None and not empty['real_samples'] and empty['benchmark_result'] == 'blocked')
    check('empty_real_CSV_header_only', len((EV / 'empty-real-cli/real-summary.csv').read_text(encoding='utf-8').splitlines()) == 1)
    iv = json.loads((PKG / 'inputs/inventory.json').read_text(encoding='utf-8'))
    historical = json.loads((rr.PROJECT / 'handoff/rk-a1u1-b18-20261026/expected.json').read_text(encoding='utf-8'))
    check('historical_b18_not_qualified', iv['qualified_real_count'] == 0 and all(not s['accept_for_real_summary'] for s in iv['candidates']) and historical['sensor_pixel_oracle_verified'] is False)

    b = rr.load('benchmark', PKG / 'benchmark.py')
    check('unchanged_ROOT_and_model_paths', b.ROOT == rr.PROJECT and Path(b.ref.__file__).resolve() == rr.PROJECT / 'tools/codec/a1_ref.py' and Path(b.strict.__file__).resolve() == rr.PROJECT / 'tools/codec/a1_inflate_strict.py')
    b.HERE = EV
    negative = EV / 'tester-negatives'
    negative.mkdir(exist_ok=False)
    # Mixed block sizes distinguish block-count and byte-weighted fallback fractions.
    rng = random.Random(2704)
    mixed_values = [rng.randrange(1024) for _ in range(128 * 2)] + [17] * (128 * 2) + [rng.randrange(1024) for _ in range(128)]
    mixed_raw = pack(mixed_values)
    mixed_path = negative / 'mixed-generated.raw10'
    mixed_path.write_bytes(mixed_raw)
    mixed = copy.deepcopy(samples['packed_raw10'])
    mixed.update(sample_id='tester_mixed', path=str(mixed_path), sha256=sha(mixed_raw), normalized_raw_sha256=sha(mixed_raw), width=128, stride=160, content_id='tester_generated_noise_flat_noise', roi={'x': 0, 'y': 0, 'width': 128, 'height': 5, 'source_width': 128, 'source_height': 5})
    mcfg = {'schema_version': 1, 'mode': {'prep': 0, 'pred': 0}, 'samples': [mixed]}
    (negative / 'mixed-config.json').write_text(json.dumps(mcfg, indent=2) + '\n', encoding='utf-8')
    b.run(mcfg, negative, EV / 'tester-mixed-run')
    inspect_result(EV / 'tester-mixed-run', {'tester_mixed': mixed})
    mixed_row = rows[-1]
    check('different_block_and_byte_fallback', 0 < mixed_row['stored_blocks'] < mixed_row['block_count'] and mixed_row['fallback_block_ratio'] != mixed_row['fallback_raw_byte_ratio'], block_fraction=mixed_row['fallback_block_ratio'], byte_fraction=mixed_row['fallback_raw_byte_ratio'])

    rec = bytearray((controls / 'benchmark-mode00/packed_raw10.a1u1').read_bytes())
    original_raw, original_xf, _ = record_decode(rec)
    rec[12:14] = (20).to_bytes(2, 'little')
    rec[40:44] = (zlib.crc32(rec[:40]) & 0xffffffff).to_bytes(4, 'little')
    (negative / 'valid-crcs-wrong-geometry.a1u1').write_bytes(rec)
    crc_states = {'header': zlib.crc32(rec[:40]) & 0xffffffff == int.from_bytes(rec[40:44], 'little'),
                  'stream': zlib.crc32(rec[44:]) & 0xffffffff == int.from_bytes(rec[36:40], 'little'),
                  'xform': zlib.crc32(original_xf) & 0xffffffff == int.from_bytes(rec[32:36], 'little'),
                  'raw': zlib.crc32(original_raw) & 0xffffffff == int.from_bytes(rec[28:32], 'little')}
    check('tester_negative_all_four_CRCs_valid', all(crc_states.values()), crc_states=crc_states, declared_width=20, actual_raw_bytes=100, geometry_requires_raw_bytes=125)
    rejected('independent_valid_CRC_wrong_geometry', lambda: record_decode(rec))
    rejected('candidate_valid_CRC_wrong_geometry', lambda: b.decode_record(rec))
    endian = copy.deepcopy(samples['little_u16'])
    endian['normalization']['byte_order'] = 'big'
    rejected('independent_wrong_endian', lambda: normalize(endian))
    rejected('candidate_wrong_endian', lambda: b.validate_sample(endian, cfg['mode'], controls))
    # Deliberately fictional metadata only tests evidence SHA rejection; never accepted as real.
    evidence = negative / 'fictional-test-evidence.txt'
    evidence.write_text('TEST ONLY. Generated synthetic values. No real sensor evidence.\n', encoding='utf-8')
    source = copy.deepcopy(samples['packed_raw10'])
    source['category'] = 'sensor_capture'
    source['provenance'].update(source_kind='sensor_capture', sensor_pixel_oracle_verified=True,
                                pixel_oracle={'method': 'test-only fictional fixture', 'reviewer': 'tester negative control', 'correctness_basis': 'not a real source; deliberate SHA rejection', 'evidence_path': str(evidence), 'evidence_sha256': '0' * 64, 'normalized_raw_sha256': sha(normal[0]), 'review_decision': 'qualified'})
    (negative / 'bad-evidence-sha-config.json').write_text(json.dumps({'schema_version': 1, 'mode': cfg['mode'], 'samples': [source]}, indent=2) + '\n', encoding='utf-8')
    check('independent_bad_evidence_SHA', sha(evidence.read_bytes()) != source['provenance']['pixel_oracle']['evidence_sha256'])
    reason = rejected('candidate_bad_evidence_SHA', lambda: b.validate_sample(source, cfg['mode'], negative))
    check('candidate_rejects_exact_evidence_SHA_gate', reason == 'pixel evidence SHA mismatch')
    sys.argv = [str(PKG / 'benchmark.py'), '--config', str(negative / 'bad-evidence-sha-config.json'), '--output', str(EV / 'bad-evidence-cli')]
    captured = io.StringIO()
    with contextlib.redirect_stdout(captured), contextlib.redirect_stderr(captured):
        code = b.main()
    (negative / 'bad-evidence-cli.log').write_text(captured.getvalue(), encoding='utf-8')
    bad_result = json.loads((EV / 'bad-evidence-cli/benchmark.json').read_text(encoding='utf-8'))
    check('bad_evidence_CLI_rc2_and_no_real_leak', code == 2 and bad_result['real_sample_count'] == 0 and bad_result['real_summary'] is None and bad_result['ratio'] is None and bad_result['blocked_inputs'][0]['reason'] == 'pixel evidence SHA mismatch', exit_code=code)
    report = {'status': 'independent_checks_pass', 'checks': checks, 'parsed_rows': rows,
              'pure_software_only': True, 'real_sample_count': 0, 'ratio': None, 'real_summary': None,
              'negative_fixtures_are_fictional_not_real_evidence': True,
              'independence': 'Positive oracle imports neither encoder nor strict parser; byte-offset A1U1 parsing, sequential fixed/stored DEFLATE bit walker, native zlib agreement, slice-based pixel reconstruction and explicit normalization. Candidate is called only to compare rejection and generate a synthetic mixed control.',
              'unchanged_ROOT': str(b.ROOT), 'redirected_HERE': str(b.HERE),
              'candidate_sha256': sha((PKG / 'benchmark.py').read_bytes()), 'python_executable': sys.executable, 'python_version': sys.version}
    (EV / 'independent-results.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('INDEPENDENT_CHECKS_PASS checks=' + str(len(checks)) + ' parsed_rows=' + str(len(rows)) + ' real_sample_count=0 ratio=null')

if __name__ == '__main__':
    main()
