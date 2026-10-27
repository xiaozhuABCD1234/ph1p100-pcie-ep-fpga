"""Round1 tester provenance/whitelist check (tester-owned, read-only on the candidate).

1. manifest-r0 / manifest-r1 SHA + every artifact hash (each manifest independently).
2. r0 artifacts unchanged between the two manifests (same rel path -> same sha).
3. independent unified diff tb_ss_4run.v -> tb_ss_4run_wd.v (difflib, n=2).
4. independent whitelist reconstruction: apply ONLY the 5 ruled changes to the r0
   text with my own literal patterns, then byte-compare with the actual r1 TB.
5. 12 DUT sources vs P4 frozen dir (byte identity).
6. dup semantics excerpt from a1_ddr_slot_store.v.
"""
import difflib, hashlib, json, os, re

RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"
P4 = r"D:\fpga\ph1p100\workflow\runs\20261025-233401_fpga-steady-state-reverdict\T10.ss-4run-matrix\r0\src"


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


res = {}
m0p = os.path.join(RUN, "manifest-r0.json")
m1p = os.path.join(RUN, "manifest-r1.json")
res["manifest_sha"] = {"r0": sha(m0p), "r1": sha(m1p)}
m0 = json.load(open(m0p))
m1 = json.load(open(m1p))
res["r0_expected"] = "e55e79659981e3a7f87696aec67d46b02011c3d8fe527c4ecdaf7b39553d9a74"
res["r1_expected"] = "e306ed42ed47dbcec6127bf2faee88925a9a88ae8a5ef07ecbda8dda91fe1fd9"


def check(m, tag):
    bad = []
    for a in m["artifacts"]:
        p = a["path"]
        if not os.path.exists(p):
            bad.append((a["rel"], "MISSING"))
        elif sha(p) != a["sha256"] or os.path.getsize(p) != a["bytes"]:
            bad.append((a["rel"], "DRIFT"))
    return dict(n=len(m["artifacts"]), bad=bad)


res["r0_artifacts"] = check(m0, "r0")
res["r1_artifacts"] = check(m1, "r1")
res["r1_flags"] = dict(stopped_modifying=m1["stopped_modifying"],
                       active_commands=m1["active_commands"],
                       previous_manifest=m1["previous_manifest"]["sha256"],
                       prev_unchanged=m1["previous_manifest"]["unchanged"],
                       repair_scope=m1["repair_scope"])
# r0 files must be untouched by round1 -> same sha in both manifests
d0 = {a["rel"]: a["sha256"] for a in m0["artifacts"]}
d1 = {a["rel"]: a["sha256"] for a in m1["artifacts"]}
res["overlap"] = dict(n=len(set(d0) & set(d1)),
                      changed=[k for k in set(d0) & set(d1) if d0[k] != d1[k]])
res["new_in_r1"] = sorted(set(d1) - set(d0))

# --- diff ---
a = open(os.path.join(RUN, "src", "tb_ss_4run.v"), encoding="utf-8").read().splitlines(keepends=True)
b = open(os.path.join(RUN, "src", "tb_ss_4run_wd.v"), encoding="utf-8").read().splitlines(keepends=True)
diff = list(difflib.unified_diff(a, b, "tb_ss_4run.v(r0)", "tb_ss_4run_wd.v(r1)", n=2))
res["diff_lines"] = len(diff)
res["diff"] = "".join(diff)
added = [l for l in diff if l.startswith("+") and not l.startswith("+++")]
removed = [l for l in diff if l.startswith("-") and not l.startswith("---")]
res["added"] = len(added)
res["removed"] = len(removed)

# --- whitelist reconstruction (my own literal patterns) ---
r0s = "".join(a)
canon = r0s
p1_old = "    localparam integer WD_LIMIT = 12000000;\n"
p1_new = ("    localparam integer WD_LIMIT = 12000000;\n"
          "    localparam integer WD_LIMIT_COLD = 20000000;   // round1: cold-start budget, anchored at t_sof(1)\n")
p4_old = ('                $display("SS_EVT t=%0d kind=exp frame=%0d n=%0d", cycles, st_exp, st_exp);\n'
          '                if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=exp frame=%0d n=%0d\\n", cycles, st_exp, st_exp);\n')
p4_new = ('                $display("SS_EVT t=%0d kind=exp frame=%0d n=%0d bytes=%0d", cycles, st_exp, st_exp, st_expb);\n'
          '                if (fe != 0) $fwrite(fe, "SS_EVT t=%0d kind=exp frame=%0d n=%0d bytes=%0d\\n", cycles, st_exp, st_exp, st_expb);\n')
p23_old = ("            // ---- per-frame watchdog (12,000,000 cycles with no export) ----\n"
           "            if ((cycles - last_exp_t) > WD_LIMIT) begin\n")
p23_new = ("            // ---- two-stage watchdog (round1 harness fix; whitelist items 2 and 3) ----\n"
           "            //  cold start: anchored at t_sof(1) while nothing has been exported yet\n"
           "            //  steady state: original 12,000,000-cycle gap between completed exports\n"
           "            if ((st_exp == 0) && ((cycles - t_sof[1]) > WD_LIMIT_COLD)) begin\n"
           '                $display("SS_STALL_COLD frame=%0d cycles=%0d read=%0d enc=%0d exported=%0d",\n'
           "                         st_exp + 1, cycles, st_read, st_enc, st_exp);\n"
           '                $display("B11_FULL_RESULT pass=0");\n'
           "                $finish;\n"
           "            end\n"
           "            if ((st_exp > 0) && ((cycles - last_exp_t) > WD_LIMIT)) begin\n")
for old, new, tag in ((p1_old, p1_new, "item1"), (p4_old, p4_new, "item4"), (p23_old, p23_new, "item2+3")):
    cnt = canon.count(old)
    res.setdefault("reconstruct", {})[tag] = cnt
    canon = canon.replace(old, new)
actual = "".join(b)
res["reconstruct_equal"] = canon == actual
if canon != actual:
    d = list(difflib.unified_diff(canon.splitlines(), actual.splitlines(), "canonical", "actual", n=1))
    res["reconstruct_diff"] = "\n".join(d[:60])

# --- DUT sources vs P4 frozen ---
dut = {}
for fn in sorted(os.listdir(os.path.join(RUN, "src"))):
    if not fn.endswith(".v") or fn.startswith("tb_"):
        continue
    p = os.path.join(RUN, "src", fn)
    q = os.path.join(P4, fn)
    dut[fn] = dict(sha=sha(p)[:16], p4_same=(os.path.exists(q) and sha(q) == sha(p)))
res["dut_vs_p4"] = dut
res["tb_vs_p4_r0"] = (sha(os.path.join(RUN, "src", "tb_ss_4run.v")) == sha(os.path.join(P4, "tb_ss_4run.v")))

# --- dup semantics ---
src = open(os.path.join(RUN, "src", "a1_ddr_slot_store.v"), encoding="utf-8").read().splitlines()
hits = [(i + 1, l.rstrip()) for i, l in enumerate(src)
        if re.search(r"dup|281|282|st_dup", l, re.I)]
res["dup_excerpt"] = [f"{i}: {l}" for i, l in hits][:40]
res["dup_281_286"] = [f"{i}: {src[i - 1].rstrip()}" for i in range(276, 292)]

json.dump(res, open(os.path.join(OUT, "r1-provenance.json"), "w"), indent=2)
print(json.dumps({k: res[k] for k in ("manifest_sha", "r0_artifacts", "r1_artifacts", "r1_flags",
                                      "overlap", "new_in_r1", "added", "removed", "reconstruct",
                                      "reconstruct_equal")}, indent=1))
print("DUT vs P4:", "all_same" if all(v["p4_same"] for v in dut.values()) else [k for k, v in dut.items() if not v["p4_same"]],
      "n=", len(dut), "tb_r0_vs_p4:", res["tb_vs_p4_r0"])
print("=== DIFF ===")
print(res["diff"])
print("=== dup context (276-291) ===")
print("\n".join(res["dup_281_286"]))
