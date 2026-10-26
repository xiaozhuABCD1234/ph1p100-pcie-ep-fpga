# G follow-up helper: deterministic recursive hash snapshot of a directory (read-only).
import hashlib, os, sys
from pathlib import Path

def main():
    root = Path(sys.argv[1]); out = Path(sys.argv[2])
    lines = []
    total = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            p = Path(dirpath) / name
            rel = p.relative_to(root).as_posix()
            try:
                data = p.read_bytes()
            except OSError as e:
                lines.append(f"{rel}\tERROR\t{e}")
                continue
            total += len(data)
            lines.append(f"{rel}\t{len(data)}\t{hashlib.sha256(data).hexdigest()}")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"files={len(lines)} bytes={total} out={out}")

main()
