"""TD CLI end-to-end command verification harness (T01.tool-B, run 20261016_185639).

Real-execution harness for the TD CLI control commands on a fresh ASCII scratch
project under D:/TD/work/csi2/_validation/td_cli_<YYYYMMDD_HHMMSS>/:

  init     - create the scratch root (mkdir exist_ok=False), copy byte-verified
             copies of tools/td/verify_cli.tcl (unmodified baseline) and
             tools/td/verify_cli_e2e.tcl (stage-1 script), write micro RTL/ADC/SDC
             assets and the auxiliary stage scripts, record all SHAs.
  stage    - execute one script through D:/downlaod/bin/td_commands_prompt.exe with
             full recording: exact argv, cwd, pid, start/end, timeout, exit_code,
             timed_out (real process-tree kill), raw stdout/stderr files + SHA,
             marker search in raw bytes, required-line checks, artifact globs with
             bytes+SHA256, new td_*.log files in cwd, script SHA re-verification.
  collect  - merge experiment.json + all stage records into one evidence JSON
             (schema 1). Does not invent verdicts: each stage carries the raw
             collector rule result (exit==0 AND marker AND non-empty artifacts).

The collector rule is intentionally strict so that script-load failures that still
exit 0 are judged fail (documented TD CLI quirk, negative-control verified).

No hardware download, no change to D:/downlaod, frozen projects, or existing
_validation directories. Single-purpose experiment artifact (non-production).
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import subprocess
import sys

if not __debug__:
    raise RuntimeError('Run without Python -O.')

TD_EXE = Path('D:/downlaod/bin/td_commands_prompt.exe')
PH1_DB = Path('D:/downlaod/arch/ph1_100p.db')
REPO_TD = Path(__file__).resolve().parent
BASELINE_TCL = REPO_TD / 'verify_cli.tcl'
E2E_TCL = REPO_TD / 'verify_cli_e2e.tcl'
COLLECTOR_RULE = (
    'stage passes iff exit_code==0 AND expected marker present (when defined) AND '
    'every declared artifact glob has >=1 non-empty match AND every required line '
    'present; exit code alone is never sufficient'
)

ASSETS = {
    'td_cli_e2e_counter.v': """\
// TD CLI end-to-end scratch design (non-production): free-running counter.
// Used only to verify TD CLI control commands on a minimal ASCII project.
module td_cli_e2e_counter (
    input  wire       sys_clk50m,
    output wire [3:0] o_led
);
    reg [24:0] counter = 25'd0;
    always @(posedge sys_clk50m) begin
        counter <= counter + 25'd1;
    end
    assign o_led = counter[24:21];
endmodule
""",
    'td_cli_e2e_counter.adc': """\
# TD CLI end-to-end scratch pin constraints (non-production; pin usage copied
# from the project's verified board.adc: clock H4, LED bank pins).
set_pin_assignment { sys_clk50m } { LOCATION = H4;  IOSTANDARD = SSTL135; PULLTYPE = PULLUP; }
set_pin_assignment { o_led[0]   } { LOCATION = E21; IOSTANDARD = LVCMOS33; }
set_pin_assignment { o_led[1]   } { LOCATION = D21; IOSTANDARD = LVCMOS33; }
set_pin_assignment { o_led[2]   } { LOCATION = E22; IOSTANDARD = LVCMOS33; }
set_pin_assignment { o_led[3]   } { LOCATION = D22; IOSTANDARD = LVCMOS33; }
""",
    'td_cli_e2e_counter.sdc': """\
# TD CLI end-to-end scratch timing constraints (non-production).
create_clock -name {sys_clk50m} -period 20.000 -waveform {0.000 10.000} [get_ports {sys_clk50m}]
""",
    's2_route.tcl': """\
# TD CLI end-to-end scratch verification, stage 2: physical route via manager.
# create_run (physical, linked to syn_e2e_1) -> launch_runs -step route -> wait_run.
# No hardware download.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./td_cli_e2e_counter.al
    create_run -constrset constraint_1 -syn_run syn_e2e_1 phy_e2e_1
    puts "TD_CLI_E2E_PHY_RUN_CREATED phy_e2e_1"
    launch_runs -step route phy_e2e_1
    puts "TD_CLI_E2E_ROUTE_LAUNCH_RETURNED phy_e2e_1"
    wait_run phy_e2e_1 -quiet
    close_project
    puts "TD_CLI_E2E_ROUTE_RETURNED"
} msg]} {
    puts stderr "TD_CLI_E2E_ROUTE_ERROR: $msg"
    exit 1
}
exit 0
""",
    's2n_native_route.tcl': """\
# TD CLI end-to-end scratch verification, native route fallback.
# WORKAROUND (documented native path), NOT a fix for any manager defect: resume
# from the exported synthesis gate DB when launch_runs -step route cannot create
# the physical run. Mirrors tools/td/route_csi_checked.tcl conventions.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./td_cli_e2e_counter.al
    load_run_param -run phy_e2e_1
    import_db ./td_cli_e2e_counter_Runs/syn_e2e_1/td_cli_e2e_counter_gate.db
    commit_param -step place
    if {[catch {insert_debugger} dmsg]} {
        puts "TD_CLI_E2E_ROUTE_NATIVE_INSERT_DEBUGGER_SKIPPED: $dmsg"
    } else {
        puts "TD_CLI_E2E_ROUTE_NATIVE_INSERT_DEBUGGER_OK"
    }
    place
    commit_param -step route
    route
    update_timing -mode final
    report_timing_summary -file ./e2e_native_route_timing.rpt
    export_db ./e2e_native_route_pr.db
    close_project
    puts "TD_CLI_E2E_ROUTE_NATIVE_RETURNED"
} msg]} {
    puts stderr "TD_CLI_E2E_ROUTE_NATIVE_ERROR: $msg"
    exit 1
}
exit 0
""",
    's3_timing.tcl': """\
# TD CLI end-to-end scratch verification, stage 3: open_run + update_timing final
# + report_timing_summary with in-script parse of SWNS/HWNS/Period lines.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./td_cli_e2e_counter.al
    open_run phy_e2e_1
    update_timing -mode final
    report_timing_summary -file ./e2e_timing.rpt
    set fh [open ./e2e_timing.rpt r]
    set timing [read $fh]
    close $fh
    foreach {label pattern} {
        SWNS {SWNS: ([-+0-9.]+)ns, STNS: ([-+0-9.]+)ns}
        HWNS {HWNS: ([-+0-9.]+)ns, HTNS: ([-+0-9.]+)ns}
        PERIOD {Period Check WNS: ([-+0-9.]+)ns}
    } {
        if {![regexp $pattern $timing unused value]} {
            error "Missing $label line in e2e_timing.rpt"
        }
        puts "TD_CLI_E2E_TIMING_${label} $value"
    }
    close_project
    puts "TD_CLI_E2E_TIMING_RETURNED"
} msg]} {
    puts stderr "TD_CLI_E2E_TIMING_ERROR: $msg"
    exit 1
}
exit 0
""",
    's4_bitgen.tcl': """\
# TD CLI end-to-end scratch verification, stage 4: bitgen from routed design.
# Re-verifies final setup timing before generating; no hardware download.
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./td_cli_e2e_counter.al
    open_run phy_e2e_1
    update_timing -mode final
    report_timing_summary -file ./e2e_bitgen_timing.rpt
    set fh [open ./e2e_bitgen_timing.rpt r]
    set timing [read $fh]
    close $fh
    if {![regexp {SWNS: ([-+0-9.]+)ns} $timing unused sw]} {
        error "Missing setup timing status in e2e_bitgen_timing.rpt"
    }
    if {$sw < 0} {
        error "STA rejects bit generation: SWNS=$sw"
    }
    if {[catch {save_best_bits} bmsg]} {
        puts "TD_CLI_E2E_SAVE_BEST_BITS_SKIPPED: $bmsg"
    } else {
        puts "TD_CLI_E2E_SAVE_BEST_BITS_OK"
    }
    bitgen -bit ./td_cli_e2e_counter.bit
    set fh [open ./td_cli_e2e_counter.bit r]
    fconfigure $fh -translation binary
    set bits [read $fh]
    close $fh
    if {[string length $bits] <= 0} {
        error "Generated bit file is empty"
    }
    puts "TD_CLI_E2E_BIT_BYTES [string length $bits]"
    close_project
    puts "TD_CLI_E2E_BITGEN_NO_DOWNLOAD"
} msg]} {
    puts stderr "TD_CLI_E2E_BITGEN_ERROR: $msg"
    exit 1
}
exit 0
""",
    'neg1_open_missing.tcl': """\
# Negative control: opening a nonexistent project must make the collector judge
# this stage fail, regardless of TD's exit code (documented as insufficient).
open_project ./definitely_missing_td_cli_e2e_project.al
puts "TD_CLI_E2E_NEG1_UNEXPECTED_MARKER"
exit 0
""",
    'neg2_undefined_command.tcl': """\
# Negative control: a script that cannot evaluate must be judged fail by the
# collector; records TD's actual exit code for a load/eval failure.
td_cli_e2e_undefined_command_for_load_failure
puts "TD_CLI_E2E_NEG2_UNEXPECTED_MARKER"
exit 0
""",
    'q1_forward_slash.tcl': """\
# Quirk check q1: './x.tcl' (forward slash) script invocation works.
puts "TD_CLI_E2E_Q1_FORWARD_SLASH_OK"
exit 0
""",
    'q2_backslash.tcl': """\
# Quirk check q2: '.\\x.tcl' (backslash) invocation is documented to fail.
puts "TD_CLI_E2E_Q2_BACKSLASH_MARKER"
exit 0
""",
    'q5_stdin.txt': """\
set e2e_x 41
if {$e2e_x == 41} { puts "TD_CLI_E2E_STDIN_OK" }
exit 0
""",
    'q7_open_relative.tcl': """\
# Quirk check q7: relative './td_cli_e2e_counter.al' resolves against cwd.
if {[catch {open_project ./td_cli_e2e_counter.al} msg]} {
    puts stderr "TD_CLI_E2E_Q7_OPEN_FAILED: $msg"
    exit 1
}
puts "TD_CLI_E2E_Q7_OPEN_OK"
close_project
exit 0
""",
}

COMMAND_MAP = {
    'import_device': ['s1_syn', 's2_route', 's3_timing', 's4_bitgen'],
    'create_project': ['s1_syn'],
    'add_files': ['s1_syn'],
    'top_module': ['s1_syn'],
    'create_run': ['s1_syn', 's2_route'],
    'open_project': ['s2_route', 's3_timing', 's4_bitgen', 'q7a_open_cwd_ok'],
    'launch_runs': ['s1_syn', 's2_route'],
    'wait_run': ['s1_syn', 's2_route'],
    'reset_runs': ['s1_syn'],
    'open_run': ['s3_timing', 's4_bitgen'],
    'update_timing': ['s3_timing', 's4_bitgen'],
    'report_timing_summary': ['s3_timing', 's4_bitgen'],
    'save_best_bits': ['s4_bitgen'],
    'bitgen': ['s4_bitgen'],
    'close_project': ['s1_syn', 's2_route', 's3_timing', 's4_bitgen', 'q7a_open_cwd_ok'],
}


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def iso_now():
    return datetime.datetime.now().astimezone().isoformat()


def json_bytes(obj):
    return (json.dumps(obj, indent=2, ensure_ascii=False) + '\n').encode('utf-8')


def file_record(path, rel_to=None):
    path = Path(path)
    rec = {'bytes': path.stat().st_size, 'sha256': sha256_file(path)}
    rec['path'] = str(path.relative_to(rel_to)).replace('\\', '/') if rel_to else str(path)
    return rec


def decode_tail(blob, limit=1500):
    for enc in ('utf-8', 'gbk'):
        try:
            text = blob.decode(enc)
            return text[-limit:]
        except UnicodeDecodeError:
            continue
    return blob[-limit:].decode('latin-1')


def cmd_init(args):
    base = Path(args.scratch_base)
    tag = args.tag or datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    root = (base / ('td_cli_' + tag)).resolve()
    root.mkdir(parents=True, exist_ok=False)
    (root / 'stages').mkdir()
    (root / 'wrongcwd').mkdir()

    assert BASELINE_TCL.is_file() and E2E_TCL.is_file(), 'repo source scripts missing'
    src_base = BASELINE_TCL.read_bytes()
    src_e2e = E2E_TCL.read_bytes()
    (root / 's0_verify_cli.tcl').write_bytes(src_base)
    (root / 'verify_cli_e2e.tcl').write_bytes(src_e2e)
    assert (root / 's0_verify_cli.tcl').read_bytes() == src_base, 'baseline copy mismatch'
    assert (root / 'verify_cli_e2e.tcl').read_bytes() == src_e2e, 'e2e copy mismatch'

    for rel, text in ASSETS.items():
        (root / rel).write_bytes(text.encode('ascii'))

    files = {}
    for p in sorted(root.rglob('*')):
        if p.is_file():
            files[p.relative_to(root).as_posix()] = file_record(p)
    experiment = {
        'schema': 1,
        'kind': 'td_cli_e2e_experiment',
        'created_at': iso_now(),
        'root': str(root),
        'tool': {
            'td_cli': str(TD_EXE),
            'td_cli_sha256': sha256_file(TD_EXE),
            'ph1_100p_db': str(PH1_DB),
            'ph1_100p_db_sha256': sha256_file(PH1_DB),
        },
        'repo_sources': {
            'verify_cli.tcl': {**file_record(BASELINE_TCL), 'path': str(BASELINE_TCL)},
            'verify_cli_e2e.tcl': {**file_record(E2E_TCL), 'path': str(E2E_TCL)},
            'verify_cli_e2e.py': {**file_record(Path(__file__)), 'path': str(Path(__file__).resolve())},
        },
        'copies_byte_identical': {
            's0_verify_cli.tcl': (root / 's0_verify_cli.tcl').read_bytes() == src_base,
            'verify_cli_e2e.tcl': (root / 'verify_cli_e2e.tcl').read_bytes() == src_e2e,
        },
        'files': files,
        'collector_rule': COLLECTOR_RULE,
        'no_hardware_download': True,
    }
    (root / 'experiment.json').write_bytes(json_bytes(experiment))
    print(json.dumps({'root': str(root), 'files': len(files),
                      'td_cli_sha256': experiment['tool']['td_cli_sha256']}, indent=2))


def cmd_stage(args):
    root = Path(args.root).resolve()
    experiment = json.loads((root / 'experiment.json').read_bytes())
    script_rel = None
    script_sha = None
    if args.script:
        script_rel = args.script.lstrip('./').replace('\\', '/')
        sp = root / script_rel
        assert sp.is_file(), f'missing script: {script_rel}'
        script_sha = sha256_file(sp)
        assert script_sha == experiment['files'][script_rel]['sha256'], \
            f'script changed after init: {script_rel}'
    cwd = root if not args.cwd else (root / args.cwd).resolve()
    assert cwd.is_dir(), f'missing cwd: {cwd}'

    argv = [str(TD_EXE)]
    if args.script_arg is not None:
        argv.append(args.script_arg)
    elif script_rel is not None:
        argv.append('./' + script_rel)

    stdin_blob = None
    if args.stdin_file:
        stdin_blob = (root / args.stdin_file).read_bytes()

    logs_dir = root / 'logs'
    logs_dir.mkdir(exist_ok=True)
    out_p = logs_dir / (args.name + '.stdout.txt')
    err_p = logs_dir / (args.name + '.stderr.txt')
    assert not out_p.exists() and not err_p.exists(), 'stage artifacts already exist; do not overwrite'

    td_before = {p.name for p in root.glob('td_*.log*')} | {p.name for p in cwd.glob('td_*.log*')}
    started = iso_now()
    proc = None
    timed_out = False
    with out_p.open('wb') as so, err_p.open('wb') as se:
        proc = subprocess.Popen(argv, cwd=str(cwd), stdout=so, stderr=se,
                                stdin=subprocess.PIPE if stdin_blob is not None else None)
        if stdin_blob is not None:
            proc.stdin.write(stdin_blob)
            proc.stdin.close()
        try:
            exit_code = proc.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(['taskkill', '/F', '/T', '/PID', str(proc.pid)],
                           capture_output=True)
            try:
                exit_code = proc.wait(timeout=120)
            except subprocess.TimeoutExpired:
                proc.kill()
                exit_code = proc.wait()
    ended = iso_now()

    blob = out_p.read_bytes() + err_p.read_bytes()
    marker_present = (args.marker.encode() in blob) if args.marker else None
    require_results = {pat: (pat.encode() in blob) for pat in args.require}

    artifacts = []
    pattern_ok = {}
    for pattern in args.artifact:
        matches = [p for p in sorted(root.glob(pattern)) if p.is_file()]
        pattern_ok[pattern] = bool(matches) and all(m.stat().st_size > 0 for m in matches)
        for m in matches:
            artifacts.append({'pattern': pattern, **file_record(m, rel_to=root),
                              'nonempty': m.stat().st_size > 0})

    td_after = {p.name for p in root.glob('td_*.log*')} | {p.name for p in cwd.glob('td_*.log*')}
    new_td_logs = []
    for name in sorted(td_after - td_before):
        for d in (cwd, root):
            cand = d / name
            if cand.is_file():
                new_td_logs.append(file_record(cand, rel_to=root))
                break

    artifacts_complete = None
    if args.artifact:
        artifacts_complete = all(pattern_ok.values())
    collector_pass = (
        exit_code == 0
        and (marker_present is not False)
        and (artifacts_complete is not False)
        and all(require_results.values())
    )
    expectation_met = None if args.expect == 'any' else (collector_pass == (args.expect == 'pass'))

    record = {
        'schema': 1,
        'kind': 'td_cli_e2e_stage',
        'name': args.name,
        'note': args.note,
        'started_at': started,
        'ended_at': ended,
        'argv': argv,
        'cwd': str(cwd),
        'pid': proc.pid,
        'timeout_seconds': args.timeout,
        'timed_out': timed_out,
        'exit_code': exit_code,
        'stdout': file_record(out_p, rel_to=root),
        'stderr': file_record(err_p, rel_to=root),
        'combined_tail': decode_tail(blob),
        'marker': args.marker,
        'marker_present': marker_present,
        'require': require_results,
        'artifacts': artifacts,
        'artifact_patterns_ok': pattern_ok,
        'artifacts_complete': artifacts_complete,
        'collector_rule': COLLECTOR_RULE,
        'collector_pass': collector_pass,
        'expectation': args.expect,
        'expectation_met': expectation_met,
        'new_td_logs': new_td_logs,
        'script': None if script_rel is None else {'path': script_rel, 'sha256': script_sha},
        'script_arg_raw': args.script_arg,
        'stdin_file': args.stdin_file,
        'runner_sha256': sha256_file(Path(__file__)),
        'tool_exe_sha256': sha256_file(TD_EXE),
    }
    (root / 'stages' / (args.name + '.json')).write_bytes(json_bytes(record))

    summary = {k: record[k] for k in ('name', 'exit_code', 'timed_out', 'marker_present',
                                      'collector_pass', 'expectation', 'expectation_met')}
    summary['artifacts'] = [a['path'] for a in artifacts]
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print('--- combined tail ---')
    print(record['combined_tail'])
    if expectation_met is False:
        sys.exit(1)


def cmd_collect(args):
    root = Path(args.root).resolve()
    out = Path(args.out).resolve()
    assert not out.exists(), f'refusing to overwrite existing evidence file: {out}'
    experiment = json.loads((root / 'experiment.json').read_bytes())
    stages = []
    for p in sorted((root / 'stages').glob('*.json'), key=lambda q: json.loads(q.read_bytes())['started_at']):
        stages.append(json.loads(p.read_bytes()))
    frozen_check = {}
    for rel, rec in experiment['files'].items():
        p = root / rel
        frozen_check[rel] = p.is_file() and sha256_file(p) == rec['sha256']
    td_logs = [file_record(p, rel_to=root) for p in sorted(root.glob('td_*.log*'))]
    command_table = {}
    stage_by_name = {s['name']: s for s in stages}
    for cmd, names in COMMAND_MAP.items():
        rows = []
        for n in names:
            s = stage_by_name.get(n)
            if s is None:
                rows.append({'stage': n, 'present': False})
            else:
                rows.append({
                    'stage': n, 'present': True, 'exit_code': s['exit_code'],
                    'timed_out': s['timed_out'], 'marker_present': s['marker_present'],
                    'collector_pass': s['collector_pass'],
                    'artifacts': [{'path': a['path'], 'bytes': a['bytes'], 'sha256': a['sha256']}
                                  for a in s['artifacts']],
                })
        command_table[cmd] = rows
    evidence = {
        'schema': 1,
        'kind': 'td_cli_commands_evidence',
        'recorded_at': iso_now(),
        'scope': 'T01.tool-B TD CLI control-command end-to-end verification (scratch, non-production)',
        'status': 'collected',
        'experiment': experiment,
        'scripts_stable_after_runs': all(frozen_check.values()),
        'frozen_check': frozen_check,
        'stages': stages,
        'command_table': command_table,
        'td_log_inventory': td_logs,
        'limits': [
            'Scratch design is a micro counter; G2-lite for command proof only, not any production candidate.',
            'No hardware download / Flash. bitgen is the final step; download was not attempted.',
        ],
    }
    out.write_bytes(json_bytes(evidence))
    print(json.dumps({'evidence': str(out), 'stages': len(stages),
                      'scripts_stable_after_runs': evidence['scripts_stable_after_runs'],
                      'stage_verdicts': {s['name']: s['collector_pass'] for s in stages}}, indent=2))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest='command', required=True)

    p = sub.add_parser('init')
    p.add_argument('--scratch-base', default='D:/TD/work/csi2/_validation')
    p.add_argument('--tag', default=None)
    p.set_defaults(func=cmd_init)

    p = sub.add_parser('stage')
    p.add_argument('--root', required=True)
    p.add_argument('--name', required=True)
    p.add_argument('--script', default=None, help='relative script name, invoked as ./<name>')
    p.add_argument('--script-arg', default=None, help='raw script argument override (quirk tests)')
    p.add_argument('--stdin-file', default=None, help='relative file piped to stdin (no argv script)')
    p.add_argument('--cwd', default=None, help='cwd relative to root (default: root)')
    p.add_argument('--timeout', type=int, default=120)
    p.add_argument('--marker', default=None)
    p.add_argument('--require', action='append', default=[])
    p.add_argument('--artifact', action='append', default=[])
    p.add_argument('--expect', choices=['pass', 'fail', 'any'], default='pass')
    p.add_argument('--note', default='')
    p.set_defaults(func=cmd_stage)

    p = sub.add_parser('collect')
    p.add_argument('--root', required=True)
    p.add_argument('--out', required=True)
    p.set_defaults(func=cmd_collect)

    args = ap.parse_args()
    args.func(args)


if __name__ == '__main__':
    main()
