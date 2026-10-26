import json,pathlib,sys
from deadline import run,mapped_project
ROOT=pathlib.Path(__file__).resolve().parents[5]
OUT=pathlib.Path(__file__).resolve().parents[1]
TREE=ROOT/'upstream/ph1p100-pcie-ep-fpga'
RTL=TREE/'rtl/ep_side/cam/sync_offline'
BIN=pathlib.Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
case=sys.argv[1] if len(sys.argv)>1 else 'positive'
target=OUT/'g1'/(sys.argv[2] if len(sys.argv)>2 else case)
target.mkdir(parents=True,exist_ok=True)
files=sorted(RTL.glob('*.v'))
if case=='negative':
    mutant=target/'sync_start_ctrl.v'
    source=(RTL/'sync_start_ctrl.v').read_text()
    assert "reg_data=8'h0f;end\n   6:" in source
    mutant.write_text(source.replace("reg_data=8'h0f;end\n   6:","reg_data=8'h00;end\n   6:",1))
    files=[mutant if p.name==mutant.name else p for p in files]
with mapped_project(ROOT) as drive:
    alias=lambda p:drive/p.relative_to(ROOT)
    run([BIN/'vlib.exe','work'],alias(target),target/'vlib.log',60)
    run([BIN/'vlog.exe','-sv','-work','work',*[alias(p) for p in files],alias(TREE/'sim/tb/tb_sync_offline.sv')],alias(target),target/'vlog.log',300)
    try:
        result=run([BIN/'vsim.exe','-c','-novopt','work.tb_sync_offline','-do','onbreak {quit -code 1}; onerror {quit -code 2}; run -all; quit -code 0'],alias(target),target/'vsim.log',300)
    except RuntimeError:
        text=(target/'vsim.log').read_text(errors='replace')
        if case!='negative' or 'SYNC_FAIL ordered role writes' not in text:raise
        print('NEGATIVE_CONTROL_REJECTED intended_role_HiZ_mutation')
    else:
        if case=='negative':raise RuntimeError('Negative control escaped')
        assert 'SYNC_OFFLINE_PASS mismatch=0' in (target/'vsim.log').read_text(errors='replace')
        print('G1_POSITIVE_PASS')
