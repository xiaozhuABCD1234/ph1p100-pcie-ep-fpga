"""Read-only package integrity check using only the Python standard library.

Run from any directory: python -B <relative path to this script>.
Only files inside this handoff package are opened. No original source tree,
simulator, TD tool or hardware is accessed and no output file is written.
"""
from pathlib import Path
import hashlib
import json
import sys


def main():
    root = Path(__file__).resolve().parent
    data = json.loads((root / 'source-map.json').read_text(encoding='utf-8'))
    errors = []
    checked = 0
    total = 0
    seen = set()
    for row in data['files']:
        name = row.get('package_path')
        if not name or row['status'] not in {'included', 'generated'}:
            continue
        target = (root / name).resolve()
        if not target.is_relative_to(root):
            errors.append('OUTSIDE_PACKAGE ' + name)
            continue
        if name in seen:
            continue
        seen.add(name)
        if not target.is_file():
            errors.append('MISSING ' + name)
            continue
        size = target.stat().st_size
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if size != row['bytes'] or actual != row['sha256']:
            errors.append('SHA_OR_SIZE_MISMATCH ' + name)
        checked += 1
        total += size
    for row in data['manifest_bindings']:
        if row.get('package_path'):
            if row['package_path'] not in seen:
                errors.append('UNINDEXED_BINDING ' + row['package_path'])
    print('PACKAGE_INTEGRITY ' + ('FAIL' if errors else 'PASS'))
    print('checked_files=%d checked_bytes=%d' % (checked, total))
    print('historical_bindings=%d drift=%d missing_or_excluded_large=%d' % (
        len(data['manifest_bindings']), sum(r['status'] == 'drift' for r in data['manifest_bindings']),
        sum(r['status'] == 'missing_or_excluded_large' for r in data['manifest_bindings'])))
    print('This checks copied bytes, not simulation, timing, bitstream or hardware acceptance.')
    for err in errors:
        print(err)
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
