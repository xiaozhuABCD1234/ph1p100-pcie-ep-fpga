"""Prepare a fresh isolated TD display probe; never change/download the camera project."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import shutil

p=argparse.ArgumentParser()
p.add_argument('--mode',type=int,choices=[0,1,2],required=True)
p.add_argument('--serializer',choices=['fabric','native_x5'],default='fabric')
a=p.parse_args()
names=['1080p30','1080p60','720p60']
name=names[a.mode]+('_native_x5' if a.serializer=='native_x5' else '')
repo=Path(__file__).resolve().parents[2]
live=Path(r'D:\TD\work\csi2\prj\camera_peer')
out=live/'_diagnostics'/('hdmi_'+name+'_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
out.mkdir(parents=True,exist_ok=False)
sources=[repo/'fpga/csi2/diagnostics/hdmi/hdmi_diagnostic_top.v',
         repo/'fpga/csi2/diagnostics/hdmi/hdmi_diagnostic_clocks.v',
         live/'uisrc/03_ip/raw10_clocks/RTL/ph1p_phy_pll_wrapper_raw10_clocks.v',
         live/'uisrc/03_ip/vtc/uivtc.v']
sources += [live/'uisrc/03_ip/alip/ui_HDMI_TX'/f for f in
            ['ui_HDMI_TX.v','lane_lvds_10_1.v','hdmi_phy_warpper.v','hdmi_tx_controller_wrapper.enc.v']]
if a.serializer=='native_x5':
    sources=[x for x in sources if x.name!='lane_lvds_10_1.v']
    sources += [repo/'fpga/csi2/diagnostics/hdmi'/x for x in ['lane_lvds_native_x5.v','lane_lvds_native_adapter.v']]
manifest={}
for source in sources:
    assert source.is_file(),source
    dest=out/source.name
    assert not dest.exists()
    shutil.copyfile(source,dest)
    manifest[source.name]={'source':str(source),'sha256':hashlib.sha256(source.read_bytes()).hexdigest()}
(out/'manifest.json').write_text(json.dumps({'mode':names[a.mode],'serializer':a.serializer,'inputs':manifest},indent=2)+'\n',encoding='utf-8')
(out/'hdmi_diag_build_top.v').write_text('''module hdmi_diag_build_top(input sys_clk50m,output O_hdmi_clk_p,output [2:0] O_hdmi_tx_p);
hdmi_diagnostic_top #(.DISPLAY_MODE(MODE_VALUE)) u_diagnostic
(.sys_clk50m(sys_clk50m),.O_hdmi_clk_p(O_hdmi_clk_p),.O_hdmi_tx_p(O_hdmi_tx_p));
endmodule
'''.replace('MODE_VALUE',str(a.mode)),encoding='ascii')
(out/'diagnostic.adc').write_text('''set_pin_assignment { sys_clk50m } { LOCATION = H4; IOSTANDARD = SSTL135; PULLTYPE = PULLUP; }
set_pin_assignment { O_hdmi_tx_p[0] } { LOCATION = B15; IOSTANDARD = LVDS33_E; }
set_pin_assignment { O_hdmi_tx_p[1] } { LOCATION = B21; IOSTANDARD = LVDS33_E; }
set_pin_assignment { O_hdmi_tx_p[2] } { LOCATION = C22; IOSTANDARD = LVDS33_E; }
set_pin_assignment { O_hdmi_clk_p } { LOCATION = C18; IOSTANDARD = LVDS33_E; }
''',encoding='ascii')
(out/'diagnostic.sdc').write_text('''create_clock -name sys_clk50m -period 20.000 -waveform {0.000 10.000} [get_ports sys_clk50m]
derive_clocks
''',encoding='ascii')
tcl='''if {[catch {
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
create_project hdmi_diagnostic ./ -family ph1 -device PH1P100SBG484 -speed -3
FILES
add_files ./diagnostic.adc
add_files ./diagnostic.sdc
top_module hdmi_diag_build_top
launch_runs syn_1
wait_run syn_1 -quiet
launch_runs -step route phy_1
wait_run phy_1 -quiet
open_run phy_1
update_timing -mode final
report_timing_summary -file ./diagnostic_timing.rpt
report_abnormal_timing_target -file ./diagnostic_abnormal.rpt
report_area -file ./diagnostic.area
close_project
puts "HDMI_DIAGNOSTIC_ROUTE_RETURNED_CHECK_REPORTS"
} msg]} { puts stderr "HDMI_DIAGNOSTIC_ERROR: $msg"; exit 1 }
exit 0
'''.replace('FILES','\n'.join('add_files ./'+x.name for x in sources)+'\nadd_files ./hdmi_diag_build_top.v')
(out/'build.tcl').write_text(tcl,encoding='ascii')
print(out)
