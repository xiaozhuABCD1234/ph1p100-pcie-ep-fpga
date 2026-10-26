from pathlib import Path
import hashlib, json, shutil, sys, importlib.util, subprocess, datetime, re, ctypes
sys.dont_write_bytecode=True
RUN=Path(__file__).resolve().parents[1]
ROOT=RUN.parents[2]
for sub in ('contract','artifacts','references/local-inputs','references/plan-inputs'):
 (RUN/sub).mkdir(parents=True,exist_ok=True)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def dump(p,x): p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def write(rel,text): (RUN/rel).write_text(text.strip()+'\n',encoding='utf-8')
def render(text):
 return re.sub(r'\{(loc\(.*?\))\}',lambda found:str(eval(found.group(1),globals())),text)
F='references/peer-fpga-2a4b253/'
D='references/peer-driver-a0215c5/'
local_names=['parallel/frame/frame_contract.py','parallel/docs/帧与元数据接口合同_2026-10-15.md','fpga/csi2/src/csi/csi_rx_packet_handler_checked.v','fpga/csi2/src/csi/csi_rx_packet_integrity.v','fpga/csi2/src/csi/csi_rx_10bit_unpack_checked.v','fpga/csi2/src/csi/csi_rx_hdr_ecc.v','fpga/csi2/src/csi/mipi_csi2_rx_ph1p.v','fpga/csi2/src/f9p_camera_capture_core.v']
local=[]
for name in local_names:
 p=ROOT/name
 if not p.is_file():
  # Locate only exact basenames within the intended source tree; preserve actual path.
  matches=list((ROOT/'fpga/csi2').rglob(Path(name).name))
  if len(matches)!=1: raise RuntimeError('input absent/ambiguous '+name)
  p=matches[0]; name=p.relative_to(ROOT).as_posix()
 q=RUN/'references/local-inputs'/name; q.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(p,q)
 local.append({'source_path':p.as_posix(),'snapshot_path':q.as_posix(),'sha256':sha(q)})
for name in ('request.md','user-feedback-01.md','input-index.md','fpga-design-guide.md','dev-plan.md','task-T03.rk-align-freeze.md','dispatch.json'):
 shutil.copyfile(RUN/name,RUN/'references/plan-inputs'/name)
dump(RUN/'references/local-provenance.json',{'head':'ba0fca5f2c397db88059040b2ffe55c76867da31','files':local,'policy':'snapshots are actual dirty-capable inputs, not inferred from HEAD; production files remain read-only'})
def loc(name,pattern):
 lines=(RUN/name).read_text(encoding='utf-8').splitlines()
 for i,line in enumerate(lines,1):
  if re.search(pattern,line): return f'`{name}:{i}`'
 raise RuntimeError('source evidence not found '+name+' '+pattern)
bar=F+'rtl/ep_side/img/ep_bar_win.v'
pusher=F+'rtl/ep_side/ddr/ddr_frame_pusher.v'
writer=F+'rtl/ep_side/ddr/cam_ddr_writer.v'
top=F+'rtl/ep_side/ph1p_pcie_ep_top.v'
header=D+'include/anlogic_pci_ioctl.h'
frame=D+'src/anlogic_pci_frame.c'
link=D+'src/anlogic_pci_link.c'
rust=D+'app/rs/src/bin/frame_grab.rs'
cam=D+'app/rs/src/bin/cam_grab.rs'

regs=[]
for off,name,access,pattern in [
 (0x40,'MAGIC','RO',r"12'h40:"),(0x44,'CTRL','RW',r"12'h44:  rd_dw_comb"),(0x48,'IMG_STATUS','RO',r"12'h48:"),(0x4c,'TEST_FRAME_CNT','RO',r"12'h4C:"),(0x64,'LEGACY_VERSION','RO',r"12'h64:"),
 (0xA0,'DDR_SEQ_A','RO',r"12'hA0:"),(0xA4,'DDR_BASE_A','RO',r"12'hA4:"),(0xA8,'DDR_STATUS_A','RO',r"12'hA8:"),(0xAC,'DDR_LEN_A','RO',r"12'hAC:"),
 (0xB0,'PUSH_DST_LO','RW',r"12'hB0:  rd_dw_comb"),(0xB4,'PUSH_DST_HI','RW',r"12'hB4:  rd_dw_comb"),(0xB8,'PUSH_DB_LO','RW',r"12'hB8:  rd_dw_comb"),(0xBC,'PUSH_DB_HI','RW',r"12'hBC:  rd_dw_comb"),
 (0xC0,'PUSH_DONE','RO',r"12'hC0:"),(0xC4,'PUSH_STATUS','RO',r"12'hC4:"),(0xC8,'PUSH_ERR','RO',r"12'hC8:"),(0xCC,'PUSH_TLP_CNT','RO',r"12'hCC:"),
 (0xD0,'CAM_DIAG_A','RO',r"12'hD0:"),(0xD4,'CAM_TAP_B','RW',r"12'hD4:  rd_dw_comb"),(0xD8,'CAM_DIAG_B','RO',r"12'hD8:"),(0xDC,'CAM_DROP_A','RO',r"12'hDC:"),
 (0xE0,'DDR_SEQ_B','RO',r"12'hE0:"),(0xE4,'DDR_BASE_B','RO',r"12'hE4:"),(0xE8,'DDR_STATUS_B','RO',r"12'hE8:"),(0xEC,'DDR_LEN_B','RO',r"12'hEC:"),(0xF0,'CAM_DROP_A2','RO',r"12'hF0:"),(0xF4,'CAM_DROP_A3','RO',r"12'hF4:")]:
 regs.append({'offset':off,'offset_hex':f'0x{off:03X}','name':name,'access':access,'status':'implemented in pinned peer; unchanged by this package','evidence':loc(bar,pattern)})
extension=[
 {'offset':0x100,'name':'DMA_CAP_BYTES','access':'RW','reset':0,'semantics':'u32 allocated transport capacity in bytes; only config staging; require >= frame dma_bytes'},
 {'offset':0x104,'name':'SESSION_ID','access':'RW','reset':0,'semantics':'nonzero new session identity; staging only; reset/unload/reconnect changes session'},
 {'offset':0x108,'name':'TX_CMD','access':'W1 command, reads 0','reset':0,'semantics':'bit0 ARM_ONE_SHOT; bit1 ACK_RELEASE; bit2 CANCEL. Exactly one bit per write; invalid combinations rejected. ARM latches destination, capacity, doorbell, session, camera and immutable complete-source descriptor atomically; disallowed busy/held/draining. CANCEL disarms, completes any already opened TLP without success doorbell, then drains outstanding source responses before idle.'},
 {'offset':0x10C,'name':'ACK_SEQ','access':'RW','reset':0,'semantics':'staged held completion sequence, used only by ACK_RELEASE'},
 {'offset':0x110,'name':'ACK_SESSION','access':'RW','reset':0,'semantics':'staged held session; ACK_RELEASE requires exact held seq AND session, no active DMA/drain'},
 {'offset':0x114,'name':'TX_STATUS','access':'RO','reset':0,'semantics':'bit0 armed, bit1 busy, bit2 held, bit3 rejected/error, bit4 draining; reserved bits zero'},
 {'offset':0x118,'name':'EXT_MAGIC','access':'RO','reset':0x31414B52,'semantics':'little-endian ASCII RKA1; absent legacy read DEAD_BEEF must fail closed'},
 {'offset':0x11C,'name':'EXT_VERSION','access':'RO','reset':0x00010000,'semantics':'proposed safety interface major1 minor0; checked before any arm'},
]
bits=[{'bit':n,'name':name,'semantics':sem} for n,name,sem in [(0,'enable','mode enable, not ownership permission'),(1,'trigger','one-cycle test trigger; self-clearing'),(2,'reinit_toggle','legacy pattern[0] routed to sensor reinit toggle'),(3,'test_pattern','legacy pattern[1], test-source mode'),(4,'reserved','write ignored/read0'),(5,'ddr_enable','capture-to-DDR enable'),(6,'push_enable','mode enable only; extension grant still required'),(7,'push_source','0 DDR, 1 ERAM diagnostic source'),(8,'camera_ab','0 A, 1 B; latch for whole transfer')]]
dump(RUN/'contract/registers.json',{'schema_version':1,'pinned_fpga_commit':'2a4b253d9f2e56a943f1667b2a7a366824dcba34','pinned_driver_commit':'a0215c5a2fcb95bfc867a4768d4831d68edf64a2','registers':regs,'ctrl_bits':bits,'ctrl_evidence':[loc(bar,r'ctrl_cam_ab\s+<= tlp_dw_s\[8\]'),loc(bar,r"1'b0, ctrl_pattern_r")],'required_rk_arm_bits':0x61,'required_rk_arm_bits_b':0x161,'legacy_driver_arm_bits':0x71,'extension_status':'proposed next-backend input ONLY; not implemented, compiled, applied or hardware tested in this package','extension_registers':extension,'default_policy':'reset cap=0 session=0 armed=0. CTRL=0x61 alone MUST NOT transmit; no legacy fallback in formal mode; every accepted grant gives at most one completed frame and holds the slot until matching ACK.','host_abi':{'slot_header_struct_bytes':16,'hdr_bytes_transport_offset':128,'host_prefix_padding_bytes':112,'r10f_header_bytes':128,'mailbox_bytes':64,'mailbox_push_dbell_offset':32,'ioctl_layout_policy':'existing structs and ioctl numbers unchanged; future ACK uses existing privileged BAR control path; reject incompatible EXT_MAGIC/VERSION rather than reinterpreting old bit4'}})

spec=importlib.util.spec_from_file_location('frozen_frame',RUN/'references/local-inputs/parallel/frame/frame_contract.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
datasets=[]
for label,w,h,rx,ry in [('small',8,4,0,0),('1080p',1920,1080,960,540)]:
 raw=bytes.fromhex('0000ffffe4')*(w*h//4)
 hdr=m.pack_header(width=w,height=h,stride_bytes=w//4*5,roi_x=rx,roi_y=ry,bayer_phase=3,session_id=0x20261017,capture_seq=1,mode_id=1,raw_bytes=len(raw),payload_bytes=len(raw),flags=m.FLAG_CROPPED if rx or ry else 0,raw_crc32=m.crc32_ieee(raw),payload_crc32=m.crc32_ieee(raw))
 content=hdr+raw; dma=content+bytes((-len(content))%4096)
 path=RUN/f'artifacts/r10f-{label}-synthetic.dma';path.write_bytes(dma)
 datasets.append({'name':label,'identity':'synthetic diagnostic ONLY; not CSI capture or Bayer phase proof','path':path.relative_to(RUN).as_posix(),'sha256':sha(path),'width':w,'height':h,'stride_bytes':w//4*5,'raw_bytes':len(raw),'payload_bytes':len(raw),'r10f_header_bytes':128,'content_bytes':len(content),'dma_bytes':len(dma),'tail_pad':len(dma)-len(content),'mwr_packets':len(dma)//128,'ddr_read_bursts':len(dma)//4096,'host_hdr_bytes':128,'host_stride':((128+len(dma)+4095)//4096)*4096,'host_total_alloc':((128+len(dma)+4095)//4096)*4096+4096,'page_size_assumption':4096,'pixel_group':[0,1,1022,1023],'packed_group_hex':'0000ffffe4','raw_crc32':m.crc32_ieee(raw),'payload_crc32':m.crc32_ieee(raw),'header_crc32':int.from_bytes(hdr[0x58:0x5c],'little')})
vectors={'schema_version':1,'scope':'executable contract fixtures only; not RTL/driver/hardware validation','datasets':datasets,
 'control':[{'id':'legacy-bit4-arm-reject','written':0x71,'readback':0x61,'required_mask':0x71,'expected':False},{'id':'new-A-arm-bits','written':0x61,'readback':0x61,'required_mask':0x61,'expected':True},{'id':'new-B-select','written':0x161,'readback':0x161,'required_mask':0x161,'expected':True}],
 'dma_boundaries':[{'id':'old-plus16-crosses4k','base':0x100000010,'bytes':2592768,'packet_bytes':128,'expected':False,'first_crossing_packet_index':31,'first_crossing_address':0x100000f90},{'id':'new-plus128-aligned','base':0x100000080,'bytes':2592768,'packet_bytes':128,'expected':True}],
 'authorization_cases':[{'id':'reset-default-no-grant','authorized':False,'capacity':2592768,'expected':False},{'id':'short-capacity','authorized':True,'capacity':2592767,'expected':False},{'id':'exact-capacity','authorized':True,'capacity':2592768,'expected':True}],
 'frame_mutations':[{'id':'valid','operation':'none','expected':True},{'id':'truncated','operation':'drop_last_byte','expected':False},{'id':'nonzero-tail','operation':'tail_nonzero','expected':False},{'id':'bad-payload-crc','operation':'payload_flip','expected':False},{'id':'bad-header-crc','operation':'header_flip','expected':False},{'id':'unknown-codec','operation':'set_codec_1_recrc','expected':False},{'id':'bad-frame','operation':'set_bad_recrc','expected':False},{'id':'partial-frame','operation':'set_partial_recrc','expected':False},{'id':'oversize-frame','operation':'set_oversize_recrc','expected':False},{'id':'illegal-payload-length','operation':'set_length_recrc','expected':False}],
 'safety_required_cases':['destination zero, unaligned or u64 end overflow => no TLP','doorbell zero, unaligned, overlapping allocated frame transport => no TLP','source base not 4KiB aligned, high bits above controller address space, or base+dma_bytes over DDR capacity => no TLP','busy/held grant => rejected, no overwrite','wrong ACK session/sequence => no release','mode/camera/address changes during transfer => affect next grant only','cancel/reset => no success doorbell; drain old session before rearm','stall each packet beat beyond WAIT_LIMIT => preserve open TLP and output until handshake; error diagnostic cannot truncate packet']}
dump(RUN/'contract/acceptance-vectors.json',vectors)

write('contract/compatibility.md',render('''# T03.rk-align-freeze：接口裁决与证据

状态：本包仅固定可恢复起点、合同与合成向量；没有修改生产RTL/驱动，没有执行构建或下载。正式双方G0签收待确认；本包局部G0/G1待三测试，G2—G5按计划不适用。所有源引用相对本run，固定提交见provenance.json。

## 固定版本与责任

FPGA peer=2a4b253d9f2e56a943f1667b2a7a366824dcba34，driver peer=a0215c5a2fcb95bfc867a4768d4831d68edf64a2。本方HEAD=ba0fca5f2c397db88059040b2ffe55c76867da31，origin/main=3862a9beef2081bbd45f8bf54d7f3b4844e3b248：仅记录差异，不同步覆盖。精确快照由git archive对象产生；临时checkout与对象内容可能不同，不作为冻结源码。

本方适配peer的匹配PCIe核/PLL、EP Posted MWr、BAR和doorbell及AXI DDR3-800E后端。本方提供checked CSI、packed RAW10、整帧good/abort裁决、内容CRC与缓冲所有权；RK适配控制位、128B槽偏移、分配容量授权、单槽消费/ACK和严格解析。旧PAXI/HDMI1080p60 002820完整保留；AXI与PAXI不能直接接线替换。peer writer的FRAME_BYTES=W*H和字节提取是8bit帧，不能当RAW10：{loc(writer,r'FRAME_BYTES\s+= W \* H')}；peer DDR参数见`references/peer-fpga-2a4b253/al_ip/ddr3_mc_0/.params_ddr3_mc_0.txt`（800E/AXI=1/PAXI=0）。

## 三层长度与两层128B

packed RAW10布局来自`references/local-inputs/parallel/frame/frame_contract.py:99`附近：P0[9:2],P1[9:2],P2[9:2],P3[9:2],四个低2bit按P0→P3。目标1920×1080，stride=2400B，raw_bytes=payload_bytes=2,592,000B。R10F header=128B，content_bytes=2,592,128B；dma_bytes=ceil(content/4096)*4096=2,592,768B；尾填充640B全0。MWr载荷128B共20,256笔，doorbell另1笔；DDR读4096B共633突发。pusher frame_bytes必须是dma_bytes，不能给raw_bytes或content_bytes：{loc(pusher,r'input  wire \[31:0\]  frame_bytes')}。

host槽头仍是四u32=16B（seq/len/flags/reserved），见{loc(header,r'struct anlogic_frame_slot_hdr')}。但frameinfo.hdr_bytes改为128B，表示传输数据起点：host [0,16)槽头，[16,128)112B零padding，[128,256)完整R10F头，[256,2592256)有效packed payload，[2592256,2592896)640B DMA尾零。host stride=PAGE_ALIGN(128+2,592,768)=2,596,864B，mailbox页起于stride，单槽总分配2,600,960B（4KiB PAGE_SIZE假设）；槽末其余3968B不是DMA数据。16B host槽头、128B host偏移与128B R10F头不可合并。旧驱动按sizeof(slot_hdr)设置hdr_bytes：{loc(frame,r'hdr_bytes = sizeof')}，地址按hdr_bytes加偏移：{loc(link,r'dst = \(u64\)hw->frame_phys')}，Rust正确使用返回hdr_bytes的入口：{loc(rust,r'let src = .*info.hdr_bytes')}。

CRC32 IEEE reflected poly0xEDB88320，init/final XOR全1。raw_crc32和payload_crc32都只覆盖packed有效载荷；header_crc32将0x58..0x5B清0后覆盖完整128B头；640B transport尾零及host前缀/槽末padding均不入内容CRC。测试向量分别破坏payload/头/尾以验证分层。旧参考build_frame默认pad_to32会将payload padding计入payload_bytes；本包用pack_header明确不含transport尾，1080p尺寸本身整除32。现有parse_frame是草案，不能直接当严格RK发布解析器：必须另检查codec=0、拒bad/partial/oversize、精确长度和尾零。BPR1保留独立，不分配压缩codec，不把BPR1放入codec0。

## CTRL、DMA与所有权

CTRL bit0 enable；bit1测试trigger自清；bit2 reinit toggle；bit3测试pattern；bit4保留读0；bit5 DDR；bit6 push；bit7源；bit8 A/B。实际赋值证据{loc(bar,r'ctrl_cam_ab\s+<= tlp_dw_s\[8\]')}与{loc(bar,r"1'b0, ctrl_pattern_r")}。RK旧ARM_BITS包含bit4=0x71，见{loc(header,r'#define ANLOGIC_CTRL_ARM_BITS')}；回读0x61导致旧条件拒绝。新必需mask=0x61，B另带0x100，触发/reinit不放入稳定arm mask。0x4C是测试源计数，真实相机帧序号A=0xA0/B=0xE0；保留0x64旧VERSION及0xB0..CC语义，旧VERSION不代表新安全扩展存在。

固定128B MWr要求dst%128=0，每笔(addr&4095)+128<=4096。页对齐base+16的第32笔(index31)从0xF90开始跨4KiB：旧+16是明确负例。base+128则每笔不跨4KiB，但不能代替容量、MPS和分配范围授权检查。门铃单DW 4B对齐且独占mailbox页内，不能与DMA传输区重叠；push_dbell相对mailbox偏移32B，见{loc(header,r'unsigned int push_dbell')}。地址64bit整帧锁存、容量>=dma_bytes、dst+len无64bit溢出、source base4KiB对齐和地址范围不超过实际DDR容量都是发包前条件。peer只检查dst非0并已有目标/门铃锁存，见{loc(pusher,r'if \(\(dst_lo ==')}与{loc(pusher,r'addr_q\s+<= .*dst_hi, dst_lo')}；不把已有锁存误说成缺失，但新增授权参数与源会话必须同时锁存。

安全扩展拟定于registers.json的0x100..0x11C，原peer这段默认DEAD_BEEF，见{loc(bar,r'default: rd_dw_comb')}；尚未实施。reset容量/会话/授权均0；CTRL 0x61单独不授权发包。单槽one-shot：ARM成功给一帧额度，完成后held，必须匹配(session,seq) ACK才release，并需重新ARM。无完整帧、容量不足、已held或会话不符禁止发包。CANCEL不截断已开TLP，完成开包/排空旧源响应后回idle，失败不门铃。源缓冲writing→complete→held_for_tx→released；双缓冲轮换本身不保证所有权。FPGA先payload后doorbell、同Requester无RO；driver READ_ONCE门铃→dma_rmb→内容验证→发布host槽头/seq；用户态复制/CRC通过后ACK。两次seq相等不能证明传输期间未覆盖。

## 帧来源与验证边界

1920×1080使用真实4K30有效图像的偶数ROI，默认有效区x960/y540；physical dummy/embedded另计。peer SKIP_ROWS=37是peer来源，见{loc(writer,r'parameter \[15:0\]\s+SKIP_ROWS')}，本板尚未验证，不能抄为板证。phase3来自旧预览配置且需正式帧实查，不能从960×540预览扩大生成1080p。当前两个dma文件均明确synthetic diagnostic。CSI不可反压，CRC/ECC/WC/行数/超时/overflow拒整帧，capture_seq允许缺口；O_frame_good在FE裁决前不发布。完整几何、曝光同步、双路吞吐、G2/G3/G4与RK实收都不由本包证明。

已冻结：版本/职责/非压缩格式/长度/位定义/安全扩展拟定语义。待确认：双方签收、实际相机几何相位、RK通道/内核/MPS/IOMMU/PAGE_SIZE、JTAG器件与硬件窗口。不适用：本包构建、板测、压缩RTL与深度/NPU。
'''))

write('contract/rk-required-changes.md',render('''# RK必改清单（目标driver a0215c5，尚未应用）

本清单是下一包的明确补丁输入；当前没有写入队友仓库、应用补丁、RK编译/安装或发送消息。新FPGA必须同时实现registers.json安全扩展后才允许formal模式；legacy diag不能绕过安全门槛。

| 必改项 | 精确位置与当前行为 | 所需结果/用户态联动 |
|---|---|---|
| CTRL | {loc(header,r'#define ANLOGIC_CTRL_CAM_SEL')}、{loc(header,r'#define ANLOGIC_CTRL_ARM_BITS')}；{loc(link,r'if \(\(ctrl & ANLOGIC_CTRL_ARM_BITS')} | bit4废弃不要求读1；ARM_BITS=0x61；新增CAM_AB=0x100，B读取0xE0..EC；bit2只作reinit toggle。cam_grab顶部旧bit4说明与常量同改，见{loc(cam,r'0x44 CTRL')}。 |
| 槽偏移/容量 | {loc(frame,r'hdr_bytes = sizeof')}、{loc(frame,r'stride = .*PAGE_ALIGN')}、{loc(frame,r'size = .*stride')} | 保留16B struct，hdr_bytes=128，前缀padding112B清0，slot_bytes=2592768，width1920/height1080，slots必须=1；运行时PAGE_SIZE核对，安全算stride/size无溢出，非法参数返回错误而不静默夹紧。4KiB时stride2596864/size2600960。 |
| 地址编程 | {loc(link,r'dst = \(u64\)hw->frame_phys')}、{loc(link,r'ANLOGIC_BAR_PUSH_DST_LO_OFF, dst_lo')} | 使用dma_alloc_coherent返回的PCIe DMA地址，不用CPU物理地址替代；dst=base+128；db=base+mb_off+offsetof(push_dbell)=base+2596864+32；低/高地址均写读回。限制任意PUSHCFG到授权分配且禁busy/held改有效配置，见{loc(link,r'cfg.flags & ~\(ANLOGIC_PUSH_CFG_SET_DST')}。保留64bit carry测试。 |
| 默认禁推/安全扩展 | {loc(link,r'anlogic_pci_link_ctrl_update\(hw, ANLOGIC_CTRL_ARM_BITS')} | 禁自动CTRL模式即持续DMA；先验证EXT_MAGIC=0x31414B52/EXT_VERSION=0x10000，确认BAR映射长度>=0x120（原WIN_END只有0xD0），配置CAP_BYTES/SESSION及地址，校验MPS>=128、single slot，再ARM_ONE_SHOT；旧peer扩展读DEAD_BEEF必须拒绝。 |
| 发布/回收 | {loc(frame,r'done = READ_ONCE\(mb->push_dbell\)')}、{loc(frame,r'WRITE_ONCE\(hdr->len')} | 保留READ_ONCE+dma_rmb；完成只表示传输终结，完整R10F检查后才COMPLETE；len语义为本次DMA有效传输范围dma_bytes，解析以R10F payload_bytes截取。held时禁止覆盖。用户态校验/保存完成才匹配ACK_SESSION/ACK_SEQ并ACK_RELEASE，之后再ARM下一帧。无ACK接口时只能一次传输后停住；不能用sleep/两次seq替代消费授权。 |
| 严格解析 | {loc(rust,r'let src = .*info.hdr_bytes')}、{loc(rust,r'if copy > info.slot_bytes')} | 使用返回hdr_bytes；非法len拒绝，取消夹紧后当成功的路径。用R10F magic/version/header128/format0/codec0/valid_bits10/packing0、geometry/stride/raw=payload、flags、session/seq及三CRC验证，要求dma精确长、所有尾填充0；未知codec拒绝。ROI/Bayer只能按验证过的源模式解释。 |
| 生命周期 | {loc(link,r'ctrl & ~ANLOGIC_CTRL_PUSH_EN')}及卸载/removed路径 | close/unload/link reset时CANCEL→等待busy/draining清零→屏蔽bus master/确认设备不再DMA→释放coherent内存；停止不可仅清push mode就马上free。重连用新session，拒绝旧doorbell/ACK/DDR响应。 |

保持现有ioctl编号与结构体布局，包括16B槽头与64B mailbox。新ACK可经现有受锁保护的BAR控制ioctl封装，不把新字段塞进旧结构体引起32/64bit ABI漂移。新字段宏、扩展窗口、safe arm helper及Rust parser/ack wrapper在后续补丁一次交付；此包不声称已有可运行补丁。

RK执行前由操作者提供真实设备BDF、driver/kernel提交、uname/getconf PAGE_SIZE、PCIe MPS及DMA mask/IOMMU状态；这些是需要采集的事实，不预设RK IP或COM号。目标板实收验收：同一冻结bit/driver至少100帧，长度/逐样本/CRC/seq/session一致，坏帧不发布，慢消费者不覆盖，恢复1次；10min短稳独立记录计数和帧率。此处均为后续操作验收，当前not_run。

先执行contract/check_contract.py确认离线向量，再由后续包产生并apply-check精确patch；不要现在将本清单的建议当上机结果。
'''))

write('backup/restore.md','''# 可恢复备份与回退

baseline-manifest.json为根tracked+本轮前nonignored untracked的实际字节清单，含上一run的未提交/未跟踪文件；all-refs.bundle保存Git refs/历史；dirty.patch保存HEAD到当前tracked差异。原工作树未stash/reset/clean或覆盖。归档不是只备HEAD。Git ignored文件不在源码备份范围；本任务新输出目录明确排除以免递归。baseline的excluded逐项列出本轮排除入口，没有删文件。

tracked-worktree.zip和untracked-worktree.zip在项目相对路径恢复；rollback-002820.zip含旧D盘input_manifest的220项、manifest本身、工程AL、bit/CWC与关键原生结果JSON，共228项；不复制历史DB。zip内每项原始SHA及archive整体SHA均在baseline-manifest，原回退input_manifest逐项核对无差异。bit入口原位D:/TD/work/csi2/prj/camera_rgb565_wb_20261015_002820/camera_ddr_display.bit，配对CWC同目录camera_ddr_display.cwc；本轮归档内同名字节相同。

实际git bundle verify已exit0，原日志bundle-verify.log。首次恢复到restore-check遇Windows MAX_PATH，保留该未完成目录与失败说明，不删除。第二次使用Windows扩展路径\\?\\在全新restore-check-v2恢复，3107项（2879根+228回退）全量SHA通过；baseline.restore_check给出准确路径。验证脚本evidence/build_baseline.py和baseline-run-02.log留存。root main-log.md由主并发写入，原字节仍在初始zip，另有stable-retake按稳定两次读取保存；漂移明确登记，不能把当前动态日志与初始字节混作同一时点。

人工恢复时先选新的空目录，使用Windows扩展绝对路径或未占用subst别名避免长路径；按zip member名单逐个写入新目录并复算SHA。任何绝对路径/..或链接member必须拒绝。先核对所有listed SHA和zip整体SHA、git bundle verify，再可在新目录git clone all-refs.bundle并选原branch；根zip还原实际dirty内容到该新目录。不得把归档直接覆盖当前dirty工作树。当前所有恢复副本只是验证证据，无生产角色。

硬件回退仅由持有硬件窗口的system角色按授权选择上面的既有002820 bit及匹配CWC；本包没有加载它。002820已归档历史G1与所选G2证据，颜色G3/G4仍待验证，不能称全系统已通过。此备份包含厂商IP/私有peer，不公开上传。

不执行任何批量删除。恢复/校验需要空间不足时保留现有产物并交规划者处理，不能自动清理。
''')

write('artifacts/next-backend-input.md',render('''# T07.rk-align-backend的固定输入

本文件仅提供下一包输入，不在本包执行。允许新目录由规划dev-plan/dispatch重新确定；旧源码、D盘工程和peer参考均只读。以references/provenance.json的168个FPGA文件与24个driver文件为准，匹配生成IP不可从别的PCIe版本拼接。

模块/IP/约束入口：peer `create_project.tcl`逐条add_files包含EP top/engine/int_handle、img BAR/regs/frame_src、cam前端、ddr_frame_pusher/cam_ddr_writer/ddr_wr_arb、uart/ubus、constraints .adc/.sdc和al_ip下pcie_ep_core、pcie_pll_ep、ram、ddr3_mc_0四个xml及全量引用内容。具体清单见`artifacts/backend-input-files.json`（仅静态解析，未运行peer脚本）。DDR当前参数DDR3-800E、PH1P_REF_CLK50、AXI地址29位/数据256位、PAXI0；实际板内DDR容量必须从匹配IP配置/器件证据确定，不以29位总线宽当容量授权。独立candidate使用这个后端，不把旧PAXI接口套上AXI。

本方checked接入不能只复制文件：保持peer PHY/byte align/word align/gearbox，输出I_clock/I_reset_n/I_enable/I_data[31:0]/I_data_valid连到csi_rx_packet_integrity，正确设置VC/RAW10 DT/实际WC与行数。其O_payload_out[31:0]/O_payload_keep[3:0]/O_payload_valid及O_in_line送csi_rx_10bit_unpack_checked，I_clock/I_reset_n/I_enable在同域；O_data_out[39:0]四个10bit样本和O_dout_valid送新增RAW10 packer/ROI/DDR完整帧控制。O_vsync_out/O_in_frame与O_frame_end/O_frame_good/O_frame_abort、错误计数/last_wc/last_lines必须接入帧裁决及诊断。旧csi_rx_packet_handler_checked只做头/WC包装而没有CRC整帧good/abort端口，不能将其单独接上就声称完整性合格。三个本方文件冻结于references/local-inputs；当前f9p_camera_capture_core cap_data是预览字节，不能作为RAW10正式源。

像素为speculative直到selected FE且完整WC/行数/CRC/ECC/超时通过；延迟后的4px valid与SOF/EOL/EOF裁决要逐拍配齐，尾组在unpacker流水排尽后才能确认complete。CSI不可反压，FIFO满/abort拒整帧而不是发布残片。source ownership为writing→complete→held_for_tx→released；两路每次各自缓冲持有，不依赖peer固定双缓冲轮换窗口。source descriptor（camera/session/seq/base/dma_bytes/CRC）必须原子跨域并锁存。Gray8 peer W*H不能代替RAW10 packed。

后端必修的已知风险与源码：pusher {loc(pusher,r'if \(utx_sel && beat_present && tl_tx_wait\)')}的超时只标flush，必须审查开放TLP期间持续stall与CPL仲裁（帧长timeout不能截半包）；{loc(pusher,r'wire\s+start\s+= push_en')}持续新seq启动未有容量/ACK授权；{loc(pusher,r'addr_q\s+<= .*dst_hi, dst_lo')}已有dst64/doorbell锁存应保留并补齐授权/会话/cap/长度/源base；{loc(pusher,r'm_axi_araddr\s+<= base_s2\[28:0\]')}会截高位，必须先拒绝非法高位及溢出；{loc(pusher,r'S_DRAIN: begin')}source FIFO排空必须有源故障/取消恢复边界，不允许旧会话响应污染下一次。4DW地址高32为0时的格式选择与RC/MPS需按规范处理，不能把peer注释当可发布资格；DW-valid=F0头、FF数据、F8单DW门铃，绝不是byte keep，字节序与BE由TLP oracle独立核对。

registers.json提出0x100..11C容量/session/one-shot/ACK扩展，当前NOT IMPLEMENTED。原0xD0..F4已有诊断，不能占用冲突。下一包须同步扩展BAR及RK匹配补丁，默认cap/session/armed=0，旧驱动0x71和原+16必须负例失败。CPU已分配DMA地址/大小、source DDR容量、门铃边界、MPS128与4KiB都检查。模式CTRL=0x61不能隐式授予持续DMA。

构建：使用D:/anlogic/TD_Release_2026.2/bin/td_commands_prompt.exe，版本实查6.2.3.210850/Tcl8.6.17。peer create_project.tcl会直接reset/launch，因此只作审查输入；在新candidate复制且改为明确分阶段脚本后才运行，禁止执行download_sram.tcl。TD cwd/./正斜杠为约定。中文长路径用未占用subst盘符映射本run/candidate，记录目标、命令与撤销；实际所有写入仍在项目。只用新映射，不触D盘旧工程。G2最终setup>=0/hold>=0/TNS0、约束/CDC/资源/引脚/IP及同DB报告bit哈希齐备后，另包system独占SRAM板测。

peer TB参考调用（本包未跑）：在隔离副本sim_do目录按include路径修正调用iverilog -g2012 -o <本包输出>/pusher.vvp tb_ddr_frame_pusher.v ../rtl/ep_side/ddr/ddr_frame_pusher.v，再vvp并要求ALL PASS；writer/arb/BAR测试台同理。peer TB头部声称只写不跑不能当已验证；它的旧+16/小几何/无ACK覆盖要新增负例和实际128B/完整1080p边界。当前PATH未发现iverilog/vvp，verilator脚本与gcc存在，实际运行版本见tool-inventory；工具缺口应交规划补条件而非绕过验证。并列使用本方parallel/pcie的PCIT/TLP oracle（下一包按依赖精确列入manifest）。

硬件：只枚举发现FTDI VID0403/PID6042双通道，尚未JTAG扫描确认器件；COM3/4为蓝牙，不能当板UART/RK。BW CLI存在但未执行加载；无RK地址/BDF/控制通道。system后续先识别连接/回退bit/独占窗口，再同候选G2与唯一bit执行已授权SRAM；Flash、未知远程主机操作不授权。
'''))

inputs=[]
for i,line in enumerate((RUN/(F+'create_project.tcl')).read_text(encoding='utf-8').splitlines(),1):
 if line.startswith('add_files '):
  rel=line[len('add_files '):].strip();p=RUN/F/rel
  inputs.append({'path':F+rel,'source_line':i,'exists':p.is_file(),'sha256':sha(p) if p.is_file() else None})
dump(RUN/'artifacts/backend-input-files.json',{'project_script':F+'create_project.tcl','entries':inputs,'script_executed':False})

inventory=json.loads((RUN/'evidence/tool-inventory.json').read_text(encoding='utf-8-sig'))
write('evidence/hardware-access.md','''# 本轮工具/硬件接入事实

实际命令：PowerShell evidence/inventory.ps1，在本项目工作目录执行；退出0。读取新TD绝对二进制SHA，临时新建U:→本run/evidence/td-probe，运行 ./probe.tcl，仅查询命令注册。stdout.log横幅实查TD Release_2026.2 / build6.2.3.210850、Tcl8.6.17，11项命令REGISTERED，READ_ONLY_CLI_PROBE_OK，非空日志。U:映射在finally撤销，原subst为空。没有工程构建/IP生成/位流下载。IpTool.exe SHA=5b0654aaa44ae9340eefcdc8cac54faed7490b0643f3fa53908c5706db175cec；本轮查二进制，未重做旧DDR1333试验。

可复用既有成功：docs/evidence/td2026_ipgen_20261016.json step1_smoke_simple_ip（APB_GPIO smoke）记录IPT-1001 target generated successfully，以及同文件6.2.3 scratch端到端回归。这里仅引用其工具入口证明，非本轮重跑；旧DDR1333 staging失败只属于DDR1333具体配置，不宣称CLI/IP Tool普遍不可用。用户本轮说明已可CLI IP Tool优先保留。详见本包evidence/tool-success-reuse.json的精简摘录与源文件SHA，未发送凭据/环境内容给worker。

只读设备查询：Win32_PnPEntity筛选FPGA相关USB，发现USB Serial Converter A/B及USB Composite Device，VID0403/PID6042，均StatusOK/error0。尚未执行JTAG链扫描，不能仅凭枚举确定PH1P100器件/加载通道。Win32_SerialPort仅列COM3/COM4蓝牙链接标准串口；未打开端口、未假定板UART或RK。BW bw.exe/bw_commands_prompt.exe存在并已哈希，可供下包system只读查询后选用。没有访问任何RK主机、SSH/安装/重启或认定IP。

G2/G3/G4/G5在本备份合同包不适用，实际板验not_run。下一硬件包所需：实际链上器件和可用BW读写入口、system独占窗口/电源状态、同候选最终G2、唯一bit及匹配CWC（若含）、回退002820身份。RK实收还缺实际通道/BDF/内核/driver/MPS/IOMMU/PAGE_SIZE；缺失不阻塞离线后端包，但不能宣称DMA实收。
''')
prior=ROOT/'docs/evidence/td2026_ipgen_20261016.json'
data=json.loads(prior.read_text(encoding='utf-8-sig'))
dump(RUN/'evidence/tool-success-reuse.json',{'source_path':prior.as_posix(),'source_sha256':sha(prior),'scope':'existing tool entry evidence, not this-run reproduction','sections':{k:v for k,v in data.items() if k in ('tool','step1_smoke_simple_ip','step3_cli_regression','environment')},'result_line':'IPT-1001 : The target has been generated successfully.','note':'source key names preserved when selected; see frozen root archive for full evidence, no credentials copied into this excerpt'})
dump(RUN/'evidence/deepseek-text-extraction-review.json',{'task_id':'648ae8308e294099b121fe77cbee1132','status':'completed','delegated':'header excerpt only -> mailbox/slot offsets and literal CTRL macros; no command requests, no file access or architecture decisions','source':header,'review':'Independently counted nine u32 fields including push_dbell at index8=32B; reserved[7] gives64B. Slot four u32 gives16B. Legacy macros ARM includes bit4=>0x71; actual pinned RTL reserves bit4. Worker closing explanation incorrectly said nine preceding fields; rejected that wording. Only offset32/size16/literal constants accepted after native ctypes verification.','verification':{'mailbox_push_dbell_offset':32,'mailbox_bytes':64,'slot_header_bytes':16},'usage_total_tokens':4427,'pending_call_ids':[]})
write('lessons-learned.md','''# T03.rk-align-freeze lessons

- 临时参考checkout可能落后于已核对Git对象；所有证据从精确commit的git archive取，不从mutable文件名推断版本。
- Windows恢复路径叠加run目录可超过MAX_PATH；首次失败保留，使用新的扩展路径恢复目录并逐项SHA校验，不能只看zip生成成功。
- host16B槽头结构、host hdr_bytes=128传输偏移和R10F128B头是三个量；CRC按有效内容与DMA尾零分层。+16每4KiB有一笔128B MWr跨界，+128只是对齐条件，还需容量/所有权。
- 工具新版本用绝对二进制+启动横幅/命令注册核实。旧DDR1333特定IP失败不能当全CLI不可用；可复用旧成功须限定范围。
- 设备枚举不是板测。FTDI双通道与蓝牙COM号不自动说明PH1P器件/JTAG/UART或RK通道。
- 有界worker只做给定头文件的文本转换，原型/偏移/位义仍由Codex独立验证；completed不等于验收通过。
''')
write('evidence/local-checks.md','''# 局部检查与5.1适用项

工作目录为项目根。实际执行build_baseline.py：首次restore-check在长路径mkdir失败，退出1，归档/bundle未损；修正采用既存原归档+新restore-check-v2扩展路径，第二次退出0，baseline-run-02.log有3107项恢复SHA成功标记。git bundle verify退出0、日志非空。原002820 input_manifest 220项全部匹配，另外8项回退依赖也恢复核验。未动原工程。

inventory.ps1退出0，READ_ONLY_CLI_PROBE_OK，11项注册、版本6.2.3.210850/Tcl8.6.17，映射撤销；USB/串口查询只读。

build_package.py仅生成本run合同/固定输入/合成数据，不写RTL/driver。contract/check_contract.py的实际执行结果保存evidence/contract-check.log与contract-check-result.json；只验证合同公式与合成协议向量，不代表DUT测试。最终输入保护校验与候选哈希由freeze_candidate.py保存。

5.1：①冻结本包实际文档/脚本/上游输入/合成向量及SHA，构建约束/IP在固定peer tree；②旧bit4及+16/CRC/长度/坏帧负例可执行；③仅TD只读probe，本包无构建产物要求，明确exit+marker+非空日志；④G2不适用（无生产RTL改动）；⑤未生成含ChipWatcher新候选，CWC校验本包不适用，旧配对只备份不重验；⑥三个独立审阅由主后续派发，当前未完成；⑦唯一旧回退入口与未测边界见restore.md，本包无新bit；⑧本包无提交/发布授权动作，未同步私有GitHub。此处不虚填三测试PASS或板测。
''')
print(json.dumps({'package_created':True,'datasets':datasets,'registers':len(regs),'extension_registers':len(extension),'local_snapshots':len(local)},ensure_ascii=False))
