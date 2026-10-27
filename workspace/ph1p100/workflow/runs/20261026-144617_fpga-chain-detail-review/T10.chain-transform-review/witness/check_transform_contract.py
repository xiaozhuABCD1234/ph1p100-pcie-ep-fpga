"""Small offline witnesses. No RTL simulator, board, network, or source writes.
Run with --stdout to reproduce without modifying the frozen package.
"""
import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import random
import struct
import sys
import zlib

OUT = Path(__file__).resolve().parents[1]
RUN = OUT.parent
BASE = RUN / 'baseline' / 'snapshot'

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod

def pack_samples(samples):
    out = bytearray()
    for i in range(0, len(samples), 4):
        q = samples[i:i+4]
        out.extend([x >> 2 for x in q])
        out.append(sum((x & 3) << (2*j) for j, x in enumerate(q)))
    return bytes(out)

def raw_vector(w, h):
    return pack_samples([((y*173 + x*79 + (x*x*7)) ^ 341) & 1023
                         for y in range(h) for x in range(w)])

def crc_bitwise(data):
    c = 0xffffffff
    for b in data:
        c ^= b
        for _ in range(8):
            c = (c >> 1) ^ (0xedb88320 if c & 1 else 0)
    return c ^ 0xffffffff

def record(raw, xf, stream, w, h, flags=0):
    first = struct.pack('<IBBHIHHIIIIII', 0x31553141, 1, flags, 44,
                        7, w, h, len(raw), len(xf), len(stream),
                        zlib.crc32(raw), zlib.crc32(xf), zlib.crc32(stream))
    assert len(first) == 40
    return first + struct.pack('<I', zlib.crc32(first)) + stream

def run():
    ref = load('t10_ref', OUT / 'inputs' / 'a1_ref.py')
    pattern = load('a1_pattern', OUT / 'inputs' / 'a1_pattern.py')
    strict = load('t10_strict', OUT / 'inputs' / 'a1_inflate_strict.py')
    pc = load('t10_pc_decode', BASE / '0054.py')
    frame = (BASE / '0146.v').read_text(encoding='utf-8')
    core = (BASE / '0145.v').read_text(encoding='utf-8')
    assert 'assign frame_commit = svalid && out_ready && slast && !killed;' in frame
    assert '!(svalid && out_ready && slast && !killed)' in frame
    assert 'stored_bits <= stored_cost(obits, sel_len);' in core
    assert 'if (blk_avail && htab_clr_done)' in core

    # Actual frozen software producer -> stdlib zlib -> a separately written
    # decoder, plus separately sourced legacy inverse. Not an RTL execution.
    cases = []
    for w, h in [(8, 2), (12, 2), (8, 3), (16, 3), (1920, 2)]:
        raw = raw_vector(w, h)
        for prep, pred in [(0, 0), (1, 0), (1, 1)]:
            enc = ref.encode_frame(raw, w, h, prep, pred)
            xf = zlib.decompress(enc['stream'])
            strict_xf, stats = strict.inflate(enc['stream'], expected_len=len(raw))
            assert xf == strict_xf == enc['xform']
            assert ref.inverse_frame(xf, w, h, prep, pred) == raw
            try:
                old = pattern.inverse_xform(xf, prep, pred, w, h)
                actual = 'equal' if old == raw else 'mismatch'
            except (IndexError, ValueError) as e:
                actual = type(e).__name__
            expected = 'equal' if not prep or (w % 8 == 0 and h % 2 == 0) else 'not_equal'
            assert (actual == 'equal') == (expected == 'equal')
            assert all(crc_bitwise(b) == zlib.crc32(b) for b in [raw, xf, enc['stream']])
            cases.append(dict(w=w, h=h, prep=prep, pred=pred,
                              bytes=len(raw), stream_bytes=len(enc['stream']),
                              strict_stats=stats, legacy_inverse=actual,
                              raw_sha256=hashlib.sha256(raw).hexdigest()))

    # Use an explicitly written single stored block so zero-pad mutation has
    # a known location. Recompute outer CRCs to test semantic rejection.
    raw = raw_vector(8, 2)
    body = b'\x01' + struct.pack('<HH', len(raw), len(raw) ^ 0xffff) + raw
    canonical = b'\x78\x9c' + body + struct.pack('>I', zlib.adler32(raw))
    malformed = {'trailing_zero': canonical + b'\x00',
                 'nonzero_stored_pad': canonical[:2] + bytes([canonical[2] | 8]) + canonical[3:]}
    tails = []
    flags = ['header_crc_ok', 'stream_crc_ok', 'zlib_ok', 'xform_len_ok',
             'xform_crc_ok', 'raw_len_ok', 'raw_crc_ok', 'worstcase_ok']
    for name, stream in malformed.items():
        parsed = pc.decode_stream(record(raw, raw, stream, 8, 2), write=False)[0][0]
        assert all(parsed[k] for k in flags)
        dec = zlib.decompressobj()
        assert dec.decompress(stream) == raw and dec.eof
        try:
            strict.inflate(stream, expected_len=len(raw))
            raise AssertionError('strict accepted malformed input')
        except strict.A1Error as e:
            rejection = str(e)
        tails.append(dict(case=name, pc_all_checks=True,
                          zlib_unused_hex=dec.unused_data.hex(), strict_rejection=rejection))
    bad_adler = canonical[:-1] + bytes([canonical[-1] ^ 1])
    try:
        zlib.decompress(bad_adler)
        raise AssertionError('Adler negative control failed')
    except zlib.error:
        pass

    # Truth-table witness for the declared abort-never-commit contract.
    abort_case = dict(frame_active=True, abort=True, proto_abort=False,
                      svalid=True, slast=True, out_ready=True, killed=False)
    commit = abort_case['svalid'] and abort_case['out_ready'] and abort_case['slast'] and not abort_case['killed']
    abort_branch = abort_case['frame_active'] and abort_case['abort'] and not commit
    assert commit and not abort_branch

    # Exact-offset induction: ceil((bits + chosen_cost)/8) grows <= n+5.
    # Include every cost from zero to stored in a small block for all offsets.
    count = 0
    for off in range(8):
        for n in range(1, 33):
            stored = 3 + ((8 - (off+3)) & 7) + 32 + 8*n
            for chosen in range(stored+1):
                assert (off+chosen+7)//8 <= (off+7)//8 + n + 5
                count += 1
    ideal = 2592000 + 5*540 + 6
    capacity = 81085*32
    assert ideal == 2594706 and capacity == 2594720
    # A legal queue arithmetic state illustrates why choosing cost from the
    # consumed offset cannot substitute for the queued offset without proof.
    stale, pending, n = 6, 2, 32
    real = (stale + pending) % 8
    calc = 3 + ((8 - (stale+3)) & 7) + 32 + n*8
    actual = 3 + ((8 - (real+3)) & 7) + 32 + n*8
    candidate = n*8 + 41
    assert actual < candidate < calc
    # This is a symbolic queue state, not proof it occurs in a real RTL run.

    # Scalar datapath arithmetic maxima and four-lane collision oracle.
    assert 77*255+150*255+29*255+128 == 65408
    assert 16*255+8 == 4088
    for v in range(256):
        assert (77*v+150*v+29*v+128) >> 8 == v
    banks = [[0]*256 for _ in range(4)]
    for _ in range(17):
        for lane in range(4):
            banks[lane][7] += 1
    assert sum(b[7] for b in banks) == 68
    # Excludes the timing of RAM forwarding/stalls; retained as a future DUT check.
    result = dict(marker='TRANSFORM_WITNESS_COMPLETE', qualification='software vectors, source-anchored scalar/Boolean witnesses; no RTL execution',
                  geometry_cases=cases, strictness_cases=tails, adler_mutation_rejected=True,
                  abort_commit=dict(inputs=abort_case, frame_commit=commit, abort_branch=abort_branch,
                                    expected_abort_never_commit=False),
                  capacity=dict(exact_offset_induction_checks=count, ideal_stream_bound=ideal,
                                output_32bit_aligned=(ideal+3)//4*4, slot_bytes=capacity,
                                ideal_spare_bytes=capacity-ideal,
                                queued_offset_countermodel=dict(consumed_offset=stale,pending_bits=pending,
                                    actual_next_offset=real,seeded_stored_cost=calc,
                                    actual_stored_cost=actual,candidate_bits=candidate,
                                    reachable_RTL_state='not_proven'),
                                offset_agnostic_bound=(8*2592000+42*540+7)//8+6,
                                capacity_proven_for_current_RTL=False),
                  gray_max=65408, gaussian_max_including_round=4088,
                  he_four_lane_samebin_count=68, he_lut_generation_cycles_only=256*14,
                  tag_wrap=dict(blocks=65536,blocks_per_1080_frame=540,
                                frames=65536/540,seconds_at_30fps=65536/(540*30),
                                stale_entry_survival='not_proven; targeted RTL test required'))
    return result

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--stdout', action='store_true')
    args = ap.parse_args()
    data = run()
    encoded = json.dumps(data, indent=2, ensure_ascii=False)
    if args.stdout:
        print(encoded)
    else:
        (OUT / 'witness' / 'result-r0.json').write_text(encoded+'\n', encoding='utf-8')
        print('TRANSFORM_WITNESS_COMPLETE cases=%d' % len(data['geometry_cases']))
