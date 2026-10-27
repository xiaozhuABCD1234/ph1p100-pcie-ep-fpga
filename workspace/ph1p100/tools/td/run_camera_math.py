"""ModelSim regression of the real preview RTL. Logs remain under the D: project."""
from pathlib import Path
import argparse
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--rtl-root", type=Path, required=True)
parser.add_argument("--label", choices=["upstream", "fixed", "fixed_retry", "final", "padded", "sequence"], required=True)
args = parser.parse_args()
root = args.rtl_root.resolve()
assert root == Path(r"D:\TD\work\csi2\prj\camera_peer").resolve()
out = root / "_sim" / args.label
assert not out.exists(), "Preserve existing results; inspect them before rerunning"
out.mkdir(parents=True)
tb = Path(__file__).resolve().parents[2] / "fpga/csi2/prj/camera_peer/uisrc/02_sim/tb_cam_preview_math.sv"
bin_dir = Path(r"D:\intelFPGA\18.1\modelsim_ase\win32aloem")
commands = [
    [str(bin_dir / "vlib.exe"), "work"],
    [str(bin_dir / "vlog.exe"), "-sv", str(root / "uisrc/01_rtl/cam_preview.v"), str(tb)],
    [str(bin_dir / "vsim.exe"), "-c", "-voptargs=+acc", "work.tb_cam_preview_math",
     "-do", "run -all; quit -f"],
]
outputs = []
for command in commands:
    result = subprocess.run(command, cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = result.stdout.decode("utf-8", errors="replace")
    outputs.append(output)
    (out / "regression.log").write_text("\n".join(outputs), encoding="utf-8")
    print(output[-5000:])
    if result.returncode:
        raise SystemExit(result.returncode)
if "MATH_PASS checks=1048583" not in outputs[-1]:
    raise SystemExit(1)
