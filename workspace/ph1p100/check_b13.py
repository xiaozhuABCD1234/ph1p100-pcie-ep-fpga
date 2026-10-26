"""T10.b13-ddr-retry checker: strict A1U1 frame + v5 status packet parser.

Adapted from check_multi_b12.py (T10.b12-r1-last).  The frame checks are
unchanged (44 B header, four CRCs, strict zlib EOF, independent RAW/xform
reference).  The status packet is the b13 v5 format:
  241 B = 4-byte header (A5 5A F1 05) + 59 x u32 LE + XOR over bytes 0..239.

Extra b13 checks (timeout / retry / giveup / stale-guard bookkeeping, guard
window silence, no half frame) are driven by expectations passed on the command
line as key=value pairs.  The PASS conditions of the frame decoder are NOT
weakened: a short/partial frame still fails mplicitly through the CRC/zlib/
reference asserts.

Usage:
  python check_b13.py <case_dir> [exported=1,timeout=1,retry=1,giveup=0,stale=0]
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
sys.path.insert(0, str(HERE / "indep" / "indep"))
from a1_pattern_reference import pack_group, inverse_xform  # noqa: E402

FMT = '<IBBHIHHIIIIIII'
ST_LEN = 241
ST_VER = 5
ST_FIELDS = 59


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


def parse(data, w, h, cam_w, roi_x, roi_y):
    off = 0
    frames, statuses = [], []
    while off < len(data):
        if data[off:off + 4] == b'A1U1':
            assert len(data) - off >= 44, 'truncated frame header'
            hd = data[off:off + 44]
            (magic, ver, flags, hlen, fid, fw, fh, rl, xl, sl, rc, xc, sc, hc) = struct.unpack(FMT, hd)
            assert (magic, ver, flags, hlen, fw, fh) == (0x31553141, 1, 3, 44, w, h), \
                'header protocol/geometry/profile'
            assert rl == xl == w * h * 5 // 4, 'raw/transform declared length'
            assert 0 < sl <= rl + 256, 'stream length bound'
            assert crc(hd[:40]) == hc, 'header CRC'
            body = data[off + 44:off + 44 + sl]
            assert len(body) == sl, 'truncated frame payload'
            assert crc(body) == sc, 'stream CRC'
            dec = zlib.decompressobj()
            xf = dec.decompress(body) + dec.flush()
            assert dec.eof and not dec.unused_data and not dec.unconsumed_tail, \
                'strict zlib EOF / trailing data'
            assert len(xf) == xl and crc(xf) == xc, 'transform length/CRC'
            raw = inverse_xform(xf, 1, 1, w, h)
            assert len(raw) == rl and crc(raw) == rc, 'raw length/CRC'
            f = dict(frame_id=fid, offset=off, header_len=hlen, stream_len=sl,
                     raw_len=rl, xform_len=xl,
                     header_crc=f'{hc:08x}', stream_crc=f'{sc:08x}',
                     xform_crc=f'{xc:08x}', raw_crc=f'{rc:08x}',
                     four_crcs_verified=True, strict_zlib_eof=True,
                     unused_data=0, unconsumed_tail=0,
                     raw_sha256=hashlib.sha256(raw).hexdigest(),
                     xform_sha256=hashlib.sha256(xf).hexdigest())
            f['raw'] = raw
            f['xf'] = xf
            frames.append(f)
            off += 44 + sl
        elif data[off:off + 2] == b'\xa5\x5a':
            p = data[off:off + ST_LEN]
            assert len(p) == ST_LEN, 'truncated status'
            assert p[:4] == bytes([0xa5, 0x5a, ST_LEN & 0xff, ST_VER]), \
                'status header/version/length'
            xor = 0
            for b in p[:-1]:
                xor ^= b
            assert p[-1] == xor, 'status XOR'
            vals = struct.unpack('<%dI' % ST_FIELDS, p[4:4 + 4 * ST_FIELDS])
            statuses.append(dict(offset=off, after_frame=len(frames), length=ST_LEN,
                                 version=ST_VER, fields=ST_FIELDS, xor_verified=True,
                                 captured=vals[0], raw_pub=vals[1], encoded=vals[2],
                                 exported=vals[3], errors=vals[6],
                                 br0=vals[43], ar_cnt=vals[44], r_cnt=vals[46],
                                 stale_r=vals[48], rd_wait=vals[49],
                                 timeout_cnt=vals[55], retry_cnt=vals[56],
                                 giveup=vals[57], stale_guard=vals[58]))
            off += ST_LEN
        else:
            raise AssertionError(f'unexpected byte at packet boundary offset={off}: '
                                 f'{data[off:off + 8].hex()}')
    assert off == len(data), 'capture trailing garbage'
    return dict(frames=frames, statuses=statuses, bytes_consumed=off)


def mutate_tail(data, frame):
    off = frame['offset']
    hd = bytearray(data[off:off + 44])
    sl = frame['stream_len']
    payload = data[off + 44:off + 44 + sl] + b'\0'
    struct.pack_into('<I', hd, 24, sl + 1)
    struct.pack_into('<I', hd, 36, crc(payload))
    struct.pack_into('<I', hd, 40, crc(hd[:40]))
    return data[:off] + hd + payload + data[off + 44 + sl:]


def check(case, expect=None):
    expect = dict(expect or {})
    case = pathlib.Path(case)
    stats = {k: int(v) for k, v in re.findall(r'(\w+)=(\d+)', (case / 'stats.txt').read_text())}
    data = bytes(map(int, (case / 'capture.dec').read_text().split()))
    wire = bytes(map(int, (case / 'wire.dec').read_text().split()))
    trace = (case / 'trace.txt').read_text(errors='replace')
    log = (case / 'console.log').read_text(errors='replace')
    errors, mutants, timeouts = [], [], []

    def req(ok, why):
        if not ok:
            errors.append(why)

    n = stats['nframes']
    n_exp = int(expect.get('exported', n))
    req('B13_CHAIN_DONE' in log, 'missing normal completion marker')
    req('Fatal' not in log and 'ASSERT_FAIL' not in log and 'WATCHDOG' not in log,
        'sim assertion/fatal/watchdog')
    req(data == wire, 'physical UART capture != transmitted debug bytes')
    req(stats['cap_bytes'] == stats['wire_bytes'] == len(data), 'capture length accounting')
    req(stats['cap'] == n and stats['source_frames'] == n, 'source/capture frame count')
    req(stats['exported'] == n_exp, 'exported=%d expected %d' % (stats['exported'], n_exp))
    req(stats['enc'] == n_exp, 'enc=%d expected %d' % (stats['enc'], n_exp))
    for key in ('raw_drop', 'cmp_drop', 'geom', 'err', 'dup_words'):
        req(stats[key] == 0, key + ' nonzero')
    req(stats['raw_pub'] == n_exp + stats['giveup_cnt'],
        'raw_pub=%d not exported(%d)+giveup(%d)' % (stats['raw_pub'], n_exp, stats['giveup_cnt']))
    req(stats['crop_sofs'] == n and stats['crop_lasts'] == n, 'crop frame boundary count')
    req(stats['raw_writes'] > 0 and stats['cmp_writes'] > 0 and stats['cmp_words'] > 0,
        'real RAW/CMP DDR/core path missing')
    req(stats['max_dq'] == 0, 'descriptor queue non-empty at end')
    req(stats['giveup_cnt'] <= stats['timeout_cnt'], 'giveup > timeout')
    req(stats['retry_cnt'] <= stats['timeout_cnt'], 'retry > timeout')
    req(stats['guard_ar'] == 0, 'AR asserted inside the store guard window')

    for key in ('timeout', 'retry', 'giveup', 'stale'):
        if key in expect:
            got = stats[{'timeout': 'timeout_cnt', 'retry': 'retry_cnt',
                         'giveup': 'giveup_cnt', 'stale': 'stale_guard_cnt'}[key]]
            req(got == int(expect[key]), '%s=%d expected %d' % (key, got, int(expect[key])))
    if n_exp == n:
        req(stats['timeout_cnt'] == 0 or 'timeout' in expect,
            'unexpected timeout on a clean run')

    for line in trace.splitlines():
        m = re.match(r'RD_TIMEOUT cycles=(\d+) rd_idx=(\d+) rd_words=(\d+) rd_sel=(\d+)', line)
        if m:
            timeouts.append(dict(cycle=int(m.group(1)), rd_idx=int(m.group(2)),
                                 rd_words=int(m.group(3)), rd_sel=int(m.group(4))))

    decoded = {}
    try:
        decoded = parse(data, stats['w'], stats['h'], stats['cam_w'],
                        stats['roi_x'], stats['roi_y'])
        frames = decoded['frames']
        req(len(frames) == n_exp, 'decoded frame count %d != %d' % (len(frames), n_exp))
        req(len(decoded['statuses']) >= 1, 'no v5 status packet captured')
        req(len(decoded['statuses']) == stats['status_grants'],
            'status grant/packet count mismatch')
        req(all(s['version'] == ST_VER and s['fields'] == ST_FIELDS and s['xor_verified']
                for s in decoded['statuses']), 'status v5 format/XOR')
        req(all(f['frame_id'] > 0 for f in frames), 'invalid frame id')
        ids = [f['frame_id'] for f in frames]
        req(ids == sorted(set(ids)), 'frame ids not strictly increasing')
        # Reference match: the source seeds are 111*(i+1); a retried/given-up
        # source keeps its seed, so match the exported frames in seed order.
        seeds = [111 * (i + 1) for i in range(n)]
        p = 0
        for f in frames:
            raw, xf = f.pop('raw'), f.pop('xf')
            found = None
            for q in range(p, len(seeds)):
                eraw, exf = reference(seeds[q], stats['w'], stats['h'], stats['cam_w'],
                                      stats['roi_x'], stats['roi_y'])
                if raw == eraw:
                    found = q
                    req(xf == exf, 'independent forward reference transform mismatch')
                    break
            req(found is not None, 'frame %d RAW matches no remaining source seed' % f['frame_id'])
            if found is not None:
                f['seed'] = seeds[found]
                f['reference_raw'] = True
                f['reference_transform'] = True
                p = found + 1
        req(sum(f['stream_len'] for f in frames) == stats['exp_bytes'],
            'exported stream byte accounting')
        af = [s['after_frame'] for s in decoded['statuses']]
        req(af == sorted(af) and all(0 <= x <= n for x in af), 'status placement/order')
        if frames:
            first = frames[0]
            bad = bytearray(data)
            bad[first['offset'] + 44] ^= 1
            for name, mut, expected in (('payload_bit_flip', bytes(bad), 'stream CRC'),
                                        ('valid_outer_CRC_zlib_tail',
                                         mutate_tail(data, first), 'strict zlib EOF')):
                try:
                    parse(mut, stats['w'], stats['h'], stats['cam_w'],
                          stats['roi_x'], stats['roi_y'])
                except (AssertionError, ValueError, zlib.error, IndexError) as exc:
                    rejection = str(exc)
                    mutants.append(dict(name=name, rejected=True, expected_reason=expected,
                                        actual_reason=rejection,
                                        valid_rejection=(expected in rejection)))
                    req(expected in rejection, 'mutant rejected for wrong reason ' + name)
                else:
                    mutants.append(dict(name=name, rejected=False))
                    errors.append('checker accepted mutant ' + name)
    except (AssertionError, ValueError, zlib.error, IndexError) as exc:
        errors.append(str(exc))
    return dict(status='PASS' if not errors else 'FAIL', errors=errors, stats=stats,
                expectations=expect, decoded=decoded, timeouts=timeouts,
                negative_tests=mutants,
                capture_sha256=hashlib.sha256(data).hexdigest(),
                wire_sha256=hashlib.sha256(wire).hexdigest(), capture_bytes=len(data),
                limitations=['64x8 ROI small geometry, not 1080p',
                             'no board-rate/STA/hardware claim from this case'])


if __name__ == '__main__':
    exp = {}
    for a in sys.argv[2:]:
        if '=' in a:
            k, v = a.split('=', 1)
            exp[k] = int(v)
    result = check(sys.argv[1], exp)
    pathlib.Path(sys.argv[1], 'result.json').write_text(json.dumps(result, indent=2))
    print(json.dumps({k: result[k] for k in ('status', 'errors', 'expectations', 'timeouts')},
                     indent=2))
    print('B13_CHECK_RESULT status=%s frames=%d statuses=%d timeout=%s retry=%s giveup=%s stale=%s'
          % (result['status'], len(result.get('decoded', {}).get('frames', [])),
             len(result.get('decoded', {}).get('statuses', [])),
             result['stats'].get('timeout_cnt'), result['stats'].get('retry_cnt'),
             result['stats'].get('giveup_cnt'), result['stats'].get('stale_guard_cnt')))
    sys.exit(result['status'] != 'PASS')
