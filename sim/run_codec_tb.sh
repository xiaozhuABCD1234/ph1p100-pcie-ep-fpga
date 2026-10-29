#!/bin/sh
# 一键回归：JPEG 整帧(两帧) + DDR 回读突发 + 压缩流写出器，全部自检。
set -e
cd "$(dirname "$0")/.."

echo "== gen input =="
python3 sim/gen_jpeg_input.py /tmp/jf_full_in.raw

echo "== tb_jpeg_full (two frames) =="
iverilog -g2012 -o /tmp/tb_jpeg_full \
    sim/tb_jpeg_full.v \
    rtl/ep_side/codec/jpeg_frame.v rtl/ep_side/codec/line2block.v \
    rtl/ep_side/codec/jpeg_enc.v rtl/ep_side/codec/dct2d8.v \
    rtl/ep_side/codec/dct1d8.v rtl/ep_side/codec/jpeg_quant_zz.v \
    rtl/ep_side/codec/jpeg_huff_enc.v rtl/ep_side/codec/jpeg_huff_tab.v
vvp /tmp/tb_jpeg_full | tee /tmp/tb_jpeg_full.log
grep -q "通过：两帧都正常结束" /tmp/tb_jpeg_full.log
# 两帧码流应逐字节一致。m_done 比最后一个 pad 字节早一拍，
# 所以帧边界可能差 1 字节：允许 s 或 s+1 的切分。
python3 - <<'EOF'
d = open('/tmp/jf_full.bin', 'rb').read()
n = len(d)
ok = False
for s in (n // 2, n // 2 + 1):
    if n >= 2 * s and d[:s] == d[s:2 * s]:
        ok = True
    if n >= 2 * s + 1 and d[:s] == d[s + 1:2 * s + 1]:
        ok = True
assert ok, f'two frames differ (DC predictor / eof regression), len={n}'
print(f'  two-frame stream OK ({n} bytes)')
EOF

echo "== tb_cstream_reader (burst) =="
iverilog -g2012 -o /tmp/tb_cstream_reader sim/tb_cstream_reader.v rtl/ep_side/codec/cstream_reader.v
vvp /tmp/tb_cstream_reader | tee /tmp/tb_cstream_reader.log
grep -q "PASS" /tmp/tb_cstream_reader.log

echo "== tb_cstream_writer (length/pad) =="
iverilog -g2012 -o /tmp/tb_cstream_writer sim/tb_cstream_writer.v rtl/ep_side/codec/cstream_writer.v
vvp /tmp/tb_cstream_writer | tee /tmp/tb_cstream_writer.log
grep -q "PASS" /tmp/tb_cstream_writer.log

echo "ALL CODEC TB PASSED"
