"""Import only pinned Git-tracked files into a NEW FPGA subproject. Never delete."""
from pathlib import Path
import hashlib
import json
import subprocess

SOURCE = Path(r"D:\TD\work\_peer_f9p_review_20261010")
TARGET = Path(r"D:\TD\work\csi2\prj\camera_peer")
COMMIT = "2d59180c38e7b7be6ac992c05c42eef12ce2811b"
GIT = r"D:\downlaod\Git\cmd\git.exe"

def git(*args):
    return subprocess.check_output([GIT, "-C", str(SOURCE), *args])

assert git("rev-parse", "HEAD").decode().strip() == COMMIT
assert not git("status", "--porcelain"), "Review clone must stay unchanged"
assert not TARGET.exists(), "Destination already exists; inspect instead of overwriting"
assert TARGET.parent.resolve() == Path(r"D:\TD\work\csi2\prj").resolve()
entries = []
for raw in git("ls-files", "-z").split(b"\0"):
    if not raw:
        continue
    rel = raw.decode("utf-8")
    src = (SOURCE / rel).resolve()
    assert src.is_relative_to(SOURCE.resolve()) and src.is_file()
    dst = TARGET / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    data = src.read_bytes()
    dst.write_bytes(data)
    entries.append({"path": rel, "upstream_sha256": hashlib.sha256(data).hexdigest()})
project = TARGET / "fpga_prj.al"
data = project.read_bytes()
old = b'/home/xiaozhu/Projects/f9p_ph1p100_imx415x2'
assert data.count(old) == 1
project.write_bytes(data.replace(old, TARGET.as_posix().encode()))
(TARGET / "UPSTREAM_MANIFEST.json").write_text(json.dumps({
    "url": "https://github.com/xiaozhuABCD1234/f9p_ph1p100_imx415x2",
    "commit": COMMIT, "files": entries,
    "initial_local_change": "fpga_prj.al Project Path points to D:/TD/work/csi2/prj/camera_peer"
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"IMPORTED {len(entries)} pinned files into {TARGET}")
