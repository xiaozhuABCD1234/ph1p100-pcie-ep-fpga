#!/usr/bin/env python3
"""生成非压缩帧/元数据接口合同的共享向量与证据。

不访问硬件、不调用 TD、不修改生产 RTL。产物：
  * 64x48 与 8x4 合成 RAW10 帧（packed 与 u16le 各一份），
  * expected.json（帧头字段表、关键像素、CRC、stride），
  * hexdump.txt（8x4 帧头 + 载荷前若干字节，供 FPGA/RK 手工逐字节对照），
  * result.json。
"""

from __future__ import annotations

import datetime
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import frame_contract as F  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "parallel"))
import meta  # noqa: E402
OUT = REPO / "parallel" / "evidence" / "frame_contract_20261015"


def hexdump(data: bytes, base: int = 0, limit: int = 0) -> str:
    lines = []
    view = data if limit <= 0 else data[:limit]
    for i in range(0, len(view), 16):
        chunk = view[i:i + 16]
        hexs = " ".join("%02X" % b for b in chunk)
        txt = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append("%04X  %-47s  %s" % (base + i, hexs, txt))
    return "\n".join(lines)


def emit(out: Path, width: int, height: int, phase: str = "RGGB"):
    px = F.synthetic_pixels(width, height)
    files = []
    for name, fmt in (("packed", F.FMT_RAW10_PACKED), ("u16le", F.FMT_RAW10_U16LE)):
        blob = F.build_frame(px, width, height, format_id=fmt, phase=phase)
        f = out / ("frame_%dx%d_%s.bin" % (width, height, name))
        f.write_bytes(blob)
        info = F.parse_frame(blob)
        ok = info["crc_ok"] and info["payload_ok"] and info["pixels"] == px
        files.append({"file": f.name, "bytes": len(blob), "verify_ok": ok,
                      "raw_crc32": info["header"]["raw_crc32"],
                      "payload_crc32": info["header"]["payload_crc32"],
                      "header_crc32": info["header"]["header_crc32"]})
    return files


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    st = F._selftest(verbose=False)
    selftest_ok = all(x[1] for x in st)

    big = emit(OUT, 64, 48)
    small = emit(OUT, 8, 4)

    # 8x4 packed 帧头 + 载荷前 16 字节 hexdump
    small_packed = OUT / "frame_8x4_packed.bin"
    blob = small_packed.read_bytes()
    (OUT / "hexdump.txt").write_text(
        "8x4 RAW10 packed frame\n"
        "== header (128B) ==\n" + hexdump(blob, 0, 128) +
        "\n== payload (first 16 bytes) ==\n" + hexdump(blob[128:], 0x80, 16) + "\n",
        encoding="utf-8")

    # 关键像素与字段
    px = F.synthetic_pixels(8, 4)
    key_pixels = {
        "corner_00": px[0], "corner_07": px[7],
        "corner_30": px[3 * 8], "corner_37": px[8 * 4 - 1],
        "first_row": px[0:8], "row1": px[8:16],
    }
    field_table = [{"offset": "0x%02X" % off, "name": n, "fmt": fmt} for off, n, fmt in F.HEADER_FIELDS]

    result = {
        "date": datetime.date.today().isoformat(),
        "evidence_meta": meta.evidence_meta(__file__),
        "kind": "frame-metadata-contract-vectors",
        "scope_boundary": "non-compressed frame/metadata/transport only; compression codec fields reserved for F2",
        "selftest": [{"name": n, "ok": bool(ok)} for n, ok in st],
        "vectors_big": big, "vectors_small": small,
        "header_field_table": field_table,
        "stride_64_packed": F.stride_for(F.FMT_RAW10_PACKED, 64),
        "stride_64_u16": F.stride_for(F.FMT_RAW10_U16LE, 64),
        "key_pixels_8x4": key_pixels,
        "crc32_check_123456789": hex(F.crc32_ieee(b"123456789")),
    }
    ok = selftest_ok and all(v["verify_ok"] for v in big + small)
    result["result"] = "pass" if ok else "fail"
    (OUT / "result.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")

    print("FRAME_CONTRACT_DIR", OUT)
    print("FRAME_CONTRACT_RUN", "PASS" if ok else "FAIL",
          "files=%d" % (len(big) + len(small)))
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
