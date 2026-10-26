"""Freeze a measured phase/white-balance candidate derived from140836."""
from pathlib import Path
import datetime
import hashlib
import json

if not __debug__:
    raise RuntimeError('Run this freezer without Python -O; assertions are required gates.')

ROOT = Path(__file__).resolve().parents[2]
BASE = Path('D:/TD/work/csi2/prj/camera_rgb565_20261014_140836')
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(BASE/'camera_ddr_display.bit') == 'e4a3e980c4bb2305c52e6316da4164f8f1588e6bc7819edf0fb68fd8f99bbf7e'
manifest = json.loads((BASE/'input_manifest.json').read_bytes())
assert len(manifest) == 215
for rel, digest in manifest.items():
    p = (BASE/rel).resolve()
    assert p.is_relative_to(BASE.resolve()) and sha(p) == digest, rel
measurement_path = ROOT/'docs/evidence/white_balance_stats_20261014.json'
measurement = json.loads(measurement_path.read_bytes())
for scene in ('white', 'red', 'blue'):
    assert measurement[scene]['sample_count'] == 960*540 and measurement[scene]['stat_valid'] == 1
w = measurement['white']; n = w['sample_count']; black = measurement['nominal_black_level_raw10']
common = w['A']+w['D']-2*n*black
def gain(channel):
    denominator = 2*(w[channel]-n*black)
    assert common > 0 and denominator > 0
    return (common*1024 + denominator//2)//denominator
red, blue = gain('C'), gain('B')
assert (red, blue, black, measurement['phase_candidate']) == (2400, 2062, 50, 3)
assert 0 <= red <= 4096 and 0 <= blue <= 4096 and 0 <= black <= 1023
OUT = BASE.parent/('camera_rgb565_wb_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
assert not OUT.exists(); OUT.mkdir()
changes = {}
for rel in manifest:
    p = OUT/rel; p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes((BASE/rel).read_bytes())
def save(rel, data, reason):
    p = OUT/rel; old = sha(p) if p.exists() else None; p.write_bytes(data)
    changes[rel] = {'before_sha256':old, 'sha256':sha(p), 'reason':reason}
for rel in manifest:
    p = OUT/rel
    if p.suffix == '.v':
        data = p.read_bytes(); relocated = data.replace(BASE.as_posix().encode(), OUT.as_posix().encode())
        if data != relocated: save(rel, relocated, 'Relocate ROM initialization path; contents unchanged')
core = OUT/'f9p_camera_display_core.v'; data = core.read_bytes()
anchor = b'bayer565_capture #(.SW(960),.SH(540),.BAYER_PHASE(0))'
assert data.count(anchor) == 1
selected = f'bayer565_capture #(.SW(960),.SH(540),.BAYER_PHASE(3),.WB_R_GAIN_Q10({red}),.WB_B_GAIN_Q10({blue}),.WB_BLACK_LEVEL({black}))'.encode()
data = data.replace(anchor, selected)
# Route the raw CSI verdict into the sampler and its equally delayed verdict
# downstream. Statistics still consume the original raw verdict inside sampler.
wire_anchor = b'    wire        w_a_pixel_valid, w_b_pixel_valid;'
assert data.count(wire_anchor) == 1
data = data.replace(wire_anchor, wire_anchor+b'\n    wire raw_a_frame_end,raw_a_frame_good,raw_a_frame_abort;')
verdict = b'.O_frame_end(cap_frame_end),.O_frame_good(cap_frame_good),.O_frame_abort(cap_frame_abort),'
assert data.count(verdict) == 1
data = data.replace(verdict,b'.O_frame_end(raw_a_frame_end),.O_frame_good(raw_a_frame_good),.O_frame_abort(raw_a_frame_abort),')
verdict = b'.frame_end(cap_frame_end),.frame_good(cap_frame_good),.frame_abort(cap_frame_abort),'
assert data.count(verdict) == 1
data = data.replace(verdict,b'.frame_end(raw_a_frame_end),.frame_good(raw_a_frame_good),.frame_abort(raw_a_frame_abort),\n        .out_frame_end(cap_frame_end),.out_frame_good(cap_frame_good),.out_frame_abort(cap_frame_abort),')
save(core.name,data,'Measured phase/gains plus matched one-clock display/verdict pipeline')
save('bayer565_capture.v', (ROOT/'fpga/csi2/src/cam/bayer565_capture.v').read_bytes(), 'Parameterized saturating R/B Q10 balance; original stats/control preserved')
save('frozen_tb_bayer565_white_balance.sv', (ROOT/'fpga/csi2/tb/tb_bayer565_white_balance.sv').read_bytes(), 'Independent arithmetic/framing/statistics tests')
save('frozen_tb_bayer565_pipeline.sv', (ROOT/'fpga/csi2/tb/tb_bayer565_pipeline.sv').read_bytes(), 'Cycle alignment and guarded-packer equivalence test')
save('frozen_unpipelined_bayer565_capture.v', (BASE.parent/'camera_rgb565_wb_20261014_233658/bayer565_capture.v').read_bytes(), 'Failed-timing arithmetic reference for one-clock equivalence, test only')
save('frozen_white_balance_stats.json', measurement_path.read_bytes(), 'Actual user measurements and calibration boundaries')
save('frozen_prepare_rgb565_white_balance.py', Path(__file__).read_bytes(), 'Derivation identity')
unchanged = ['rgb565_frame_pack_guarded.v','rgb565_display_read.v','rgb565_display_pixels.v','camera_rgb565_display_guarded.v','camera_ddr_display_top.v','ddrmc_display_top.v','ddr_frame_store.v','capture_async_fifo.v','board.adc','timing.sdc','camera/uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v','camera/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack_checked.v','camera/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v','camera/uisrc/01_rtl/raw10_display60_clocks.v']
for rel in unchanged: assert (OUT/rel).read_bytes() == (BASE/rel).read_bytes(), rel
inputs = {p.relative_to(OUT).as_posix():sha(p) for p in sorted(OUT.rglob('*')) if p.is_file()}
(OUT/'input_manifest.json').write_bytes((json.dumps(inputs,indent=2)+'\n').encode())
(OUT/'white_balance_overlay.json').write_bytes((json.dumps({'base':str(BASE),'input_count':len(inputs),'phase':3,'R_gain_Q10':red,'B_gain_Q10':blue,'black_level':black,'changes':changes,'unchanged_hashes':{rel:sha(OUT/rel) for rel in unchanged},'measurement_sha256':sha(measurement_path),'hardware_verified':False,'limits':measurement['limitations']},indent=2)+'\n').encode())
print(OUT)
