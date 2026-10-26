"""Copy the existing project into the user-designated FPGA repository.

No deletion, Git publication, build, hardware access, or candidate rewriting.
Generated bulk artifacts stay local and are indexed as exclusions.
"""
from pathlib import Path
import collections
import datetime
import hashlib
import json
import os
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8")
SOURCE = Path(r"D:\fpga\ph1p100")
DEST = Path(r"D:\fpga\repos\ph1p100-pcie-ep-fpga")
SUBREPO = SOURCE / "upstream/ph1p100-pcie-ep-fpga"
PREFIX = Path("workspace/ph1p100")
STARTED = datetime.datetime.now(datetime.timezone.utc).isoformat()
RECORDS, EXCLUDED, ERRORS = [], [], []
PRUNE = {".git", ".git_empty_old", "__pycache__", "node_modules", ".venv",
         "venv", "target", "work", "backup", "backups", "_scratch",
         "obj_dir", "questa_lib", "modelsim_lib", "vsimlib", "restored-tracked-worktree"}
TEXT = {".md", ".txt", ".json", ".jsonl", ".csv", ".xml", ".yaml", ".yml",
        ".toml", ".py", ".ps1", ".psm1", ".sh", ".bat", ".cmd", ".v", ".sv",
        ".vh", ".svh", ".vhd", ".vhdl", ".tcl", ".sdc", ".adc", ".al", ".f",
        ".do", ".flist", ".c", ".h", ".cpp", ".hpp", ".rs", ".lock", ".cfg",
        ".ini", ".rpt", ".diff", ".patch", ".stats", ".evt", ".hdr", ".log",
        ".out", ".err", ".stdout", ".stderr"}
ASSETS = {".png", ".jpg", ".jpeg", ".svg", ".pdf", ".docx", ".dma", ".a1u1"}


def omitted(path, reason, size=None):
    EXCLUDED.append(dict(source=str(path.relative_to(SOURCE)).replace("\\", "/"),
                         reason=reason, bytes=size))


def copy_file(src, relative, group):
    relative = Path(relative)
    reserved = {"con", "prn", "aux", "nul"} | {f"{p}{n}" for p in ("com", "lpt") for n in range(1, 10)}
    relative = Path(*(f"_portable_{p}" if p.split(".")[0].lower() in reserved else p for p in relative.parts))
    target = DEST / relative
    if not target.resolve().is_relative_to(DEST.resolve()):
        raise ValueError("destination outside the designated repository")
    data = None
    for attempt in range(2):
        try:
            before = src.stat()
            value = src.read_bytes()
            after = src.stat()
        except OSError as error:
            ERRORS.append(dict(source=str(src), error=str(error)))
            return
        if before.st_size == len(value) == after.st_size and before.st_mtime_ns == after.st_mtime_ns:
            data = value
            break
    if data is None:
        omitted(src, "actively changing during both bounded reads")
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
    sha = hashlib.sha256(data).hexdigest()
    if hashlib.sha256(target.read_bytes()).hexdigest() != sha:
        raise ValueError("copy verification failed: " + str(relative))
    RECORDS.append(dict(source=src.relative_to(SOURCE).as_posix(),
                        destination=relative.as_posix(), group=group, bytes=len(data),
                        sha256=sha, lf_sha256=hashlib.sha256(data.replace(b"\r\n", b"\n")).hexdigest(),
                        source_mtime_ns=after.st_mtime_ns))


def permitted(src, rel):
    parts = [x.lower() for x in rel.parts]
    name, ext = src.name.lower(), src.suffix.lower()
    size = src.stat().st_size
    if name.startswith(".env") or ext in {".lic", ".key", ".pem", ".pfx", ".p12"}:
        return False, "credential or local configuration filename"
    if ext in {".pyc", ".pyo", ".db", ".wlf", ".vcd", ".fst", ".dmp", ".exe", ".dll", ".o", ".ko"}:
        return False, "cache, compiled output, wave, database or dump"
    in_run = parts[:2] == ["workflow", "runs"]
    if in_run and (ext in {".hex", ".mem", ".dec", ".bit", ".cwc", ".bid"}):
        return False, "generated run vector or duplicate bit; selected current bits are copied separately"
    if ext == ".bin":
        allow = parts[0] == "parallel" or ("board" in parts and any(p.startswith("captures") for p in parts))
        return (allow and size <= 5 * 1024 * 1024), "generated binary; real small board captures and reference fixtures only"
    if ext in TEXT or ext in ASSETS or name in {"makefile", ".gitignore", ".gitattributes", "sha256sums", "path_contract"}:
        limit = 256 * 1024 if ext in {".rpt", ".log", ".out", ".err", ".stdout", ".stderr"} else 20 * 1024 * 1024
        if size > limit:
            return False, "large generated report/vector/asset; keep local source and existing manifest"
        return True, ""
    if not in_run and ext in {".hex", ".mem"} and size <= 2 * 1024 * 1024:
        return True, ""
    return False, "not a source/configuration/document/small evidence file"


def copy_tree(dirname):
    base = SOURCE / dirname
    if not base.exists():
        return
    for here, dirs, names in os.walk(base, followlinks=False,
                                     onerror=lambda e: ERRORS.append(dict(source=str(e.filename), error=str(e)))):
        here = Path(here)
        rel_here = here.relative_to(SOURCE)
        kept = []
        for name in dirs:
            p = here / name
            rel = p.relative_to(SOURCE)
            parts = [x.lower() for x in rel.parts]
            reason = ""
            if name.lower() in PRUNE or name.endswith("_Runs") or name.startswith("out-") or name == "out":
                reason = "cache/build/backup or reproducible decoder output directory"
            elif p.is_symlink():
                reason = "nested link; root docs junction is copied by explicit entry"
            elif parts[:2] == ["workflow", "runs"] and "td" in parts and name.lower() in {"src", "vendor", "ip", "output", "export"}:
                reason = "generated/copied TD vendor tree; canonical IP and source candidates are retained separately"
            if reason:
                omitted(p, reason)
            else:
                kept.append(name)
        dirs[:] = kept
        for name in names:
            src = here / name
            rel = src.relative_to(SOURCE)
            try:
                ok, reason = permitted(src, rel)
                if ok:
                    copy_file(src, PREFIX / rel, "workspace_snapshot")
                else:
                    omitted(src, reason, src.stat().st_size)
            except OSError as error:
                ERRORS.append(dict(source=str(src), error=str(error)))


def main():
    if subprocess.check_output(["git", "-C", str(DEST), "remote", "get-url", "origin"], text=True).strip() != "https://github.com/xiaozhuABCD1234/ph1p100-pcie-ep-fpga.git":
        raise ValueError("wrong destination remote")
    changed = subprocess.check_output(["git", "-C", str(SUBREPO), "diff", "--name-only", "-z", "HEAD"]).split(b"\0")
    extra = subprocess.check_output(["git", "-C", str(SUBREPO), "ls-files", "--others", "--exclude-standard", "-z"]).split(b"\0")
    for raw in sorted(set(changed + extra)):
        if not raw:
            continue
        rel = Path(os.fsdecode(raw)); src = SUBREPO / rel
        if "__pycache__" in rel.parts or src.suffix in {".pyc", ".out", ".err"}:
            omitted(src, "generated local lint/cache output")
        elif src.is_file():
            copy_file(src, rel, "fpga_native_source_update")
    protocol = SUBREPO / "docs/protocol/rka1-r10f-v1"
    for src in protocol.rglob("*"):
        if src.is_file():
            copy_file(src, src.relative_to(SUBREPO), "protocol_byte_preservation")
    for dirname in ("fpga", "tools", "docs", "workflow", "parallel", ".agents", ".opencode", "specs", "test-reports", "handoff"):
        copy_tree(dirname)
    for src in SOURCE.iterdir():
        if src.is_file() and (src.suffix.lower() in TEXT or src.name in {".gitignore", ".gitattributes"}):
            ok, reason = permitted(src, Path(src.name))
            if ok:
                copy_file(src, PREFIX / src.name, "workspace_entry")
            else:
                omitted(src, reason, src.stat().st_size)
    handoff = SOURCE / "handoff/rk-a1u1-b18-20261026"
    for src in handoff.rglob("*"):
        if src.is_file() and not any(x.startswith("out") or x == "__pycache__" for x in src.relative_to(handoff).parts):
            copy_file(src, src.relative_to(SOURCE), "portable_rk_handoff")
    for package in ("T10.b18-b17-b", "T10.b20-a-timing"):
        base = SOURCE / "workflow/runs/20261020-0209_singleA_aplus_closedloop" / package / "r0/td"
        for name in ("a1_board.bit", "a1_board.cwc", "a1_board_inst.bid"):
            src = base / name
            if src.is_file():
                copy_file(src, Path("artifacts") / package / name, "existing_bit_not_new_hardware_validation")
    summary = dict(started_utc=STARTED, finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   source_root=str(SOURCE), destination_repository="xiaozhuABCD1234/ph1p100-pcie-ep-fpga",
                   files=len(RECORDS), bytes=sum(x["bytes"] for x in RECORDS),
                   groups=dict(collections.Counter(x["group"] for x in RECORDS)),
                   notes=["Point-in-time file copies; not a unified implementation or hardware PASS.",
                          "Original manifests are preserved; omitted generated files remain at source.",
                          "lf_sha256 permits only Git's configured CRLF-to-LF text normalization for native paths; workspace/artifacts use byte-preserving attributes."],
                   records=RECORDS)
    docs = DEST / "docs"; docs.mkdir(exist_ok=True)
    (docs / "sync-20261027-manifest.json").write_bytes((json.dumps(summary, ensure_ascii=False, indent=2) + "\n").encode())
    (docs / "sync-20261027-exclusions.json").write_bytes((json.dumps(dict(excluded=EXCLUDED, errors=ERRORS), ensure_ascii=False, indent=2) + "\n").encode())
    (DEST / ".gitattributes").write_bytes(b"workspace/** -text\nartifacts/** -text\nhandoff/** -text\ndocs/protocol/** -text\n")
    print(json.dumps({k: v for k, v in summary.items() if k != "records"}, ensure_ascii=False))
    print(json.dumps(dict(exclusions=len(EXCLUDED), errors=len(ERRORS)), ensure_ascii=False))
    if ERRORS:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
