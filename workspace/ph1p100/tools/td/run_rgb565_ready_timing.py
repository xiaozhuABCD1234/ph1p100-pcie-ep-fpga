"""Run DDR-ready timing regressions against one hash-verified frozen project."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import time
import zlib

ROOT = Path(__file__).resolve().parents[2]
BIN = Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
RTL = ('capture_async_fifo.v', 'ddr_frame_store.v', 'rgb565_frame_pack_guarded.v',
       'rgb565_display_read.v', 'rgb565_display_pixels.v', 'camera_rgb565_display_guarded.v')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--project', required=True, type=Path)
    parser.add_argument('--suite', choices=('ready', 'ddr'), default='ready')
    parser.add_argument('--production', action='store_true')
    parser.add_argument('--fault', choices=('none', 'ready-reset-bypass'), default='none')
    parser.add_argument('--timeout', type=int, default=900)
    args = parser.parse_args()
    if args.production and args.suite != 'ddr':
        parser.error('Production geometry is the existing DDR regression only')
    if args.fault != 'none' and args.suite != 'ready':
        parser.error('The ready-reset negative control is for the ready suite')
    project = args.project.resolve()
    if project.parent != Path('D:/TD/work/csi2/prj').resolve():
        raise ValueError('Expected a frozen project directly under D:/TD/work/csi2/prj')
    manifest_path = project / 'input_manifest.json'
    manifest = json.loads(manifest_path.read_bytes())
    for relative, digest in manifest.items():
        source = (project / relative).resolve()
        if not source.is_relative_to(project) or sha(source) != digest:
            raise ValueError(f'Frozen project input mismatch: {relative}')
    out = Path(tempfile.mkdtemp(prefix='rgb565_ready_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_'),
                                dir='D:/TD/work/csi2/_validation'))
    result = {'accepted': False, 'hardware_verified': False, 'project': str(project),
              'manifest_sha256': sha(manifest_path), 'manifest_inputs': len(manifest),
              'suite': args.suite, 'production': args.production, 'fault': args.fault,
              'sources': {}, 'commands': [], 'scope': 'Real frozen frame pack/FIFOs/store/reader/pixels; DDR controller modeled with response-flush contract'}
    top = 'tb_rgb565_ready_timing' if args.suite == 'ready' else 'tb_rgb565_ddr_display'
    files = [top + '.sv', *RTL]
    try:
        (out / 'runner.py.snapshot').write_bytes(Path(__file__).read_bytes())
        for name in files:
            source = ROOT / 'fpga/csi2/tb' / name if name.endswith('.sv') else project / name
            (out / name).write_bytes(source.read_bytes())
            result['sources'][name] = {'path': str(source), 'sha256': sha(source)}
        if args.fault == 'ready-reset-bypass':
            target = out / 'camera_rgb565_display_guarded.v'
            text = target.read_bytes().decode()
            old = 'wire run_rst_n=rst_n&&ddr_ready;'
            if text.count(old) != 1:
                raise ValueError('Expected exactly one common ready/reset expression')
            target.write_bytes(text.replace(old, 'wire run_rst_n=rst_n;').encode())
            result['control'] = 'Only snapshot mutated: raw ready removed from common asynchronous reset; original frozen inputs untouched'
        pixels = 960*540 if args.production else 64*16
        crc = []
        for frame_id in range(1, 7):
            raw = bytearray()
            for offset in range(pixels):
                value = ((frame_id*7919 + offset*131 + (offset >> 8)*997 + (offset >> 16)*1237) ^ 0xa639) & 65535
                raw.extend(value.to_bytes(2, 'little'))
            crc.append(zlib.crc32(raw))
        (out / 'golden_crc.txt').write_bytes(('\n'.join(f'{v:08x}' for v in crc) + '\n').encode())
        result['golden'] = {'method': 'Python zlib.crc32 of independent RGB565 fixture, little endian',
                            'values': crc, 'sha256': sha(out / 'golden_crc.txt')}
        params = ['-gSW=960', '-gSH=540', '-gPRODUCTION=1'] if args.production else []
        commands = [['vlib.exe', 'work'], ['vlog.exe', '-sv', '+define+GUARDED', *files],
                    ['vsim.exe', '-c', *params, 'work.' + top, '-do', 'run -all; quit -f']]
        for number, command in enumerate(commands):
            actual = [str(BIN / command[0]), *command[1:]]
            started = time.monotonic()
            process = subprocess.run(actual, cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=args.timeout)
            log = out / f'{number}.log'
            log.write_bytes(process.stdout)
            text = process.stdout.decode(errors='replace')
            print(text[-2400:])
            errors = [int(v) for v in re.findall(r'\bErrors:\s*(\d+)', text)]
            warnings = [int(v) for v in re.findall(r'\bWarnings:\s*(\d+)', text)]
            result['commands'].append({'command': actual, 'exit_code': process.returncode,
                                       'elapsed_seconds': round(time.monotonic()-started, 3),
                                       'errors': errors, 'warnings': warnings, 'log': log.name, 'sha256': sha(log)})
            if process.returncode or re.search(r'\*\*\s*(?:Error|Fatal|Warning)\b', text) or any(errors) or any(warnings):
                raise RuntimeError('Native simulation command failed or emitted a warning/error')
            if number == 1 and errors != [0]:
                raise RuntimeError('Missing native zero-error compilation summary')
        prefix = 'RGB565_READY' if args.suite == 'ready' else 'RGB565_DDR'
        result['simulation_markers'] = re.findall(prefix + r'_(?:PASS|FAIL)[^\r\n]*', text)
        if args.fault == 'ready-reset-bypass':
            result['accepted'] = len(result['simulation_markers']) == 1 and result['simulation_markers'][0].startswith('RGB565_READY_FAIL ready pulse must flush prior epoch')
        else:
            result['accepted'] = len(result['simulation_markers']) == 1 and result['simulation_markers'][0].startswith(prefix + '_PASS ')
        # Catch source drift that occurred while a long production regression ran.
        for relative, digest in manifest.items():
            if sha(project / relative) != digest:
                raise RuntimeError(f'Frozen source drift during simulation: {relative}')
    except Exception as error:
        result['accepted'] = False
        result['error'] = repr(error)
    finally:
        result['executed_inputs'] = {name: sha(out / name) for name in files if (out / name).exists()}
        result['runner_sha256'] = sha(out / 'runner.py.snapshot') if (out / 'runner.py.snapshot').exists() else None
        (out / 'result.json').write_bytes((json.dumps(result, indent=2) + '\n').encode())
    print('RGB565_READY_TEST_ACCEPTED' if result['accepted'] else 'RGB565_READY_TEST_FAILED', out)
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    sys.exit(main())
