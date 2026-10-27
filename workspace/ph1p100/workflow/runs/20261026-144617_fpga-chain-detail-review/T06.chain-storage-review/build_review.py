"""Assemble the T06 read-only review. Writes only this task directory."""
from pathlib import Path
import csv, hashlib, json, shutil, re, sys
from datetime import datetime, timezone

ROOT=Path('D:/fpga/ph1p100')
RUN=ROOT/'workflow/runs/20261026-144617_fpga-chain-detail-review'
OUT=RUN/'T06.chain-storage-review'
BASE=RUN/'baseline/source-manifest.json'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def now(): return datetime.now(timezone.utc).isoformat()
def put(name, value):
    p=OUT/name
    assert p.resolve().is_relative_to(OUT.resolve())
    p.parent.mkdir(parents=True,exist_ok=True)
    if isinstance(value,(dict,list)): value=json.dumps(value,ensure_ascii=False,indent=2)+'\n'
    p.write_text(value,encoding='utf-8')
def load(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
assert ROOT.resolve()==ROOT and OUT.resolve().is_relative_to(RUN.resolve())
assert not OUT.is_symlink()
baseline=load(BASE)
assert sha(BASE)=='c08adc09b364828fee5d94953a89898a3220af8c8f99cdec52404fec06f74c96'
bm={Path(f['snapshot_path']).name:f for f in baseline['files']}
verification=[]
for f in baseline['files']:
    p=Path(f['snapshot_path']); actual=sha(p)
    assert actual==f['sha256'],p
    verification.append({'path':str(p),'sha256':actual,'size':p.stat().st_size})
t02=RUN/'T02.chain-input-review/manifest-r0.json'
t02report=RUN/'test-reports/T02.chain-input-review-r0-integrated.md'
assert sha(t02)=='af32567395a3083b3b5005df40cfc37857f54b133293a644782eca9d6a34b997'
assert sha(t02report)=='c96751cda203daf4c53a47909760f7d5b2edd3b88abdedbda0e625d67d2fb920'
dep=load(t02)
for f in dep['files']: assert sha(f['path'])==f['sha256'],f['path']
put('baseline-verification-r0.json',{'baseline_manifest_sha256':sha(BASE),'checked':len(verification),'files':verification,'T02_manifest_sha256':sha(t02),'T02_report_sha256':sha(t02report),'T02_frozen_files_checked':len(dep['files']),'result':'all_equal'})
controls=[]
for name in ['request.md','dev-plan.md','fpga-design-guide.md','input-index.md','dispatch.json','planning/task-T06-chain-storage-review.md','planning/recovery-T06-20261026-163157.md','user-feedback-20261026-160812.md','user-feedback-20261026-163157.md']:
    src=RUN/name; dst=OUT/'controls'/name; before=sha(src)
    dst.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(src,dst)
    assert before==sha(src)==sha(dst)
    controls.append({'original_path':str(src),'frozen_path':str(dst),'sha256':before})
put('control-bindings.json',controls)
selected=['0005.md','0009.v','0010.v','0036.v','0040.v','0098.v','0101.v','0103.v','0139.md','0140.md','0141.json','0143.v','0144.v','0146.v','0147.v','0148.v','0150.v','0151.v','0152.v','0153.v','0154.v','0155.al','0156.adc','0157.sdc','0163.v','0164.v','0165.v','0166.v','0167.v','0168.md','0169.md','0170.md','0171.md','0284.md','0285.md']
sources=[]
for key in selected:
    f=bm[key]; p=Path(f['snapshot_path'])
    sources.append({'source_id':'B'+key[:4],'source_path':f['source_path'],'source_relative':f['source_relative'],'snapshot_path':str(p),'sha256':f['sha256'],'line_count':len(p.read_text(encoding='utf-8-sig').splitlines()),'role': 'b15_selected_source' if key in ['0143.v','0144.v','0150.v','0153.v'] else 'qualified_reference_or_evidence'})
def ref(key,lo,hi):
    f=bm[key]; return {'source_id':'B'+key[:4],'source_path':f['source_path'],'snapshot_path':f['snapshot_path'],'sha256':f['sha256'],'line_start':lo,'line_end':hi}
al=Path(bm['0155.al']['snapshot_path']).read_text(encoding='utf-8-sig')
compile_paths=re.findall(r'<File Path="([^"]+)"',al)
candidate=load(bm['0141.json']['snapshot_path'])
put('source-map.json',{'task_id':'T06.chain-storage-review','baseline_manifest':str(BASE),'baseline_manifest_sha256':sha(BASE),'sources':sources,'compiled_top':'p2_a1_board_top','compile_entry_source_id':'B0155','compile_paths':compile_paths,'candidate_changed_src_sha256':candidate.get('changed_src_sha256'),'candidate_build':candidate.get('build'),'candidate_boundary':'b15 selected changed-src bridge B0153 is distinct from stale td/src bridge B0163. Existing source/manifest bindings do not certify encrypted MC internals or all historical bit dependencies. Source snapshots are review inputs, not a new build.','dependencies':[{'task_id':'T02.chain-input-review','manifest_path':str(t02),'sha256':sha(t02),'report_path':str(t02report),'report_sha256':sha(t02report),'scope':'Accepted input review only. Preserve F01/F02/F03/F04/F06.'}],'branches':[{'name':'b15 A+ UART','status':'selected diagnostic source','stores':'2 RAW + 2 CMP; A only'},{'name':'upstream RAW/R10F AXI','status':'separate production reference; not b15 native PAXI','stores':'protected two-base writer and ARM/TX/HELD DMA consumer'},{'name':'preview native store','status':'independent reference','stores':'three slots; last-word fence; may replace READY only'},{'name':'b17','status':'planning-only in this baseline; do not import active changes'},{'name':'steady-state P4','status':'separate offline/TB slot-free candidate; not production shared-DDR proof'}]})
findings=[]
def finding(fid,severity,kind,claim,refs,trigger,impact,recommendation,benefit,tradeoff,validation):
    findings.append(dict(finding_id=fid,severity=severity,kind=kind,claim=claim,evidence_refs=refs,reproduction=trigger,impact=impact,recommendation=recommendation,expected_benefit=benefit,tradeoff=tradeoff,validation=validation,disposition='review_only; no production change; independent acceptance pending'))
finding('T06-F01','high','confirmed_issue','b15内部256bit字下标在唯一PAXI边界缺少同份原生参考要求的左移3位适配；这是源码合同差异，未定位板上缺R根因。',[ref('0144.v',178,206),ref('0143.v',70,82),ref('0153.v',97,105),ref('0153.v',343,345),ref('0153.v',390,397),ref('0166.v',83,99),ref('0040.v',32,56)],'连续字0/1经桥为PAXI0/1，参考为0/8；条件模型addr>>3时不同图样会别名。','像素/压缩内容存在错址覆盖风险；不把条件模型误差称真实MC已测坏。','保留内部字单位，仅在范围检查后的一个边界转换；归b17后续授权。','恢复参考地址步长；不估计性能百分比。','原生地址低位/容量与所有消费者必须共同核验。','小图样多地址读回；地址适配正对照和低3位/越界负例；真实IP与新候选绑定。')
finding('T06-F02','high','confirmed_issue','b15完整写mask恒全1，与同份mtest完整写mask=0相反；生成wrapper只重排未取反。',[ref('0153.v',343,348),ref('0167.v',431,452),ref('0165.v',384,392),ref('0040.v',49,55)],'写全字时桥送ffffffff；参考送00000000。条件模型1=屏蔽时两字均未更新。','原生完整写合同不一致；加密MC内部极性仍需厂商/板证，不能宣称已证实旧bit全写屏蔽。','按同版本原生mask合同适配，模型执行逐字节mask；不按AXI名称猜语义。','消除写掩码误用风险。','需要与生成IP绑定而非泛化所有PAXI。','固定图样/逐字节部分mask/全mask正反对照和真实读回。')
finding('T06-F03','high','evidence_gap','一笔AR在途不等于AW/AR共享命令互斥；b15写/读引擎可同拍握手，而厂商参考以单cmd_type与共同ready选命令。',[ref('0143.v',59,85),ref('0153.v',338,407),ref('0167.v',441,454)],'WF和AF均有请求、AR空闲、路径空且AW/W/ARready同时为1。','若原生MC不能双接纳，则可能丢命令；本审查没有MC逐事务接纳证据。','将读写同时接纳合同列为必须证明项；保守串行只作未来诊断对照。','区分地址/mask/仲裁根因，避免继续仅改重试。','串行化可能降低服务率，需预算验证。','同拍三ready端口轨迹与分开ready对照；原生MC实际接纳和响应对应。')
finding('T06-F04','high','evidence_gap','RAW/CMP在最后数据进入桥WF时置READY；没有最终写可见确认或跨WF/AF fence，独立读引擎可在写仍阻塞时发AR。',[ref('0144.v',174,184),ref('0144.v',301,318),ref('0153.v',97,110),ref('0153.v',338,407),ref('0040.v',85,114)],'一字小帧最后flush已入WF、PAXI写ready保持0但读ready为1；读取同槽可先于实际写。','存在read-before-visible允许轨迹；是否真实调度触发/MC排序可避免仍缺证据。raw_pub只能证明enqueue，不证明内存内容正确。','补充完整发布点合同：native写完成/有资格的ordering fence后才READY；与晚CSI裁决同时满足。','防消费者读取尚未落地的新帧。','需确认PAXI写完成定义；可能延长占槽，不能简单多等固定周期。','witness发布轨迹；独立队列/RTL可控stall判据；后续真实最后写/首读相关证据。')
finding('T06-F05','high','confirmed_issue','slot_seq/pub_tgl在每次begin翻转，abort消耗序号；oldest_slot一位排序在合法store接口轨迹下可选新槽，违反发布顺序。',[ref('0144.v',145,148),ref('0144.v',268,297),ref('0144.v',328,344),ref('0148.v',314,332),ref('0148.v',384,415)],'合法store接口轨迹：A槽0发布并open；B槽1发布；close A；C槽0 begin后abort；D槽0发布，消费者在此期间未open B。此时B和D seq均1，rd_expect=1，oldest_slot优先槽0取D，发布FIFO仍B,D。','模块发布顺序缺陷已见证；若CMP消费者延迟领取使此轨迹可达，可用B描述符配D内容，E_OPEN仅计错继续输出。当前默认整机调度下该完整轨迹可达性未证明，不声称板上已发生。','未来修复应使用真实发布队列/可证明代际顺序，abort不得制造排序歧义；本包不改RTL。','保持commit顺序与descriptor-slot一一对应。','不能只把begin翻转挪到某一分支而不验证并发发布/领取/abort。','witness顺序轨迹；测试者用独立FIFO oracle或真实store微仿真复核；整机另验消费者pacing可达性。')
finding('T06-F06','high','confirmed_issue','T02晚CSI裁决缺口延伸到store：ROI last即READY；wr_abort只影响wr_active的WRITING，无法撤销READY或已READING的帧。',[ref('0152.v',108,111),ref('0150.v',480,493),ref('0144.v',174,180),ref('0144.v',282,318),ref('0144.v',328,344)],'ROI完成先于源行后缀CRC/FE；晚abort在wr_active=0时到来，abort_now为0。','坏帧可能已被编码/导出领取。不能把格式错误当DDR错，不能只OR晚abort。','发布必须等待选定good/EOF裁决和最终写可见性；重新定义pending-verdict所有权。','防坏帧/半事务公开。','等待裁决增加持槽时间，需要完整吞吐和满队列策略。','沿T02-F02/F03源链，末ROI CRC/后缀短长/缺FE/晚abort与消费者抢先领取测试。')
finding('T06-F07','high','evidence_gap','purge/有限guard能排空窗口内旧R，但无响应tag/epoch；旧R延迟超过guard并落在新ar_busy窗口时可被当新响应。',[ref('0153.v',173,205),ref('0153.v',275,336),ref('0153.v',396,426),ref('0144.v',187,215),ref('0150.v',630,647)],'旧AR超时→purge/guard结束→新AR握手ar_busy=1→旧R才到；rf_push仅按ar_busy判归属。','有限时间窗不是无界延迟下的新会话隔离证明；reset前后响应同类。未声称板上实际出现。','明确控制器flush/最大响应生命周期保证，或设计可验证代际隔离；不靠加大guard称证明。','阻止旧数据污染retry/新帧。','PAXI无ID时需厂商特定排空/重置协议及性能代价。','窗口内、边界、窗口外并跨retry/新帧/业务reset的晚R负例。')
finding('T06-F08','medium','confirmed_issue','top F_WAIT watchdog要求rd_close释放槽，但store仅R_HOLD处理rd_close；AR长期未接纳时R_AR不退出，且raw_rd_timeout在R_AR不触发。',[ref('0150.v',661,684),ref('0144.v',187,195),ref('0144.v',346,381),ref('0144.v',407,418)],'保持ddr_arready=0超过WD_LIMIT=16777216个A1周期；top退F_IDLE并脉冲close，store仍R_AR/READING。','watchdog声明的干净释放不能成立；raw_rd_open_ready持续0可阻塞后续帧。','未来把取消/释放合同覆盖AR未接纳与R等待，保持真实在途响应隔离。','恢复长AR stall后的可用性。','不得未经排空就把旧响应归属清除。','独立状态判据验证R_AR+rd_close无转移；缩短受控watchdog的RTL负例和恢复测试。')
finding('T06-F09','medium','evidence_gap','固定槽默认布局不重叠，但store没有waddr<SLOT_WORDS/累计字节硬截止；EXPECT_BYTES只在wr_last检查，MODE1 keep需连续低位且非末字全4B。',[ref('0150.v',124,162),ref('0144.v',151,184),ref('0144.v',301,325),ref('0144.v',198,206)],'过长流或缺last持续写；MODE0第129601字进入下一槽，MODE1超过81085字跨槽；稀疏keep计数与紧凑读长度不等价。','当前正常固定几何/编码上界路径需由生产者证明；恶化输入可越槽。非断言已在当前正常帧触发。','在未来接口合同明确最大字/精确长度/keep前缀、tail清零和越界拒整帧；编码膨胀上界归T10。','防超长和非规范keep破坏相邻持有帧。','边界保护需含已排队写的处置。','长度SLOT_WORDS边界±1、无last、keep0/稀疏/非末partial、32bit加法溢出负例。')
finding('T06-F10','medium','evidence_gap','FIFO各域有同步复位释放，但bridge DDR FSM/occupancy直接用A1释放复位；新增rf_pop_gray跨域未见对应skew约束。',[ref('0036.v',8,34),ref('0152.v',387,403),ref('0153.v',229,272),ref('0153.v',350,378),ref('0157.sdc',35,57)],'A1 reset释放相对DDR时钟任意相位；Gray多位路由偏斜未受该新增总线专门约束。','不能据FIFO reset同步或异步切组声明整个bridge CDC签核。','本域reset同步与完整Gray约束/复位计数一致性审计，保持T02-F06。','减少恢复/occupancy误判风险；不是当前缺R根因结论。','需新候选STA/CDC证明，不能本轮改约束。','真实生成路径Gray skew/max-delay与复位释放检查，边界reset/stall模型。')
finding('T06-F11','high','confirmed_issue','b15行为模型直接用低19位字下标、忽略mask且独立接纳读写；写数组仅同拍AW/W成立，没有覆盖桥分开AW/W接纳。',[ref('0154.v',88,102),ref('0154.v',170,220),ref('0154.v',241,242),ref('0153.v',343,373)],'不同地址低3位、mask翻转、AW先W后、同拍AW/AR；宽松模型不能拒绝原生误用。','旧整帧CRC/zlib PASS不能证明原生MC地址/mask/命令合同；也不能证明L_max=1。','模型独立执行原生合同并覆盖AW/W分别保持、全位越界、并发拒绝或明确接纳规则。','提高失败判别力，停止循环假设自证。','条件模型仍非厂商MC，不能用它最终归因板上缺R。','witness五种小图样条件模型与外部adapter正对照；真实IP合同另验。')
finding('T06-F12','high','evidence_gap','DDR预算必须包含RAW每20B占32B和RAW写/读+CMP写/读；两槽深度不是服务率。现有单路TB slot-free和93.75MB/s sink证据不证明生产双路。',[ref('0144.v',16,18),ref('0150.v',124,135),ref('0284.md',20,28),ref('0284.md',65,73)],'1080p30，RAW129600字/帧，CMP按81085字容量预算；单路四次搬运404.5152MB/s，双路809.0304MB/s，未计额外开销与重试。','仅77.76/155.52MB/s payload可能低估共享DDR需求；缓存加深不能补长期服务不足。','用最坏膨胀/真实native服务/生产slot-free/sink/双路资源联合签核；其他活动run仍只读。','建立可审计最坏服务下界，无空报性能提升百分比。','容量预算不自动成为已证明编码上界，25%仅参考。','独立重算witness预算；实际持续读写、仲裁空窗、恢复和每路服务上界后续验收。')
finding('T06-F13','info','no_issue_found','限定静态范围内，b15正常begin只选FREE、abort抑制同拍flush；同读在途的owner路由及FIFO持数机制应保留。',[ref('0144.v',141,180),ref('0144.v',268,318),ref('0143.v',75,109),ref('0036.v',16,34)],'依赖成对内部AW/Wready、有限原生响应长度、稳定producer及正常边界。','未见应直接删除slot/owner/skid/CRC的依据；F04/F05/F07不被此局部核对覆盖。','保留保护；优化须证明接受事件/恢复/所有权等价。','避免把保护状态误作冗余。','局部静态no_issue不是任意故障或板级证明。','真实DUT随机stall/abort/reset及描述符顺序scoreboard。')
finding('T06-F14','medium','evidence_gap','upstream RAW/R10F AXI分支含B响应后发布/保护位/ARM-TX-HELD与session ACK；它与b15不同。FIFO满可丢EOF标记、响应跨reset/session排空仍需该候选证据。',[ref('0098.v',292,345),ref('0098.v',392,405),ref('0098.v',887,977),ref('0101.v',397,429),ref('0101.v',711,808),ref('0101.v',974,1025),ref('0139.md',7,12),ref('0140.md',36,47)],'EOF被满FIFO阻塞时走帧内timeout；ARM前旧R/跨session取消需DRAIN和控制器契约；不能移用预览replace READY策略。','源码有保护不是当前b15集成或整板通过；旧离线closedloop report仅原候选可复用。','分清native与AXI mask/byte地址，保留事务保护与ACK；后续T11检查DMA完整外传。','防分支混拼和把预览策略用于生产DMA。','本包仅相邻存储契约，PCIe完整外传细节归T11。','绑定旧候选检查EOF丢失/timeout、cancel drain/held ACK错误session/迟到R和不可覆盖。')
finding('T06-F15','low','redundancy_candidate','仓库P1默认store/arb与b15 changed-src、旧td/src bridge并存；未选中副本可做未来来源收口候选，不能按文件数推导硬件资源浪费。',[ref('0155.al',23,35),ref('0155.al',95,109),ref('0009.v',1,7),ref('0010.v',1,19),ref('0163.v',1,18)],'以仓库同名文件或stale td/src bridge当b15实际编译实现。','容易审错版本；删除可能破坏旧候选重现。','优先清晰source-map/构建白名单；归档/删除需另授权，当前禁止删除。','降低版本误读，暂无可量化ERAM/slice收益。','必须保留历史manifest可复现性与消费者。','编译入口闭包/全部引用扫描后再考虑归档。')
put('findings.json',{'task_id':'T06.chain-storage-review','round':0,'findings':findings})

# checkpoint fields are the frozen plan's exact required schema.
rows=[]
def cp(label,stage,key,lo,hi,producer,consumer,units,clock,event,ownership,invariant,recovery,result,fid,nextcheck):
    f=bm[key]
    rows.append(dict(checkpoint=label,stage=stage,parent_task='T06',producer=producer,consumer=consumer,source_path=f['snapshot_path'],source_sha256=f['sha256'],line_start=lo,line_end=hi,input_output_units=units,clock_reset=clock,acceptance_event=event,ownership=ownership,invariant=invariant,failure_recovery=recovery,result=result,evidence=fid+'; findings.json evidence_refs; witness/result-r0.json',optimization='仅建议；不实施；见'+fid,verification_next=nextcheck))
cp('C01','1-layout','0155.al',23,109,'b15 .al','store/arb/bridge','selected sources vs stale copies','A1/DDR reset per top','File Path selection','protected legacy inputs','changed-src B0143/B0144/B0153 selected; B0163 not selected','do not replace historical inputs','no_issue_found','T06-F15','independent compile path parse')
cp('C02','1-layout','0144.v',151,164,'40bit sample lane vector','RAW pack/feeder','4x40bit in160 LSB of256;20 payload/32 DDR B','clk_a1 rst_n','wr_ready; four groups per flush','WRITING only','MODE0 and feeder preserve exact bit vector; no repack; external T02-F01 format issue remains','format fix belongs later; retain T02-F01','no_issue_found','T06-F13','T02 F01 bit provenance + feeder slices B0150:687-694')
cp('C03','1-layout','0150.v',124,160,'RAW/CMP base','slot address','RAW0 0..129599;RAW1 129600..259199;CMP0 262144..343228;CMP1 343229..424313','A1','begin/flush','two separate pairs','2944-word gap and within2^24 words at defaults','SIMULATION assertions only','no_issue_found','T06-F13','independent range arithmetic')
cp('C04','1-layout','0144.v',178,206,'word_index','PAXI27','word vs native unit vs byte offset','A1->DDR','bridge enqueue then native handshake','slot word offset','native conversion missing; ref<<3','not fixed by retry','confirmed_issue','T06-F01','address/mask witness')
cp('C05','1-layout','0153.v',97,138,'32bit word address','27bit WF/AF','truncate low27; ref<<3 needs input<2^24','A1->DDR','WF/AF push','range must remain in slot','default max424313 fits19 bits; arbitrary parameter overflow unguarded','future check before truncation','evidence_gap','T06-F09','capacity±1 and addition overflow')
cp('C06','1-layout','0144.v',151,184,'wr_data/keep','slot byte stream','MODE0 5B/group;MODE1 popcount keep and 32B words','A1','wr_ready','WRITING','RAW no per-row padding; upper96 zero; partial mode1 assumes prefix keep','reject nonprefix/overlength','evidence_gap','T06-F09','last/keep/stride edge cases')
cp('C07','2-paxi','0153.v',343,348,'bridge full write','generated PAXI','mask32 all1 vs reference0','DDR','native W','queued write owns data','wrapper permutes no inversion','qualify same-IP contract','confirmed_issue','T06-F02','partial/all mask contrast')
cp('C08','2-paxi','0153.v',338,378,'WF FIFO','AW/W native','one256bit word; AW/W independent seen flags','DDR rst_n from A1','both seen before wf_pop','one FIFO word held until both','native W/AW stall uses stable wf_rdata; pop bubble avoids duplicate','pending clears on reset','no_issue_found','T06-F13','independent AW-before-W/W-before-AW; model gap F11')
cp('C09','2-paxi','0143.v',59,82,'two store requests','internal bridge FIFO','AW/W atomic pair; internal ready tied by bridge','A1 synchronous reset','s_awvalid && s_awready && s_wready','selected master only','arb combinational grant can change if other req appears under stall; internal accept only when paired ready','no generic AXI compatibility claim','evidence_gap','T06-F03','stall+new contender interface monitor')
cp('C10','2-paxi','0153.v',396,407,'AF','native read','one AR through RLAST','DDR','AR handshake then RLAST','ar_busy owner window','single AR does not serialize AW; first-cycle R needs real latency assumption','purge overrides busy','evidence_gap','T06-F03','native command and response timing contract')
cp('C11','2-paxi','0143.v',75,109,'RAW/CMP AR','one read owner','256bit response, no tag','A1','AR handshake/R take','rd_owner held until R or raw abort','route only owner; round-robin successful grants','raw-only abort preserves CMP owner','no_issue_found','T06-F13','owner/fairness with bounded response')
cp('C12','2-paxi','0153.v',338,407,'write and read engines','shared MC','AW/W/AR possible same cycle','DDR','independent handshakes','no shared command owner','single-AR is distinct from AW/AR exclusivity','native acceptance unknown','evidence_gap','T06-F03','single-command contrast')
cp('C13','2-paxi','0036.v',8,34,'WF32/AF16/RF16 FIFO','registered output/skid','FIFO entries not byte payload; prefetch holds','independent FIFO releases','push=w_valid&&w_ready; fetch only space','FIFO full forbids writes; data held on stall','do not delete skid/full; full raw ingress rejects frame','per-domain reset FIFO only','no_issue_found','T06-F13','random stall/same-cycle take refill')
cp('C14','2-paxi','0153.v',229,272,'RF pop count Gray','DDR rf_path_empty','5bit modulo count and synced skid empty','A1->DDR direct reset','push&&rf_wready; rf_pop','no-overflow relies max native burst<=16 and counters coherent','empty gate conditional; L_max not independently proven','guard/reset and skew caveat','evidence_gap','T06-F10','native burst bound; Gray/reset formal/STA')
cp('C15','2-paxi','0157.sdc',35,57,'A1-released reset/Gray','DDR FSM','clock groups and constrained original pointer buses','A1187.5/DDR~200 MHz','reset release and CDC sampling','counter/FSM reset must match FIFO','rf_pop_gray not among constrained paths','preserve T02 F06/diagnostic thin STA','evidence_gap','T06-F10','new candidate CDC and reset qualification')
cp('C16','3-ownership','0144.v',141,180,'wr_begin','FREE->WRITING','2-slot state','A1','wr_begin&&wr_begin_ready','never write READY/READING at normal length','abort suppresses same-cycle consume/flush','abort+begin uses other FREE slot','no_issue_found','T06-F13','simultaneous begin/last/abort/close')
cp('C17','3-ownership','0144.v',301,344,'final flush into WF','READY->READING','logical enqueue vs native visible','A1->DDR','wr_last&&wr_ready publishes','consumer may immediately open','no final native fence in b15','preview native fence is distinct reference','evidence_gap','T06-F04','read-before-visible trace')
cp('C18','3-ownership','0144.v',174,180,'late CSI verdict','published RAW slot','good/abort arrives after ROI last','camera->A1','abort_now=wr_abort&&wr_active','READY/READING no revoke','late OR cannot revoke consumed frame','wait verdict plus write visibility','confirmed_issue','T06-F06','bad suffix/CRC/FE with early consumer')
cp('C19','3-ownership','0150.v',434,465,'SOF admission','RAW begin/skid','raw_id successful admissions only','A1','e_sof&&raw_begin_ready','full queue skip whole frame','deny counters separate DDR not ready/no free; not capture_seq','next SOF re-admit; epoch absent','evidence_gap','T06-F07','full queue and capture/admission/session identity')
cp('C20','3-ownership','0144.v',268,297,'begin/abort','slot_seq/pub_tgl','onebit order state','A1','begin toggles even aborted frame','oldest must match descriptor FIFO','abort holes cause seq collision and newest first','source anchored witness A/B/Cabort/D','confirmed_issue','T06-F05','independent FIFO order oracle')
cp('C21','3-ownership','0148.v',314,332,'frame descriptor commit','2-entry queue','same-cycle push/pop count, IDs/lengths','A1','dq_push_ok/dq_pop_ok','queue full may push when pop','queue count corrected but store order F05 remains','E_OPEN mismatch counted not rejected','confirmed_issue','T06-F05','descriptor vs selected slot identity')
cp('C22','3-ownership','0144.v',187,215,'RAW read','timeout/guard/retry','8192/32768 A1 cycles;2 retries','A1','only armed R_RW counts timeout','same slot stays READING','retry from word0 and reset partial encoder/CMP','giveup frees after retry budget','no_issue_found','T06-F13','response-drop/guard/budget; not hardware')
cp('C23','3-ownership','0153.v',275,336,'raw timeout toggle','AF/RF/skid purge','DDRguard65536;A1hold70000','A1/DDR','purge_evt; local drain','WF writes intentionally retained','window drains stale responses but no ID/epoch','oldR after guard can enter new busy','evidence_gap','T06-F07','late-window boundary/new-session negative')
cp('C24','3-ownership','0150.v',630,647,'read timeout','encoder/CMP abort tail','orphan output drain16 cycles','A1','raw_rd_timeout highest priority','no partial CMP publish','finite tail needs core maximum drain contract','retained b13 logic; not delete','evidence_gap','T06-F07','late encoder output beyond tail')
cp('C25','3-ownership','0150.v',661,684,'top watchdog','raw_rd_close','16777216cycles~89.478ms','A1','F_WAIT WD branch','store only closes R_HOLD','R_AR ignores close and no timeout purge','may wedge raw slot','confirmed_issue','T06-F08','state trace plus bounded RTL future')
cp('C26','3-ownership','0150.v',569,587,'CMP store','UART reader','RETRY_EN0 variable-length','A1','rd_open then response','READING held until close','lost CMP R has no equivalent watchdog; no unconditional fairness/liveness','requires future recovery contract','evidence_gap','T06-F07','lost CMP R / backpressure / reset')
cp('C27','3-ownership','0103.v',111,143,'two AXI writers','shared AXI write port','AW/W/B response and byte-mask','DDR/reset domain of separate branch','hold grant while selected busy','not native PAXI arbiter','transaction-grant switching requires bounded busy; not deadline fairness','preserve response owner until completed','no_issue_found','T06-F14','separate candidate arbiter closedloop evidence')
cp('C28','3-ownership','0098.v',292,345,'camera RAW/R10F','AXI writer FIFO','43bit SOF/EOF/bad+packed group','cam/ddr separate resets','f_wr=push&&!wfull','frame_armed then verdict_bad','full can drop EOF; timeout fallback not sticky EOF replay','retain bad/EOF count and scope','evidence_gap','T06-F14','full on EOF/no EOF recovery')
cp('C29','3-ownership','0098.v',887,977,'RAW/R10F writes','protected publication','AXI B then header rewrite B then good verdict','DDR','rw_done_r && S_WAIT && verdict','protect actual pub_par; releases explicit','not b15 and not generic PAXI mask contract','bad/noack never good publish','no_issue_found','T06-F14','last B/header error/publication/release collision')
cp('C30','3-ownership','0101.v',711,808,'ARM/claim/TX','HELD/ACK_RELEASE','session+sequence bound; SENDING conceptual=G_TX','tl/DDR','ACK only matching held_seq/held_sess','held remains on bad ACK; cancel TX drains','preview READY replacement cannot justify DMA reuse','cancel waits pending beat/package drain','no_issue_found','T06-F14','wrong ACK/session/cancel/late R future T11')
cp('C31','4-budget-model','0154.v',88,102,'behavioral AW/W','array word address','low19 array index;mask ignored','sim DDR','AW/W same-cycle only','independent AR queue; no real conflict','model green cannot reject native misuse','conditional contrasts only','confirmed_issue','T06-F11','independent mask/address model mutation')
cp('C32','4-budget-model','0150.v',124,135,'1080p RAW','DDR shared service','129600 words vs81000 densely packed words','30fps;A1187.5/DDR~200 MHz','four memory moves per frame','2 RAW+2 CMP; queue depth not fps','single404.5152MB/s dual809.0304MB/s capacity budget','plus retry/header/command/refresh overhead','evidence_gap','T06-F12','independent byte/word/service-rate re-count')
cp('C33','4-budget-model','0284.md',20,28,'separate P4 TB','production pacing','TB slot-free93.75MB/s sink single core','187.5MHz offline','scope G0_feasible_for_scope','production slot-free not established','strict serial and incompressible sink gaps retained','no rerun of long four-frame matrix','evidence_gap','T06-F12','bind separate manifest; no production extrapolation')
cp('C34','4-budget-model','0168.md',44,85,'b15 historical reports','G2-G5 qualification','SWNS+.012ns diagnostic only;H4_UNRESOLVED','historical candidate','old download/150s observation only','no new bit/board test','report L_max and root-cause claims not adopted; audit fixes cam11/cam12','new G2-G5 N/A per plan; old gaps retained','evidence_gap','T06-F11','native contract and transaction traces future b17')
cp('C35','4-budget-model','0169.md',1,30,'b17 frozen plan','future native contract','plan only in baseline','no execution','not an implemented candidate','protect entire active b17 directory','no merge/new result chasing','future authorized b17 own evidence','evidence_gap','T06-F03','planner preserves pending implementation')
with (OUT/'checkpoints.csv').open('w',encoding='utf-8-sig',newline='') as h:
    w=csv.DictWriter(h,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
put('coverage-r0.json',{'semantic_steps':[{'step':1,'checkpoints':['C%02d'%i for i in range(1,7)]},{'step':2,'checkpoints':['C%02d'%i for i in range(7,16)]},{'step':3,'checkpoints':['C%02d'%i for i in range(16,31)]},{'step':4,'checkpoints':['C%02d'%i for i in range(31,36)]},{'step':5,'artifacts':['review.md','checkpoints.csv','findings.json','source-map.json','witness/','commands.json','lessons.md','manifest-r0.json']}],'checkpoints':len(rows),'findings':len(findings),'blank_cells':sum(v=='' for row in rows for v in row.values()),'coverage':'all planned semantic clusters represented; independent tester pending'})
put('lessons.md','''# T06 可复用经验

- 相同总线宽度不表示同地址单位。内部256bit字、PAXI原生单位和字节偏移必须分开；只在唯一边界转换并检查扩展前范围。
- publication不是FIFO enqueue。独立WF/AF跨域队列没有天然先写可见保证；发布要同时满足最终内容可见和源帧good裁决。
- 排序位必须与真实提交语义一致。begin和abort消耗一位代际会导致两槽同seq，优先槽编号不能替代真实FIFO顺序。
- watchdog发close不等于消费者已处理。必须逐状态核对取消：R_AR忽略rd_close，原R_RW timeout也不会在R_AR发生。
- 固定guard不是任意迟到响应隔离证明，有限时间窗需要控制器最大生命周期/flush合同。FIFO复位同步也不覆盖全部桥FSM和新增Gray约束。
- 二槽容量不产生fps。RAW每20B有效数据占32B DDR字，所有读写与CMP最坏回退都要计入，且不能把槽深度推导为持续服务率。
- DeepSeek仅作最小上下文算术辅助。其回复错误地把槽深度推成60fps、把MODE1按20B计算，并含非JSON表达式；均拒绝，数值由本包独立重算。
- 本轮只读审查；没有改生产RTL、约束、b17或其他活动run；没有删除、TD、硬件或发布操作。
''')
put('review.md','''# T06 存储链路细节审查（round0）

本包按原计划五步完成只读审查产物，待独立综合测试。最优先的新发现是 **begin/abort消耗一位排序状态可导致READY槽逆序，进而错配导出描述符（F05）**。已知原生地址与完整写mask差异继续保留（F01/F02）；没有实施优化或新候选。审查通过仅表示完整性与结论可靠，不代表被审查DUT已通过，不关闭父T06或整链路。

## 输入、候选与边界

统一baseline manifest SHA256=c08adc09b364828fee5d94953a89898a3220af8c8f99cdec52404fec06f74c96，287份快照在组装时逐项核对。T02已验manifest=af32567395a3083b3b5005df40cfc37857f54b133293a644782eca9d6a34b997，独立报告=c96751cda203daf4c53a47909760f7d5b2edd3b88abdedbda0e625d67d2fb920；其329个冻结文件逐项复核，全部只读引用。控制副本及恢复授权绑定于control-bindings.json。HEAD沿原计划27c596b01cd961dfa9d0850e4fbf879fe249de90，预存dirty/删除未知所有者全部保护。

实际b15编译入口B0155选changed-src store B0144、arb B0143、bridge B0153；旧td/src bridge B0163不能替换当前实际源。source-map.json记录原路径、快照、SHA、编译路径和旧candidate字段；只认证审查输入，未认证所有依赖到旧bit。b17在统一baseline只含计划/指南/索引，保留待实施状态；不跟随其活动目录变化。

三条存储分支分别处理：b15 A+ UART双RAW/双CMP槽；原生三槽preview store B0040；独立upstream RAW/R10F AXI生产参考B0098/B0101/B0103。后者有B响应、字节地址与AXI byte-enable，不能把native PAXI mask极性覆盖过去。预览replace READY不能作为DMA可覆盖依据。

## 五步覆盖

1. **布局/单位/容量**（C01–C06）：默认RAW每4个40bit组用一个256bit字，20B有效、32B传输；raw0=0..129599，raw1=129600..259199，cmp0=262144..343228，cmp1=343229..424313，间隙2944字。19位最大字下标在2^24字容量内；改参后的32bit加法/27bit截断/24bit原生转换需额外检查。RAW无行padding，行480组对应120字，RAW尾帧整字。MODE1 keep为连续低位和非末全字的前提必须保留，任意稀疏keep不能由popcount自动紧凑化。
2. **PAXI/CDC/接纳**（C07–C15）：地址漏左移与mask相反是确定源码差异；真实MC内部仍未证。桥AW/W使用aw_seen/w_seen分别持有直到双完成，WF pop后有等待；模型只同拍写，未覆盖分开接受。内部AW/W为原子pair，store忽略AWready依赖arb/bridge绑定；不能泛化为标准AXI master。arb grant未在stall锁定，新请求可能改变下游mux，需限定接口合同。读owner在AR建立到R/abort，轮转只提供在服务有界前提下的成功事务公平，不能承诺最大等待时间。bridge单AR至RLAST不是AW/AR互斥，L_max=1无独立原生证明。FIFO reset有各域释放，桥自身DDR FSM仍用A1释放复位，rf_pop_gray新增跨域未见专属skew约束。
3. **所有权/发布/恢复**（C16–C30）：正常begin仅取FREE、abort压制同拍flush且可在另一FREE槽同拍begin，这些保护不能删。RAW/CMP last仅入WF就READY，没有最终原生可见fence（F04）；晚CSI裁决只影响仍WRITING的槽，不能撤销已READY/READING（F06，继承T02-F02/F03）。一位slot_seq在begin而非真实publish翻转，abort制造排序歧义（F05）。descriptor队列同拍push/pop计数本身有统一接受点，但E_OPEN ID/长度错配只计错继续发，无法掩护F05。

   raw timeout仅R_RW且AR已被store侧接受时计8192 A1周期；实际是AF enqueue而非native MC接纳，不能称端到端MC延迟计时。same-slot retry最多2次，GUARD32768 A1周期；桥A1hold70000、DDRguard65536且保持WF。窗口内旧R排空有结构支持，超过窗口并落到新ar_busy的旧R没有tag/epoch可分（F07）。top watchdog在F_WAIT超16777216周期发rd_close并退IDLE，但store仅R_HOLD受理，R_AR可永久挂住（F08）；CMP RETRY_EN=0无同等读丢失恢复。raw_id是admission，不是capture_seq；业务reset也没有跨旧MC响应的独立代际保证。

   upstream RAW/R10F等待EOF/good、payload/beat总量、B响应及头重写后裁决，按实际pub_par设置protect位；满FIFO可丢EOF并依赖timeout。ARM/TX/HELD/session ACK与cancel DRAIN保护分开记录，错误ACK不释放HELD。旧closedloop报告限定其冻结候选；该分支完整DMA/PCIe外传后续T11审查，不把源码存在写成b15已接入。
4. **服务预算/模型见证**（C31–C35）：witness脚本源锚定地重算与构造反例，结果见witness/result-r0.json。payload每路77.760MB/s、双路155.520MB/s；RAW因20/32布局每方向124.416MB/s。按CMP槽容量2594720B预算（不宣称已证明编码膨胀上界），RAW写+读+CMP写+读=404.5152MB/s/路，双路809.0304MB/s；25%参考=505.644/1011.288MB/s。未计命令、refresh、额外头/fence和重试，因此是预算基础，非实测保证。总421370个256bit搬运/帧，单路12,641,100次/秒，双路25,282,200次/秒，需真实共享服务率与空窗资格。

   两槽只给深度，不能推出60fps；最坏持槽时间/RAW读后释放/生产CMP回收决定是否持续。P4单核187.5MHz、TB slot-free、93.75MB/s sink、行为DDR只在原scope成立；strict serial和raw不可压缩sink门槛保留，生产双路未证明。b15模型低19位数组地址、忽略mask、独立AW/AR，旧CRC全绿无法排除native误用。小图样五模型只说明给定合同下的错误/适配，不复现或归因真实MC缺R。
5. **交付/冻结**：35行checkpoints、15项findings及source-map、witness、commands、lessons、局部引用与哈希核查，所有开发活动结束后唯一manifest-r0.json。详细触发/收益/代价/后续验证在findings，不新增正式任务。

## 可复查见证与独立复核入口

- F05合法顺序轨迹A(slot0),B(slot1),C(slot0 abort),D(slot0)导致B/D同seq=1、expect=1，优先槽0返回D而描述符首项B。测试者应以独立FIFO提交oracle、穷举轨迹或实际store微仿真验证，不仅复读开发模型。
- 两字不同图样分别用宽松字地址、native addr>>3、mask1屏蔽、联合合同及外部address<<3/mask0适配对照。预期不一致0/1/2/2/0。这是离线算术模型，非厂商MC或真实DUT仿真。
- 单字WF已入队而native写阻塞、AF独立可读的发布轨迹显示read-before-visible允许窗口；没有声称已在实际板上捕获。
- R_AR下watchdog close不被store case处理，以及旧R超过guard落入新busy的归属谓词，均为源锚定状态/布尔见证，非cycle-accurate仿真。

## 优化顺序及已有证据资格

先正确性：原生地址/mask与接纳合同、F05顺序、发布可见/晚裁决、F08取消状态与代际隔离；再可观测性：失败AR完整地址/低3位、实际AW/W/AR接纳和写可见；再吞吐：生产slot-free/共享服务/真实sink/双路资源；最后来源收口。没有依据直接删除FIFO、skid、CRC或slot状态；同名源码副本只作可维护性冗余候选，没有ERAM/slice节省承诺。

旧b15 G2=原报告诊断SWNS+0.012ns而非生产STA/CDC签核；G3=原一次SRAM下载/150秒观察；G4=H4_UNRESOLVED、enc/exported=0；G5持续生产服务not_run。旧报告“已排除bridge根因”“L_max=1”等外推不采用。审计对cam11/cam12与均值失败字编号的纠正保留；不追逐跨快照后的三帧完成状态，报告内部已写完成而审计早期写仍运行，仅按各自时点资格记录。新G2–G5依冻结计划not_applicable：本包只读，不交bit/签核；这不删除原硬件缺口。

未运行TD、综合、布线、STA/CDC工具、RTL/完整帧仿真、bitgen/CWC、下载、COM/JTAG、Flash、板卡/RK或网络下载；不使用共享库/盘符。未修改生产、T02、baseline、任务板或其他run。回退为保持全部原候选；若审查结论错误，只在本任务新轮修正文档并重新冻结，旧结果保留。所有发现等待独立综合测试，当前无DUT通过声明。
''')
put('assembly-result-r0.json',{'created_utc':now(),'baseline_files':len(verification),'dependency_files':len(dep['files']),'checkpoint_count':len(rows),'finding_count':len(findings),'control_count':len(controls),'production_changes':0,'hardware_actions':0,'result':'ASSEMBLY_COMPLETE'})
print('ASSEMBLY_COMPLETE checkpoints=%d findings=%d baseline=%d dependency=%d'%(len(rows),len(findings),len(verification),len(dep['files'])))
