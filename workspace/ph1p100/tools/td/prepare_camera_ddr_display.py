"""Prepare an isolated DDR-display project from pinned camera/DDR inputs."""
from pathlib import Path
import subprocess,sys,hashlib,json
repo=Path(__file__).resolve().parents[2]
base=repo/'tools/td/prepare_camera_ddr_capture.py'
r=subprocess.run([sys.executable,'-X','utf8',str(base),'--phy-strategy','TimingHigh'],cwd=repo,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',check=True)
old=Path(r.stdout.strip().splitlines()[-1]).resolve()
parent=Path('D:/TD/work/csi2/prj').resolve()
assert old.parent==parent and old.name.startswith('camera_ddr_capture_') and not old.is_symlink()
out=parent/old.name.replace('camera_ddr_capture_','camera_ddr_display_',1)
assert out.parent.resolve()==parent and not out.exists()
# Rename only the just-created, validated project. Existing candidates stay put.
old.rename(out)
for f in out.rglob('*.v'):
 s=f.read_bytes();n=s.replace(old.as_posix().encode('ascii'),out.as_posix().encode('ascii'))
 if n!=s:f.write_bytes(n)
cam=repo/'fpga/csi2/src/cam'
core=(cam/'f9p_camera_capture_core.v').read_text(encoding='utf-8')
core=core.replace('module f9p_camera_capture_core (','module f9p_camera_display_core (\n    output wire display_pclk,display_rst_n,display_vs,display_hs,display_de,\n    input wire[23:0] ddr_rgb,input wire ddr_vs,ddr_hs,ddr_de,')
core=core.replace('.I_video_in_data ({w_rgb_r, w_rgb_g, w_rgb_b})','.I_video_in_data (ddr_rgb)')
core=core.replace('.I_video_in_de   (w_cam_alive ? w_cam_de : r_tpg_de)','.I_video_in_de   (ddr_de)')
core=core.replace('.I_video_in_vs   (w_cam_alive ? r_cam_vs[1] : r_tpg_vs)','.I_video_in_vs   (ddr_vs)')
core=core.replace('.I_video_in_hs   (w_cam_alive ? r_cam_hs[1] : r_tpg_hs)','.I_video_in_hs   (ddr_hs)')
core=core.replace('assign cap_clk=w_a_byte_clk;','assign cap_clk=w_a_byte_clk;\nassign display_pclk=w_pclkx1;assign display_rst_n=w_pixel_rst_n;\nassign display_vs=w_vtc_vs;assign display_hs=w_vtc_hs;assign display_de=w_vtc_de;')
assert '.I_video_in_data (ddr_rgb)' in core
(cam/'f9p_camera_display_core.v').write_bytes(core.encode());(out/'f9p_camera_display_core.v').write_bytes(core.encode())
ctrl=(repo/'fpga/csi2/src/mem/ddrmc_capture_top.v').read_text()
ctrl=ctrl.replace('module ddrmc_capture_top #(','module ddrmc_display_top #(')
ctrl=ctrl.replace('// clock & reset\n    input cap_clk','// clock & reset\n    input display_pclk,display_rst_n,display_vs,display_hs,display_de,\n    output[23:0] ddr_rgb,output ddr_vs,ddr_hs,ddr_de,\n    input cap_clk',1)
ctrl=ctrl.replace('camera_ddr_capture #(.FRAME_BYTES(FRAME_BYTES))','camera_ddr_display #(.SW(960),.SH(540))')
ctrl=ctrl.replace('.rst_n(ddrphy_rst_n),.ddr_ready(ddrphy_rdy)', '.rst_n(ddrphy_rst_n&&display_rst_n),.ddr_ready(ddrphy_rdy)')
ctrl=ctrl.replace('wire[31:0] capture_drops;','(* MARK_DEBUG="true" *) wire[31:0] capture_drops,underflow_frames,shown_frames;')
ctrl=ctrl.replace(' .sof(cap_sof)', ' .pclk(display_pclk),.vs(display_vs),.hs(display_hs),.de(display_de),\n .rgb(ddr_rgb),.out_vs(ddr_vs),.out_hs(ddr_hs),.out_de(ddr_de),.underflow_frames(underflow_frames),.shown_frames(shown_frames),\n .sof(cap_sof)')
ctrl=ctrl.replace('reg [25:0] clk_cnt;', '''// Register the pixel-domain error flag before its two-stage crossing.
reg pixel_error_seen;
always @(posedge display_pclk or negedge ddrphy_rst_n)begin
 if(!ddrphy_rst_n)pixel_error_seen<=0;else if(underflow_frames!=0)pixel_error_seen<=1;
end
(* ASYNC_REG="TRUE" *) reg[1:0] pixel_error_sync;
always @(posedge dhi_clk or negedge ddrphy_rst_n)begin
 if(!ddrphy_rst_n)pixel_error_sync<=0;else pixel_error_sync<={pixel_error_sync[0],pixel_error_seen};
end
reg [25:0] clk_cnt;''')
ctrl=ctrl.replace('if(failed_frames!=0||protocol_errors!=0)', 'if(failed_frames!=0||protocol_errors!=0||pixel_error_sync[1])')
(repo/'fpga/csi2/src/mem/ddrmc_display_top.v').write_bytes(ctrl.encode());(out/'ddrmc_display_top.v').write_bytes(ctrl.encode())
for name in ['camera_ddr_display.v','ddr_display_read.v','gray_display_pixels.v']:(out/name).write_bytes((repo/'fpga/csi2/src/mem'/name).read_bytes())
top=(out/'camera_ddr_capture_top.v').read_text()
top=top.replace('module camera_ddr_capture_top#(','module camera_ddr_display_top#(').replace('ddrmc_capture_top #(','ddrmc_display_top #(').replace('f9p_camera_capture_core u_camera','f9p_camera_display_core u_camera')
ports=' .display_pclk(display_pclk),.display_rst_n(display_rst_n),.display_vs(display_vs),.display_hs(display_hs),.display_de(display_de),\n .ddr_rgb(ddr_rgb),.ddr_vs(ddr_vs),.ddr_hs(ddr_hs),.ddr_de(ddr_de),\n'
top=top.replace('    .cap_clk(cap_clk)',ports+'    .cap_clk(cap_clk)')
top=top.replace('wire cap_clk,cap_sof,cap_valid,cap_last;', 'wire display_pclk,display_rst_n,display_vs,display_hs,display_de;\nwire[23:0] ddr_rgb;wire ddr_vs,ddr_hs,ddr_de;\nwire cap_clk,cap_sof,cap_valid,cap_last;')
top=top.replace(' .O_led(camera_led)',ports+' .O_led(camera_led)')
(out/'camera_ddr_display_top.v').write_bytes(top.encode())
sdc=(out/'timing.sdc').read_text().replace('-group {sys_clk50m pclkx1 pclkx5 mclk27 ddr_user}','-group {sys_clk50m pclkx1 pclkx5 mclk27} -group {ddr_user}')
sdc+='\n# Display FIFO crosses independent DDR and fractional pixel PLL domains.\n'
for src,dst in [('wgray','rq1_wgray'),('rgray','wq1_rgray')]:
 sdc+=f'set_path_skew -from [get_regs {{u_ddrmc_test_top/u_capture/u_display_fifo/{src}[*]}}] -to [get_regs {{u_ddrmc_test_top/u_capture/u_display_fifo/{dst}[*]}}] 4.000\n'
(out/'timing.sdc').write_bytes(sdc.encode())
t=(out/'build.tcl').read_text()
for src,dst in [('camera_ddr_capture_top','camera_ddr_display_top'),('camera_ddr_capture.v','camera_ddr_display.v'),('ddrmc_capture_top.v','ddrmc_display_top.v'),('f9p_camera_capture_core.v','f9p_camera_display_core.v')]:t=t.replace(src,dst)
t=t.replace('create_project camera_ddr_capture ', 'create_project camera_ddr_display ').replace('camera_ddr_capture_Runs','camera_ddr_display_Runs').replace('camera_ddr_capture_pr.db','camera_ddr_display_pr.db')
t=t.replace('top_module camera_ddr_display_top','add_files ./ddr_display_read.v\nadd_files ./gray_display_pixels.v\ntop_module camera_ddr_display_top')
(out/'build.tcl').write_bytes(t.encode())
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
manifest={f.relative_to(out).as_posix():sha(f) for f in sorted(out.rglob('*')) if f.is_file() and f.name!='input_manifest.json'}
(out/'input_manifest.json').write_bytes((json.dumps(manifest,indent=2)+'\n').encode())
print(out)
