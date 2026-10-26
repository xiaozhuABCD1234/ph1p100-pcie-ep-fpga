"""Generate audit artifacts only beneath this task directory; no production edits."""
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from datetime import datetime, timezone

OUT = Path(__file__).resolve().parent
RUN = OUT.parent
ROOT = RUN.parents[2]
TASK = 'T10.chain-transform-review'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def readj(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def dump(name, value):
    (OUT/name).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

baseline = readj(RUN/'baseline/source-manifest.json')
sources = {}
for item in baseline['files']:
    assert sha(item['snapshot_path']) == item['sha256']
    sid = 'B'+Path(item['snapshot_path']).stem
    sources[sid] = dict(item, source_id=sid)
for i,item in enumerate(readj(OUT/'supplemental-sources.json'),1):
    assert sha(item['snapshot_path']) == item['sha256'] == sha(item['source_path'])
    sid = 'S%02d'%i
    sources[sid] = dict(item,source_id=sid)
deps=[]
dispatch=readj(OUT/'controls/dispatch.json')
for dep in dispatch['completed_dependencies']:
    mp=Path(dep['manifest_path']); rp=Path(dep['report_path'])
    assert sha(mp)==dep['manifest_sha256'] and sha(rp)==dep['report_sha256']
    m=readj(mp)
    for item in m['files']:
        assert sha(item['path'])==item['sha256'], item['path']
    assert rp.read_text(encoding='utf-8').startswith('### 判定：PASS')
    deps.append(dict(dep,checked_files=len(m['files']),result='same accepted input'))
dump('dependency-qualification.json',dict(task_id=TASK,dependencies=deps,
     baseline_files=len(baseline['files']),baseline_manifest_sha256=sha(RUN/'baseline/source-manifest.json'),
     old_dispatch_policy='Old dependency controls remain immutable; current T10 controls independently copied.'))

def ref(sid,a,b):
    s=sources[sid]
    assert 1<=a<=b<=len(Path(s['snapshot_path']).read_text(encoding='utf-8-sig').splitlines())
    return dict(source_id=sid,source_path=s['source_path'],snapshot_path=s['snapshot_path'],
                sha256=s['sha256'],line_start=a,line_end=b)

findings=[]
def finding(n,severity,kind,claim,refs,reproduction,impact,recommendation,benefit,tradeoff,validation):
    findings.append(dict(finding_id='T10-F%02d'%n,severity=severity,kind=kind,claim=claim,
      evidence_refs=[ref(*r) for r in refs],reproduction=reproduction,impact=impact,
      recommendation=recommendation,expected_benefit=benefit,tradeoff=tradeoff,validation=validation,
      disposition='review_only; no production fix; independent acceptance pending'))

finding(1,'high','confirmed_issue','继承T02-F01/F02/F03及T06-F04/F05/F06/F07：A+字节往返、CRC和Adler只能证明给定输入自洽，不能恢复已误解释的样本、撤销ROI后才判坏的CSI帧或证明DDR可见/事务归属。',
 [('B0150',529,541),('B0146',393,409),('B0150',837,860)],
 'T02/T06已验输入契约；sample lanes错误仍可被编码并解回同一错误字节。',
 '像素真值、最终好帧资格与编码格式正确性分账；raw_id不是capture_seq。',
 '先修上游格式与最终裁决/写可见/epoch，再绑定原始像素oracle；本包不实施。',
 '避免CRC全绿掩盖输入语义错误。','裁决可能延长槽持有；需要跨包协议。',
 '真实checked CSI→重打包→store→编码→独立像素oracle，晚CRC/FE/旧响应负例。')
finding(2,'high','confirmed_issue','a1_frame_top在abort或重复SOF与最后输出握手同拍时仍frame_commit；顺序分支明确让提交胜出，与本模块“Abort never commit”说明不一致。',
 [('B0146',11,14),('B0146',171,187),('B0146',326,341),('B0146',542,556)],
 'frame_active=1,svalid=slast=out_ready=1,killed=0,abort=1：组合frame_commit=1且abort分支条件=0。见witness/result-r0.json。',
 '模块接口允许取消同拍提交；顶层描述符以a1_commit生成。默认b15时序/板上可达性未证明。',
 '明确abort与完成优先级并使提交/存储/描述符一致；若完成优先是产品语义，需显式合同及上游保证。',
 '防取消事务被当作完整结果。','不能只门控last而留下store/描述符分裂。',
 '独立测试用时序判据覆盖最后字stall→abort→ready及同拍重复SOF，含下一事务恢复。')
finding(3,'high','confirmed_issue','现PC消费者a1_pattern.inverse_xform对prep=1使用halfw//4并总读四plane，不能覆盖RTL允许的W%4==0几何和奇数H尾行；expected_xform还对奇数尾补不存在的第二行。',
 [('B0146',70,78),('B0146',416,422),('S05',88,165),('B0054',82,86)],
 '独立RAW样本+冻结a1_ref生产软件向量：W12H2 prep1返回错像素；W8H3/W16H3 prep1抛IndexError；W8H2和prep0为正对照。',
 '合法小几何可能无法被当前UART消费者正确恢复；默认W1920H1080不触发本项。',
 '统一合法几何/尾行与每plane非整4组处理，或显式拒收并收窄接口；不得假称全参数已支持。',
 '避免黄金向量与消费者共同排除合法边界。','未来需固定协议版本与边界策略。',
 '测试者用不同样本/手工反交织oracle核对W4、12、20及奇数H；保留偶数1920正例。')
finding(4,'high','evidence_gap','理想精确bit offset下回退上界为raw+5*NBLK+6=2,594,706B；当前S_WAIT用已消费obits计成本，未等opq排空，尚未证明它等于下一块真实起始opq_bit_off。CMP槽14B余量不能反证此条件。',
 [('B0145',488,495),('B0145',719,727),('B0145',1322,1343),('B0145',1371,1397),('B0145',1642,1654),('B0145',1668,1677),('B0150',124,138)],
 '静态见S_REPLAY_E末次入队后直接S_WAIT；符号状态consumed off6+pending2=>actual0，calc overhead42/actual40，候选41可按错误成本入选；此状态在真实RTL可达性未证。',
 '当前容量上界对混合fixed/stored、停顿和残留offset的证明缺失；不声称已发生RTL/板级溢出。无offset保证的宽松界2,594,841B大于槽。',
 '后续证明队列offset一致或在成本边界使用准确累计offset，并绑定容量硬截止。',
 '使容量预算与实际编码最坏界闭合。','不能靠扩大CMP掩盖成本/事务问题；容量与T06服务预算联动。',
 '针对前块fixed尾位0..7/后一块近阈值候选/所有sink stall独立记录cost seed与真实边界，检查单调界；不要重跑四帧矩阵代替。')
finding(5,'medium','confirmed_issue','冻结pc_decode只用zlib.decompress，接受多余zlib尾字节和非零stored对齐位；重算外层长度/CRC后其全部检查仍为true。已有strict inflater具备不同拒收语义但该消费者未使用。',
 [('B0054',67,95),('S02',1,16),('S02',247,295)],
 '同一合法stored流分别追加00、把stored头bit3置1；重算44B外头及CRC；PC全检查true，独立严格解码器拒收。',
 'CRC只能检查声明的字节完整性，不能替代规范性拒收；本项是软件消费者缺陷，不是编码RTL已产生非法流。',
 '后续将严格单member/零对齐/精确长度规则接到实际消费者并保持错误类型。',
 '防伪有效码流与互通差异。','严格拒收可能影响历史宽容样例；需版本清单。',
 '独立测试者以不同尾长度/拼接member/损坏Adler/截断做变异；必须同时保留合法fixed/stored正例。')
finding(6,'low','confirmed_issue','Gaussian stream注释声称CFA parity clamp，实例实际PARITY_CLAMP=0为Y8普通replicate；HE注释<=~3.3k与当前14相位*256=3584周期的LUT步骤自身已不符。',
 [('B0027',4,9),('B0027',83,95),('B0023',220,251),('B0028',21,23),('B0028',456,519)],
 '边界非恒定图可区分replicate与反射到相邻同色；HE LUTGEN相位0..13每项14周期且非零den帧执行全部。',
 '文档会误导oracle和持续服务预算；不称Gaussian数据通路数学错误。',
 '以当前实例和实际相位更新注释/服务预算；本包仅记录。',
 '减少错误边界模型和低估帧间空窗。','不改变既有Y8算法定义。',
 '边缘脉冲区分两种clamp；以状态计数器实测完整HE publish/clear空窗。')
finding(7,'medium','no_issue_found','限定标量/静态范围：Gray加权和、Gaussian一次舍入位宽、HE四lane分bank/前帧LUT/首帧identity/坏帧不发布/双bank发布有明确实现依据；这不等于当前RTL任意stall/reset已测。',
 [('B0031',25,63),('B0027',133,186),('B0028',97,114),('B0028',232,274),('B0028',309,327),('B0028',395,429),('B0028',473,533)],
 'Gray最大65408；Gaussian最大含round=4088；HE每bank24bit、总像素<=4194304、CDF*255<=1069547520，32bit足；四lane17个同bin beat总68。',
 '未见标量溢出/同拍跨lane覆盖；RAM读后写转发、连续同bin跨拍与长stall仍需真DUT判据。',
 '保留转发、双LUT、坏帧裁决与侧带；不要按“相同内容”删副本。',
 '避免误删满足端口数与事务原子性的结构。','本包算术见证不覆盖RAM时序。',
 '不同判据复核最大值、边缘和四lane同bin；未来真DUT覆盖gap/stall/reset、连帧LUT版本。')
finding(8,'medium','evidence_gap','三算法Gray/Gaussian/HE是Bayer解马赛克后的并行Y8诊断分支；b15 A+只接packed RAW10。prep=0是变换旁路仍输出zlib，stored是变换域回退；均不是帧级原始像素RAW codec自动切换。没有三算法→A+动态模式mux。',
 [('B0029',5,30),('B0029',129,187),('B0111',27,44),('B0256',1798,1809),('B0155',71,86),('B0150',529,541),('B0146',1,19),('B0004',39,53)],
 '编译入口及实例核对；b15 .al无三算法，独立closedloop generate接sink_ready111。BPR1/Rice仅历史工作树/文档参考，主编译表不选其RTL。',
 '不能把Y8当Bayer或只改codec_id宣称BPR1/R10F/A+互通；CFA/方向源依据仍缺。',
 '后续若接入，冻结格式/精确长度/模式/帧边界选择与consumer合同；现参数固定无需虚造模式切换PASS。',
 '避免路径/颜色语义混拼。','增加真正接口/元数据，不在本轮实现。',
 '检验每个consumer格式，帧内禁止模式变更；reset/abort后新模式另帧；CFA标靶。')
finding(9,'high','evidence_gap','旧吞吐/STA/资源只对各自候选有效：P4单核187.5MHz、合成/comp proxy、TB slot-free和93.75MB/s sink；未证明自然/最坏全内容、生产slot-free、双核共享DDR/资源。',
 [('B0277',1,6),('B0285',13,59),('B0168',44,52),('B0140',7,13),('B0140',35,45),('B0283',33,40)],
 'P4 R1 4677970、R2 6449405、R3 sink_limited、R4 5928286；冷启动与稳态分开；231/289只是旧模型预算。',
 'P1080硬门槛6.25M周期/77.76MB/s每路保留，25%仅参考；旧102/300与另一200/300不能拼成当前双路资源余量。',
 '保留原候选资格与未测门槛；自然四帧/fast sink/生产调度归其他活动run。',
 '防范围外性能与板测结论。','本轮不重复长矩阵、不触硬件。',
 '未来完整候选manifest+实际STA/CDC/资源、真实DDR持续服务与双路per-stream实测。')
finding(10,'low','redundancy_candidate','raw/xform/stream/header CRC、Adler、双行bank和各分支obuf不是已证明可删的逻辑冗余；未选中的同名源/原型文件可作来源收口候选，不能按文件数宣称硬件资源节约。',
 [('B0146',189,195),('B0146',393,409),('B0146',487,529),('B0054',67,95),('B0029',191,244),('B0022',39,83),('B0026',1,7)],
 'raw CRC消费恢复像素；xform CRC分离预处理；stream/header CRC检验不同字节范围；Adler是zlib格式；obuf解耦不同sink。',
 '消费者、接受事件和故障模型不同；相等一次或无误码不能证明等价。',
 '先整理构建白名单/文档；只有消费者/故障模型等价及综合网表差分后另授权考虑删除。',
 '降低版本误用风险；无已量化slice/ERAM收益。','保留历史重现、诊断定位与RAM端口需求；当前禁止删除。',
 '逐CRC注入对应范围错误，stall/abort/next-frame；保留每消费者观测及故障覆盖矩阵。')
finding(11,'high','evidence_gap','字典用16bit blk_tag隔离block，只在reset做1024项valid sweep；有限标签回绕后旧条目存活条件尚无验证。不能把tag相等直接当无限时长会话隔离证明。',
 [('B0145',121,121),('B0145',519,524),('B0145',598,640),('B0145',921,921),('B0145',1022,1080),('B0145',1380,1388)],
 '65536块回绕，1080p每帧540块，约121.363帧/4.045秒@30fps。需保持某hash未更新跨完整周期，再使其tag/三字节/距离条件匹配；本包未生成真实RTL可达反例。',
 '潜在旧字典引用当前bank不同内容；严重性按数据正确性风险，当前为证据缺口。',
 '后续证明所有条目在回绕前无条件更新/失效，或定义可证明的回绕清理策略。',
 '使长稳字典边界有可证合同。','清表可能产生服务空窗；不能自行延伸硬件验收。',
 '缩小tag位宽的隔离变异与真实16bit长稳反例；zlib独立解码+原始字节oracle，覆盖abort重启与hash冷门项。')
dump('findings.json',dict(task_id=TASK,round=0,findings=findings))

rows=[]
def cp(label,stage,sid,a,b,producer,consumer,units,event,invariant,result,evidence,opt,nextcheck):
    r=ref(sid,a,b)
    rows.append(dict(checkpoint=label,stage=stage,parent_task='T10',producer=producer,consumer=consumer,
       source_path=r['snapshot_path'],source_sha256=r['sha256'],line_start=a,line_end=b,
       input_output_units=units,clock_reset='源文件所示同域clk/rst_n；b15 clk_a1；PHY/CDC资格继承T02/T06',
       acceptance_event=event,ownership='帧/块/sideband随真实接受事件；不同候选不共用',
       invariant=invariant,failure_recovery='保留abort/reset/旧响应边界；见发现与后续验证',
       result=result,evidence=evidence,optimization=opt,verification_next=nextcheck))

data=[
('C01','分支/编译','B0155',71,86,'b15 board','A+','RAW10 40bit','compile File Path','实际选changed-src A+','no_issue_found','F08','清晰source-map','不把源码存在当实例'),
('C02','分支/参考','B0004',39,53,'BPR1历史','R10F参考','36B内头/128B外头','历史文档而非compile','BPR1/Rice不是当前zlib','evidence_gap','F08','保留来源资格','不改codec_id伪兼容'),
('C03','输入格式/旁路','B0146',1,19,'packed RAW10','frame transform','5B/4px','in_valid&&in_ready','prep0字节旁路仍zlib','evidence_gap','F01/F08','修明确边界','原始像素oracle'),
('C04','三算法顺序','B0029',5,30,'demosaic/Gray','Gaussian及HE','4xRGB8→4xY8','共同广播take','Gaussian/HE并行非串行','no_issue_found','F08','无集成时不造mux','各port消费者确认'),
('C05','Gray位宽/舍入','B0031',25,63,'RGB8','Y8','77R+150G+29B+128 >>8','s_ready全流水使能','最大65408无溢出，2级同stall','no_issue_found','F07','保留流水','极值与stall侧带'),
('C06','Gaussian位宽/舍入','B0027',133,186,'Y8窗口','4xY8','横11bit纵13bit','pipe_en','含round最大4088，一次+8>>4','no_issue_found','F07','保留扩位','独立边界图'),
('C07','Gaussian边界/几何','B0027',66,95,'rowwin','Gaussian','W%4=0,W>=8,H>=2','cfg一次锁存','实际普通replicate与注释不符','confirmed_issue','F06','纠正文档','边缘脉冲区分parity'),
('C08','帧裁决/标记','B0023',77,114,'rowwin输入','branch marker','sof/eol/eof/abort','accept=s_valid&&s_ready','错位/超长/重SOF拒帧','no_issue_found','F07','不删marker','DUT坏帧与恢复'),
('C09','HE配置/首帧','B0028',60,88,'cfg','HE','W,H<=2048','cfg_valid&&cfg_ready','首帧identity且reset先clear','no_issue_found','F07','保持cfg合同','reset/首帧'),
('C10','HE四lane同bin','B0028',97,114,'Y8四lane','4bank hist','24bit每bin','accept&&in_frame','各lane独立计数','no_issue_found','F07','不按值相同删bank','跨拍同bin/stall真DUT'),
('C11','HE转发/停顿','B0028',232,274,'hist RAM','hist更新','+1及两级samebin bypass','we_now&&en','跨拍RAM转发需时序验证','evidence_gap','F07','保留hazard bypass','独立RAM时序oracle'),
('C12','HE前帧/坏帧','B0028',395,429,'帧EOF/abort','LUT构建','beats/rows','good_evt/abort_evt','坏帧good_d0不publish','no_issue_found','F07','前级严格几何不能省','bad FE/错行/active SOF'),
('C13','HE双LUT/原子发布','B0028',473,533,'CDF','下一帧LUT','32bit num/den,8bit q','ST_PUB bank翻转','常量帧identity，inactive bank写','no_issue_found','F07','保留pingpong','帧边界版本与最大CDF'),
('C14','HE服务空窗','B0028',456,533,'LUTGEN','CLEAR/下一帧','14x256周期加merge/clear','单相位一步','当前注释3.3k过时','confirmed_issue','F06','重算空窗','实际状态计时'),
('C15','广播/背压/复位','B0029',129,244,'Gray','3branch/obuf','data+sof/eol/eof/abort','共同ready及port各take','全-or-none，冻结侧带同步','no_issue_found','F07/F10','保留独立obuf','分支交替stall/marker'),
('C16','模式/CFA元数据','B0150',529,541,'RAW feeder','A+','prep/pred固定参数','首SOF锁存','Y8不能直接当Bayer','evidence_gap','F08','未来明确定义模式','帧内变更/重启'),
('C17','A+分块/预测边界','B0146',393,484,'RAW样本','plane/predict/pack','2行,<=4800B,10bit modulo','分组展开后core ready','plane anchor/pj归零，奇数尾一行','no_issue_found','F03/F07','保留row pair banks','独立反交织oracle'),
('C18','几何消费者','S05',88,165,'xform bytes','UART逆变换','W4mod8/oddH','软件消费精确xlen','合法几何解码失败','confirmed_issue','F03','统一支持边界','W4/12/20与奇数H'),
('C19','字典/匹配距离','B0145',519,559,'block bytes','LZ77','pos严格较前/dist<=2048','hit2寄存谓词','block-local tag/range/三字节比较','evidence_gap','F11','证明tag回绕','冷门hash跨65536块'),
('C20','匹配长度/投机abort','B0145',1446,1575,'candidate','fixed/stored选择','len3..258','SCAN/EXT/MCHK','overflow只放弃candidate仍stored','no_issue_found','F04/F07','保留候选与原块','长度3/258/末尾边界'),
('C21','编码bit序','B0145',346,405,'literal/length','LSB packer','反转fixed码/extra bits','cp_en','BFINAL/BTYPE和EOB分开','no_issue_found','F07','不混淆byte端序','zlib+strict小见证'),
('C22','候选重放/尾位','B0145',1642,1687,'candidate RAM','opq','rbits_left精确bit','opq_accept','尾字节仅发送剩余位','no_issue_found','F04/F05','保留bits计数','fixed所有尾offset'),
('C23','stored/膨胀容量','B0145',1371,1397,'offset seed','cost选择','bit成本→byte容量','S_WAIT','实际offset一致性未证','evidence_gap','F04','先证明bound','近阈值+sink stall'),
('C24','stored LEN/尾零','B0145',839,890,'块','zlib','LE LEN/NLEN,zero pad,BE Adler','opq_accept','补位0且精确最终字节','no_issue_found','F05/F07','区分bit pad/keep','非零pad变异'),
('C25','Adler范围/扩位','B0145',1133,1155,'accepted xform bytes','Adler wide','mod65521,22/35bit','in_acc/块尾fold','不覆盖头或原始RAW','no_issue_found','F07/F10','保留格式校验','独立Adler与最大块'),
('C26','CRC与精确长','B0146',487,539,'raw/xform/stream','descriptor','B单位/valid keep','实际接受处更新','不同CRC覆盖不同域','no_issue_found','F01/F10','不按相同结果删CRC','分域故障注入'),
('C27','尾word保持','B0146',518,556,'core byte','32bit skid','keep1/3/7/f','svalid&&ready','invalid lane无零保证，只认keep','no_issue_found','F07','完整字同拍refill未实现仅性能取舍','stall/keep归属'),
('C28','abort提交裁决','B0146',326,341,'cancel','commit','帧事务','最后字握手同拍','abort-never-commit被违反','confirmed_issue','F02','先统一事务优先级','时序独立判据'),
('C29','raw_id/descriptor/恢复','B0150',630,719,'RAW timeout/feeder','CMP事务','raw_id/cmp_id,16cycle orphan tail','a1_commit/abort','T06顺序/旧响应缺口不能忽略','evidence_gap','F01/F02','绑定epoch/取消','超时+迟到输出+下一帧'),
('C30','严格软件消费','B0054',67,95,'zlib payload','PC inverse','精确stream_len/CRC','软件decode','CRC全真不保证规范尾部','confirmed_issue','F05','采用严格入口','拼接/尾零/截断'),
('C31','吞吐/冷启动/sink','B0277',1,6,'旧四帧矩阵','P1080结论','cycles,MB/s','稳态Sss非cold','合成/proxy/slot-free限定','evidence_gap','F09','不重复另一run矩阵','生产sink与自然内容'),
('C32','STA/资源/候选资格','B0168',44,52,'旧b15报告','本审查引用','102/300,+0.012ns','原候选','非本轮STA/双核签核','evidence_gap','F09','来源分列','未来同DB/bit绑定'),
('C33','冗余候选/消费者','B0022',39,83,'各branch','独立sink','8slot sideband FIFO','push/pop','端口/故障模型不等价','redundancy_candidate','F10','先收口文档/白名单','网表差分后另授权'),
]
for args in data:
    cp(*args)
with (OUT/'checkpoints.csv').open('w',newline='',encoding='utf-8-sig') as f:
    writer=csv.DictWriter(f,fieldnames=list(rows[0]));writer.writeheader();writer.writerows(rows)
used=set(r['source_id'] for x in findings for r in x['evidence_refs'])|set(x[2] for x in data)
dump('source-map.json',dict(task_id=TASK,baseline_manifest=str(RUN/'baseline/source-manifest.json'),
 baseline_manifest_sha256=sha(RUN/'baseline/source-manifest.json'),sources={k:sources[k] for k in sorted(used)},
 compiled_top='p2_a1_board_top',compile_entry_source_id='B0155',
 branches=[dict(name='b15 A+ UART',status='compile-selected A only RAW10 -> transform -> LZ77/fixed or stored -> zlib -> CMP/UART'),
 dict(name='upstream closedloop algorithms',status='separate CLOSEDLOOP_EN diagnostic demosaic/Gray -> parallel Gray/Gaussian/HE, not connected to A+'),
 dict(name='RAW/R10F PCIe',status='separate production reference, no compressed codec adapter established'),
 dict(name='BPR1/Rice',status='historical separate worktree/reference; not selected by b15 compile; not revalidated'),
 dict(name='bounded Gaussian frame',status='unselected prototype; not streaming performance evidence')],
 consumer_references=dict(S01='software reference, hash/tokenization differs from RTL; decoder tests are semantic, no byte-identical RTL claim',
 S02='strict independent decoder',S05='actual pc_decode inverse dependency')))
dump('deepseek-result.json',dict(task_id='9d5be9d9bf284ed0aeac1c74c51f161e',project_root=str(ROOT),
 status='completed',rounds=1,usage=dict(prompt_tokens=882,completion_tokens=2745,total_tokens=3627),
 pending_operations=[],scope='pure arithmetic and witness idea; no files, shell or decisions',
 answer_excerpts=['B_max(H) = ceil((48+38442*f+19242*h)/8)',
 '1080p upper bound 2594841 B', 'approximately 968 bit (about 31 words) exceeds capacity'],
 acceptance='No worker claim adopted without independent derivation; capacity-overflow inference rejected'))
(OUT/'deepseek-review.md').write_text('''# DeepSeek辅助复核

只向官方worker发送W/H、4800B块、stored成本与CMP字数；一轮completed、无操作请求，因此没有pending call_id需要resume。worker不访问文件，不承担最终判断。

拒绝其“每像素5字节”、偶数H中间公式、968bit约31字及从宽松上界推断实际stored溢出的表述。968bit约3.78个256bit字；worker给出的2,594,841B只是逐块独立max pad的宽松上界，不能称全stored实际长度。精确offset选择条件成立时用ceil累计成本归纳得到raw+5B+6=2,594,706B；全stored每块自然字节对齐。

Codex另从真实RTL识别obits/opq_bit_off尚未证明相等的问题，见F04。此问题并非worker发现，也不使用worker的错误推断充作缺陷。小见证自行编写并以zlib/严格解码/边界公式交叉核验；最终验收由独立综合测试者完成。
''',encoding='utf-8')

(OUT/'review.md').write_text('''# T10 算法与压缩细节只读审查（round0）

本包完成五步审查材料，等待独立综合测试；未实施优化，也未签核被审查DUT。33个检查点覆盖计划语义簇，11项发现保留已知问题和证据缺口。唯一候选是本任务审查材料，不是新bit或生产实现。

## 分支与输入

源映射和SHA见source-map.json。b15 .al选changed-src的camera_a1_uart_top/a1_frame_top/a1_deflate_core，单A RAW捕获→DDR→feeder→A+→CMP→UART；与三算法没有串接。三算法在独立upstream CLOSEDLOOP_EN分支，Bayer10 sample lanes→demosaic RGB8→Gray8，然后Gray直接输出、Gaussian(Y8)、HE(Y8)并行，各自obuf与诊断sink。另一RAW/R10F PCIe分支不等于压缩已接通。BPR1/Rice是历史文档和另一Bayer工作树参考，b15编译不选；不重开旧codec。bounded Gaussian frame是原型，不能作为流式持续服务证明。

T02/T06已验manifest及报告分别重新核验，同输入资格见dependency-qualification.json。T02错误packed入口、晚CSI裁决与raw_id语义，T06发布顺序/写可见/guard无epoch/取消状态均继续保留。编码CRC/Adler和逆变换即便一致，也不证明传感器原像素或完整有效帧。没有重跑存储穷举，没有把默认调度成功例当作模块合同证明。

## 五步覆盖

1. C01—C04、C16与source-map分列当前A+/LZ77/DEFLATE、RAW变换旁路、历史BPR1/Rice及三算法；实际编译实例优先于10/15指南。prep0仍zlib，stored回退的是xform字节；不是整个帧无压缩RAW模式。
2. C05—C15覆盖Gray位宽和两级stall、Gaussian普通replicate与一次舍入、rowwin严格sideband、HE四bank/两级转发/首帧identity/前帧LUT/坏帧/原子发布/clear及空窗。Gray最大65408、Gaussian含舍入最大4088；HE24bit bank、26bit合并、32bit乘255在最大几何足够。HE全同灰常量帧den0采用identity。cfg只接收一次，动态模式并未实现，不能造一个切换测试声称已接入编码。
3. C17—C30覆盖2行块/奇数尾、plane anchor与10bit modulo预测、匹配长度3..258/距离1..2048、block tag和hash bypass、投机候选abort、fixed反码/extra bits/LSB打包/EOB、stored LEN/NLEN与尾零、32bit keep/精确长度、CRC/Adler覆盖、abort与描述符/恢复。发现详见下一节和findings.json。原始/变换/码流CRC分别在不同接受边界更新，Adler覆盖xform，不覆盖头或原始RAW。不能重算CRC给已错帧赋予good资格。
4. 自写witness/check_transform_contract.py复查15个软件向量/几何模式、两类非规范码流变异、abort布尔裁决、bit offset归纳与队列反模型、标量位宽/四lane计数。zlib标准库与另源strict inflater是不同解码判据；冻结a1_ref软件tokenizer与RTL hash/插入策略不同，未声称其字节等同真实RTL。没有RTL仿真或四帧矩阵。旧吞吐/资源按下节限定。
5. 标准review/checkpoints/findings/source-map/witness/commands/lessons、控制副本、依赖资格与局部核查齐备后停止修改，机械冻结唯一manifest-r0.json。正式三维结论由下一位综合测试者给出。

## 主要发现与资格

F02：最后字已valid并ready时，同时abort/重复SOF仍commit，源码明确让完成优先，与注释合同冲突。见证是源码锚定布尔真值，不是cycle-accurate RTL可达性测试；b15默认调度和板上是否触发未证。后续需要同时定义store发布、descriptor与取消优先级，不能只改一个输出信号。

F03：真实PC消费者的inverse_xform假定每plane长度可被4整除且总有四plane。W12H2 prep1错像素，W8H3/W16H3 prep1越界；W8H2和prep0为正对照。RTL GEOOK允许W4倍数和奇数H，因此不是这些向量本身违反RTL几何。旧expected_xform还对奇数尾生成额外零行，不能用它来否认RTL一行尾合同。默认1920×1080不触发该软件边界。

F05：码流追加00或stored对齐位置1，重算外层精确长度/CRC后，pc_decode全部布尔检查仍true，而strict inflater拒收。它证明实际消费入口的严格性不足，不证明RTL产生过非法流。损坏Adler的负对照被zlib拒绝，检查不是恒接受。

F04：若每块选择成本相对真实起始offset准确，ceil累计bit成本每块最多增加n+5B，因此1920×1080流长≤2,594,706B、32bit补齐2,594,708B、CMP槽2,594,720B。物理无效word lane不承诺清零，只认keep/精确长度。容量14B余量只在成本前提成立时有效。RTL在末尾操作入opq后可直接S_WAIT，而成本seed取已消费obits；未等待队列排空/未证明与opq_bit_off等价。符号off6+pending2的反模型可使比较偏大2bit；其真实RTL可达性仍未证明。本包将其列evidence_gap，不把宽松界2,594,841B反说成已发生溢出。存储没有硬容量截止的T06缺口因此不能忽略。

F11：16bit block tag在65536块回绕；1080p540块/帧约121.36帧、4.05秒@30fps。reset清valid不等于每次回绕清理；旧hash条目是否必然被刷新缺证据。需针对冷门hash跨回绕的真DUT或形式判据；本包没有可达溢出/错码反例，禁止把风险写成板上事实。

F06：Gaussian stream注释混入Bayer parity clamp，实际PARITY_CLAMP0普通replicate；HE当前14相位×256，仅LUTGEN已3584周期，大于注释约3.3k，尚加merge/clear。属于明确文档/预算过时，不主张改现算法数学。F07标量静态未见问题，RAM转发遇长stall、连帧/坏帧LUT版本及本域复位仍需真实DUT覆盖；不能用同bank纯软件计数代替。

## 吞吐、资源与G层

| 证据候选 | 可引用事实 | 保留限制 |
|---|---|---|
| P4冻结单核187.5MHz | C1合成slot-free Sss4,677,970；同内容strict-serial6,449,405；comp代理5,928,286 | R3随机raw为93.75MB/s sink受限；自然内容、最坏全内容、生产slot-free与双路未证。冷启动Lcold与稳态分开，proxy不是自然图。|
| P1080预算 | 每路77.760MB/s、6.25M周期；两路155.520MB/s；25%只是参考 | 不放宽硬门槛。A+理想最坏输出77.84118MB/s，双路155.68236MB/s，外头另计。RAW20/32 DDR搬运及四次读写沿用T06，不能按压缩比抹掉。|
| b15旧诊断 | 原报告G2 reported pass，SWNS+0.012ns，ERAM+CWC102/300 | 仅诊断薄余量；完整CDC/实际MC/生产双路不因此通过。G3旧下载/150秒观察仅reported observation；G4 blocked H4_UNRESOLVED、enc/exported0；G5生产稳定性not_run。|
| upstream旧T09集成 | 原报告选定内部STA+0.100ns、ERAM200/300及full1080p算法模型服务 | 属另一manifest/DB/时钟与实现版本；不能拼到b15或当前2级Gray/8slot副本。G3原计划不适用该离线包，G4原报告not_run/deferred，G5依原报告不适用；生产板级仍未证。|
| 双核旧231/289预算 | 来源索引可引用 | assumed_from_single_core，共享PAXI及Routed unproven，不是当前资源/时序实测。|

本轮G0是审查工作流接口，G1是离线见证；性能名为P1080。新G2/G3/G4/G5执行not_applicable，事先理由为只读、不改RTL/时钟/IP/约束、不交新bit、不签核硬件。未执行TD/bitgen/CWC/COM/JTAG/Flash/板卡/RK，不代做b17或143924活动线。

## 优化、复核入口与回退

正确性优先：F01输入真值与最终裁决→F02取消原子性→F03/F05实际消费者边界→F04/F11最坏成本及字典回绕证明；可观测性保持raw_id/cmp_id/capture_seq/epoch区别；持续服务/资源由F09保留后续门槛。只给有依据的收益与验证，不报虚构百分比。

F10仅建议未来收口构建白名单/来源文档。raw/xform/stream/header CRC与Adler消费者和故障模型不同；row banks提供重叠/多端口，obuf解耦不同sink，不能直接删。所有“删除候选”都要求消费者、故障模型、接受事件、所有权、恢复等价及综合网表差分；当前没有删除建议可立即执行。

局部执行见commands.json与本目录native stdout/stderr；统一baseline287项和已验T02/T06全部manifest项重新核对。首个根/角色短读已在1.2秒完成但没有显式Job deadline，后续全部读搜使用60秒自有Job；最初大批输出有截断，之后定向补读，未当成完整语义证据。生成器初次因obuf引用尾行88超出实际83而停止；见证初次因将decode_stream返回的(frames,off)当frames而停止。依据实际行数/类型各纠正一次，原失败日志保留为attempt1；不属于DUT实测失败。DeepSeek仅有界算术建议，其错误/过松推断拒绝，详见deepseek-review.md。全部补充源复制前/后/副本SHA一致。

测试者须用不同判据复核全部高风险F01/F02/F03/F04/F09/F11及其余引用，不以运行本见证本身代替独立验收；建议另写时序/几何oracle及offset状态解析。没有生产变更需回滚；发现审查结论错误时保留本轮证据，在新修复轮改本包并重冻。父T10、未验T11及整链路/硬件仍不关闭。
''',encoding='utf-8')
(OUT/'lessons.md').write_text('''# T10 可复用经验

- 编码往返和CRC一致只证明给定字节自洽，不能恢复已错误的上游sample/packed格式或CSI最终裁决。
- 边界oracle必须覆盖RTL声明的W%4与奇数尾行，不能把旧软件隐含的W%8、偶数H当接口合同。
- zlib库解压成功不保证精确单member与零padding；应检验消费结束及格式规范，CRC不替代语义。
- 最坏膨胀证明必须使用真实待入流bit offset。队列已接收与已消费offset不同，容量剩余不反证成本比较正确。
- 16bit标签以块为单位回绕，不是按帧；长稳时必须证明旧字典失效，不只测reset初始化。
- 来源相同名字、旧STA、合成吞吐和生产硬件是不同证据边界；不把文档纠错变成生产修复。

验证入口：witness/check_transform_contract.py --stdout；独立测试者另用时序、反交织、变异/边界判据。所有活动/写入仅本任务目录。
''',encoding='utf-8')

# CSV/schema/ref checks are local delivery checks, not independent acceptance.
assert len(rows)==33 and len({x['checkpoint'] for x in rows})==33
assert all(all(str(v).strip() for v in x.values()) for x in rows)
assert {x['kind'] for x in findings} <= {'confirmed_issue','evidence_gap','no_issue_found','redundancy_candidate'}
for x in findings:
    assert all(str(v).strip() for v in x.values())
dump('local-verification-r0.json',dict(marker='T10_LOCAL_DELIVERY_COMPLETE',checkpoints=len(rows),findings=len(findings),
 baseline_hashes=len(baseline['files']),dependency_frozen_files=sum(x['checked_files'] for x in deps),
 schema_nonempty=True,source_references_valid=True,not_independent_acceptance=True,
 scope='G0/G1 read-only audit; no RTL simulation/TD/hardware'))
dump('commands.json',dict(task_id=TASK,workdir=str(ROOT),tools=dict(python=sys.version,powershell='7.6.5',git='2.54.0.windows.1'),
 commands=[dict(command='PowerShell Get-Content/Get-FileHash/Copy-Item/rg on stated inputs',
  deadline_seconds=60,termination='self-owned Start-Job / Wait-Job -Timeout 60 / Stop-Job',exit_code=0,
  qualification='Initial root/role short read completed in 1.2s without explicit Job deadline; subsequent reads used Job deadline.'),
 dict(command='git status --short --untracked-files=no; git --version; python --version',exit_code=0,
  evidence='worktree-before.json and native session output'),
 dict(command=f'python -B -X utf8 "{OUT / "build_review.py"}"',deadline_seconds=300,
  exit_code='see build-native-run.json; first failure retained as build-attempt1-native-run.json',marker='T10_LOCAL_DELIVERY_COMPLETE',artifacts=['dependency-qualification.json','local-verification-r0.json']),
 dict(command=f'python -B -X utf8 "{OUT / "witness/check_transform_contract.py"}"',deadline_seconds=300,
  exit_code='see witness-native-run.json; first failure retained as witness-attempt1-native-run.json',marker='TRANSFORM_WITNESS_COMPLETE',artifacts=['witness/result-r0.json'])],
 no_production_changes=True,no_deletion=True,micro_RTL_simulations=0))
print('T10_LOCAL_DELIVERY_COMPLETE checkpoints=33 findings=11 baseline=287')
