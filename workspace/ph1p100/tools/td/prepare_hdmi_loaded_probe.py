"""Clone only frozen222159 inputs and overlay a load-preserving HDMI probe."""
from pathlib import Path
import datetime, hashlib, json

repo=Path(__file__).resolve().parents[2]
base=Path('D:/TD/work/csi2/prj/camera_csi_integrity_20261012_222159').resolve()
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(base/'camera_ddr_display.bit')=='379bd654d0730f22f5fe775cb8ee26fe7fb7ab2daba3c7adaddc3a1a45cf5f85'
manifest=json.loads((base/'input_manifest.json').read_text())
assert len(manifest)==184
for name,digest in manifest.items():
    source=(base/name).resolve()
    assert source.is_relative_to(base) and source.is_file()
    assert sha(source)==digest,name
out=base.parent/('camera_hdmi_loaded_probe_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
assert out.parent==base.parent and not out.exists()
out.mkdir()
for name in manifest:
    target=out/name
    target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes((base/name).read_bytes())
changed={}
def save(name,content,reason):
    target=out/name
    before=sha(target) if target.exists() else None
    target.write_bytes(content)
    changed[name]={'before_sha256':before,'sha256':sha(target),'reason':reason}
# Relocate the two original absolute init paths; no other source edits here.
for name in manifest:
    target=out/name
    if target.suffix=='.v':
        content=target.read_bytes()
        relocated=content.replace(base.as_posix().encode(),out.as_posix().encode())
        if content!=relocated:save(name,relocated,'Relocate copied initialization path')
name='f9p_camera_display_core.v'
s=(out/name).read_text(encoding='utf-8')
anchor='    ui_HDMI_TX #(\n'
assert s.count(anchor)==1
probe='''    // Diagnostic mux does not gate CSI, DDR capture, verification or display reads.
    wire[23:0] probe_rgb;
    wire probe_de,probe_vs,probe_hs;
    wire probe_pattern_mode;
    gray_pattern_probe u_gray_probe(
        .clk(w_pclkx1),.rst_n(w_pixel_rst_n),
        .in_rgb(ddr_rgb),.in_de(ddr_de),.in_vs(ddr_vs),.in_hs(ddr_hs),
        .out_rgb(probe_rgb),.out_de(probe_de),.out_vs(probe_vs),.out_hs(probe_hs),
        .pattern_mode(probe_pattern_mode));

'''
s=s.replace(anchor,probe+anchor)
for old,new in [('data (ddr_rgb)','data (probe_rgb)'),('de   (ddr_de)','de   (probe_de)'),
                ('vs   (ddr_vs)','vs   (probe_vs)'),('hs   (ddr_hs)','hs   (probe_hs)')]:
    assert s.count('.I_video_in_'+old)==1
    s=s.replace('.I_video_in_'+old,'.I_video_in_'+new)
save(name,s.encode(),'One common-stage automatic camera/pattern mux immediately before HDMI')
save('gray_pattern_probe.v',(repo/'fpga/csi2/diagnostics/hdmi/gray_pattern_probe.v').read_bytes(),'Diagnostic module')
build=(out/'build.tcl').read_text()
assert build.count('add_files ./f9p_camera_display_core.v')==1
build=build.replace('add_files ./f9p_camera_display_core.v','add_files ./f9p_camera_display_core.v\nadd_files ./gray_pattern_probe.v')
cut=build.index('launch_runs -step route phy_1')
build=build[:cut]+'''close_project
puts "HDMI_LOADED_PROBE_SYNTHESIS_RETURNED"
} msg]} {puts stderr "HDMI_LOADED_PROBE_SYNTHESIS_ERROR: $msg";exit 1}
exit 0
'''
save('build_probe.tcl',build.encode('ascii'),'Synthesis only; native physical flow follows separately')
save('route_probe.tcl',(base/'route_csi_checked.tcl').read_bytes(),'Same TimingHigh physical flow/constraints; no bit generation')
overlay={'base_project':str(base),'base_manifest_sha256':sha(base/'input_manifest.json'),
         'base_bit_sha256':sha(base/'camera_ddr_display.bit'),'changes':changed,
         'rate_scope':'Unchanged148.5/742.5MHz and LVDS33_E; local device-rate qualification conflict remains',
         'hardware_verified':False,'purpose':'Same-bit comparison; camera/DDR remain running in both display modes'}
(out/'probe_overlay.json').write_bytes((json.dumps(overlay,indent=2)+'\n').encode())
inputs={p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file()}
(out/'input_manifest.json').write_bytes((json.dumps(inputs,indent=2)+'\n').encode())
for name in ['timing.sdc','board.adc','camera/uisrc/01_rtl/raw10_display60_clocks.v',
             'camera/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v']:
    assert sha(out/name)==sha(base/name),name
print(out)
