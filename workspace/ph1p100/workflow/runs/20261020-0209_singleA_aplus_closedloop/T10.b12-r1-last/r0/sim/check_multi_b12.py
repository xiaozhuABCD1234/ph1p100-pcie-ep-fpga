"""T10.b12-r1-last T10 checker: strict sequential A1U1 + status v4 parser.

Adapted from the frozen independent multi-frame checker
(work/b10-gap-sim-20261025-132023/multi-frame/check_strict.py).  The *frame*
checks are unchanged; only the status packet is the b11/b12 v4 format
(225 B = 4-byte header + 55 x u32 + XOR over bytes 0..223, VER=4), because this
package keeps the frozen v4 status packet.  No raw-deflate fallback, no resync.
"""
import hashlib
import json
import pathlib
import re
import struct
import sys
import zlib

sys.dont_write_bytecode = True
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "indep"))
from a1_pattern_reference import pack_group, inverse_xform  # noqa: E402

FMT = '<IBBHIHHIIIIIII'
ST_LEN = 225
ST_VER = 4
ST_FIELDS = 55


def crc(data):
    return zlib.crc32(data) & 0xffffffff


def reference(seed, w, h, cam_w, roi_x, roi_y):
    rows = []
    st = 0x12345678 ^ seed
    for y in range(roi_y + h):
        row = []
        for g in range(cam_w // 4):
            st ^= (st << 13) & 0xffffffff
            st ^= st >> 17
            st ^= (st << 5) & 0xffffffff
            st &= 0xffffffff
            row.extend([st & 1023, (st >> 10) & 1023, (st >> 20) & 1023, (st >> 22) & 1023])
        if y >= roi_y:
            rows.append(row[roi_x:roi_x + w])
    raw = b''.join(pack_group(*row[x:x + 4]) for row in rows for x in range(0, w, 4))
    xf = bytearray()
    for by in range(0, h, 2):
        samples = []
        for plane in range(4):
            prev = 0
            for k in range(w // 2):
                s = rows[by + plane // 2][2 * k + plane % 2]
                samples.append(s if k == 0 else (s - prev) & 1023)
                prev = s
        for k in range(0, len(samples), 4):
            xf.extend(pack_group(*samples[k:k + 4]))
    return raw, bytes(xf)


def parse(data, nframes, w, h, cam_w, roi_x, roi_y):
    off = 0
    frames, statuses, order = [], [], []
    while off < len(data):
        if data[off:off + 4] == b'A1U1':
            assert len(data) - off >= 44, 'truncated frame header'
            hd = data[off:off + 44]
            (magic, ver, flags, hlen, fid, fw, fh, rl, xl, sl, rc, xc, sc, hc) = struct.unpack(FMT, hd)
            assert (magic, ver, flags, hlen, fw, fh) == (0x31553141, 1, 3, 44, w, h), 'header protocol/geometry/profile'
            assert fid == len(frames) + 1, 'frame ID/order'
            assert rl == xl == w * h * 5 // 4, 'raw/transform declared length'
            assert 0 < sl <= rl + 256, 'stream length bound'
            assert crc(hd[:40]) == hc, 'header CRC'
            body = data[off + 44:off + 44 + sl]
            assert len(body) == sl, 'truncated frame payload'
            assert crc(body) == sc, 'stream CRC'
            dec = zlib.decompressobj()
            xf = dec.decompress(body) + dec.flush()
            assert dec.eof and not dec.unused_data and not dec.unconsumed_tail, 'strict zlib EOF / trailing data'
            assert len(xf) == xl and crc(xf) == xc, 'transform length/CRC'
            raw = inverse_xform(xf, 1, 1, w, h)
            assert len(raw) == rl and crc(raw) == rc, 'raw length/CRC'
            eraw, exf = reference(111 * (len(frames) + 1), w, h, cam_w, roi_x, roi_y)
            assert raw == eraw, 'source RAW mismatch/stale frame'
            assert xf == exf, 'independent forward reference transform mismatch'
            frames.append(dict(frame_id=fid, seed=111 * (len(frames) + 1), offset=off,
                               header_len=hlen, stream_len=sl, raw_len=rl, xform_len=xl,
                               header_crc=f'{hc:08x}', stream_crc=f'{sc:08x}',
                               xform_crc=f'{xc:08x}', raw_crc=f'{rc:08x}', four_crcs_verified=True,
                               strict_zlib_eof=True, unused_data=0, unconsumed_tail=0,
                               reference_raw=True, reference_transform=True,
                               raw_sha256=hashlib.sha256(raw).hexdigest(),
                               xform_sha256=hashlib.sha256(xf).hexdigest()))
            order.append('frame:' + str(fid))
            off += 44 + sl
        elif data[off:off + 2] == b'\xa5\x5a':
            p = data[off:off + ST_LEN]
            assert len(p) == ST_LEN, 'truncated status'
            assert p[:4] == bytes([0xa5, 0x5a, ST_LEN & 0xff, ST_VER]), 'status header/version/length'
            xor = 0
            for b in p[:-1]:
                xor ^= b
            assert p[-1] == xor, 'status XOR'
            vals = struct.unpack('<%dI' % ST_FIELDS, p[4:4 + 4 * ST_FIELDS])
            statuses.append(dict(offset=off, after_frame=len(frames), length=ST_LEN, version=ST_VER,
                                 fields=ST_FIELDS, xor_verified=True,
                                 captured=vals[0], raw_pub=vals[1], encoded=vals[2],
                                 exported=vals[3], errors=vals[6]))
            order.append('status')
            off += ST_LEN
        else:
            raise AssertionError(f'unexpected byte at packet boundary offset={off}: {data[off:off+8].hex()}')
    assert off == len(data), 'capture trailing garbage'
    assert len(frames) == nframes, f'frame count: got {len(frames)} expected {nframes}'
    assert len({f['raw_sha256'] for f in frames}) == nframes, 'sources are not distinct'
    return dict(frames=frames, statuses=statuses, order=order, bytes_consumed=off)


def mutate_tail(data, frame):
    off = frame['offset']
    hd = bytearray(data[off:off + 44])
    sl = frame['stream_len']
    payload = data[off + 44:off + 44 + sl] + b'\0'
    struct.pack_into('<I', hd, 24, sl + 1)
    struct.pack_into('<I', hd, 36, crc(payload))
    struct.pack_into('<I', hd, 40, crc(hd[:40]))
    return data[:off] + hd + payload + data[off + 44 + sl:]


def check(case):
    case = pathlib.Path(case)
    stats = {k: int(v) for k, v in re.findall(r'(\w+)=(\d+)', (case / 'stats.txt').read_text())}
    data = bytes(map(int, (case / 'capture.dec').read_text().split()))
    wire = bytes(map(int, (case / 'wire.dec').read_text().split()))
    log = (case / 'console.log').read_text(errors='replace')
    errors, decoded, mutants = [], {}, []
    def req(ok, why):
        if not ok:
            errors.append(why)
    n = stats['nframes']
    args = (n, stats['w'], stats['h'], stats['cam_w'], stats['roi_x'], stats['roi_y'])
    req('MULTI_DONE' in log, 'missing normal completion marker')
    req('Fatal' not in log and 'ASSERT_FAIL' not in log and 'WATCHDOG' not in log,
        'sim assertion/fatal/watchdog')
    req(data == wire, 'physical UART capture != transmitted debug bytes')
    req(stats['cap_bytes'] == stats['wire_bytes'] == len(data), 'capture length accounting')
    for key in ['cap', 'raw_pub', 'enc', 'exported', 'source_frames', 'crop_sofs', 'crop_lasts']:
        req(stats[key] == n, key + ' != expected frame count')
    for key in ['raw_drop', 'cmp_drop', 'geom', 'err', 'dup_words', 'fifo_reject', 'assert_fails']:
        req(stats[key] == 0, key + ' nonzero')
    req(stats['crop_beats'] == stats['raw_beats'] == n * stats['w'] * stats['h'] // 4,
        'crop/RAW group accounting')
    req(stats['source_groups'] == n * (stats['roi_y'] + stats['h']) * (stats['cam_w'] // 4),
        'full camera driver group accounting')
    req(stats['raw_writes'] > 0 and stats['cmp_writes'] > 0 and stats['cmp_words'] > 0,
        'real RAW/CMP DDR/core path missing')
    try:
        decoded = parse(data, *args)
        req(sum(f['stream_len'] for f in decoded['frames']) == stats['exp_bytes'],
            'exported stream byte accounting')
        if n == 3:
            req(stats['ticks_in_frame'] > 0, 'no real status tick during open frame')
            req(stats['boundary_due_queued'] > 0, 'no real dq>0 + status_due frame boundary')
            req(any(0 < s['after_frame'] < n for s in decoded['statuses']),
                'no %d-byte status between frames' % ST_LEN)
            req(len(decoded['statuses']) == stats['status_grants'], 'status grant/packet count mismatch')
            req(all(s['version'] == ST_VER and s['fields'] == ST_FIELDS and s['xor_verified']
                    for s in decoded['statuses']), 'status v4 format/XOR')
        else:
            req(not decoded['statuses'], 'control should have status disabled')
        first = decoded['frames'][0]
        bad = bytearray(data)
        bad[first['offset'] + 44] ^= 1
        for name, mut, expected in [('payload_bit_flip', bytes(bad), 'stream CRC'),
                                    ('valid_outer_CRC_zlib_tail', mutate_tail(data, first), 'strict zlib EOF')]:
            try:
                parse(mut, *args)
            except (AssertionError, ValueError, zlib.error, IndexError) as exc:
                rejection = str(exc)
                ok = expected in rejection
                mutants.append(dict(name=name, rejected=True, expected_reason=expected,
                                    actual_reason=rejection, valid_rejection=ok))
                req(ok, 'mutant failed for unexpected reason ' + name)
            else:
                mutants.append(dict(name=name, rejected=False))
                errors.append('checker accepted mutant ' + name)
    except (AssertionError, ValueError, zlib.error, IndexError) as exc:
        errors.append(str(exc))
    return dict(status='PASS' if not errors else 'FAIL', errors=errors, stats=stats, decoded=decoded,
                negative_tests=mutants, capture_sha256=hashlib.sha256(data).hexdigest(),
                wire_sha256=hashlib.sha256(wire).hexdigest(), capture_bytes=len(data),
                limitations=['64x8 ROI small geometry, not 1080p, no board-rate/STA/hardware claim',
                             'Three frames share one reset epoch; finite RAW slots may delay third input'])


if __name__ == '__main__':
    result = check(sys.argv[1])
    pathlib.Path(sys.argv[1], 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    sys.exit(result['status'] != 'PASS')
