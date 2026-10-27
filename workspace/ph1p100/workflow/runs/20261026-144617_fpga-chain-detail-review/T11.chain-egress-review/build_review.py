from pathlib import Path
import csv, hashlib, json, sys, datetime

OUT = Path(__file__).resolve().parent
RUN = OUT.parent
ROOT = RUN.parents[2]
assert ROOT == Path('D:/fpga/ph1p100')
def readj(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def putj(name, obj): (OUT/name).write_text(json.dumps(obj, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def put(name, text): (OUT/name).write_text(text.strip()+'\n', encoding='utf-8')
def csvout(name, rows):
    with (OUT/name).open('w', encoding='utf-8-sig', newline='') as f:
        w=csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

base=readj(RUN/'baseline/source-manifest.json')
sources={'B'+Path(x['snapshot_path']).stem:x for x in base['files']}
for x in readj(OUT/'inputs/supplemental-sources.json'): sources[x['source_id']]=x
deps=['T02.chain-input-review','T06.chain-storage-review','T10.chain-transform-review']
dep_findings=[]; dep_bindings=[]; aliases={}
dispatch=readj(OUT/'controls/dispatch.json')
for t in deps:
    m=RUN/t/'manifest-r0.json'; report=RUN/'test-reports'/f'{t}-r0-integrated.md'
    exp=next(x for x in dispatch['completed_dependencies'] if x['task_id']==t)
    assert sha(m)==exp['manifest_sha256'] and sha(report)==exp['report_sha256']
    assert report.read_text(encoding='utf-8-sig').startswith('### 判定：PASS')
    for e in readj(m)['files']: assert sha(e['path'])==e['sha256'],e['path']
    dep_bindings.append({'task_id':t,'manifest_path':str(m),'manifest_sha256':sha(m),'report_path':str(report),'report_sha256':sha(report),'scope':'accepted read-only audit only; no DUT/board PASS'})
    sm=readj(RUN/t/'source-map.json')
    inherited=sm['sources']
    entries=inherited.items() if isinstance(inherited,dict) else [(e.get('source_id',str(i)),e) for i,e in enumerate(inherited)]
    for sid,e in entries: aliases[t+':'+sid]=e
    dep_findings += readj(RUN/t/'findings.json')['findings']

def ref(sid,lo,hi,reason):
    s=sources[sid]; return {'source_id':sid,'snapshot_path':s['snapshot_path'],'sha256':s['sha256'],'line_start':lo,'line_end':hi,'reason':reason}
findings=[]
def finding(fid,sev,kind,claim,refs,trigger,impact,rec,benefit,cost,valid,default):
    findings.append(dict(finding_id=fid,severity=sev,kind=kind,claim=claim,evidence_refs=refs,reproduction=trigger,impact=impact,recommendation=rec,expected_benefit=benefit,tradeoff=cost,validation=valid,disposition='review_only; implementation_deferred',default_configuration_affected=default))
finding('T11-F01','high','confirmed_issue','UART导出E_OPEN对槽ID/精确长度不符只计错，仍cmp_open并无条件转E_HDR；没有拒绝错误事务。',
 [ref('B0148',403,415,'错误只更新st_err；头发送无guard'),ref('B0148',439,461,'以描述符长度发送并关闭槽'),ref('B0150',838,864,'commit到独立描述符队列及store读口')],
 '模块接口给d_id=7/stream_len=33与cmp_id=8/cmp_len=1，cmp_open_ready=1；E_OPEN仍进入E_HDR。witness/egress_witness.py枚举匹配/不匹配正反例；不是RTL仿真。',
 '错误元数据和另一槽载荷可能被拼接；描述符超出槽最后32B字的容量时可永等rd_valid。与T06排序反例相邻，但默认全尺寸整机可达性未证。',
 '后续使错误ID/长度在任何头字节外发前失败关闭，定义槽归还/描述符丢弃/重新对齐及可观测错误。',
 '阻断已检测到的不一致事务外发；收益是正确性，不报资源百分比。','拒绝恢复状态与超时要和slot/store一起验证。',
 '真实exporter+store RTL注入ID错/len短长、同拍push/pop、reset及后继正常帧；零错误头/零误释放。','not_proven; requires mismatch; normal matching descriptors unaffected')
finding('T11-F02','medium','confirmed_issue','RAW PCIe pusher的claim_base_ok用32bit ddr_base+frame_bytes比较容量，回绕可放行越界源，随后AR地址截为29bit。',
 [ref('B0101',397,403,'32bit加法上界比较且未要求par_valid'),ref('B0101',970,990,'base_s2[28:0]发AR'),ref('B0123',105,122,'默认固定槽及256MiB容量'),ref('B0123',312,324,'默认源来自writer的选定base')],
 'ddr_base=0xfffff000, frame_bytes=4096, cap=0x10000000：32bit sum=0通过；宽精度sum=0x100000000应拒。首AR=0x1ffff000。',
 '模块声称的容量拒绝不成立；默认writer固定低地址不触发，不能写成默认板上越界或缺R根因。',
 '后续在边界用扩位加法并检查base范围/所选槽白名单，再截29bit；保留主机目的64bit独立检查。',
 '使所有接口输入的源边界检查可验证。','扩位组合逻辑与更严格拒绝，需确认合法基址。',
 '独立扩位算术及真实DUT边界0/cap-4096/cap/0xfffff000，默认槽为正控制；验证不发AR且后续恢复。','false_for_frozen_fixed_writer_bases; module_interface_counterexample')
finding('T11-F03','high','evidence_gap','PCIe本地doorbell已被TL接纳及G_HELD不等于RK完成可见；本轮未绑定主机DMA分配/缓存一致性/屏障/读取验证后ACK的同候选证据。',
 [ref('B0101',542,573,'TC0/RO=0头和本地utx_ack'),ref('B0101',733,753,'仅匹配held session/seq才release'),ref('B0101',875,934,'done/HELD依本地接纳而非PCIe Completion'),ref('B0118',333,355,'cap/session与单bit命令')],
 '检索范围为统一快照RAW top/pusher/BAR/RAW合同、旧T09报告及补冻IP；不把旧RK收图反馈当本候选主机证据。',
 '必须区分TL接纳、posted write排序、CPU可见、CPU消费及ACK；FPGA不能仅凭cap寄存器证明DMA地址来自授权分配。',
 '后续绑定实际RK驱动、DMA/IOMMU映射、CPU同步/屏障、session重启与读后ACK协议；保留HELD保护。',
 '防主机读到旧内容及过早重用；可定位责任边界。','增加端到端证据和主机动作，不能靠删ACK减少复杂度。',
 '同候选真实主机核对payload/header/seq/CRC，延迟/错/旧session ACK、PERST/re-enumeration和并发重复窗口；G2–G5授权另行。','unproven_for_current_hardware')
finding('T11-F04','high','evidence_gap','A+ UART与RAW/R10F PCIe是分离分支；压缩帧级codec/外头、精确长度至DMA对齐、描述符与完成ACK尚未实际接入该PCIe top。',
 [ref('B0150',830,866,'A+ commit只驱动UART exporter'),ref('B0123',1515,1544,'PCIe top使用cam_r10f_writer'),ref('B0098',440,464,'codec=0且raw_bytes=payload_bytes'),ref('B0123',1712,1726,'RAW pusher及默认4KiB服务')],
 '按两份实际top/编译入口实例追踪，无三算法→A+→R10F压缩DMA通路；不是仅按文件名搜索。',
 '不能以A+能压、RAW PCIe能传或旧RK能收组合成双路压缩生产闭环。stored回退仍是变换域zlib，不是codec=0 raw。',
 '后续先冻结压缩接口和codec版本/头长/每帧容量/取消/ACK，再选择生产接入，保持现RAW兼容。',
 '消除跨分支假设，形成可验端到端边。','协议、顶层、缓冲和RK解码均需联动验证。',
 '同冻结manifest真实DUT与主机解码后的源像素oracle、最坏回退/尾字节/模式错拒收；不能只改codec_id。','true_as_missing_integration; no_claim_of_runtime_failure')
finding('T11-F05','medium','evidence_gap','UART st_exported/close在最后payload装入本地holding寄存器后即可发生，既非末stop-bit已离线、亦非PC消费确认；没有传输ACK/重试事务。',
 [ref('B0148',334,344,'单拍请求及busy定义'),ref('B0148',449,461,'sent加1后P_DONE与close'),ref('B0148',210,222,'下一帧边界确实等待tx_ready'),ref('B0148',513,519,'holding独立于slot')],
 '最后byte复制到tx_byte_r→sent达标→P_DONE→close；UART busy仍可能为1。本地轨迹见witness，不宣称已发生丢字节。',
 '槽最后字节已被复制，早释放本身未证明破坏数据；但exported不能用于整帧主机成功率/吞吐或掉电安全证明。',
 '后续明确本地queued/wire_done/host_accepted计数语义；若要求可靠传输，另冻结ACK/重试/epoch。',
 '计数与真正完成事件一致，降低诊断误判。','增加计数/协议需要独立验兼容性。',
 '观察末byte请求/last stop-bit/close各时刻，重置/断线注入及PC完整CRC判据；保留独立holding。','true_for_counter_semantics; no_proven_slot_corruption')
finding('T11-F06','medium','evidence_gap','已补冻PCIe实际生成wrapper/工程入口，端口是256bit数据+8bit tl_tx_valid+tl_tx_wait，无32bit byte_keep；但该当前源不能追认旧bit完整IP身份和真实TL接纳/CDC签核。',
 [ref('E02',1,14,'生成TD版本6.2.174248'),ref('E02',76,103,'DW有效端口和LINK_WIDTH=2'),ref('E01',310,334,'实际pusher/writer工程源'),ref('E01',360,368,'工程XML IP入口'),ref('B0123',633,641,'top直连IP')],
 'E01–E05副本前后SHA一致；生成器元数据1.0/171484 2025-08-11与wrapper TD6.2.174248分别记录，不能当当前安装版或旧bit签名。',
 '字节keep假设会错解F0/FF/F8；封装版本存在只构成来源证据，不证明本候选板级性能。',
 '后续在生产manifest补全生成IP/加密内部/参数/约束/bit绑定及真实TL语义/背压/复位证明。',
 '避免错误IP适配和跨版本混证。','完整闭包需未来G2/板级窗口，当前只读审查不运行。',
 '厂商定义及真实IP RTL/TL monitors独立确认DW方向/F0/FF/F8、stall数据稳定、复位和重连。','qualification_gap')
finding('T11-F07','high','evidence_gap','P1080必须计入R10F 128B头/640B尾零、128B载荷TLP的16B头及门铃；UART和93.75MB/s代理sink不足以证明生产双路。',
 [ref('B0098',153,167,'R10F精确payload和4KiB DMA'),ref('B0101',234,241,'默认128B/TLP与4KiB burst'),ref('B0101',542,570,'4DW头和1DW门铃'),ref('B0123',1712,1718,'实际默认参数'),ref('B0283',1,20,'旧scope必须保留')],
 '见witness/result-r0.json独立整数算术：R10F DMA=2592768B，20256个128B MWr，TLP总=2916884B/帧（含20B门铃，不含DLL/PHY）。',
 '双路TLP预算175.01304MB/s；b15四次DDR预算809.0304MB/s。不同路径预算不得相加成一个已接入实现或以压缩平均值代最坏。',
 '后续用真实内容/生产slot-free/fast sink与共享DDR签核；本轮不重复另一活动run四帧矩阵。',
 '准确定位吞吐瓶颈与最坏容量。','需要实测持续服务和资源/时序，队列加深不能增加长期服务率。',
 '独立整数重算，真实DUT和共享服务率/背压/坏帧恢复矩阵；保留成本offset前提与CMP14B余量缺口。','budget_gap; no_measured_rate_claim')
finding('T11-F08','low','redundancy_candidate','UART源码头/中段仍写诊断v3=177B/43字段，实际常量v5=241B/59字段；维护性收口可行，不能把旧文档副本数当硬件冗余。',
 [ref('B0148',36,56,'旧v3注释'),ref('B0148',204,235,'真实v5参数与59字段snapshot')],
 '对比STS_LEN=241、STS_VER=5和4+59*4+1=241；不用旧注释指导解析。',
 '旧布局可能误导人工/新工具；本轮未证实已有PC parser按旧布局失败。',
 '后续将协议布局放单一版本来源并同步注释/解码器；FIFO/skid/CRC/Adler/row-bank均不直接删除。',
 '减少维护歧义；无资源百分比收益。','须留版本兼容和解码回归。',
 'v3/v4/v5录制向量与实际v5字段/XOR对照；综合网表差分后才谈资源。','true_for_comment_mismatch; parser_runtime_not_proven')
finding('T11-F09','info','no_issue_found','限定当前PAY_DW=32/BURST_BEATS=128与对齐前提，默认TLP不跨4KiB且≤最小128B MPS；BE/DW-valid、冻结ARM/匹配ACK及槽持有有明确实现。',
 [ref('B0101',542,604,'全DW数据F0/FF、门铃F8及BE=f/0、ARM检查'),ref('B0101',733,795,'session/seq保护和cancel状态'),ref('B0101',909,950,'HELD到ACK才释放'),ref('B0123',1712,1722,'冻结默认参数')],
 'witness枚举全部32种128B对齐页内偏移；每个payload+offset≤4096；mps_code0..5最小128B。只检查真实默认值，不推广任意PAY_DW。',
 '本地静态算术未发现默认包界矛盾；host可见性、IP真实stall/CDC、同时命令优先与重置晚响应未做RTL/硬件签核。',
 '保留ACK/HELD/FIFO/读持数及错误计数；后续扩参数需重新证明BE、MPS、尾包和4KiB。',
 '保留已有安全边界与可追溯接受事件。','真实DUT/host验证仍需授权。',
 '测试者用不同判据复核包字段、对齐及扩位边界；生产未来随机stall/reset、旧ACK、cancel和link重启。','default_static_scope_only')
putj('findings.json',{'task_id':'T11.chain-egress-review','round':0,'findings':findings})
putj('source-map.json',{'task_id':'T11.chain-egress-review','baseline_manifest':str(RUN/'baseline/source-manifest.json'),'baseline_manifest_sha256':sha(RUN/'baseline/source-manifest.json'),'sources':sources,'inherited_source_aliases':aliases,'dependencies':dep_bindings,'compiled_tops':{'b15':'B0155 -> p2_a1_board_top, changed-src camera/A+/UART','RAW_reference':'E01 -> ph1p_pcie_ep_top, B0098/B0101/B0121/B0123 and E02–E05 IP','algorithm':'B0123 separate cam_algo_diagnostics; not A+ input','offline':'inherited isolated sync/recovery; not b15 integration'},'candidate_boundary':'Supplemental current project/IP source copies do not retroactively authenticate old bit; no new build.'})

# These are semantic checkpoints within this package, not additional tasks.
checks=[
('C01','branches','A+ commit','UART exporter','B0150',830,866,'44B A1U1 + exact zlib bytes','clk_a1=clk_uart frozen board','a1_commit then desc_push','CMP slot + descriptor','actual UART branch only','reset clears descriptor; no host ACK','evidence_gap','T11-F04','Freeze future compressed PCIe interface'),
('C02','lengths','A1 metadata','A1U1 header','B0148',238,266,'raw/xform/zlib each bytes; W/H pixels','A1 domain','descriptor dequeue at grant_frame','one latched descriptor','magic/version/profile/44B LE header are distinct from R10F','reset cancels local stream','no_issue_found','T11-F09','Independent header byte order parser'),
('C03','crc','header byte mux','UART header','B0148',418,435,'CRC32 bytes0..39; crc at40..43','A1 domain','!tx_valid_r && tx_ready','local header state','byte39 included before crc_fin emitted','partial external frame requires PC rejection','no_issue_found','T11-F09','Compute IEEE reflected CRC independently'),
('C04','ownership','descriptor','CMP read slot','B0148',403,415,'ID and exact stream_len bytes','A1 domain','cmp_open_ready -> cmp_open','store owns selected READY slot','ID and length must match before any external header','mismatch merely counts; fails open','confirmed_issue','T11-F01','Inject wrong ID and short/long length'),
('C05','payload_tail','CMP 256bit word','UART byte','B0148',439,461,'32B storage word -> exact sent bytes','A1=UART for actual integration','rd_valid/rd_take then one byte request','holding register copies before slot close','no storage alignment bytes beyond stream_len','long wrong descriptor can wait indefinitely','confirmed_issue','T11-F01','Partial-word lengths 1/31/32/33 with mismatched slot'),
('C06','diagnostics','status snapshot','UART frame boundary','B0148',204,235,'v5 241B=4+59*4+1; XOR8','A1 domain','grant_status exclusive grant_frame','atomic allsnap','status never inserted into frame payload','status sticky waits next boundary','redundancy_candidate','T11-F08','Versioned diagnostics parser and boundary stall'),
('C07','completion','local last-byte request','exported/close','B0148',449,461,'sent bytes not host-delivered bytes','A1 and same UART clock','P_DONE after sent reaches len','last word already copied','local counter != wire/PC acceptance','reset/line fault no reliable replay','evidence_gap','T11-F05','Observe close, last stop bit, host parse separately'),
('C08','queue','A+ commit producer','descriptor FIFO','B0148',210,222,'two entries; count accepted events','A1 domain','desc_push && (!full || grant_frame)','two store slots two descriptors','same-cycle full pop may accept push; no unconditional queue loss proof','reject counted; future recovery required','no_issue_found','T11-F09','Full simultaneous push/pop and upstream commit cancel'),
('C09','RAW_header','sample lanes','R10F writer','B0098',435,464,'128B LE; codec0; RAW10 packed stride2400','cam->DDR->TL CDC per branch','payload word_take + final good+B','per-camera double slots','payload/raw CRC exact packed only; header crc self field zero','bad frame does not qualify published; inherited EOF-full gap','no_issue_found','T11-F09','Independent header/CRC and final B qualification'),
('C10','DMA_padding','R10F valid bytes','RAW pusher','B0098',153,167,'2592000+128+640=2592768B DMA','DDR writer / TL reader','published DMA length','slot retained through TX/HELD','tail zeros excluded CRC and payload_bytes','do not confuse content and allocated length','no_issue_found','T11-F07','Independent ceil4096 and CRC exclusion'),
('C11','publication','R10F writer final rewrite','readable slot','B0098',945,977,'4KiB payload bursts +32B CRC header rewrite','DDR then publication CDC','final rewrite B tracked via rw_done_r','protected double slot','header rewrite visible before publication; inherited T06 contract','B error rejects; reset/late responses remain unproved','evidence_gap','T11-F03','Reuse T06 audit and bind actual B/CDC candidate'),
('C12','IP','RAW TL mux','generated PCIe wrapper','E02',76,103,'256bit/8 DW-valid; no 32B byte_keep','tl_clk_user reset/link conditions','selected TL valid && !tl_tx_wait','TLP arbitration retained to EOP','F0/FF/F8 describe valid DW not byte keep','real IP/backpressure/reset evidence limited','evidence_gap','T11-F06','Vendor/real-IP DW lane monitor; old bit binding'),
('C13','TLP_header','pusher','TL data','B0101',542,571,'4DW MWr address +32DW payload; oneDW doorbell','TL user domain','utx_sel && !tl_tx_wait && beat_present && beat_ready','one packet until last_k','BE=f/f data; f/0 doorbell; RO=0/TC0 source bits','cancel drains outstanding packet','no_issue_found','T11-F09','Decode DW0/DW1/address/BE and byte swap'),
('C14','MPS_4KiB','ARM config','TLP segmentation','B0101',593,604,'frame multiple4096; dst align128; fixed128B TLP','TL user domain','valid ARM + later claim','ARM latched descriptor','128B fits smallest accepted MPS code0..5 and aligned page','malformed ARM rejected','no_issue_found','T11-F09','Enumerate32 alignments and MPS codes; no generic params claim'),
('C15','host_bounds','host registers','ARM latch','B0101',376,382,'64bit dst+frame; cap bytes; separate db 4B','TL user domain','arm_reject gate','latched dst/db/cap/session','nonzero/alignment/cap/wrap/no-overlap checked','no proof address is actual host allocation','evidence_gap','T11-F03','DMA map/IOMMU authority and overflow controls'),
('C16','source_bounds','published DDR base','AR29','B0101',397,403,'32bit base/len ->29bit DDR byte address','TL->DDR synchronized descriptor','claim_base_ok then claim','selected source slot','wide base+len<=capacity required before truncation','32bit addition can wrap','confirmed_issue','T11-F02','0xfffff000+4096 and fixed default base positive cases'),
('C17','authorization','BAR ARM/cap/session','safe gate','B0118',333,355,'cap/session u32; onehot W1 command','TL user domain','exact command bits; cap/session only IDLE','frozen ARM descriptor','cannot mutate active latched address by later BAR writes','cfg rejects and errors; FPGA does not certify host memory allocation','no_issue_found','T11-F09','Wrong onehot/session/cap and active config writes'),
('C18','visibility','last payload TL accept','doorbell then HELD','B0101',857,881,'posted MWr data then singleDW seq','TL user domain','each utx_ack; db_sent after local doorbell accept','HELD retains source','local done is not host memory read completion','late/link failures require host recovery','evidence_gap','T11-F03','Host coherent DMA / read-before-ACK / ordering evidence'),
('C19','ACK','host ack_seq/session','slot release','B0101',733,753,'u32 held seq + nonzero session','TL then per-slot release CDC','G_HELD && matching both','HELD owner=host until ACK/CANCEL','bad ACK leaves held slot untouched','session reuse/wrap needs bounded lifecycle','no_issue_found','T11-F09','Delay/wrong/stale ACK and session restart'),
('C20','cancel','host CANCEL','drain/release','B0101',756,795,'finish current TLP then drain','TL/DDR reset domains','singlebit cancel pulse','G_TX->G_DRAIN; G_HELD release','never truncate issued TLP intentionally; no success for cancel_r path','same-cycle final doorbell/cancel and reset need RTL proof','evidence_gap','T11-F03','At HEAD/DATA/TEND/doorbell WAIT inject cancel and PERST'),
('C21','reset_retry','link/reset','AXI/TL/session','B0123',510,524,'PERST/link qualified tl reset distinct power_on_rst_dly','TL and DDR independently','rst_sync and top selected pusher rst','cleared ownership vs late in-flight I/O','must not pair old response/ACK with new session','old real IP/CDC/host drain evidence absent','evidence_gap','T11-F06','Unplug/re-enumerate/late R/clock stop; no hardware in this audit'),
('C22','compression_gap','A+ output descriptor','R10F/DMA hypothetical','B0123',1515,1544,'A1U1 zlib != R10F codec0 packed','different tops/clocks/candidates','no actual common acceptance event','no shared compressed DMA ownership contract','must freeze version/length/padding/CRC/ACK before integration','cannot repair by codec_id edit alone','evidence_gap','T11-F04','Future real producer->consumer integration oracle'),
('C23','branch_gap','Y8 three algorithms','A+ raw encoder','B0123',1805,1814,'Bayer->RGB->Gray/Gauss/HE diagnostic results','independent diagnostic branch','diagnostic sink not codec input handshake','independent row banks/obuf','processed Y8 not original packed Bayer','dynamic mode mux absent per T10-F08','evidence_gap','T11-F04','Reuse T10 mapping; freeze metadata before mux'),
('C24','late_verdict','CSI good/abort','publish->encode->export','B0150',838,849,'capture/admission/export IDs differ','camera/CDC/A1','ROI-last then a1_commit is not final CSI good','WRITING/READY/READING conflict inherited','CRC self-consistency cannot confer source good','late abort cannot revoke READY; samecycle commit F02 inherited','confirmed_issue','T11-F04','Cross-package late bad/cancel negative frame must never reach descriptor'),
('C25','throughput','1920x1080p30 raw','single/dual sinks','B0098',153,167,'77.760/155.520MB/s packed; R10F/TLP separately','budget not measured clock','30 complete good frames/s desired','queues finite','long-term service must exceed worst sustained input','finite queue depth cannot fix overload','evidence_gap','T11-F07','Independent overhead budget and real sustained sink'),
('C26','DDR_budget','RAW+CMP store','shared DDR','B0101',234,241,'four passes; raw20 useful/32 allocated; CMP align32','b15 independent from AXI RAW candidate','each accepted read/write counted','per-source slots','dual b15 budget809.0304MB/s excludes protocol/refresh','address/mask/visibility defects remain; no predicted achieved rate','evidence_gap','T11-F07','Reuse T06 and independent arithmetic; no mixing candidates'),
('C27','legacy','BPR1/Rice and sync tracks','current branch diagram','B0283',1,20,'old codec/version and isolated test tracks','different candidates','only their frozen report events','no shared board ownership','do not draw historical pipeline as implemented current path','no migration claim; b17 planned at frozen snapshot','evidence_gap','T11-F04','Read accepted maps; preserve historical role labels'),
('C28','evidence','accepted three audit packages','this merged audit','B0155',1,20,'manifest SHA/report SHA; G0/G1 audit scope','frozen copies, no active build','before/after hash equality','protected dependencies read-only','all source refs/claims traceable; G2–G5 not newly run','audit acceptance does not close parent hardware tasks','no_issue_found','T11-F06','Independent SHA, dedup and coverage verification'),
]
rows=[]
for c,stage,prod,cons,sid,lo,hi,units,clock,event,owner,inv,recovery,result,fid,nxt in checks:
    s=sources[sid]
    rows.append(dict(checkpoint=c,stage=stage,parent_task='T11',producer=prod,consumer=cons,source_path=s['snapshot_path'],source_sha256=s['sha256'],line_start=lo,line_end=hi,input_output_units=units,clock_reset=clock,acceptance_event=event,ownership=owner,invariant=inv,failure_recovery=recovery,result=result,evidence=fid+'; '+sid,optimization=next(f['recommendation'] for f in findings if f['finding_id']==fid),verification_next=nxt))
csvout('checkpoints.csv',rows)

# Explicit complete cross-package dedup. Each original finding occurs exactly once.
group_specs=[
('CHAIN-01','correctness','像素入口格式与给定字节自洽的区别',['T02-F01','T10-F01'],'default b15 source path affected; no old-bit pixel test claim'),
('CHAIN-02','correctness','最终好帧/取消/发布事务',['T02-F02','T02-F03','T06-F06','T10-F02'],'late CSI verdict and samecycle final cancel are distinct triggers within shared transaction group'),
('CHAIN-03','correctness','原生PAXI地址/mask及模型资格',['T06-F01','T06-F02','T06-F03','T06-F11'],'frozen source differences; true MC missing-R root cause not signed off'),
('CHAIN-04','correctness','DDR可见性/槽排序/导出描述符一致性',['T06-F04','T06-F05','T11-F01'],'legal store/module counterexamples; full-size default reachability not proven'),
('CHAIN-05','correctness','超时取消/晚响应与跨会话隔离',['T06-F07','T06-F08','T06-F10','T02-F06'],'watchdog store-state mismatch confirmed; finite guard and CDC gaps retained'),
('CHAIN-06','correctness','容量/位偏移及源地址边界',['T06-F09','T10-F04','T11-F02'],'CMP14B margin conditional on bit-offset cost; source-wrap default fixed bases unaffected'),
('CHAIN-07','correctness','消费者合法几何和严格子集拒收',['T10-F03','T10-F05'],'small geometry prep1 defect; default1920x1080 unaffected; ignored padding only A+ strict subset'),
('CHAIN-08','observability','capture/session/ROI/CFA与曝光同步',['T02-F04','T02-F05','T02-F09'],'admission ID != capture sequence; SOF arrival pairing != exposure proof'),
('CHAIN-09','observability','导出完成/主机可见性/ACK',['T11-F03','T11-F05'],'TL accepted/local queued != CPU consumed; preserve HELD and matching ACK'),
('CHAIN-10','observability','分支接入、IP与硬件证据资格',['T02-F07','T06-F14','T10-F08','T11-F04','T11-F06'],'RAW reference/A+UART/diagnostics/offline/historical not one built pipeline'),
('CHAIN-11','observability','长时字典tag复用',['T10-F11'],'16bit tag wraps~4.045s@30fps; no wrong-code reproduction'),
('CHAIN-12','throughput','最坏服务率与资源/时序签核',['T06-F12','T10-F09','T11-F07'],'P4 R1/R4 singlecore synthetic/proxy TB-slotfree sink93.75 only; production gap'),
('CHAIN-13','resources','维护性冗余候选与注释',['T02-F08','T06-F15','T10-F06','T10-F10','T11-F08'],'no immediate removal of CRC/Adler/FIFO/skid/rowbanks/obuf; no fabricated saving'),
('CHAIN-14','retained_controls','静态范围内未发现问题的必要控制',['T02-F10','T06-F13','T10-F07','T11-F09'],'limited checks; no arbitrary stall/reset/CDC or hardware PASS')]
allf={f['finding_id']:f for f in dep_findings+findings}
assert len(allf)==45
seen=[]; groups=[]
for gid,priority,title,ids,boundary in group_specs:
    seen+=ids
    fs=[allf[i] for i in ids]
    groups.append(dict(group_id=gid,priority=priority,title=title,original_finding_ids=ids,new_finding_ids=[i for i in ids if i.startswith('T11-')],evidence_refs=[e for f in fs for e in f['evidence_refs']],trigger_and_default_scope=boundary,claims=[{'finding_id':f['finding_id'],'kind':f['kind'],'claim':f['claim']} for f in fs],recommendation=[f['recommendation'] for f in fs],expected_benefit=[f['expected_benefit'] for f in fs],tradeoff=[f['tradeoff'] for f in fs],validation=[f['validation'] for f in fs],rollback='Retain current production sources/bit/RAW compatibility. Future change needs new bound candidate and tests.'))
assert len(seen)==len(set(seen))==len(allf) and set(seen)==set(allf)
root_specs=[
('sample_format',['T02-F01']),('late_CSI_verdict',['T02-F02','T06-F06']),('last_ROI_suffix',['T02-F03']),
('capture_sequence',['T02-F04']),('exposure_sync',['T02-F05']),('camera_reset',['T02-F06']),('PHY_qualification',['T02-F07']),('CFA_metadata',['T02-F09']),
('native_address',['T06-F01']),('native_mask',['T06-F02']),('native_command_acceptance',['T06-F03']),('write_visibility',['T06-F04']),('store_order',['T06-F05']),('late_response_epoch',['T06-F07']),('watchdog_state',['T06-F08']),('store_capacity_keep',['T06-F09']),('bridge_CDC',['T06-F10']),('model_qualification',['T06-F11']),
('production_service_qualification',['T06-F12','T10-F09','T11-F07']),('RAW_writer_session_qualification',['T06-F14']),
('samecycle_cancel_commit',['T10-F02']),('consumer_legal_geometry',['T10-F03']),('block_cost_bit_offset',['T10-F04']),('strict_consumer_subset',['T10-F05']),('algorithm_comments',['T10-F06']),('missing_branch_integration',['T10-F08','T11-F04']),('dictionary_tag_wrap',['T10-F11']),
('exporter_mismatch_fail_open',['T11-F01']),('DDR_source_add_wrap',['T11-F02']),('host_DMA_visibility',['T11-F03']),('UART_completion_semantics',['T11-F05']),('generated_IP_candidate_binding',['T11-F06']),('status_layout_comments',['T11-F08']),
('unselected_source_maintenance',['T02-F08','T06-F15']),('checksum_buffer_removal_unproven',['T10-F10']),
('input_retained_controls',['T02-F10']),('store_retained_controls',['T06-F13']),('transform_retained_controls',['T10-F07']),('PCIe_retained_controls',['T11-F09'])]
root_index=[]; id_to_root={}
for idx,(name,ids) in enumerate(root_specs,1):
    rid=f'ROOT-{idx:02d}'
    root_index.append(dict(root_id=rid,topic=name,original_finding_ids=ids,claims=[{'finding_id':i,'kind':allf[i]['kind'],'claim':allf[i]['claim']} for i in ids],scope='Original trigger/default/qualification retained verbatim in source finding and thematic group; adjacent roots are not merged.'))
    for i in ids: id_to_root[i]=rid
assert len(root_index)==39 and set(id_to_root)|{'T10-F01'}==set(allf)
summary=dict(original_finding_id='T10-F01',kind='inherited_composite_summary_not_a_new_root',references=[id_to_root[i] for i in ['T02-F01','T02-F02','T02-F03','T06-F04','T06-F05','T06-F07']],note='CRC/Adler self-consistency cannot fix independent upstream defects; this inherited summary is stored once and does not create another defect.')
putj('chain-findings.json',{'task_id':'T11.chain-egress-review','not_a_global_task_board':True,'dependency_manifests':dep_bindings,'counts':{'inherited_original_records':36,'T11_package_records':9,'all_original_records':45,'thematic_groups':14,'root_or_retained_control_entries':39,'composite_inherited_summaries':1,'not_a_defect_count':True},'groups':groups,'group_semantics':'14 thematic presentation bundles only; distinct root causes are separately indexed below and are not conflated','root_index':root_index,'inherited_composite_summaries':[summary]})
opt=[]
for g in groups:
    if g['priority']=='retained_controls': continue
    opt.append(dict(priority=g['priority'],group_id=g['group_id'],title=g['title'],root_ids=';'.join(sorted({id_to_root[i] for i in g['original_finding_ids'] if i in id_to_root})),original_finding_ids=';'.join(g['original_finding_ids']),trigger_default_scope=g['trigger_and_default_scope'],evidence_qualification='frozen source + accepted audit; not hardware signature; thematic row may cite multiple distinct roots',recommendation=' | '.join(g['recommendation']),benefit_basis=' | '.join(g['expected_benefit']),cost=' | '.join(g['tradeoff']),minimum_next_validation=' | '.join(g['validation']),rollback=g['rollback']))
csvout('optimization.csv',opt)

# Edges are not speculative architecture links. 'missing' explicitly has no connected consumer.
edge_defs=[
('E01','b15 actual','CSI checked/unpack','crop/CDC','40bit 4x10 samples misread as packed bytes','clk_cam -> clk_a1','unbackpressured valid; sticky abort token','capture/admission slot','final CSI verdict disconnected','reset epoch evidence gap','T02:C08-C23; T02-F01/F02/F03'),
('E02','b15 actual','crop/CDC','RAW store','40bit group; 20useful/32 allocated','A1 -> DDR','begin/ready; flush accepted by bridge','FREE->WRITING->READY','ROI last only; final late bad cannot revoke','F_WAIT/R_AR cancel mismatch','T06:C01-C35; T06-F04/F06/F08'),
('E03','b15 actual','RAW store/arb/bridge','DDR PAXI','word_index vs native <<3; mask inversion','A1<->DDR','AW/W/AR separately accepted; model gap','read owner plus one AR in flight','write visibility not guaranteed by FIFO enqueue','finite guard no response epoch','T06-F01/F02/F03/F07/F11'),
('E04','b15 actual','RAW read/feeder','A+ frame/core','40bit group -> transformed bytes/zlib','A1','valid/ready, final output commit','RAW reading + CMP writing','samecycle abort/SOF may still commit','tag wrap and cancellation boundaries','T10:C17-C30; T10-F02/F04/F11'),
('E05','b15 actual','A+ commit/CMP','descriptor/exporter','exact zlib len/profile/raw/xform/stream CRC','A1','commit -> desc_push; open_ready','CMP READY->READING','mismatch counted but header still emitted','no mismatch fail-closed recovery','T11:C01-C08; T11-F01'),
('E06','b15 actual','exporter/UART','PC decoder','A1U1 44B+exact zlib bytes','clk_a1=uart_clk; serial->PC','local UART request/busy; PC parse','slot copied until close; no host ACK','CRC/Adler check given bytes, strict parser gap','line/reset partial frame no reliable retry','T10-F03/F05; T11-F05'),
('E07','RAW reference actual source','CSI A/B checked','two cam_r10f_writer','sample lanes explicitly packed; R10F codec0','cam_A/B -> DDR','nonbackpressure; FIFO token; final good','per-camera double slot','final good/B rewrite qualify; inherited full-EOF gap','late response/reset qualification absent','T02 RAW branch; T06-F14; T11:C09-C11'),
('E08','RAW reference actual source','R10F slot','pusher AXI reader','DMA align4096, 128B head/packed/tail640','DDR -> TL user','published src_seq after ARM then AR/R','ARMED->TX->HELD','bound source check wrap possible outside fixed defaults','cancel drain; late-R reset proof absent','T11:C10-C21; T11-F02/F03'),
('E09','RAW reference actual source','pusher/engine mux','generated PCIe core','256bit+8 DW-valid F0/FF/F8; 128B TLP','TL user','utx_sel&&!wait&&beat_present&&beat_ready','TLP arbitration to EOP','TL accepted is local; no CPU visibility proof','PERST/link reset different local paths','T11:C12-C18; E01–E05 supplemental IP'),
('E10','host boundary unverified','PCIe posted writes','RK DMA/ACK consumer','R10F bytes + oneDW doorbell session/seq','TL -> host DMA/CPU','host visibility/parse then matching ACK required','HELD until ACK/CANCEL','actual bound driver/cache/barrier evidence missing','session restart/stale ACK/IOMMU policy unbound','T11-F03; T11:C15-C21'),
('E11','independent diagnostic actual source','Bayer demosaic','Gray/Gauss/HE sinks','RGB8 -> parallel Y8, not original packed Bayer','diagnostic clock path','branch accepted events/rowbank/obuf','independent row/obuf/LUT banks','bad frame/LUT rules T10; no A+ mux','dynamic mode metadata unconnected','T10:C05-C15; T10-F08'),
('E12','missing integration','A+ compressed descriptors','compressed PCIe/R10F codec consumer','no frozen compressed codec framing/len/ACK mapping','no shared implemented clock contract','no actual common acceptance event','no integrated production ownership','missing; do not infer from path existence','must specify cancel/reset/session','T11-F04; T11:C22-C23'),
('E13','isolated offline','sync control/mailbox/pairer','sync gate/dual scheduler','SOF timestamps and capture/drop events','per-camera->control CDC','mailbox accepted + pair window','isolated candidate ownership','arrival pairing only; no physical exposure proof','offline recovery only','T02-F05; accepted T02/T06 maps'),
('E14','historical/reference','BPR1/Rice / raw draft','historical software consumers','old codec contract distinct A+/R10F','historical candidate','historical report acceptance only','no current production ownership','not migrated; no live producer-consumer edge','not current recovery proof','T10:C01-C04; B0053:6-14'),
('E15','b15 actual diagnostic','HDMI test pattern','HDMI display','test pattern, not captured image','display domain','display timing events','test-pattern buffers','does not prove camera capture content/fps','independent display reset','T02:C01-C02; T02-F08')]
cov=[]
edge_sources=[('B0150',310,360),('B0144',156,163),('B0153',1,30),('B0146',180,190),('B0150',838,864),('B0148',439,461),('B0098',435,464),('B0101',397,403),('E02',76,103),('B0101',733,753),('B0123',1805,1814),('B0123',1515,1544),('B0086',1,25),('B0053',6,14),('B0151',1,25)]
for (eid,branch,prod,cons,fmt,clock,event,owner,good,reset,evidence),(sid,lo,hi) in zip(edge_defs,edge_sources):
    cov.append(dict(edge_id=eid,branch_status=branch,producer=prod,consumer=cons,format_units=fmt,clock_reset=clock,acceptance_event=event,ownership=owner,final_good_qualification=good,reset_cancel=reset,review_status='reviewed_evidence_gap' if ('missing' in branch or 'unverified' in branch) else 'reviewed',evidence=evidence,source_binding=json.dumps(ref(sid,lo,hi,'representative edge anchor; detailed contract spans in referenced checkpoints/findings'),ensure_ascii=False),required_next='see chain-findings.json corresponding original IDs; future DUT/host verification'))
csvout('coverage.csv',cov)
put('chain-map.mmd', '''flowchart LR
 subgraph B15["b15 A+ UART diagnostic source; not board closed"]
  A["CSI A checked 4x10 samples"] -->|"E01 format/verdict gaps"| C["crop + CDC"]
  C -->|E02| RS["RAW store"]
  RS <-->|"E03 native PAXI contract gaps"| DD["b15 DDR"]
  RS -->|E04| AP["A+ frame/core"]
  AP -->|"E05 commit / descriptor"| EX["CMP + UART exporter"]
  EX -->|"E06 A1U1 exact zlib"| PC["PC consumer"]
  PAT["test pattern"] -->|"E15 independent"| HDMI["HDMI"]
 end
 subgraph RAW["Independent RAW/R10F PCIe reference source"]
  AB["checked CSI A/B"] -->|E07| RW["two R10F codec0 writers"]
  RW -->|"E08 padded DMA slots"| PU["ARM pusher AXI reader"]
  PU -->|"E09 8 DW-valid"| IP["PCIe generated core"]
  IP -.->|"E10 host visibility/ACK unverified"| RK["RK DMA consumer"]
  RK -.->|"matching session/seq ACK required"| PU
  AB --> DEM["Bayer demosaic"] -->|E11| ALG["Gray/Gaussian/HE diagnostic sinks"]
 end
 AP -.->|"E12 missing compressed PCIe integration"| PU
 OFF["isolated sync/recovery candidates"] -.->|"E13 separate evidence only"| AB
 HIST["historical BPR1/Rice + RAW draft"] -.->|"E14 reference only"| PC
''')
put('chain-review.md', '''# FPGA链路细节总表（T11 round0开发交付）

本文件汇总四包的审查产物，T02/T06/T10已独立round0审查PASS；本包等待新综合测试者验收。只有本包也PASS后原规划才能称本轮整链路细节审查完成。任何审查PASS均不表示DUT/生产双路/真实板级通过，不关闭父T02/T06/T10/T11。

`chain-map.mmd`以实际分支作图；`coverage.csv`列15条边，逐条包含格式/单位/时钟/接受事件/所有权/最终good/复位取消。E12明确未接入，E10是未绑定真实主机证据的边界，E13隔离离线，E14历史参考。b15只有A接A+，B/三算法/RAW PCIe不得画成同一生产链。HDMI为测试图。`source-map.json`合并前三包所有来源别名并保留候选身份；补冻工程与IP只证明当前只读源，不追认旧bit。

`chain-findings.json`把36个继承原finding加9个本包记录完整分到14个展示专题，每个原ID在专题归属恰好一次。14是展示专题数，不是根因或新增缺陷数：独立的`root_index`列39条根因/保留控制索引（含四项no_issue_found），同根因跨包合并，不同根因分别保留；T10-F01复合继承说明单独一次存储并引用6条相关root，不新增根因。排序缺陷、消费者失败开放、可见性、有限guard、取消同拍、源地址回绕各有独立root，不能因为位于同专题而混为一个根因。原独立报告和原finding完整保留，未改写前包。`optimization.csv`按正确性→可观测性→吞吐→资源排列，含root_ids、具体建议、触发/默认配置资格、收益依据、代价、最小验证和回退。

优先正确性为入口4×10样本/packed不等价、最终CSI裁决与abort优先、原生地址/mask、DDR可见性、合法store排序与导出描述符拒错。后续PC往返CRC/Adler只验证给定字节自洽，不能恢复起始错误像素、撤销晚到坏帧或证明MC内容可见。T10同拍abort/重复SOF仍commit要在后续发布/描述符合同中闭环。

默认配置资格必须保留：T06排序在合法store接口已证，默认全尺寸整机可达性未证；T11描述符错配接口反例同理。T11源地址回绕仅为模块输入反例，默认固定低地址writer不触发。T10合法小几何prep1消费者缺陷默认1920×1080不触发。strict padding/尾字节按A+ v1严格子集拒收，不宣称通用zlib必须拒绝ignored padding，也未证明RTL产生非法流。16bit tag约4.045秒回绕是长时定向证明缺口，不是已复现错码。CMP理想上界2594706B与14B槽余量依赖真实块起始offset成本前提；queued/consumed offset等价仍未证。

## 预算与既有资格

`witness/result-r0.json`和`budget.csv`使用十进制MB。RAW packed每帧2592000B，每路77.760/双路155.520MB/s；A+理想上界2594706B，每路77.84118/双路155.68236MB/s，A1U1外44B后2594750B，外头不含在内层长度。R10F当前codec0头128B，DMA2592768B含640B尾零；每帧20256个128B MWr，每个16B TLP头，加单DW门铃20B，总2916884B，即每路87.50652/双路175.01304MB/s，仍未含DLL/PHY/ACK/replay/idle。UART 8N1按10bit/byte计算，不能拿115200或本地FIFO接纳冒充PCIe生产sink。

b15每20B RAW占32B，单帧RAW占4147200B不是u16像素声明；CMP理想上界向32B补齐2594720B。RAW写读+CMP写读共13483840B/帧，两路30fps为809.0304MB/s预算，未含控制/refresh/仲裁/停顿。此布局预算与RAW AXI路径是不同候选，不拼成已实现链。P4 R1/R4仅单核187.5MHz、合成/comp代理、TB slot-free、93.75MB/s sink，R2 strict-serial及R3 sink受限缺口保留；不能扩成自然/最坏内容或生产双路。b15 102/300 ERAM、+0.012ns与上游旧T09 200/300、+0.100ns属于不同实现，不能相加资源或拼时序签核。

本轮新G2/G3/G4/G5均not_applicable，理由沿冻结dev-plan：只读、不改RTL/IP/时钟/约束、不交新bit、不签核硬件。既有b15 G2仅旧报告诊断薄余量reported_pass范围，完整CDC/真实MC行为未签核；G3旧下载/150s观察范围reported_pass；G4仍blocked/H4_UNRESOLVED、enc/exported=0；G5生产稳定性/持续服务not_run。上游旧T09 G2仅其另一manifest选定内部范围，G3旧离线包不适用、G4 not_run/deferred、G5旧范围不适用；真实RK/当前A+结合仍缺证据。隔离同步/恢复G0/G1仅原候选范围，不证明曝光同步迁入。

## 最多三条后续主题

1. 原生PAXI修复与小图样真实读回/缺R事务证据，归b17活动线；本轮基线b17仍是计划，无实施/验收可复用，不追逐更新。
2. 真实内容P1080、生产slot-free/fast sink、双路共享DDR/资源签核，归另一活动run 20261026-143924，不重复其四帧矩阵。
3. 按优化表实施正确性与接口收口，未来新候选完成适用G2与真实曝光/完整帧/恢复/稳定性门槛。RK深度/NPU继续暂缓。

回退入口是保留全部现源、旧候选和RAW协议；本轮没有生产改动。审查错误由同任务新轮次纠正并重新冻结，旧轮证据保留。
''')
put('review.md', '''# T11 发布/导出/PCIe审查 round0

本包完成五步文档审查并提供可复查离线见证，等待独立综合测试，不宣称DUT或硬件通过。写入仅本目录，未改前三包、统一baseline、源码、全局任务板或dispatch。

1. UART与RAW/R10F分别检查：A1U1固定44B LE头，CRC32覆盖头0..39、raw/xform/zlib精确字节分别校验，内层zlib带Adler；从CMP末32B字只发送stream_len精确字节。R10F codec0头128B，header CRC自字段零后覆盖128B，raw/payload CRC只含有效packed载荷，DMA尾零不计CRC。profile静态prep/pred，admission ID不等于capture_seq，R10F有session/capture/mode但曝光/时间戳字段为0。CRC相同不代表相机像素及完整帧good。C01–C11、F01/F04/F05/F08。
2. PCIe工程和实际IP源补冻E01–E05；wrapper TD6.2.174248、IP元数据1.0/171484 2025-08-11，LINK_WIDTH=2。256bit数据+8bit DW有效，不能当byte keep；F0头四DW、FF八DW数据、F8四DW头+一DW门铃，代码的bswap256/bswap32与MSB DW位置需真实IP方向绑定。默认32DW=128B载荷≤最小合法MPS，dst128B对齐、frame4KiB倍数，因此不跨4KiB；门铃4B对齐、BE=f/0。ARM锁存dst/db/cap/session，检查非零/对齐/容量/64bit目的wrap/门铃重叠；单bit命令，cap/session活动期拒写，后续影子地址改动不改变latched值。DDR源边界32bit回绕反例F02明确默认固定基址不触发。ACK匹配held/session/seq才释放；CANCEL_TX经drain。TL accepted/doorbell_done不是PCIe completion/CPU消费；真实host分配/屏障/ACK及重启/晚R证据缺口保留。C12–C21、F02/F03/F06/F09。
3. `chain-review.md/chain-map.mmd/coverage.csv/chain-findings.json`合并前三份PASS审查，保留真实分支、15边、45原记录、14展示专题和39条独立根因/保留控制索引；继承复合说明不新增缺陷。C22–C24/C27–C28。
4. `witness/egress_witness.py`独立重算整数预算、源码锚定32bit边界/描述符失败开放事件与正控制、全部默认页偏移。`budget.csv/optimization.csv`区分纯预算、旧候选结果和未证生产事实；不复跑另一run长矩阵。C25–C26。
5. 标准产物与三份依赖manifest/独立报告全部绑定，运行记录在commands.json；活动结束后一次冻结manifest-r0.json，后续由新综合测试者做SHA/语义/去重/预算及不同判据核验。

本包最高风险新结论F01可用真实RTL导出器故障注入，或测试者不同事件判据核查E_OPEN状态选择；F02需独立扩位oracle/真实DUT边界。当前见证是静态源码锚定+算术/状态简模，不是cycle-accurate RTL或板测。正常匹配描述符、默认低地址槽、合法MPS/对齐作为正控制；不得把接口反例说成默认板上已发生。

已验依赖按冻结SHA只读复用，前包见证不重复执行。新G0/G1本地核查结果留文件，独立判定待测试者；新G2–G5不适用沿规划理由，旧门槛缺口见chain-review。没有立即删除任何CRC/Adler、FIFO/skid、row bank/obuf建议；源白名单与旧注释收口只计维护收益，无网表不能给资源百分比。

执行边界：根技能第一次短读发生在dispatch deadline规则读取前，未套显式timeout，保留此限制；其后读/搜/输入冻结均自有PowerShell Job+55秒Wait/Stop。一次短读函数名R碰撞内置r别名，引发Invoke-History参数错误；已用Read-Slice更正一次，保留失败记录，不把它当验证通过。Python检查用自有Process/WaitForExit真实240秒deadline，超时Kill(true)只终止该进程树。无TD/综合/bit/Flash/COM/JTAG/RK/网络下载/共享仿真库/盘符/删除/commit/push操作。

DeepSeek仅整数算术辅助，实际project_root=D:/fpga/ph1p100，未发源码/图像/secret。其不必要noop操作被拒，call_id以真实拒绝结果resume一次，模型随后completed。worker把RAW/R10F与A1U1错误混合、漏TLP头等，全部该表未采用；本地Python独立核对正确R10F及DDR预算，细节见witness/deepseek-review.json。复杂契约与最终验证均由Codex执行。
''')
put('lessons.md', '''# T11可复用经验

- 检出ID/长度不一致后只记错再发送是失败开放；验证应观察任何外部头字节是否已发出，并把slot回收/描述符重同步作为同一事务。
- 边界比较中的加法位宽决定是否允许回绕；目的64bit保护不能代替源32bit保护。模块接口反例必须说明默认top是否可达。
- local enqueue、TL accept、线末stop-bit、CPU可见/消费、ACK各有不同完成事件。slot数据复制后释放可能安全，不能因此改称主机完成。
- RAW packed、b15 RAW存储占用、A+内层、UART外头、R10F有效长/DMA/TLP开销分别计算。worker算术也须独立复核；发现混合格式即拒绝其表。
- 合并审查要保留每条原finding ID恰好一次，并保留合法小几何/默认几何、模型/真实MC、隔离/生产等触发限定；不按组数宣称新增缺陷。
- PowerShell短函数名R会命中内置r历史别名；使用无歧义Read-Slice。命令启动前实施真实deadline，yield不是timeout。
''')
putj('witness/deepseek-review.json',{'task_id':'0fcfc60e032d428fad70dcb40633d4f5','project_root':'D:\\fpga\\ph1p100','purpose':'integer arithmetic only; no project source transmitted','pending_call_id':'call_00_VRywLjL8kcPkakfj4crj9903','proposal':'python -c "print(\'noop\')"','decision':'denied; not executed','resume_count_for_call_id':1,'worker_final_status':'completed','api_total_tokens':3524,'accepted_only_after_independent_check':['raw=2592000','A+ideal2594706','rawstore4147200','CMPalloc2594720','DDRdual809030400B/s','mod32wrap=0','low29=0x1ffff000'],'rejected_worker_errors':['bytes_per_pixel=5 and line_bytes=540 mislabeled','mixed A+44B wrapper with R10F128B header; 128+2594706+44 incorrectly summed as2594750','R10F TLP calculation omitted16B/TLP header','called129600*32 u16 storage rather than20B/32B group layout','worker R10F bandwidth77.84508MB/s not used'],'no_worker_command_executed':True,'independent_result_path':str(OUT/'witness/result-r0.json')})
putj('commands.json',{'task_id':'T11.chain-egress-review','working_directory':str(ROOT),'read_search_control':'PowerShell own Start-Job; Wait-Job Timeout55; Stop-Job own job only','initial_exception':'First root AGENTS/dev skill short read before dispatch timeout rule lacked explicit timeout; no persistent process','failed_read':{'command_fragment':'function R($id,$lo,$hi) then R ...','result':'Invoke-History positional argument errors (alias collision), not validation PASS','correction':'Read-Slice used once in following controlled job'},'failed_build':{'attempt':1,'exit_code':1,'cause':'T06 source-map sources is list while T02/T10 use dictionary','fix':'handle both list and dict, one corrected retry; first failure logs retained'},'witness_command':'python -B -X utf8 T11.chain-egress-review/witness/egress_witness.py --out <task-owned-dir>','witness_deadline_seconds':240,'runner':'System.Diagnostics.Process own process; WaitForExit; Kill(entireProcessTree=true) on deadline','execution_logs':'native-run-r0.json + native-run-attempt2-r0.json + build/witness/verify stdout/stderr under this directory','hardware_actions':0,'TD_builds':0,'RTL_simulations':0,'deletions':0,'production_modifications':0,'worker':{'task_id':'0fcfc60e032d428fad70dcb40633d4f5','state':'completed; noop denied and resumed exactly once','review':'witness/deepseek-review.json'}})
putj('dependency-bindings.json',dep_bindings)
print(json.dumps({'build':'review artifacts generated','checkpoints':len(rows),'edges':len(cov),'original_findings':len(allf),'groups':len(groups)},ensure_ascii=False))
