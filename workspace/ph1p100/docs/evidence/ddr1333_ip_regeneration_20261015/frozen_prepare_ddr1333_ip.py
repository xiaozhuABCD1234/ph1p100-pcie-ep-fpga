"""Prepare an isolated DDR1333 IP regeneration trial; never launch or delete files."""
from pathlib import Path
import datetime
import hashlib
import json
import re

BASE = Path('D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820')
DEPOT = Path('D:/downlaod/ip/depot/MIS_DDRF6F1D0P0_1.2')
GOLDEN = Path('D:/TD/work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/golden_adc/ap115v2_ddr3_x32.adc')


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


def prepare():
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
    argv = ['D:/downlaod/bin/IpTool.exe', 'D:/downlaod', '-user', (out/'source/ddrmc_x32/ddrmc_x32.xml').as_posix(), '-gen', (out/'depot/Component.xml').as_posix(), '-device', 'PH1P100SBG484', '-export_to', export.as_posix(), '-comp', 'ddrmc_1333', '-use_value', 'copy']
    record = {'baseline': BASE.as_posix(), 'baseline_manifest_sha256': sha(BASE/'input_manifest.json'), 'user_values': user_values, 'expected_derived': {'CL':10, 'CWL':7, 'tCK_min_ns':1.5, 'physical_clock_max_mhz':'2000/3'}, 'pin_comparison': {'matched':70, 'unused_extra':{'ddr_addr[14]':'J5'}}, 'generator_cleanup_preserved': changes, 'argv': argv, 'cli_entry_status':'inferred from executable usage; not yet executed', 'generated':False, 'hardware_download':False}
    (out/'preparation.json').write_text(json.dumps(record, indent=2)+'\n', encoding='utf-8')
    (out/'frozen_prepare_ddr1333_ip.py').write_bytes(Path(__file__).read_bytes())
    files = {p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file()}
    (out/'preparation_manifest.json').write_text(json.dumps(files, indent=2)+'\n', encoding='utf-8')
    print(out)


if __name__ == '__main__':
    prepare()
