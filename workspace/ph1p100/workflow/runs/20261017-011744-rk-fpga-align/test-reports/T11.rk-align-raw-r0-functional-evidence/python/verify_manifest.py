#!/usr/bin/env python3
"""Independent manifest verifier (functional r0 evidence).

Written by the functional tester, NOT reusing the developer's gen_manifest scripts.
Recomputes SHA256 of every entry in candidate-manifest.json using the manifest's own
path_base declarations and reports mismatches / missing files.
"""
import hashlib
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", ".."))
RUN = os.path.join(ROOT, "workflow", "runs", "20261017-011744-rk-fpga-align")
MANIFEST = os.path.join(RUN, "raw", "candidate-manifest.json")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def main():
    with open(MANIFEST, "rb") as f:
        raw_bytes = f.read()
    manifest_sha = hashlib.sha256(raw_bytes).hexdigest()
    m = json.loads(raw_bytes.decode("utf-8"))
    print("manifest:", MANIFEST)
    print("manifest_sha256(bytes, as-is):", manifest_sha)
    # canonical: JSON file bytes as read (UTF-8, no newline normalization)
    expected_sha = "AAB0CC08EF0134D5FCB18B25E0B70C43E9AF1D577513CA2996DC46F22DE76975"
    print("matches claimed AAB0CC08...:", manifest_sha.upper() == expected_sha)

    bases = {
        "production_inputs": ROOT,
        "build_scripts": ROOT,
        "test_inputs": ROOT,
        "rk_patch_inputs": RUN,
        "build_artifacts": RUN,
    }
    total = 0
    bad = []
    missing = []
    for key, base in bases.items():
        entries = m.get(key, [])
        print(f"category {key}: {len(entries)} entries, base={base}")
        for e in entries:
            total += 1
            p = os.path.join(base, e["path"])
            if not os.path.isfile(p):
                missing.append((key, e["path"]))
                continue
            got = sha256_file(p)
            if got.lower() != e["sha256"].lower():
                bad.append((key, e["path"], e["sha256"], got))
    print(f"TOTAL entries checked: {total}")
    print(f"MISMATCH: {len(bad)}")
    for b in bad:
        print("  BAD", b)
    print(f"MISSING: {len(missing)}")
    for x in missing:
        print("  MISS", x)
    ok = (not bad) and (not missing)
    print("SELF-CHECK RESULT:", "ALL_HASHES_OK" if ok else "INTEGRITY_PROBLEM")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
