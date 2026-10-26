"""Parse the two 1-frame stage-probe logs into out/stage-probe.json.

Input:  r0/sim/logs/{n,l}-probe.log  (1 frame, FRAMES=1 CONTENT=2 PACING=0
        SINK=1 CAPTURE=0, +RAW40 = P1 frozen raw40_{n,l}.hex)
Output: r0/out/stage-probe.json

Validation rule (frozen, dev-plan section 2 step 2): the probe interval
t_enc(1)-t_pub(1) must be within +-2% of the P1 r1 frame-1 value
(N 7,476,245 / L 6,979,811); otherwise the probe is invalid and must not be
used by the model.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = {"N": 7_476_245, "L": 6_979_811}   # P1 r1 t_enc(1)-t_pub(1), frozen
TOL_PCT = 2.0
BYTES = 2_592_000

CORE_RE = re.compile(r"CORE_STAGE t=(\d+) exp_bytes=(\d+) blocks=(\d+) fixed=(\d+) stored=(\d+) "
                     r"literals=(\d+) matches=(\d+) cand_aborts=(\d+) stall=(\d+) "
                     r"max_match=(\d+) max_dist=(\d+) t_pub1=(-?\d+) t_enc1=(-?\d+) "
                     r"core_interval=(-?\d+)")
EVT_RE = re.compile(r"SS_EVT t=(\d+) kind=(pub|enc|exp|sof|cam_end) frame=(\d+)(?: n=\d+)?(?: bytes=(\d+))?")


def parse(log: Path):
    txt = log.read_text(encoding="utf-8", errors="replace")
    out = {"log": str(log).replace("\\", "/"), "frames": {}}
    m = CORE_RE.search(txt)
    if not m:
        out["core_stage_present"] = False
        return out
    out["core_stage_present"] = True
    (t, expb, blocks, fixed, stored, lits, mats, aborts, stall, mx, md,
     t_pub1, t_enc1, interval) = (int(g) for g in m.groups())
    out.update(t_core_stage=t, exp_bytes_at_commit=expb, blocks=blocks, fixed_blocks=fixed,
               stored_blocks=stored, literals=lits, matches=mats, cand_aborts=aborts,
               stall=stall, max_match=mx, max_dist=md, t_pub1=t_pub1, t_enc1=t_enc1,
               cycles=interval)
    ev = {}
    for line in txt.splitlines():
        e = EVT_RE.search(line)
        if not e:
            continue
        tt, kind, fr, by = e.groups()
        if fr == "1" and kind not in ev:
            ev[kind] = {"t": int(tt), "bytes": int(by) if by else None}
    out["events_frame1"] = ev
    out["stream_bytes"] = ev.get("exp", {}).get("bytes")
    out["bytes"] = BYTES
    out["markers"] = {
        "SS_STALL": "SS_STALL" in txt,
        "SS_STALL_COLD": "SS_STALL_COLD" in txt,
        "B11_FULL_TIMEOUT": "B11_FULL_TIMEOUT" in txt,
        "errors_0": "Errors: 0," in txt,
        "forced": ("force " in txt) or ("deposit" in txt),
    }
    return out


def main():
    res = {"task": "T10.ss-g0-prod-coregap", "probe": {}, "validation": {}}
    for name, f in (("N", "n-probe.log"), ("L", "l-probe.log")):
        p = parse(ROOT / "sim" / "logs" / f)
        res["probe"][name] = p
    ok_all = True
    for name in ("N", "L"):
        p = res["probe"][name]
        if not p.get("core_stage_present") or not p.get("cycles"):
            res["validation"][name] = {"valid": False, "reason": "no CORE_STAGE line"}
            ok_all = False
            continue
        dev = 100.0 * (p["cycles"] - REF[name]) / REF[name]
        v = {"reference_p1_r1_frame1": REF[name], "probe_cycles": p["cycles"],
             "deviation_pct": round(dev, 4), "tolerance_pct": TOL_PCT,
             "within_tolerance": abs(dev) <= TOL_PCT,
             "counters_present": all(p.get(k) is not None for k in
                                     ("blocks", "fixed_blocks", "stored_blocks", "literals",
                                      "matches", "cand_aborts", "stall", "max_match", "max_dist")),
             "no_force_no_stall": (not p["markers"]["forced"]) and
                                  (not p["markers"]["SS_STALL"]) and
                                  (not p["markers"]["SS_STALL_COLD"])}
        v["valid"] = bool(v["within_tolerance"] and v["counters_present"] and v["no_force_no_stall"])
        ok_all = ok_all and v["valid"]
        res["validation"][name] = v
    res["all_valid"] = ok_all
    out = ROOT / "out" / "stage-probe.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(res, indent=2), encoding="utf-8")
    print(json.dumps(res["validation"], indent=2))
    print("all_valid =", ok_all)


if __name__ == "__main__":
    main()
