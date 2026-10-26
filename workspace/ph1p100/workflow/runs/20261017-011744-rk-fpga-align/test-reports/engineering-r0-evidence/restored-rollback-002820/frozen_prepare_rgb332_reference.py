"""Derive a separate reference-strip candidate from frozen RGB332161550."""
from pathlib import Path
import datetime,hashlib,json
from rgb332_reference_support import attach_reference

repo=Path(__file__).resolve().parents[2]
base=Path('D:/TD/work/csi2/prj/camera_rgb332_20261013_161550')
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
assert sha(base/'camera_ddr_display.bit')=='6b94fb04649de5fbffc1075f50e5cc58182e221864b2fb924813fe5b66125f5f'
manifest=json.loads((base/'input_manifest.json').read_bytes());assert len(manifest)==193
for rel,digest in manifest.items():
 f=(base/rel).resolve();assert f.is_relative_to(base.resolve()) and sha(f)==digest,rel
out=base.parent/('camera_rgb332_reference_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
assert not out.exists();out.mkdir();changes={}
for rel in manifest:
 f=out/rel;f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes((base/rel).read_bytes())
def save(rel,data,reason):
 f=out/rel;before=sha(f) if f.exists() else None;f.write_bytes(data)
 changes[rel]={'before_sha256':before,'sha256':sha(f),'reason':reason}
for rel in manifest:
 f=out/rel
 if f.suffix=='.v':
  raw=f.read_bytes();data=raw.replace(base.as_posix().encode(),out.as_posix().encode())
  if raw!=data:save(rel,data,'Relocate unchanged ROM initialization payload')
save('camera_ddr_display_guarded.v',attach_reference((base/'camera_ddr_display_guarded.v').read_bytes()),'Keep original decoder/control/FIFOs; overlay known RGB after DDR decoding')
save('rgb332_reference_overlay.v',(repo/'fpga/csi2/src/mem/rgb332_reference_overlay.v').read_bytes(),'Fixed digital reference strip; original image below it; no added control latency')
s=(base/'build_rgb332.tcl').read_bytes();anchor=b'add_files ./rgb332_display_pixels.v';assert s.count(anchor)==1
s=s.replace(anchor,anchor+b'\nadd_files ./rgb332_reference_overlay.v').replace(b'RGB332_SYNTHESIS_',b'RGB332_REFERENCE_SYNTHESIS_')
save('build_reference.tcl',s,'Synthesis entry with the new overlay source')
save('route_reference.tcl',(base/'route_rgb332.tcl').read_bytes().replace(b'CSI_CHECKED_ROUTE_',b'RGB332_REFERENCE_ROUTE_'),'Same native physical flow and timing strategy')
for kind in ['inspect','bitgen']:
 save(kind+'_reference.tcl',('set display_checkpoint ./csi_checked_debug_pr.db\nsource ./'+kind+'_rgb332_body.tcl\n').encode(),'Review/generate only from this new routed checkpoint')
save('audit_hdmi_reference.tcl',(base/'audit_hdmi_rgb332.tcl').read_bytes(),'Read-only HDMI PAD audit of this new checkpoint')
save('refine_reference_once.tcl',(repo/'tools/td/refine_rgb332_once.tcl').read_bytes(),'Optional single separately saved native refinement if STA fails')
for rel in ['prepare_rgb332_reference.py','rgb332_reference_support.py']:
 save('frozen_'+rel,(repo/'tools/td'/rel).read_bytes(),'Candidate derivation script identity')
for rel in ['f9p_camera_display_core.v','bayer332_capture.v','rgb332_display_pixels.v','ddr_frame_store.v','ddr_display_read.v','gray_frame_pack_guarded.v','timing.sdc','board.adc','camera/uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v','camera/uisrc/01_rtl/raw10_display60_clocks.v']:
 assert (out/rel).read_bytes()==(base/rel).read_bytes(),rel
inputs={f.relative_to(out).as_posix():sha(f) for f in sorted(out.rglob('*')) if f.is_file()}
(out/'input_manifest.json').write_bytes((json.dumps(inputs,indent=2)+'\n').encode())
(out/'reference_overlay.json').write_bytes((json.dumps({'base':str(base),'base_bit_sha256':sha(base/'camera_ddr_display.bit'),'base_input_count':193,'input_count':len(inputs),'changes':changes,'reference_rows':64,'palette':['white','red','green','blue','cyan','magenta','yellow','black'],'added_pipeline_cycles':0,'hardware_verified':False,'limits':'Reference bypasses camera payload but preserves camera/DDR activity. Correct bars do not prove acquisition or physical-rate qualification.'},indent=2)+'\n').encode())
print(out)
