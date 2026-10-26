"""Assemble T01.tool-E2 evidence JSONs from the frozen on-disk execution records.

Reads (read-only): both candidates' native_* records / reports / area files,
docs/evidence historical JSONs + archives, 002820 frozen baseline, tool anchors.
Writes: docs/evidence/ddr1333_build_sta_20261017.json (dev-plan sec.4.2 name)
        docs/evidence/ddr1333_integration_timing_20261017.json (dispatch alias name)
Both files get identical content; each records the other as alias.
"""
from pathlib import Path
import hashlib, json, datetime, re

REPO = Path(r'C:\Users\czz\OneDrive\桌面\实验室\竞赛\嵌入式\FPGA创新设计赛道')
EV = REPO / 'docs' / 'evidence'
RUN = REPO / 'workflow' / 'runs' / '20261017_153201_T01_ddr1333_integration'
PRJ = Path('D:/TD/work/csi2/prj')
P1333 = PRJ / 'camera_rgb565_ddr1333_20261017_160741'
PCTL = PRJ / 'camera_rgb565_ddr1600ctl_20261017_160741'
P002820 = PRJ / 'camera_rgb565_wb_20261015_002820'
RUNNER = REPO / 'tools' / 'td' / 'run_rgb565_ddr1333.py'


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def frec(p):
    p = Path(p)
    return {'path': str(p), 'bytes': p.stat().st_size, 'sha256': sha(p)} if p.is_file() else None


def load(p):
    return json.loads(Path(p).read_bytes())


def sta_block(report):
    t = Path(report).read_text(errors='replace')
    vals = {}
    for ln in t.splitlines():
        s = ln.strip()
        if s.startswith('SWNS:'):
            parts = s.replace('ns', '').replace(',', '').split()
            vals.update(setup_ns=float(parts[1]), setup_tns_ns=float(parts[3]))
        elif s.startswith('HWNS:'):
            parts = s.replace('ns', '').replace(',', '').split()
            vals.update(hold_ns=float(parts[1]), hold_tns_ns=float(parts[3]))
        elif s.startswith('Period Check WNS:'):
            vals['period_ns'] = float(s.split()[3].replace('ns', ''))
    viol = []
    groups = 0
    for ln in t.splitlines():
        if 'Viol Endpoints' in ln:
            viol.append(int(re.search(r'([0-9]+) Viol Endpoints', ln).group(1)))
        elif ln.strip().startswith('Path Group'):
            groups += 1
    m = re.search(r'(\w+):\s+([0-9.]+)\s+\d+\s+ddr_user', t)
    clock = None
    if m:
        clock = {'clk_id': m.group(1), 'summary_freq_mhz': float(m.group(2))}
        row = re.search(r'(?m)^\s*' + re.escape(m.group(1)) + r'\s+\S+\s+\S+\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s', t)
        if row:
            clock.update(c_period_ns=float(row[3]), c_freq_mhz=float(row[4]))
    cov = re.search(r'STA coverage\s+:\s+([0-9.]+%)', t)
    return dict(sta=vals, endpoint_groups=len(viol), violating_endpoints_sum=sum(viol),
                path_groups=groups, ddr_user_clock=clock, sta_coverage=cov[1] if cov else None,
                report=dict(frec(report)))


def resources(area):
    a = Path(area).read_text(errors='replace')
    def g(pat):
        m = re.search(pat, a)
        return int(m[1]) if m else None
    return {k: g(v) for k, v in {'lut6': r'#lut6\s+(\d+)', 'reg': r'#reg\s+(\d+)', 'eram': r'#eram\s+(\d+)',
                                 'dsp': r'#dsp\s+(\d+)', 'pll': r'#pll\s+(\d+)'}.items()}


def duration(rec):
    a = datetime.datetime.fromisoformat(rec['started_at'])
    b = datetime.datetime.fromisoformat(rec['ended_at'])
    return round((b - a).total_seconds(), 1)


now = datetime.datetime.now().astimezone().isoformat()

records = {
    'ddr1333': {s: load(P1333 / ('native_' + s + '.json')) for s in ('build', 'route', 'bitgen')},
    'ddr1600ctl': {s: load(PCTL / ('native_' + s + '.json')) for s in ('build', 'route', 'bitgen')},
}

gate1333 = load(RUN / 'dev-notes-E2-gate-ddr1333.json')
gates = {
    'ddr1333': dict(gate1333, command="python -X utf8 -B tools/td/check_timing_margin.py D:/TD/work/csi2/prj/camera_rgb565_ddr1333_20261017_160741/capture_timing.rpt --min-setup-ns 0.3 --expected-endpoint-groups 66", exit_code=1,
                    stdout_file=frec(RUN / 'dev-notes-E2-gate-ddr1333.json'),
                    verdict='rejected: setup 0.230 < required 0.300 (all other conditions pass)'),
    'ddr1600ctl': dict(load(RUN / 'dev-notes-E2-gate-ctl.json'), command="python -X utf8 -B tools/td/check_timing_margin.py D:/TD/work/csi2/prj/camera_rgb565_ddr1600ctl_20261017_160741/capture_timing.rpt --min-setup-ns 0.3 --expected-endpoint-groups 68", exit_code=1,
                       stdout_file=frec(RUN / 'dev-notes-E2-gate-ctl.json'),
                       verdict='rejected: setup 0.128 < required 0.300 (all other conditions pass)'),
}

rechecks = {}
for tag, proj in (('ddr1333', P1333), ('ddr1600ctl', PCTL)):
    f = RUN / ('dev-notes-E2-sta-recheck-' + ('ddr1333' if tag == 'ddr1333' else 'ctl') + '.log')
    rechecks[tag] = {'file': frec(f), 'independent_line_parser_matches_runner': True,
                     'parser': 'line-scan parser (separate from runner regexes), same fields + Viol Endpoints count + Path Group count'}

shape = {
    'ddr1333': {
        'path_groups': 33, 'endpoint_groups': 66, 'expected_endpoint_groups_set': 66,
        'decision': 'expected=66 (identical to frozen 002820 66-group shape)',
        'reason': 'ordered Path Group name list identical to 002820 capture_timing.rpt (33 lines -> 66 Max/Min endpoint-group statistics); all 66 violation counts = 0; set/ordered equality machine-checked in E2 review',
    },
    'ddr1600ctl': {
        'path_groups': 34, 'endpoint_groups': 68, 'expected_endpoint_groups_set': 68,
        'decision': 'expected=68 (34 Path Group lines -> 68 statistics)',
        'reason': 'name SET identical to 002820/1333; the only difference vs the 1333 report is one extra occurrence of the mcu_clk -> mcu_clk group (14 -> 15), reproducing the historical 68-group shape note (APB readback/transfer_done grouping); all 68 violation counts = 0',
    },
}

hist = load(EV / 'camera_rgb565_wb_20261015_002820.json')
hist_phases = hist['g2']['phases']
h103222 = load(EV / 'camera_rgb565_timing_20261015_103222.json')['g2']
h111134 = load(EV / 'camera_rgb565_timing_20261015_111134.json')['g2']
h114913 = load(EV / 'camera_rgb565_timing_20261015_114913.json')['g2']
cli622 = frec(Path('D:/downlaod/bin/td_commands_prompt.exe'))

def hist_row(name, tool, phases, ns, archive, strategy, notes, bitgen_phases=None):
    row = {'candidate': name, 'tool': tool, 'cli': cli622 if tool == 'TD 6.2.2' else None,
           'build_script_sha': phases['build']['script_sha256'], 'route_script_sha': phases['route']['script_sha256'],
           'bitgen_script_sha': phases['bitgen']['script_sha256'] if bitgen_phases else None,
           'runner_sha': phases['route']['runner_sha256'], 'manifest_sha': ns['input_manifest_sha256'],
           'manifest_items': 221, 'strategy': strategy,
           'build': {'exit_code': phases['build']['exit_code'], 'marker_present': phases['build']['marker_present'],
                      'gate_db_sha256': list(phases['build']['artifacts'].values())[0]},
           'route': {'exit_code': phases['route']['exit_code'], 'marker_present': phases['route']['marker_present'],
                      'selected_db_sha256': phases['route'].get('selected_db_sha256')},
           'bitgen': ({'exit_code': phases['bitgen']['exit_code'], 'marker_present': phases['bitgen']['marker_present'],
                        'bit_sha256': phases['bitgen']['artifacts'].get('camera_ddr_display.bit')} if bitgen_phases else None),
           'route_report': sta_block(archive / 'capture_timing.rpt'),
           'resources': resources(archive / 'capture.area'), 'notes': notes}
    return row

historical_rows = [
    hist_row('002820 (baseline, frozen)', 'TD 6.2.2', hist_phases, hist,
             P002820, 'TimingHigh',
             'frozen WB baseline; bitgen accepted 6.2.2; route STA == bitgen STA', bitgen_phases=True),
]

# fix archive path for 002820 (read from the frozen project itself)
historical_rows[0]['route_report'] = sta_block(P002820 / 'capture_timing.rpt')
historical_rows[0]['resources'] = resources(P002820 / 'capture.area')
historical_rows[0]['manifest_items'] = 220

for tag, j, strategy, notes in (
    ('103222', h103222, 'TimingHigh', 'exploratory ready-timing RTL change; no bit; deliverable=false'),
    ('111134', h111134, 'TimingUltra', 'exploratory TimingUltra; no bit; deliverable=false'),
    ('114913', h114913, 'TimingUltra', 'exploratory 0.300ns reserve at implementation (guard -0.477 / nominal -0.177); no bit; deliverable=false'),
):
    arch = EV / ('camera_rgb565_timing_20261015_' + tag) / 'g2'
    phases = j['native_stages']
    if tag == '114913':
        phases = dict(phases, bitgen=None)
    historical_rows.append(hist_row(tag, 'TD 6.2.2', phases, {'input_manifest_sha256': j['native_stages']['build']['input_manifest_sha256']},
                                    arch, strategy, notes))

new_rows = []
for role, proj in (('ddr1333 (new IP, main)', P1333), ('ddr1600ctl (old IP control)', PCTL)):
    r = records[role.split()[0]]
    route_sta = sta_block(proj / 'capture_timing.rpt')
    bit_sta = sta_block(proj / 'candidate_timing.rpt')
    new_rows.append({**{
        'candidate': role, 'tool': 'TD 6.2.3 (Release_2026.2, DB_VERSION 46207)', 'cli': r['build']['td_cli'],
        'build_script_sha': r['build']['script_sha256'], 'route_script_sha': r['route']['script_sha256'],
        'bitgen_script_sha': r['bitgen']['script_sha256'], 'runner_sha': r['build']['runner_sha256'],
        'manifest_sha': r['build']['input_manifest_sha256'], 'manifest_items': r['build']['input_manifest_items'],
        'strategy': 'TimingHigh',
        'build': {'exit_code': r['build']['exit_code'], 'marker_present': r['build']['marker_present'],
                  'gate_db_sha256': list(r['build']['artifacts'].values())[0], 'duration_s': duration(r['build'])},
        'route': {'exit_code': r['route']['exit_code'], 'marker_present': r['route']['marker_present'],
                  'selected_db_sha256': r['route']['selected_db_sha256'], 'duration_s': duration(r['route'])},
        'bitgen': {'exit_code': r['bitgen']['exit_code'], 'marker_present': r['bitgen']['marker_present'],
                   'bit_sha256': r['bitgen']['artifacts'].get('camera_ddr_display.bit'), 'duration_s': duration(r['bitgen']),
                   'prechecks': r['bitgen'].get('bitgen_prechecks')},
        'route_report': route_sta, 'bitgen_report': bit_sta,
        'resources': resources(proj / 'capture.area'),
        'notes': 'nominal, no reserve; same runner/scripts/tool as the other 6.2.3 row; only difference = DDR IP closure + rate',
    }})

table = {
    'fields': ['candidate', 'tool+cli', 'build/route/bitgen script sha', 'runner sha', 'manifest sha+items',
               'build exit/marker/gate.db sha', 'route exit/marker/selected db sha', 'final STA route (setup/STNS, hold/HTNS, period)',
               'endpoint groups / violating endpoints', 'report sha', 'ddr_user period', 'resources LUT/REG/ERAM/DSP/PLL', 'strategy', 'notes'],
    'rows_6_2_3': new_rows,
    'rows_6_2_2_history': historical_rows,
    'caveat': '6.2.2 rows carry the older toolchain; cross-row comparison mixes tool version; the 1600ctl row isolates the DDR-rate factor on 6.2.3',
}

drc = {
    'ddr1333': {'tmst_7700_lines_in_route_log': 3, 'severe_counts': ['1 (place stage)', '4 (route stage)', '4 (route report DRC)'],
                'route_exit_code': 0, 'marker_present': True},
    'ddr1600ctl': {'tmst_7700_lines_in_route_log': 3, 'severe_counts': ['1 (place stage)', '4 (route stage)', '4 (route report DRC)'],
                   'route_exit_code': 0, 'marker_present': True},
    'history_6_2_2': 'TMST-7700 string count = 0 in 002820/103222/111134/114913 route logs (message code appears only in TD 6.2.3)',
    'interpretation': 'TD 6.2.3 route DRC reports 4 SEVERE timing-constraint issues on BOTH candidates (old-IP control included) => tool-version behavior on this design, not a new-IP defect; details ("check_timing report") were not generated by the frozen scripts; unresolved open item (honest boundary)',
    'sta_coverage': {'ddr1333': '96.49%', 'ddr1600ctl': '96.43%', '002820_6_2_2': '97.99%'},
}

zero = {
    'ddr1333_manifest_recheck': {'items': 221, 'mismatches': [], 'manifest_sha_ok': True},
    'ddr1600ctl_manifest_recheck': {'items': 221, 'mismatches': [], 'manifest_sha_ok': True},
    '002820_manifest_sha': sha(P002820 / 'input_manifest.json'),
    '002820_bit_sha': sha(P002820 / 'camera_ddr_display.bit'),
    'run1_source_manifest_sha': sha(Path('D:/TD/work/csi2/_validation/td2026_gui_bootstrap_20261017_000935/candidate_manifest.json')),
    'run2_mirror_manifest_sha': sha(Path('D:/TD/work/csi2/_validation/td2026_b_run2_20261017_143128/run2_candidate_manifest.json')),
}

tee_logs = {}
for n in ('ddr1333-build', 'ddr1333-route', 'ddr1333-bitgen', 'ctl-build', 'ctl-route', 'ctl-bitgen'):
    tee_logs['dev-notes-E2-run-' + n + '.log'] = frec(RUN / ('dev-notes-E2-run-' + n + '.log'))

td_logs = {}
for tag, proj in (('ddr1333', P1333), ('ddr1600ctl', PCTL)):
    for f in sorted(list(proj.glob('td_*.log')) + list(proj.glob('td_*.logw'))):
        td_logs[tag + '/' + f.name] = frec(f)

native_files = {}
for tag, proj in (('ddr1333', P1333), ('ddr1600ctl', PCTL)):
    for s in ('build', 'route', 'bitgen'):
        for ext in ('json', 'txt'):
            native_files[tag + '/native_' + s + '.' + ext] = frec(proj / ('native_' + s + '.' + ext))

bitgen_files = {}
for tag, proj in (('ddr1333', P1333), ('ddr1600ctl', PCTL)):
    for n in ('camera_ddr_display.bit', 'camera_ddr_display_inst.bid'):
        bitgen_files[tag + '/' + n] = frec(proj / n)

run_dir_files = {}
for f in sorted(RUN.iterdir()):
    if f.is_file():
        run_dir_files[f.name] = frec(f)

evidence = {
    'schema': 1,
    'kind': 'ddr1333_build_sta_E2',
    'workpackage': 'T01.tool-E2 — TD 6.2.3 full chain (syn -> route -> final STA) for camera_rgb565_ddr1333_20261017_160741 and camera_rgb565_ddr1600ctl_20261017_160741; same-toolchain comparison table; honest 0.300ns assessment; conditional bitgen (no hardware)',
    'recorded_at': now,
    'run_dir': 'workflow/runs/20261017_153201_T01_ddr1333_integration',
    'status': 'ready_for_test (build/route/STA/bitgen executed and recorded; timings recorded honestly; no hardware action)',
    'evidence_files': {
        'canonical (dev-plan sec.4.2 name)': 'docs/evidence/ddr1333_build_sta_20261017.json',
        'alias (dispatch name, identical content)': 'docs/evidence/ddr1333_integration_timing_20261017.json',
        'note': 'both files are written from the same assembler run with identical content; either may be cited',
    },
    'frozen_inputs': {
        'candidates': {
            'ddr1333': {'path': str(P1333), 'input_manifest_sha256': sha(P1333 / 'input_manifest.json'),
                        'items': 221, 'overlay_sha256': sha(P1333 / 'ddr1333_overlay.json')},
            'ddr1600ctl': {'path': str(PCTL), 'input_manifest_sha256': sha(PCTL / 'input_manifest.json'),
                           'items': 221, 'overlay_sha256': sha(PCTL / 'ddr1333_overlay.json')},
        },
        'tool_6_2_3': records['ddr1333']['build']['td_cli'],
        'tool_anchors': records['ddr1333']['build']['tool_anchors'],
        'tool_6_2_2_frozen': cli622,
    },
    'runner': {'file': frec(RUNNER), 'assertion_floor': 'full run_rgb565_native.py floor + CLI SHA + script SHA + execution_ok/timing split + fail-closed bitgen; negative tests (-O guard, bad name, wrong parent) verified without writes',
               'sha_used_in_all_records': records['ddr1333']['build']['runner_sha256']},
    'executions': records,
    'sta_rechecks': rechecks,
    'report_shape_review': shape,
    'gate_0_300': gates,
    'comparison_table': table,
    'drc_observations': drc,
    'bitgen_cwc': {
        'bitgen': 'executed for BOTH candidates (each STA all non-negative, TNS=0, 4 skew constraints with min slack>0, 0 abnormal endpoints)',
        'cwc_export': 'not_run (optional; no hardware path in this batch; not needed for the comparison data)',
    },
    'post_run_zero_drift': zero,
    'deviations_from_plan': [
        {'item': 'evidence filename', 'detail': 'dev-plan sec.4.2 named ddr1333_build_sta_<date>.json; dispatch named ddr1333_integration_timing_<date>.json; both written with identical content'},
        {'item': 'stage timeouts', 'detail': 'dispatch caps used: build 1800s, route 3600s, bitgen 900s (dev-plan wrote 2400/5400/1800); no stage timed out'},
        {'item': 'bitgen scope', 'detail': 'bitgen run for both candidates (dev-plan allowed 1333 and/or ctl); CWC export skipped as optional'},
    ],
    'artifacts_inventory': {
        'run_dir_files': run_dir_files, 'td_cli_logs': td_logs, 'native_stage_records': native_files,
        'tee_logs': tee_logs, 'bitgen_outputs': bitgen_files,
        'note': 'large DBs/bit files stay in the candidates on D:; hashes recorded here',
    },
    'known_limits': [
        'No hardware action of any kind: no download, no Flash, no GUI; generated .bit files are candidates only.',
        '0.300ns exploration objective NOT met by either candidate (1333: 0.230; 1600ctl: 0.128); this is the honest nominal result; the objective is a self-imposed exploration line, not a device guarantee.',
        'TMST-7700 (4 SEVERE timing-constraint issues) emitted by TD 6.2.3 route DRC on both candidates; absent in 6.2.2 logs; detailed check_timing report not generated by the frozen scripts; open item for planner/E3/user.',
        'STA coverage 96.49%/96.43% vs 97.99% (002820, 6.2.2); difference observed, not fully explained in this batch.',
        '6.2.2 rows vs 6.2.3 rows mix tool version; only the 1333-vs-1600ctl pair is same-tool, same-script, same-runner.',
        'Endpoint-group count for the gate was reviewed manually and set explicitly per report (66 for 1333, 68 for ctl); the gate counts Path-Group lines and violation entries, not physical uniqueness.',
        'capture_route_drc.rpt produced by report_route_status -drc was not written by either tool version (same as historical behavior); no regression claimed from it.',
        'Real DDR calibration/board behavior, color acceptance, HDMI electrical/thermal and long-run stability remain untested (later board phases).',
    ],
}

evidence['run_notes'] = {
    'dev_notes': frec(RUN / 'dev-notes-E2.md'),
    'lessons_learned': frec(RUN / 'lessons-learned.md'),
    'gate_outputs': {'ddr1333': frec(RUN / 'dev-notes-E2-gate-ddr1333.json'),
                     'ddr1600ctl': frec(RUN / 'dev-notes-E2-gate-ctl.json')},
    'sta_rechecks': {'ddr1333': frec(RUN / 'dev-notes-E2-sta-recheck-ddr1333.log'),
                     'ddr1600ctl': frec(RUN / 'dev-notes-E2-sta-recheck-ctl.log')},
}
evidence['assembly_history'] = [
    {'pass': 1, 'note': 'initial assembly right after bitgen; evidence sha 4ff87e812fff383c14d341927dd4e61b1c6be87fda6846c91e2360dfb8243adf'},
    {'pass': 2, 'note': 'second pass: adds run_notes (dev-notes-E2.md / lessons-learned.md / gate and recheck files) and refreshed run_dir_files inventory; identical-content pair maintained'},
]

text = json.dumps(evidence, indent=2, ensure_ascii=False) + '\n'
canonical = EV / 'ddr1333_build_sta_20261017.json'
alias = EV / 'ddr1333_integration_timing_20261017.json'
if canonical.exists() or alias.exists():
    # this assembler may refresh only the pair it produced: byte-identical pair, same kind tag
    assert canonical.exists() and alias.exists(), 'refuse to create missing half of the evidence pair'
    assert sha(canonical) == sha(alias), 'refuse to overwrite a drifted evidence pair'
    assert load(canonical).get('kind') == 'ddr1333_build_sta_E2', 'refuse to overwrite foreign evidence'
canonical.write_text(text, encoding='utf-8')
alias.write_text(text, encoding='utf-8')
print('canonical', canonical, len(text.encode('utf-8')), sha(canonical))
print('alias    ', alias, len(text.encode('utf-8')), sha(alias))
print('rows_6_2_3', [r['candidate'] for r in table['rows_6_2_3']])
print('rows_history', [r['candidate'] for r in table['rows_6_2_2_history']])
