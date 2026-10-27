import hashlib, json, os
RUN = r"D:\fpga\ph1p100\workflow\runs\20261026-143924_fpga-1080p30-g0-production\T10.ss-g0-prod-content\r0"
m = json.load(open(os.path.join(RUN, 'manifest-r0.json')))
bad = []
for a in m['artifacts']:
    p = a['path']
    if not os.path.exists(p):
        bad.append((a['rel'], 'MISSING'))
        continue
    h = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    if h != a['sha256'] or os.path.getsize(p) != a['bytes']:
        bad.append((a['rel'], 'DRIFT'))
print("artifacts:", len(m['artifacts']), "drift/missing:", bad)
print("stopped_modifying:", m['stopped_modifying'], "active_commands:", m['active_commands'])
print("verdict headline:", m['verdict']['headline'], m['verdict']['per_class'])
a = json.load(open(os.path.join(RUN, 'content-audit.json')))
print("audit conclusion:", json.dumps(a.get('conclusion'), indent=1)[:900])
print("audit sensor hits:", len(a['sensor_raw_search']['hits']), "truncated:", a['sensor_raw_search']['truncated'])
