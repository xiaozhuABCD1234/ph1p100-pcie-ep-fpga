import importlib.util, os, json
tr = r"T:\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.a1-enc-rtl\tester-r0"
spec = importlib.util.spec_from_file_location('idv', os.path.join(tr, 'independent_decode.py'))
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
idx = json.load(open(os.path.join(os.path.dirname(tr), 'p2', 'cases', 'index.json'), encoding='utf-8'))
for c in idx['cases']:
    xf = open(c['xform'], 'rb').read()
    o, i = m.parse_zlib_stream(m.load_hex(os.path.join(tr, 'runs', c['name'], 'out.hex')), len(xf))
    print(f"{c['name']:34s} matches={i['matches']:5d} min={i['minlen']:3d} max={i['maxlen']:3d} maxd={i['maxdist']:5d} dist1={i['has_dist1']} ndists={i['ndists']}")
