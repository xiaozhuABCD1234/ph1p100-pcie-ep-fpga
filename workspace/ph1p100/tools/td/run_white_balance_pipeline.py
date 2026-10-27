"""Candidate-bound cycle/packer equivalence, including a zero-stage fault control."""
from pathlib import Path
import argparse, datetime, hashlib, json, re, subprocess, sys

if not __debug__:
    raise RuntimeError('Run verification without Python -O.')
p=argparse.ArgumentParser();p.add_argument('project',type=Path);a=p.parse_args()
project=a.project.resolve();assert project.parent==Path('D:/TD/work/csi2/prj').resolve()
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
manifest=json.loads((project/'input_manifest.json').read_bytes());assert len(manifest)==220
for rel,h in manifest.items():
    f=(project/rel).resolve();assert f.is_relative_to(project) and sha(f)==h,rel
core=(project/'f9p_camera_display_core.v').read_text(encoding='utf-8')
instance=re.findall(r'bayer565_capture\s*#\((.*?)\)\s+u_cam_preview\s*\((.*?)\);',core,re.S)
assert len(instance)==1
expected={'SW':960,'SH':540,'BAYER_PHASE':3,'WB_R_GAIN_Q10':2400,'WB_B_GAIN_Q10':2062,'WB_BLACK_LEVEL':50}
assert {k:int(v) for k,v in re.findall(r'\.(\w+)\((\d+)\)',instance[0][0])}==expected
ports=dict(re.findall(r'\.(\w+)\((\w+)\)',instance[0][1]))
assert ports['clk']=='w_a_byte_clk' and ports['rst_n']=='w_a_rst_out'
for kind in ('end','good','abort'):
    assert core.count(f'.O_frame_{kind}(raw_a_frame_{kind})')==1
    assert ports[f'frame_{kind}']==f'raw_a_frame_{kind}'
    assert ports[f'out_frame_{kind}']==f'cap_frame_{kind}'
out=Path('D:/TD/work/csi2/_validation')/('wb565_pipeline_candidate_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
mapping={'rtl':('bayer565_capture.v','bayer565_capture.v'),'tb':('frozen_tb_bayer565_pipeline.sv','tb_bayer565_pipeline.sv'),'packer':('rgb565_frame_pack_guarded.v','rgb565_frame_pack_guarded.v'),'original':('frozen_unpipelined_bayer565_capture.v','old_bayer565_capture.v')}
inputs={}
for key,(source,name) in mapping.items():
    f=out/name;f.write_bytes((project/source).read_bytes())
    inputs[key]={'path':str(f),'source_path':str(project/source),'sha256':sha(f)}
old=(out/'old_bayer565_capture.v').read_bytes()
assert hashlib.sha256(old).hexdigest()=='362509c9b56113a64685b5d7059c89c284891dcbce7f8265b8f022f8aa620586'
assert old.count(b'module bayer565_capture')==1
(out/'bayer565_reference.v').write_bytes(old.replace(b'module bayer565_capture',b'module bayer565_reference'))
inputs['reference']={'path':str(out/'bayer565_reference.v'),'sha256':sha(out/'bayer565_reference.v'),'original':inputs.pop('original'),'transform':'module name only: bayer565_capture -> bayer565_reference'}
(out/'runner.py.snapshot').write_bytes(Path(__file__).read_bytes())
tb=(out/'tb_bayer565_pipeline.sv').read_text(encoding='utf-8')
for name,value in [('BAYER_PHASE',3),('WB_R_GAIN_Q10',2400),('WB_B_GAIN_Q10',2062),('WB_BLACK_LEVEL',50)]:
    assert re.findall(r'\.'+name+r'\((\d+)\)',tb)==[str(value),str(value)]
bin_path=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
commands=[];results=[];logs={};accepted=False
record={'schema':'wb565_pipeline_v1','project':str(project),'input_manifest_sha256':sha(project/'input_manifest.json'),'core_sha256':sha(project/'f9p_camera_display_core.v'),'actual_core_parameters':expected,'core_verdict_wiring_checked':True,'inputs':inputs,'hardware_verified':False,'ok':False,'status':'fail','bounds':{'sampler_latency':'exactly +1 cycle every non-reset cycle','verdict_latency':'raw FE/good/abort +1 cycle','statistics':'same cycle as frozen reference','packer_latency':'exact +1 with ready1; ordered258bit tokens/equal drops over footer/abort stalls','geometry':'16x2, fixed receivedGBRG; no full-system or board claim'}}
try:
    for fault in (True,False):
        library='red_work' if fault else 'work'
        prefix='red_' if fault else ''
        compile_name=prefix+'compile.log';run_name=prefix+'run.log';sim_name=prefix+'simulator.log'
        logs.update({('fault_' if fault else '')+kind:str(out/name) for kind,name in [('compile',compile_name),('run',run_name),('simulator',sim_name)]})
        stages=[['vlib.exe',library],['vlog.exe','-sv',* ([] if fault else ['+define+PIPELINE_VERDICT_PORTS']),'-work',library,'old_bayer565_capture.v' if fault else 'bayer565_capture.v','bayer565_reference.v','rgb565_frame_pack_guarded.v','tb_bayer565_pipeline.sv'],['vsim.exe','-c','-l',sim_name,library+'.tb_bayer565_pipeline','-do','run -all; quit -f']]
        for i,argv in enumerate(stages):
            command=[str(bin_path/argv[0]),*argv[1:]];commands.append({'executable':command[0],'arguments':command[1:]})
            q=subprocess.run(command,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=60)
            filename=prefix+'vlib.log' if i==0 else (compile_name if i==1 else run_name)
            (out/filename).write_bytes(q.stdout);s=q.stdout.decode(errors='replace')
            errors=[int(n) for n in re.findall(r'Errors:\s*(\d+)',s)];warnings=[int(n) for n in re.findall(r'Warnings:\s*(\d+)',s)]
            results.append({'command':command,'exit_code':q.returncode,'log':filename,'errors':errors,'warnings':warnings})
            assert q.returncode==0 and not any(errors) and not any(warnings) and not re.search(r'\*\*\s*(Error|Fatal|Warning)',s)
            if i in (1,2):assert errors and warnings
        if fault:
            fail_line=next((v for v in s.splitlines() if 'BAYER565_PIPELINE_FAIL cycle=10 fixture=1 display delay got=100/0000 expected=000/0000' in v),None)
            assert fail_line and 'BAYER565_PIPELINE_PASS' not in s
            record['fault']={'detected':True,'kind':'frozen_zero_stage_sampler_as_DUT','dut_sha256':sha(out/'old_bayer565_capture.v'),'macro':'PIPELINE_VERDICT_PORTS omitted; raw verdict wires for legacy interface','fail_marker':'BAYER565_PIPELINE_FAIL','fail_line':fail_line,'errors':0,'warnings':0}
        else:
            pass_line=next((v for v in s.splitlines() if 'BAYER565_PIPELINE_PASS ' in v),None)
            assert pass_line and 'BAYER565_PIPELINE_FAIL' not in s
            counts={k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',pass_line)}
            assert counts=={'cases':14,'pixel_checks':437,'latency_checks':3218,'verdict_checks':3218,'stat_checks':3218,'pack_checks':2878,'starts':15,'words':20,'footers':7,'aborts':7,'stalls':24,'reset_inflight':1,'restart_pending':1}
            record.update(counts=counts,green={'pass_marker':'BAYER565_PIPELINE_PASS','pass_line':pass_line,'errors':0,'warnings':0},ok=True,status='pass')
            print(pass_line)
except Exception as error:
    record['error']=repr(error)
finally:
    (out/'commands.json').write_bytes((json.dumps(commands,indent=2)+'\n').encode())
    record.update(logs=logs,commands=str(out/'commands.json'),command_results=results,runner_sha256=sha(out/'runner.py.snapshot'))
    (out/'result.json').write_bytes((json.dumps(record,indent=2)+'\n').encode())
print('WB565_PIPELINE_ACCEPTED' if record['ok'] else 'WB565_PIPELINE_REJECTED',out)
sys.exit(0 if record['ok'] else 1)
