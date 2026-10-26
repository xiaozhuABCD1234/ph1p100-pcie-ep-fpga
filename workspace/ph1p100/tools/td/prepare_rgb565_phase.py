"""Single-variable received-Bayer-origin experiment from the frozen RGB565 bit."""
from pathlib import Path
import datetime,hashlib,json
ROOT=Path(__file__).resolve().parents[2]
BASE=Path('D:/TD/work/csi2/prj/camera_rgb565_20261014_140836')
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
assert sha(BASE/'camera_ddr_display.bit')=='e4a3e980c4bb2305c52e6316da4164f8f1588e6bc7819edf0fb68fd8f99bbf7e'
manifest=json.loads((BASE/'input_manifest.json').read_bytes());assert len(manifest)==215
for rel,digest in manifest.items():
    f=(BASE/rel).resolve();assert f.is_relative_to(BASE.resolve()) and sha(f)==digest,rel
OUT=BASE.parent/('camera_rgb565_phase3_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
assert not OUT.exists();OUT.mkdir();changes={}
for rel in manifest:
    f=OUT/rel;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes((BASE/rel).read_bytes())
def save(rel,data,reason):
    f=OUT/rel;old=sha(f) if f.exists() else None;f.write_bytes(data)
    changes[rel]={'before_sha256':old,'sha256':sha(f),'reason':reason}
for rel in manifest:
    f=OUT/rel
    if f.suffix=='.v':
        raw=f.read_bytes();new=raw.replace(BASE.as_posix().encode(),OUT.as_posix().encode())
        if new!=raw:save(rel,new,'Relocate identical ROM initialization contents')
f=OUT/'f9p_camera_display_core.v';raw=f.read_bytes();anchor=b'bayer565_capture #(.SW(960),.SH(540),.BAYER_PHASE(0))'
assert raw.count(anchor)==1
save(f.name,raw.replace(anchor,anchor.replace(b'PHASE(0)',b'PHASE(3)')),'Only functional change: received Bayer phase RGGB0 to GBRG3')
save('frozen_prepare_rgb565_phase.py',Path(__file__).read_bytes(),'Derivation identity')
save('frozen_tb_bayer_origin.sv',(ROOT/'fpga/csi2/tb/tb_bayer_origin.sv').read_bytes(),'Independent fixed-GBRG and zero-dummy fixtures')
unchanged=['bayer565_capture.v','rgb565_frame_pack_guarded.v','rgb565_display_read.v','rgb565_display_pixels.v','camera_rgb565_display_guarded.v','camera_ddr_display_top.v','ddrmc_display_top.v','ddr_frame_store.v','capture_async_fifo.v','board.adc','timing.sdc','camera/uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v','camera/uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack_checked.v','camera/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v','camera/uisrc/01_rtl/raw10_display60_clocks.v']
for name in unchanged:assert (OUT/name).read_bytes()==(BASE/name).read_bytes(),name
inputs={f.relative_to(OUT).as_posix():sha(f) for f in sorted(OUT.rglob('*')) if f.is_file()}
(OUT/'input_manifest.json').write_bytes((json.dumps(inputs,indent=2)+'\n').encode())
(OUT/'phase_overlay.json').write_bytes((json.dumps({'base':str(BASE),'base_bit_sha256':sha(BASE/'camera_ddr_display.bit'),'base_input_count':215,'input_count':len(inputs),'phase_before':0,'phase_after':3,'mapping_after':{'R':'C','G':'(A+D)/2','B':'B'},'changes':changes,'unchanged_hashes':{n:sha(OUT/n) for n in unchanged},'hardware_verified':False,'assumption':'Sony all-pixel RAW image region includes first Dummy; true first DT2B line and observed origin not measured. Linux SGBRG10 is cross-platform support, not board evidence.','limits':'Single-variable phase candidate, not confirmed root cause, WB or sparkle repair. Sensor registers, geometry, DDR and HDMI unchanged. First dummy preview row/margins and later ISP calibration remain separate issues.'},indent=2)+'\n').encode())
print(OUT)
