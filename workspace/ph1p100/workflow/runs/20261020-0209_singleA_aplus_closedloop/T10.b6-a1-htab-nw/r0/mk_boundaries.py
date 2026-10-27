import pathlib

src = pathlib.Path(r'D:\fpga\ph1p100\work\parallel-sim-20261024-2204\boundaries\run_boundaries.py')
t = src.read_text(encoding='utf-8')
old_out = "OUT=ROOT/'work/parallel-sim-20261024-2204/boundaries'; RUN=ROOT/'workflow/runs/20261020-0209_singleA_aplus_closedloop'; B5=RUN/'T10.b5-a1-htab-pipe/r0'"
new_out = "OUT=ROOT/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw/r0/sim/boundaries'; RUN=ROOT/'workflow/runs/20261020-0209_singleA_aplus_closedloop'; B6=RUN/'T10.b6-a1-htab-nw/r0'"
assert t.count(old_out) == 1
t = t.replace(old_out, new_out)
t = t.replace('B5', 'B6')
old_h = "'a1_deflate_core.v':'29b1e3e1a66abef78c228c4189322b0139a266d43bf02827dd1ebe498cdc9828'"
new_h = "'a1_deflate_core.v':'6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb'"
assert t.count(old_h) == 1
t = t.replace(old_h, new_h)
t = t.replace("'input_manifest':str(B6/'CANDIDATE-MANIFEST-b5-a1-htab-pipe-r0.json')",
              "'input_manifest':str(B6/'CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json')")
t = t.replace('Frozen r5 DUT sources', 'Frozen b6 DUT sources')
assert 'B5' not in t
out = pathlib.Path(r'D:\fpga\ph1p100\workflow\runs\20261020-0209_singleA_aplus_closedloop\T10.b6-a1-htab-nw\r0\run_boundaries.py')
out.write_text(t, encoding='utf-8', newline='\n')
print('written', out, len(t))
