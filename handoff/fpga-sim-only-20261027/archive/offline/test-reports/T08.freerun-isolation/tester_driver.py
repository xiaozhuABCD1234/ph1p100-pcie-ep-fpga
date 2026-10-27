"""Independent tester launcher: writes only this evidence directory."""
import sys
sys.dont_write_bytecode = True
import argparse, hashlib, importlib.util, json
from pathlib import Path

EV = Path(__file__).resolve().parent
PKG = EV.parent.parent / 'T08.freerun-isolation'
spec = importlib.util.spec_from_file_location('frozen_runner', PKG/'run_freerun.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)

def save(name, value):
    (EV/name).write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')

def variant_compile():
    source = (PKG/'tb_freerun.sv').read_text(encoding='utf-8')
    source = source.replace('integer busy_end=320000;', 'integer busy_end=420000;')
    source = source.replace('target=T0+phase+n*period;if($time<target)#(target-$time);',
        'target=T0+phase+n*period;if($time<target)#(target-$time);\n'
        '   if($test$plusargs("GATE_SOURCE")&&cam==0&&n==3)wait(ready_a);')
    assert source != (PKG/'tb_freerun.sv').read_text(encoding='utf-8')
    tb = EV/'tb_tester_longbusy.sv'
    tb.write_text(source, encoding='utf-8')
    build = EV/'build-variant'
    build.mkdir(exist_ok=False)
    ini = build/'modelsim.ini'
    ini.write_text('[Library]\nwork = '+(build/'work').as_posix()+'\n', encoding='ascii')
    binding = json.loads((PKG/'inputs/source-binding.json').read_text())
    sources = [Path(row['path']) for row in binding['sources'] if row['compiled']]
    assert all(runner.sha(Path(r['path'])) == r['sha256'] for r in binding['sources'])
    r = runner.command([runner.TOOLS/'vlib.exe', build/'work'], build, build/'vlib.log', 60)
    assert r['exit_code'] == 0 and not r['timeout']
    args = [runner.TOOLS/'vlog.exe', '-sv', '-modelsimini', ini, '-work', build/'work', '+define+MIPI_PHY_SIM_STUB']
    args += ['+incdir+'+x.as_posix() for x in sorted({x.parent for x in sources})]
    args += sources+[tb]
    r = runner.command(args, build, build/'vlog.log', 300)
    text = (build/'vlog.log').read_text(errors='replace')
    assert r['exit_code'] == 0 and not r['timeout'] and 'Errors: 0' in text and '** Error' not in text
    save('variant-binding.json', {'original_tb':str(PKG/'tb_freerun.sv'),
        'original_tb_sha256':runner.sha(PKG/'tb_freerun.sv'), 'variant_tb':str(tb),
        'variant_tb_sha256':runner.sha(tb), 'busy_end_ns':420000,
        'normal_mode_source_unconditional':True,
        'negative_plusarg':'GATE_SOURCE: intentionally waits for A descriptor ready at frame4',
        'compile':r})
    print('TESTER_VARIANT_COMPILE_OK')

def source_negative():
    build=EV/'build-variant'; out=EV/'negative-ready-gated';out.mkdir(exist_ok=False)
    args=[runner.TOOLS/'vsim.exe','-c','-modelsimini',build/'modelsim.ini','-lib',build/'work',
        'tb_freerun','+CASE=4','+GATE_SOURCE',
        '-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0']
    r=runner.command(args,out,out/'vsim.log',300)
    text=(out/'vsim.log').read_text(errors='replace')
    # ModelSim can return zero after $fatal; adjudicate the explicit fatal/scoreboard markers.
    r['expected_rejection']='FREERUN_FAIL' in text and '** Fatal' in text and 'source schedule overrun' in text and 'FREERUN_PASS' not in text
    save('ready-gated-negative-result.json',r)
    assert r['expected_rejection'],r
    print('READY_GATED_SOURCE_REJECTED')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action');p.add_argument('--case',type=int,default=0);a=p.parse_args()
    if a.action=='compile':runner.compile_at(EV/'build-original')
    elif a.action=='case':runner.run_case(EV/'build-original',EV/f'case{a.case}',a.case)
    elif a.action=='variant-compile':variant_compile()
    elif a.action=='variant-case':runner.run_case(EV/'build-variant',EV/'case5-longbusy',5)
    elif a.action=='negative':source_negative()
    else:raise ValueError(a.action)
