# G-package helper: dump given PDF page range as text (pymupdf), read-only.
import sys, re

def main():
    import fitz
    path = sys.argv[1]
    p_from = int(sys.argv[2]); p_to = int(sys.argv[3])
    term = sys.argv[4] if len(sys.argv) > 4 else None
    doc = fitz.open(path)
    for i in range(p_from - 1, min(p_to, len(doc))):
        text = doc[i].get_text("text")
        if term:
            flat = re.sub(r"\s+", " ", text)
            for m in re.finditer(re.escape(term), flat, re.IGNORECASE):
                s = max(0, m.start() - 150); e = min(len(flat), m.end() + 250)
                print(f"PAGE={i+1} TERM={term} :: ...{flat[s:e]}...")
        else:
            print(f"===== PAGE {i+1} =====")
            print(text)

main()
