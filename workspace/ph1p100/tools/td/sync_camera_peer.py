from pathlib import Path
raise SystemExit("Historical one-off snapshot record. Review current source and metadata before synchronizing.")
import json, hashlib, subprocess
workspace=Path(__file__).resolve().parents[2]
root=Path(r'D:\TD\work\csi2\prj\camera_peer').resolve()
mirror=(workspace/'fpga/csi2/prj/camera_peer').resolve()
assert mirror.is_relative_to(workspace.resolve())
manifest=json.loads((root/'UPSTREAM_MANIFEST.json').read_text(encoding='utf-8'))
for name in ['tb_cam_preview_math.sv','tb_cam_preview_read.sv']:
 src=mirror/'uisrc/02_sim'/name
 dst=root/'uisrc/02_sim'/name
 dst.write_bytes(src.read_bytes())
ignore=root/'.gitignore'
s=ignore.read_bytes()
extra=b'\n# Local verification data (kept on D:, never copied into source snapshot)\n_sim/\n_evidence/\n_probe*/\n'
if b'_probe*/' not in s: ignore.write_bytes(s+extra)
notes='''# 本地接入说明

源自上游提交2d59180c38e7b7be6ac992c05c42eef12ce2811b，原README记录固定来源版本，最新状态以本文件和项目docs差异报告为准。

工作目录是D:/TD/work/csi2/prj/camera_peer，仓库fpga/csi2/prj/camera_peer仅源码快照。打开本机D盘fpga_prj.al。另一个路径/机器需要先调整.al中Project Path；源文件采用相对路径。没有自动同步。

本轮只修改cam_preview.v行为：水平缩位、垂直进位、clog2b、完整RAM地址空间与同步读口/bram属性；图像仍960x540，输入仍4K RAW10，未改相机/引脚/tap。原PCIe骨架未覆盖。测试平台未纳入综合工程。

本机构建syn_pad_1/phy_pad_1已产生bit，但setup WNS=-0.221ns，STA没有通过；不要把它作为验收bit。详细警告及后续路线见仓库docs/相机链路方案对照与验证_2026-10-10.md。未下载或烧录。

原gen_ip.tcl是旧实验，不执行；download_sram.tcl为原工程Linux路径，不执行。build_padded.tcl用于本次新run，重复执行已有同名run会报错；未来构建应明确新run名，保留证据，不reset或批量删除。

原样审查副本在D:/TD/work/_peer_f9p_review_20261010。UPSTREAM_MANIFEST.json记录原文件SHA256；LOCAL_STATE.json记录当前源码、bit、验证摘要和修改清单。D盘_sim、_evidence、_probe和fpga_prj_Runs保留实际日志，源码快照不含大体积构建产物。
'''
(root/'LOCAL_NOTES.md').write_text(notes,encoding='utf-8')
files=[f['path'] for f in manifest['files']]+['UPSTREAM_MANIFEST.json','LOCAL_NOTES.md','build_local.tcl','build_fixed.tcl','build_fixed_bram.tcl','build_fixed_final.tcl','build_padded.tcl','uisrc/02_sim/tb_cam_preview_math.sv','uisrc/02_sim/tb_cam_preview_read.sv']
hashes={}
for rel in files:
 src=(root/rel).resolve()
 assert src.is_relative_to(root) and src.is_file()
 dst=(mirror/rel).resolve()
 assert dst.is_relative_to(mirror)
 dst.parent.mkdir(parents=True,exist_ok=True)
 data=src.read_bytes()
 dst.write_bytes(data)
 assert dst.read_bytes()==src.read_bytes()
 hashes[rel]=hashlib.sha256(data).hexdigest()
changed=[f['path'] for f in manifest['files'] if hashes[f['path']]!=f['upstream_sha256']]
bit=root/'fpga_prj_Runs/phy_pad_1/fpga_prj.bit'
state={'upstream_commit':manifest['commit'],'date':'2026-10-10','modified_upstream_files':changed,'sha256':hashes,
 'build':{'compiled_cam_preview_sha256':hashlib.sha256((root/'_evidence/padded_build_cam_preview.v').read_bytes()).hexdigest(),'post_build_change':'comments only, Verilog tokens independently unchanged','tool':'6.2.2.200067','syn':'syn_pad_1','phy':'phy_pad_1','bit_path':str(bit),'bit_bytes':bit.stat().st_size,'bit_sha256':hashlib.sha256(bit.read_bytes()).hexdigest(),'eram':224,'slice':3190,'setup_wns_ns':-0.221,'setup_tns_ns':-2.156,'hold_wns_ns':0.020,'sta_coverage_percent':97.91,'timing_pass':False,'hardware_downloaded':False},
 'simulation':{'math_checks':1048583,'math_pass':True,'read_cycles_width4':420,'read_cycles_width3':356,'read_pass':True},
 'evidence_root':str(root)}
for base in [root,mirror]:
 (base/'LOCAL_STATE.json').write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Preserve existing PCIe skeleton; verify against repository HEAD as well as D:.
git=r'D:\downlaod\Git\cmd\git.exe'
original=subprocess.check_output([git,'show','HEAD:fpga/csi2/src/pcie_top.v'],cwd=workspace)
assert original==(workspace/'fpga/csi2/src/pcie_top.v').read_bytes()==Path(r'D:\TD\work\csi2\src\pcie_top.v').read_bytes()
print(json.dumps({'mirrored_files':len(files)+1,'modified_upstream_files':changed,'bit_sha256':state['build']['bit_sha256'],'pcie_skeleton_unchanged':True},ensure_ascii=False))
