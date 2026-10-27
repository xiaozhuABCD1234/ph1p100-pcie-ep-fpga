"""Retained ModelSim RGB8 gray checks; no hardware or synthesis claims.

python tools/rtl_checks/verify_gray.py --label green
python tools/rtl_checks/verify_gray.py --label rounding_negative --mutation rounding
The negative control must fail payload comparison. Only simulator copies mutate.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import random
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / 'fpga/csi2/src/img/rgb8_gray_stream.v'
TB = ROOT / 'fpga/csi2/tb/tb_rgb8_gray_stream.sv'
REFERENCE = ROOT / 'tools/image_preprocess/reference.py'
MODELSIM = Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def vectors():
    spec = importlib.util.spec_from_file_location('gray_public_reference', REFERENCE)
    reference = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reference)
    lines, pixels, expected = [], [], []
    counts = {'literal': 0, 'gray_levels': 0, 'corners': 0, 'random_full_rate': 0,
              'random_backpressure': 0, 'reset_pending': 0}

    def control(cmd, arg=0):
        lines.append(f'{cmd} 0 0 0 0 0 0 {arg}')

    def token(rgb, category, sof=0, last=0, literal=None):
        # Unbounded Python integers and integer division are the specification.
        r, g, b = rgb
        yy = (77 * r + 150 * g + 29 * b + 128) // 256
        if literal is not None:
            assert yy == literal
        pixels.append(tuple(rgb)); expected.append(yy)
        counts[category] += 1
        lines.append(f'0 {r} {g} {b} {sof} {last} {yy} 0')

    control(3, 1)
    for rgb, yy in [((0, 0, 0), 0), ((255, 255, 255), 255), ((255, 0, 0), 77),
                    ((0, 255, 0), 149), ((0, 0, 255), 29)]:
        token(rgb, 'literal', 1, 1, yy)
    for level in range(256):
        token((level,) * 3, 'gray_levels', int(level == 0), int(level == 255), level)
    for r in (0, 1, 127, 128, 254, 255):
        for g in (0, 1, 127, 128, 254, 255):
            for b in (0, 1, 127, 128, 254, 255):
                token((r, g, b), 'corners', int(r == b), int(g == b))
    rng = random.Random(0x20261015)
    for phase, category in [(1, 'random_full_rate'), (0, 'random_backpressure')]:
        control(3, phase)
        for index in range(4096):
            token(tuple(rng.randrange(256) for _ in range(3)), category,
                  int(index % 97 == 0), int(index % 31 == 30))
            if phase == 0 and index % 19 == 0:
                control(1, rng.randint(1, 25))
    # Drain, then fill an empty slot with sink blocked, hold, asynchronously reset.
    control(3, 1); control(1, 3); control(3, 2)
    token((128, 0, 0), 'reset_pending', 1, 1)
    control(1, 17); control(2); control(3, 1)
    token((255, 255, 255), 'reset_pending', 0, 1)
    control(1, 4)
    assert reference.rgb8_to_y8([pixels])[0] == expected
    return lines, counts


def run(args):
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%f')
    run_dir = ROOT.parent / 'deepseek_validation_runs' / f'gray_{args.label}_{stamp}'
    if not str(run_dir).isascii():
        raise RuntimeError('ModelSim run path must be ASCII')
    run_dir.mkdir(parents=True, exist_ok=False)
    sources = {}
    for source in (RTL, TB, Path(__file__).resolve(), REFERENCE):
        target = run_dir / source.name
        shutil.copyfile(source, target)
        sources[str(source.relative_to(ROOT))] = {'sha256_before': sha(source), 'copy_sha256': sha(target)}
    copied_rtl = run_dir / RTL.name
    if args.mutation == 'rounding':
        content = copied_rtl.read_text()
        assert content.count("17'd128;") == 1
        copied_rtl.write_text(content.replace("17'd128;", "17'd0;"))
    sources[str(RTL.relative_to(ROOT))]['simulation_sha256'] = sha(copied_rtl)
    lines, vector_counts = vectors()
    vector_path = run_dir / 'vectors.txt'
    vector_path.write_text('\n'.join(lines) + '\n', encoding='ascii')
    (run_dir / 'run.do').write_text(
        'onerror {quit -code 2}\nonbreak {}\nrun -all\n'
        'if {[examine -radix decimal /tb_rgb8_gray_stream/test_passed] == 1} {quit -code 0} else {quit -code 3}\n', encoding='ascii')
    commands = [['vlib.exe', 'work'], ['vlog.exe', '-sv', RTL.name, TB.name],
                ['vsim.exe', '-c', '-onfinish', 'stop', '-l', 'transcript.log',
                 'work.tb_rgb8_gray_stream', '+VECTORS=vectors.txt', '-do', 'run.do']]
    runs = []
    output = ''
    for index, command in enumerate(commands):
        full_command = [str(MODELSIM / command[0]), *command[1:]]
        process = subprocess.run(full_command, cwd=run_dir, capture_output=True, text=True, timeout=120)
        output = process.stdout + process.stderr
        log = run_dir / f'command_{index}.log'
        log.write_text(output)
        runs.append({'command': full_command, 'cwd': str(run_dir), 'exit_code': process.returncode,
                     'log': str(log), 'log_sha256': sha(log), 'log_bytes': log.stat().st_size})
        if index < 2 and (process.returncode or re.search(r'\*\* Error', output)):
            raise RuntimeError(f'Build failed: {log}')
    marker = re.search(r'PASS gray accepted=(\d+) emitted=(\d+) dropped=(\d+) stalls=(\d+) refills=(\d+) bubbles=(\d+) held=(\d+) resets=(\d+) cycles=(\d+)', output)
    coverage = dict(zip(('accepted', 'emitted', 'dropped', 'stalls', 'refills', 'bubbles', 'held', 'resets', 'cycles'), map(int, marker.groups()))) if marker else None
    simulator_errors = bool(re.search(r'\*\* (?:Error|Fatal)|Errors:\s*[1-9]', output))
    errors = simulator_errors or 'FAIL gray' in output
    green = runs[-1]['exit_code'] == 0 and bool(marker) and not errors and coverage['accepted'] == sum(vector_counts.values())
    expected_negative = (args.mutation == 'rounding' and runs[-1]['exit_code'] == 3
                         and not marker and not simulator_errors and 'FAIL gray' in output
                         and 'payload mismatch expected y=77 sof=1 last=1 got y=76' in output)
    for relative, source in sources.items():
        source['sha256_after'] = sha(ROOT / relative)
        source['unchanged_during_run'] = source['sha256_after'] == source['sha256_before']
        assert source['unchanged_during_run'], relative
    report = {'label': args.label, 'utc': stamp, 'root': str(ROOT), 'run_dir': str(run_dir),
              'mutation': args.mutation, 'sources': sources, 'commands': runs,
              'vector_counts': vector_counts, 'vector_sha256': sha(vector_path), 'coverage': coverage,
              'software_reference_crosscheck': True, 'passed': green, 'expected_negative_detected': expected_negative,
              'limitations': ['RTL simulation only; no synthesis, timing, resource or board evidence',
                              'Finite directed/random coverage, not exhaustive RGB or formal proof']}
    report_path = run_dir / 'report.json'
    report_path.write_text(json.dumps(report, indent=2))
    print(json.dumps({'report': str(report_path), 'passed': green, 'expected_negative_detected': expected_negative,
                      'vector_counts': vector_counts, 'coverage': coverage}, indent=2))
    return 0 if (green if args.mutation == 'none' else expected_negative) else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label', default='green')
    parser.add_argument('--mutation', choices=('none', 'rounding'), default='none')
    raise SystemExit(run(parser.parse_args()))
