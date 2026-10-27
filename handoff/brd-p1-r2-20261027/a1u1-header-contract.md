# A1U1 44-byte header contract (D6 鈥?host/offline tool owns the header)

The DUT stores **only the exact zlib stream** in the slot: 2-byte zlib header
(`78 9c`), the DEFLATE body, and the 4-byte big-endian Adler-32.  The slot does
**not** contain the 44-byte A1U1 header; the DUT does not claim to send one.
The host/RK/packer prepends this header before writing the frame file, and
`stream_len`, `xform_len`, `raw_len` and the three CRCs come from the P4 status
face (or from the received bytes when the status face is unavailable).

Little-endian byte layout (total 44 B):

| offset | size | field | value/source |
|---|---|---|---|
| 0 | u32 | magic | `0x31553141` = file bytes `41 31 55 31` (`A1U1`) |
| 4 | u8 | version | `1` |
| 5 | u8 | flags | `{6'b0, pred, prep}` (bit0 = prep, bit1 = pred) |
| 6 | u16 | header_len | `44` |
| 8 | u32 | frame_id | capture/frame identity (P4 `capture_seq` or host-selected; P2 must fix one) |
| 12 | u16 | width | ROI width (`1920` on board) |
| 14 | u16 | height | ROI height (`1080`) |
| 16 | u32 | raw_len | `W*H*10/8` (`2,592,000` on board) |
| 20 | u32 | xform_len | bytes fed to the A+ core |
| 24 | u32 | stream_len | exact zlib bytes (no padding) |
| 28 | u32 | raw_crc | zlib CRC-32 of the raw packed bytes |
| 32 | u32 | xform_crc | zlib CRC-32 of the transform-domain bytes |
| 36 | u32 | stream_crc | zlib CRC-32 of the zlib stream |
| 40 | u32 | header_crc | zlib CRC-32 of bytes 0..39 |

CRC-32 (zlib): init `0xFFFFFFFF`, reflected polynomial `0xEDB88320`, final XOR
`0xFFFFFFFF`.  The header CRC covers exactly bytes 0..39 (not the payload).

Rules:

- The frame file = 44-byte header + `stream_len` payload bytes.  Do not pad the
  payload to `frame_bytes` in the file; the PCIe transport pads to 4 KiB, the
  file does not.
- `frame_bytes = align_up(stream_len, 4096)` is the transport length; the slot
  tail beyond `stream_len` is zero padding and must not be consumed.
- The slot base word (2048 = byte `0x1_0000`) is the P4 descriptor value; the
  receiver must not infer the slot from a fixed 1 MB/9 MB map.
- **D2 dependency:** the P4 status word (BAR `0x130..0x13C`) is not implemented
  in round1, so a P2 host that needs `stream_len`/CRCs before a transfer must
  either read them from the received frame or wait for the D2 task.  Do not
  claim the host can read P4 status in round1.
- The local G1 TB builds this header itself (`tb_brd_g1_r2.v`), validates the
  header CRC and writes `a1u1_frame.bin`; the DUT is not modified for it.
