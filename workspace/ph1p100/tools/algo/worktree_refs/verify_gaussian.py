"""Retained ModelSim checks for the bounded three-row Gaussian prototype.

python tools/rtl_checks/verify_gaussian.py --label green
python tools/rtl_checks/verify_gaussian.py --label small --max-width 7
python tools/rtl_checks/verify_gaussian.py --label rounding_negative --mutation rounding
Only frozen simulator copies are mutated; native nonzero exit and the named
payload assertion are required for the negative control. No hardware claims.
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
import sys

# Loading the public reference must not write cache files outside owned paths.
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / 'fpga/csi2/src/img/gray8_gaussian3x3_frame.v'
TB = ROOT / 'fpga/csi2/tb/tb_gray8_gaussian3x3_frame.sv'
REFERENCE = ROOT / 'tools/image_preprocess/reference.py'
MODELSIM = Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def oracle(frame):
    """Separable integer oracle: replicate by padding, round once at the end.

    Deliberately independent of the public reference's nested kernel loops.
    Horizontal sums remain unrounded before the vertical combination.
    """
    horizontal = []
    for row in frame:
        padded = [row[0], *row, row[-1]]
        horizontal.append([a + 2*b + c for a, b, c in
                           zip(padded, padded[1:], padded[2:])])
    rows = [horizontal[0], *horizontal, horizontal[-1]]
    return [[(a + 2*b + c + 8) // 16 for a, b, c in zip(top, mid, bot)]
            for top, mid, bot in zip(rows, rows[1:], rows[2:])]


def vectors(max_width):
    spec = importlib.util.spec_from_file_location('gaussian_public_reference', REFERENCE)
    reference = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reference)
    lines, cases = [], []
    rng = random.Random(0x20261015)

    def frame(image, category, *, literal=None, traffic=0, kind=0, abort_at=0):
        h, w = len(image), len(image[0])
        assert 1 <= w <= max_width and h <= 2160
        result = oracle(image)
        assert result == reference.gaussian3x3(image), category
        if literal is not None:
            assert result == literal, category
        lines.append(f'{kind} {w} {h} {traffic} {abort_at} {w*h}')
        lines.extend(f'{pixel} {expected}' for row, out in zip(image, result)
                     for pixel, expected in zip(row, out))
        cases.append({'category': category, 'kind': kind, 'width': w, 'height': h,
                      'pixels': w*h, 'traffic': traffic, 'abort_at': abort_at,
                      'literal_checked': literal is not None})

    for value in (0, 1, 17, 127, 128, 254, 255):
        frame([[value]], 'literal_1x1', literal=[[value]], traffic=1)
    frame([[0], [16], [0]], 'literal_1xN', literal=[[4], [8], [4]])
    frame([[0, 16, 0]], 'literal_Nx1', literal=[[4, 8, 4]])
    frame([[0, 16], [32, 48]], 'literal_2x2', literal=[[12, 20], [28, 36]])
    # Half-up threshold at the center: (8+8)//16 == 1 (no earlier rounding).
    frame([[0, 0, 0], [0, 2, 0], [0, 0, 0]], 'literal_rounding',
          literal=[[0, 0, 0], [0, 1, 0], [0, 0, 0]])
    width = min(7, max_width)
    for value in (0, 1, 127, 255):
        frame([[value]*width for _ in range(5)], 'constant', traffic=1)
    for y, x in ((0, 0), (0, width-1), (4, 0), (4, width-1), (2, width//2)):
        image = [[0]*width for _ in range(5)]
        image[y][x] = 255
        frame(image, 'impulse')
    frame([[(x*19+y*37) % 256 for x in range(width)] for y in range(9)], 'ramp_odd')
    frame([[rng.randrange(256)] for _ in range(2160)], 'height2160')
    frame([[rng.randrange(256) for _ in range(max_width)] for _ in range(3)], 'max_width_3rows')
    for index in range(32):
        w, h = rng.randint(1, min(max_width, 31)), rng.randint(1, 17)
        frame([[rng.randrange(256) for _ in range(w)] for _ in range(h)],
              'random_full_rate' if index % 2 else 'random_bubbles_stalls', traffic=index % 2)
    # Prime all banks, abort both a partially filled new row and a held output,
    # then use a distinct tiny frame to expose stale-bank or reset-state reuse.
    frame([[rng.randrange(256) for _ in range(width)] for _ in range(5)], 'reset_collect', kind=2, abort_at=2)
    frame([[255, 0], [0, 255]], 'after_collect_reset')
    frame([[(x*31+y*53) % 256 for x in range(width)] for y in range(5)], 'reset_output', kind=3, abort_at=2)
    frame([[5]], 'after_output_reset', literal=[[5]])
    invalids = {(0, 1), (1, 0), (0, 0), (max_width+1, 1), (3840, 1),
                (3841, 1), (4095, 1), (1, 2161), (1, 4095)}
    for w, h in sorted(invalids):
        if w <= 4095 and (w == 0 or w > max_width or h == 0 or h > 2160):
            lines.append(f'1 {w} {h} 0 0 0')
            cases.append({'category': 'invalid', 'kind': 1, 'width': w, 'height': h, 'pixels': 0})
    return lines, cases


RED_STUB = '''module gray8_gaussian3x3_frame #(parameter MAX_WIDTH=1920)(
input clk,rst_n,cfg_valid, input [11:0] cfg_width,cfg_height,
output cfg_ready,input s_valid,input [7:0] s_data,output s_ready,
output m_valid,input m_ready,output [7:0] m_data,output m_sof,m_eol,m_eof,
output done_valid,input done_ready,output done_error);
reg busy; always @(posedge clk or negedge rst_n)
if (!rst_n) busy<=0; else if(cfg_valid && cfg_ready) busy<=1; else if(done_ready) busy<=0;
assign cfg_ready=rst_n && !busy; assign s_ready=0; assign m_valid=0;
assign m_data=0; assign m_sof=0; assign m_eol=0; assign m_eof=0;
assign done_valid=rst_n && busy; assign done_error=0; endmodule
'''


def run(args):
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%f')
    run_dir = ROOT.parent / 'parallel_round2_runs' / f'gaussian-{args.label}-{stamp}'
    if not str(run_dir).isascii():
        raise RuntimeError('ModelSim database path must be ASCII')
    run_dir.mkdir(parents=True, exist_ok=False)
    sources = {}
    for source in (RTL, TB, Path(__file__).resolve(), REFERENCE):
        if args.red_stub and source == RTL and not source.exists():
            continue
        target = run_dir / source.name
        shutil.copyfile(source, target)
        sources[str(source.relative_to(ROOT))] = {'sha256_before': sha(source), 'copy_sha256': sha(target)}
    copied_rtl = run_dir / RTL.name
    if args.red_stub:
        copied_rtl.write_text(RED_STUB, encoding='ascii')
    if args.mutation == 'rounding':
        content = copied_rtl.read_text(encoding='utf-8')
        assert content.count("12'd8;") == 1
        copied_rtl.write_text(content.replace("12'd8;", "12'd0;"), encoding='utf-8')
    simulation_sha = sha(copied_rtl)
    lines, cases = vectors(args.max_width)
    vector_path = run_dir / 'vectors.txt'
    vector_path.write_text('\n'.join(lines)+'\n', encoding='ascii')
    (run_dir / 'run.do').write_text(
        'onerror {quit -code 2}\nonbreak {}\nrun -all\n'
        'if {[examine -radix decimal /tb_gray8_gaussian3x3_frame/test_passed] == 1} {quit -code 0} else {quit -code 3}\n', encoding='ascii')
    commands = [['vlib.exe', 'work'], ['vlog.exe', '-sv', RTL.name, TB.name],
                ['vsim.exe', '-c', '-onfinish', 'stop', '-l', 'transcript.log',
                 f'-gMAX_WIDTH={args.max_width}', 'work.tb_gray8_gaussian3x3_frame',
                 '+VECTORS=vectors.txt', '-do', 'run.do']]
    runs, output = [], ''
    for index, command in enumerate(commands):
        full_command = [str(MODELSIM/command[0]), *command[1:]]
        process = subprocess.run(full_command, cwd=run_dir, capture_output=True, text=True, timeout=120)
        output = process.stdout + process.stderr
        log = run_dir / f'command_{index}.log'
        log.write_text(output, encoding='utf-8')
        runs.append({'command': full_command, 'cwd': str(run_dir), 'exit_code': process.returncode,
                     'log': str(log), 'log_sha256': sha(log), 'log_bytes': log.stat().st_size})
        if index < 2 and (process.returncode or re.search(r'\*\* Error', output)):
            break
    names = ('frames','invalid','accepted','emitted','complete_pixels','held','stalls','bubbles',
             'ack_stalls','reset_collect','reset_output','cycles')
    marker = re.search('PASS gaussian '+ ' '.join(name+r'=(\d+)' for name in names), output)
    coverage = dict(zip(names,map(int,marker.groups()))) if marker else None
    frame_names = ('kind','width','height','accepted','emitted','sof','eol','eof','reset')
    frame_pattern = 'FRAME gaussian '+ ' '.join(name+r'=(\d+)' for name in frame_names)
    frame_results = [dict(zip(frame_names,map(int,match)))
                     for match in re.findall(frame_pattern,output)]
    frame_counts_checked = len(frame_results) == len(cases)
    for case, actual in zip(cases,frame_results):
        expected = {key:case[key] for key in ('kind','width','height')}
        kind, count = case['kind'],case['pixels']
        if kind == 0:
            expected.update(accepted=count,emitted=count,sof=1,eol=case['height'],eof=1,reset=0)
        elif kind == 1:
            expected.update(accepted=0,emitted=0,sof=0,eol=0,eof=0,reset=0)
        elif kind == 2:
            expected.update(accepted=case['abort_at'],emitted=0,sof=0,eol=0,eof=0,reset=1)
        else:
            expected.update(accepted=2*case['width'],emitted=case['abort_at'],
                            sof=1,eol=case['abort_at']//case['width'],eof=0,reset=1)
        frame_counts_checked &= actual == expected
    errors = bool(re.search(r'\*\* (?:Error|Fatal)|Errors:\s*[1-9]',output))
    complete_pixels = sum(case['pixels'] for case in cases if case['kind'] == 0)
    green = bool(len(runs) == 3 and runs[-1]['exit_code'] == 0 and marker and not errors
                 and 'FAIL gaussian' not in output and coverage['frames'] == len(cases)
                 and coverage['complete_pixels'] == complete_pixels and frame_counts_checked)
    negative = bool(args.mutation == 'rounding' and len(runs) == 3 and runs[-1]['exit_code'] == 3
                    and not marker and not errors and 'payload mismatch index=4 expected=1 got=0' in output)
    red = bool(args.red_stub and len(runs) == 3 and runs[-1]['exit_code'] == 3
               and not marker and not errors and 'premature completion' in output)
    for relative, source in sources.items():
        source['sha256_after'] = sha(ROOT/relative)
        source['unchanged_during_run'] = source['sha256_before'] == source['sha256_after']
        assert source['unchanged_during_run'], relative
    report = {'label': args.label, 'utc': stamp, 'root': str(ROOT), 'run_dir': str(run_dir),
              'max_width': args.max_width, 'mutation': args.mutation, 'red_stub': args.red_stub,
              'sources': sources, 'simulation_rtl_sha256': simulation_sha, 'commands': runs,
              'cases': cases, 'case_count': len(cases), 'expected_complete_pixels': complete_pixels,
              'frame_results': frame_results, 'frame_counts_checked': frame_counts_checked,
              'vector_sha256': sha(vector_path), 'software_reference_crosscheck': True,
              'literal_frame_count': sum(case.get('literal_checked', False) for case in cases),
              'coverage': coverage, 'passed': green, 'expected_negative_detected': negative,
              'expected_red_detected': red,
              'limitations': ['Finite simulation coverage; no formal proof',
                              'Asynchronous multiple row reads, phased input service; no synthesis, RAM inference, timing, resources or hardware evidence']}
    report_path = run_dir/'report.json'
    report_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({'report':str(report_path),'passed':green,'expected_negative_detected':negative,
                      'expected_red_detected':red,'case_count':len(cases),'coverage':coverage},indent=2))
    return 0 if (red if args.red_stub else negative if args.mutation != 'none' else green) else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--label',default='green')
    parser.add_argument('--mutation',choices=('none','rounding'),default='none')
    parser.add_argument('--max-width',type=int,default=1920,choices=range(3,3841))
    parser.add_argument('--red-stub',action='store_true')
    raise SystemExit(run(parser.parse_args()))
