"""Prepare a NEW single-camera CSI-CRC/FE-gated DDR display candidate."""
from pathlib import Path
import subprocess,sys,json,hashlib
repo=Path(__file__).resolve().parents[2]
r=subprocess.run([sys.executable,'-X','utf8',str(repo/'tools/td/prepare_camera_csi_checked.py')],cwd=repo,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',check=True)
fresh=Path(r.stdout.strip().splitlines()[-1]).resolve();parent=Path('D:/TD/work/csi2/prj').resolve()
assert fresh.parent==parent and fresh.name.startswith('camera_csi_checked_') and not fresh.is_symlink()
out=parent/fresh.name.replace('camera_csi_checked_','camera_csi_integrity_',1);assert not out.exists() and out.parent.resolve()==parent
fresh.rename(out)
for f in out.rglob('*.v'):
 b=f.read_bytes();n=b.replace(fresh.as_posix().encode('ascii'),out.as_posix().encode('ascii'))
 if b!=n:f.write_bytes(n)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();overlay={}
def edit(name,fn):
 p=out/name;before=sha(p);s=fn(p.read_text());p.write_bytes(s.encode());overlay[name]={'before_sha256':before,'sha256':sha(p)}
def patch(s,old,new):
 assert s.count(old)==1,(old,s.count(old));return s.replace(old,new,1)
ip='camera/uisrc/03_ip/mipi_csi_2/'
events=['frame_end','frame_good','frame_abort'];stats=['crc_errors','header_errors','packet_timeouts','frame_timeouts','good_frames','bad_frames','last_wc','last_lines']
def wrap(s):
 ports='output wire '+','.join('O_'+v for v in events)+',\n    '
 ports+=''.join('output wire['+('15:0' if v.startswith('last_') else '31:0')+'] O_'+v+',\n    ' for v in stats)
 s=patch(s,'output wire                  O_pixel_valid',ports+'output wire                  O_pixel_valid')
 s=patch(s,'csi_rx_packet_handler_checked #(','csi_rx_packet_integrity #(')
 s=patch(s,'.MIPI_LAN (LANE_NUM)\n    ) u_packet', '.VC_ID (0)\n    ) u_packet')
 return patch(s,'.O_payload_keep  (checked_payload_keep),','.O_payload_keep  (checked_payload_keep),\n        '+','.join('.O_'+v+'(O_'+v+')' for v in events+stats)+',')
edit(ip+'mipi_csi2_rx_ph1p.v',wrap)
def core(s):
 s=patch(s,'module f9p_camera_display_core (','module f9p_camera_display_core (\n    output wire '+','.join('cap_'+v for v in events)+',')
 pos=s.index('    mipi_csi2_rx_ph1p #(.LANE_NUM(4)) u_csi_a')
 diag='\n    '+''.join('(* MARK_DEBUG="true" *) wire['+('15:0' if v.startswith('last_') else '31:0')+'] w_a_'+v+';\n    ' for v in stats)
 s=s[:pos]+diag+s[pos:]
 start=s.index('u_csi_a (');end=s.index('    );',start);seg=s[start:end]
 seg=patch(seg,'.O_pixel_valid      (w_a_pixel_valid )','.O_pixel_valid      (w_a_pixel_valid ),\n        '+','.join('.O_'+v+'(cap_'+v+')' for v in events)+',\n        '+','.join('.O_'+v+'(w_a_'+v+')' for v in stats));s=s[:start]+seg+s[end:]
 start=s.index('u_csi_b (');end=s.index('    );',start);seg=s[start:end]
 seg=patch(seg,'.O_pixel_valid      (w_b_pixel_valid )','.O_pixel_valid      (w_b_pixel_valid ),\n        '+','.join('.O_'+v+'()' for v in events+stats));return s[:start]+seg+s[end:]
edit('f9p_camera_display_core.v',core)
def ctrl(s):
 s=patch(s,'    input cap_clk,','    input '+','.join('cap_'+v for v in events)+',\n    input cap_clk,')
 s=patch(s,'camera_ddr_display #','camera_ddr_display_guarded #')
 s=patch(s,' .sof(cap_sof)', ' '+','.join('.'+v+'(cap_'+v+')' for v in events)+',\n .sof(cap_sof)')
 insert='''// Source-domain drop flag is registered before the two-stage DDR crossing.
reg cap_error_seen;
always @(posedge cap_clk or negedge ddrphy_rst_n)begin
 if(!ddrphy_rst_n)cap_error_seen<=0;else if(capture_drops!=0)cap_error_seen<=1;
end
(* ASYNC_REG="TRUE" *) reg[1:0] cap_error_sync;
always @(posedge dhi_clk or negedge ddrphy_rst_n)begin
 if(!ddrphy_rst_n)cap_error_sync<=0;else cap_error_sync<={cap_error_sync[0],cap_error_seen};
end
'''
 s=patch(s,'reg pixel_error_seen;',insert+'reg pixel_error_seen;')
 return patch(s,'failed_frames!=0||protocol_errors!=0||pixel_error_sync[1]','failed_frames!=0||protocol_errors!=0||pixel_error_sync[1]||cap_error_sync[1]')
edit('ddrmc_display_top.v',ctrl)
def top(s):
 s=patch(s,'wire cap_clk,cap_sof,cap_valid,cap_last;', 'wire '+','.join('cap_'+v for v in events)+';\nwire cap_clk,cap_sof,cap_valid,cap_last;')
 old='.cap_clk(cap_clk),.cap_sof(cap_sof)';assert s.count(old)==2
 return s.replace(old,','.join('.cap_'+v+'(cap_'+v+')' for v in events)+','+old)
edit('camera_ddr_display_top.v',top)
files={'fpga/csi2/src/csi/csi_rx_packet_integrity.v':ip+'csi_rx_packet_integrity.v','fpga/csi2/src/mem/gray_frame_pack_guarded.v':'gray_frame_pack_guarded.v','fpga/csi2/src/mem/camera_ddr_display_guarded.v':'camera_ddr_display_guarded.v'}
for src,dst in files.items():
 (out/dst).write_bytes((repo/src).read_bytes());overlay[dst]={'source':src,'sha256':sha(out/dst)}
build=(out/'build.tcl').read_text()
for old,new in [('csi_rx_packet_handler_checked.v','csi_rx_packet_integrity.v'),('gray_frame_pack.v','gray_frame_pack_guarded.v'),('camera_ddr_display.v','camera_ddr_display_guarded.v')]:build=patch(build,'/'+old,'/'+new)
(out/'build.tcl').write_bytes(build.encode('ascii'))
(out/'integrity_overlay.json').write_bytes((json.dumps({'overlay':overlay,'policy':'CRC all selected-VC long packets; frame-consistent RAW10 WC, nonempty image, FE-gated footer; exact sensor WC/lines/ID not hardware-frozen','board_scope':'A only; RAW10 4K30 to 960x540 Gray8 DDR, HDMI1080p60'},indent=2)+'\n').encode())
(out/'input_manifest.json').write_bytes((json.dumps({p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file() and p.name!='input_manifest.json'},indent=2)+'\n').encode())
print(out)
