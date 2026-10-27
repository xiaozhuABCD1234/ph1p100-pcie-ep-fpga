from pathlib import Path
import ctypes
import hashlib
import json
import re
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[5]
RUN = ROOT/'workflow/runs/20261017-011744-rk-fpga-align'
OUT = Path(__file__).resolve().parent
def sha(b): return hashlib.sha256(b).hexdigest()
def read(p): return (RUN/p).read_text(encoding='utf-8-sig')
def obj(p): return json.loads(read(p))
checks=[]
def check(name, passed, detail=None): checks.append({'name':name,'pass':bool(passed),'detail':detail})

class Slot(ctypes.Structure):
    _fields_=[(n,ctypes.c_uint32) for n in ('seq','len','flags','reserved')]
class Mailbox(ctypes.Structure):
    _fields_=[(n,ctypes.c_uint32) for n in ('magic','seq','count','slot_bytes','slots','stride','width','height','push_dbell')]+[('reserved',ctypes.c_uint32*7)]
check('u32 ABI sizes and doorbell offset',ctypes.sizeof(Slot)==16 and ctypes.sizeof(Mailbox)==64 and Mailbox.push_dbell.offset==32,{'slot':ctypes.sizeof(Slot),'mailbox':ctypes.sizeof(Mailbox),'push_dbell':Mailbox.push_dbell.offset})

fpga='references/peer-fpga-2a4b253/'
driver='references/peer-driver-a0215c5/'
bar=read(fpga+'rtl/ep_side/img/ep_bar_win.v')
link=read(driver+'src/anlogic_pci_link.c')
frame=read(driver+'src/anlogic_pci_frame.c')
pusher=read(fpga+'rtl/ep_side/ddr/ddr_frame_pusher.v')
header=read(driver+'include/anlogic_pci_ioctl.h')
for name,passed in [
 ('BAR CTRL bits source',all(x in bar for x in ('ctrl_cam_ab    <= tlp_dw_s[8]','ctrl_ddr_en    <= tlp_dw_s[5]','ctrl_push_en   <= tlp_dw_s[6]','ctrl_push_src  <= tlp_dw_s[7]','1\'b0, ctrl_pattern_r, ctrl_trigger, ctrl_enable'))),
 ('BAR extension absent default',"default: rd_dw_comb = 32'hDEAD_BEEF" in bar and not re.search(r"12'h(?:100|104|108|10C|110|114|118|11C)\s*:",bar,re.I)),
 ('legacy dst and db formulas', 'dst = (u64)hw->frame_phys + (u64)hw->frame_hdr_bytes' in link and 'offsetof(struct anlogic_frame_mailbox, push_dbell)' in link),
 ('legacy host offset sizeof slot', 'hdr_bytes = sizeof(struct anlogic_frame_slot_hdr)' in frame),
 ('host allocation DMA API', 'dma_alloc_coherent(&hw->pdev->dev, size, &hw->frame_phys' in frame),
 ('completion CPU barrier', 'done = READ_ONCE(mb->push_dbell);\n    dma_rmb();' in frame),
 ('legacy teardown only mode and sleep', 'ctrl & ~ANLOGIC_CTRL_PUSH_EN' in link and 'msleep(20);' in link),
 ('legacy BAR window 0xD0', 'ANLOGIC_BAR_LINK_WIN_END    (ANLOGIC_BAR_PUSH_TLP_OFF + 4u)' in header and 'ANLOGIC_BAR_PUSH_TLP_OFF    0xCCu' in header),
 ('pusher existing 64-bit latches', 'addr_q    <= {dst_hi, dst_lo}' in pusher and 'db_a_q    <= {db_hi, db_lo}' in pusher),
 ('pusher legacy trigger ungated by ACK', 'push_en && src_rdy && (src_seq != last_seq) && (p_st == S_IDLE)' in pusher),
 ('legacy source address truncation', 'm_axi_araddr  <= base_s2[28:0] + a_bcnt * BURST_STEP' in pusher),
]: check(name,passed)

citations=[]
for doc in ('contract/compatibility.md','contract/rk-required-changes.md','artifacts/next-backend-input.md'):
    for rel,num in re.findall(r'`(references/[^`\n]+?):(\d+)`',read(doc)):
        path=RUN/rel
        lines=path.read_text(encoding='utf-8-sig').splitlines() if path.is_file() else []
        item={'document':doc,'path':rel,'line':int(num),'text':lines[int(num)-1] if 0<int(num)<=len(lines) else None}
        citations.append(item)
        check('source citation '+rel+':'+num,item['text'] is not None)

baseline=obj('backup/baseline-manifest.json')
rollback=[]
with zipfile.ZipFile(RUN/'backup/rollback-002820.zip') as z:
    for rec in baseline['rollback']:
        if rec['path'] not in ('camera_ddr_display.bit','camera_ddr_display.cwc','input_manifest.json','camera_ddr_display.al'):
            continue
        data=z.read(rec['path'])
        source=Path(rec['source_path']).read_bytes()
        same=sha(data)==rec['sha256']==sha(source) and len(data)==rec['bytes']
        check('rollback original/archive identity '+rec['path'],same)
        rollback.append({'path':rec['path'],'source_path':rec['source_path'],'bytes':len(data),'sha256':sha(data),'original_sha256':sha(source)})

gitchecks=[]
for repo,commit,rels in [
 ('C:/Users/czz/AppData/Local/Temp/opencode/ref_ph1p100_fpga','2a4b253d9f2e56a943f1667b2a7a366824dcba34',('rtl/ep_side/img/ep_bar_win.v','rtl/ep_side/ddr/ddr_frame_pusher.v','rtl/ep_side/ddr/cam_ddr_writer.v')),
 ('C:/Users/czz/AppData/Local/Temp/opencode/ref_ph1p100_driver','a0215c5a2fcb95bfc867a4768d4831d68edf64a2',('include/anlogic_pci_ioctl.h','src/anlogic_pci_link.c','src/anlogic_pci_frame.c','app/rs/src/bin/frame_grab.rs')),
]:
    prefix=fpga if 'fpga' in repo else driver
    for rel in rels:
        cmd=['git','-C',repo,'show',commit+':'+rel]
        run=subprocess.run(cmd,capture_output=True)
        same=run.returncode==0 and sha(run.stdout)==sha((RUN/prefix/rel).read_bytes())
        check('pinned source byte identity '+rel,same)
        gitchecks.append({'argv':cmd,'exit_code':run.returncode,'stdout_sha256':sha(run.stdout),'snapshot_sha256':sha((RUN/prefix/rel).read_bytes()),'stderr':run.stderr.decode('utf-8',errors='replace')})

tools=obj('evidence/tool-inventory.json')
toolidentities=[]
for t in tools['tools']:
    data=Path(t['path']).read_bytes()
    check('tool binary identity '+t['path'],sha(data)==t['sha256'] and len(data)==t['bytes'])
    toolidentities.append({'path':t['path'],'bytes':len(data),'sha256':sha(data)})
probe=read('evidence/td-probe/stdout.log')
check('frozen TD read-only probe markers','6.2.3.210850' in probe and 'TCL_VERSION 8.6.17' in probe and 'READ_ONLY_CLI_PROBE_OK' in probe and probe.count('REGISTERED ')==11)
reuse=obj('evidence/tool-success-reuse.json')
check('prior tool evidence source identity',sha(Path(reuse['source_path']).read_bytes())==reuse['source_sha256'])
check('candidate unchanged after integration audit',sha((RUN/'candidate-manifest.json').read_bytes())=='9662167a4af6fcea43a76491a9507b191552fa52209648147de02f91cfd877c5')
result={'marker':'SYSTEM_INTEGRATION_AUDIT_COMPLETE','checks':checks,'failed_checks':[x for x in checks if not x['pass']],'source_citations':citations,'rollback':rollback,'git_source_checks':gitchecks,'tool_identities':toolidentities,'hardware_actions':'none; existing evidence reviewed only'}
(OUT/'integration-result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'marker':result['marker'],'check_count':len(checks),'failed_checks':result['failed_checks'],'citations':len(citations),'rollback_identity_count':len(rollback),'pinned_source_count':len(gitchecks)},ensure_ascii=False))
sys.exit(1 if result['failed_checks'] else 0)
