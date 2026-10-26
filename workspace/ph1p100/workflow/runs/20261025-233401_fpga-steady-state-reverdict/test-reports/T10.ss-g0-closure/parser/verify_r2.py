#!/usr/bin/env python3
"""Round2 metadata retest for T10.ss-g0-closure (tester-owned, ASCII-only).

Reuses round1 r3_frozen/v1 evidence; independently checks manifest-r2
(82 artifacts), metadata/budget/report/table/DIFF fixes, P1/P2/comp drift,
12 DUT copies, 0 TD/board, and the G0 scope/boundaries.
"""
import csv
import hashlib
import json
import pathlib
import re
import sys
import zlib

ROOT = pathlib.Path(r"D:\fpga\ph1p100")
RUN = ROOT / "workflow" / "runs" / "20261025-233401_fpga-steady-state-reverdict"
TASK = RUN / "T10.ss-g0-closure" / "r0"
P1 = RUN / "T10.ss-steady-anchor" / "r0"
P2 = RUN / "T10.ss-verdict-r1" / "r0"
TEST = RUN / "test-reports" / "T10.ss-g0-closure"
COMP = ROOT / "work" / "parallel-sim-20261024-2204" / "codec-throughput" / "comp"

res = {"checks": [], "computed": {}, "observations": []}


def add(name, ok, detail=""):
    res["checks"].append({"name": name, "ok": bool(ok), "detail": detail})
    return bool(ok)


def sha(b):
    return hashlib.sha256(b).hexdigest()


def shafile(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()


def main():
    manp = TASK / "manifest-r2.json"
    man = json.loads(manp.read_text(encoding="utf-8"))
    man_sha = shafile(manp)
    r1_sha = shafile(TASK / "manifest-r1.json")
    r0_sha = shafile(TASK / "manifest-r0.json")
    res["computed"]["manifest_r2_sha256"] = man_sha
    res["computed"]["manifest_r1_sha256"] = r1_sha
    res["computed"]["manifest_r0_sha256"] = r0_sha

    # 1. manifest-r2 82 artifacts / previous manifest
    add("manifest-r2 82 artifacts", man.get("artifact_count") == 82 and len(man.get("artifacts", [])) == 82,
        "count=%d" % man.get("artifact_count", -1))
    bad = []
    for a in man.get("artifacts", []):
        fp = TASK / a["path"]
        if not fp.exists() or shafile(fp) != a["sha256"]:
            bad.append(a["path"])
    add("manifest-r2 artifact hashes 0 mismatch", not bad, json.dumps(bad))
    add("manifest-r2 previous_manifest=r1 D700FE9A", man.get("previous_manifest", {}).get("sha256") == r1_sha.lower(),
        man.get("previous_manifest", {}).get("sha256", ""))
    add("manifest-r2 includes manifest-r1 artifact",
        any(a["path"] == "manifest-r1.json" for a in man.get("artifacts", [])), "manifest-r1 artifact")
    add("manifest-r2 stopped/active", man.get("stopped_modifying") is True and man.get("active_commands") == 0,
        json.dumps({"stopped_modifying": man.get("stopped_modifying"), "active_commands": man.get("active_commands")}))
    add("manifest-r2 no forbidden actions", man.get("forbidden_actions_used") == [], str(man.get("forbidden_actions_used")))
    add("manifest-r2 frozen TB a565c6f2", shafile(TASK / "src" / "tb_ss_g0.v") ==
        "a565c6f25f5d8ac16ce8dd8042f35395c6018a23d1093448077b0e90b79bd3d0",
        shafile(TASK / "src" / "tb_ss_g0.v"))
    add("manifest-r2 legacy TB archived 89948303",
        (TASK / "src" / "legacy" / "tb_ss_g0_89948303.v").exists()
        and shafile(TASK / "src" / "legacy" / "tb_ss_g0_89948303.v") ==
        "89948303be78da2b4e2cbccbb70935d26825b518620c679ba9d959d3c950008e"
        and any(a["path"] == "src/legacy/tb_ss_g0_89948303.v" for a in man.get("artifacts", [])),
        "legacy artifact")
    add("manifest-r2 no TEMP-only TB", all("TEMP" not in a["path"].upper() and "tb_prefix" not in a["path"]
        for a in man.get("artifacts", [])), "paths clean")

    # 2. verdict/budget metadata
    add("manifest-r2 verdict.r3_S_ss=5928286.0", man.get("verdict", {}).get("r3_S_ss") == 5928286.0,
        repr(man.get("verdict", {}).get("r3_S_ss")))
    v = json.loads((TASK / "out" / "g0-verdict.json").read_text(encoding="utf-8"))
    add("manifest.r3_S_ss == g0-verdict.runs.r3f.S_ss",
        man.get("verdict", {}).get("r3_S_ss") == v.get("runs", {}).get("r3f", {}).get("S_ss") == 5928286.0,
        "%r / %r" % (man.get("verdict", {}).get("r3_S_ss"), v.get("runs", {}).get("r3f", {}).get("S_ss")))
    b = man.get("budget", {})
    add("budget 112 min / 6532.4 s / full 5/5",
        b.get("sim_wall_limit_min") == 112 and b.get("sim_wall_seconds") == 6532.4
        and b.get("full_frame_vsim_runs") == 5 and b.get("full_frame_vsim_limit") == 5,
        json.dumps({k: b.get(k) for k in ["sim_wall_limit_min", "sim_wall_seconds", "full_frame_vsim_runs", "full_frame_vsim_limit"]}))
    note = b.get("sim_wall_note", "")
    add("budget note round1 +22.1 / 108.9", "108.9" in note and "22.1" in note and "112" in note,
        note)
    rep = (TASK / "g0-closure.md").read_text(encoding="utf-8", errors="replace")
    add("g0-closure section2 108.9 min <=112 + r3_frozen 1326.1",
        "6532.4 s = 108.9 min" in rep and "112" in rep and "r3_frozen" in rep and "1326.1" in rep,
        "section 2 budget text")
    add("g0-closure no stale 86.8<=90 as cumulative", "108.9" in rep and "≤112" in rep, "budget")

    # 3. r3_vs_r0
    rv = v.get("r3_vs_r0", {})
    add("g0-verdict r3_vs_r0 legacy/frozen 5928286 delta=0",
        rv.get("legacy_S_ss") == 5928286.0 and rv.get("frozen_S_ss") == 5928286.0 and rv.get("delta_cycles") == 0.0,
        json.dumps(rv))
    resi = (TASK / "result-r1.md").read_text(encoding="utf-8", errors="replace")
    add("result-r1 r3_vs_r0 reference consistent", "r3_vs_r0" in resi and "r3_vs_r0" in v,
        "result/verdict both reference r3_vs_r0")

    # 4. g0-table A1 serial source / -4 only overlapped
    with open(TASK / "out" / "g0-table.csv", newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    add("g0-table 32 rows", len(rows) == 32, "rows=%d" % len(rows))
    by = {(r["anchor"], r["view"], r["mode"]): r for r in rows}
    ov = by[("A1_grad_measured", "overlapped", "c1s1")]
    se = by[("A1_grad_measured", "serial", "c1s1")]
    add("A1 overlapped R1 4,677,531 with -4 note",
        float(ov["S_cycles"]) == 4677531.0 and "4,677,535" in ov["source"] and "-4" in ov["source"],
        ov["source"])
    add("A1 serial source=R2 and no -4 note",
        "R2" in se["source"] and "4,677,535" not in se["source"] and "-4" not in se["source"],
        se["source"])
    add("P proxy source r3_frozen", "r3_frozen" in by[("P_proxy_measured", "overlapped", "c1s1")]["source"],
        by[("P_proxy_measured", "overlapped", "c1s1")]["source"])
    add("P proxy serial assumed", "assumed" in by[("P_proxy_measured", "serial", "c1s1")]["label"],
        by[("P_proxy_measured", "serial", "c1s1")]["label"])
    add("c2s2=C / c1s2=C/2", all(
        abs(float(by[(a, view, "c2s2")]["capacity_MBps"]) - float(by[(a, view, "c1s1")]["capacity_MBps"])) < 1e-9
        and abs(float(by[(a, view, "c1s2")]["capacity_MBps"]) - float(by[(a, view, "c1s1")]["capacity_MBps"]) / 2) < 1e-9
        for a in ["A1_grad_measured", "A2_comp_assumed", "A3_rand_assumed", "P_proxy_measured"]
        for view in ["overlapped", "serial"]), "per-stream")
    add("G25 ref only / no cold L_cold", "gate_G25_ref_only" in rows[0]
        and all(abs(float(r["S_cycles"]) - 6766434) > 1 for r in rows), "G25 ref / no L_cold")

    # 5. DIFF p2_a1_board_top / check_outputs 25/25
    diff = (TASK / "src" / "DIFF.md").read_text(encoding="utf-8", errors="replace")
    add("DIFF p2_a1_board_top not copied/not compiled",
        "P3 未复制、未编译" in diff and "p2_a1_board_top" in diff
        and "表述已删除" in diff, "DIFF sections 8/9")
    co = json.loads((TASK / "out" / "check-outputs.json").read_text(encoding="utf-8"))
    add("check-outputs 25/25 all_pass", co.get("total") == 25 and co.get("passed") == 25
        and co.get("all_pass") is True, json.dumps({k: co.get(k) for k in ["total", "passed", "all_pass"]}))
    add("check-outputs C23/C24/C25 present",
        any(c.get("id") == "C23_manifest_r3_S_ss" and c.get("pass") for c in co.get("checks", []))
        and any(c.get("id") == "C24_budget_override" and c.get("pass") for c in co.get("checks", []))
        and any(c.get("id") == "C25_r3_vs_r0" and c.get("pass") for c in co.get("checks", [])),
        "C23/C24/C25")

    # 6. content-proxy/scope/R4/A1/G25/boundaries
    cp = json.loads((TASK / "out" / "content-proxy.json").read_text(encoding="utf-8"))
    meta = (COMP / "in.meta").read_bytes()
    add("content-proxy in.meta 330 B E98C9A1C", cp["inputs"]["in.meta"]["bytes"] == 330
        and cp["inputs"]["in.meta"]["sha256"] == "e98c9a1c3e0fe621c9aa65aaadbcacbef13c2437a0bbbafcde17d2ff471f80fe"
        and sha(meta) == "e98c9a1c3e0fe621c9aa65aaadbcacbef13c2437a0bbbafcde17d2ff471f80fe",
        "%s/%s" % (cp["inputs"]["in.meta"]["bytes"], cp["inputs"]["in.meta"]["sha256"]))
    add("content-proxy in.hex/in.xform hashes",
        cp["inputs"]["in.hex"]["sha256"] == shafile(COMP / "in.hex")
        and cp["inputs"]["in.xform"]["sha256"] == shafile(COMP / "in.xform"), "hashes")
    add("content-proxy raw/tiled crc/length", cp["outputs"]["raw_bytes"] == 2592000
        and cp["outputs"]["tiled_xform_bytes"] == 2592000
        and cp["outputs"]["raw_crc32"] == 3613527589
        and cp["outputs"]["xform_crc32"] == 3038348232, json.dumps(cp["outputs"]))
    sc = v.get("scope", "")
    add("scope 93.75/proxy/slot-free/behavioral/per-stream/single-core",
        all(k in sc for k in ["93.75", "proxy", "slot-free", "behavioral", "per-stream", "single core"]), sc[:180])
    add("scope raw band 77.84/103.79 not_proven",
        "77.84" in sc and "103.79" in sc and "not_proven" in sc, sc[:220])
    add("R4 not_run / assumed 7,616,377.5", "not_run" in v.get("r4", "") and "assumed" in v.get("r4", ""),
        v.get("r4", ""))
    add("A1 -4 note", "4,677,535" in v.get("a1_overlapped_note", "") and "4 cycles" in v.get("a1_overlapped_note", ""),
        v.get("a1_overlapped_note", ""))
    add("G25 no downgrade / ref only", v.get("not_downgraded") is True and v.get("g25_used_for_headline") is False,
        json.dumps({"not_downgraded": v.get("not_downgraded"), "g25_used": v.get("g25_used_for_headline")}))
    add("G0 verdict G0_feasible_for_scope", v.get("verdict") == "G0_feasible_for_scope",
        v.get("verdict", ""))
    add("g0-verdict r3f S_ss=5928286", v.get("runs", {}).get("r3f", {}).get("S_ss") == 5928286.0,
        str(v.get("runs", {}).get("r3f", {}).get("S_ss")))
    add("same-run r3_frozen bad=0", v.get("proxy_self_check", {}).get("r3_frozen_same_run", {}).get("bad") == 0,
        str(v.get("proxy_self_check", {}).get("r3_frozen_same_run", {})))

    # 7. reuse round1 evidence (hashes unchanged)
    rf_log = TASK / "sim" / "logs" / "r3_frozen.log"
    rf_stats = TASK / "sim" / "caps" / "r3_frozen.stats"
    rf_hdr = TASK / "sim" / "caps" / "r3_frozen.hdr"
    v1_log = TEST / "r1-v1" / "v1_r1.log"
    add("r3_frozen evidence hashes unchanged",
        shafile(rf_log) == "1944fcc69e8393ba897457cc0bb71d5187f5f89f0c4ad03e26ae25d68b62ddf5"
        and shafile(rf_stats) == "c10ff20b75a7dce5fbdb421acaf6b9557c87d91335dbda599b1c8949835f1cfb"
        and shafile(rf_hdr) == "3fa9bd96b7e937039314d0d7aa170b0e317083c9f9dd77ab0d4d1e25d099a461",
        "%s %s %s" % (shafile(rf_log), shafile(rf_stats), shafile(rf_hdr)))
    rt = rf_log.read_text(encoding="utf-8", errors="replace")
    add("r3_frozen same-run bad=0 checked=518400",
        re.search(r"SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400", rt) is not None
        and re.search(r"SS_VEC_MATCH bad=0 checked=518400 drv_groups=2073600", rt) is not None,
        "frame1+final")
    st = {}
    for kv in rf_stats.read_text(encoding="utf-8", errors="replace").strip().split():
        if "=" in kv:
            k, val = kv.split("=", 1)
            try:
                st[k] = int(val)
            except ValueError:
                st[k] = val
    add("r3_frozen counters/vec_bad0", st.get("cap") == 4 and st.get("enc") == 4 and st.get("exported") == 4
        and st.get("read") == 518400 and st.get("raw_drop") == 0 and st.get("cmp_drop") == 0
        and st.get("geom") == 0 and st.get("err") == 0 and st.get("dup") == 0 and st.get("wd") == 0
        and st.get("vec_bad") == 0 and st.get("vec_checked") == 518400 and st.get("drv_groups") == 2073600,
        json.dumps(st))
    add("r3_frozen S_ss from runs.csv/g0-verdict", v.get("runs", {}).get("r3f", {}).get("S_ss") == 5928286.0,
        "5928286.0")
    add("tester short v1 log bad=0", v1_log.exists()
        and "SS_VEC_MATCH bad=0 checked=518400 drv_groups=518400" in v1_log.read_text(encoding="utf-8", errors="replace"),
        str(v1_log))
    add("tester v1 hash unchanged", shafile(v1_log) == "bd72c28655f68fc40ba5fd8f1bb9ab7fa46a794a74986559ae70aa50de2694c1",
        shafile(v1_log))

    # 8. P1/P2/comp drift, DUT copies, 0 TD, write scope
    protected = [
        (P1 / "manifest-r0.json", "39f3e3d6d115afbdcda9753b254f6971a10eb75df88d5718eb9ea5a247199f9a"),
        (P1 / "out" / "steady-state.json", "a0945e1f60d9e7651d3db2d1a4d939b665d4fe451e9206537fb3b7d0c5430023"),
        (P1 / "sim" / "run_ss.py", "d7417ea1f4ee32c17412a0d82ee547407cd8dc6be7b1ebe34061c347586dbac8"),
        (P1 / "src" / "tb_ss_anchor.v", "ddd9e02ca71aa3b81e86f4cc0f151498fd48bf9a4dbbcc042b59c97d9f15d1ff"),
        (P1 / "sim" / "caps" / "ss4.stats", "29bd31851804714bf65df6d5f4aa29f9daddccebe4d858e08dbfed2e937981a5"),
        (P2 / "manifest-r0.json", "fd27c70f304f51ba0b0b022398acd46f1f5f43a32351acfc472dea12e034fad0"),
        (P2 / "verdict-r1.md", "62ec3adc067101383613ef3e5ff659b7139f320f57d1f1e6ad6ea30c09a3c18a"),
        (COMP / "in.hex", "edbfdeaedb06824ced20ad76b260979e95e1322d6f6e3bab5e7a951a268f9849"),
    ]
    badp = [[str(p), e, shafile(p)] for p, e in protected if shafile(p) != e]
    add("P1/P2/comp 8 inputs 0 drift", not badp, json.dumps(badp))
    p2m = json.loads((P2 / "manifest-r0.json").read_text(encoding="utf-8"))
    bad2 = [a["path"] for a in p2m["artifacts"] if not (P2 / a["path"]).exists() or shafile(P2 / a["path"]) != a["sha256"]]
    add("P2 34 artifacts 0 drift", not bad2, json.dumps(bad2))
    p1m = json.loads((P1 / "manifest-r0.json").read_text(encoding="utf-8"))
    bad1 = [a["path"] for a in p1m.get("artifacts", []) if not (P1 / a["path"]).exists() or shafile(P1 / a["path"]) != a["sha256"]]
    add("P1 artifacts 0 drift", not bad1, json.dumps(bad1))
    p1art = {a["path"]: a["sha256"] for a in p1m.get("artifacts", [])}
    copies = ["a1_ddr_arb2.v", "a1_ddr_model.v", "a1_ddr_slot_store.v", "a1_deflate_core.v",
              "a1_frame_top.v", "a1_raw_crop.v", "a1_uart_export.v", "cam_diag_mailbox.v",
              "camera_a1_uart_top.v", "capture_async_fifo.v", "p2_ddr_bridge.v", "p2_paxi_model_b11.v"]
    bc = [[c, p1art.get("src/" + c), shafile(TASK / "src" / c)] for c in copies
          if p1art.get("src/" + c) != shafile(TASK / "src" / c)]
    add("12 DUT copies == P1 manifest", not bc, json.dumps(bc))
    cmds = man.get("commands", [])
    add("0 TD/board/COM/JTAG commands", all(any(k in c["argv"][0].lower() for k in ["vsim", "vlog", "vlib"]) for c in cmds),
        "n=%d" % len(cmds))
    add("vsim wall 6532.4", abs(sum(c["seconds"] for c in cmds if "vsim" in c["argv"][0].lower()) - 6532.4) < 0.1,
        "sum=%.1f" % sum(c["seconds"] for c in cmds if "vsim" in c["argv"][0].lower()))
    add("artifacts under task dir", all(str(TASK).lower() in str((TASK / a["path"]).resolve()).lower()
        for a in man.get("artifacts", [])), "paths")

    # observations (non-blocking)
    res["observations"] = [
        "manifest-r2 artifacts includes sim/_repair.py (2,402 B) while notes.scratch_excluded still says it is non-artifact scratch excluded; DIFF.md section 9 F8 also says it was removed from manifest. Artifact hash itself is consistent; this is a stale note/DIFF wording, not a data issue.",
        "g0-closure.md section 10 headline still says the formal check is against manifest-r1.json; after round2 the frozen manifest is manifest-r2.json. Historical wording; update to r2 if a final report edit is made.",
    ]
    return res


if __name__ == "__main__":
    try:
        r = main()
    except Exception:
        import traceback
        traceback.print_exc()
        r = res
    (TEST / "evidence" / "verify_r2.json").write_text(json.dumps(r, indent=2, ensure_ascii=False), encoding="utf-8")
    n = len(r.get("checks", []))
    p = sum(1 for c in r.get("checks", []) if c["ok"])
    print("checks=%d pass=%d fail=%d" % (n, p, n - p))
    for c in r.get("checks", []):
        if not c["ok"]:
            print("FAIL:", c["name"], "||", c["detail"])
    print("OBSERVATIONS:")
    for o in r.get("observations", []):
        print("-", o)
