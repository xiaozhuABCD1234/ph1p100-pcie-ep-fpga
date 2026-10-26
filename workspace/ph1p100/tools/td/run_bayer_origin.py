"""Bind a fixed-origin fixture to the actual candidate's Bayer phase selection."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,subprocess,sys
p=argparse.ArgumentParser();p.add_argument('project',type=Path);p.add_argument('--expect-old-phase-failure',action='store_true');a=p.parse_args()
ROOT=Path(__file__).resolve().parents[2];project=a.project.resolve()
manifest=json.loads((project/'input_manifest.json').read_bytes())
for rel,h in manifest.items():
    f=(project/rel).resolve();assert f.is_relative_to(project) and hashlib.sha256(f.read_bytes()).hexdigest()==h,rel
core=(project/'f9p_camera_display_core.v').read_bytes();phase=re.findall(rb'bayer565_capture\s*#\([^;]+?\.BAYER_PHASE\((\d+)\)',core)
assert len(phase)==1;phase=int(phase[0]);assert phase==(0 if a.expect_old_phase_failure else 3)
out=Path('D:/TD/work/csi2/_validation')/('bayer_origin_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
files=['tb_bayer_origin.sv','bayer565_capture.v']
(out/files[0]).write_bytes((ROOT/'fpga/csi2/tb'/files[0]).read_bytes());(out/files[1]).write_bytes((project/files[1]).read_bytes())
(out/'selected_core.v.snapshot').write_bytes(core);(out/'runner.py.snapshot').write_bytes(Path(__file__).read_bytes())
result={'project':str(project),'input_manifest_sha256':hashlib.sha256((project/'input_manifest.json').read_bytes()).hexdigest(),'phase_from_actual_core':phase,'core_sha256':hashlib.sha256(core).hexdigest(),'expected_old_failure':a.expect_old_phase_failure,'commands':[],'accepted':False,'hardware_verified':False,'scope':'Fixed GBRG assumption and zero-dummy model, not evidence of actual sensor output origin.'}
BIN=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
try:
    port_define=['+define+WB_PIPELINED_PORTS'] if b'out_frame_end' in (out/'bayer565_capture.v').read_bytes() else []
    for i,cmd in enumerate([['vlib.exe','work'],['vlog.exe','-sv',*port_define,*files],['vsim.exe','-c','-gDUT_PHASE='+str(phase),'work.tb_bayer_origin','-do','run -all; quit -f']]):
        command=[str(BIN/cmd[0]),*cmd[1:]];q=subprocess.run(command,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
        (out/f'{i}.log').write_bytes(q.stdout);s=q.stdout.decode(errors='replace');print(s[-1700:])
        errors=[int(v) for v in re.findall(r'Errors:\s*(\d+)',s)];warnings=[int(v) for v in re.findall(r'Warnings:\s*(\d+)',s)]
        result['commands'].append({'command':command,'exit_code':q.returncode,'errors':errors,'warnings':warnings,'log':f'{i}.log'})
        assert q.returncode==0 and not any(errors) and not any(warnings) and not re.search(r'\*\*\s*(?:Fatal|Error|Warning)',s)
        if i==1:assert errors==[0]
    if a.expect_old_phase_failure:result['accepted']='BAYER_ORIGIN_FAIL color phase=0 index=0 got=f81f expected=07e0' in s and 'BAYER_ORIGIN_PASS' not in s
    else:result['accepted']='BAYER_ORIGIN_PASS phase=3 outputs=64' in s and 'BAYER_ORIGIN_FAIL' not in s
except Exception as error:result['error']=repr(error)
finally:
    result['inputs']={n:hashlib.sha256((out/n).read_bytes()).hexdigest() for n in files};(out/'result.json').write_bytes((json.dumps(result,indent=2)+'\n').encode())
print('BAYER_ORIGIN_ACCEPTED' if result['accepted'] else 'BAYER_ORIGIN_REJECTED',out);sys.exit(0 if result['accepted'] else 1)
