import hashlib,json
m=json.load(open(r'D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\INT.P1-r0-manifest.json'))
def sha(p):
    h=hashlib.sha256()
    f=open(p,'rb')
    for c in iter(lambda:f.read(65536),b''):
        h.update(c)
    f.close()
    return h.hexdigest()
for e in m['production_inputs']:
    print('PROD', e['path'], sha(e['path'])==e['sha256'])
for e in m.get('test_input_entries',[]):
    print('TEST', e['path'], sha(e['path'])==e['sha256'])