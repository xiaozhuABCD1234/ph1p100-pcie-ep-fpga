"""Freeze one DDR1333 integration candidate (or the 1600 control) from the frozen 002820 baseline.

Default mode derives D:/TD/work/csi2/prj/camera_rgb565_ddr1333_<ts>:
byte-for-byte copy of camera_rgb565_wb_20261015_002820 (220 manifest items, per-item SHA
verified) with vendor/ip/ddrmc_x32/** wholly replaced by the frozen run1 DDR1333 IP closure
(61 files; wrapper renamed by the tool) and the three IP generation logs replaced. Every
non-IP item must stay byte-identical (machine-accounted: changed set == 27 closure files +
adc/proc logs; wrapper rename = 1 removed + 1 added; drc_check.log is byte-identical by nature
and recorded as such, not hidden).

--control derives camera_rgb565_ddr1600ctl_<ts>: byte-for-byte copy plus this frozen script only.
The control candidate exists to re-run the SAME TD 6.2.3 toolchain/scripts on the unchanged
1600 IP (E2b), isolating the tool-version factor from the DDR-rate factor in the 1333-vs-1600
comparison.

Discipline: create-only (OUT.mkdir(exist_ok=False)); never delete; no path relocation; single
IP source (run1 is copied; the run2 mirror is only registered); no build/route/STA/GUI/hardware.
"""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re

if not __debug__:
    raise RuntimeError('Run this freezer without Python -O; assertions are required gates.')

PRJ = Path('D:/TD/work/csi2/prj')
BASE = PRJ/'camera_rgb565_wb_20261015_002820'
IP_RUN1 = Path('D:/TD/work/csi2/_validation/td2026_gui_bootstrap_20261017_000935')
IP_OUT = IP_RUN1/'ip_out'
IP_RUN2 = Path('D:/TD/work/csi2/_validation/td2026_b_run2_20261017_143128')
TD_ROOT = Path('D:/anlogic/TD_Release_2026.2')

BASELINE_MANIFEST_SHA = '8f8e4efe9b9320cbc595f94e337395744dbd957630576123576ee2c357f9a1c8'
BASELINE_BIT_SHA = '4d591c31da9a71b9c261972e5089930af3e441c2096ed37736c8d2340ddd8865'
RUN1_MANIFEST_SHA = 'd71057f3e3b859ad34bbec477232938a8aa6de8bbddf04ae1c75605074c08434'
RUN2_MANIFEST_SHA = '9b3e5d002b6c433726ae2fe703ee40f9f1ce933e494f95712cc3173acd09d716'
RUN2_DIFF_REPORT_SHA = '579be12af6092cf13b38c390a71e329d3f67e1b40b66e0fcdd3fa56e3fe3c8cb'
RUN2_SEMANTIC_DIFF_SHA = '9b30df6584fa42ec848c7d17159d8a0488e42f08997da9791859a8e17c6c15ef'
INPUT_PINS_SHA = 'f09042381856bf55de58f89debf70167a2956904528d92fd71c6993c08db33da'
BOOT_AL_SHA = 'ef721c4dc9f3de2038d50203046e6d5eeba41703dfca55b46400eb8838db7210'
IP_PREFIX = 'vendor/ip/ddrmc_x32/'
OLD_WRAPPER = IP_PREFIX+'ph1p_ddrmc_wrapper_ddrmc_x32.v'
NEW_WRAPPER = IP_PREFIX+'ddrmc_x32_ph1p_ddrmc_wrapper.v'
LOG_MAP = {'vendor/ip/ddrmc_x32_adc.log': 'ddrmc_x32_adc.log',
           'vendor/ip/ddrmc_x32_drc_check.log': 'ddrmc_x32_drc_check.log',
           'vendor/ip/ddrmc_x32_proc.log': 'ddrmc_x32_proc.log'}

# Frozen reference anchors of the run1 closure (fpga-design-guide.md sec.2; all re-verified here).
ANCHORS = {
    'ddrmc_x32/ddrmc_x32.xml': '92155f9d1b34f06b80292cd884dbb202aa3cdfc78d99b67f19f09f2b81b8b606',
    'ddrmc_x32/ddrmc_x32.v': '7edef919ab538b4777ac9124a527b2aa68f260a3e4e5393786a31da135a326b0',
    'ddrmc_x32/ddrmc_x32_ph1p_ddrmc_wrapper.v': '609f3c60ce46ec1f25b414c1270d7b6e964e9658b7c3641b54ce78100ae28fb6',
    'ddrmc_x32/.params_ddrmc_x32.txt': '86d1c0b66b1e437b092382f0a289f3c54813add3625093bce0a1026f97b38a2f',
    'ddrmc_x32/.m_params_ddrmc_x32.txt': '6401066a5cf41aae3db87d687eadddd0bbca2089ea49723d72a8b9d2b8a40ffb',
    'ddrmc_x32/Design.xml': '72f2bb57dadea7b38b25bde251154935d36b25500ae22274f46f7fb7ed5ae24f',
    'ddrmc_x32/src/adc/ddrmc_x32.adc': '751997438bd28e2a956864493b3083008e1458878263dd709a569feca09c0baa',
    'ddrmc_x32/src/sdc/ddrmc_x32.sdc': 'adb6317927dfd09095073cad40be8e63d39ea3d941b4c790f2f483b1aed428d6',
    'ddrmc_x32_adc.log': 'c50695df67a6902a17cb52036e1d03534dfa308ca788bf7197fa42f5adc229ff',
    'ddrmc_x32_drc_check.log': '757219756351ee532625bb7def55d6e08dc0c42cabd37c77d0974b952e68537e',
    'ddrmc_x32_proc.log': '9c1cdf4b2f89604c9189c6504ecb8485be1aef658b05807012687eb72026686f',
}

# Frozen machine-verified diff list: the 27 of the 60 same-name closure files that differ
# old (1600/6.2.2 tool era) vs new (1333/6.2.3) -- fpga-design-guide.md sec.2. Re-computed and
# required to match exactly; any mismatch stops the derivation.
EXPECTED_DIFF_27 = [
    '.m_params_ddrmc_x32.txt', '.params_ddrmc_x32.txt', 'Design.xml', 'DesignConfiguration.xml',
    'ddrmc_x32.v', 'ddrmc_x32.xml', 'sim/fileset/fileset_mis.f',
    'src/rtl/cal/ph1p_ddrphy_cal_gate_wrapper.v', 'src/rtl/cal/ph1p_ddrphy_cal_wla.v',
    'src/rtl/include/ph1p_mis_define.vh', 'src/rtl/mc/mc0_alc_mc_top_all.enc.sv',
    'src/rtl/phy/ddrphy_cfg_rom.txt', 'src/rtl/phy/ph1p_ddrphy.v',
    'src/rtl/phy/ph1p_ddrphy_cmd_decode.v', 'src/rtl/phy/ph1p_ddrphy_cmd_execution.v',
    'src/rtl/phy/ph1p_ddrphy_cmd_wrapper.v', 'src/rtl/phy/ph1p_ddrphy_fast_init_wrapper.v',
    'src/rtl/phy/ph1p_ddrphy_init.v', 'src/rtl/phy/ph1p_ddrphy_top.v',
    'src/rtl/phy/ph1p_ddrphy_wphase_ctl.v', 'src/rtl/phy/ph1p_ddrphy_wrapper.v',
    'src/rtl/timing/ddr3/ddr3_1066.vh', 'src/rtl/timing/ddr3/ddr3_1333.vh',
    'src/rtl/timing/ddr3/ddr3_1600.vh', 'src/rtl/timing/ddr3/ddr3_800.vh',
    'src/rtl/timing/ddr3/ddr3_parameter.vh', 'src/rtl/top/ph1p_ddrmc_top.v']

# Files inside vendor/ip/ddrmc_x32/ that ddrmc_x32.xml does NOT list in its RTL fileSet; each one
# has a verified internal reference (the xml itself/Design files/params records/sim fileset and
# the two Verilog include-dir headers). The dev-plan literal allowance named only 5 of these;
# the exact 9-item set below is the machine-verified closure and is asserted as equality.
CLOSURE_EXTRAS = {
    'ddrmc_x32.xml': 'the IP descriptor itself',
    'Design.xml': 'IP-XACT design entity referenced via designInstantiation in ddrmc_x32.xml',
    'DesignConfiguration.xml': 'IP-XACT design configuration referenced via designConfigurationInstantiation',
    '.params_ddrmc_x32.txt': 'IpTool parameter record',
    '.m_params_ddrmc_x32.txt': 'IpTool derived parameter record',
    '.ports_ddrmc_x32.txt': 'IpTool port record',
    'sim/fileset/fileset_mis.f': 'MIS simulation file set (declares the include dirs)',
    'src/rtl/include/ph1p_mis_define.vh': 'Verilog header; included by mc0_alc_mc_top_all.enc.sv and ph1p_ddrphy_wrapper.v; incdir declared in fileset_mis.f',
    'src/rtl/phy/include/ph1p_ddrphy_board_delay.vh': 'Verilog header; included by ph1p_ddrphy_fast_init_wrapper.v; incdir declared in fileset_mis.f',
}
PLAN_LITERAL_EXTRAS = {'Design.xml', 'DesignConfiguration.xml', '.params_ddrmc_x32.txt',
                       '.m_params_ddrmc_x32.txt', '.ports_ddrmc_x32.txt'}

TOOL_ANCHORS = {
    'release': 'TD Release_2026.2 (6.2.3.210850)',
    'db_version_from_guide': '46207',
    'cli': {'path': 'D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe',
            'sha256': '2629e474df036a871807e564190febfbbd9780a09365f600c10463911c8c1223'},
    'td': {'path': 'D:/anlogic/TD_Release_2026.2/bin/td.exe',
           'sha256': 'fa2a5ac6e5342b2f801efa7a6aa345a5fd02d6f25ffa0d1e6380ff0ebd306a87'},
    'iptool': {'path': 'D:/anlogic/TD_Release_2026.2/bin/IpTool.exe',
               'sha256': '5b0654aaa44ae9340eefcdc8cac54faed7490b0643f3fa53908c5706db175cec'},
    'arch_db': {'path': 'D:/anlogic/TD_Release_2026.2/arch/ph1_100p.db',
                'sha256': '939ec2948f40546c9c545786af96ab4cb007a5ecf063f133da2b7835983ff77b'},
    'license': {'path': 'D:/anlogic/TD_Release_2026.2/license/Anlogic.lic',
                'sha256': 'dc19fee62eff532d4c6a84c04ce34267b03190b753a3198a6788c3ec9e45c1a6'},
}

UNCHANGED_GUARDS = {
    'camera_ddr_display_top.v': '738e199f303bfdb9d18dbff78f0affcd8a03041d1bd0ca738f2f1d57ebd5eb35',
    'ddrmc_display_top.v': 'b75ddd3b13b478b857ed18049b2eed399e7702eca88807319a7b3424dea274d5',
    'build_rgb565.tcl': '5aa25fd23b3d73d061b86cf82092f8c35e7bc9ba3b8d2b769243f071129288f9',
    'route_rgb565.tcl': '019db289dec71867c51af16b334c1e0efb19a4b1d57a3e4e5870e8c672bb5489',
    'bitgen_rgb565.tcl': 'fcce5e2088e523a2b9b5f91633b172c411058cc382af8a2393d05e7af4d64201',
    'timing.sdc': '0c32c5f7a536bbc811901d5af254a4fddc270dcdd2b59c16caeb006ef0f7fe1c',
    'board.adc': '1cb30346fa17da6bb0e77802ca72c4b4bb4aecc1445711e19391cf4ee2271580',
    IP_PREFIX+'src/adc/ddrmc_x32.adc': '751997438bd28e2a956864493b3083008e1458878263dd709a569feca09c0baa',
    IP_PREFIX+'src/sdc/ddrmc_x32.sdc': 'adb6317927dfd09095073cad40be8e63d39ea3d941b4c790f2f483b1aed428d6',
}

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--control', action='store_true',
                    help='produce the DDR1600 control candidate (002820 byte copy + frozen script only)')
parser.add_argument('--timestamp', default=None, metavar='YYYYMMDD_HHMMSS',
                    help='candidate timestamp; default = now (allows pairing ddr1333/control runs)')
args = parser.parse_args()
timestamp = args.timestamp or datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
assert re.fullmatch(r'\d{8}_\d{6}', timestamp), timestamp
mode = 'control' if args.control else 'ddr1333'
OUT = PRJ/(('camera_rgb565_ddr1600ctl_' if args.control else 'camera_rgb565_ddr1333_')+timestamp)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def ok(step, detail):
    print('PASS[%s] %s ; %s' % (mode, step, detail))


# --- A1: frozen baseline 002820 (read-only) -------------------------------------------------
assert sha(BASE/'input_manifest.json') == BASELINE_MANIFEST_SHA, 'Baseline manifest mismatch'
assert sha(BASE/'camera_ddr_display.bit') == BASELINE_BIT_SHA, 'Baseline bit mismatch'
manifest = json.loads((BASE/'input_manifest.json').read_bytes())
assert len(manifest) == 220, 'Baseline input count mismatch'
for rel, digest in manifest.items():
    path = (BASE/rel).resolve()
    assert path.is_relative_to(BASE.resolve()) and sha(path) == digest, 'Baseline input mismatch: '+rel
ok('A1-base', 'manifest 8f8e4efe/220 items + bit 4d591c31 re-verified')

# --- A2: single IP source = run1 closure (64 files), run2 registered as mirror only ---------
assert sha(IP_RUN1/'candidate_manifest.json') == RUN1_MANIFEST_SHA, 'Run1 candidate manifest mismatch'
candidate = json.loads((IP_RUN1/'candidate_manifest.json').read_bytes())
assert candidate['file_count'] == 64 and len(candidate['files']) == 64, 'Run1 file count mismatch'
for item in candidate['files']:
    path = (IP_RUN1/item['rel']).resolve()
    assert path.is_relative_to(IP_RUN1.resolve()), item['rel']
    assert path.stat().st_size == item['bytes'] and sha(path) == item['sha256'].lower(), 'Run1 input mismatch: '+item['rel']
assert sha(IP_RUN2/'run2_candidate_manifest.json') == RUN2_MANIFEST_SHA, 'Run2 mirror manifest mismatch'
assert sha(IP_RUN2/'run1_run2_diff_report.json') == RUN2_DIFF_REPORT_SHA, 'Run2 diff report mismatch'
assert sha(IP_RUN2/'semantic_diff_result.json') == RUN2_SEMANTIC_DIFF_SHA, 'Run2 semantic diff mismatch'
ok('A2-source', 'run1 64/64 files re-verified (D71057F3); run2 mirror 9B3E5D00 registered, never copied')

# --- A3: run1 closure key anchors + bootstrap evidence files --------------------------------
for rel, want in ANCHORS.items():
    assert sha(IP_OUT/rel) == want, 'Run1 anchor mismatch: '+rel
assert sha(IP_RUN1/'input_pins.adc') == INPUT_PINS_SHA, 'Run1 bootstrap input_pins.adc mismatch'
assert sha(IP_RUN1/'ddr1333_proj_boot.al') == BOOT_AL_SHA, 'Run1 boot .al mismatch (bystander only)'
ok('A3-anchors', '11 closure anchors + input_pins.adc + boot .al (bystander) re-verified')

# --- A4: 1333 parameter text (frozen values) ------------------------------------------------
params_text = (IP_OUT/'ddrmc_x32/.params_ddrmc_x32.txt').read_text(encoding='utf-8', errors='replace')
for probe in ('PH1P_DDR_SPEED : 1333.00', 'PH1P_SPEED_BIN : DDR3-1333J', 'CWL : 7', 'tCK : 1500'):
    assert probe in params_text, 'Param probe missing: '+probe
mparams_text = (IP_OUT/'ddrmc_x32/.m_params_ddrmc_x32.txt').read_text(encoding='utf-8', errors='replace')
for probe in ('CL; 1; 10', 'PLL0_FBKCLK_DIV; 1; 80', 'PLL0_REFCLK_DIV; 1; 3', 'PLL1_REFCLK_FREQ; 1; 166.7'):
    assert probe in mparams_text, 'Derived param probe missing: '+probe
ok('A4-params', '1333.00/DDR3-1333J/CWL7/tCK1500 + CL10/PLL0 80/3 + PLL1 166.7 present')

# --- A5: interface invariants (ports 53 lines equal; wrapper rename; ipinst prefix) ---------
def port_lines(path):
    text = Path(path).read_text(encoding='utf-8', errors='replace')
    return [line.strip() for line in text.splitlines() if re.match(r'\s*(input|output|inout)\b', line)]

old_v = BASE/(IP_PREFIX+'ddrmc_x32.v')
new_v = IP_OUT/'ddrmc_x32/ddrmc_x32.v'
old_ports, new_ports = port_lines(old_v), port_lines(new_v)
assert len(old_ports) == len(new_ports) == 53 and old_ports == new_ports, 'ddrmc_x32 port lines differ'
new_v_text = new_v.read_text(encoding='utf-8', errors='replace')
old_v_text = old_v.read_text(encoding='utf-8', errors='replace')
assert new_v_text.splitlines()[68].strip() == 'ddrmc_x32_ph1p_ddrmc_wrapper'
assert old_v_text.splitlines()[68].strip() == 'ph1p_ddrmc_wrapper_ddrmc_x32'
assert ')ph1p_ddrmc_wrapper' in new_v_text and ')ph1p_ddrmc_wrapper' in old_v_text, 'instance name changed'
assert '.tCK(1500)' in new_v_text and '.tCK(1250)' in old_v_text, 'tCK anchor changed'
wrapper_text = (IP_OUT/'ddrmc_x32/ddrmc_x32_ph1p_ddrmc_wrapper.v').read_text(encoding='utf-8', errors='replace')
assert 'module ddrmc_x32_ph1p_ddrmc_wrapper' in wrapper_text and 'MC0_DDR3_1333J' in wrapper_text
assert 'ph1p_ddrmc_top' in wrapper_text, 'wrapper lost ph1p_ddrmc_top instantiation'
adc_text = (IP_OUT/'ddrmc_x32/src/adc/ddrmc_x32.adc').read_text(encoding='utf-8', errors='replace')
ipinst = re.findall(r'set_ipinst_assignment\s+(\S+)', adc_text)
assert ipinst and all(p.startswith('{ph1p_ddrmc_wrapper/ph1p_ddrmc_top/') for p in ipinst), 'ipinst prefix changed'
ok('A5-interface', '53 port lines equal; wrapper renamed (module MC0_DDR3_1333J); %d ipinst paths keep ph1p_ddrmc_wrapper/ph1p_ddrmc_top' % len(ipinst))

# --- A6: xml fileSet vs disk closure (no dangling, no stray) --------------------------------
def xml_listed(ip_dir):
    raw = (ip_dir/'ddrmc_x32.xml').read_text(encoding='utf-8-sig', errors='replace')
    listed = re.findall(r'<ipxact:file>.*?<ipxact:name>([^<]+)</ipxact:name>.*?</ipxact:file>', raw, re.S)
    assert raw.count('<ipxact:file>') == len(listed), 'xml file block count mismatch'
    return listed

def disk_rel(ip_dir):
    return {p.relative_to(ip_dir).as_posix() for p in ip_dir.rglob('*') if p.is_file()}

def closure_check(ip_dir, tag):
    listed, disk = set(xml_listed(ip_dir)), disk_rel(ip_dir)
    assert listed <= disk, tag+' xml lists a file missing on disk: '+repr(sorted(listed-disk))
    assert disk - listed == set(CLOSURE_EXTRAS), tag+' disk extras differ from verified set'
    return listed, disk

new_listed, new_disk = closure_check(IP_OUT/'ddrmc_x32', 'run1')
old_listed, old_disk = closure_check(BASE/IP_PREFIX, '002820')
assert len(new_disk) == len(old_disk) == 61 and len(new_listed) == 52
beyond_plan = (new_disk - new_listed) - PLAN_LITERAL_EXTRAS
assert beyond_plan == {'ddrmc_x32.xml', 'sim/fileset/fileset_mis.f',
                       'src/rtl/include/ph1p_mis_define.vh',
                       'src/rtl/phy/include/ph1p_ddrphy_board_delay.vh'}, beyond_plan
fileset_text = (IP_OUT/'ddrmc_x32/sim/fileset/fileset_mis.f').read_text(encoding='utf-8', errors='replace')
assert '#+incdir+<mis_path>/ddrmc_x32/src/rtl/include' in fileset_text
assert '#+incdir+<mis_path>/ddrmc_x32/src/rtl/phy/include' in fileset_text
assert 'ph1p_mis_define' in (IP_OUT/'ddrmc_x32/src/rtl/mc/mc0_alc_mc_top_all.enc.sv').read_text(encoding='utf-8', errors='replace')
assert 'ph1p_mis_define' in (IP_OUT/'ddrmc_x32/src/rtl/phy/ph1p_ddrphy_wrapper.v').read_text(encoding='utf-8', errors='replace')
assert 'ph1p_ddrphy_board_delay' in (IP_OUT/'ddrmc_x32/src/rtl/phy/ph1p_ddrphy_fast_init_wrapper.v').read_text(encoding='utf-8', errors='replace')
ok('A6-closure', 'xml 52/52 present; disk=52+xml extras(9, each referenced; plan literal named 5, +4 recorded)')

# --- A7: machine diff accounting: exactly the frozen 27 changed + 2 logs; rename 1/1 ---------
old_closure = {rel[len(IP_PREFIX):] for rel in manifest if rel.startswith(IP_PREFIX)}
assert len(old_closure) == 61, 'base closure count mismatch'
identical, different = [], []
for rel in sorted(old_closure & new_disk):
    (identical if sha(BASE/(IP_PREFIX+rel)) == sha(IP_OUT/('ddrmc_x32/'+rel)) else different).append(rel)
assert len(identical) == 33 and len(different) == len(EXPECTED_DIFF_27) == 27, 'diff counts changed'
assert set(different) == set(EXPECTED_DIFF_27), 'computed 27-diff set != frozen list'
assert old_closure - new_disk == {'ph1p_ddrmc_wrapper_ddrmc_x32.v'}, 'only old wrapper may leave the closure'
assert new_disk - old_closure == {'ddrmc_x32_ph1p_ddrmc_wrapper.v'}, 'only new wrapper may join the closure'
log_state = {rel: ('same' if sha(BASE/rel) == sha(IP_OUT/src) else 'changed') for rel, src in LOG_MAP.items()}
assert log_state == {'vendor/ip/ddrmc_x32_adc.log': 'changed',
                     'vendor/ip/ddrmc_x32_drc_check.log': 'same',
                     'vendor/ip/ddrmc_x32_proc.log': 'changed'}, log_state
outside = [rel for rel in manifest if not rel.startswith(IP_PREFIX) and rel not in LOG_MAP]
assert len(outside) == 156, 'outside-scope count mismatch'
changed_names = {IP_PREFIX+r for r in different} | {rel for rel, s in log_state.items() if s == 'changed'} | {NEW_WRAPPER}
removed_names = {OLD_WRAPPER}
total_entries = len(changed_names) + 1  # + removed
assert total_entries == 31, 'machine diff entry count changed'
plan_expected_entries = 32
ok('A7-diff', '27 closure + adc/proc logs changed; drc identical; rename 1 removed/1 added; total 31 (plan literal 32; deviation recorded)')

# --- A8: tool anchors (6.2.3) re-verified, read-only ----------------------------------------
for key in ('cli', 'td', 'iptool', 'arch_db', 'license'):
    entry = TOOL_ANCHORS[key]
    assert Path(entry['path']).is_file() and sha(entry['path']) == entry['sha256'], 'Tool anchor mismatch: '+key
ok('A8-tools', '6.2.3 CLI 2629e474 + td/IpTool/arch/license anchors re-verified')

# --- derive (create-only) --------------------------------------------------------------------
assert not OUT.exists(), 'Never overwrite a candidate'
OUT.mkdir(exist_ok=False)
changes, removed, added = {}, {}, {}
if mode == 'ddr1333':
    assert OLD_WRAPPER in manifest and NEW_WRAPPER not in manifest
    for rel in manifest:
        path = OUT/rel
        if rel == OLD_WRAPPER:
            removed[rel] = {'before_sha256': manifest[rel], 'action': 'not_copied',
                            'reason': 'wrapper renamed by the 6.2.3 re-generation; replaced by '+NEW_WRAPPER+' (copy-only derivation, nothing deleted)'}
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        if rel.startswith(IP_PREFIX):
            path.write_bytes((IP_OUT/'ddrmc_x32'/rel[len(IP_PREFIX):]).read_bytes())
            reason = 'DDR1333 IP closure file from the frozen 6.2.3 run1 generation (single source)'
        elif rel in LOG_MAP:
            path.write_bytes((IP_OUT/LOG_MAP[rel]).read_bytes())
            reason = 'IP generation log from the frozen 6.2.3 run1 generation'
        else:
            path.write_bytes((BASE/rel).read_bytes())
            reason = None
        after = sha(path)
        if after != manifest[rel]:
            assert reason, 'unexpected change outside the replacement scope: '+rel
            changes[rel] = {'before_sha256': manifest[rel], 'after_sha256': after, 'reason': reason}
    assert set(changes) == {IP_PREFIX+r for r in different} | {rel for rel, s in log_state.items() if s == 'changed'}
    wrapper_bytes = (IP_OUT/'ddrmc_x32/ddrmc_x32_ph1p_ddrmc_wrapper.v').read_bytes()
    (OUT/NEW_WRAPPER).write_bytes(wrapper_bytes)
    assert sha(OUT/NEW_WRAPPER) == ANCHORS['ddrmc_x32/ddrmc_x32_ph1p_ddrmc_wrapper.v']
    added[NEW_WRAPPER] = {'sha256': sha(OUT/NEW_WRAPPER), 'reason': 'wrapper renamed by the 6.2.3 re-generation of the DDR1333 IP'}
    # post-copy scope assertions
    assert not (OUT/OLD_WRAPPER).exists()
    for rel in outside:
        assert sha(OUT/rel) == manifest[rel], 'outside-scope drift: '+rel
    for rel in identical:
        assert sha(OUT/(IP_PREFIX+rel)) == manifest[IP_PREFIX+rel], 'identical file drifted: '+rel
    for rel in different:
        assert sha(OUT/(IP_PREFIX+rel)) == sha(IP_OUT/('ddrmc_x32/'+rel)), 'diff file != run1: '+rel
else:
    for rel in manifest:
        path = OUT/rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((BASE/rel).read_bytes())
        assert sha(path) == manifest[rel], 'control copy drifted: '+rel
    assert not changes and not removed, 'control must be a zero-change copy'

for rel, want in UNCHANGED_GUARDS.items():
    assert sha(OUT/rel) == want, 'unchanged guard mismatch: '+rel
pre_frozen = sum(1 for p in OUT.rglob('*') if p.is_file())
assert pre_frozen == 220, 'candidate file count before frozen script mismatch: %d' % pre_frozen
(OUT/'frozen_prepare_rgb565_ddr1333.py').write_bytes(Path(__file__).read_bytes())
assert sha(OUT/'frozen_prepare_rgb565_ddr1333.py') == sha(Path(__file__).resolve())
files = sorted(p for p in OUT.rglob('*') if p.is_file())
assert len(files) == 221, 'candidate file count after frozen script mismatch: %d' % len(files)
inputs = {p.relative_to(OUT).as_posix(): sha(p) for p in files}
assert len(inputs) == 221 and 'frozen_prepare_rgb565_ddr1333.py' in inputs
assert 'input_manifest.json' not in inputs and 'ddr1333_overlay.json' not in inputs
ok('A9-derived', 'candidate %s frozen: 221 items (220 base%s + frozen script)' % (OUT.name, '' if mode == 'control' else ', wrapper swapped'))

fairness = [
    {'check': 'top-level + ddrmc_display_top byte-equal to 002820', 'result': 'pass', 'evidence': 'UNCHANGED_GUARDS + outside-scope loop'},
    {'check': 'build/route/bitgen tcl equal (5aa25fd2/019db289/fcce5e20)', 'result': 'pass', 'evidence': 'UNCHANGED_GUARDS'},
    {'check': 'timing.sdc / board.adc equal (0c32c5f7/1cb30346)', 'result': 'pass', 'evidence': 'UNCHANGED_GUARDS'},
    {'check': 'IP src/adc + src/sdc byte-equal old/new', 'result': 'pass', 'evidence': 'UNCHANGED_GUARDS + identical count 33'},
    {'check': 'all remaining project RTL/ROM refs byte-equal (no path relocation)', 'result': 'pass', 'evidence': 'outside-scope loop (156/156)'},
    {'check': 'referenced ROM path kept (fair-comparison no-relocation rule)', 'result': 'pass', 'evidence': 'outside-scope loop; no .v rewritten'},
    {'check': 'unreferenced vendor leftovers kept as-is (RTL/**, ap115v2.adc)', 'result': 'pass', 'evidence': 'outside-scope loop'},
    {'check': 'strategy/params untouched (TimingHigh, no SDC/ADC edits)', 'result': 'pass', 'evidence': 'script hashes equal'},
    {'check': 'tool version pinned 6.2.3 for the whole chain (E2)', 'result': 'pass', 'evidence': 'TOOL_ANCHORS'},
    {'check': 'STA wording/gate left to E2 (not run here)', 'result': 'not_run', 'evidence': 'E1 scope: derivation only'},
]
overlay = {
    'schema': 1,
    'kind': 'rgb565_ddr1333_candidate_overlay',
    'mode': mode,
    'created_at': datetime.datetime.now().astimezone().isoformat(),
    'candidate': OUT.as_posix(),
    'base': BASE.as_posix(),
    'baseline_manifest_sha256': BASELINE_MANIFEST_SHA,
    'baseline_bit_sha256': BASELINE_BIT_SHA,
    'input_count': len(inputs),
    'new_ip': {
        'run1_root': IP_OUT.as_posix(),
        'run1_manifest': 'candidate_manifest.json',
        'run1_manifest_sha256': RUN1_MANIFEST_SHA,
        'run1_file_count': 64,
        'run2_mirror_root': IP_RUN2.as_posix(),
        'run2_manifest_sha256': RUN2_MANIFEST_SHA,
        'run2_mirror_note': 'equivalent mirror (run1==run2 after field-level normalization); registered only, never copied (single-source discipline)',
        'consumed_by_this_candidate': mode == 'ddr1333',
    },
    'replacement_scope': {
        'closure_files': 61,
        'log_files': 3,
        'total': 64,
        'rule': 'vendor/ip/ddrmc_x32/<rel> <- run1 ip_out/ddrmc_x32/<rel>; vendor/ip/<log> <- run1 ip_out/<log>',
    },
    'changes': changes,
    'removed': removed,
    'added': {**added, 'frozen_prepare_rgb565_ddr1333.py': {'sha256': sha(OUT/'frozen_prepare_rgb565_ddr1333.py')}},
    'diff_accounting': {
        'identical_within_closure': identical,
        'changed_same_name_27': sorted(different),
        'log_replacement': log_state,
        'total_entries': 0 if mode == 'control' else total_entries,
        'plan_expected_total': 0 if mode == 'control' else plan_expected_entries,
        'deviation': 'none; zero diff outside the replacement scope (control: zero diff except frozen script)' if mode == 'control' else
                      'plan sec.4.1.7(d) estimated 32 entries assuming all 3 IP logs change; actual=31 because vendor/ip/ddrmc_x32_drc_check.log is byte-identical old vs new (sha 75721975...). All actual differences stay inside the 64-file replacement scope; outside scope = 0 diff.',
    },
    'closure_extras': {rel: CLOSURE_EXTRAS[rel] for rel in sorted(CLOSURE_EXTRAS)},
    'closure_extras_deviation': 'dev-plan literal allowance named 5 metadata files; machine closure needs 9 (adds ddrmc_x32.xml itself, sim/fileset/fileset_mis.f, and the two Verilog include-dir headers, each with verified internal references). Exact-9 equality asserted instead of the weaker subset.',
    'unchanged_guards': {rel: sha(OUT/rel) for rel in UNCHANGED_GUARDS},
    'fairness_checklist': fairness,
    'hardware_verified': False,
    'hardware_download': False,
    'build_tool_anchor': TOOL_ANCHORS,
}
(OUT/'input_manifest.json').write_bytes((json.dumps(inputs, indent=2)+'\n').encode())
(OUT/'ddr1333_overlay.json').write_bytes((json.dumps(overlay, indent=2)+'\n').encode())
summary = {
    'mode': mode, 'candidate': OUT.as_posix(),
    'input_manifest_sha256': sha(OUT/'input_manifest.json'), 'input_count': len(inputs),
    'overlay_sha256': sha(OUT/'ddr1333_overlay.json'),
    'frozen_script_sha256': sha(OUT/'frozen_prepare_rgb565_ddr1333.py'),
    'changed_entries': len(changes), 'removed_entries': len(removed), 'added_entries': len(added),
    'hardware_verified': False,
}
print(json.dumps(summary, indent=2))
print(OUT)
