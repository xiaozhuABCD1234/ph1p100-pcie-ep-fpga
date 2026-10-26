"""Legacy regression replay: the byte-identical P2 model must reproduce the frozen
P2 scenarios.csv (43 rows) and overhead-sensitivity.csv (129 rows).

Purpose: prove that every corrected number in out/scenarios.csv comes from a rule /
anchor / input change, not from a different arithmetic implementation.  The P2 code is
imported from inputs/legacy/calc.py (sha256-verified copy) and is never modified.

Exit code 0 only if header + all rows match (strings exactly, numbers within 1e-6).
"""
import hashlib
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LEGACY = os.path.join(ROOT, "inputs", "legacy")
P2_OUT = ("D:/fpga/ph1p100/workflow/runs/20261025-195604_fpga-dual-aplus-core-feasibility/"
          "T10.dual-aplus-service-verdict/r0/out")

TOL = 1e-6


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_json(path):
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def load_legacy_calc():
    path = os.path.join(LEGACY, "calc.py")
    spec = importlib.util.spec_from_file_location("legacy_calc", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_rows(path):
    with open(path, "r", encoding="utf-8", newline="") as fh:
        text = fh.read()
    lines = [ln for ln in text.replace("\r\n", "\n").split("\n") if ln != ""]
    return lines[0], lines[1:]


def split_csv_line(line):
    """Minimal CSV splitter with quote handling (fields contain commas)."""
    out, cur, quoted, i = [], [], False, 0
    while i < len(line):
        ch = line[i]
        if quoted:
            if ch == '"':
                if i + 1 < len(line) and line[i + 1] == '"':
                    cur.append('"')
                    i += 2
                    continue
                quoted = False
                i += 1
                continue
            cur.append(ch)
            i += 1
            continue
        if ch == '"':
            quoted = True
            i += 1
            continue
        if ch == ",":
            out.append("".join(cur))
            cur = []
            i += 1
            continue
        cur.append(ch)
        i += 1
    out.append("".join(cur))
    return out


def compare(name, expected_lines, actual_lines, header):
    mismatches = []
    if len(expected_lines) != len(actual_lines):
        mismatches.append({"field": "<row_count>", "expected": len(expected_lines),
                           "actual": len(actual_lines)})
    cols = header.split(",")
    for idx, (e, a) in enumerate(zip(expected_lines, actual_lines)):
        ef, af = split_csv_line(e), split_csv_line(a)
        if len(ef) != len(af):
            mismatches.append({"row": idx, "field": "<field_count>",
                               "expected": len(ef), "actual": len(af)})
            continue
        for j, (ev, av) in enumerate(zip(ef, af)):
            col = cols[j] if j < len(cols) else "#%d" % j
            if ev == av:
                continue
            try:
                if abs(float(ev) - float(av)) <= TOL:
                    continue
            except ValueError:
                pass
            mismatches.append({"row": idx, "field": col, "expected": ev, "actual": av})
    return {"name": name, "rows": len(expected_lines), "mismatch_count": len(mismatches),
            "mismatches": mismatches[:10]}


def main():
    legacy = load_legacy_calc()
    frozen = load_json(os.path.join(LEGACY, "frozen-inputs.json"))
    rules = load_json(os.path.join(LEGACY, "rules.json"))
    import hashlib as _h
    legacy_hashes = {
        "calc.py": sha256(os.path.join(LEGACY, "calc.py")),
        "rules.json": sha256(os.path.join(LEGACY, "rules.json")),
        "frozen-inputs.json": sha256(os.path.join(LEGACY, "frozen-inputs.json")),
    }
    expected_hashes = {
        "calc.py": "9eea41f56586d6cdd18f50433d607870aa725396e1688d5ce97ecd0c67f9bd2c",
        "rules.json": "fdaae351c56d29cc97cdf3a66a393422854e61e95b24828b9ff3182ab1e42f4d",
        "frozen-inputs.json": "888d3f3361aada77c77fc87140d6469b052d4dac2c63466e2007cfbf973a0f59",
    }
    if legacy_hashes != expected_hashes:
        print("LEGACY_HASH_MISMATCH")
        print(json.dumps(legacy_hashes, indent=2))
        return 2

    rows = legacy.scenario_rows(frozen, rules)
    scen_text = "\n".join([",".join(legacy.SCENARIO_COLS)]
                          + [legacy.row_to_csv(r, legacy.SCENARIO_COLS) for r in rows]) + "\n"
    exp_header, exp_rows = read_rows(os.path.join(P2_OUT, "scenarios.csv"))
    act_header = legacy.SCENARIO_COLS
    act_lines = scen_text.replace("\r\n", "\n").split("\n")[1:]
    act_lines = [ln for ln in act_lines if ln != ""]
    res_scen = compare("scenarios.csv", exp_rows, act_lines, exp_header)
    res_scen["header_match"] = (exp_header == ",".join(act_header))
    res_scen["byte_identical"] = (scen_text.replace("\r\n", "\n") ==
                                  "\n".join([exp_header] + exp_rows) + "\n")

    over = legacy.overhead_sensitivity_rows(rows, frozen, rules)
    over_text = "\n".join([",".join(legacy.OVERHEAD_COLS)]
                          + [legacy.row_to_csv(r, legacy.OVERHEAD_COLS) for r in over]) + "\n"
    exp_h2, exp_o = read_rows(os.path.join(P2_OUT, "overhead-sensitivity.csv"))
    act_o = [ln for ln in over_text.replace("\r\n", "\n").split("\n")[1:] if ln != ""]
    res_over = compare("overhead-sensitivity.csv", exp_o, act_o, exp_h2)
    res_over["header_match"] = (exp_h2 == ",".join(legacy.OVERHEAD_COLS))

    result = {
        "legacy_hashes": legacy_hashes,
        "legacy_hashes_match_p2": legacy_hashes == expected_hashes,
        "scenarios_csv": res_scen,
        "overhead_sensitivity_csv": res_over,
        "tolerance": TOL,
        "verdict": ("PASS" if (res_scen["mismatch_count"] == 0 and res_scen["header_match"])
                    else "FAIL"),
    }
    out_path = os.path.join(ROOT, "out", "legacy-regression.json")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=2)
        fh.write("\n")
    print("legacy hashes match P2: %s" % result["legacy_hashes_match_p2"])
    print("scenarios.csv: rows=%d header_match=%s byte_identical=%s mismatch=%d"
          % (res_scen["rows"], res_scen["header_match"], res_scen["byte_identical"],
             res_scen["mismatch_count"]))
    for m in res_scen["mismatches"]:
        print("  MISMATCH %s" % m)
    print("overhead-sensitivity.csv: rows=%d header_match=%s mismatch=%d"
          % (res_over["rows"], res_over["header_match"], res_over["mismatch_count"]))
    for m in res_over["mismatches"]:
        print("  MISMATCH %s" % m)
    print("VERDICT=%s" % result["verdict"])
    return 0 if result["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
