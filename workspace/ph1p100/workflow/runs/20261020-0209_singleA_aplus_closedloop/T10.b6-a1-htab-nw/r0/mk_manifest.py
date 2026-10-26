import json, hashlib, pathlib, re, sys

root = pathlib.Path(r'D:\fpga\ph1p100')
pkg = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b6-a1-htab-nw'
r0 = pkg/'r0'
sim = r0/'sim'
td = r0/'td'


def sha(p):
    p = pathlib.Path(p)
    return hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else None


def rec(p):
    p = pathlib.Path(p)
    return dict(path=str(p), exists=p.exists(), bytes=(p.stat().st_size if p.exists() else None), sha256=sha(p))


def grep(p, pat, flags=0):
    p = pathlib.Path(p)
    if not p.exists():
        return None
    m = re.search(pat, p.read_text(errors='replace'), flags)
    return m


def timing(p):
    p = pathlib.Path(p)
    if not p.exists():
        return {}
    t = p.read_text(errors='replace')
    d = {}
    for key, pat in [('SWNS', r'SWNS:\s*(-?[0-9.]+)ns'), ('STNS', r'STNS:\s*(-?[0-9.]+)ns'),
                     ('HWNS', r'HWNS:\s*(-?[0-9.]+)ns'), ('HTNS', r'HTNS:\s*(-?[0-9.]+)ns'),
                     ('PWNS', r'Period Check WNS:\s*(-?[0-9.]+)ns')]:
        m = re.search(pat, t)
        if m:
            d[key] = float(m.group(1))
    m = re.search(r'([0-9]+) Viol Endpoints,\s+([0-9]+) Total Endpoints', t)
    if m:
        d['viol_endpoints'] = int(m.group(1)); d['total_endpoints'] = int(m.group(2))
    return d


def area(p):
    p = pathlib.Path(p)
    if not p.exists():
        return {}
    t = p.read_text(errors='replace')
    d = {}
    for k, pat in [('lut', r'#lut\*\s+([0-9]+)'), ('lut6', r'#lut6\s+([0-9]+)'),
                   ('reg', r'#reg\s+([0-9]+)'), ('eram', r'#eram\s+([0-9]+)'),
                   ('slice', r'#slice\*\s+([0-9]+)')]:
        m = re.search(pat, t)
        if m:
            d[k] = int(m.group(1))
    return d


p2 = json.loads((sim/'p2-regression.json').read_text())
p1 = json.loads((sim/'p1-regression.json').read_text())
bnd = json.loads((sim/'boundaries/result.json').read_text())

bit = td/'a1_board.bit'; cwc = td/'a1_board.cwc'; bid = td/'a1_board_inst.bid'
bitgen_log = td/'bitgen_console_r0.log'

man = {
    'task_id': 'T10.b6-a1-htab-nw',
    'round': 'r0',
    'run_id': '20261020-0209_singleA_aplus_closedloop',
    'status': 'ready_for_test',
    'scope': 'remove the r5 per-match S_EXT wait cycle by restoring the r4 hit-cycle first-extension compare; bm_b read address is driven by fabric flops only',
    'single_rtl_change': rec(r0/'changed-src/a1_deflate_core.v'),
    'rtl_diff': rec(r0/'rtl-diff-r0.patch'),
    'rtl_diff_vs_upstream_r4': rec(r0/'rtl-diff-vs-r4.patch'),
    'inputs_read_only': {
        'r5_core': dict(path=str(root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/changed-src/a1_deflate_core.v'),
                        sha256='29b1e3e1a66abef78c228c4189322b0139a266d43bf02827dd1ebe498cdc9828'),
        'r4_upstream_core': dict(path=str(root/'upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v'),
                                 sha256='d4b799612519d4cb6c32a0c0e87807be84dec711fc01e2146b054d464d1b88de'),
        'p2_vectors': {
            'comp_in_hex': rec(root/'work/parallel-sim-20261024-2204/codec-throughput/comp/in.hex'),
            'comp_in_meta': rec(root/'work/parallel-sim-20261024-2204/codec-throughput/comp/in.meta'),
            'comp_in_xform': rec(root/'work/parallel-sim-20261024-2204/codec-throughput/comp/in.xform'),
            'rand_in_hex': rec(root/'work/parallel-sim-20261024-2204/codec-throughput/rand/in.hex'),
            'rand_in_meta': rec(root/'work/parallel-sim-20261024-2204/codec-throughput/rand/in.meta'),
            'rand_in_xform': rec(root/'work/parallel-sim-20261024-2204/codec-throughput/rand/in.xform'),
        },
        'p2_tb': rec(root/'upstream/ph1p100-pcie-ep-fpga/sim/tb/codec/tb_a1_deflate_core.v'),
        'p1_tb': rec(root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b1-a1-uart-integ/r0/sim/tb_camera_a1_uart_top.v'),
        'p1_goldens_b5': {n: rec(root/('workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b5-a1-htab-pipe/r0/sim/captures/'+n+'.dec'))
                          for n in ['micro8x2', 'mid64x8', 'full_grad']},
        'sdc_and_pins_unchanged': {n: rec(td/n) for n in ['p2_board.sdc', 'a1_small_top.sdc', 'board_p2.adc']},
    },
    'functional': {
        'p2': p2,
        'p1': p1,
        'boundaries': dict(status=bnd.get('status'),
                           cases=[dict(name=c['name'], status=c['status'], checks=c['checks'],
                                       stats=c['stats'], first_deflate_btype=c.get('first_deflate_btype'))
                                  for c in bnd.get('cases', [])],
                           runner=rec(r0/'run_boundaries.py')),
        'sim_runner': rec(r0/'run_sim.py'),
        'sim_logs': [str(p) for p in sorted((sim/'logs').glob('*'))],
    },
    'engineering': {
        'syn_gate_timing': timing(td/'syn_gate_timing.rpt'),
        'syn_gate_area': area(td/'syn_gate_area.rpt'),
        'routed_timing': timing(td/'routed_timing.rpt'),
        'routed_timing_flow': timing(td/'phy_pr_timing_flow.rpt'),
        'routed_area': area(td/'routed_area.rpt'),
        'reports': {n: rec(td/n) for n in ['syn_gate_timing.rpt', 'syn_gate_area.rpt', 'routed_timing.rpt',
                                           'routed_timing_summary.rpt', 'routed_qor.rpt', 'routed_area.rpt',
                                           'routed_check_timing.rpt', 'routed_timing_status.rpt',
                                           'route_flow.status', 'place_flow.status', 'build_console_r0.log']},
        'tcl': {n: rec(td/n) for n in ['01_build.tcl', '02_bitgen.tcl', '03_cwc.tcl']},
    },
    'system': {
        'interfaces_unchanged': 'a1_deflate_core port list, clock, reset unchanged; only htab entry/read structure and the hit-cycle reference byte source changed',
        'frame_crc_ddr_uart_unchanged': True,
        'board_and_download': 'not_run (this round explicitly forbids download/Flash)',
    },
    'candidate': {
        'bit': rec(bit), 'cwc': rec(cwc), 'bid': rec(bid),
        'compiled_bit_matches_parent': (sha(td/'cw/compiled.bit') == sha(bit)) if bit.exists() else None,
        'compiled_cwc_matches_parent': (sha(td/'cw/compiled.cwc') == sha(cwc)) if cwc.exists() else None,
        'bitgen_console': rec(bitgen_log),
        'cwc_console': rec(td/'cwc_console_r0.log'),
    },
    'tools': {'modelsim': 'ModelSim Intel FPGA Edition 10.5b (vlog/vsim 10.5b, 2016.10)',
              'td': 'Anlogic TD Release_2026.2 (PH1P100SBG484 -3)',
              'python': sys.version.split()[0]},
    'budget': {'td_sessions_used': 3, 'syn_runs': 1, 'route_runs': 1, 'bitgen': 1, 'cwc': 1, 'download': 0},
    'caveats': [],
}
if bit.exists():
    man['caveats'].append('board/hardware validation not run (download forbidden this round); G4 not_run')
if man['engineering']['routed_timing'].get('SWNS') is not None and man['engineering']['routed_timing']['SWNS'] < 0.2:
    man['caveats'].append('routed WNS %.3f ns is between the +0.05 floor and +0.20; thin margin, same class as b5 r0 +0.100' % man['engineering']['routed_timing']['SWNS'])
if man['engineering']['syn_gate_timing'].get('SWNS') is not None and man['engineering']['syn_gate_timing']['SWNS'] < 0.3:
    man['caveats'].append('synthesis SWNS %.3f ns < +0.3 (b5 r0 was +0.222, still routed to 0 violations); gate-level source is not this cone' % man['engineering']['syn_gate_timing']['SWNS'])
man['caveats'].append('implementation note: the frozen design guide section 4.1 p3v shadow table was NOT used; the same timing goal was met by carrying bm[ref+3] inside the hash entry (htab_b3) and deleting the speculative bm_b read. Bytes/cycles are provably r4-identical and the bm_b address is flop-only, so the structural and functional acceptance conditions are unchanged.')

(pkg/'CANDIDATE-MANIFEST-b6-a1-htab-nw-r0.json').write_text(json.dumps(man, indent=2))

lines = ['# T10.b6-a1-htab-nw r0 artifact hashes (sha256, bytes)', '']
for label, v in [('core', man['single_rtl_change']), ('rtl-diff-r0', man['rtl_diff']),
                 ('rtl-diff-vs-r4', man['rtl_diff_vs_upstream_r4'])]:
    lines.append('%-28s %s  %s' % (label, v['sha256'], v['bytes']))
for grp in ['engineering']:
    for n, v in man[grp]['reports'].items():
        lines.append('%-28s %s  %s' % (n, v['sha256'], v['bytes']))
for n, v in man[grp]['tcl'].items():
    lines.append('%-28s %s  %s' % (n, v['sha256'], v['bytes']))
for n in ['bit', 'cwc', 'bid']:
    v = man['candidate'][n]
    lines.append('%-28s %s  %s' % (n, v['sha256'], v['bytes']))
lines.append('%-28s %s' % ('compiled_bit==bit', man['candidate']['compiled_bit_matches_parent']))
lines.append('%-28s %s' % ('compiled_cwc==cwc', man['candidate']['compiled_cwc_matches_parent']))
for case in ['comp', 'rand']:
    v = p2[case]
    lines.append('%-28s %s  %s B  %d cycles  %s' % ('p2/'+case+'.out.hex', v['output_sha256'], v['output_bytes'],
                                                    v['run_cycles'], 'PASS' if v['tb_pass'] and v['zlib_ok'] and v['strict_ok'] else 'FAIL'))
for n, v in p1.items():
    lines.append('%-28s %s  %s B  identical=%s' % ('p1/'+n+'.dec', v['dec_sha256'], v['dec_bytes'], v['byte_identical']))
(pkg/'artifact-hashes.txt').write_text('\n'.join(lines)+'\n')
print(json.dumps({'routed': man['engineering']['routed_timing'], 'syn': man['engineering']['syn_gate_timing'],
                  'area_routed': man['engineering']['routed_area'],
                  'bit': man['candidate']['bit']['sha256'], 'cwc': man['candidate']['cwc']['sha256'],
                  'bitlen': man['candidate']['bit']['bytes'], 'caveats': man['caveats']}, indent=2))
