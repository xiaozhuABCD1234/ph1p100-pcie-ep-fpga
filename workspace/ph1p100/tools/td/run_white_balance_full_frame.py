"""Two production-size frames using a verified frozen candidate and zlib CRCs."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
import time
import zlib

if not __debug__:
    raise RuntimeError('Run this verifier without Python -O.')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_manifest(project, manifest):
    for relative, digest in manifest.items():
        source = (project / relative).resolve()
        if not source.is_relative_to(project) or sha(source) != digest:
            raise ValueError(f'Candidate input mismatch: {relative}')


def selected_core_parameters(core):
    core = re.sub(r'//[^\n]*|/\*.*?\*/', '', core, flags=re.S)
    instances = re.findall(r'bayer565_capture\s*#\((.*?)\)\s+u_cam_preview\s*\((.*?)\);', core, re.S)
    if len(instances) != 1:
        raise ValueError('Expected exactly one selected u_cam_preview sampler instance')
    parameters = {}
    for name in ('SW', 'SH', 'BAYER_PHASE', 'WB_R_GAIN_Q10', 'WB_B_GAIN_Q10', 'WB_BLACK_LEVEL'):
        found = re.findall(r'\.' + name + r'\s*\(\s*(\d+)\s*\)', instances[0][0])
        if len(found) != 1:
            raise ValueError(f'Missing or ambiguous core parameter: {name}')
        parameters[name] = int(found[0])
    if (parameters['SW'], parameters['SH'], parameters['BAYER_PHASE']) != (960, 540, 3):
        raise ValueError('This fixture requires production 960x540 and received GBRG phase3')
    if not (0 <= parameters['WB_R_GAIN_Q10'] <= 4096 and 0 <= parameters['WB_B_GAIN_Q10'] <= 4096
            and 0 <= parameters['WB_BLACK_LEVEL'] <= 1023):
        raise ValueError('Unsupported gain or black-level configuration')

    def named_ports(text):
        pairs = re.findall(r'\.(\w+)\s*\(\s*(\w+)\s*\)', text)
        if len(dict(pairs)) != len(pairs):
            raise ValueError('Duplicate named port in selected instance')
        return dict(pairs)

    sampler_ports = named_ports(instances[0][1])
    required_sampler = {'clk': 'w_a_byte_clk', 'rst_n': 'w_a_rst_out',
                        'in_pixels': 'w_a_pixel', 'in_valid': 'w_a_pixel_valid',
                        'in_line': 'w_a_in_line', 'in_frame': 'w_a_in_frame',
                        'out_sof': 'cap_sof', 'out_valid': 'cap_valid',
                        'out_last': 'cap_last', 'out_data': 'cap_data'}
    for kind in ('end', 'good', 'abort'):
        required_sampler[f'frame_{kind}'] = f'raw_a_frame_{kind}'
        required_sampler[f'out_frame_{kind}'] = f'cap_frame_{kind}'
    for port, wire in required_sampler.items():
        if sampler_ports.get(port) != wire:
            raise ValueError(f'Actual sampler wiring mismatch: {port} -> {wire}')
    receivers = re.findall(r'mipi_csi2_rx_ph1p\s*#\((.*?)\)\s+u_csi_a\s*\((.*?)\);', core, re.S)
    if len(receivers) != 1:
        raise ValueError('Expected exactly one selected u_csi_a receiver instance')
    receiver_ports = named_ports(receivers[0][1])
    required_receiver = {'O_byte_clk': 'w_a_byte_clk', 'O_rst_out': 'w_a_rst_out'}
    for kind in ('end', 'good', 'abort'):
        required_receiver[f'O_frame_{kind}'] = f'raw_a_frame_{kind}'
    for port, wire in required_receiver.items():
        if receiver_ports.get(port) != wire:
            raise ValueError(f'Actual CSI receiver wiring mismatch: {port} -> {wire}')
    return parameters


def component(frame, x, y, channel):
    return (
        (x + 17*y + 173*frame) % 1024,
        (5*x + 7*y + 97*frame + 19) % 1024,
        (11*x + 13*y + 211*frame + 23 + ((x//7 + y//5 + frame) % 2)) % 1024,
        (3*x + 29*y + 509*frame + 7) % 1024,
    )[channel]


def balanced(value, gain, black):
    delta = value - black
    rounded = (abs(delta)*gain + 512) // 1024
    result = black + (rounded if delta >= 0 else -rounded)
    return min(1023, max(0, result))


def make_golden(parameters):
    records = []
    for frame in range(2):
        payload = bytearray()
        sums = [0, 0, 0, 0]
        coverage = [set() for _ in range(4)]
        for y in range(540):
            for x in range(960):
                r, gt, gb, b = (component(frame, x, y, c) for c in range(4))
                value = ((balanced(r, parameters['WB_R_GAIN_Q10'], parameters['WB_BLACK_LEVEL']) // 32) * 2048
                         + ((gt + gb) // 32) * 32
                         + balanced(b, parameters['WB_B_GAIN_Q10'], parameters['WB_BLACK_LEVEL']) // 32)
                payload.extend(value.to_bytes(2, 'little'))
                for c, raw in enumerate((r, gt, gb, b)):
                    coverage[c].add(raw)
                for c, raw in enumerate((gt, b, r, gb)):
                    sums[c] += raw
        if any(len(values) != 1024 for values in coverage):
            raise ValueError('Fixture does not cover every RAW10 value in each channel')
        records.append({'frame_id': frame+1, 'pixels': 518400, 'bytes': len(payload),
                        'crc32': f'{zlib.crc32(payload):08x}',
                        'payload_sha256': hashlib.sha256(payload).hexdigest(),
                        'raw_stats_abcd': sums, 'raw_levels_per_channel': [len(v) for v in coverage]})
    return records


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--timeout', type=int, default=900)
    args = parser.parse_args()
    project = args.project.resolve()
    if project.parent != Path('D:/TD/work/csi2/prj').resolve():
        raise ValueError('Expected a frozen candidate directly under D:/TD/work/csi2/prj')
    manifest_path = project / 'input_manifest.json'
    manifest = json.loads(manifest_path.read_bytes())
    if len(manifest) != 220:
        raise ValueError(f'Expected the 220-input pipeline candidate, got {len(manifest)}')
    verify_manifest(project, manifest)
    core_path = project / 'f9p_camera_display_core.v'
    core = core_path.read_text(encoding='utf-8-sig')
    parameters = selected_core_parameters(core)
    root = Path(__file__).resolve().parents[2]
    tb_source = root / 'fpga/csi2/tb/tb_bayer565_full_frame.sv'
    out = Path('D:/TD/work/csi2/_validation') / ('wb565_full_frame_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
    out.mkdir()
    sources = {'bayer565_capture.v': project / 'bayer565_capture.v',
               'rgb565_frame_pack_guarded.v': project / 'rgb565_frame_pack_guarded.v',
               'selected_core.v.snapshot': core_path,
               'input_manifest.json.snapshot': manifest_path,
               'tb_bayer565_full_frame.sv': tb_source,
               'runner.py.snapshot': Path(__file__).resolve()}
    for name, source in sources.items():
        (out / name).write_bytes(source.read_bytes())
    result = {'schema': 'wb565_full_frame_v1', 'project': str(project),
              'manifest_sha256': sha(manifest_path), 'manifest_entries_verified': len(manifest),
              'selected_core_sha256': sha(core_path), 'actual_core_parameters': parameters,
              'core_verdict_wiring_checked': True,
              'accepted': False, 'hardware_verified': False, 'commands': [],
              'scope': 'Two 960x540 sampler/guarded-packer frames, all 2160 received rows and 960 groups per row; every RGB565 sample and payload word, raw statistics, frame metadata and independent zlib CRC. No CSI parsing, DDR, HDMI or timing claim.'}
    start = time.monotonic()
    print('WB565_FULL_FRAME_RUN', out, flush=True)
    try:
        golden = make_golden(parameters)
        (out / 'golden.json').write_text(json.dumps(golden, indent=2) + '\n', encoding='ascii')
        (out / 'golden_crc.hex').write_text(''.join(record['crc32'] + '\n' for record in golden), encoding='ascii')
        result['golden'] = golden
        print('GOLDEN_CRC', golden[0]['crc32'], golden[1]['crc32'], flush=True)
        bin_path = Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
        commands = [
            ['vlib.exe', 'work'],
            ['vlog.exe', '-sv', 'bayer565_capture.v', 'rgb565_frame_pack_guarded.v', 'tb_bayer565_full_frame.sv'],
            ['vsim.exe', '-c', '-l', 'simulator.log',
             f'-gR_GAIN={parameters["WB_R_GAIN_Q10"]}', f'-gB_GAIN={parameters["WB_B_GAIN_Q10"]}',
             f'-gBLACK_LEVEL={parameters["WB_BLACK_LEVEL"]}', 'work.tb_bayer565_full_frame', '-do', 'run -all; quit -f'],
        ]
        for index, argv in enumerate(commands):
            command = [str(bin_path / argv[0]), *argv[1:]]
            log_path = out / f'{index}.log'
            with log_path.open('xb') as stream:
                run = subprocess.run(command, cwd=out, stdout=stream, stderr=subprocess.STDOUT, timeout=args.timeout)
            output = log_path.read_bytes().decode(errors='replace')
            errors = [int(v) for v in re.findall(r'Errors:\s*(\d+)', output)]
            warnings = [int(v) for v in re.findall(r'Warnings:\s*(\d+)', output)]
            result['commands'].append({'command': command, 'exit_code': run.returncode,
                                       'errors': errors, 'warnings': warnings, 'log': str(log_path)})
            print(output[-1800:], flush=True)
            if run.returncode != 0 or any(errors) or any(warnings) or re.search(r'\*\*\s*(?:Fatal|Error|Warning)', output):
                raise ValueError(f'Native tool failed or emitted diagnostics: {argv[0]}')
            if index in (1, 2) and (errors != [0] or warnings != [0]):
                raise ValueError(f'Missing clean native tool summary: {argv[0]}')
        pattern = (r'WB565_FULL_FRAME_PASS frames=2 width=960 height=540 outputs=1036800 payload_words=64800 '
                   r'starts=2 footers=2 stats_checks=2 raw_levels_per_channel_per_frame=1024 high_x=760320 '
                   r'high_y=545280 gaps=([1-9]\d*) crc0=' + golden[0]['crc32'] + ' crc1=' + golden[1]['crc32'])
        if len(re.findall(pattern, output, re.I)) != 1 or 'WB565_FULL_FRAME_FAIL' in output:
            raise ValueError('Missing exact full-frame PASS counts or CRCs')
        verify_manifest(project, manifest)
        for name, source in sources.items():
            if sha(out / name) != sha(source):
                raise ValueError(f'Input changed during run: {name}')
        result['accepted'] = True
        result['pass_line'] = re.search(pattern, output, re.I).group(0)
    except Exception as error:
        result['error'] = repr(error)
    finally:
        result['elapsed_seconds'] = round(time.monotonic() - start, 3)
        names = list(sources) + [name for name in ('golden.json', 'golden_crc.hex') if (out / name).exists()]
        result['inputs'] = {name: sha(out / name) for name in names}
        (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('WB565_FULL_FRAME_ACCEPTED' if result['accepted'] else 'WB565_FULL_FRAME_REJECTED', out, flush=True)
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    sys.exit(main())
