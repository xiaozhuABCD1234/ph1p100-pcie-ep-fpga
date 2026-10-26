"""Freeze RGB565 RTL and native ModelSim logs; never build/download a bitstream."""
from pathlib import Path
import argparse,datetime,hashlib,json,re,subprocess,sys,zlib
ROOT=Path(__file__).resolve().parents[2]
BASE=Path('D:/TD/work/csi2/prj/camera_rgb332_reference_20261013_215134')
BIN=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
p=argparse.ArgumentParser();p.add_argument('--test',choices=['capture','pack','ddr'],default='capture')
p.add_argument('--baseline',action='store_true');p.add_argument('--production',action='store_true');p.add_argument('--address-fault',action='store_true')
p.add_argument('--stats-early',action='store_true')
a=p.parse_args()
if a.baseline and a.test!='capture':p.error('baseline is real RGB332 with a compatibility adapter, capture only')
if (a.production or a.address_fault) and a.test!='ddr':p.error('geometry/address controls are DDR only')
if a.stats_early and (a.test!='capture' or a.baseline):p.error('stats-early is real RGB565 capture only')
out=Path('D:/TD/work/csi2/_validation')/('rgb565_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
result={'test':a.test,'baseline':a.baseline,'production':a.production,'address_fault':a.address_fault,'stats_early':a.stats_early,'accepted':False,'commands':[],'sources':{},'hardware_verified':False}
files=[]
def snap(f):
    data=f.read_bytes();assert not (out/f.name).exists();(out/f.name).write_bytes(data)
    result['sources'][f.name]={'path':str(f),'sha256':hashlib.sha256(data).hexdigest()};files.append(f.name)
try:
    (out/'runner.py.snapshot').write_bytes(Path(__file__).read_bytes())
    if a.test=='capture':
        top='tb_bayer565_capture';snap(ROOT/'fpga/csi2/tb'/f'{top}.sv')
        if a.baseline:
            snap(BASE/'bayer332_capture.v')
            adapter='''`timescale 1ns/1ps
module bayer565_capture #(parameter SW=8,SH=4,BAYER_PHASE=0)(
input clk,rst_n,input[39:0] in_pixels,input in_valid,in_line,in_frame,
output out_sof,out_valid,out_last,output[15:0] out_data,
input frame_end,frame_good,frame_abort,
output out_frame_end,out_frame_good,out_frame_abort,
output[31:0] stat_a,stat_b,stat_c,stat_d,stat_count,stat_sequence,output stat_valid);
wire[7:0] old_data;
bayer332_capture #(.SW(SW),.SH(SH),.BAYER_PHASE(BAYER_PHASE)) old(
.clk(clk),.rst_n(rst_n),.in_pixels(in_pixels),.in_valid(in_valid),.in_line(in_line),.in_frame(in_frame),
.out_sof(out_sof),.out_valid(out_valid),.out_last(out_last),.out_data(old_data));
assign out_data={8'd0,old_data};assign {stat_a,stat_b,stat_c,stat_d,stat_count,stat_sequence,stat_valid}=0;
assign {out_frame_end,out_frame_good,out_frame_abort}=0;
endmodule
'''
            (out/'baseline_adapter.v').write_bytes(adapter.encode());files.append('baseline_adapter.v')
            result['control']='Constructed width adapter around actual frozen RGB332 sampler, no stub for old color algorithm.'
        else:
            snap(ROOT/'fpga/csi2/src/cam/bayer565_capture.v')
            if a.stats_early:
                f=out/'bayer565_capture.v';raw=f.read_bytes();(out/'bayer565_capture.v.original').write_bytes(raw)
                s=raw.decode();assert s.count('else if(frame_end)')==1
                s=s.replace('else if(frame_end)','else if(frame_end||(pending&&pending_last))')
                s=s.replace('frame_good&&!frame_rise','(frame_good||(pending&&pending_last))&&!frame_rise')
                f.write_bytes(s.encode());result['control']='Constructed early statistics publisher on preview_last, before CSI FE; candidate RTL untouched.'
        prefix='RGB565_CAPTURE'
    elif a.test=='pack':
        top='tb_rgb565_guarded_pack';snap(ROOT/'fpga/csi2/tb'/f'{top}.sv')
        snap(ROOT/'fpga/csi2/src/mem/rgb565_frame_pack_guarded.v');prefix='RGB565_PACK'
    else:
        top='tb_rgb565_ddr_display';snap(ROOT/'fpga/csi2/tb'/f'{top}.sv')
        for n in ['capture_async_fifo.v','ddr_frame_store.v']:snap(BASE/n)
        for n in ['rgb565_frame_pack_guarded.v','rgb565_display_read.v','rgb565_display_pixels.v','camera_rgb565_display_guarded.v']:snap(ROOT/'fpga/csi2/src/mem'/n)
        prefix='RGB565_DDR'
        pixels=(960*540) if a.production else (64*16)
        values=[]
        for frame_id in range(1,7):
            raw=bytearray()
            for n in range(pixels):
                code=((frame_id*7919+n*131+(n>>8)*997+(n>>16)*1237)^0xa639)&65535
                raw+=code.to_bytes(2,'little')
            values.append(zlib.crc32(raw))
        (out/'golden_crc.txt').write_bytes(('\n'.join(f'{v:08x}' for v in values)+'\n').encode())
        files_crc=hashlib.sha256((out/'golden_crc.txt').read_bytes()).hexdigest()
        result['golden']={'method':'Python zlib.crc32 of independent arithmetic RGB565 codes, little-endian','sha256':files_crc,'values':values}
    params=['-gSW=960','-gSH=540','-gPRODUCTION=1'] if a.production else []
    if a.address_fault:params+=['-gADDRESS_FAULT=1']
    cmds=[['vlib.exe','work'],['vlog.exe','-sv','+define+GUARDED',*files],['vsim.exe','-c',*params,'work.'+top,'-do','run -all; quit -f']]
    for i,cmd in enumerate(cmds):
        actual=[str(BIN/cmd[0]),*cmd[1:]]
        q=subprocess.run(actual,cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=300)
        (out/f'{i}.log').write_bytes(q.stdout);s=q.stdout.decode(errors='replace');print(s[-2200:])
        errs=[int(v) for v in re.findall(r'\bErrors:\s*(\d+)',s)];warns=[int(v) for v in re.findall(r'\bWarnings:\s*(\d+)',s)]
        result['commands'].append({'command':actual,'exit_code':q.returncode,'errors':errs,'warnings':warns,'log':f'{i}.log'})
        assert q.returncode==0 and not re.search(r'\*\*\s*(?:Error|Fatal|Warning)\b',s) and not any(errs) and not any(warns)
        if i==1:assert errs==[0]
    if a.stats_early:result['accepted']=prefix+'_FAIL premature/invalid statistics publication' in s and prefix+'_PASS' not in s
    elif a.baseline:result['accepted']=prefix+'_FAIL color' in s and prefix+'_PASS' not in s
    elif a.address_fault:result['accepted']=prefix+'_FAIL 2x2 pixel/old-frame residue' in s and prefix+'_PASS' not in s
    else:result['accepted']=prefix+'_PASS' in s and prefix+'_FAIL' not in s
except Exception as e:result['error']=repr(e)
finally:
    result['inputs']={n:hashlib.sha256((out/n).read_bytes()).hexdigest() for n in files}
    (out/'result.json').write_bytes((json.dumps(result,indent=2)+'\n').encode())
print('RGB565_TEST_ACCEPTED' if result['accepted'] else 'RGB565_TEST_FAILED',out)
sys.exit(0 if result['accepted'] else 1)
