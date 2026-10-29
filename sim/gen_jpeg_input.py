#!/usr/bin/env python3
"""生成 tb_jpeg_full 的确定性输入：1920x1088 灰度 raw（无外部依赖）。

用法： python3 sim/gen_jpeg_input.py [输出路径，默认 /tmp/jf_full_in.raw]
"""
import sys

W, H = 1920, 1088
out = sys.argv[1] if len(sys.argv) > 1 else '/tmp/jf_full_in.raw'
seed = 0x12345
buf = bytearray(W * H)
i = 0
for y in range(H):
    for x in range(W):
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        noise = (seed >> 16) & 0x3F
        buf[i] = (x * 3 + y * 5 + ((x * x + y * y) >> 6) + noise) & 0xFF
        i += 1
with open(out, 'wb') as f:
    f.write(buf)
print(f'wrote {out} ({len(buf)} bytes, {W}x{H} gradient+noise)')
