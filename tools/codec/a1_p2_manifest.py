#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Final P2 candidate manifest: absolute paths, SHA256, 0-mismatch recheck."""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
UP = os.path.join(PROJECT, "upstream", "ph1p100-pcie-ep-fpga")
RUN = os.path.join(PROJECT, "workflow", "runs", "20261020-0209_singleA_aplus_closedloop",
                   "T10.a1-enc-rtl", "p2")


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    files = []
    for base, dirs, fns in os.walk(RUN):
        dirs[:] = [d for d in dirs if not d.startswith("work")]
        for fn in fns:
            if fn.startswith("dbg") or fn in ("CANDIDATE-MANIFEST.json", "manifest-check.txt"):
                continue
            files.append(os.path.join(base, fn))
    for src in (
        os.path.join(UP, "rtl", "ep_side", "codec", "a1_deflate_core.v"),
        os.path.join(UP, "sim", "tb", "codec", "tb_a1_deflate_core.v"),
        os.path.join(HERE, "a1_p2_gen.py"),
        os.path.join(HERE, "a1_p2_verify.py"),
        os.path.join(HERE, "a1_p2_manifest.py"),
        os.path.join(HERE, "run_p2.ps1"),
        os.path.join(PROJECT, "workflow", "runs", "20261020-0209_singleA_aplus_closedloop",
                     "lessons", "T10.a1-enc-rtl-lessons.md"),
        os.path.join(RUN, "dev-result.md"),
        os.path.join(RUN, "dev-notes.md"),
    ):
        if os.path.isfile(src):
            files.append(src)
    files = sorted(set(os.path.abspath(p) for p in files))
    entries = []
    bad = 0
    for p in files:
        h = sha(p)
        if h != sha(p):
            bad += 1
        entries.append({"path": p, "sha256": h, "bytes": os.path.getsize(p)})
    body = "\n".join("%s  %s" % (e["sha256"], e["path"]) for e in entries)
    cid = hashlib.sha256(body.encode("utf-8")).hexdigest()
    man = {"task_id": "T10.a1-enc-rtl", "kind": "unique-candidate",
           "candidate_id": cid, "file_count": len(entries),
           "hash_mismatches": bad, "files": entries}
    with open(os.path.join(RUN, "CANDIDATE-MANIFEST.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, indent=1)
    verdict = json.load(open(os.path.join(RUN, "result.json"), "r", encoding="utf-8"))["verdict"]
    with open(os.path.join(RUN, "manifest-check.txt"), "w", encoding="utf-8") as f:
        f.write("candidate_id=%s\nfiles=%d\nhash_mismatches=%d\nresult_json_verdict=%s\n"
                % (cid, len(entries), bad, verdict))
    print(json.dumps({"candidate_id": cid, "files": len(entries),
                      "hash_mismatches": bad, "result_json_verdict": verdict}, indent=1))
    return 0 if (bad == 0 and verdict == "PASS") else 1


if __name__ == "__main__":
    sys.exit(main())
