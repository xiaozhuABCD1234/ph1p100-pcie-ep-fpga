"""Prepare an isolated DDR1333 IP regeneration trial; never launch or delete files."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re

BASE = Path('D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820')
DEPOT = Path('D:/downlaod/ip/depot/MIS_DDRF6F1D0P0_1.2')
GOLDEN = Path('D:/TD/work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/golden_adc/ap115v2_ddr3_x32.adc')

# Actual state of the IpTool headless generation entry, as established by the
# controlled experiments recorded in docs/evidence/ddr1333_iptool_cli_20261016.json
# (20 controlled attempts, 2026-10-16). Override with --entry-status when a
# later experiment changes the state. Never infer this from binary strings.
ENTRY_STATUS = (
    'not demonstrated as of 2026-10-16: across 20 controlled attempts, no headless IpTool run '
    'produced a complete IP. With a tool-era consistent instance (and the external golden-ADC path '
    'mapped to a local file) the automatic copy flow DOES load the instance values (log: set REF_CLK '
    '50.00 / DDR_SPEED 1600.00 after the 100/800 defaults) but generation still fails deterministically '
    'with "#IP Generate Failed!" (~2.5 s, 8 scaffolding files, byte-identical tool logs). Hand-edited '
    'instances break the copy-value load path (falls back to component defaults). The 6.2.2 Tcl side has '
    'no create_ip/generate_target family and no usable set-params-and-generate entry (set_ip_property/'
    'xmlipgen/create_syn_ip minimal calls failed or were unverifiable). See '
    'docs/evidence/ddr1333_iptool_cli_20261016.json.'
)
ENTRY_STATUS_SOURCE = 'docs/evidence/ddr1333_iptool_cli_20261016.json'


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def pins(p):
    result = {}
    for line in p.read_text().splitlines():
        if line.lstrip().startswith('#'):
            continue
        m = re.search(r'set_ippin_assignment\s+\{([^}]+)\}\s+\{[^}]*LOCATION\s*=\s*(\w+)', line)
        if m:
            name = m[1].strip()
            if re.fullmatch(r'ddr_(?:ck_[pn]|[rc]as_n|we_n|cs_n|cke|odt|reset_n)\[0\]', name):
                name = name[:-3]
            assert name not in result, name
            result[name] = m[2]
    return result


def prepare(manual_gui=False, comp_name='ddrmc_1333', use_value='copy', extra_flags=(),
            user_mode='file', gen_mode='file', entry_status=ENTRY_STATUS):
    if user_mode not in ('file', 'directory') or gen_mode not in ('file', 'directory'):
        raise SystemExit('user/gen mode must be file or directory')
    if use_value not in ('copy', 'default'):
        raise SystemExit('use_value must be copy or default')
    manifest = json.loads((BASE/'input_manifest.json').read_bytes())
    assert sha(BASE/'input_manifest.json') == '8f8e4efe9b9320cbc595f94e337395744dbd957630576123576ee2c357f9a1c8'
    for rel, digest in manifest.items():
        path = (BASE/rel).resolve()
        assert path.is_relative_to(BASE.resolve()) and sha(path) == digest, rel
    ip = BASE/'vendor/ip/ddrmc_x32'
    actual, golden = pins(ip/'src/adc/ddrmc_x32.adc'), pins(GOLDEN)
    assert len(actual) == 70 and all(golden.get(k) == v for k, v in actual.items())
    out = Path('D:/TD/work/csi2/_validation')/('ddr1333_ip_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
    out.mkdir(exist_ok=False)
    changes = []
    for source, dest in ((ip, out/'source/ddrmc_x32'), (DEPOT, out/'depot')):
        for p in sorted(source.rglob('*')):
            assert not (getattr(p.lstat(), 'st_file_attributes', 0) & 0x400), p
            if p.is_file():
                q = dest/p.relative_to(source)
                q.parent.mkdir(parents=True, exist_ok=True)
                q.write_bytes(p.read_bytes())
                assert sha(q) == sha(p)
    export = out/'output'
    retained = out/'_retained'
    export.mkdir()
    retained.mkdir()
    helper = out/'retain_ip_path.tcl'
    # Keep obsolete generator files outside the active IP fileset. No deletion.
    # Both roots are literal private paths, not caller-controlled Tcl variables.
    helper.write_text('''if {[llength [info commands retain_ip_path]] == 0} {
proc retain_ip_path {path} {
    set root [file normalize {@EXPORT@}]
    set keep [file normalize {@KEEP@}]
    set src [file normalize $path]
    set prefix "[string tolower $root]/"
    if {![string equal -length [string length $prefix] $prefix "[string tolower $src]/"] || [string equal -nocase $src $root]} {
        error "Retention source outside private export: $src"
    }
    if {![file exists $src]} {return}
    # Reject links/junctions along the path before moving any directory.
    set check $src
    foreach boundary [list $root $keep] {
        if {[file type $boundary] eq "link"} {error "Retention boundary link forbidden: $boundary"}
    }
    while {![string equal -nocase $check $root]} {
        if {[file type $check] eq "link"} {error "Retention link forbidden: $check"}
        set parent [file dirname $check]
        if {$parent eq $check} {error "Retention ancestor escaped private export"}
        set check $parent
    }
    set target [file join $keep [string range $src [expr {[string length $root]+1}] end]]
    set index 0
    set dest $target
    while {[file exists $dest]} {incr index;set dest "$target.$index"}
    set dest [file normalize $dest]
    set kp "[string tolower $keep]/"
    if {![string equal -length [string length $kp] $kp "[string tolower $dest]/"]} {
        error "Retention destination outside private scratch: $dest"
    }
    set check [file dirname $dest]
    while {![string equal -nocase $check $keep]} {
        if {[file exists $check] && [file type $check] eq "link"} {error "Retention destination link forbidden: $check"}
        set parent [file dirname $check]
        if {$parent eq $check} {error "Retention destination ancestor escaped private scratch"}
        set check $parent
    }
    file mkdir [file dirname $dest]
    file rename $src $dest
    set f [open [file join $keep retention.log] a]
    puts $f [list $src $dest]
    close $f
}
}
'''.replace('@EXPORT@', export.as_posix()).replace('@KEEP@', retained.as_posix()), encoding='utf-8')
    for p in sorted((out/'depot').rglob('*.tcl')):
        raw = p.read_bytes()
        # Exact known vendor cleanup spelling; reject any remaining active delete.
        modified = raw.replace(b'file delete -force ', b'retain_ip_path ')
        assert not re.search(rb'(?m)^\s*file\s+delete\b', modified), p
        if modified != raw or p.name == 'Dependency.tcl':
            modified = ('source {'+helper.as_posix()+'}\n').encode()+modified
            p.write_bytes(modified)
            changes.append({'path': p.relative_to(out).as_posix(), 'before': hashlib.sha256(raw).hexdigest(), 'after': sha(p), 'cleanup_replacements': raw.count(b'file delete -force ')})
    pinfile = out/'input_pins.adc'
    pinfile.write_bytes(GOLDEN.read_bytes())
    user_values = {'PH1P_DDR_SPEED': '1333.00', 'PH1P_SPEED_BIN': 'DDR3-1333J', 'CWL': '7', 'PH1P_IO_ASSIGN': pinfile.as_posix()}
    design = out/'source/ddrmc_x32/Design.xml'
    raw = design.read_text(encoding='utf-8')
    for key, value in user_values.items():
        val = '&quot;'+value+'&quot;' if key in ('PH1P_SPEED_BIN', 'PH1P_IO_ASSIGN') else value
        raw, n = re.subn(r'(referenceId="'+key+r'">)[^<]+(</ipxact:configurableElementValue>)', lambda m: m[1]+val+m[2], raw)
        assert n == 1, key
    design.write_text(raw, encoding='utf-8')
    params = out/'source/ddrmc_x32/.params_ddrmc_x32.txt'
    raw = params.read_text()
    for key, value in user_values.items():
        # Non-greedy match tolerates the drive colon in a path value.
        raw, n = re.subn(r'(?m)^('+key+r' : ).*?( : [UG] : )', lambda m: m[1]+value+m[2], raw)
        assert n == 1, key
    params.write_text(raw, encoding='utf-8')
    user_opt = (out/'source/ddrmc_x32').as_posix() if user_mode == 'directory' else (out/'source/ddrmc_x32/ddrmc_x32.xml').as_posix()
    gen_opt = (out/'depot').as_posix() if gen_mode == 'directory' else (out/'depot/Component.xml').as_posix()
    argv = ['D:/downlaod/bin/IpTool.exe', 'D:/downlaod'] + list(extra_flags) + ['-user', user_opt, '-gen', gen_opt, '-device', 'PH1P100SBG484', '-export_to', export.as_posix(), '-comp', comp_name, '-use_value', use_value]
    record = {'baseline': BASE.as_posix(), 'baseline_manifest_sha256': sha(BASE/'input_manifest.json'), 'user_values': user_values, 'expected_derived': {'CL':10, 'CWL':7, 'tCK_min_ns':1.5, 'physical_clock_max_mhz':'2000/3'}, 'pin_comparison': {'matched':70, 'unused_extra':{'ddr_addr[14]':'J5'}}, 'generator_cleanup_preserved': changes, 'argv': argv, 'argv_form': {'comp_name': comp_name, 'use_value': use_value, 'extra_flags': list(extra_flags), 'user_mode': user_mode, 'gen_mode': gen_mode}, 'argv_notes': ('Historical form uses file paths for -user/-gen. The 2026-10-16 controlled experiments '
                    '(docs/evidence/ddr1333_iptool_cli_20261016.json) showed IpTool appends /Design.xml and /Component.xml to these options, i.e. it validates them as directories; '
                    'use --user-mode directory --gen-mode directory for that corrected form. Moreover, the hand-edited instance produced by this script (Design.xml/.params edited while '
                    '.m_params stays at the baseline) makes the automatic copy flow fall back to component defaults; a tool-era unedited instance loads values correctly. '
                    'Keep that in mind when reusing this package for generation tests.'),
                'cli_entry_status': entry_status, 'cli_entry_status_source': ENTRY_STATUS_SOURCE,
                'generated': False, 'hardware_download': False}
    if manual_gui:
        guard = out/'manual_binding_guard.tcl'
        guard.write_text('''# This marker is emitted only when the private generator is loaded.
foreach required_var {IP_INSTALL_PATH IP_EXPORT_PATH IP_COMPONENT_NAME} {
    if {![info exists $required_var]} {error "Missing IPTool context: $required_var"}
}
set expected_depot [file normalize {@DEPOT@}]
if {![string equal -nocase [file normalize $IP_INSTALL_PATH] $expected_depot]} {
    error "Private generator binding mismatch; stop before generation"
}
# The launcher supplies the export path. Refuse redirected generation/context.
if {![string equal -nocase [file normalize $IP_EXPORT_PATH] [file normalize {@EXPORT@}]]} {
    error "Private export path mismatch; stop before generation"
}
if {$IP_COMPONENT_NAME ne "@COMP@"} {
    error "Private component name mismatch; expected @COMP@"
}
set binding_file [open {@MARKER@} w]
puts $binding_file [list PRIVATE_DDR1333_GENERATOR_BOUND $IP_INSTALL_PATH $IP_EXPORT_PATH $IP_COMPONENT_NAME]
close $binding_file
'''.replace('@DEPOT@', (out/'depot').as_posix()).replace('@EXPORT@', export.as_posix()).replace('@MARKER@', (out/'gui_depot_binding.log').as_posix()).replace('@COMP@', comp_name), encoding='utf-8')
        guarded = [out/'depot/Dependency.tcl'] + list((out/'depot').rglob('plugin_end.tcl'))
        for p in guarded:
            p.write_bytes(('source {'+guard.as_posix()+'}\n').encode()+p.read_bytes())
        # Update recorded modified SHA values, retaining the installed originals.
        for entry in changes:
            entry['after'] = sha(out/entry['path'])
        gui_argv = argv[:-2]  # Interactive configuration: omit automatic copy mode.
        assert all(not any(c in arg for c in '"%&|<>\r\n') for arg in gui_argv)
        command = ' '.join('"'+arg+'"' for arg in gui_argv)
        launcher = out/'open_ddr1333_gui.cmd'
        launcher.write_bytes(('@echo off\r\ncd /d "%~dp0"\r\n'+command+'\r\necho IPTool window closed. Keep this folder for review.\r\npause\r\n').encode('ascii'))
        record['manual_gui'] = {'argv':gui_argv, 'launcher':launcher.name,
                                'binding_marker':'gui_depot_binding.log',
                                'binding_guard_sha256':sha(guard),
                                'status':'prepared; GUI entry not verified',
                                'note':('Launcher keeps the historical file-path form for -user/-gen. The 2026-10-16 experiments showed '
                                        'the automatic modes validate these options as directories; whether the interactive entry is also '
                                        'affected is not established (GUI marker was not observed within 40 s of a monitored launch).'),
                                'safety':'Do not Generate unless marker contains this private depot/output and GUI values match.'}
    (out/'preparation.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    (out/'frozen_prepare_ddr1333_ip.py').write_bytes(Path(__file__).read_bytes())
    files = {p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file()}
    (out/'preparation_manifest.json').write_text(json.dumps(files, indent=2)+'\n', encoding='utf-8')
    print(out)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manual-gui-kit', action='store_true', help='Prepare a guarded interactive launcher; do not launch it')
    parser.add_argument('--comp-name', default='ddrmc_1333', help='IP instance name passed to -comp (default ddrmc_1333)')
    parser.add_argument('--use-value', choices=['copy', 'default'], default='copy', help='-use_value mode (default copy, historical form)')
    parser.add_argument('--extra-flag', action='append', default=[], metavar='TOKEN',
                        help='extra argv token inserted right after TD_PATH (repeatable; e.g. --extra-flag -no_status)')
    parser.add_argument('--user-mode', choices=['file', 'directory'], default='file',
                        help='file = historical (…/ddrmc_x32.xml); directory = validated directory form (…/ddrmc_x32)')
    parser.add_argument('--gen-mode', choices=['file', 'directory'], default='file',
                        help='file = historical (…/Component.xml); directory = validated directory form (…/depot)')
    parser.add_argument('--entry-status', default=ENTRY_STATUS,
                        help='factual record of the current headless-entry state; do not set to inferred/unverified claims')
    a = parser.parse_args()
    prepare(a.manual_gui_kit, comp_name=a.comp_name, use_value=a.use_value, extra_flags=a.extra_flag,
            user_mode=a.user_mode, gen_mode=a.gen_mode, entry_status=a.entry_status)
