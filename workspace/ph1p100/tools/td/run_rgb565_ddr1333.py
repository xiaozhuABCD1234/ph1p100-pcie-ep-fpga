"""Run one explicit native TD 6.2.3 phase for the DDR1333 integration candidates.

T01.tool-E2 runner (see dev-plan sec.4.2 in
workflow/runs/20261017_153201_T01_ddr1333_integration/). This is a NEW runner;
tools/td/run_rgb565_native.py stays frozen as the 6.2.2 runner.

Assertion floor inherited from run_rgb565_native.py (not weakened):
  * refuses -O execution;
  * project must live directly under D:/TD/work/csi2/prj and start with
    camera_rgb565_;
  * full input_manifest.json SHA re-check of every item before any execution;
  * refusing to overwrite native_<stage>.json/.txt (failed runs preserved);
  * command = [<TD CLI>, ./<stage script>] with cwd = project directory;
  * success identities: exit code + in-script marker + non-empty artifacts + SHA;
  * real timeout (process tree killed, never left running);
  * route STA summary extraction (SWNS/STNS/HWNS/HTNS/Period Check WNS).

Record-only extensions (this batch, documented per dev-plan sec.4.2):
  * TD 6.2.3 CLI path+SHA asserted (2629e474...) before anything is executed;
  * tool anchor hashes (td.exe / IpTool.exe / arch db / license) recorded;
  * frozen build/route/bitgen script SHAs asserted;
  * runner/script/manifest/artifact/log bytes+SHA, endpoint group counts,
    ddr_user clock period, start/end wall clock, raw argv;
  * explicit execution_ok (exit0 + marker + complete artifacts drives the
    process exit code) versus timing records: the 0.300 gate with a reviewed
    expected endpoint count is run separately and recorded in the evidence
    JSON. Negative timing is valid E2 data and is recorded, never hidden.
  * bitgen stage stays fail-closed: a bit is only accepted when STA is all
    non-negative (setup/hold/period >= 0, TNS = 0), the four Gray-bus
    set_path_skew constraints are present with no negative slack, and no
    abnormal endpoints remain. No hardware download, ever.
"""
from pathlib import Path
import argparse, datetime, hashlib, json, os, re, subprocess, sys

if not __debug__:
    raise RuntimeError('Run DDR1333 native verification without Python -O.')

TD_CLI = Path('D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe')
TD_CLI_SHA256 = '2629e474df036a871807e564190febfbbd9780a09365f600c10463911c8c1223'
TOOL_ANCHORS = {
    'td': ('D:/anlogic/TD_Release_2026.2/bin/td.exe', 'fa2a5ac6e5342b2f801efa7a6aa345a5fd02d6f25ffa0d1e6380ff0ebd306a87'),
    'iptool': ('D:/anlogic/TD_Release_2026.2/bin/IpTool.exe', '5b0654aaa44ae9340eefcdc8cac54faed7490b0643f3fa53908c5706db175cec'),
    'arch_db': ('D:/anlogic/TD_Release_2026.2/arch/ph1_100p.db', '939ec2948f40546c9c545786af96ab4cb007a5ecf063f133da2b7835983ff77b'),
    'license': ('D:/anlogic/TD_Release_2026.2/license/Anlogic.lic', 'dc19fee62eff532d4c6a84c04ce34267b03190b753a3198a6788c3ec9e45c1a6'),
}
STAGES = {
    'build': {
        'script': 'build_rgb565.tcl',
        'script_sha256': '5aa25fd23b3d73d061b86cf82092f8c35e7bc9ba3b8d2b769243f071129288f9',
        'marker': 'RGB565_SYNTHESIS_RETURNED',
        'artifacts': ['camera_ddr_display_Runs/syn_1/camera_ddr_display_gate.db'],
    },
    'route': {
        'script': 'route_rgb565.tcl',
        'script_sha256': '019db289dec71867c51af16b334c1e0efb19a4b1d57a3e4e5870e8c672bb5489',
        'marker': 'RGB565_ROUTE_RETURNED_CHECK_REPORTS_NO_BIT',
        'artifacts': ['csi_checked_debug_pr.db', 'capture_timing.rpt', 'capture_skew.rpt',
                      'capture_ignored.rpt', 'capture_abnormal.rpt', 'capture.area'],
    },
    'bitgen': {
        'script': 'bitgen_rgb565.tcl',
        'script_sha256': 'fcce5e2088e523a2b9b5f91633b172c411058cc382af8a2393d05e7af4d64201',
        'marker': 'CAMERA_DDR_DISPLAY_CANDIDATE_GENERATED_NO_DOWNLOAD',
        'artifacts': ['camera_ddr_display.bit', 'camera_ddr_display_inst.bid', 'candidate_timing.rpt',
                      'candidate_skew.rpt', 'candidate_abnormal.rpt', 'candidate_ignored.rpt'],
    },
}
BITGEN_BODY = ('bitgen_rgb332_body.tcl', '7999f5f75136f5c1aa893ad64737f3b861f666b26a3608a76cea07a94af21b31')
STA_PATTERNS = [r'SWNS: ([-+0-9.]+)ns, STNS: ([-+0-9.]+)ns',
                r'HWNS: ([-+0-9.]+)ns, HTNS: ([-+0-9.]+)ns',
                r'Period Check WNS: ([-+0-9.]+)ns']


def sha256_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_record(path):
    if not path.is_file() or not path.stat().st_size:
        return None
    return {'bytes': path.stat().st_size, 'sha256': sha256_file(path)}


def extract_sta(text):
    checks = [re.search(pattern, text) for pattern in STA_PATTERNS]
    if not all(checks):
        return None
    setup, hold, period = checks
    return {'setup_ns': float(setup[1]), 'setup_tns_ns': float(setup[2]),
            'hold_ns': float(hold[1]), 'hold_tns_ns': float(hold[2]),
            'period_ns': float(period[1])}


def sta_extras(text):
    endpoints = [int(x) for x in re.findall(r'(\d+) Viol Endpoints', text)]
    groups = re.findall(r'(?m)^Path Group\s*:\s*(.+)$', text)
    m = re.search(r'(\w+):\s+([0-9.]+)\s+\d+\s+ddr_user\b', text)
    clock = None
    if m:
        clock = {'clk_id': m.group(1), 'summary_freq_mhz': float(m.group(2))}
        row = re.search(r'(?m)^\s*' + re.escape(m.group(1)) +
                        r'\s+\S+\s+\S+\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s+([-0-9.]+)\s', text)
        if row:
            clock.update(rise_ns=float(row[1]), fall_ns=float(row[2]),
                         c_period_ns=float(row[3]), c_freq_mhz=float(row[4]))
    return {'endpoint_groups_raw_count': len(endpoints),
            'violating_endpoints_sum': sum(endpoints),
            'path_groups_detected': len(groups), 'ddr_user_clock': clock}


p = argparse.ArgumentParser()
p.add_argument('project', type=Path)
p.add_argument('stage', choices=sorted(STAGES))
p.add_argument('--timeout', type=int, default=1800)
a = p.parse_args()
assert 1 <= a.timeout <= 7200

assert TD_CLI.is_file(), 'TD 6.2.3 CLI missing: ' + str(TD_CLI)
cli_sha = sha256_file(TD_CLI)
assert cli_sha == TD_CLI_SHA256, 'TD CLI SHA mismatch: ' + cli_sha
anchors = {}
for key, (path, expected) in TOOL_ANCHORS.items():
    f = Path(path)
    record = file_record(f)
    record = record or {'bytes': None, 'sha256': None}
    record.update(path=path, present=f.is_file(), expected_sha256=expected,
                  sha_match=(f.is_file() and record['sha256'] == expected))
    anchors[key] = record

root = a.project.resolve()
assert root.parent == Path('D:/TD/work/csi2/prj').resolve(), 'Project outside the frozen candidate tree'
assert root.name.startswith('camera_rgb565_'), 'Unexpected project name: ' + root.name
manifest = json.loads((root / 'input_manifest.json').read_bytes())
for rel, digest in manifest.items():
    f = (root / rel).resolve()
    assert f.is_relative_to(root) and sha256_file(f) == digest, 'Manifest mismatch: ' + rel
assert not (root / 'timing_overlay.json').exists(), \
    'Implementation-reserve overlay is out of scope for T01.tool-E2 (nominal only)'

stage = STAGES[a.stage]
record_path = root / ('native_' + a.stage + '.json')
log_path = root / ('native_' + a.stage + '.txt')
assert not record_path.exists() and not log_path.exists(), \
    'Do not overwrite an execution; preserve failures.'
script_path = root / stage['script']
assert script_path.is_file(), 'Frozen stage script missing: ' + stage['script']
script_sha = sha256_file(script_path)
assert script_sha == stage['script_sha256'], 'Frozen script SHA mismatch: ' + stage['script']
if a.stage == 'bitgen':
    body_path = root / BITGEN_BODY[0]
    assert body_path.is_file() and sha256_file(body_path) == BITGEN_BODY[1], 'Frozen bitgen body mismatch'

command = [str(TD_CLI).replace('\\', '/'), './' + stage['script']]
result = {
    'schema': 1, 'kind': 'ddr1333_native_stage', 'stage': a.stage, 'argv': sys.argv[1:],
    'command': command, 'cwd': str(root), 'script': stage['script'], 'script_sha256': script_sha,
    'runner_sha256': sha256_file(Path(__file__)), 'interpreter': sys.version.split()[0],
    'input_manifest_sha256': sha256_file(root / 'input_manifest.json'), 'input_manifest_items': len(manifest),
    'td_cli': {'path': str(TD_CLI).replace('\\', '/'), 'sha256': cli_sha}, 'tool_anchors': anchors,
    'timeout_seconds': a.timeout, 'started_at': datetime.datetime.now().astimezone().isoformat(),
    'hardware_download': False,
}
print('[ddr1333-runner] stage=%s project=%s timeout=%ss' % (a.stage, root.name, a.timeout), flush=True)

timed_out = False
exit_code = None
timeout_kill = None
with log_path.open('wb') as stream:
    creationflags = getattr(subprocess, 'CREATE_NEW_PROCESS_GROUP', 0)
    proc = subprocess.Popen(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                            creationflags=creationflags)
    try:
        exit_code = proc.wait(timeout=a.timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        kill = subprocess.run(['taskkill', '/F', '/T', '/PID', str(proc.pid)],
                              capture_output=True, timeout=120)
        try:
            proc.wait(timeout=60)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=60)
        timeout_kill = {'returncode': kill.returncode,
                        'stdout': kill.stdout.decode(errors='replace').strip(),
                        'stderr': kill.stderr.decode(errors='replace').strip()}
        result['error'] = 'timeout after %ss; process tree taskkill issued' % a.timeout
output = log_path.read_text(errors='replace')
result.update(exit_code=exit_code, timed_out=timed_out, timeout_kill=timeout_kill,
              expected_marker=stage['marker'], marker_present=stage['marker'] in output)
result['artifacts'] = {}
result['artifact_bytes'] = {}
for rel in stage['artifacts']:
    rec = file_record(root / rel)
    result['artifacts'][rel] = rec['sha256'] if rec else None
    result['artifact_bytes'][rel] = rec['bytes'] if rec else None
if a.stage != 'build' and (root / 'csi_checked_debug_pr.db').is_file():
    result['selected_db_sha256'] = sha256_file(root / 'csi_checked_debug_pr.db')
if a.stage == 'build' and (root / 'camera_ddr_display_Runs/syn_1/run.log').is_file():
    result['synthesis_worker_log'] = file_record(root / 'camera_ddr_display_Runs/syn_1/run.log')

execution_ok = (exit_code == 0 and result['marker_present']
                and all(result['artifacts'].values()))
result['execution_ok'] = execution_ok
result['acceptance_basis'] = ('execution_ok (exit0 + marker + non-empty artifacts); '
                              'timing is recorded separately, never hidden')

report = {'route': root / 'capture_timing.rpt', 'bitgen': root / 'candidate_timing.rpt'}.get(a.stage)
if report is not None:
    if not report.is_file():
        report = None
result['timing_records'] = None
if report is not None:
    text = report.read_text(errors='replace')
    sta = extract_sta(text)
    result['sta_summary_present'] = sta is not None
    result['sta'] = sta
    if sta is not None:
        result['sta'] = dict(sta, report=str(report), report_sha256=sha256_file(report), **sta_extras(text))
        result['constraint_timing_pass'] = (min(sta['setup_ns'], sta['hold_ns'], sta['period_ns']) >= 0
                                            and sta['setup_tns_ns'] == 0 and sta['hold_tns_ns'] == 0)
        result['timing_signoff'] = None
        result['timing_records'] = ('endpoint-group review + check_timing_margin.py --min-setup-ns 0.3 '
                                    'gate are recorded in docs/evidence/ddr1333 evidence JSON, not self-certified here')
    else:
        result['constraint_timing_pass'] = None
        result['timing_signoff'] = None
if a.stage == 'bitgen' and execution_ok:
    ok = bool(result.get('constraint_timing_pass'))
    skew_path = root / 'candidate_skew.rpt'
    abnormal_path = root / 'candidate_abnormal.rpt'
    if skew_path.is_file() and abnormal_path.is_file():
        skew = skew_path.read_text(errors='replace')
        abnormal = abnormal_path.read_text(errors='replace')
        slacks = [float(x) for x in re.findall(r'(?m)^Slack +: ([-+0-9.]+)ns', skew)]
        prechecks = {
            'skew_constraints': len(re.findall(r'(?m)^[0-9]+,  set_path_skew', skew)),
            'skew_paths': len(slacks), 'skew_min_ns': min(slacks) if slacks else None,
            'abnormal_endpoints': len(re.findall(r'End Point:', abnormal)),
            'skew_report_sha256': sha256_file(skew_path), 'abnormal_report_sha256': sha256_file(abnormal_path),
        }
        ok = ok and prechecks['skew_constraints'] == 4 and prechecks['skew_paths'] >= 8 \
            and prechecks['skew_min_ns'] is not None and prechecks['skew_min_ns'] >= 0 \
            and prechecks['abnormal_endpoints'] == 0
        result['bitgen_prechecks'] = prechecks
    else:
        result['bitgen_prechecks'] = {'error': 'skew/abnormal report missing'}
        ok = False
    result['acceptance_basis'] = ('execution_ok + fail-closed timing/skew/abnormal prechecks '
                                  '(mirrors bitgen_rgb332_body.tcl)')
    execution_ok = ok
result['execution_ok'] = execution_ok
result['accepted'] = execution_ok
result.update(ended_at=datetime.datetime.now().astimezone().isoformat(),
              log_bytes=log_path.stat().st_size, log_sha256=sha256_file(log_path))
record_path.write_bytes((json.dumps(result, indent=2) + '\n').encode())
print(json.dumps(result, indent=2))
print(output[-2200:])
sys.exit(0 if result['accepted'] else 1)
