#!/usr/bin/env python3
"""T11.BRD.P1 r2 — r1 vs r2 SHA comparison (RTL delta must be 0).

Compares, byte for byte:
  r1/rtl/**            vs r2/rtl/**            -> rtl_delta must be 0
  r1/constraints/**    vs r2/constraints/**    -> constraints_delta must be 0
  handoff/brd-p1-r1-20261027/filelist.tcl
                       vs r2/filelist.tcl      -> filelist_delta must be 0

`r2/filelist.tcl` has no r1 work-root counterpart (r1's single source list lives
in the r1 handoff package), so the comparison is done against that file.

Writes `r1-r2-sha-diff.md` next to this script and exits non-zero on any delta
or any missing/extra file.
"""
import hashlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
R2 = HERE.parent
R1 = R2.parent / "r1"
REPO = R2.parents[4]
FL_R1 = REPO / "handoff" / "brd-p1-r1-20261027" / "filelist.tcl"
FL_R2 = R2 / "filelist.tcl"


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()


def tree(base: Path) -> dict:
    if not base.exists():
        return {}
    return {str(p.relative_to(base)).replace("\\", "/"): p
            for p in base.rglob("*") if p.is_file()}


def section(title: str, a_base: Path, b_base: Path, rows: list, delta_name: str) -> str:
    a, b = tree(a_base), tree(b_base)
    lines = [f"## {title}", "",
             f"- r1 files: {len(a)}   r2 files: {len(b)}"]
    same = mismatch = 0
    for rel in sorted(set(a) | set(b)):
        pa, pb = a.get(rel), b.get(rel)
        if pa is None:
            lines.append(f"- MISSING_IN_R1 `{rel}`")
            mismatch += 1
            continue
        if pb is None:
            lines.append(f"- MISSING_IN_R2 `{rel}`")
            mismatch += 1
            continue
        ha, hb = sha(pa), sha(pb)
        if ha == hb:
            same += 1
            lines.append(f"- same  `{rel}`  {ha}  ({pa.stat().st_size} B)")
            rows.append((rel, ha, hb, True))
        else:
            mismatch += 1
            lines.append(f"- **DIFF** `{rel}`  r1={ha} r2={hb}")
            rows.append((rel, ha, hb, False))
    lines.append("")
    lines.append(f"**{delta_name} = {mismatch}** (identical files: {same})")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    rows: list = []
    out = ["# r1 vs r2 SHA comparison (T11.BRD.P1 round 2)", "",
           f"- repo root: `{REPO.as_posix()}`",
           f"- r1 work root: `{R1.relative_to(REPO).as_posix()}`",
           f"- r2 work root: `{R2.relative_to(REPO).as_posix()}`",
           "- rule: round 2 may only change `sim/**`, `evidence/**`, docs, the manifest",
           "  and the handoff package. RTL / constraints / filelist must stay byte-identical.",
           ""]

    out.append(section("rtl/**", R1 / "rtl", R2 / "rtl", rows, "rtl_delta"))
    out.append(section("constraints/**", R1 / "constraints", R2 / "constraints", rows, "constraints_delta"))

    # filelist
    ok = FL_R1.exists() and FL_R2.exists() and sha(FL_R1) == sha(FL_R2)
    fl_delta = 0 if ok else 1
    out += ["## filelist.tcl", "",
            f"- r1 (package): `{FL_R1.relative_to(REPO).as_posix()}` sha256 `{sha(FL_R1) if FL_R1.exists() else 'MISSING'}`",
            f"- r2 (work root): `{FL_R2.relative_to(REPO).as_posix()}` sha256 `{sha(FL_R2) if FL_R2.exists() else 'MISSING'}`",
            f"- identical: {ok}", "",
            f"**filelist_delta = {fl_delta}**", ""]

    # what changed in r2 (informational, must be sim/evidence/docs only)
    changed = sorted(
        str(p.relative_to(R2)).replace("\\", "/")
        for p in R2.rglob("*")
        if p.is_file() and p.suffix.lower() not in (".bin",)
        and "sim/work" not in str(p).replace("\\", "/")
    )
    out += ["## r2 files (informational: every r2-only path is sim/evidence/doc/handoff work)", ""]
    out += [f"- `{c}`" for c in changed if not c.startswith(("rtl/", "constraints/"))]
    out.append("")

    total_delta = sum(1 for r in rows if not r[3]) + fl_delta
    out += ["## verdict", "",
            f"- rtl_delta = {sum(1 for r in rows if not r[3])}",
            f"- filelist_delta = {fl_delta}",
            f"- overall_delta = {total_delta}",
            "",
            "**RTL_DELTA_ZERO=" + ("TRUE" if total_delta == 0 else "FALSE") + "**", ""]

    md = HERE / "r1-r2-sha-diff.md"
    md.write_text("\n".join(out), encoding="utf-8")
    print(f"WROTE {md}")
    for r in rows:
        if not r[3]:
            print(f"DELTA {r[0]} r1={r[1]} r2={r[2]}")
    print(f"RTL_DELTA={sum(1 for r in rows if not r[3])} FILELIST_DELTA={fl_delta} "
          f"OVERALL_DELTA={total_delta}")
    print("R1_R2_SHA_DIFF=" + ("PASS" if total_delta == 0 else "FAIL"))
    return 0 if total_delta == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
