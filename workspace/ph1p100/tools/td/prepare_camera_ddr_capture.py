"""Derive a camera tap and prepare a fresh, isolated camera-to-DDR candidate."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,shutil,subprocess
p=argparse.ArgumentParser();p.add_argument('--derive-only',action='store_true');p.add_argument('--phy-strategy',choices=['default','TimingHigh'],default='default');a=p.parse_args()
repo=Path(__file__).resolve().parents[2];camera=repo/'fpga/csi2/prj/camera_peer'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
base=json.loads((repo/'docs/evidence/raw10_display60_20261011.json').read_text())
for f,h in {**base['source_hashes'],**base['unchanged_from_6fd42f5']}.items():
    assert sha(camera/f)==h,('Changed proven camera input',f)
dest=repo/'fpga/csi2/src/cam';dest.mkdir(parents=True,exist_ok=True)
preview=(camera/'uisrc/01_rtl/cam_preview.v').read_text(encoding='utf-8')
preview=preview.replace('module cam_preview #(','module cam_preview_capture #(')
# Keep the existing address stage outside ERAM. TD otherwise folds it into
# the RAM and routes the address adder directly to high-fanout chip selects.
# SWUG106 dont_touch preserves the register; logical latency stays unchanged.
preview=preview.replace('reg [AWB-1:0]   r_raddr', '(* dont_touch="true" *) reg [AWB-1:0]   r_raddr')
preview=preview.replace('output wire          O_cam_alive','output wire O_gray_sof,O_gray_valid,O_gray_last,output wire[7:0] O_gray_data,\n    output wire          O_cam_alive')
preview=preview.replace('endmodule','''// Tap the same registered word that is written into the original preview RAM.
assign O_gray_sof=w_frame_rise;
assign O_gray_valid=(|r_we)&&!w_frame_rise;
assign O_gray_data=r_wr_data;
assign O_gray_last=O_gray_valid&&r_we[3]&&(r_wr_addr==RPB*SW-1);
endmodule''')
(dest/'cam_preview_capture.v').write_bytes(preview.encode())
source=(camera/'uisrc/01_rtl/f9p_imx415x2_top.v').read_text(encoding='utf-8')
core=source.replace('module f9p_imx415x2_top (','module f9p_camera_capture_core (\n    output wire cap_clk,cap_sof,cap_valid,cap_last,output wire[7:0] cap_data,')
core=core.replace('cam_preview #(','cam_preview_capture #(')
core=core.replace('.O_cam_alive (w_cam_alive       )','.O_cam_alive (w_cam_alive       ),\n        .O_gray_sof(cap_sof),.O_gray_valid(cap_valid),.O_gray_last(cap_last),.O_gray_data(cap_data)')
core=core.replace('endmodule','assign cap_clk=w_a_byte_clk;\nendmodule')
(dest/'f9p_camera_capture_core.v').write_bytes(core.encode())
ctrl=(repo/'fpga/csi2/src/mem/ddrmc_frame_top.v').read_text()
ctrl=ctrl.replace('module ddrmc_frame_top #(','module ddrmc_capture_top #(').replace('parameter FRAME_WORDS = 16200,','parameter FRAME_BYTES = 518400,')
ctrl=ctrl.replace('    input                       ref_clk','    input cap_clk,cap_sof,cap_valid,cap_last,input[7:0] cap_data,\n    input                       ref_clk')
begin=ctrl.index('ddr_frame_probe #(');end=ctrl.index('reg [25:0] clk_cnt;',begin)
ctrl=ctrl[:begin]+'''wire[31:0] capture_drops;
camera_ddr_capture #(.FRAME_BYTES(FRAME_BYTES)) u_capture(
 .clk(dhi_clk),.cap_clk(cap_clk),.rst_n(ddrphy_rst_n),.ddr_ready(ddrphy_rdy),
 .sof(cap_sof),.pixel_valid(cap_valid),.pixel_last(cap_last),.pixel(cap_data),
 .passed_frames(passed_frames),.failed_frames(failed_frames),.published_frames(published_frames),.protocol_errors(protocol_errors),.capture_drops(capture_drops),
 .paxi_awaddr(paxi_awaddr),.paxi_awvalid(paxi_awvalid),.paxi_awready(paxi_awready),
 .paxi_wdata(paxi_wdata),.paxi_wstrb(paxi_wstrb),.paxi_wvalid(paxi_wvalid),.paxi_wlast(paxi_wlast),.paxi_wready(paxi_wready),
 .paxi_araddr(paxi_araddr),.paxi_arvalid(paxi_arvalid),.paxi_arready(paxi_arready),
 .paxi_rdata(paxi_rdata),.paxi_rvalid(paxi_rvalid),.paxi_rlast(paxi_rlast),.paxi_rready(paxi_rready));
'''+ctrl[end:]
ctrl=ctrl.replace('failed_words','failed_frames')
(repo/'fpga/csi2/src/mem/ddrmc_capture_top.v').write_bytes(ctrl.encode())
if a.derive_only:
    print('DERIVED_ONLY');raise SystemExit(0)
vendor=repo/'fpga/csi2/prj/ddr_frame_probe/vendor'
vm=json.loads((vendor.parent/'vendor_manifest.json').read_text())
assert all(sha(vendor/f)==h for f,h in vm['files'].items())
out=Path('D:/TD/work/csi2/prj')/('camera_ddr_capture_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
out.mkdir(parents=True,exist_ok=False);shutil.copytree(vendor,out/'vendor')
# Only the selected source snapshot, never the live project's runs or outputs.
tracked=subprocess.check_output(['D:/downlaod/Git/cmd/git.exe','ls-files','-z','fpga/csi2/prj/camera_peer/uisrc'],cwd=repo).decode().split('\0')
for name in filter(None,tracked):
    f=repo/name;q=out/'camera'/f.relative_to(camera);q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(f,q)
new_sources=['capture_async_fifo.v','gray_frame_pack.v','camera_ddr_capture.v','ddr_capture_check.v','ddr_frame_store.v','ddrmc_capture_top.v']
for f in new_sources:shutil.copyfile(repo/'fpga/csi2/src/mem'/f,out/f)
for f in ['cam_preview_capture.v','f9p_camera_capture_core.v']:shutil.copyfile(dest/f,out/f);new_sources.append(f)
top=(vendor/'rtl/top/example_top.v').read_text()
top=top.replace('module example_top#(','module camera_ddr_capture_top#(').replace('ddrmc_test_top #(','ddrmc_capture_top #(')
top=top.replace('sys_clk','sys_clk50m').replace('usr_uart_txd','O_uart_txd')
top=top.replace('output [              2 : 0]  led','output [              3 : 0]  O_led')
camera_header=source[source.index('module f9p_imx415x2_top ('):source.index(');',source.index('module f9p_imx415x2_top ('))]
lines=[x for x in camera_header.splitlines()[1:] if re.match(r'\s*(input|output|inout)\b',x) and not any(s in x for s in ['sys_clk50m','O_led','O_uart_txd'])]
ports=[re.search(r'\b(\w+)\s*,?\s*(?://.*)?$',x).group(1) for x in lines]
port_text='\n'.join(x.split('//')[0].rstrip().rstrip(',')+',' for x in lines).rstrip(',')
top=top.replace('ddr_dm\n);','ddr_dm,\n'+port_text+'\n);')
assert all(p in top[:top.index(');')] for p in ports)
top=top.replace('    .led             ( led               )','    .cap_clk(cap_clk),.cap_sof(cap_sof),.cap_valid(cap_valid),.cap_last(cap_last),.cap_data(cap_data),\n    .led             ( O_led[2:0]        )')
rom=(out/'vendor/rtl/usr_mcu_srcs/mcu_rom/mcu_rom.txt').as_posix()
top=top.replace('"../mcu_rom/mcu_rom.txt"','"'+rom+'"')
inst='\nwire cap_clk,cap_sof,cap_valid,cap_last;wire[7:0] cap_data;wire[3:0] camera_led;wire camera_uart;\nf9p_camera_capture_core u_camera(\n'
inst+=',\n'.join(' .'+p+'('+p+')' for p in ['sys_clk50m']+ports)
inst+=',\n .O_led(camera_led),.O_uart_txd(camera_uart),.cap_clk(cap_clk),.cap_sof(cap_sof),.cap_valid(cap_valid),.cap_last(cap_last),.cap_data(cap_data));\nassign O_led[3]=~camera_led[0];\n'
top=top.replace('endmodule',inst+'endmodule');(out/'camera_ddr_capture_top.v').write_bytes(top.encode());new_sources.append('camera_ddr_capture_top.v')
adc=(camera/'uisrc/04_pin/fep_vid006_imx415.adc').read_text()
extra=(vendor/'adc/ap115v2.adc').read_text()
extra='\n'.join(x for x in extra.splitlines() if any(' '+p+' ' in x for p in ['sys_rst_n','usr_uart_rxd']))
(out/'board.adc').write_bytes((adc+'\n'+extra+'\n').encode())
sdc=(camera/'uisrc/04_pin/timing.sdc').read_text().replace('u_csi_','u_camera/u_csi_').replace('X_ui_pll/','u_camera/X_ui_pll/').replace('u_camera_startup/','u_camera/u_camera_startup/')
# Include DDR user clocks in the non-CSI group. DDR IP retains its own MCU/PHY exceptions.
sdc=sdc.replace('set_clock_groups -asynchronous','rename_clock -name {ddr_user} [get_clocks {u_ddrmc_test_top/u_ddrmc_x32/usr_clk}]\nset_clock_groups -asynchronous')
sdc=sdc.replace('-group {sys_clk50m pclkx1 pclkx5 mclk27}','-group {sys_clk50m pclkx1 pclkx5 mclk27 ddr_user}')
# B receive datapath is unused in this A-only candidate and synthesis removes it.
sdc='\n'.join(x for x in sdc.splitlines() if not x.startswith('create_generated_clock -name {mipi_b_byte_clk}'))+'\n'
sdc=sdc.replace('-group {mipi_b_clk_hs mipi_b_byte_clk}', '-group {mipi_b_clk_hs}')
sdc+='''
# SWUG105 PDF81-82: bus skew remains active despite asynchronous clock groups.
set_path_skew -from [get_regs {u_ddrmc_test_top/u_capture/u_fifo/wgray[*]}] -to [get_regs {u_ddrmc_test_top/u_capture/u_fifo/rq1_wgray[*]}] 4.000
set_path_skew -from [get_regs {u_ddrmc_test_top/u_capture/u_fifo/rgray[*]}] -to [get_regs {u_ddrmc_test_top/u_capture/u_fifo/wq1_rgray[*]}] 4.000
'''
(out/'timing.sdc').write_bytes(sdc.encode())
source_list=re.findall(r'<File Path="([^\"]+)"', (camera/'fpga_prj.al').read_text())
source_list=[f for f in source_list if f.endswith('.v') and not f.endswith(('f9p_imx415x2_top.v','cam_preview.v'))]
files=['./'+f for f in new_sources]+['./camera/'+f for f in source_list]
files+=['./camera/uisrc/03_ip/raw10_clocks/raw10_clocks.xml','./camera/uisrc/03_ip/ui_pll/ui_pll.xml']
files+=['./'+p.relative_to(out).as_posix() for p in sorted((out/'vendor/rtl/usr_mcu_srcs').rglob('*.v'))]
files+=['./vendor/ip/ddrmc_x32/ddrmc_x32.xml','./board.adc','./timing.sdc']
for f in files:assert (out/f).is_file(),f
tcl='''if {[catch {
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
create_project camera_ddr_capture ./ -family ph1 -device PH1P100SBG484 -speed -3
FILES
top_module camera_ddr_capture_top
PHY_STRATEGY
launch_runs syn_1
wait_run syn_1 -quiet
launch_runs -step route phy_1
wait_run phy_1 -quiet
import_db ./camera_ddr_capture_Runs/phy_1/camera_ddr_capture_pr.db
update_timing -mode final
report_timing_summary -file ./capture_timing.rpt
report_timing_ignored -file ./capture_ignored.rpt -ep_num 50
report_abnormal_timing_target -file ./capture_abnormal.rpt
report_path_skew -file ./capture_skew.rpt -ep_num 20
report_area -file ./capture.area
close_project
puts "CAPTURE_ROUTE_RETURNED_CHECK_REPORTS"
} msg]} {puts stderr "CAPTURE_BUILD_ERROR: $msg";exit 1}
exit 0
'''.replace('FILES','\n'.join('add_files '+f for f in files)).replace('PHY_STRATEGY','set_strategy -run phy_1 TimingHigh' if a.phy_strategy=='TimingHigh' else '# Default physical strategy')
(out/'build.tcl').write_bytes(tcl.encode())
(out/'input_manifest.json').write_bytes((json.dumps({p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file()},indent=2)+'\n').encode())
print(out)
