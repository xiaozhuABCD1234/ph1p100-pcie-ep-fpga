"""Snapshot and simulate the reference overlay; no FPGA build or download."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys

from rgb332_reference_support import attach_reference


BASE = Path('D:/TD/work/csi2/prj/camera_rgb332_20261013_161550')
MODELSIM = Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
VALIDATION = Path('D:/TD/work/csi2/_validation')
REPO = Path(__file__).resolve().parents[2]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Expected exactly one testbench anchor: ' + old)
    return text.replace(old, new)


def reference_ddr_tb(source):
    """Change only the display oracle; retain the real DDR fault workflows."""
    text = source.decode('utf-8')
    oracle = ''' localparam REFERENCE_ROWS=(SH>=64)?64:4;
 function[23:0] reference_color(input integer col);
  case((col*8)/(SW*2))
   0:reference_color=24'hffffff;1:reference_color=24'hff0000;
   2:reference_color=24'h00ff00;3:reference_color=24'h0000ff;
   4:reference_color=24'h00ffff;5:reference_color=24'hff00ff;
   6:reference_color=24'hffff00;default:reference_color=24'h000000;
  endcase
 endfunction
 function[23:0] display_expected(input[7:0] code,input integer col,row);
  integer r,g,b;
  begin
   r=(((code>>5)&7)*255+3)/7;g=(((code>>2)&7)*255+3)/7;b=(code&3)*85;
   display_expected=(row<REFERENCE_ROWS)?reference_color(col):{r[7:0],g[7:0],b[7:0]};
  end
 endfunction
'''
    text = replace_once(text, ' task show_frame(', oracle + ' task show_frame(')
    text = replace_once(
        text, 'if(fault==0&&rgb!=={expected,expected,expected})',
        'if((fault==0||b<REFERENCE_ROWS)&&rgb!==display_expected(expected,a,b))')
    text = replace_once(
        text, 'if(fault&&underflow_frames!=0&&rgb!==0)',
        'if(fault&&b>=REFERENCE_ROWS&&underflow_frames!=0&&rgb!==0)')
    text = replace_once(
        text, 'repeat(64)begin tick(0,0,1);if(rgb!==0)fail("startup black");end',
        'for(integer startup_x=0;startup_x<64;startup_x++)begin '
        'tick(0,0,1);if(rgb!==reference_color(startup_x))fail("startup reference");end')
    text = replace_once(
        text, 'if({out_vs,out_hs,out_de}!=={v,h,d})fail("video control alignment");',
        'if({out_vs,out_hs,out_de}!=={v,h,d})fail("video control alignment");\n'
        '  if(!d&&rgb!==0)fail("reference blank black");')
    text = replace_once(
        text, '// Startup without a complete frame must remain black, without a false error.',
        '// Startup shows reference bars without a complete camera frame or false underflow.')
    return text.encode('utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--test', choices=['overlay', 'ddr'], default='overlay')
    parser.add_argument('--baseline', action='store_true')
    parser.add_argument('--production', action='store_true')
    args = parser.parse_args()
    if args.baseline and args.test != 'overlay':
        parser.error('--baseline is an overlay-only functional negative control')
    if args.production and args.test != 'ddr':
        parser.error('--production selects the full 960x540 DDR payload')

    out = VALIDATION / ('rgb332_reference_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    result = {'test': args.test, 'baseline': args.baseline, 'production': args.production,
              'accepted': False, 'commands': [], 'source_inputs': {}, 'inputs': {},
              'script_hashes': {}, 'snapshot_transforms': []}
    files = []

    def snapshot(source, name=None):
        data = source.read_bytes()
        target = name or source.name
        if (out / target).exists():
            raise ValueError('Duplicate snapshot filename: ' + target)
        (out / target).write_bytes(data)
        result['source_inputs'][target] = {'path': str(source), 'sha256': sha(data)}
        return data

    try:
        for source in [Path(__file__).resolve(), REPO / 'tools/td/rgb332_reference_support.py']:
            data = snapshot(source)
            result['script_hashes'][source.name] = sha(data)

        overlay = REPO / 'fpga/csi2/src/mem/rgb332_reference_overlay.v'
        if args.test == 'overlay':
            top = 'tb_rgb332_reference_overlay'
            snapshot(REPO / 'fpga/csi2/tb' / (top + '.sv'))
            if args.baseline:
                result['product_implementation_present'] = overlay.is_file()
                if overlay.is_file():
                    original = snapshot(overlay)
                    (out / (overlay.name + '.original')).write_bytes(original)
                else:
                    result['snapshot_transforms'].append('Constructed passthrough stub; no product implementation yet.')
                stub = '''`timescale 1ns/1ps
module rgb332_reference_overlay #(parameter SW=960,SH=540,REFERENCE_ROWS=64)(
 input pclk,rst_n,vs,de,input[23:0] camera_rgb,output[23:0] rgb);
 assign rgb=(!rst_n||!de)?24'd0:camera_rgb;
endmodule
'''
                (out / overlay.name).write_bytes(stub.encode('ascii'))
                result['snapshot_transforms'].append('Same-interface active-video camera_rgb passthrough stub with reset/blank black; require RGB332_REFERENCE_FAIL pixel, zero tool errors and zero exit codes.')
            else:
                snapshot(overlay)
            files = [top + '.sv', overlay.name]
            prefix = 'RGB332_REFERENCE'
        else:
            manifest_bytes = (BASE / 'input_manifest.json').read_bytes()
            manifest = json.loads(manifest_bytes)
            if len(manifest) != 193:
                raise ValueError('Frozen RGB332 candidate must have 193 inputs')
            base_root = BASE.resolve()
            for name, digest in manifest.items():
                source = (BASE / name).resolve()
                if not source.is_relative_to(base_root) or sha(source.read_bytes()) != digest:
                    raise ValueError('Frozen candidate input mismatch: ' + name)
            snapshot(BASE / 'input_manifest.json', 'base_input_manifest.json')
            result['base'] = str(BASE)
            result['base_manifest_sha256'] = sha(manifest_bytes)
            top = 'tb_ddr_display'
            original_tb = snapshot(REPO / 'fpga/csi2/tb' / (top + '.sv'))
            (out / (top + '.sv.original')).write_bytes(original_tb)
            (out / (top + '.sv')).write_bytes(reference_ddr_tb(original_tb))
            dependencies = ['capture_async_fifo.v', 'gray_frame_pack_guarded.v',
                            'ddr_frame_store.v', 'ddr_display_read.v',
                            'rgb332_display_pixels.v', 'camera_ddr_display_guarded.v']
            for name in dependencies:
                snapshot(BASE / name)
            guarded = out / 'camera_ddr_display_guarded.v'
            original_guarded = guarded.read_bytes()
            (out / (guarded.name + '.original')).write_bytes(original_guarded)
            # The candidate preparer uses this exact shared byte transformation.
            guarded.write_bytes(attach_reference(original_guarded))
            snapshot(overlay)
            files = [top + '.sv', *dependencies, overlay.name]
            prefix = 'DDR_DISPLAY'
            result['snapshot_transforms'].extend([
                'attach_reference(bytes) on frozen 161550 guarded module; preserve original pixel consumer and DDR logic.',
                'Independent arithmetic RGB332 oracle below reference rows; fixed white/red/green/blue/cyan/magenta/yellow/black palette above.',
                'Startup reference oracle, reference checks during fault frames, black underflow only below reference rows, and blanking black checks; original control alignment and #0.1 sampling retained.'])
            result['geometry'] = {'sw': 960 if args.production else 64,
                                  'sh': 540 if args.production else 16,
                                  'reference_rows': 64 if args.production else 4}

        result['inputs'] = {name: sha((out / name).read_bytes()) for name in files}
        result['compile_files'] = files
        params = ['-gSW=960', '-gSH=540', '-gPRODUCTION=1'] if args.production else []
        commands = [['vlib.exe', 'work'],
                    ['vlog.exe', '-sv', *(['+define+GUARDED'] if args.test == 'ddr' else []), *files],
                    ['vsim.exe', '-c', *params, 'work.' + top, '-do', 'run -all; quit -f']]
        last_log = ''
        for index, command in enumerate(commands):
            actual = [str(MODELSIM / command[0]), *command[1:]]
            entry = {'command': actual, 'cwd': str(out), 'log': f'{index}.log', 'returncode': None}
            result['commands'].append(entry)
            try:
                completed = subprocess.run(actual, cwd=out, stdout=subprocess.PIPE,
                                           stderr=subprocess.STDOUT, timeout=300)
                output = completed.stdout
                entry['returncode'] = completed.returncode
            except subprocess.TimeoutExpired as error:
                output = error.stdout or b''
                (out / entry['log']).write_bytes(output)
                entry['timed_out'] = True
                raise RuntimeError('ModelSim timeout: ' + command[0]) from error
            (out / entry['log']).write_bytes(output)
            last_log = output.decode('utf-8', errors='replace')
            print(last_log[-2200:])
            errors = [int(n) for n in re.findall(r'\bErrors\s*:\s*(\d+)', last_log)]
            entry['reported_errors'] = errors
            expected_failure = (args.baseline and index == 2
                                and bool(re.search(r'\bRGB332_REFERENCE_FAIL pixel\b', last_log))
                                and not re.search(r'\bRGB332_REFERENCE_PASS\b', last_log))
            entry['expected_functional_failure'] = bool(expected_failure)
            entry['tool_error'] = bool(re.search(r'\*\*\s*(?:Error|Fatal)\b', last_log))
            if completed.returncode or entry['tool_error'] or any(errors):
                raise RuntimeError('ModelSim command failed: ' + command[0])
            if index == 1 and not errors:
                raise RuntimeError('Missing ModelSim compile Errors: 0 summary')

        passed = bool(re.search(r'\b' + prefix + r'_PASS\b', last_log))
        failed = bool(re.search(r'\b' + prefix + r'_FAIL\b', last_log))
        result['accepted'] = (bool(re.search(r'\bRGB332_REFERENCE_FAIL pixel\b', last_log))
                              and not passed) if args.baseline else (passed and not failed)
        result['expected_marker'] = prefix + ('_FAIL pixel' if args.baseline else '_PASS')
        if not result['accepted']:
            result['error'] = 'Expected functional marker missing or conflicting'
    except Exception as error:
        result['error'] = f'{type(error).__name__}: {error}'
    finally:
        # Retain actual transformed inputs even when compilation or simulation fails.
        result['inputs'] = {name: sha((out / name).read_bytes()) for name in files if (out / name).is_file()}
        (out / 'result.json').write_bytes((json.dumps(result, indent=2) + '\n').encode('utf-8'))
    print('RGB332_REFERENCE_TEST_ACCEPTED' if result['accepted'] else 'RGB332_REFERENCE_TEST_FAILED', out)
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    sys.exit(main())
