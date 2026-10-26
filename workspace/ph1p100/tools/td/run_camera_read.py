"""Compare public read outputs to the pinned upstream RTL, under asynchronous clocks."""
from pathlib import Path
import argparse
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--label", choices=["read_equivalence", "read_final", "read_padded", "read_geometry"], default="read_equivalence")
args = parser.parse_args()
root = Path(r"D:\TD\work\csi2\prj\camera_peer")
out = root / "_sim" / args.label
assert not out.exists()
out.mkdir(parents=True)
upstream = Path(r"D:\TD\work\_peer_f9p_review_20261010\uisrc\01_rtl\cam_preview.v").read_bytes()
assert upstream.count(b"module cam_preview #(") == 1
(out / "upstream_cam_preview.v").write_bytes(upstream.replace(b"module cam_preview #(", b"module upstream_cam_preview #("))
tb = Path(__file__).resolve().parents[2] / "fpga/csi2/prj/camera_peer/uisrc/02_sim/tb_cam_preview_read.sv"
bin_dir = Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
outputs = []
for command in [
    [str(bin_dir / "vlib.exe"), "work"],
    [str(bin_dir / "vlog.exe"), "-sv", str(root / "uisrc/01_rtl/cam_preview.v"),
     "upstream_cam_preview.v", str(tb)],
    [str(bin_dir / "vsim.exe"), "-c", "-voptargs=+acc", "work.tb_cam_preview_read", "-do", "run -all; quit -f"],
    [str(bin_dir / "vsim.exe"), "-c", "-voptargs=+acc", "-gSW=3", "work.tb_cam_preview_read", "-do", "run -all; quit -f"],
]:
    result = subprocess.run(command, cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = result.stdout.decode("utf-8", errors="replace")
    outputs.append(output)
    (out / "regression.log").write_text("\n".join(outputs), encoding="utf-8")
    print(output[-5000:])
    if result.returncode:
        raise SystemExit(result.returncode)
if not all("READ_PASS" in output and "banks=1111" in output for output in outputs[-2:]):
    raise SystemExit(1)
