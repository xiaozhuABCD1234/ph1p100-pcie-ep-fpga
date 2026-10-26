from pathlib import Path
import json,hashlib,struct,zlib,sys,platform,difflib
from r10f_oracle import check_r10f
H=Path(__file__).resolve().parent
ROOT=Path(r'D:\fpga\ph1p100')
OLD=ROOT/'workflow/runs/20261024-221529_fpga-sim-integration-recovery/T08.sync-production-sim'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
# Independently test the worker's proposal before using its result.
payload=bytes((97+22*13+r*23+k*7)&255 for r in range(3) for k in range(20))
w=[0]*32;w[:14]=[0x46303152,1,128+(1<<16),0,0,9,1,(3<<16)|16,20,0,10<<16,60,60,1]
w[20]=w[21]=zlib.crc32(payload);w[22]=zlib.crc32(struct.pack('<32I',*w))
blob=struct.pack('<32I',*w)+payload+bytes(4096-128-60)
check_r10f(blob,1,9,22,16,3)
rejected=[]
for offset in [0,16,20,28,80,84,88,128,4095]:
 b=bytearray(blob);b[offset]^=1
 try:check_r10f(bytes(b),1,9,22,16,3)
 except AssertionError:rejected.append(offset)
assert len(rejected)==9
(H/'oracle-selftest.json').write_text(json.dumps({'good_geometry':'W16H3','positive_pass':True,'rejected_offsets':rejected,'independent_review':'header session word4 zero and mode word6 one verified against frozen writer; standard CRC plus mathematical payload pattern'},indent=2),encoding='utf-8')
# The exact digital source list has no vendor or sensor substitutes.
excludes={'crc16_upd4.v','crc32_upd4.v'}
rtl=[p for p in (H/'candidate/rtl').rglob('*.v') if 'rc_side' not in p.parts and p.name not in excludes]
rtl += [H/'dual_local_closure.v',H/'sync_i2c_config.v',H/'sync_frame_gate.v']
assert all(p.is_file() for p in rtl)
(H/'sources.f').write_text('\n'.join(p.as_posix() for p in rtl)+'\n',encoding='utf-8')
tcl='set rtl_sources [list \\\n'+''.join('  {'+p.as_posix()+'} \\\n' for p in rtl)+']\nforeach source $rtl_sources {\n if {![file isfile $source]} {error "missing candidate source: $source"}\n}\n# Integration source closure only. No TD command or build is invoked.\n'
(H/'integration-sources.tcl').write_text(tcl,encoding='ascii')
sources=[{'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size} for p in rtl]
(H/'source-closure.json').write_text(json.dumps({'rtl_sources':sources,'simulation_only':['vendor_env.sv','sensor_i2c.sv','tb_production_sync.sv','tb_production_sync_legacy.sv'],'vendor_ip':'not_run; DDR3 MC, PLL, PCIe IP are behavior models for this offline digital closure, no production IP evidence claimed'},indent=2),encoding='utf-8')
diffs=[];changes=[]
for p in (H/'candidate').rglob('*'):
 if p.is_file():
  old=OLD/'candidate'/p.relative_to(H/'candidate')
  if old.is_file() and sha(old)!=sha(p):
   changes.append({'path':str(p),'old_sha256':sha(old),'new_sha256':sha(p)})
   diffs.extend(difflib.unified_diff(old.read_text(encoding='utf-8',errors='replace').splitlines(True),p.read_text(encoding='utf-8',errors='replace').splitlines(True),fromfile=old.as_posix(),tofile=p.as_posix()))
(H/'candidate.diff').write_text(''.join(diffs),encoding='utf-8')
(H/'candidate-changes.json').write_text(json.dumps(changes,indent=2),encoding='utf-8')
protection=[]
for x in json.loads((H.parent/'planning-input-manifest.json').read_text(encoding='utf-8-sig'))['files']:
 p=Path(x['path']);actual=sha(p);assert actual==x['sha256'],'protected source drift '+str(p);protection.append({'path':str(p),'sha256':actual})
(H/'protected-input-audit.json').write_text(json.dumps(protection,indent=2),encoding='utf-8')
raw=1920*1080*5//4;dma=((128+raw+4095)//4096)*4096
slots=[0x100000,0x900000,0x1100000,0x1900000]
assert raw==2592000 and dma==2592768 and all(base+dma<=base+8388608 and base+8388608<=2**29 for base in slots)
audit={'geometry':{'W':1920,'H':1080,'raw_bytes':raw,'content_bytes':128+raw,'dma_bytes':dma,'slot_bytes':8388608},'slot_bases':slots,'boundary_check':True,'double_1080p30_raw_MBps':155.52,'raw_write_plus_read_minimum_MBps':311.04,'physical_CDC_STA_resources':'not_run','cdc_structure':'writer asynchronous FIFO retained; sync_sof_mailbox/reset retained; ownership and AXI operate only in DHI; exported sync observations remain in existing tl_clk_user 50MHz domain, no asynchronous multi-bit resampling added','reset':'common DDR reset clears reader skid/outstanding/ownership and environment queue; only common DDR reset recovers LOCK','latch_review':'new combinational ext range loop assigns defaults; sequential state owns every mailbox/AXI register; no intentional latch','axi':'at most one burst, max128 beats, no4KiB crossing, registered AR stable to handshake, RRESP/RID/RLAST checked, drain before release','python':platform.python_version(),'source_count':len(rtl),'worker_task':'e41b4647d8a442e49e42b98807adc147','worker_pending_call_ids':[]}
(H/'static-audit.json').write_text(json.dumps(audit,indent=2),encoding='utf-8')
tools=[]
for p in [Path(sys.executable),Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem\vlog.exe'),Path(r'D:\intelFPGA\18.1\modelsim_ase\win32aloem\vsim.exe')]:tools.append({'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size})
(H/'tool-identity.json').write_text(json.dumps(tools,indent=2),encoding='utf-8')
print('AUDIT_OK sources='+str(len(rtl))+' protected='+str(len(protection))+' helper_mutations_rejected=9')
