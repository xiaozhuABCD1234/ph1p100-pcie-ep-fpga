from pathlib import Path
root=Path(r'D:\TD\work\csi2\prj\camera_peer')
p=root/'uisrc/01_rtl/cam_preview.v'
s=p.read_bytes()
backup=root/'_evidence/fix3_cam_preview.v'
if backup.exists(): assert backup.read_bytes()==s
else: backup.write_bytes(s)
assert s.count(b'for (i = 1; i < x; i = i * 2)')==1
s=s.replace(b'for (i = 1; i < x; i = i * 2)',b'for (i = 2; i < x; i = i * 2)')
needle=b'localparam AWB    = clog2b(RPB * SW);'
assert s.count(needle)==1
s=s.replace(needle,needle+b'\r\n    localparam RAM_DEPTH = (1 << AWB); // complete address space for ERAM')
for i in range(4):
 old=f'r_fb{i} [0:RPB*SW-1]'.encode()
 assert s.count(old)==1
 s=s.replace(old,f'r_fb{i} [0:RAM_DEPTH-1]'.encode())
p.write_bytes(s)
q=Path('tools/td/build_camera_fixed.tcl')
t=q.read_text(encoding='utf-8').replace('syn_fix_3','syn_pad_1').replace('phy_fix_3','phy_pad_1')
q.write_text(t,encoding='utf-8')
(root/'build_padded.tcl').write_text(t,encoding='utf-8')
q=Path('tools/td/run_camera_math.py')
t=q.read_text(encoding='utf-8').replace('"fixed_retry", "final"','"fixed_retry", "final", "padded"')
q.write_text(t,encoding='utf-8')
q=Path('tools/td/run_camera_read.py')
t=q.read_text(encoding='utf-8').replace('"read_equivalence", "read_final"','"read_equivalence", "read_final", "read_padded"')
q.write_text(t,encoding='utf-8')
print('Padded banks; actual preview stays 960x540')
