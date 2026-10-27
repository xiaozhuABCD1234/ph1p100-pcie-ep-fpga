#!/usr/bin/env python3
"""证据审计：把"文档里写的"与"实际产物"自动比对，防止数字/链接漂移。

动因：独立复核已经抓到两次同类纰漏——文档写着旧的项数/旧的数值/断链，
而实际产物已变。人工核对不可靠，这里做成可复跑的断言。

检查项：
  1. `parallel/**/*.md` 里所有相对链接都能解析到存在的文件；
  2. 帧合同文档里引用的 CRC/长度与真实 .bin 一致；
  3. 三算法文档写的自检项数与 `summary.json` 一致；
  4. 闪点文档/进展文档引用的跳变密度与 `sparkle_stress` 现产物一致；
  5. README 写的回归项数与 `run_all.py` 实际注册数一致，且最近一次回归零失败。

只读；不修改任何文件。
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PAR = REPO / "parallel"


def check_links():
    bad = []
    for md in list(PAR.rglob("*.md")):
        text = md.read_text(encoding="utf-8", errors="replace")
        for target in re.findall(r"\]\(([^)]+)\)", text):
            t = target.split("#")[0].strip()
            if not t or t.startswith(("http://", "https://", "mailto:")):
                continue
            if t.startswith("/"):
                continue
            p = (md.parent / t).resolve()
            if not p.exists():
                bad.append("%s -> %s" % (md.relative_to(PAR), t))
    return ("links_resolve", not bad, "; ".join(bad[:5]))


def check_frame_numbers():
    doc = PAR / "docs" / "帧与元数据接口合同_2026-10-15.md"
    vec = PAR / "evidence" / "frame_contract_20261015" / "frame_8x4_packed.bin"
    if not doc.exists() or not vec.exists():
        return ("frame_doc_numbers", False, "doc or vector missing")
    text = doc.read_text(encoding="utf-8", errors="replace")
    sys.path.insert(0, str(PAR / "frame"))
    import frame_contract as FC
    info = FC.parse_frame(vec.read_bytes())
    h = info["header"]
    want = ["0x%08X" % h["raw_crc32"], "0x%08X" % h["payload_crc32"], "0x%08X" % h["header_crc32"]]
    missing = [w for w in want if w not in text]
    return ("frame_doc_numbers", not missing, "missing %s" % missing if missing else "crc ok")


def check_algo_count():
    doc = PAR / "docs" / "三算法软件金参考_2026-10-15.md"
    sm = PAR / "evidence" / "image_algorithms_20261015" / "summary.json"
    if not doc.exists() or not sm.exists():
        return ("algo_doc_count", False, "missing")
    n = len(json.loads(sm.read_text(encoding="utf-8"))["selftest"])
    text = doc.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"自检\s*\*{0,2}(\d+)\s*项", text)
    ok = bool(m) and int(m.group(1)) == n
    return ("algo_doc_count", ok, "doc=%s actual=%d" % (m.group(1) if m else "?", n))


def check_sparkle_numbers():
    doc = PAR / "docs" / "并行轨道进展_2026-10-15.md"
    sm = PAR / "evidence" / "sparkle_stress_20261015" / "summary.json"
    if not doc.exists() or not sm.exists():
        return ("sparkle_doc_numbers", False, "missing")
    d = json.loads(sm.read_text(encoding="utf-8"))
    mt = d["patterns"]["max_toggle"]["combined_transition_density"]
    rb = d["patterns"]["refbar"]["combined_transition_density"]
    text = doc.read_text(encoding="utf-8", errors="replace")
    # 文档里以 0.4998 / 0.1571 形式出现（四位小数）
    ok = ("%.4f" % mt) in text and ("%.4f" % rb) in text
    return ("sparkle_doc_numbers", ok, "max_toggle=%.4f refbar=%.4f" % (mt, rb))


def check_runall_counts():
    import importlib.util
    spec = importlib.util.spec_from_file_location("run_all_mod", PAR / "run_all.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["run_all_mod"] = mod
    spec.loader.exec_module(mod)
    sw, ms = len(mod.CASES), len(mod.MODELSIM_CASES)
    readme = (PAR / "README.md").read_text(encoding="utf-8", errors="replace")
    m1 = re.search(r"run_all\.py\s*#\s*(\d+)\s*项", readme)
    m2 = re.search(r"--with-modelsim\s*#\s*(\d+)\s*项", readme)
    ok = bool(m1 and m2) and int(m1.group(1)) == sw and int(m2.group(1)) == sw + ms
    # 最近一次回归必须零失败
    runs = sorted([p for p in (PAR / "evidence").glob("run_all_*") if p.is_dir()])
    last_ok = None
    if runs:
        s = json.loads((runs[-1] / "summary.json").read_text(encoding="utf-8"))
        # 最近一次可能是"纯软件"或"含 ModelSim"两种之一，都允许；但必须零失败
        last_ok = s["result"] == "pass" and len(s["cases"]) in (sw, sw + ms)
    return ("runall_counts", ok and (last_ok is not False),
            "sw=%d ms=%d doc=(%s,%s) last=%s" % (sw, ms, m1 and m1.group(1), m2 and m2.group(1), last_ok))


def main():
    checks = [check_links(), check_frame_numbers(), check_algo_count(),
              check_sparkle_numbers(), check_runall_counts()]
    for name, ok, detail in checks:
        print("EVIDENCE_AUDIT %-22s %s  %s" % (name, "PASS" if ok else "FAIL", detail))
    ok = all(c[1] for c in checks)
    print("EVIDENCE_AUDIT", "PASS" if ok else "FAIL", "checks=%d" % len(checks))
    if not ok:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
