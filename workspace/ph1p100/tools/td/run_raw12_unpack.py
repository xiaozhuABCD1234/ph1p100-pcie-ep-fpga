"""Run isolated RAW12 regression; preserve every run and require a PASS marker."""
from pathlib import Path
import argparse
import datetime
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--red', action='store_true', help='Prove tests reject a no-op implementation')
parser.add_argument('--rtl', type=Path, help='Optional source to test instead of repository RTL')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')
out = Path(r'D:\TD\work\csi2\_validation\raw12') / (stamp + ('_red' if args.red else '_green'))
out.mkdir(parents=True, exist_ok=False)
rtl = args.rtl or repo / 'fpga/csi2/rtl/csi2_raw12_unpack.v'
if args.red:
    rtl = out / 'null_unpack.v'
    rtl.write_text('''module csi2_raw12_unpack(
input I_clock,I_reset_n,I_enable,input [31:0] I_data,input [2:0] I_nbytes,
input I_valid,I_sop,I_eop,output [47:0] O_pixels,output [2:0] O_pixel_count,
output O_packet_done,O_packet_error);
assign O_pixels=0; assign O_pixel_count=0;
assign O_packet_done=0; assign O_packet_error=0;
endmodule
''', encoding='ascii')
tb = repo / 'fpga/csi2/tests/tb_csi2_raw12_unpack.sv'
bin_dir = Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem')
commands = [
    [str(bin_dir/'vlib.exe'), 'work'],
    [str(bin_dir/'vlog.exe'), '-sv', str(rtl), str(tb)],
    [str(bin_dir/'vsim.exe'), '-c', 'work.tb_csi2_raw12_unpack',
     '-do', 'onerror {quit -code 1}; run -all; quit -f'],
]
logs = []
for command in commands:
    result = subprocess.run(command, cwd=out, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = result.stdout.decode('utf-8', errors='replace')
    logs.append(output)
    (out/'regression.log').write_text('\n'.join(logs), encoding='utf-8')
    print(output[-3000:])
    if result.returncode and not (args.red and command==commands[-1] and 'RAW12_FAIL' in output):
        raise SystemExit(result.returncode)
final = logs[-1]
print('EVIDENCE', out)
if args.red:
    if 'RAW12_FAIL flags' not in final or 'RAW12_PASS' in final:
        raise SystemExit('Negative control did not fail as expected')
    print('RAW12_RED_EXPECTED_FAILURE')
elif 'RAW12_PASS' not in final or 'RAW12_FAIL' in final:
    raise SystemExit('RAW12 regression failed')
