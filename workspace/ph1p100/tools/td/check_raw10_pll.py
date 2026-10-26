"""Check generated PH1P100 RAW10 clocks from effective RTL parameters.

This is a file/configuration audit, not PLL simulation or timing sign-off.
Exit 0 for the approved profile, 2 for a generated configuration mismatch.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument('--ip-dir', type=Path, default=Path(
    r'D:\TD\work\csi2\prj\camera_peer\uisrc\03_ip\raw10_clocks'))
parser.add_argument('--output', type=Path)
parser.add_argument('--clock-top', type=Path, help='Authored clock wrapper to audit without modifying generated IP')
parser.add_argument('--profile', choices=['stable30','display60'], default='stable30')
args = parser.parse_args()
ip = args.ip_dir.resolve()
top_path = args.clock_top.resolve() if args.clock_top else ip/'raw10_clocks.v'
wrapper_path = ip/'RTL/ph1p_phy_pll_wrapper_raw10_clocks.v'
design_path = ip/'Design.xml'
top = top_path.read_text(encoding='utf-8-sig')
wrapper = wrapper_path.read_text(encoding='utf-8-sig')
metadata = {x.attrib['referenceId']: x.text for x in
            ET.parse(design_path).iter() if 'referenceId' in x.attrib}

def parameter(name):
    value = r'\s*(?:"([^"]*)"|([-+]?\d+(?:\.\d+)?))'
    explicit = re.search(r'\.'+re.escape(name)+r'\s*\('+value+r'\s*\)', top)
    default = re.search(r'\bparameter\s+'+re.escape(name)+r'\s*='+value, wrapper)
    match = explicit or default
    if match is None:
        raise ValueError('Cannot resolve generated RTL parameter: '+name)
    return (match.group(1) if match.group(1) is not None else match.group(2),
            'top override' if explicit else 'wrapper default')

names = ['FIN', 'REFCLK_DIV', 'FBCLK_DIV', 'FRAC_ENABLE', 'SDM_FRAC',
         'FBKCLK', 'FEEDBK_MODE']
names += [f'CLKC{i}_{suffix}' for i in range(3)
          for suffix in ['ENABLE', 'DIV', 'CPHASE', 'FPHASE']]
effective = {name: dict(zip(['value', 'source'], parameter(name))) for name in names}
get = lambda name: effective[name]['value']
if get('FBKCLK') != 'VCO_PHASE0' or get('FEEDBK_MODE') != 'NOCOMP':
    raise ValueError('This audit requires the approved No compensation/VCO feedback profile')
frac = int(get('SDM_FRAC'))/(1 << 24) if get('FRAC_ENABLE') == 'ENABLE' else 0
vco = float(get('FIN'))/int(get('REFCLK_DIV'))*(int(get('FBCLK_DIV'))+frac)
actual = [vco/int(get(f'CLKC{i}_DIV')) for i in range(3)]
targets = [148.5, 742.5, 27.0] if args.profile=='display60' else [74.25, 371.25, 27.0]
issues = []
if metadata.get('VCO_FRACTIONAL_ENABLE_DISP') != '1':
    issues.append('Wizard VCO Fractional Enable is not selected')
if get('FRAC_ENABLE') != 'ENABLE':
    issues.append('Effective RTL FRAC_ENABLE is DISABLE')
for i, (got, target) in enumerate(zip(actual, targets)):
    if abs(got-target) > 0.000001:
        issues.append(f'CLK{i}: {got:.9f} MHz differs from {target} MHz')
    if get(f'CLKC{i}_ENABLE') != 'ENABLE':
        issues.append(f'CLK{i} is not enabled')
    if int(get(f'CLKC{i}_CPHASE')) != int(get(f'CLKC{i}_DIV'))-1 or int(get(f'CLKC{i}_FPHASE')) != 0:
        issues.append(f'CLK{i} does not use the approved generated zero-phase settings')
report = {
    'status': 'rejected' if issues else 'configuration_pass',
    'scope': 'Effective clock RTL over generated PLL wrapper, plus VCO wizard metadata; no runtime or hardware result',
    'clock_top': str(top_path), 'profile': args.profile,
    'ip_directory': str(ip),
    'wizard_vco_fractional_enable': metadata.get('VCO_FRACTIONAL_ENABLE_DISP'),
    'effective_rtl_parameters': effective,
    'vco_mhz': vco, 'actual_mhz': actual, 'target_mhz': targets,
    'issues': issues,
    'sha256': {str(p.relative_to(ip)) if p.is_relative_to(ip) else str(p): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in [top_path, wrapper_path, design_path]},
}
text = json.dumps(report, ensure_ascii=False, indent=2)+'\n'
if args.output:
    args.output.write_text(text, encoding='utf-8')
print(text, end='')
raise SystemExit(2 if issues else 0)
