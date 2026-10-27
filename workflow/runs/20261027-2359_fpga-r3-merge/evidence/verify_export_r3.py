#!/usr/bin/env python3
"""r3 export regression verifier (task D).

Checks the four export runs produced by sim/run_export.ps1 plus the two
diagnostic runs:
  * SCEN=0 NF=2  : two frames, byte-exact, wrong ACK holds, correct ACK releases
  * SCEN=3 NF=2  : same with host TL wait + slow-DDR backpressure
  * SCEN=2 NF=2  : wrong-ACK branch
  * HOST_MODEL=1 : legacy r0g decode (must FAIL, proving the r0g observation is
                   a TB decode artifact and not the DUT)
  * neg_both     : illegal base + illegal cap rejected, no MWr / no doorbell

It does not re-judge the DUT; it only reads the frozen logs and applies the
markers the TB already prints.
"""
import re
import sys
from pathlib import Path

RUN = Path(__file__).resolve().parents[1]
SIM = RUN / "sim"

fails = []
checks = 0


def check(name, cond, detail=""):
    global checks
    checks += 1
    print(("PASS " if cond else "FAIL ") + name + (f"  [{detail}]" if detail else ""))
    if not cond:
        fails.append(name)


def newest(pattern):
    hits = sorted(SIM.glob(pattern), key=lambda p: p.stat().st_mtime)
    return hits[-1] if hits else None


def text(p):
    raw = p.read_bytes()
    for enc in ("utf-8-sig", "utf-16", "latin-1"):
        try:
            return raw.decode(enc)
        except (UnicodeDecodeError, UnicodeError):
            continue
    return raw.decode("latin-1", errors="replace")


def markers(txt, key):
    out = []
    for m in re.finditer(rf"^#?\s*{re.escape(key)}[^\r\n]*", txt, re.M):
        out.append(m.group(0))
    return out


def positive(tag, path, req):
    print(f"\n=== {tag}: {path.name if path else 'MISSING'} ===")
    if path is None:
        check(f"{tag}_log_present", False, "no log")
        return
    txt = text(path)
    check(f"{tag}_no_timeout", "RESULT=FAIL timeout" not in txt)
    check(f"{tag}_req_{req}", f"TB_REQ={req}" in txt, "TB_REQ")
    frames = markers(txt, "FRAME_RESULT")
    check(f"{tag}_frame_count_{req}", len(frames) == req, f"{len(frames)}")
    check(f"{tag}_all_frames_pass",
          all("PASS" in f for f in frames) and len(frames) == req,
          "; ".join(frames))
    pcs = markers(txt, "PAYLOAD_COMPARE")
    judged = [p for p in pcs if "NOT_EXECUTED" not in p]
    check(f"{tag}_payload_count_{req}", len(judged) == req, f"{len(judged)}")
    check(f"{tag}_mismatch_zero",
          all("mismatch=0 " in p or p.rstrip().endswith("mismatch=0") for p in judged),
          " | ".join(judged))
    check(f"{tag}_legacy_model_differs",
          all("legacy_mismatch=0" not in p for p in judged),
          "the old lane0/LSB decode must not accidentally match")
    check(f"{tag}_doorbell_one_each",
          all("doorbell=1" in p for p in judged))
    check(f"{tag}_pos_pass", any("POS_RESULT=PASS" in x for x in markers(txt, "POS_RESULT")),
          " | ".join(markers(txt, "POS_RESULT")))
    check(f"{tag}_x_zero", "x_cnt=0" in txt, "x_cnt")
    check(f"{tag}_e8_negative_control", "E8_NEGCTL" in txt and "expect 1_then_0" in txt)


def main():
    s0 = newest("sim_export_s0_h0_*.log")
    s3 = newest("sim_export_s3_h0_*.log")
    s2 = newest("sim_export_s2_h0_*.log")
    legacy = SIM / "logs_export_legacy.txt"
    neg = SIM / "logs_export_neg.txt"

    positive("scen0", s0, 2)
    positive("scen3_backpressure", s3, 2)
    positive("scen2", s2, 2)

    print("\n=== ACK / negative markers (all positive runs) ===")
    for tag, p, want_wrong in (("scen0", s0, True), ("scen3", s3, False), ("scen2", s2, True)):
        if p is None:
            check(f"{tag}_ack_log", False)
            continue
        txt = text(p)
        if want_wrong:
            check(f"{tag}_wrong_ack_no_release",
                  "PASS neg2: wrong ACK did not release" in txt and "NEG2_RESULT=PASS" in txt)
        else:
            # SCEN=3 is the backpressure scenario; the wrong-ACK branch is
            # exercised by SCEN=0 and SCEN=2 (asserted above).
            check(f"{tag}_wrong_ack_branch_not_run", "NEG2_RESULT" not in txt,
                  "SCEN=3 is backpressure only")
        check(f"{tag}_correct_ack_released",
              len(markers(txt, "INFO frame=")) >= 1 and "released the slot" in txt)
        check(f"{tag}_no_deadlock", "RESULT=FAIL timeout" not in txt)

    print(f"\n=== legacy r0g host model (diagnostic): {legacy.name} ===")
    if legacy.exists():
        txt = text(legacy)
        check("legacy_run_present", "HOST_MODEL=1" in txt, "HOST_MODEL=1")
        check("legacy_reproduces_r0g_failure",
              "FRAME_RESULT frame=0 FAIL" in txt and "mismatch=3830" in txt,
              "expected mismatch=3830")
        check("legacy_not_silently_passing", "POS_RESULT=FAIL" in txt)
    else:
        check("legacy_log_present", False, str(legacy))

    print(f"\n=== illegal descriptors: {neg.name} ===")
    if neg.exists():
        txt = text(neg)
        check("neg_base_rejected", "POS_RESULT=NEG_PASS id=1" in txt)
        check("neg_cap_rejected", "POS_RESULT=NEG_PASS id=2" in txt)
        check("neg_two_rejections", len(markers(txt, "NEG_RESULT=PASS")) == 2,
              f"{len(markers(txt, 'NEG_RESULT=PASS'))}")
    else:
        check("neg_log_present", False, str(neg))

    print(f"\nCHECKS={checks} FAILS={len(fails)}")
    print("EXPORT_REGRESSION=" + ("PASS" if not fails else "FAIL " + ",".join(fails)))
    return 0 if not fails else 1


if __name__ == "__main__":
    raise SystemExit(main())
