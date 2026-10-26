# G-package helper: read-only PDF term search with context (pymupdf). No files written except stdout.
import sys, re

def main():
    import fitz  # PyMuPDF
    path = sys.argv[1]
    terms = sys.argv[2].split('|')
    ctx = int(sys.argv[3]) if len(sys.argv) > 3 else 160
    doc = fitz.open(path)
    total_hits = 0
    for i, page in enumerate(doc):
        try:
            text = page.get_text("text")
        except Exception as e:
            print(f"PAGE_ERR p{i}: {e}")
            continue
        flat = re.sub(r"\s+", " ", text)
        for t in terms:
            for m in re.finditer(re.escape(t), flat, re.IGNORECASE):
                s = max(0, m.start() - ctx)
                e = min(len(flat), m.end() + ctx)
                snippet = flat[s:e]
                print(f"PDF={path} PAGE={i+1} TERM={t} :: ...{snippet}...")
                total_hits += 1
                if total_hits > 200:
                    print("...TRUNCATED at 200 hits")
                    return
    print(f"TOTAL_HITS={total_hits} PAGES={len(doc)}")

main()
