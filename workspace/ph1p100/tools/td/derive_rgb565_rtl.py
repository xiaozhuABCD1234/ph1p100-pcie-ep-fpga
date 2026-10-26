"""Materialize reviewed RGB565 RTL from the unchanged 215134 source inputs."""
from pathlib import Path
import json,hashlib
from rgb565_support import capture,pack,reader,consumer,wrapper
root=Path(__file__).resolve().parents[2]
base=Path('D:/TD/work/csi2/prj/camera_rgb332_reference_20261013_215134')
manifest=json.loads((base/'input_manifest.json').read_bytes());assert len(manifest)==202
for rel,digest in manifest.items():
    assert hashlib.sha256((base/rel).read_bytes()).hexdigest()==digest,rel
for old,new,folder,transform in [
 ('bayer332_capture.v','bayer565_capture.v','cam',capture),
 ('gray_frame_pack_guarded.v','rgb565_frame_pack_guarded.v','mem',pack),
 ('ddr_display_read.v','rgb565_display_read.v','mem',reader),
 ('rgb332_display_pixels.v','rgb565_display_pixels.v','mem',consumer),
 ('camera_ddr_display_guarded.v','camera_rgb565_display_guarded.v','mem',wrapper)]:
    (root/'fpga/csi2/src'/folder/new).write_bytes(transform((base/old).read_bytes()))
