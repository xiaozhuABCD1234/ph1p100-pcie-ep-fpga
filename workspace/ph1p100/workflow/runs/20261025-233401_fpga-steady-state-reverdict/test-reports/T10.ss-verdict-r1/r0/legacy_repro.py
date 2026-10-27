"""Tester's independent legacy replay for T10.ss-verdict-r1 round 0.

Requirement (dev-plan 4.5 / design-guide 7.2): use the ORIGINAL P2 rules to reproduce the
frozen 43-row P2 scenarios.csv with 0 mismatch (<= 1e-6), and verify the candidate's
out/legacy-regression.json.

This script is written by the tester and does NOT import model/regress_legacy.py.  It
imports the P2 original model/calc.py (read-only) and compares every cell itself.  It also
hand-recomputes three legacy rows from the design-guide formulas as a non-model cross-check.
"""
import csv
import hashlib
import importlib.util
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
P2 = ("D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/"
      "T10.dual-aplus-service-verdict/r0")
R0 = ("D:/fpga/ph1p100/workflow/runs/20261025-233401_fpga-steady-state-reverdict/"
      "T10.ss-verdict-r1/r0")
TOL = 1e-6
CHECKS = [0]
FAILS = []


def ck(name, cond, detail=""):
    CHECKS[0] += 1
    if not cond:
        FAILS.append(name)
        print("FAIL  %s  %s" % (name, detail))


def near(a, b, tol=TOL):
    return abs(float(a) - float(b)) <= tol


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def load_p2_calc():
    path = os.path.join(P2, "model", "calc.py")
    spec = importlib.util.spec_from_file_location("p2_calc_original", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_csv_rows(path):
    with open(path, "r", encoding="utf-8", newline="") as fh:
        rdr = csv.reader(fh)
        rows = list(rdr)
    return rows[0], rows[1:]


def compare_csv(name, exp_header, exp_rows, got_text, exp_path=None):
    got = list(csv.reader(got_text.splitlines()))
    got_header, got_rows = got[0], got[1:]
    mismatches = []
    if exp_header != got_header:
        mismatches.append({"field": "<header>", "expected": exp_header, "actual": got_header})
    if len(exp_rows) != len(got_rows):
        mismatches.append({"field": "<row_count>", "expected": len(exp_rows),
                           "actual": len(got_rows)})
    for idx, (e, a) in enumerate(zip(exp_rows, got_rows)):
        if len(e) != len(a):
            mismatches.append({"row": idx, "field": "<field_count>",
                               "expected": len(e), "actual": len(a)})
            continue
        for j, (ev, av) in enumerate(zip(e, a)):
            if ev == av:
                continue
            try:
                if abs(float(ev) - float(av)) <= TOL:
                    continue
            except ValueError:
                pass
            mismatches.append({"row": idx, "field": exp_header[j] if j < len(exp_header) else j,
                               "expected": ev, "actual": av})
    byte_identical = None
    if exp_path is not None:
        with open(exp_path, "r", encoding="utf-8", newline="") as fh:
            raw = fh.read().replace("\r\n", "\n")
        byte_identical = (raw == got_text)
    return {"name": name, "rows": len(exp_rows), "mismatch_count": len(mismatches),
            "mismatches": mismatches[:10], "header_match": exp_header == got_header,
            "byte_identical": byte_identical}


def main():
    legacy = load_p2_calc()
    frozen = load_json(os.path.join(P2, "inputs", "frozen-inputs.json"))
    rules = load_json(os.path.join(P2, "model", "rules.json"))

    # legacy copies must be byte-identical to the P2 originals
    for fname in ("calc.py", "rules.json", "frozen-inputs.json"):
        src = os.path.join(P2, "model", fname) if fname != "frozen-inputs.json" \
            else os.path.join(P2, "inputs", fname)
        copy = os.path.join(R0, "inputs", "legacy", fname)
        ck("legacy copy %s byte-identical to P2" % fname, sha256(src) == sha256(copy))

    rows = legacy.scenario_rows(frozen, rules)
    scen_text = "\n".join([",".join(legacy.SCENARIO_COLS)] +
                          [legacy.row_to_csv(r, legacy.SCENARIO_COLS) for r in rows]) + "\n"
    exp_h, exp_rows = read_csv_rows(os.path.join(P2, "out", "scenarios.csv"))
    res_scen = compare_csv("scenarios.csv", exp_h, exp_rows, scen_text,
                           os.path.join(P2, "out", "scenarios.csv"))
    print("scenarios: rows=%d header=%s byte_identical=%s mismatch=%d"
          % (res_scen["rows"], res_scen["header_match"], res_scen["byte_identical"],
             res_scen["mismatch_count"]))
    ck("legacy scenarios: 43 rows", res_scen["rows"] == 43)
    ck("legacy scenarios: header matches", res_scen["header_match"])
    ck("legacy scenarios: 0 mismatch <= 1e-6", res_scen["mismatch_count"] == 0,
       res_scen["mismatches"][:3])

    over = legacy.overhead_sensitivity_rows(rows, frozen, rules)
    over_text = "\n".join([",".join(legacy.OVERHEAD_COLS)] +
                          [legacy.row_to_csv(r, legacy.OVERHEAD_COLS) for r in over]) + "\n"
    exp_h2, exp_o = read_csv_rows(os.path.join(P2, "out", "overhead-sensitivity.csv"))
    res_over = compare_csv("overhead-sensitivity.csv", exp_h2, exp_o, over_text,
                           os.path.join(P2, "out", "overhead-sensitivity.csv"))
    print("overhead: rows=%d header=%s mismatch=%d"
          % (res_over["rows"], res_over["header_match"], res_over["mismatch_count"]))
    ck("legacy overhead: 129 rows 0 mismatch", res_over["rows"] == 129
       and res_over["mismatch_count"] == 0)

    # ---- my own formula cross-check of three legacy rows (no model call) ----
    RAW = 2592000.0
    CLK = 187.5e6
    cold = 6421414.0
    c1080 = RAW * CLK / cold / 1e6
    m1080 = 100.0 * (c1080 / 77.76 - 1.0)
    c1080_2 = c1080 / 2.0
    m1080_2 = 100.0 * (c1080_2 / 77.76 - 1.0)
    raw1600 = 1600 * 900 * 5 / 4
    cyc1600 = raw1600 * (355261.0 / 153600.0) + 426385.0
    c1600 = raw1600 * CLK / cyc1600 / 1e6
    m1600 = 100.0 * (c1600 / (raw1600 * 30 / 1e6) - 1.0)
    by_id = {r["scenario_id"]: r for r in rows}
    r1 = by_id["1920x1080-30fps-c1s1-187.5MHz"]
    r2 = by_id["1920x1080-30fps-c1s2-187.5MHz"]
    r3 = by_id["1600x900-30fps-c1s1-187.5MHz"]
    ck("legacy row 1080p30 c1s1 hand calc (75.6843 / -2.6694%)",
       near(r1["capacity_chain_MBps"], c1080) and near(r1["margin_chain_pct"], m1080))
    ck("legacy row 1080p30 c1s2 hand calc (37.8421 / -51.3347%)",
       near(r2["per_stream_capacity_chain_MBps"], c1080_2) and near(r2["margin_chain_pct"], m1080_2))
    ck("legacy row 1600x900 c1s1 hand calc (73.5358 / +36.1774%)",
       near(r3["capacity_chain_MBps"], c1600) and near(r3["margin_chain_pct"], m1600))
    ck("legacy row 1080p30 c1s1 verdict infeasible (cold-latency rule)",
       r1["verdict"] == "infeasible")
    ck("legacy row counts feasible/conditional/infeasible = 8/22/13",
       [sum(1 for r in rows if r["verdict"] == v) for v in
        ("feasible", "conditional", "infeasible")] == [8, 22, 13])

    dev = load_json(os.path.join(R0, "out", "legacy-regression.json"))
    ck("dev legacy-regression verdict PASS", dev.get("verdict") == "PASS")
    ck("dev legacy-regression 43 rows 0 mismatch",
       dev["scenarios_csv"]["rows"] == 43 and dev["scenarios_csv"]["mismatch_count"] == 0)
    ck("dev legacy-regression reports byte_identical true",
       dev["scenarios_csv"].get("byte_identical") is True)
    ck("dev legacy-regression claims match my replay",
       dev["scenarios_csv"]["mismatch_count"] == res_scen["mismatch_count"]
       and dev["scenarios_csv"]["rows"] == res_scen["rows"])

    out = {
        "checks": CHECKS[0],
        "failures": FAILS,
        "verdict": "PASS" if not FAILS else "FAIL",
        "scenarios": res_scen,
        "overhead": res_over,
        "tolerance": TOL,
        "dev_json_claims": {
            "verdict": dev.get("verdict"),
            "rows": dev["scenarios_csv"]["rows"],
            "mismatch_count": dev["scenarios_csv"]["mismatch_count"],
            "byte_identical": dev["scenarios_csv"].get("byte_identical"),
        },
    }
    with open(os.path.join(HERE, "legacy_repro.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)
        fh.write("\n")
    print("\n%d checks, %d failures" % (CHECKS[0], len(FAILS)))
    print("LEGACY_REPRO=%s" % out["verdict"])
    return 0 if not FAILS else 1


if __name__ == "__main__":
    raise SystemExit(main())
