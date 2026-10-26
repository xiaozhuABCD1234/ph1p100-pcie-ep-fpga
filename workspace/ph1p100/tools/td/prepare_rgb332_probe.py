"""Derive a byte-compatible RGB332 camera diagnostic from frozen222159."""
from pathlib import Path
import datetime,hashlib,json
repo=Path(__file__).resolve().parents[2]
base=Path('D:/TD/work/csi2/prj/camera_csi_integrity_20261012_222159')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(base/'camera_ddr_display.bit')=='379bd654d0730f22f5fe775cb8ee26fe7fb7ab2daba3c7adaddc3a1a45cf5f85'
manifest=json.loads((base/'input_manifest.json').read_bytes());assert len(manifest)==184
for name,digest in manifest.items():
 p=(base/name).resolve();assert p.is_relative_to(base.resolve()) and sha(p)==digest,name
out=base.parent/('camera_rgb332_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'));assert not out.exists();out.mkdir()
changes={}
for name in manifest:
 dest=out/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes((base/name).read_bytes())
def save(name,data,why):
 p=out/name;before=sha(p) if p.exists() else None;p.write_bytes(data)
 changes[name]={'before_sha256':before,'sha256':sha(p),'reason':why}
for name in manifest:
 p=out/name
 if p.suffix=='.v':
  b=p.read_bytes();m=b.replace(base.as_posix().encode(),out.as_posix().encode())
  if b!=m:save(name,m,'Relocate unchanged initialization payload path')
p=out/'f9p_camera_display_core.v';s=p.read_text(encoding='utf-8')
start=s.index('    cam_preview_capture #(');end=s.index('    );',start)+len('    );')
s=s[:start]+'''    // RGB332 camera data; no recovery from previously averaged Gray8.
    bayer332_capture #(.SW(960),.SH(540),.BAYER_PHASE(0)) u_cam_preview(
        .clk(w_a_byte_clk),.rst_n(w_a_rst_out),.in_pixels(w_a_pixel),
        .in_valid(w_a_pixel_valid),.in_line(w_a_in_line),.in_frame(w_a_in_frame),
        .out_sof(cap_sof),.out_valid(cap_valid),.out_last(cap_last),.out_data(cap_data));
    // The historical direct-preview fallback is unused by the DDR HDMI path.
    assign w_cam_rgb=24'd0;assign w_cam_de=1'b0;assign w_cam_alive=1'b0;'''+s[end:]
save(p.name,s.encode(),'Replace Gray8 tap with first2x2 Bayer RGB332 stream; preserve CSI/DDR interfaces')
p=out/'camera_ddr_display_guarded.v';s=p.read_bytes()
old=b'gray_display_pixels #(.SW(SW),.SH(SH)) u_pixels('
assert s.count(old)==1
s=s.replace(old,b'rgb332_display_pixels #(.SW(SW),.SH(SH),.FRAMES_PER_MODE(480)) u_pixels(')
anchor=b'.underflow_frames(underflow_frames),.shown_frames(shown_frames));';assert s.count(anchor)==1
s=s.replace(anchor,b'.underflow_frames(underflow_frames),.shown_frames(shown_frames),.color_mode());')
save(p.name,s,'Decode RGB332 and alternate with gray from the same payload')
for name,folder in [('bayer332_capture.v','cam'),('rgb332_display_pixels.v','mem')]:
 save(name,(repo/'fpga/csi2/src'/folder/name).read_bytes(),'RGB332 diagnostic module')
s=(out/'build.tcl').read_text();anchor='add_files ./f9p_camera_display_core.v';assert s.count(anchor)==1
s=s.replace(anchor,anchor+'\nadd_files ./bayer332_capture.v\nadd_files ./rgb332_display_pixels.v')
s=s[:s.index('launch_runs -step route phy_1')]+'''close_project
puts "RGB332_SYNTHESIS_RETURNED"
} msg]} {puts stderr "RGB332_SYNTHESIS_ERROR: $msg";exit 1}
exit 0
'''
save('build_rgb332.tcl',s.encode('ascii'),'Synthesis only; native physical flow follows separately')
save('route_rgb332.tcl',(base/'route_csi_checked.tcl').read_bytes(),'Preserve physical flow and constraints; no bitgen/download')
for source,target,body in [('inspect_camera_ddr_display.tcl','inspect_rgb332_body.tcl','inspect_rgb332.tcl'),('bitgen_camera_ddr_display.tcl','bitgen_rgb332_body.tcl','bitgen_rgb332.tcl')]:
 save(target,(repo/'tools/td'/source).read_bytes(),'Existing read-only export or fail-closed bitgen body')
 save(body,('set display_checkpoint ./csi_checked_debug_pr.db\nsource ./'+target+'\n').encode(),'Select exact new routed checkpoint')
for name in ['timing.sdc','board.adc','camera/uisrc/01_rtl/raw10_display60_clocks.v','camera/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v','ddr_frame_store.v','ddr_display_read.v','gray_frame_pack_guarded.v']:
 assert (base/name).read_bytes()==(out/name).read_bytes(),name
(out/'rgb332_overlay.json').write_bytes((json.dumps({'base':str(base),'base_bit_sha256':sha(base/'camera_ddr_display.bit'),'changes':changes,'pixel_format':'RGB332','frame_bytes':960*540,'bayer_phase':'RGGB candidate; verify physical red/blue targets','hardware_verified':False,'limits':'No white balance/gamma/denoise. Unresolved HDMI rate qualification. No DDR-ready control change.'},indent=2)+'\n').encode())
inputs={p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file()}
(out/'input_manifest.json').write_bytes((json.dumps(inputs,indent=2)+'\n').encode())
print(out)
