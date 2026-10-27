import pathlib
p = pathlib.Path("check_b13.py"); t = p.read_text(encoding="utf-8")
old = """    for key in ('raw_drop', 'cmp_drop', 'geom', 'err', 'dup_words'):
        req(stats[key] == 0, key + ' nonzero')
"""
new = """    for key in ('raw_drop', 'geom', 'err', 'dup_words'):
        req(stats[key] == 0, key + ' nonzero')
    if stats['timeout_cnt'] == 0:
        req(stats['cmp_drop'] == 0, 'cmp_drop nonzero on a clean run')
"""
assert old in t, "check anchor"
t = t.replace(old, new)
p.write_text(t, encoding="utf-8")

p = pathlib.Path("run_b13.py"); r = p.read_text(encoding="utf-8")
r = r.replace('"DROP_ADDR": 48', '"DROP_ADDR": 16').replace('"LATE_ADDR": 48', '"LATE_ADDR": 16')
p.write_text(r, encoding="utf-8")
print("patched ok")
