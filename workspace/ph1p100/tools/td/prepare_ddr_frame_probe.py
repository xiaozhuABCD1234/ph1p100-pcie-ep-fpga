"""Snapshot the board DDR example and prepare a fresh standalone frame probe.

Never downloads hardware, changes generated IP, or overwrites a previous run.
"""
from pathlib import Path
import datetime
import hashlib
import json
import shutil

repo = Path(__file__).resolve().parents[2]
reference = Path(r'D:/TD/work/peripheral/09_ddr3_ddrmc_cal_x32_1066mbps/prj_src')
snapshot = repo / 'fpga/csi2/prj/ddr_frame_probe/vendor'
out = Path(r'D:/TD/work/csi2/prj') / ('ddr_frame_probe_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
manifest = {}
for source in sorted(reference.rglob('*')):
    if not source.is_file():
        continue
    relative = source.relative_to(reference)
    target = snapshot / relative
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if target.exists():
        assert hashlib.sha256(target.read_bytes()).hexdigest() == digest, target
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    manifest[relative.as_posix()] = digest
snapshot.parent.mkdir(parents=True, exist_ok=True)
(snapshot.parent / 'vendor_manifest.json').write_text(json.dumps({
    'reference': str(reference), 'files': manifest,
    'note': 'Unmodified input snapshot. Directory name does not establish DDR rate.'
}, indent=2) + '\n', encoding='utf-8')
out.mkdir(parents=True, exist_ok=False)
shutil.copytree(snapshot, out / 'vendor')

# Derived wrapper keeps the original MCU/APB initialization and exact DDR pin ports.
top = (snapshot / 'rtl/top/example_top.v').read_text()
rom = (out / 'vendor/rtl/usr_mcu_srcs/mcu_rom/mcu_rom.txt').resolve()
assert rom.is_file(), rom
top = top.replace('"../mcu_rom/mcu_rom.txt"', '"' + rom.as_posix() + '"')
top = top.replace('module example_top#', 'module ddr_frame_probe_top#')
top = top.replace('ddrmc_test_top #(', 'ddrmc_frame_top #(')
assert 'module ddr_frame_probe_top#' in top and str(rom.as_posix()) in top
(out / 'ddr_frame_probe_top.v').write_text(
    '// Derived from vendor example_top.v; only top/child names and ROM path changed.\n' + top,
    encoding='ascii')

sources = []
for filename in ['ddr_frame_store.v', 'ddr_frame_probe.v', 'ddrmc_frame_top.v']:
    source = repo / 'fpga/csi2/src/mem' / filename
    shutil.copyfile(source, out / filename)
    sources.append('./' + filename)
sources.append('./ddr_frame_probe_top.v')
sources.extend('./' + x.relative_to(out).as_posix()
               for x in sorted((out / 'vendor/rtl/usr_mcu_srcs').rglob('*.v')))
sources.append('./vendor/ip/ddrmc_x32/ddrmc_x32.xml')
tcl = '''if {[catch {
import_device ph1_100p.db -package PH1P100SBG484 -speed 3
create_project ddr_frame_probe ./ -family ph1 -device PH1P100SBG484 -speed -3
FILES
add_files ./vendor/adc/ap115v2.adc
add_files ./vendor/sdc/ap115v2.sdc
top_module ddr_frame_probe_top
launch_runs syn_1
wait_run syn_1 -quiet
launch_runs -step route phy_1
wait_run phy_1 -quiet
# Reload the exported routed checkpoint explicitly. The project manager can
# reject open_run after a completed child run; use the actual exported DB.
import_db ./ddr_frame_probe_Runs/phy_1/ddr_frame_probe_pr.db
update_timing -mode final
report_timing_summary -file ./probe_timing.rpt
report_timing_ignored -file ./probe_ignored.rpt -ep_num 50
report_abnormal_timing_target -file ./probe_abnormal.rpt
report_area -file ./probe.area
close_project
puts "DDR_FRAME_ROUTE_RETURNED_CHECK_REPORTS"
} msg]} { puts stderr "DDR_FRAME_BUILD_ERROR: $msg"; exit 1 }
exit 0
'''.replace('FILES', '\n'.join('add_files ' + x for x in sources))
(out / 'build.tcl').write_text(tcl, encoding='ascii')
(out / 'input_manifest.json').write_text(json.dumps({
    x.relative_to(out).as_posix(): hashlib.sha256(x.read_bytes()).hexdigest()
    for x in sorted(out.rglob('*')) if x.is_file()
}, indent=2) + '\n', encoding='utf-8')
print(out)
