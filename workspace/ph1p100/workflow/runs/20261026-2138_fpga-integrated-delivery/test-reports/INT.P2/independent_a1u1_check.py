#!/usr/bin/env python3
import struct, zlib, hashlib, os, sys, subprocess, tempfile, shutil

ROOT = r"D:\fpga\ph1p100"
SAMPLE = os.path.join(ROOT, "tools", "integrated_delivery", "evidence", "a1u1_sample.a1u1")
DECODER = os.path.join(ROOT, "tools", "integrated_delivery", "a1u1_decode.py")
ALIGNED = 4096
MAGIC = 0x31553141
HEADER_LEN = 44

def crc32(b): return zlib.crc32(b) & 0xFFFFFFFF

def parse(data):
    assert len(data) >= HEADER_LEN
    magic = struct.unpack_from("<I", data, 0)[0]
    version = data[4]; flags = data[5]
    header_len = struct.unpack_from("<H", data, 6)[0]
    frame_id = struct.unpack_from("<I", data, 8)[0]
    width, height = struct.unpack_from("<HH", data, 12)
    raw_len, xform_len, stream_len = struct.unpack_from("<III", data, 16)
    raw_crc, xform_crc, stream_crc = struct.unpack_from("<III", data, 28)
    header_crc = struct.unpack_from("<I", data, 40)[0]
    assert magic == MAGIC, "bad magic"
    assert version == 1, "bad version"
    assert header_len == HEADER_LEN, "bad header_len"
    assert raw_len == width*height*10//8, "raw_len mismatch"
    payload = data[HEADER_LEN:HEADER_LEN+stream_len]
    tail = data[HEADER_LEN+stream_len:]
    assert len(payload) == stream_len
    assert crc32(data[0:40]) == header_crc, "header crc"
    assert crc32(payload) == stream_crc, "stream crc"
    assert all(b == 0 for b in tail), "nonzero tail"
    dec = zlib.decompress(payload)
    assert len(dec) == xform_len, "decompress len != xform_len"
    assert crc32(dec) == xform_crc, "xform crc mismatch"
    assert crc32(dec) == raw_crc, "raw crc mismatch (identity sample)"
    assert len(data) == ALIGNED, "total size not aligned"
    assert (HEADER_LEN + stream_len) <= ALIGNED
    return {"width":width,"height":height,"raw_len":raw_len,"xform_len":xform_len,
            "stream_len":stream_len,"decompressed":len(dec),"tail":len(tail),
            "frame_id":frame_id,"flags":flags}

data = open(SAMPLE,"rb").read()
info = parse(data)
print("INDEPENDENT_A1U1_PASS")
for k,v in info.items(): print(f"  {k}: {v}")

def run_decoder(path):
    r = subprocess.run([sys.executable, DECODER, path, str(ALIGNED)],
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr

tmp = tempfile.mkdtemp()
mutations = []
d = bytearray(data); struct.pack_into("<I", d, 40, 0xDEADBEEF); p=os.path.join(tmp,"bad_header_crc.a1u1"); open(p,"wb").write(d); mutations.append(("bad_header_crc", p))
d = bytearray(data); struct.pack_into("<I", d, 36, 0); p=os.path.join(tmp,"bad_stream_crc.a1u1"); open(p,"wb").write(d); mutations.append(("bad_stream_crc", p))
d = bytearray(data); d[HEADER_LEN+313] = 1; p=os.path.join(tmp,"nonzero_tail.a1u1"); open(p,"wb").write(d); mutations.append(("nonzero_tail", p))
p=os.path.join(tmp,"truncated.a1u1"); open(p,"wb").write(data[:100]); mutations.append(("truncated", p))
d = bytearray(data); struct.pack_into("<I", d, 0, 0); p=os.path.join(tmp,"bad_magic.a1u1"); open(p,"wb").write(d); mutations.append(("bad_magic", p))
d = bytearray(data); struct.pack_into("<I", d, 24, ALIGNED); p=os.path.join(tmp,"big_stream.a1u1"); open(p,"wb").write(d); mutations.append(("big_stream", p))

all_rejected = True
for name, p in mutations:
    rc, out = run_decoder(p)
    rejected = (rc != 0)
    all_rejected = all_rejected and rejected
    print(f"  mutation {name}: rc={rc} rejected={rejected}")

regen = os.path.join(tmp, "regen.a1u1")
subprocess.run([sys.executable, os.path.join(ROOT,"tools","integrated_delivery","gen_a1u1_sample.py"), regen, str(ALIGNED)], check=True)
h1 = hashlib.sha256(open(SAMPLE,"rb").read()).hexdigest()
h2 = hashlib.sha256(open(regen,"rb").read()).hexdigest()
print(f"  reproducibility: original={h1} regen={h2} same={h1==h2}")
assert h1 == h2, "regen hash differs"
assert all_rejected, "some mutation not rejected"
print("INDEPENDENT_A1U1_ALL_MUTATIONS_REJECTED")
shutil.rmtree(tmp)
sys.exit(0)
PYEOF