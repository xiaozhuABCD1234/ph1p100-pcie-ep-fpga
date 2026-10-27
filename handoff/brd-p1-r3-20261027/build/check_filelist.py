#!/usr/bin/env python3
"""T11.BRD.P1 r3 filelist preflight (repo root).

Parses handoff/brd-p1-r3-20261027/filelist.tcl, expands the repo-relative
variables, and fails closed on:
  * a missing source
  * *.v.stale / */src/src/* / peer-ref-2a4b253 / the two old r3-era copies
  * the two rejected r3-era SHA256 values anywhere in the list
  * two files defining the same module name
  * a .bit / .cwc in the source list
  * an unresolved `include
It also writes build/filelist-sha256.json (repo-relative path + SHA256 + size)
so the manifest and the handoff bind the exact same bytes.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
PKG = REPO / "handoff" / "brd-p1-r3-20261027"
FL = PKG / "filelist.tcl"
REJECTED_SHA = {
    "863932B3D42FBB4F97AD2A6A9397E477A012B61B534CD4DBEAD1997AF73A44BC",
    "B8096430C060BE77BE408B1D4103DE87F543193F94E78DE418189EA32C412B64",
}

vars = {"R": str(REPO)}
files = []
for raw in FL.read_text().splitlines():
    line = raw.split("#", 1)[0].strip()
    m = re.match(r"set\s+(\w+)\s+\$(\w+)(/.*)?$", line)
    if m:
        base = vars.get(m.group(2))
        if base is None:
            print(f"UNKNOWN_VAR {m.group(2)} in: {raw}")
            sys.exit(2)
        vars[m.group(1)] = base + (m.group(3) or "")
        continue
    m = re.match(r"lappend\s+FL\s+\$(\w+)(/.*)?$", line)
    if m:
        base = vars.get(m.group(1))
        if base is None:
            print(f"UNKNOWN_VAR {m.group(1)} in: {raw}")
            sys.exit(2)
        files.append(base + (m.group(2) or ""))

fails = []
sha_rows = []
mods = {}
for f in files:
    p = Path(f)
    if not p.exists():
        fails.append(f"missing {f}")
        continue
    s = str(p).replace("\\", "/")
    try:
        rel = str(p.resolve().relative_to(REPO.resolve())).replace("\\", "/")
    except ValueError:
        rel = "EXTERNAL/" + p.name
    if s.lower().endswith(".v.stale") or "/src/src/" in s or "peer-ref-2a4b253" in s:
        fails.append(f"guarded path {f}")
    if "integrated_delivery/algo_rowwin3_p4.v" in s or "integrated_delivery/gray8_gaussian3x3_stream_p4.v" in s:
        fails.append(f"rejected r3-era path {f}")
    if p.suffix.lower() in (".bit", ".cwc"):
        fails.append(f"bitstream/cwc in filelist {f}")
    h = hashlib.sha256(p.read_bytes()).hexdigest().upper()
    if h in REJECTED_SHA:
        fails.append(f"rejected r3-era SHA {f}")
    sha_rows.append({"path": rel, "sha256": h, "size": p.stat().st_size})
    if p.suffix.lower() == ".v":
        for name in re.findall(r"(?m)^\s*module\s+(\w+)", p.read_text(errors="replace")):
            if name in mods:
                fails.append(f"duplicate module {name}: {mods[name]} and {s}")
            else:
                mods[name] = s

# include resolution: every `include in a listed Verilog source must resolve
for f in list(files):
    p = Path(f)
    if p.suffix.lower() != ".v":
        continue
    try:
        txt = p.read_text(errors="replace")
    except OSError:
        continue
    for inc in re.findall(r'`include\s+"([^"]+)"', txt):
        target = (p.parent / inc).resolve()
        if not target.exists():
            fails.append(f"include missing {inc} from {f}")

out = PKG / "build" / "filelist-sha256.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps({
    "task_id": "T11.BRD.P1",
    "round": 3,
    "repo_relative": True,
    "path_basis": "relative to the repository root (no absolute paths, no T:/Y:)",
    "filelist_tcl": "handoff/brd-p1-r3-20261027/filelist.tcl",
    "filelist_tcl_sha256": hashlib.sha256(FL.read_bytes()).hexdigest().upper(),
    "source_count": len(files),
    "files": sha_rows,
}, indent=2) + "\n")

print(f"BRD_FILELIST_COUNT={len(files)}")
print(f"MISSING={sum(1 for x in fails if x.startswith('missing'))}")
print(f"DUP_MODULES={sum(1 for x in fails if x.startswith('duplicate'))}")
print(f"REJECTED_FILES={sum(1 for x in fails if 'r3-era' in x)}")
print(f"GUARD_FAILURES={len(fails)}")
for x in fails:
    print("FAIL " + x)
print("FILELIST_SHA_JSON=" + str(out))
print("CHECK_FILELIST=" + ("PASS" if not fails else "FAIL"))
sys.exit(0 if not fails else 1)
