"""Check a routed TD report against an explicit setup-margin objective."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys


def measure(path, expected_endpoint_groups=66):
    if not isinstance(expected_endpoint_groups, int) or expected_endpoint_groups < 2 or expected_endpoint_groups % 2:
        raise ValueError('Expected endpoint groups must be a positive even integer')
    raw = path.read_bytes()
    report = raw.decode(errors='replace')
    values = {}
    for key, pattern in {
        'setup_ns': r'SWNS: ([-+0-9.]+)ns, STNS:',
        'setup_tns_ns': r'SWNS: [-+0-9.]+ns, STNS: ([-+0-9.]+)ns',
        'hold_ns': r'HWNS: ([-+0-9.]+)ns, HTNS:',
        'hold_tns_ns': r'HWNS: [-+0-9.]+ns, HTNS: ([-+0-9.]+)ns',
        'period_ns': r'Period Check WNS: ([-+0-9.]+)ns',
    }.items():
        match = re.search(pattern, report)
        if not match:
            raise ValueError('Missing timing summary: '+key)
        values[key] = float(match[1])
    if 'Confidence          : Routed' not in report:
        raise ValueError('Require a routed report')
    endpoints = [int(x) for x in re.findall(r'(\d+) Viol Endpoints', report)]
    if len(endpoints) != expected_endpoint_groups:
        raise ValueError(f'Expected {expected_endpoint_groups} endpoint groups, found {len(endpoints)}')
    groups = re.findall(r'(?m)^Path Group\s*:\s*(.+)$', report)
    if len(groups)*2 != expected_endpoint_groups:
        raise ValueError('Incomplete path group statistics')
    values.update(report=str(path.resolve()), report_sha256=hashlib.sha256(raw).hexdigest(),
                  endpoint_groups=len(endpoints), violating_endpoints=sum(endpoints))
    return values


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('report', type=Path)
    parser.add_argument('--min-setup-ns', type=float, required=True)
    parser.add_argument('--expected-endpoint-groups', type=int, default=66,
                        help='Expected actual-project report shape; changes require review')
    args = parser.parse_args()
    if not 0 <= args.min_setup_ns <= 5:
        parser.error('Setup objective must be between 0 and 5 ns')
    if args.expected_endpoint_groups < 2 or args.expected_endpoint_groups % 2:
        parser.error('Expected endpoint groups must be a positive even integer')
    result = measure(args.report, args.expected_endpoint_groups)
    result['required_setup_ns'] = args.min_setup_ns
    result['accepted'] = (result['setup_ns'] >= args.min_setup_ns
                          and result['setup_tns_ns'] == result['hold_tns_ns'] == 0
                          and min(result['hold_ns'], result['period_ns']) >= 0
                          and result['violating_endpoints'] == 0)
    print(json.dumps(result, indent=2))
    sys.exit(0 if result['accepted'] else 1)
