"""Read both development tracks; write comparison evidence only in this folder.

No RTL, source worktree, IP, constraints or hardware are modified. The codec
worktree is an explicit argument, never inferred from this script's location.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import random
import struct
import subprocess
import sys
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--codec-root', type=Path, required=True)
    args = ap.parse_args()
    peer = args.codec_root.resolve(strict=True)
    sources = {
        'frame': ROOT / 'parallel/frame/frame_contract.py',
        'algorithm': ROOT / 'parallel/algorithms/image_algorithms_ref.py',
        'codec': peer / 'tools/bayer_codec/codec.py',
        'preprocess': peer / 'tools/image_preprocess/reference.py',
        'codec_tests': peer / 'tools/bayer_codec/test_codec.py',
    }
    before = {k: hashlib.sha256(p.read_bytes()).hexdigest() for k, p in sources.items()}
    fc, ia, codec, pre = [module(k, sources[k]) for k in ('frame', 'algorithm', 'codec', 'preprocess')]
    tests = module('codec_comparison_tests', sources['codec_tests'])
    with (OUT / 'codec_tests.log').open('w', encoding='utf-8') as stream:
        result = unittest.TextTestRunner(stream=stream, verbosity=2).run(
            unittest.defaultTestLoader.loadTestsFromModule(tests))
    checks = []
    def check(name, ok):
        checks.append({'name': name, 'ok': bool(ok)})
        if not ok:
            raise AssertionError(name)

    check('codec_unit_tests', result.wasSuccessful() and result.testsRun > 0)
    rng = random.Random(20261016)
    for w, h in ((4, 1), (8, 4), (64, 48)):
        raw = [rng.randrange(1024) for _ in range(w * h)]
        packed = fc.pack_raw10(raw)
        check(f'raw10_bytes_{w}x{h}', codec.pack_raw10(raw) == packed)
        check(f'raw10_samples_{w}x{h}', codec.unpack_raw10(packed) == raw)
        for phase in range(4):
            blob = codec.encode_frame(packed, w, h, phase, 2)
            check(f'bpr1_roundtrip_{w}x{h}_phase{phase}', codec.decode_frame(blob).raw == packed)
            # Inner payload length excludes the 36B BPR1 frame header.
            fields = codec.FRAME_HEADER.unpack_from(blob)
            check(f'bpr1_length_{w}x{h}_phase{phase}', len(blob) == 36 + fields[9])

    for w, h in ((1, 1), (1, 4), (4, 1), (16, 12), (1920, 3)):
        values = [rng.randrange(256) for _ in range(w * h)]
        rows = [values[y*w:(y+1)*w] for y in range(h)]
        check(f'gaussian_{w}x{h}', ia.gaussian3x3(values, w, h) ==
              [v for row in pre.gaussian3x3(rows) for v in row])
        hist = ia.histogram(values)
        check(f'cdf_min_{w}x{h}', ia.cdf_min_lut(hist, len(values)) == list(pre.cdf_min_lut(hist)))
    rgb = [(rng.randrange(1024), rng.randrange(1024), rng.randrange(1024)) for _ in range(1024)]
    rgb8 = [[tuple(v >> 2 for v in pixel) for pixel in rgb]]
    check('gray_after_raw10_truncation', ia.y8_from_rgb(rgb, 10) == pre.rgb8_to_y8(rgb8)[0])
    he1, he2 = ia.HeLut(), pre.PreviousFrameEqualizer()
    for seq, valid in enumerate((True, False, True, True)):
        values = [rng.randrange(256) for _ in range(32)]
        expected = ia.apply_lut(values, he1.begin_frame())
        got = he2.process([values], complete=True, valid=valid)[0]
        check(f'previous_frame_he_{seq}', expected == got)
        he1.end_frame(values, valid)
        check(f'previous_frame_lut_{seq}', he1.lut == list(he2.lut))

    # Probe acceptance gaps without treating them as validated production support.
    blob = fc.build_frame(list(range(32)), 8, 4)
    observations = []
    for name, updates in (
        ('unsupported_codec', {'codec_id': 99}),
        ('bad_frame_flag', {'flags': fc.FLAG_BAD}),
        ('invalid_bayer_phase', {'bayer_phase': 99}),
    ):
        header = fc.unpack_header(blob)
        header.update(updates)
        probe = fc.parse_frame(fc.pack_header(**header) + blob[128:])
        observations.append({'probe': name, 'errors': probe['errors'],
                             'pixels_returned': probe['pixels'] is not None,
                             'crc_ok': probe['crc_ok'],
                             'note': 'Inspection only: callers still need explicit protocol rejection gates.'})
    compressed = codec.encode_frame(bytes(2400), 1920, 1)
    header = fc.unpack_header(fc.build_frame([0] * 1920, 1920, 1))
    padded = compressed + bytes((-len(compressed)) % 32)
    header.update(codec_id=1, payload_bytes=len(padded), payload_crc32=fc.crc32_ieee(padded))
    probe = fc.parse_frame(fc.pack_header(**header) + padded)
    observations.append({'probe': 'compressed_envelope_without_adapter',
                         'errors': probe['errors'], 'crc_ok': probe['crc_ok'],
                         'bpr1_bytes': len(compressed), 'dma_payload_bytes': len(padded),
                         'note': 'codec_id=1 is only a local probe; no enum is frozen.'})
    after = {k: hashlib.sha256(p.read_bytes()).hexdigest() for k, p in sources.items()}
    check('inputs_unchanged_during_comparison', before == after)
    git = subprocess.run(['git', '-C', str(peer), 'rev-parse', 'HEAD'],
                         capture_output=True, text=True, check=True).stdout.strip()
    report = {'result': 'pass', 'codec_root': str(peer), 'codec_head': git,
              'codec_unit_tests': result.testsRun, 'cross_checks': checks,
              'observed_gaps': observations,
              'inputs': {k: {'path': str(p), 'sha256': before[k]} for k, p in sources.items()},
              'hardware_verified': False, 'modelsim_rerun': False}
    (OUT / 'cross_track.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'CROSS_TRACK PASS checks={len(checks)} codec_tests={result.testsRun}')
    for observation in observations:
        print('OBSERVATION', observation['probe'], json.dumps(observation, ensure_ascii=True))


if __name__ == '__main__':
    main()
