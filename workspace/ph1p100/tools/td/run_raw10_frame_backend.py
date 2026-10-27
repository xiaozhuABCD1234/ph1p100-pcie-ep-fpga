"""Frozen-source tests for the full-size RAW10 frame backend, not sensor capture."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,subprocess,sys

REPO=Path(__file__).resolve().parents[2]
MODELSIM=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
LEGACY='ce9e9cd58faa4ef02e147c1609ef3c831162a91a'
parser=argparse.ArgumentParser()
parser.add_argument('--test',choices=['probe','store','capture'],default='probe')
parser.add_argument('--baseline',action='store_true')
parser.add_argument('--production',action='store_true')
parser.add_argument('--high-alias',action='store_true')
a=parser.parse_args()
if a.baseline and (a.test!='probe' or not a.production or a.high_alias):
    parser.error('Baseline is the real old offset-wrap test: probe --production only')
if a.high_alias and (a.test!='probe' or not a.production):
    parser.error('High alias requires production probe')
out=Path('D:/TD/work/csi2/_validation')/('raw10_frame_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir()
top={'probe':'tb_ddr_frame_probe','store':'tb_ddr_frame_store','capture':'tb_capture_chain'}[a.test]
sources=['fpga/csi2/tb/'+top+'.sv','fpga/csi2/src/mem/ddr_frame_store.v']
if a.test=='probe':sources+=['fpga/csi2/src/mem/ddr_frame_probe.v']
if a.test=='capture':
    sources+=['fpga/csi2/src/mem/'+n for n in ['capture_async_fifo.v','ddr_capture_check.v']]
    sources+=['fpga/csi2/src/mem/'+n for n in ['gray_frame_pack.v','camera_ddr_capture.v']]
result={'test':a.test,'baseline':a.baseline,'production':a.production,'high_alias':a.high_alias,
        'scope':'Offline native-PAXI backend; no real camera, DDR PHY, display or performance acceptance.',
        'inputs':{},'source_paths':{},'commands':[],'accepted':False}
try:
    for name in sources:
        if a.baseline and name.startswith('fpga/csi2/src/'):
            data=subprocess.check_output(['D:/downlaod/Git/cmd/git.exe','show',LEGACY+':'+name],cwd=REPO)
        else:data=(REPO/name).read_bytes()
        target=out/Path(name).name;assert not target.exists();target.write_bytes(data)
        result['inputs'][target.name]=hashlib.sha256(data).hexdigest();result['source_paths'][target.name]=name
    (out/'runner.py.snapshot').write_bytes(Path(__file__).read_bytes())
    params=[]
    if a.test=='probe':params=['-gFRAME_WORDS='+str(81001 if a.production else 8),'-gHIGH_ADDRESS_ALIAS='+str(int(a.high_alias))]
    if a.test=='capture':
        params=['-gFRAME_BYTES='+str(2592000 if a.production else 256)]
    commands=[['vlib.exe','work'],['vlog.exe','-sv',*[Path(s).name for s in sources]],
              ['vsim.exe','-c',*params,'work.'+top,'-do','run -all; quit -f']]
    last=''
    for index,cmd in enumerate(commands):
        actual=[str(MODELSIM/cmd[0]),*cmd[1:]]
        entry={'command':actual,'cwd':str(out),'log':str(index)+'.log'};result['commands'].append(entry)
        try:
            completed=subprocess.run(actual,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=300)
        except subprocess.TimeoutExpired as error:
            (out/entry['log']).write_bytes(error.stdout or b'')
            entry['timed_out']=True
            raise
        (out/entry['log']).write_bytes(completed.stdout);last=completed.stdout.decode(errors='replace')
        entry['exit_code']=completed.returncode
        entry['reported_errors']=[int(n) for n in re.findall(r'\bErrors:\s*(\d+)',last)]
        entry['reported_warnings']=[int(n) for n in re.findall(r'\bWarnings:\s*(\d+)',last)]
        print(last[-2200:])
        assert completed.returncode==0 and not re.search(r'\*\*\s*(?:Error|Fatal|Warning)\b',last)
        assert not any(entry['reported_errors']) and not any(entry['reported_warnings'])
        if index==1:assert entry['reported_errors']==[0]
    prefix={'probe':'DDR_PROBE','store':'DDR_FRAME','capture':'CAPTURE_CHAIN'}[a.test]
    if a.baseline:
        result['accepted']='DDR_PROBE_FAIL write offset wrapped/truncated expected=65536 actual=0' in last and 'DDR_PROBE_PASS' not in last
    else:result['accepted']=prefix+'_PASS' in last and prefix+'_FAIL' not in last
    result['expected_marker']='DDR_PROBE_FAIL write offset wrapped/truncated expected=65536 actual=0' if a.baseline else prefix+'_PASS'
except Exception as error:
    result['error']=repr(error)
finally:
    (out/'result.json').write_bytes((json.dumps(result,indent=2)+'\n').encode())
print('RAW10_FRAME_TEST_ACCEPTED' if result['accepted'] else 'RAW10_FRAME_TEST_FAILED',out)
sys.exit(0 if result['accepted'] else 1)
