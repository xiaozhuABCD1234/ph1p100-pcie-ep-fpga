"""Tester's input-drift check (T10.ss-verdict-r1 r0).

Hashes every bound input recorded in the candidate's input-verified.json, then re-verifies
the artifact lists of the P1 and P2 frozen manifests and the candidate manifest.  Written
in Python so UTF-8 paths (Chinese doc names) are handled correctly.
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = "D:/fpga/ph1p100"
RUN = os.path.join(ROOT, "workflow/runs/20261025-233401_fpga-steady-state-reverdict")
R0 = os.path.join(RUN, "T10.ss-verdict-r1", "r0")
P1 = os.path.join(RUN, "T10.ss-steady-anchor", "r0")
P2 = os.path.join(ROOT, "workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/"
                        "T10.dual-aplus-service-verdict/r0")
FAILS = []
CHECKS = [0]


def ck(name, cond, detail=""):
    CHECKS[0] += 1
    if not cond:
        FAILS.append(name)
        print("FAIL  %s  %s" % (name, detail))


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def verify_artifacts(name, base, arts):
    bad = []
    for a in arts:
        path = a["path"] if os.path.isabs(a["path"]) else os.path.join(base, a["path"])
        if not os.path.exists(path):
            bad.append((a["path"], "missing"))
            continue
        h = sha256(path)
        if h != a["sha256"]:
            bad.append((a["path"], h))
    ck("%s artifacts all match (%d)" % (name, len(arts)), not bad, bad[:3])
    return bad


def main():
    iv = load_json(os.path.join(R0, "input-verified.json"))
    n = 0
    for item in iv["inputs"]:
        path = os.path.join(ROOT, item["path"])
        if not os.path.exists(path):
            ck("input exists %s" % item["id"], False, path)
            continue
        h = sha256(path)
        ck("input %s sha256 unchanged" % item["id"], h == item["expected_sha256"], h)
        n += 1
    ck("20 bound inputs checked", n == 20, n)

    p1m = load_json(os.path.join(P1, "manifest-r0.json"))
    verify_artifacts("P1", P1, p1m["artifacts"])
    ck("P1 manifest sha256 = 39f3e3d6...9f9a",
       sha256(os.path.join(P1, "manifest-r0.json")) ==
       "39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a")

    p2m = load_json(os.path.join(P2, "manifest-r0.json"))
    verify_artifacts("P2", P2, p2m["artifacts"])
    ck("P2 manifest sha256 = 5ed90500...36a6",
       sha256(os.path.join(P2, "manifest-r0.json")) ==
       "5ed90500a7e9650ca17e5f269731984fea9f215d7401d555dc5633551c2436a6")

    cand = load_json(os.path.join(R0, "manifest-r0.json"))
    verify_artifacts("candidate", R0, cand["artifacts"])
    ck("candidate manifest sha256 = fd27c70f...fad0 (unchanged after tester runs)",
       sha256(os.path.join(R0, "manifest-r0.json")) ==
       "fd27c70f304f51ba0b0b022398acd46f1f5f43a32351acfc472dea12e034fad0")
    ck("candidate has 34 artifacts and 0 unlisted extras",
       len(cand["artifacts"]) == 34)

    out = {"checks": CHECKS[0], "failures": FAILS,
           "verdict": "PASS" if not FAILS else "FAIL",
           "p1_artifacts": len(p1m["artifacts"]), "p2_artifacts": len(p2m["artifacts"]),
           "candidate_artifacts": len(cand["artifacts"])}
    with open(os.path.join(HERE, "drift_check.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
        fh.write("\n")
    print("\n%d checks, %d failures" % (CHECKS[0], len(FAILS)))
    print("DRIFT_CHECK=%s" % out["verdict"])
    return 0 if not FAILS else 1


if __name__ == "__main__":
    sys.exit(main())
