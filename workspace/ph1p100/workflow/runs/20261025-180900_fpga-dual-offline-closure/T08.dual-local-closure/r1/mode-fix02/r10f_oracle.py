def check_r10f(blob: bytes, camera: int, capture_seq: int, source_fid: int,
              width=8, height=2):
    """Validate an R10F v1 frame: 32 little-endian u32 header words, packed
    payload, zero DMA tail. Returns a small metadata dict; raises
    AssertionError on any mismatch."""
    import struct
    import zlib

    HEADER_BYTES = 128
    raw = width * height * 5 // 4
    stride = width * 5 // 4
    dma = ((HEADER_BYTES + raw + 4095) // 4096) * 4096

    # --- overall length ---
    assert len(blob) == dma, (len(blob), dma)

    # --- header words ---
    hdr = blob[:HEADER_BYTES]
    words = list(struct.unpack("<32I", hdr))

    payload = blob[HEADER_BYTES:HEADER_BYTES + raw]
    tail = blob[HEADER_BYTES + raw:]

    crc_payload = zlib.crc32(payload) & 0xFFFFFFFF

    expected = [0] * 32
    expected[0] = 0x46303152
    expected[1] = 1
    expected[2] = 128 + (camera << 16)
    expected[5] = capture_seq
    expected[6] = 1
    expected[7] = (height << 16) | width
    expected[8] = stride
    expected[10] = 10 << 16
    expected[11] = raw
    expected[12] = raw
    expected[13] = 1
    expected[20] = crc_payload
    expected[21] = crc_payload
    # word22 computed below; sof timestamp / timehz (words 14..19) stay zero.

    header_with_word22_zero = hdr[:88] + b"\x00\x00\x00\x00" + hdr[92:]
    crc_header = zlib.crc32(header_with_word22_zero) & 0xFFFFFFFF
    expected[22] = crc_header

    for i in range(32):
        assert words[i] == expected[i], (i, hex(words[i]), hex(expected[i]))

    # --- payload pattern ---
    pos = 0
    for row in range(height):
        for k in range(stride):
            exp = (camera * 97 + source_fid * 13 + row * 23 + k * 7) & 0xFF
            assert payload[pos] == exp, (row, k, payload[pos], exp)
            pos += 1
    assert pos == raw, (pos, raw)

    # --- zero DMA tail ---
    for j, b in enumerate(tail):
        assert b == 0, ("tail", j, b)

    return {
        "width": width,
        "height": height,
        "stride": stride,
        "raw": raw,
        "dma": dma,
        "camera": camera,
        "capture_seq": capture_seq,
        "source_fid": source_fid,
        "crc_payload": crc_payload,
        "crc_header": crc_header,
        "tail_len": len(tail),
    }
