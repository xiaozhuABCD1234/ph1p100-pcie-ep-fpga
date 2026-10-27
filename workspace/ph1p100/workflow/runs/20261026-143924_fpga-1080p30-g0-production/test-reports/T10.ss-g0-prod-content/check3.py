import json, os
from PIL import Image
RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
OUT = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\test-reports\T10.ss-g0-prod-content"

print("=== commands.jsonl (raw) ===")
for i, ln in enumerate(open(os.path.join(RUN, 'sim', 'commands.jsonl'), encoding='utf-8')):
    print(i, ln.strip()[:400])

print("=== content-audit summary ===")
a = json.load(open(os.path.join(RUN, 'content-audit.json')))
print("top-level keys:", list(a.keys()))
print("no_real_sensor_raw:", a.get('no_real_sensor_raw'))
print(json.dumps({k: v for k, v in a.items() if k not in ('candidates', 'entries', 'items')}, indent=1)[:1500])
cand = a.get('candidates') or a.get('entries') or a.get('items') or []
print("n candidates:", len(cand))
for c in cand:
    print(" ", c.get('id'), "|", c.get('classification') or c.get('class'), "|",
          str(c.get('path'))[-58:], "|", c.get('usable'), c.get('labels'))

print("=== thumbnails ===")
ims = []
for name, lab in (("img102.jpg", "N: img102.jpg"), ("img105.jpg", "L: img105.jpg")):
    im = Image.open(os.path.join(r"C:\Windows\Web\Screen", name)).convert("RGB")
    im.thumbnail((760, 760))
    ims.append((im, lab))
W = sum(i.width for i, _ in ims) + 20
H = max(i.height for i, _ in ims) + 10
comp = Image.new("RGB", (W, H), (255, 255, 255))
x = 0
for im, lab in ims:
    comp.paste(im, (x, 0))
    x += im.width + 20
comp.save(os.path.join(OUT, "source-images-thumb.png"))
print("saved", comp.size)
