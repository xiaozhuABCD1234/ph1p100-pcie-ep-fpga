"""Freeze a full-color candidate from215134, excluding unfinished RAW capacity work."""
from pathlib import Path
import datetime,hashlib,json
from rgb565_support import once

ROOT=Path(__file__).resolve().parents[2]
BASE=Path('D:/TD/work/csi2/prj/camera_rgb332_reference_20261013_215134')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(BASE/'camera_ddr_display.bit')=='5c8d3081ae5a56e8cd9c35de134ca75c7fece5f5379d33587b727d73a9ea35cd'
manifest=json.loads((BASE/'input_manifest.json').read_bytes());assert len(manifest)==202
for rel,digest in manifest.items():
    f=(BASE/rel).resolve();assert f.is_relative_to(BASE.resolve()) and sha(f)==digest,rel
OUT=BASE.parent/('camera_rgb565_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
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
        if raw!=new:save(rel,new,'Relocate unchanged ROM contents')
for folder,names in [('cam',['bayer565_capture.v']),('mem',['rgb565_frame_pack_guarded.v','rgb565_display_read.v','rgb565_display_pixels.v','camera_rgb565_display_guarded.v'])]:
    for name in names:save(name,(ROOT/'fpga/csi2/src'/folder/name).read_bytes(),'RGB565 preview pipeline; independently simulated')
s=(BASE/'f9p_camera_display_core.v').read_bytes().decode()
s=once(s,'output wire[7:0] cap_data','output wire[15:0] cap_data')
s=once(s,'bayer332_capture #(','bayer565_capture #(')
s=once(s,'.out_sof(cap_sof),.out_valid(cap_valid),.out_last(cap_last),.out_data(cap_data));',
       '''.out_sof(cap_sof),.out_valid(cap_valid),.out_last(cap_last),.out_data(cap_data),
        .frame_end(cap_frame_end),.frame_good(cap_frame_good),.frame_abort(cap_frame_abort),
        .stat_a(raw_a_sum),.stat_b(raw_b_sum),.stat_c(raw_c_sum),.stat_d(raw_d_sum),
        .stat_count(raw_sample_count),.stat_sequence(raw_stat_sequence),.stat_valid(raw_stat_valid));''')
anchor='    bayer565_capture #('
s=once(s,anchor,'''    // Raw10 sampled Bayer-position sums, before RGB565 quantization.
    (* MARK_DEBUG="true" *) wire[31:0] raw_a_sum,raw_b_sum,raw_c_sum,raw_d_sum;
    (* MARK_DEBUG="true" *) wire[31:0] raw_sample_count,raw_stat_sequence;
    (* MARK_DEBUG="true" *) wire raw_stat_valid;
'''+anchor)
s=s.replace('// RGB332 camera data; no recovery from previously averaged Gray8.','// RAW10 to RGB565 camera preview through external DDR, always color.')
s=s.replace('    // 摄像头实时预览：A 口 4K 流 → 抽降到 960x540 灰度 → 片内 ERAM(224 块) → 放大 2 倍显示',
            '    // A:4K RAW10 ->960x540 RGB565 -> external DDR ->2x HDMI preview.')
save('f9p_camera_display_core.v',s.encode(),'16-bit capture interface and raw Bayer statistics; sensor/PHY/HDMI unchanged')
for name in ['camera_ddr_display_top.v','ddrmc_display_top.v']:
    s=(BASE/name).read_bytes().decode();s=once(s,'[7:0] cap_data','[15:0] cap_data')
    if name=='ddrmc_display_top.v':s=once(s,'camera_ddr_display_guarded #(','camera_rgb565_display_guarded #(')
    save(name,s.encode(),'Carry16-bit pixels without truncation')
s=(BASE/'build_reference.tcl').read_bytes().decode()
for old,new in [('gray_frame_pack_guarded.v','rgb565_frame_pack_guarded.v'),('camera_ddr_display_guarded.v','camera_rgb565_display_guarded.v'),('bayer332_capture.v','bayer565_capture.v'),('rgb332_display_pixels.v','rgb565_display_pixels.v'),('ddr_display_read.v','rgb565_display_read.v')]:
    s=once(s,'add_files ./'+old,'add_files ./'+new)
s=once(s,'add_files ./rgb332_reference_overlay.v\n','')
save('build_rgb565.tcl',s.replace('RGB332_REFERENCE','RGB565').encode(),'Explicit synthesis entry')
save('route_rgb565.tcl',(BASE/'route_reference.tcl').read_bytes().replace(b'RGB332_REFERENCE',b'RGB565'),'Same native physical flow; no bit generation')
for kind in ['inspect','bitgen']:
    save(kind+'_rgb565.tcl',('set display_checkpoint ./csi_checked_debug_pr.db\nsource ./'+kind+'_rgb332_body.tcl\n').encode(),'Use only selected new routed checkpoint')
save('audit_hdmi_rgb565.tcl',(BASE/'audit_hdmi_reference.tcl').read_bytes(),'Read-only native HDMI audit')
save('export_rgb565_debug.tcl',b'''if {[catch {
 import_device ph1_100p.db -package PH1P100SBG484 -speed 3
 open_project ./camera_ddr_display.al
 import_db ./csi_checked_debug_pr.db
 export_cwc ./camera_ddr_display.cwc
 close_project
 puts "RGB565_CWC_EXPORTED"
} msg]} {puts stderr "RGB565_CWC_ERROR: $msg";exit 1}
exit 0
''','Export matching debug description, no cable connection/download')
for rel in ['prepare_rgb565.py','rgb565_support.py']:
    save('frozen_'+rel,(ROOT/'tools/td'/rel).read_bytes(),'Derivation identity')
for rel in ['ddr_frame_store.v','capture_async_fifo.v','timing.sdc','board.adc','camera/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v','camera/uisrc/01_rtl/raw10_display60_clocks.v','camera/uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v']:
    assert (OUT/rel).read_bytes()==(BASE/rel).read_bytes(),rel
inputs={f.relative_to(OUT).as_posix():sha(f) for f in sorted(OUT.rglob('*')) if f.is_file()}
(OUT/'input_manifest.json').write_bytes((json.dumps(inputs,indent=2)+'\n').encode())
(OUT/'rgb565_overlay.json').write_bytes((json.dumps({'base':str(BASE),'base_bit_sha256':sha(BASE/'camera_ddr_display.bit'),'base_input_count':202,'input_count':len(inputs),'changes':changes,
    'format':'RGB565 little-endian16codes/256bits','preview':[960,540],'display':[1920,1080,60],'camera_fps':30,'payload_bytes':1036800,'frame_words':32401,'three_slots_bytes':3110496,'reference_rows':0,'gray_alternation':False,'bayer_phase':0,'white_balance':'No unmeasured gains; raw four-position statistics exported for measured calibration','hardware_verified':False,'limits':'Preview demosaic by2x2 cell then decimation, not full-resolution ISP. No gamma, lens correction or calibrated color matrix. Sparkles unresolved. Serial HDMI electrical-rate qualification unchanged.'},indent=2)+'\n').encode())
print(OUT)
