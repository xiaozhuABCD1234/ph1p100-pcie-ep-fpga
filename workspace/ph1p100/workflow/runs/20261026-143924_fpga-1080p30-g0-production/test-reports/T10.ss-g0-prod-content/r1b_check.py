"""r1b gate-correction re-check: frozen manifests, candidate immutability, no rerun.

Read-only. Writes only test-reports/.../r1b-frozen-check.json.
"""
import hashlib, json, os, time

RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
P4 = r"D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-4run-matrix\r0\src"


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


res = {"checked_at": time.strftime("%Y-%m-%dT%H:%M:%S")}
for tag in ("r0", "r1"):
    p = os.path.join(RUN, "manifest-%s.json" % tag)
    m = json.load(open(p))
    bad = []
    for a in m["artifacts"]:
        q = a["path"]
        if not os.path.exists(q):
            bad.append((a["rel"], "MISSING"))
        elif sha(q) != a["sha256"] or os.path.getsize(q) != a["bytes"]:
            bad.append((a["rel"], "DRIFT"))
    res[tag] = dict(manifest_sha256=sha(p), count=len(m["artifacts"]), drift=bad,
                    stopped_modifying=m.get("stopped_modifying"),
                    active_commands=m.get("active_commands"))

prev = json.load(open(os.path.join(OUT, "r1-tester-verify.json")))
res["matches_r1_verification"] = {
    "r0": prev["r0"]["manifest_sha256"] == res["r0"]["manifest_sha256"],
    "r1": prev["r1"]["manifest_sha256"] == res["r1"]["manifest_sha256"],
}

# candidate immutability: no r1b artifacts, r1 evidence mtimes/logs untouched, TB hashes
caps = sorted(os.path.basename(p) for p in
              __import__("glob").glob(os.path.join(RUN, "sim", "caps", "*")))
res["caps_files"] = caps
res["new_r1b_artifacts"] = [c for c in caps if "r1b" in c.lower()]
res["r1_evidence_mtime"] = {f: time.strftime("%Y-%m-%d %H:%M:%S",
                                             time.localtime(os.stat(os.path.join(RUN, "sim", "caps", f)).st_mtime))
                            for f in caps if f.startswith(("n-r1", "l-r1"))}
res["tb_sha"] = {f: sha(os.path.join(RUN, "src", f)) for f in ("tb_ss_4run.v", "tb_ss_4run_wd.v")}
res["tb_expected"] = {"tb_ss_4run.v": "7f5cc29405001e4a5da868e8129819e0068715965999c7e81082e38e20947f81",
                      "tb_ss_4run_wd.v": "785c3ef1d044f8529b7232ae37ed3a67172b6c4cd512c47a713103675090b79a"}
res["tb_ok"] = all(res["tb_sha"][k] == v for k, v in res["tb_expected"].items())
res["dut_vs_p4"] = {f: sha(os.path.join(RUN, "src", f)) == sha(os.path.join(P4, f))
                    for f in os.listdir(os.path.join(RUN, "src"))
                    if f.endswith(".v") and not f.startswith("tb_")}
res["dut_all_same"] = all(res["dut_vs_p4"].values())
# a1_ddr_slot_store.v dup semantics lines (unchanged since r0)
lines = open(os.path.join(RUN, "src", "a1_ddr_slot_store.v"), encoding="utf-8").read().splitlines()
res["dup_src"] = {i: lines[i - 1].rstrip() for i in range(280, 285)}
res["dup_src_sha"] = sha(os.path.join(RUN, "src", "a1_ddr_slot_store.v"))

json.dump(res, open(os.path.join(OUT, "r1b-frozen-check.json"), "w"), indent=2)
print(json.dumps(res, indent=1))
