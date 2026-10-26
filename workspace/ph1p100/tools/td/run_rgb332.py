"""Freeze and simulate the RGB332 diagnostic; no build or hardware download."""
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess,re,zlib
p=argparse.ArgumentParser();p.add_argument('--baseline',action='store_true');p.add_argument('--test',choices=['capture','display','chain','ddr_display'],default='capture');p.add_argument('--production',action='store_true');p.add_argument('--address-fault',action='store_true');a=p.parse_args()
if a.baseline and a.test not in ['capture','display']:p.error('baseline control is available for capture/display only')
if a.production and a.test not in ['chain','ddr_display']:p.error('production selects full-width chain or full DDR display geometry')
if a.address_fault and a.test!='ddr_display':p.error('address fault is for DDR display only')
repo=Path(__file__).resolve().parents[2]
out=Path('D:/TD/work/csi2/_validation')/('rgb332_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f'));out.mkdir()
top='tb_bayer332_capture' if a.test=='capture' else 'tb_rgb332_display'
source=('fpga/csi2/src/cam/cam_preview_capture.v' if a.baseline else 'fpga/csi2/src/cam/bayer332_capture.v') if a.test=='capture' else ('fpga/csi2/src/mem/gray_display_pixels.v' if a.baseline else 'fpga/csi2/src/mem/rgb332_display_pixels.v')
files=[repo/'fpga/csi2/tb'/(top+'.sv'),repo/source] if a.test in ['capture','display'] else []
if a.test=='chain':
 top='tb_csi_preview_integrity'
 files=[repo/'fpga/csi2/tb'/(top+'.sv'),repo/'fpga/csi2/prj/camera_peer/uisrc/03_ip/mipi_csi_2/csi_rx_hdr_ecc.v',
        repo/'fpga/csi2/src/csi/csi_rx_packet_integrity.v',repo/'fpga/csi2/src/csi/csi_rx_10bit_unpack_checked.v',
        repo/'fpga/csi2/src/cam/bayer332_capture.v',*[repo/'fpga/csi2/src/mem'/n for n in ['gray_frame_pack_guarded.v','capture_async_fifo.v','ddr_frame_store.v']]]
if a.test=='ddr_display':
 top='tb_ddr_display'
 files=[repo/'fpga/csi2/tb/tb_ddr_display.sv',*[repo/'fpga/csi2/src/mem'/n for n in ['capture_async_fifo.v','gray_frame_pack_guarded.v','ddr_frame_store.v','ddr_display_read.v','rgb332_display_pixels.v','camera_ddr_display_guarded.v']]]
for f in files:(out/f.name).write_bytes(f.read_bytes())
if a.test=='chain':
 s=(out/(top+'.sv')).read_text()
 start=s.index(' cam_preview_capture #(');end=s.index(');',start)+2
 s=s[:start]+''' bayer332_capture #(.SW(SW),.SH(SH),.BAYER_PHASE(0)) preview(
 .clk(clk),.rst_n(rst_n),.in_pixels(pixels),.in_valid(pixels_valid),.in_line(inl),.in_frame(inf),
 .out_sof(gs),.out_valid(gv),.out_last(gl),.out_data(gd));'''+s[end:]
 start=s.index(' function[7:0] gray(');end=s.index('endfunction',start)+len('endfunction')
 s=s[:start]+''' function[7:0] gray(input integer col);
 integer r,b,g;begin r=value(col*5);b=value(col*5+1);g=(r+b)/2;gray=((r/32)<<5)|((g/32)<<2)|(b/64);end endfunction'''+s[end:]
 (out/(top+'.sv')).write_bytes(s.encode())
 wc=4800 if a.production else 80
 value=lambda n:(n*37+(n>>8)*13+7)&255
 payload=bytes(((value(n)//32)<<5)|((((value(n)+value(n+1))//2)//32)<<2)|(value(n+1)//64) for n in range(0,wc,5))*4
 (out/'golden_crc.txt').write_bytes((f'{zlib.crc32(payload):08x}\n').encode())
if a.test=='ddr_display':
 f=out/'camera_ddr_display_guarded.v';s=f.read_bytes();old=b'gray_display_pixels #(.SW(SW),.SH(SH)) u_pixels('
 assert s.count(old)==1;s=s.replace(old,b'rgb332_display_pixels #(.SW(SW),.SH(SH),.FRAMES_PER_MODE(480)) u_pixels(')
 anchor=b'.underflow_frames(underflow_frames),.shown_frames(shown_frames));';assert s.count(anchor)==1
 f.write_bytes(s.replace(anchor,b'.underflow_frames(underflow_frames),.shown_frames(shown_frames),.color_mode());'))
 f=out/'tb_ddr_display.sv';s=f.read_text()
 anchor=' task show_frame('
 ref=''' function[23:0] color_expected(input[7:0] code);
 integer r,g,b;begin r=(((code>>5)&7)*255+3)/7;g=(((code>>2)&7)*255+3)/7;b=(code&3)*85;
 color_expected={r[7:0],g[7:0],b[7:0]};end endfunction
'''
 assert s.count(anchor)==1;s=s.replace(anchor,ref+anchor)
 assert s.count('rgb!=={expected,expected,expected}')==1
 s=s.replace('rgb!=={expected,expected,expected}','rgb!==color_expected(expected)');f.write_bytes(s.encode())
binpath=Path('D:/intelFPGA/18.1/modelsim_ase/win32aloem')
params=(['-gLINE_BYTES=4800'] if a.production else []) if a.test=='chain' else (['-gSW=960','-gSH=540','-gPRODUCTION=1'] if a.production else [])
if a.address_fault:params+=['-gADDRESS_FAULT=1']
commands=[['vlib.exe','work'],['vlog.exe','-sv']+(['+define+BASELINE_GRAY'] if a.baseline else [])+(['+define+GUARDED'] if a.test=='ddr_display' else [])+[f.name for f in files],['vsim.exe','-c',*params,'work.'+top,'-do','run -all; quit -f']]
results=[]
for index,cmd in enumerate(commands):
 q=subprocess.run([str(binpath/cmd[0]),*cmd[1:]],cwd=out,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=240)
 (out/f'{index}.log').write_bytes(q.stdout);s=q.stdout.decode(errors='replace');print(s[-2200:]);results.append({'command':cmd,'returncode':q.returncode})
 if index<2 and (q.returncode or '** Error' in s):raise SystemExit('Compilation failed: '+str(out))
prefix='INTEGRITY' if a.test=='chain' else 'DDR_DISPLAY' if a.test=='ddr_display' else 'RGB332_'+a.test.upper()
passed=q.returncode==0 and prefix+'_PASS' in s and prefix+'_FAIL' not in s and '** Error' not in s
accepted=(prefix+('_FAIL color' if a.test=='capture' else '_FAIL pixel') in s and prefix+'_PASS' not in s) if a.baseline else passed
if a.address_fault:accepted='DDR_DISPLAY_FAIL 2x2 pixel/old-frame residue' in s and 'DDR_DISPLAY_PASS' not in s
transforms={'chain':'Substitute RGB332 capture and independent RGB332 golden; production=4800-byte CSI lines with compact vertical geometry','ddr_display':'Substitute exact RGB332 consumer; independent arithmetic color oracle; production=960x540 complete payload and 1920x1080 active pixels with compact blanking'}
(out/'result.json').write_bytes((json.dumps({'test':a.test,'baseline':a.baseline,'production':a.production,'address_fault':a.address_fault,'accepted':accepted,'commands':results,'inputs':{f.name:hashlib.sha256((out/f.name).read_bytes()).hexdigest() for f in files},'snapshot_transform':transforms.get(a.test)},indent=2)+'\n').encode())
print('RGB332_TEST_ACCEPTED' if accepted else 'RGB332_TEST_FAILED',out)
if not accepted:raise SystemExit(1)
