# -*- coding: utf-8 -*-
"""T11.rk-align-raw round0 engineering (independent tester).
Read-only recompute of the frozen candidate-manifest.json (SHA, 243 entries),
mtime zero-late-write scan, T07-vs-T11 delta, bit/CWC scan.
Writes only under test-reports/T11.rk-align-raw-r0-engineering/.
"""
import hashlib, json, os, sys
from datetime import datetime

ROOT = r"C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道"
RUN = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align")
OUT = os.path.join(RUN, "test-reports", "T11.rk-align-raw-r0-engineering")
MAN = os.path.join(RUN, "raw", "candidate-manifest.json")
T07MAN = os.path.join(RUN, "backend", "candidate-manifest.json")

def sha256_file(p, bs=1 << 20):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        while True:
            b = f.read(bs)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

def mtime(p):
    return datetime.fromtimestamp(os.path.getmtime(p)).strftime("%Y-%m-%d %H:%M:%S")

def base_for(section):
    if section in ("rk_patch_inputs", "build_artifacts"):
        return RUN
    return ROOT

def walk_files(top):
    for dirpath, dirnames, filenames in os.walk(top):
        for fn in filenames:
            yield os.path.join(dirpath, fn)

def main():
    lines = []
    man_sha = sha256_file(MAN)
    man_mtime = mtime(MAN)
    with open(MAN, encoding='utf-8') as f:
        man = json.load(f)

    lines.append("== T11 manifest self-recompute (independent) ==")
    lines.append(f"manifest   : {MAN}")
    lines.append(f"manifest SHA256 : {man_sha}")
    lines.append(f"manifest mtime  : {man_mtime}")
    lines.append(f"schema={man.get('schema')} task={man.get('task_id')} round={man.get('round')}")

    sections = ["production_inputs", "build_scripts", "test_inputs", "rk_patch_inputs", "build_artifacts"]
    total = ok = missing = mismatch = size_bad = 0
    per_section = {}
    covered = []          # (section, abspath, relpath, mtime_str)
    for sec in sections:
        ok_s = miss_s = mm_s = sz_s = 0
        mt = []
        for e in man.get(sec, []):
            rel = e["path"]
            p = os.path.join(base_for(sec), rel.replace("/", os.sep))
            total += 1
            if not os.path.isfile(p):
                missing += 1; miss_s += 1
                lines.append(f"MISSING  [{sec}] {rel}")
                continue
            got = sha256_file(p)
            if got != e["sha256"]:
                mismatch += 1; mm_s += 1
                lines.append(f"MISMATCH [{sec}] {rel}\n  expect {e['sha256']}\n  actual {got}")
            else:
                ok += 1; ok_s += 1
            if "size" in e and os.path.getsize(p) != e["size"]:
                size_bad += 1; sz_s += 1
                lines.append(f"SIZE     [{sec}] {rel} expect {e['size']} got {os.path.getsize(p)}")
            m = mtime(p)
            mt.append(m)
            covered.append((sec, p, rel, m))
        per_section[sec] = dict(entries=len(man.get(sec, [])), ok=ok_s, missing=miss_s,
                                mismatch=mm_s, size_bad=sz_s,
                                mtime_min=min(mt) if mt else None, mtime_max=max(mt) if mt else None)
        lines.append(f"[{sec}] entries={len(man.get(sec, []))} ok={ok_s} missing={miss_s} mismatch={mm_s} size_bad={sz_s} mtime {per_section[sec]['mtime_min']} .. {per_section[sec]['mtime_max']}")

    lines.append(f"TOTAL entries={total} OK={ok} MISSING={missing} MISMATCH={mismatch} SIZE_MISMATCH={size_bad}")
    lines.append(f"selfcheck file says: {json.load(open(os.path.join(RUN,'raw','manifest-selfcheck.json'),encoding='utf-8'))}")

    # zero-late-write: any covered file written after the manifest itself?
    late = [(s, r, m) for (s, p, r, m) in covered if m > man_mtime]
    lines.append(f"covered files with mtime later than manifest mtime ({man_mtime}): {len(late)}")
    for s, r, m in late:
        lines.append(f"  LATE [{s}] {r} mtime={m}")

    # T07 -> T11 delta on shared sections
    t07 = json.load(open(T07MAN, encoding='utf-8'))
    lines.append("")
    lines.append("== T07 (68f9f4d0) manifest -> T11 delta, shared sections ==")
    for sec in ["production_inputs", "build_scripts", "test_inputs"]:
        a = {e["path"]: e["sha256"] for e in t07.get(sec, [])}
        b = {e["path"]: e["sha256"] for e in man.get(sec, [])}
        changed = sorted([k for k in set(a) & set(b) if a[k] != b[k]])
        added = sorted(set(b) - set(a))
        removed = sorted(set(a) - set(b))
        lines.append(f"[{sec}] T07={len(a)} T11={len(b)} changed={len(changed)} added={len(added)} removed={len(removed)}")
        for k in changed:
            lines.append(f"  CHANGED {k}\n    T07={a[k]}\n    T11={b[k]}")
        for k in added:
            lines.append(f"  ADDED   {k}")
        for k in removed:
            lines.append(f"  REMOVED {k}")
    # rk / build_artifacts are T11-only contexts; still compare rk patch names vs T07
    a = {e["path"]: e["sha256"] for e in t07.get("rk_patch_inputs", [])}
    b = {e["path"]: e["sha256"] for e in man.get("rk_patch_inputs", [])}
    lines.append(f"[rk_patch_inputs] T07={len(a)} T11={len(b)} added={sorted(set(b)-set(a))} removed={sorted(set(a)-set(b))}")

    # bit scan (candidate tree)
    cand = os.path.join(RUN, "raw", "candidate")
    bits = []
    for p in walk_files(cand):
        if p.lower().endswith(".bit"):
            bits.append((os.path.relpath(p, RUN).replace(os.sep, '/'), os.path.getsize(p), sha256_file(p), mtime(p)))
    lines.append("")
    lines.append("== *.bit scan under raw/candidate ==")
    for rel, sz, h, m in sorted(bits):
        lines.append(f"{h}  {sz:>9}  {m}  {rel}")

    # CWC scan
    cwc = [p for p in walk_files(cand) if 'cwc' in os.path.basename(p).lower()]
    lines.append("")
    lines.append(f"== CWC files under raw/candidate: {len(cwc)} ==")
    for p in cwc:
        lines.append(os.path.relpath(p, RUN))

    # T07-vs-T11 bit
    t07_bit = man.get("baseline_candidate", {}).get("bit_sha256")
    lines.append("")
    lines.append(f"baseline (T07 r3) bit per T11 manifest: {t07_bit}")
    lines.append(f"T07 manifest selfcheck: {json.load(open(os.path.join(RUN,'backend','manifest-selfcheck.json'),encoding='utf-8')) if os.path.exists(os.path.join(RUN,'backend','manifest-selfcheck.json')) else 'n/a'}")

    txt = "\n".join(lines) + "\n"
    with open(os.path.join(OUT, "verify_manifest.out.txt"), "w", encoding='utf-8') as f:
        f.write(txt)
    summary = dict(manifest_sha=man_sha, manifest_mtime=man_mtime, total=total, ok=ok,
                   missing=missing, mismatch=mismatch, size_bad=size_bad,
                   per_section=per_section, late_count=len(late),
                   bits=[{"rel": r, "size": s, "sha": h, "mtime": m} for r, s, h, m in bits],
                   cwc_count=len(cwc))
    with open(os.path.join(OUT, "verify_manifest.json"), "w", encoding='utf-8') as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)
    print(txt)

if __name__ == "__main__":
    main()
