"""Overlay reviewed CSI packet/unpack modules onto a NEW pinned DDR project."""
from pathlib import Path
import hashlib,json,subprocess,sys
repo=Path(__file__).resolve().parents[2]
r=subprocess.run([sys.executable,'-X','utf8',str(repo/'tools/td/prepare_camera_ddr_display.py')],cwd=repo,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding='utf-8',check=True)
fresh=Path(r.stdout.strip().splitlines()[-1]).resolve()
parent=Path('D:/TD/work/csi2/prj').resolve()
assert fresh.parent==parent and fresh.name.startswith('camera_ddr_display_') and not fresh.is_symlink()
out=parent/fresh.name.replace('camera_ddr_display_','camera_csi_checked_',1)
assert not out.exists() and out.parent.resolve()==parent
fresh.rename(out)
for f in out.rglob('*.v'):
 b=f.read_bytes();n=b.replace(fresh.as_posix().encode('ascii'),out.as_posix().encode('ascii'))
 if b!=n:f.write_bytes(n)
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
ip=out/'camera/uisrc/03_ip/mipi_csi_2'
wrapper=ip/'mipi_csi2_rx_ph1p.v';before=sha(wrapper)
s=wrapper.read_text(encoding='utf-8')
assert s.count('csi_rx_packet_handler #(')==1 and s.count('csi_rx_10bit_unpack u_unpack')==1
s=s.replace('csi_rx_packet_handler #(','csi_rx_packet_handler_checked #(').replace('csi_rx_10bit_unpack u_unpack','csi_rx_10bit_unpack_checked u_unpack')
s=s.replace('    csi_rx_packet_handler_checked #(', '    wire [3:0] checked_payload_keep;\n    csi_rx_packet_handler_checked #(')
s=s.replace('.O_payload_valid (w_payload_valid   ),','.O_payload_valid (w_payload_valid   ),\n        .O_payload_keep  (checked_payload_keep),')
s=s.replace('.I_din_valid    (w_payload_valid   ),','.I_din_valid    (w_payload_valid   ),\n        .I_keep         (checked_payload_keep),')
assert s.count('checked_payload_keep')==3
wrapper.write_bytes(s.encode('utf-8'))
t=(out/'build.tcl').read_text()
overlays={}
for old,new in [('csi_rx_packet_handler.v','csi_rx_packet_handler_checked.v'),('csi_rx_10bit_unpack.v','csi_rx_10bit_unpack_checked.v')]:
 source=repo/'fpga/csi2/src/csi'/new;dest=ip/new
 assert t.count('/'+old)==1
 t=t.replace('/'+old,'/'+new);dest.write_bytes(source.read_bytes())
 overlays[dest.relative_to(out).as_posix()]={'source':source.relative_to(repo).as_posix(),'sha256':sha(dest)}
(out/'build.tcl').write_bytes(t.encode('ascii'))
overlays[wrapper.relative_to(out).as_posix()]={'original_sha256':before,'sha256':sha(wrapper),'change':'checked packet/unpack instances and contiguous byte keep only'}
(out/'csi_overlay.json').write_text(json.dumps({'overlay':overlays,'boundary':'CRC16/frame rejection not implemented; soft PHY, sensor mode, DDR and HDMI preserved'},indent=2)+'\n',encoding='ascii')
manifest={f.relative_to(out).as_posix():sha(f) for f in sorted(out.rglob('*')) if f.is_file() and f.name!='input_manifest.json'}
(out/'input_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='ascii')
print(out)
