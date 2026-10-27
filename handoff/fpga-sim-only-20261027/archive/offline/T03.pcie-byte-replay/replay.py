#!/usr/bin/env python3
"""OFFLINE ONLY: reconstruct the existing A1U1 header from exact zlib + metadata.

This does not implement a PCIe serializer or assert physical DMA tail contents.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys
import zlib

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[4]
REF = ROOT / 'handoff/rk-a1u1-b18-20261026'
sys.path.insert(0, str(REF / 'reference'))
import a1_ref
import a1_inflate_strict

HEADER = struct.Struct('<4sBBHIHHIIIIIII')
def sha(data): return hashlib.sha256(data).hexdigest()
def crc(data): return zlib.crc32(data) & 0xffffffff
def align(n): return (n + 4095) // 4096 * 4096
def require(ok, why):
    if not ok: raise ValueError(why)

def context(meta, camera, session):
    require(camera in (0, 1) and session > 0, 'invalid expected context')
    require(meta['camera_id'] == camera, 'camera sidecar mismatch')
    require(meta['session'] == session, 'session sidecar mismatch')
    require(meta['offline_header_reconstruction'] is True, 'offline label required')
    require(meta['identity_transport_status'] == 'sidecar_only_not_on_A1U1_wire', 'identity label')
    require(meta['prep'] == (meta['flags'] & 1) and meta['pred'] == ((meta['flags'] >> 1) & 1), 'prep/pred sidecar mismatch')
    require(meta['mode'] == 0, 'this replay requires packed RAW10 mode')

def decode_record(data):
    require(len(data) >= 44, 'truncated header')
    magic, ver, flags, hlen, fid, w, h, rn, xn, sn, rc, xc, sc, hc = HEADER.unpack_from(data)
    require(magic == b'A1U1' and ver == 1 and hlen == 44, 'unsupported header')
    require(flags & ~3 == 0, 'reserved flags')
    a1_ref.validate_geometry(w, h, flags & 1, flags >> 1, rn)
    require(rn <= 64 * 1024 * 1024 and xn == rn, 'raw/xform length mismatch')
    require(0 < sn <= rn + 4096 and len(data) == 44 + sn, 'record length/trailing bytes')
    require(crc(data[:40]) == hc, 'header CRC')
    stream = data[44:]
    require(crc(stream) == sc, 'stream CRC')
    obj = zlib.decompressobj()
    xf = obj.decompress(stream, xn + 1)
    require(obj.eof and not obj.unused_data and not obj.unconsumed_tail, 'strict zlib termination/extra stream')
    require(len(xf) == xn, 'inflated length mismatch')
    # Independent DEFLATE parser additionally rejects invalid block trees/distances.
    strict_xf, stats = a1_inflate_strict.inflate(stream, expected_len=xn)
    require(strict_xf == xf, 'inflate oracle disagreement')
    require(crc(xf) == xc, 'xform CRC')
    raw = a1_ref.inverse_frame(xf, w, h, flags & 1, flags >> 1)
    require(len(raw) == rn and crc(raw) == rc, 'raw CRC/length')
    return raw, dict(frame_id=fid, width=w, height=h, flags=flags, raw_bytes=rn,
                     xform_bytes=xn, zlib_bytes=sn, a1u1_bytes=len(data),
                     current_dma_bytes=align(sn), proposed_dma_bytes=align(len(data)),
                     raw_crc32=f'{rc:08x}', xform_crc32=f'{xc:08x}',
                     stream_crc32=f'{sc:08x}', header_crc32=f'{hc:08x}',
                     raw_sha256=sha(raw), strict_stats=stats)

def make_record(stream, meta):
    h = HEADER.pack(b'A1U1', 1, meta['flags'], 44, meta['frame_id'],
        meta['width'], meta['height'], meta['raw_bytes'], meta['xform_bytes'],
        len(stream), int(meta['raw_crc32'], 16), int(meta['xform_crc32'], 16), crc(stream), 0)
    return h[:40] + struct.pack('<I', crc(h[:40])) + stream

def reconstruct(stream, meta, out, camera, session, capacity):
    context(meta, camera, session)
    require(sha(stream) == meta['slot_sha256'], 'slot SHA mismatch')
    record = make_record(stream, meta)
    raw, info = decode_record(record)
    require(info['raw_sha256'] == meta['raw_sha256'], 'raw SHA mismatch')
    require(align(len(record)) <= capacity, 'capacity insufficient for proposed header layout')
    out = Path(out); out.mkdir(parents=True, exist_ok=False)
    (out / 'current-slot.bin').write_bytes(stream)
    (out / 'current-dma.bin').write_bytes(stream + bytes(align(len(stream)) - len(stream)))
    (out / 'reconstructed.a1u1').write_bytes(record)
    (out / 'proposed-a1u1-dma.bin').write_bytes(record + bytes(align(len(record)) - len(record)))
    (out / 'expected.raw10').write_bytes(raw)
    side = dict(meta, **{k:v for k,v in info.items() if k not in meta}, capacity_bytes=capacity,
        current_dma_tail_model='offline_zero_fill_beyond_exact_slot_not_proven_in_hardware',
        proposed_layout_status='offline_reference_not_connected_to_PCIe')
    (out / 'replay-metadata.json').write_text(json.dumps(side, indent=2)+'\n', encoding='utf-8')
    return info

def verify_case(path, camera, session, capacity):
    p = Path(path); meta = json.loads((p / 'replay-metadata.json').read_text(encoding='utf-8'))
    context(meta, camera, session)
    stream = (p / 'current-slot.bin').read_bytes(); current = (p / 'current-dma.bin').read_bytes()
    rec = (p / 'reconstructed.a1u1').read_bytes(); proposed = (p / 'proposed-a1u1-dma.bin').read_bytes()
    require(len(current) == align(len(stream)) and len(current) <= capacity, 'current DMA length/capacity')
    require(current[:len(stream)] == stream and not any(current[len(stream):]), 'current DMA content/nonzero tail')
    require(sha(stream) == meta['slot_sha256'] and rec[44:] == stream, 'slot/record mismatch')
    raw, info = decode_record(rec)
    require(len(proposed) == align(len(rec)) and len(proposed) <= capacity, 'proposed DMA length/capacity')
    require(proposed[:len(rec)] == rec and not any(proposed[len(rec):]), 'proposed DMA content/nonzero tail')
    require(raw == (p / 'expected.raw10').read_bytes(), 'raw byte oracle mismatch')
    for key in ['frame_id','width','height','flags','raw_bytes','xform_bytes','zlib_bytes','a1u1_bytes',
                'current_dma_bytes','proposed_dma_bytes','raw_crc32','xform_crc32','stream_crc32','header_crc32','raw_sha256']:
        require(meta[key] == info[key], 'metadata mismatch: '+key)
    return info

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action', choices=['reconstruct','verify'])
    ap.add_argument('--case', type=Path, required=True)
    ap.add_argument('--slot', type=Path); ap.add_argument('--metadata', type=Path)
    ap.add_argument('--camera', type=int, required=True); ap.add_argument('--session', type=int, required=True)
    ap.add_argument('--capacity', type=int, required=True)
    a = ap.parse_args()
    try:
        if a.action == 'verify': result = verify_case(a.case, a.camera, a.session, a.capacity)
        else: result = reconstruct(a.slot.read_bytes(), json.loads(a.metadata.read_text(encoding='utf-8')), a.case, a.camera, a.session, a.capacity)
        print(json.dumps(dict(status='pass', offline_only=True, **result))); return 0
    except (ValueError, OSError, KeyError, struct.error, zlib.error, a1_inflate_strict.A1Error) as e:
        print(json.dumps(dict(status='reject', error=str(e)))); return 1
if __name__ == '__main__': raise SystemExit(main())
