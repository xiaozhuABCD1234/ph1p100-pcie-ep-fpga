"""Tester-owned independent T03 offline functional evidence; no DUT changes."""
from pathlib import Path
import contextlib
import hashlib
import io
import json
import platform
import runpy
import struct
import sys
import time

sys.dont_write_bytecode = True
RUN = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
MANIFEST = RUN / 'candidate-manifest.json'
EXPECTED_MANIFEST = '9662167a4af6fcea43a76491a9507b191552fa52209648147de02f91cfd877c5'
RESULTS = []

def check(name, actual, expected):
    RESULTS.append({'id': name, 'actual': actual, 'expected': expected, 'pass': actual == expected})

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def verify_manifest(stage):
    check(stage + ':manifest-hash', sha(MANIFEST), EXPECTED_MANIFEST)
    manifest = json.loads(MANIFEST.read_text(encoding='utf-8-sig'))
    mismatches = []
    for entry in manifest['files']:
        path = Path(entry['path'])
        if not path.is_file():
            mismatches.append({'path': entry['relative_path'], 'reason': 'missing'})
        elif path.stat().st_size != entry['bytes'] or sha(path) != entry['sha256']:
            mismatches.append({'path': entry['relative_path'], 'reason': 'bytes/hash'})
    check(stage + ':all-frozen-files', mismatches, [])
    return len(manifest['files'])

# CRC table derived from the specified reflected polynomial, independently of
# the fixture generator and the candidate binascii/zlib-based checker.
TABLE = []
for value in range(256):
    for _ in range(8):
        value = (value >> 1) ^ (0xEDB88320 if value & 1 else 0)
    TABLE.append(value)

def crc(data):
    state = 0xFFFFFFFF
    for byte in data:
        state = TABLE[(state ^ byte) & 255] ^ (state >> 8)
    return state ^ 0xFFFFFFFF

def number(blob, offset, size=4):
    return int.from_bytes(blob[offset:offset + size], 'little')

def recalc_header(blob):
    blob[0x58:0x5C] = bytes(4)
    blob[0x58:0x5C] = crc(blob[:128]).to_bytes(4, 'little')
    return blob

def strict_oracle(blob, ds):
    if len(blob) < 128:
        return False
    if blob[:4] != b'R10F' or [number(blob, x, 2) for x in (4, 6, 8)] != [1, 0, 128]:
        return False
    if blob[11] != 0 or number(blob, 12) != 0 or blob[42:44] != bytes([10, 0]):
        return False
    width, height = number(blob, 28, 2), number(blob, 30, 2)
    if (width, height) != (ds['width'], ds['height']) or width == 0 or height == 0 or width % 4:
        return False
    stride = width // 4 * 5
    raw = stride * height
    if (number(blob, 32), number(blob, 44), number(blob, 48)) != (stride, raw, raw):
        return False
    if number(blob, 76) & 0xFFFFFFFD or any(blob[92:128]):
        return False
    if (number(blob, 16), number(blob, 20)) != (0x20261017, 1):
        return False
    end = 128 + raw
    dma = ((end + 4095) // 4096) * 4096
    if len(blob) != dma or dma != ds['dma_bytes'] or any(blob[end:]):
        return False
    header = bytearray(blob[:128])
    stored_header_crc = number(header, 88)
    header[88:92] = bytes(4)
    effective_crc = crc(blob[128:end])
    return (crc(header) == stored_header_crc and
            effective_crc == number(blob, 80) == number(blob, 84))

def mutate(blob, operation):
    b = bytearray(blob)
    if operation == 'none':
        pass
    elif operation == 'drop_last_byte':
        del b[-1:]
    elif operation == 'tail_nonzero':
        b[-1] = 1
    elif operation == 'payload_flip':
        b[128] ^= 1
    elif operation == 'header_flip':
        b[24] ^= 1
    else:
        fields = {
            'set_codec_1_recrc': (12, 4, 1),
            'set_bad_recrc': (76, 4, 1),
            'set_partial_recrc': (76, 4, 4),
            'set_oversize_recrc': (76, 4, 8),
            'set_length_recrc': (48, 4, number(b, 44) + 1),
        }
        off, size, value = fields[operation]
        b[off:off + size] = value.to_bytes(size, 'little')
        recalc_header(b)
    return b

start = time.time()
file_count = verify_manifest('before')
vectors = json.loads((RUN / 'contract/acceptance-vectors.json').read_text(encoding='utf-8-sig'))
registers = json.loads((RUN / 'contract/registers.json').read_text(encoding='utf-8-sig'))
check('crc-standard-check', crc(b'123456789'), 0xCBF43926)
check('crc-empty-check', crc(b''), 0)

# Rerun the candidate suite, saving its actual stdout; no frozen outputs written.
previous_argv = sys.argv
sys.argv = [str(RUN / 'contract/check_contract.py')]
candidate_stdout = io.StringIO()
try:
    with contextlib.redirect_stdout(candidate_stdout):
        candidate = runpy.run_path(str(RUN / 'contract/check_contract.py'))
finally:
    sys.argv = previous_argv
(OUT / 'candidate-check.log').write_text(candidate_stdout.getvalue(), encoding='utf-8')
(OUT / 'candidate-check-result.json').write_text(json.dumps(candidate['output'], indent=2) + '\n', encoding='utf-8')
check('candidate-suite-marker', candidate['output']['marker'], 'CONTRACT_FIXTURES_OK')
check('candidate-suite-failures', candidate['output']['failures'], 0)

derived = []
extra_mutations = [
    ('magic', 0, 4, int.from_bytes(b'NOPE', 'little')),
    ('major', 4, 2, 2), ('minor', 6, 2, 1), ('header-length', 8, 2, 16),
    ('format', 11, 1, 1), ('valid-bits', 42, 1, 8), ('packing', 43, 1, 1),
    ('zero-width', 28, 2, 0), ('unaligned-width', 28, 2, 7),
    ('zero-height', 30, 2, 0), ('stride', 32, 4, 1), ('raw-bytes', 44, 4, 1),
    ('payload-huge', 48, 4, 0xFFFFFFFF), ('payload-zero', 48, 4, 0),
    ('unknown-flags', 76, 4, 16), ('reserved-nonzero', 127, 1, 1),
    ('wrong-session', 16, 4, 1), ('wrong-seq', 20, 4, 2),
    ('raw-crc', 80, 4, 0), ('payload-crc', 84, 4, 0),
]
for ds in vectors['datasets']:
    name = ds['name']
    blob = (RUN / ds['path']).read_bytes()
    width, height = ds['width'], ds['height']
    stride = width // 4 * 5
    raw = stride * height
    content = 128 + raw
    dma = ((content + 4095) // 4096) * 4096
    host_stride = ((128 + dma + 4095) // 4096) * 4096
    arithmetic = {'stride_bytes': stride, 'raw_bytes': raw, 'payload_bytes': raw,
                  'r10f_header_bytes': 128, 'content_bytes': content, 'dma_bytes': dma,
                  'tail_pad': dma - content, 'mwr_packets': dma // 128,
                  'ddr_read_bursts': dma // 4096, 'host_hdr_bytes': 128,
                  'host_stride': host_stride, 'host_total_alloc': host_stride + 4096}
    for key, value in arithmetic.items():
        check(name + ':arithmetic:' + key, value, ds[key])
    check(name + ':artifact-sha', sha(RUN / ds['path']), ds['sha256'])
    check(name + ':artifact-dma-length', len(blob), dma)
    pixels = ds['pixel_group']
    group = bytes([p // 4 for p in pixels] + [sum((p % 4) << (2 * i) for i, p in enumerate(pixels))])
    check(name + ':packed-group', group.hex(), ds['packed_group_hex'])
    check(name + ':all-payload-groups', blob[128:content] == group * (width * height // 4), True)
    effective_crc = crc(blob[128:content])
    check(name + ':raw-crc-independent', effective_crc, ds['raw_crc32'])
    check(name + ':payload-crc-independent', effective_crc, ds['payload_crc32'])
    hdr = bytearray(blob[:128]); stored = number(hdr, 88); hdr[88:92] = bytes(4)
    check(name + ':header-crc-independent', crc(hdr), stored)
    check(name + ':header-crc-vector', stored, ds['header_crc32'])
    check(name + ':tail-all-zero', any(blob[content:]), False)
    check(name + ':tail-excluded-from-crc', crc(blob[128:]) == effective_crc, False)
    check(name + ':synthetic-identity', 'synthetic diagnostic ONLY' in ds['identity'], True)
    for vector in vectors['frame_mutations']:
        mutated = mutate(blob, vector['operation'])
        check(name + ':oracle:' + vector['id'], strict_oracle(mutated, ds), vector['expected'])
        check(name + ':candidate:' + vector['id'], candidate['strict'](mutated, ds), vector['expected'])
    for label, off, size, value in extra_mutations:
        b = bytearray(blob); b[off:off+size] = value.to_bytes(size, 'little'); recalc_header(b)
        check(name + ':oracle-extra:' + label, strict_oracle(b, ds), False)
        check(name + ':candidate-extra:' + label, candidate['strict'](b, ds), False)
    for label, b in [('header-only', blob[:128]), ('payload-truncated', blob[:content-1]),
                     ('extra-zero-page', blob + bytes(4096)), ('one-extra-zero', blob + b'\x00')]:
        check(name + ':oracle-extra:' + label, strict_oracle(b, ds), False)
        check(name + ':candidate-extra:' + label, candidate['strict'](b, ds), False)
    # A synthetic host slot demonstrates the independent prefix and transport layers.
    host = bytearray(host_stride + 4096)
    struct.pack_into('<IIII', host, 0, 1, dma, 1, 0)
    host[128:128+dma] = blob
    check(name + ':host-prefix-zero', any(host[16:128]), False)
    check(name + ':host-frame-start', bytes(host[128:132]), b'R10F')
    check(name + ':host-payload-start', host[256:261].hex(), group.hex())
    check(name + ':host-slot-end-padding', host_stride - (128 + dma), 3968)
    check(name + ':host-mailbox-db-offset', host_stride + 32, ds['host_stride'] + 32)
    derived.append({'dataset': name, **arithmetic, 'host_payload_start': 256,
                    'host_payload_end': 256 + raw, 'host_dma_end': 128 + dma,
                    'host_mailbox_db': host_stride + 32, 'raw_crc32': effective_crc,
                    'header_crc32': stored})

# Match the pinned RTL's bit assignments, excluding reserved bit4 and self-clearing bit1.
for vector in vectors['control']:
    stable = sum(vector['written'] & (1 << bit) for bit in (0, 2, 3, 5, 6, 7, 8))
    check(vector['id'] + ':readback', stable, vector['readback'])
    check(vector['id'] + ':arm-result', (stable & vector['required_mask']) == vector['required_mask'], vector['expected'])
check('new-A-mask', registers['required_rk_arm_bits'], (1 << 0) | (1 << 5) | (1 << 6))
check('new-B-mask', registers['required_rk_arm_bits_b'], registers['required_rk_arm_bits'] | (1 << 8))
check('legacy-mask', registers['legacy_driver_arm_bits'], 0x71)
check('host-prefix-layer-table', registers['host_abi']['host_prefix_padding_bytes'], 128 - 16)
check('host-abi-transport-offset', registers['host_abi']['hdr_bytes_transport_offset'], 128)
check('host-abi-R10F-header', registers['host_abi']['r10f_header_bytes'], 128)
check('extension-no-register-overlap', len({r['offset'] for r in registers['registers'] + registers['extension_registers']}), len(registers['registers']) + len(registers['extension_registers']))
ext = {entry['name']: entry for entry in registers['extension_registers']}
check('extension-magic-little-endian', ext['EXT_MAGIC']['reset'], int.from_bytes(b'RKA1', 'little'))
check('extension-major-minor', ext['EXT_VERSION']['reset'], 1 << 16)
for name in ['DMA_CAP_BYTES', 'SESSION_ID', 'TX_CMD', 'ACK_SEQ', 'ACK_SESSION', 'TX_STATUS']:
    check(name + ':reset-zero', ext[name]['reset'], 0)

boundaries = []
for vector in vectors['dma_boundaries']:
    addresses = list(range(vector['base'], vector['base'] + vector['bytes'], 128))
    crossings = [i for i, address in enumerate(addresses) if address // 4096 != (address + 127) // 4096]
    check(vector['id'] + ':128B-and-4K', vector['base'] % 128 == 0 and not crossings, vector['expected'])
    if 'first_crossing_packet_index' in vector:
        check(vector['id'] + ':first-crossing-index', crossings[0], vector['first_crossing_packet_index'])
        check(vector['id'] + ':first-crossing-address', addresses[crossings[0]], vector['first_crossing_address'])
        check(vector['id'] + ':every-page-crossing', len(crossings), 633)
    boundaries.append({'id': vector['id'], 'packet_count': len(addresses), 'crossing_count': len(crossings),
                       'first_crossing_index': crossings[0] if crossings else None})
for vector in vectors['authorization_cases']:
    check(vector['id'] + ':authorization', bool(vector['authorized'] and vector['capacity'] >= 2592768), vector['expected'])

file_count_after = verify_manifest('after')
check('same-frozen-file-count', file_count_after, file_count)
failures = [item for item in RESULTS if not item['pass']]
output = {'scope': 'T03 offline contract/fixtures only; no RTL/driver/hardware execution',
          'manifest_sha256': sha(MANIFEST), 'frozen_file_count': file_count,
          'python': platform.python_version(), 'checks': len(RESULTS), 'failures': failures,
          'derived': derived, 'boundaries': boundaries, 'results': RESULTS,
          'elapsed_seconds': round(time.time() - start, 3),
          'marker': 'FUNCTIONAL_INDEPENDENT_OK' if not failures else 'FUNCTIONAL_INDEPENDENT_FAIL'}
(OUT / 'independent-result.json').write_text(json.dumps(output, indent=2, default=lambda value: value.hex() if isinstance(value, bytes) else str(value)) + '\n', encoding='utf-8')
print(json.dumps({key: output[key] for key in ('checks', 'frozen_file_count', 'failures', 'elapsed_seconds', 'marker')}))
raise SystemExit(bool(failures))
