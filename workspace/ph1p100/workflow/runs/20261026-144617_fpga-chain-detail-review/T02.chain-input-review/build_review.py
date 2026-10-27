"""Assemble T02 read-only review artifacts, all writes confined to this package."""
import csv
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path('D:/fpga/ph1p100')
RUN = ROOT/'workflow/runs/20261026-144617_fpga-chain-detail-review'
OUT = RUN/'T02.chain-input-review'
BASE = RUN/'baseline/source-manifest.json'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return path.read_text(encoding='utf-8-sig', errors='replace')


def save(name, content):
    path = (OUT/name).resolve()
    assert path.is_relative_to(OUT.resolve())
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(content,encoding='utf-8')


def js(name, value):
    save(name,json.dumps(value,ensure_ascii=False,indent=2)+'\n')


baseline = json.loads(read(BASE))
assert sha(BASE) == 'c08adc09b364828fee5d94953a89898a3220af8c8f99cdec52404fec06f74c96'
baseline_checks = []
for entry in baseline['files']:
    snapshot = Path(entry['snapshot_path'])
    actual = sha(snapshot)
    assert actual == entry['sha256'], str(snapshot)
    baseline_checks.append({'path':str(snapshot),'sha256':actual,'result':'match'})
supplements = json.loads(read(OUT/'supplemental-sources.json'))
selected = [16,36,82,86,88,89,90,98,123,141,144,146,147,149,150,151,152,155,157,168,172,173,182,183,187,271,274]
sources = {}
for entry in baseline['files']:
    number = int(Path(entry['snapshot_path']).stem)
    if number in selected:
        sources[f'S{number:04d}'] = dict(entry, role='immutable_baseline',
            review_read_scope='targeted source ranges; not whole-repository validation')
aliases = {'rx_phy_ph1p.v':'P_PHY','csi_rx_hdr_ecc.v':'P_ECC','csi_rx_byte_align.v':'P_BYTE',
           'csi_rx_word_align.v':'P_WORD','csi_rx_word_gear_box.v':'P_GEAR',
           'csi_rx_packet_integrity.v':'P_CSI','csi_rx_10bit_unpack_checked.v':'P_UNPACK',
           'mipi_csi2_rx_ph1p.v':'P_MIPI','ui_i2c.v':'P_I2C','ui_cfg_imx415.v':'P_CFG',
           'ui_imx415_reg.v':'P_TABLE','camera_startup.v':'P_START','auto_delay_ctl.v':'P_AUTO'}
for entry in supplements:
    assert sha(Path(entry['snapshot_path'])) == entry['sha256']
    sources[aliases[Path(entry['snapshot_path']).name]] = dict(entry,role='compile-selected_supplement')


def ev(source_id,start,end,reason):
    entry = sources[source_id]
    assert 1 <= start <= end <= len(read(Path(entry['snapshot_path'])).splitlines())
    return {'source_id':source_id,'snapshot_path':entry['snapshot_path'],
            'sha256':entry['sha256'],'line_start':start,'line_end':end,'reason':reason}


findings = []
def finding(fid,severity,kind,claim,evidence,reproduction,impact,recommendation,benefit,tradeoff,validation,disposition):
    findings.append(dict(finding_id=fid,severity=severity,kind=kind,claim=claim,
        evidence_refs=evidence,reproduction=reproduction,impact=impact,recommendation=recommendation,
        expected_benefit=benefit,tradeoff=tradeoff,validation=validation,disposition=disposition))


finding('T02-F01','high','confirmed_issue',
 '冻结的b15源工程连接把4×10bit样本向量直接传给要求五字节packed RAW10的A+入口；缺少边界重打包。该结论不声明旧bit实际像素已测坏。',
 [ev('P_UNPACK',23,31,'输出拼接为P3/P2/P1/P0四个10bit样本'),ev('S0151',376,382,'相机tap直接传递解包输出'),
  ev('S0147',148,161,'crop只复制40bit而不变换格式'),ev('S0150',344,360,'43bit CDC sideband携带原样40bit'),
  ev('S0150',434,452,'捕获skid原样接收'),ev('S0144',156,163,'raw store按40bit原样拼接'),
  ev('S0150',687,694,'feeder按40bit原样切片'),ev('S0146',393,399,'A+按字节和末字节LSB解读')],
 'python -B -X utf8 witness/check_input_contract.py --out <tester允许目录>；[0,1,2,3]的wire字=e400000000，解包字=00c0200400，消费者读成[0,16,128,768]。',
 '图像样本值和Bayer平面输入语义错误；压缩/解压及CRC相互一致仍可掩盖“起始像素已经解释错”的问题。',
 '后续在唯一边界明确选择packed bytes或sample lanes；若保留A+合同，参考RAW writer的显式重打包，并补跨真实checked解包到解码后像素的端到端检查。此包不改RTL。',
 '恢复正确样本语义；不以压缩比或代码行数估算收益。',
 '增加或移动组合打包边界；须复核时序、字节CRC、已有golden来源和模式元数据。',
 '独立测试者用不同判据解析concat/或直接运行真实unpack并对比源样本；混合LSB/高位、0/1023、lane顺序、所有keep尾部；后续绑定新候选做G2及板上原图比对。',
 'correctness_first; implementation_deferred')
finding('T02-F02','high','confirmed_issue',
 'b15顶层将相机cap_frame_end/good/abort悬空，A+捕获仅依据ROI计数out_last，无法接收CSI随后产生的坏帧撤销。',
 [ev('S0152',108,127,'三个裁决输出全部悬空'),ev('P_MIPI',121,150,'完整性层产生裁决且像素先流出'),
  ev('P_CSI',92,105,'CRC/超时发现晚于已流出的payload'),ev('S0147',142,159,'ROI完成置done并禁用后续frame_fall abort'),
  ev('S0150',317,318,'FIFO abort仅来自crop/overflow')],
 '见witness/run-r0/result.json late_verdict_trace；最后ROI组在源行第722组，后面还有243组，再有该行CRC和后续FE；该行CRC错误不能通过悬空端口撤销A+捕获。',
 'ROI最后行的坏CRC、ROI完成后错误或缺FE不构成A+发布门槛；不能以crop_groups/raw_pub作为完整源好帧证明。DDR本身是否能完成发布是另一包问题。',
 '后续使捕获事务持有到明确采用的完整性裁决，跨域携带同帧good/abort/epoch；明确“整源帧合格”或“逐ROI行合格”的策略并据此定义最后发布点。',
 '防止坏帧被当作有效输入；保留不可反压流入的恢复能力。',
 '等待裁决会延长slot占用；只把abort线OR到旧ROI last之后不足以撤销已发布帧。',
 '注入最后ROI行CRC错、坏FE、缺FE、重复FS和timeout，验证零发布及后续正常帧恢复；测试必须经过真实checked CSI到捕获门槛。',
 'correctness_first; do_not_close_hardware_task')
finding('T02-F03','medium','confirmed_issue',
 'crop声明最后ROI行也需完整CG组，但done在最后ROI像素即置1，使该行后缀的短/长行无法再触发几何检查；这是局部合同与实现不一致。',
 [ev('S0147',13,18,'注释声明至最后ROI行都要求精确组数'),ev('S0147',132,145,'new_line/frame_fall检查均受!done限制'),
  ev('S0147',148,161,'组计数/last在行结束前完成')],
 '本候选GX=243、OG=480、CG=966：最后ROI组=722，尚余243组。将最后ROI行在第723组之后提前结束，ROI last已经发出，done使后续检查关闭。witness记录该算术和条件。',
 '总像素ROI数量正确不证明所依赖源行几何完整；最后一行缩短到ROI右边界仍被视为ROI完成。',
 '统一F02的提交裁决与最后行检查；若有意忽略ROI外后缀，修改未来合同并证明CRC覆盖/相位策略，不能只删除检查。',
 '消除最后ROI行的边界盲区，减少误导性计数结论。',
 '需要存留pending-last与裁决状态，保持abort优先和队列顺序。',
 '最小几何正例/末行缺后缀/多后缀/坏CRC/帧早停负例，独立核对last和最终发布；不是重新跑完整1080p长仿真。',
 'share_validation_with_F02')
finding('T02-F04','medium','evidence_gap',
 'A+ raw_id仅在成功准入的SOF增加，是admission序号；未见每个源FS递增并穿过CDC/导出的capture_seq或会话epoch绑定。',
 [ev('S0150',197,223,'源frame计数只用于诊断'),ev('S0150',310,360,'FIFO仅abort/last/sof/40bit'),
  ev('S0150',415,460,'raw_id仅成功begin分支增加'),ev('S0088',20,24,'隔离同步mailbox的全事件序号是另一合同')],
 '结构对比：连续三个源SOF，中间一次begin被拒；raw_id只见两次递增，不能从下游ID恢复该源丢帧位置。',
 '采集丢帧、准入丢帧和重试无法只凭输出序号区分；双路对齐不能用该序号推定相同曝光。',
 '后续区分capture_seq/admission_id/export_id与epoch，在源SOF计数并按同帧事务传播，保留拒绝原因。',
 '提升丢帧与配对可观测性；对吞吐无直接承诺。',
 '增加元数据位宽与回绕/复位合同，需跨消费者版本验证。',
 '丢SOF/中间帧拒绝/复位/序号回绕后，用独立事件日志核对源计数、准入和导出关系。',
 'followup_observability')
finding('T02-F05','high','evidence_gap',
 'b15两路各自自动配置并启动，且只把A接入A+；共用MCLK/XCLR不能证明双路曝光同步。SOF配对/重锁仅存在于独立离线轨道证据。',
 [ev('S0151',112,116,'共用启动时钟/复位'),ev('S0151',215,239,'独立配置器'),ev('P_TABLE',49,52,'表内XMASTER=0'),
  ev('P_CFG',105,128,'各自退出standby并启动'),ev('S0152',325,337,'A-only压缩接入'),
  ev('S0089',13,40,'按控制域接收时刻窗口配对和重锁'),ev('S0187',3,7,'离线隔离候选的交付资格')],
 '搜索冻结b15工程文件列表与top：无sync_offline实例；另读sync_start_ctrl、mailbox/pairer及隔离gate/config源；这些不在b15编译清单。',
 '不能将“双路收到帧”“SOF skew落窗”或离线PASS写成板级同曝光配对已完成。',
 '保留离线同步候选身份；后续迁入真实双路链后绑定角色寄存器、物理同步连接与曝光观测，明确SOF时间戳的CDC延迟误差。',
 '把序号配对、起流控制、曝光同步三个门槛分开，避免错误关闭父T08。',
 '新增真实同步线/传感器副作用和板窗验证；不由本包获取设备授权。',
 '先核对真实I2C角色写值/等待与失路清理，再测物理曝光与SOF、丢路重锁/全局reset及稳定性。',
 'awaiting_future_hardware_authorization; audit_not_blocked')
finding('T02-F06','medium','evidence_gap',
 'FIFO本身有各域同步释放；crop与相机侧诊断却直接使用在clk_a1域释放的a1_rst_n，且未与PHY O_rst_out共同定义恢复契约。现有SDC不等于该释放已签核。',
 [ev('S0152',258,269,'A1域复位生成'),ev('S0150',169,180,'crop直接rst_n'),ev('S0147',109,117,'crop为同步采样reset'),
  ev('S0036',8,10,'FIFO各域复位释放'),ev('S0157',35,57,'异步分组与Gray skew约束')],
 '结构检查；未运行reset相位/停byteclk再恢复的真实DUT或恢复recovery/removal分析。',
 '时钟停顿时同步reset可能未被crop采到，释放时元稳/旧状态清理缺乏本候选证据；不据此声称已板测失败。',
 '后续定义相机域本地assert/release和PHY重锁epoch，检查计数、crop、FIFO、abort事务的一致复位，不只替换一处reset线。',
 '减少复位后旧帧混入/恢复不确定性。',
 '改变恢复时序，可能影响SOF丢弃与warmup；需真实DUT和CDC/STA。',
 '停clk_cam期间全局reset、PHY-only reset、DDR掉ready、任意相位释放，检查首帧完整性与无旧事务发布。',
 'engineering_gate_gap')
finding('T02-F07','medium','evidence_gap',
 '本候选以手动tap46和软PHY对齐运行；包层只主张逐包同步、严格ECC拒错而非纠错。已有+0.012ns诊断余量和旧收包记录不能替代当前物理链路/完整CDC签核。',
 [ev('S0151',124,129,'手动tap配置'),ev('P_PHY',61,104,'恢复byteclk和tap选择'),ev('P_WORD',55,57,'四lane有效共同成立'),
  ev('P_CSI',1,7,'逐包同步支持范围'),ev('S0168',44,52,'旧诊断候选薄余量')],
 '冻结源码和旧结果资格审查；未做电气、眼图、连续HS或新STA。',
 '换板/线速/温压后不能以tap值和旧STA推断稳定接收；支持范围必须约束数据源。',
 '保留逐包同步profile，后续以实际lane速率/数据源绑定采样窗口和错误率、完整CDC/时序。',
 '明确链路适用范围，避免将协议模型结果外推物理层。',
 '重新扫tap与稳定性需要明确硬件授权/时间窗。',
 '真实设备绑定bit/source/约束，测错误计数和恢复；连续HS若需求出现需单独协议验证。',
 'future_G2_G5')
finding('T02-F08','low','redundancy_candidate',
 'b15工程清单仍列cam_preview_capture及旧FIFO源，实际camera core已改为HDMI测试图；手动tap模式下自动扫描不参与tap选择。仅存在/列入清单不能证明资源浪费。',
 [ev('S0155',15,210,'编译文件列表'),ev('S0151',350,374,'预览被测试图替换、cap_data有效常量0'),
  ev('P_PHY',102,104,'手动选择tap'),ev('P_PHY',158,173,'自动扫描仅保留状态输出')],
 '静态列单/实例差异；本包未生成网表/资源diff。',
 '旧注释和未实例文件易误导当前链路图；是否有可裁剪逻辑需先查实际消费者/网表。',
 '后续先整理源码入口和注释，自动扫描只有证明调试消费者不再需要且测得净表资源后才考虑删。',
 '更清楚的工程入口；资源/功耗收益未知，不报节省百分比。',
 '删除调试能力可能损害换板定位；综合已裁掉的模块不会带来资源收益。',
 '对比真实编译实例/综合网表/资源和调试消费者，保留回退；不能仅按文本重复删模块。',
 'low_priority_no_deletion_authorized')
finding('T02-F09','medium','evidence_gap',
 'ROI偶数起点保持相对CFA相位，但不证明绝对RGGB；b15与RAW生产参考采用不同ROI/skip合同。传感器几何、CFA和方向必须随候选元数据绑定。',
 [ev('S0147',30,36,'b15几何3864×2192、972/556、1920×1080'),ev('S0147',81,90,'几何合法性约束'),
  ev('P_TABLE',70,81,'方向/窗口表字段'),ev('S0146',4,17,'消费者声明RGGB phase0'),
  ev('S0123',105,116,'RAW生产参考不同ROI/skip')],
 '算术：972 mod4=0，556 mod2=0；相对于同一源阵列相位未变；未使用实际标靶/传感器权威CFA证据确认绝对颜色。',
 '长度正确或packed互逆不能证明CFA正确；不同源ROI参数不能混用为同一图像候选。',
 '后续为每分支固定源有效阵列、active origin、ROI/skip、CFA/方向和精确字节端序，原图端到端标靶核对。',
 '避免颜色/空间错位与候选混拼。',
 '需要传感器/解码消费者共同解释metadata；无性能收益主张。',
 '以实拍颜色/棋盘或权威模式数据比对CFA，覆盖偶数ROI和方向切换，绑定输出头。',
 'metadata_and_sensor_evidence_gap')
finding('T02-F10','info','no_issue_found',
 '在静态检查的合同范围内，checked层提供VC0/RAW10/ECC/CRC/keep与有界超时；CDC FIFO原子携带数据和sideband，满时有sticky abort，不能删除这些保护以追求简化。',
 [ev('P_CSI',23,42,'包筛选与CRC/keep生成'),ev('P_CSI',57,105,'FS/FE与错误/超时裁决'),
  ev('P_UNPACK',12,31,'低字节keep和五字节组装'),ev('S0150',303,360,'独立abort token、sticky loss及43bit FIFO'),
  ev('S0036',16,34,'接受事件、预取和stall保持')],
 '源码合同核对；本包数值见证验证解包格式，未重跑完整CSI/FIFO RTL矩阵。',
 '单点静态未发现问题不等于DUT证明；F01/F02的边界问题仍然成立。',
 '保留错误检测/原子sideband/粘滞abort和计数；只在有消费者等价证明后考虑简化。',
 '维护可恢复的不可反压入口。',
 '保留必要状态；资源开销未在本包重测。',
 '后续真实DUT覆盖尾keep、stall同拍take/refill、丢SOF/LAST、满FIFO abort重试及reset。',
 'static_no_issue_only')

rows=[]
def cp(tag,stage,producer,consumer,sid,a,b,units,clock,event,ownership,invariant,recovery,result,fid,optimization,next_check):
    src=sources[sid]
    rows.append(dict(checkpoint=tag,stage=stage,parent_task='T02',producer=producer,consumer=consumer,
        source_path=src['snapshot_path'],source_sha256=src['sha256'],line_start=a,line_end=b,
        input_output_units=units,clock_reset=clock,acceptance_event=event,ownership=ownership,
        invariant=invariant,failure_recovery=recovery,result=result,evidence=f'{sid}:{a}-{b}; {fid}',
        optimization=optimization,verification_next=next_check))

cp('C01','step1.compile','a1_board.al','p2_a1_board_top','S0155',15,140,'source path/module','candidate explicit source; no build','UsedInSyn=true + top selection','changed-src owns compiled RTL; td duplicate not assumed','A-only A+ path is distinct from upstream RAW dual','source drift => freeze mismatch, never chase active runs','no_issue_found','T02-F08','preserve compile map','verify .al + candidate hashes')
cp('C02','step1.branches','u_csi_a/u_csi_b','A tap / unused B / HDMI test pattern','S0151',350,382,'4x10bit / 24bit RGB test pattern','A/B byteclk; pclk','A pixel_valid; display_de independently','only A tap enters A+; B not compressed','file presence does not establish path integration','retain branch roles; no production merge','no_issue_found','T02-F05','remove misleading documentation only after binding','trace both instance connections')
cp('C03','step2.startup','PLL lock','XCLR/MCLK/config reset','P_START',10,29,'50MHz cycles / output clock','async lock loss; falling MCLK gate release','count threshold and gate_ready','one startup owner shared by A/B','XCLR then MCLK then config; delays source-derived only','lock loss clears counters/gates; sensor effects untested','no_issue_found','T02-F05','keep glitch-free gate','hardware reset/clock qualification deferred')
cp('C04','step2.i2c-owner','ui_cfg_imx415','ui_i2c / sensor SDA','P_CFG',77,124,'4 write bytes or 3+1 random-read bytes','sys50; cfg_rst_n','request held until busy_sync high; done when low','one core per bus; data held through transaction','cfg_done after table/readback + start master','NACK/timeout enters FAILED; reset required','no_issue_found','T02-F10','no blind retry; define recovery first','pin-level ACK/readback/last-byte NACK')
cp('C05','step2.i2c-failure','ui_i2c W_ACK','ui_cfg error_sync','P_I2C',152,173,'busy/error levels','sys50 with clock enables','ACK sampled scl_fall_ce; busy on scl_rise_ce','single master; SDA open drain','errors cannot be treated as config success','FAILED latches until cfg reset; no automatic retries','no_issue_found','T02-F10','bounded re-init only under future explicit policy','timeout/NACK and restart proof')
cp('C06','step2.phy','4 MIPI lanes','word/byte alignment','P_PHY',61,104,'serial bits -> byte clock','per-camera recovered clk; O_rst_out','clock detector enables RX reset release','each lane local sample; manual tap46','manual tap is candidate-specific','clock loss/auto scan behavior needs device evidence','evidence_gap','T02-F07','preserve profile; measure before pruning auto scan','tap/line-rate/error-rate qualification')
cp('C07','step2.lane-align','aligned lane valids','gearbox','P_WORD',55,57,'4x8bits ->32bit','byteclk O_rst_out','AND of all delayed lane-valids','per-packet alignment handshake','all lanes valid before word-valid; not arbitrary continuous HS','packet_done resets packet alignment; PHY outside G1','no_issue_found','T02-F07','do not remove packet_done handshake','deskew limit and packet-tail independent cases')
cp('C08','step2.vc-dt-ecc','CSI header','selected RAW10 packets','P_CSI',23,30,'VC bits / DT6 / WC16 bytes','byteclk O_rst_out','strict header ECC equality and selected VC/DT','VC0 selected; wrong-VC not image payload','RAW10 WC nonzero multiple5; optional exact WC/lines disabled','bad header marks frame_bad and abort','no_issue_found','T02-F10','strict rejection is supported; no ECC-correction claim','ECC mutation/wrong VC DT/zero WC')
cp('C09','step2.crc-keep-timeout','CSI BODY','speculative payload + late abort','P_CSI',35,42,'4 low bytes/keep per beat; CRC16 0x8408','byteclk O_rst_out','I_data_valid; consumed-byte comparison','CRC covers payload bytes; CRC bytes excluded from keep','pixels remain speculative before FE','idle32/frame16777216 counters abort; no full-frame buffer','no_issue_found','T02-F10','retain checksum and bounded timeout','CRC/tail partial keep/idle/frame timeout')
cp('C10','step2.fs-fe-lines','CSI short packets','frame_open/frame_good','P_CSI',67,89,'FS/FE frame-id / line count','byteclk O_rst_out','selected FS opens; selected FE validates','one selected frame; duplicate FS aborts old','EXPECTED_LINES=0 and CHECK_FRAME_ID=0 are permissive defaults','frame_bad blocks future selected payload until next FS','evidence_gap','T02-F02','bind exact geometry and publishing policy','missing/duplicate FS/FE and frame-id mismatch')
cp('C11','step2.raw10-tail','payload bytes+keep','four 10bit sample lanes','P_UNPACK',12,31,'5 bytes -> 4 samples; count0..4','byteclk O_rst_out','I_din_valid && incoming!=0; output pipeline group_valid','line pulse clears pending bytes','contiguous keep; no cross-line byte carry','partial residual discarded by next line; invalid keep emits no bytes','no_issue_found','T02-F10','retain explicit group representation','all legal keep sequences and partial tail')
cp('C12','step2.format-boundary','unpack->crop->raw FIFO/store','a1_frame_top packed parser','S0146',393,399,'4x10bit vector vs packed five bytes','clk_cam -> clk_a1 through FIFO','A+ in_valid && in_ready','40bit unchanged until parser; missing repack','source pixel values must survive representation change','CRC consistency does not repair initial interpretation','confirmed_issue','T02-F01','one explicit repack boundary','independent source-sample oracle; witness mixed vectors')
cp('C13','step2.roi-phase','3864x2192 source array','1920x1080 ROI at972/556','S0147',30,90,'966 source groups/row;480 ROI groups;518400/frame','clk_cam; rst_n from A1','pix_valid && in_frame && active && !done','even/group-aligned crop retains relative CFA','ROI fits source; positive production defaults fixed','illegal enumerated geometry fails elaboration; absolute CFA unproved','evidence_gap','T02-F09','record source origin/phase separately','sensor CFA/orientation and branch metadata proof')
cp('C14','step2.line-tail','source line group counter','crop out_last/done','S0147',132,161,'CG966; last ROI group722; suffix243','clk_cam synchronous reset','new_line check before done; last on NGRP-1','ROI count completion ends local checking','last ROI source row must match stated complete-row contract','done suppresses later geometry and frame_fall abort','confirmed_issue','T02-F03','hold pending-last until adopted validation point','last-row short/long suffix/early FE negative cases')
cp('C15','step2.bad-frame-revoke','CSI good/abort/end','A+ capture transaction','S0152',108,127,'same-frame verdict pulse vs ROI last','camera -> clk_a1 required but absent','cap_frame_end/good/abort have empty top connections','no consumer owns CSI verdict for A+','bad source frame must never be presented as qualified','crop/overflow abort exists; CSI verdict absent','confirmed_issue','T02-F02','connect verdict with ownership and delayed publication','last ROI row CRC/missing FE/recovery')
cp('C16','step3.nonbackpressure','camera crop stream','43bit CDC FIFO','S0150',303,340,'40 data + sof/last/abort; FIFO depth512','clk_cam ->clk_a1; common rst_n','push=fifo_wvalid && fifo_wready; camera cannot stall','abort token persists until accepted','data loss must poison entire owning capture transaction','sticky abort_hold; overflow count; no retry of lost pixel','no_issue_found','T02-F10','keep sticky abort and drop counters','full FIFO loses SOF/middle/LAST; token must arrive')
cp('C17','step3.ready-valid','CDC FIFO output','raw capture skid','S0150',391,469,'one 40bit group + sof/last/abort','clk_a1; rst_n','fifo_valid&&fifo_ready; skid_take=skid_valid&&raw_wr_ready','single capture owner; deny SOF sets skip_frame','abort priority; stalled skid not overwritten under stated source stream','skip_frame drains until next SOF; store details deferred T06','no_issue_found','T02-F10','retain take/refill and orphan drain; no deletion proposal','real-DUT stall/SOF denial/abort coincidence; not proven for arbitrary malformed beats')
cp('C18','step3.cdc','43bit FIFO write domain','43bit FIFO read domain','S0036',8,34,'atomic payload+3 sidebands / Gray pointer','async assert + independent 2FF release','push and registered fetch; hold r_data under stall','writer owns until pointer transfer; prefetch register owns fetched beat','sideband cannot tear from data; held data stable while stalled','reset clears pointers/r_valid; skew constraints reviewed separately','no_issue_found','T02-F10','keep Gray registration and pointer skew checks','formal/RTL random-phase reset/stall deferred')
cp('C19','step3.reset','A1 reset release / PHY reset','crop/FIFO/camera status','S0152',258,269,'reset level / clock readiness','A1 local sync; crop cam domain lacks local release','a1_rst_sync[2]; no O_rst_out connection at crop','mixed-domain reset epoch not documented','stopped byteclk must not retain old capture epoch','FIFO self-synchronizes; crop reset sampled only on cam edge','evidence_gap','T02-F06','define per-domain release and epoch','clock-stopped reset/PHY-only reset/DDR readiness loss')
cp('C20','step3.capture-seq','each source FS','raw_id and output descriptor','S0150',434,460,'source capture count vs admitted frame id','source counter cam; raw_id A1','raw_id increments only successful SOF begin','ID belongs to admitted transaction, not every physical frame','source drops must be observable without guessing','deny reasons counted; source FS counter only diagnostic','evidence_gap','T02-F04','carry capture_seq+epoch distinct from admission id','three source frames with middle deny; reset/retry mapping')
cp('C21','step3.exposure','two independent sensor config FSMs','two sensor streams','S0151',215,239,'per-camera I2C control / common MCLK','sys50 shared clock; independent completion','each START_MASTER done independently','both configured master per current table','common clock/reset does not prove simultaneous exposure','per-camera FAILED; no active cross-camera stop/relock','evidence_gap','T02-F05','preserve explicit master/slave plan in separate candidate','real role writes and physical exposure timing')
cp('C22','step3.sync-start-stop','sync_start_ctrl','exclusive I2C adapter','S0090',19,105,'14 start writes / 6 cleanup writes / 24ms waits','ctrl reset local; source not in b15 build','req_valid&&req_ready then rsp_valid','one outstanding accepted request; ACK timeout poisons transport','late response cannot be reused by automatic retry','cleanup ordering; timeout requires global transport reset','no_issue_found','T02-F05','reuse independently verified isolated design only with candidate binding','independent pin sequence/timeout/reset and mode-off equivalence')
cp('C23','step3.sof-mailbox','source SOF','ctrl event/sequence/lost','S0088',9,35,'32bit all-event seq + rejected counter','source/dst sync_reset in wrapper','SOF accepted only mailbox free; sequence counts all events','stable payload until ack; rejection counted','no overwrite of occupied mailbox; lost count comes with later accepted payload','shared reset clears toggles; stopped source may delay lost observation','no_issue_found','T02-F04','keep rejection observability; do not equate latency to exposure','mailbox overrun, no subsequent SOF, reset at occupied slot')
cp('C24','step3.pair-relock','A/B mailbox arrivals','SOF pair descriptor','S0089',13,41,'ctrl timestamps and signed modular skew','ctrl domain reset; enable gates slots','have_a&&have_b plus difference within PAIR_WINDOW','pair retains per-camera seq; pairs by arrival window, not seq equality','skew is arrival-time metric with CDC uncertainty','missing/overwritten slots clear lock; next qualifying pair relocks','evidence_gap','T02-F05','document arrival skew limits and expected seq offsets','missing camera/window edges/timestamp wrap/relock; physical proof separate')
cp('C25','step3.isolated-gate','ctrl permit','per-camera admission gate','S0182',7,21,'permit / SOF / good / abort','async revoke; 2FF release in cam domain','admit only new SOF after synchronized permit','revoked open frame emits abort; source SOF not fabricated','offline gate evidence does not establish production connection','permit loss aborts and waits future real SOF','no_issue_found','T02-F05','preserve whole-frame admission contract','true overlay vs baseline identity; mode disable equivalence')
cp('C26','step1.reference-raw','checked sample lanes','cam_r10f_writer packed RAW','S0098',216,230,'sample lanes -> five-byte packed group; ROI+skip','camera byteclk then writer-owned CDC','cam_pix_valid within configured window','separate upstream RAW candidate; explicit repack exists','RAW reference format adapter is not present automatically in A+','eof_good/abort used by separate writer','no_issue_found','T02-F01','use as reference for a future explicit boundary','do not merge candidates or use reference PASS for b15')
cp('C27','step3.reference-bad-frame','cam_frame_good/abort + EOF','RAW writer EOF token','S0098',259,300,'good/abort state + EOF bit','cam_clk; cam_rst_n','EOF with accumulated good/abort and row count','selected source frame owns accumulated verdict','bad flag in EOF token; no good => bad','FIFO-full EOF loss recovery needs T06 evidence; no signoff here','evidence_gap','T02-F02','keep EOF bad bit; review overflow/system ownership in T06','EOF token loss/full/reset proof deferred T06')
cp('C28','step4.evidence-qualification','b15 result / sync delivery indexes','audit claims','S0168',44,73,'old STA/build/board observations','bound old candidate only','reported measurements are historical; no new execution','b15 and isolated overlay remain distinct','audit PASS cannot mean DUT/physical sync PASS','H4_UNRESOLVED kept; L_max/root-cause overclaims rejected','evidence_gap','T02-F07','preserve measured facts and qualify inference','old report references/hash; no L_max=1 or address-root-cause signoff')

fields=['checkpoint','stage','parent_task','producer','consumer','source_path','source_sha256','line_start','line_end','input_output_units','clock_reset','acceptance_event','ownership','invariant','failure_recovery','result','evidence','optimization','verification_next']
with (OUT/'checkpoints.csv').open('w',newline='',encoding='utf-8-sig') as handle:
    writer=csv.DictWriter(handle,fieldnames=fields)
    writer.writeheader();writer.writerows(rows)
js('findings.json',{'task_id':'T02.chain-input-review','round':0,'findings':findings})
candidate=json.loads(read(RUN/'baseline/snapshot/0141.json'))
bindings=[]
for sid in ['S0147','S0150','S0151','S0152']:
    entry=sources[sid]; name=Path(entry['source_path']).name
    expected=candidate['changed_src_sha256'][name]
    assert entry['sha256']==expected
    bindings.append({'source_id':sid,'candidate_expected_sha256':expected,'result':'match'})
assert sources['S0155']['sha256']==candidate['build']['a1_board.al']
assert sources['S0157']['sha256']==candidate['build']['p2_board.sdc']
al=read(Path(sources['S0155']['snapshot_path']))
compile_paths=re.findall(r'<File Path="([^"]+)"',al)
js('source-map.json',{'task_id':'T02.chain-input-review','baseline_manifest':str(BASE),'baseline_manifest_sha256':sha(BASE),
    'sources':sources,'compiled_top':'p2_a1_board_top','compile_entry_source_id':'S0155','compile_paths':compile_paths,
    'candidate_changed_source_binding':bindings,'candidate_identity_boundary':'.al/changed RTL hashes match candidate manifest; camera dependency hashes omitted from that old manifest, so supplements do not certify historical bit contents',
    'branches':[
        {'name':'b15 A+ UART diagnostic','role':'compile-selected source review; old board H4_UNRESOLVED','top':'p2_a1_board_top','camera':'A only to A+; B receiver exists without A+ consumer','format_in':'four 10bit sample lanes','crop':[3864,2192,972,556,1920,1080],'format_expected_downstream':'packed RAW10 five bytes','hardware_proof':'not newly run'},
        {'name':'b15 HDMI','role':'test pattern only; old preview source listed without active preview instance','format':'RGB24 test pattern'},
        {'name':'upstream RAW/R10F','role':'separate production reference; not the b15 candidate','top':'ph1p_pcie_ep_top','camera':'A and B writers','format':'sample lanes explicitly repacked to five bytes','geometry':'W1920 H1080 X960 Y540 plus own SKIP_ROWS; do not substitute b15 source geometry'},
        {'name':'sync-production-sim','role':'isolated overlay; no claim of current production migration','gate':'sync_frame_gate','i2c':'sync_i2c_config','evidence':'S0172/S0173/S0187; baseline S0123 is pre-overlay production input'},
        {'name':'dual-local-closure','role':'separate isolated evidence index only','evidence':'S0274; no hardware exposure or dual A+ integration inference'}]})
js('baseline-verification-r0.json',{'baseline_manifest_sha256':sha(BASE),'files_checked':len(baseline_checks),'mismatches':0,'checks':baseline_checks,
    'supplements_checked':len(supplements),'source_modified_by_review':0,'candidate_binding':bindings})
witness=json.loads(read(OUT/'witness/run-r0/result.json'))
assert witness['marker']=='T02_INPUT_WITNESS_COMPLETE'
save('review.md',f'''# T02 输入链路细节审查（round0）

本包完成原计划T02的只读审查产物，等待独立综合测试。它不对DUT或整链路作通过判定，不关闭父硬件任务。用户原话、恢复授权、计划和工程指南仍以run根的冻结输入为准。

最优先的源码问题是 **4×10bit样本向量与packed RAW10的入口格式不一致（F01）**，其次是 **CSI好/坏帧裁决未接入A+捕获（F02）**。F03记录最后ROI行几何合同的独立盲区。已知b15缺R、enc/exported=0继续保留，本包没有定位真实MC根因，也不把上述问题描述成旧bit已经实测的像素错误。

## 输入和实际接入

唯一统一基线为 `{BASE}`，SHA256 `{sha(BASE)}`。全部{len(baseline_checks)}项snapshot本地重算一致。输入工程HEAD为27c596b01cd961dfa9d0850e4fbf879fe249de90，既有dirty/删除全部保护。本包只在自身目录写入。`source-map.json`给出原路径、snapshot路径、SHA与实际编译入口；`checkpoints.csv`为{len(rows)}行包内检查点，不是新增调度任务。

`a1_board.al`的top为p2_a1_board_top，核心源选中changed-src；与candidate manifest比较的crop/camera top/core/board top及.al/SDC哈希一致。统一baseline未收齐相机依赖，于本目录inputs只读补冻{len(supplements)}项，并核对复制前/后与副本SHA。该操作没有修改baseline。相机依赖未逐项出现在旧candidate manifest，因此补冻内容只证明本次源工程引用，不认证历史bit内每份依赖；不同SHA的upstream配置器没有被冒充成b15配置器。依赖的原始生成时间/旧bit资格缺口保留。

|分支|实际输入、裁决和范围|
|---|---|
|b15 A+ UART|两路CSI接收，但仅A的40bit tap进入crop→43bit CDC→RAW store→feeder→A+；B无压缩消费者。源3864×2192，ROI(972,556)、1920×1080，966源组/行，480 ROI组/行。cap_frame_end/good/abort在板top悬空。|
|b15 HDMI|实际输出测试图；cam_preview_capture仍在文件表不代表被实例化，cap_sof/valid/last/data常量0。显示Hz不能证明采集fps。|
|upstream RAW/R10F|独立ph1p_pcie_ep_top，A/B各有cam_r10f_writer；显式sample-lanes→packed重打包并消费frame_good/abort。其ROI/skip参数与b15分别绑定，不混作同候选。|
|同步/双路离线轨道|sync_start_ctrl/mailbox/pair与隔离sync_frame_gate、exclusive I2C overlay有源码/交付记录；baseline中的生产top是overlay前输入。b15未编译这些实例；独立离线PASS不证明迁入生产或真实曝光同步。|

## 五步覆盖及判据

1. 编译/分支/参数重建：C01—C02、C26和source-map。实际选中路径优先于仓库同名文件或旧注释。
2. I2C/CSI/RAW/ROI：C03—C15。b15配置器单master/每路独占，先写201表项、选择寄存器masked readback，再退出standby、等待24ms、启动；busy完成后才cfg_done。NACK/事务超时失败锁存，未实现自动重试。SDA开漏；SCL输出不主张clock-stretch/多master。启动默认延迟为50MHz阈值，未重新验证传感器电气。包层VC0、RAW10 DT2b、严格ECC比对（无纠错）、CRC16初ffff/反射8408、低字节keep，逐包同步profile，有idle/frame timeout。IMAGE_WC/EXPECTED_LINES/CHECK_FRAME_ID默认0，故好帧不代表精确3864×2192或帧ID严格校验。四lane同拍有效后进入gearbox。解包按五字节组成四样本，残留在新行丢弃；输出格式必须与下一消费者分别核对。
3. 入口/CDC/序号/同步：C16—C25、C27。CSI不可反压，FIFO满不能要求源重发。现有sticky abort token、sideband原子打包、Gray指针/独立复位释放及skid接受条件已逐条检查；不能为简化删除。局部no_issue_found仅表示静态范围未见矛盾，不是随机stall/reset仿真证明。crop复位释放与PHY重锁缺证据；raw_id是成功准入ID，不等于capture_seq。SOF mailbox计数每次输入并记录拒绝，pairer以控制域到达时间差窗配对，窗口缺路/覆盖会解锁再锁，不保证传感器曝光；丢事件计数要等下一次可接受mailbox提交才随payload可见。
4. 发现与优化：全部见findings.json的结构化证据/触发/收益/代价/验证/处置。所有确定性问题均带冻结源码SHA和行号。见证与算术如下；未提出直接删除状态/缓存/CRC的建议。
5. 交付和冻结：本目录review/checkpoints/findings/source-map/witness/commands/lessons及局部核查，再以manifest-r0.json绑定所有输入/产物；冻结后停止修改和活动。

## 可复查见证及局限

实际执行Python3.11标准库 `witness/check_input_contract.py`，解析冻结producer的Verilog concat切片，再独立构造规范RAW10并按消费者位域重算。结果：源[0,1,2,3]对应wire=e400000000，解包word=00c0200400，被A+读为[0,16,128,768]。4096个逐lane/0…1023数值组合中{witness['single_lane_sweep']['mismatches']}个不保持样本；全0/全1023可假通过，故不能只用极值平场。显式重打包负对照恢复原样本。该检查拒绝的是接口值不等价，未执行RTL、DDR或整帧编码。

第二个源锚定时序见证：最后ROI行零起编号1635，最后ROI组722，源行仍有243组后缀。crop立即置done/out_last，new_line和frame_fall检查均要求!done；该行CRC更晚才知，且CSI abort端口在board top未接A+。因此ROI计数完成不是CSI帧合格证明。此见证是算术/状态条件轨迹，未声称cycle-accurate RTL仿真；独立测试者应使用不同判据复核最高风险F01，并核对F02/F03的源码链。

## 按优先级的后续工作

|优先级|发现|收益与代价|必须验证|
|---|---|---|---|
|正确性1|F01格式契约|恢复样本值；在明确边界重打包的组合逻辑/时序代价待测，无压缩比收益估算。|跨真实checked unpack→crop→store/feeder→解码后像素oracle；混合LSB/lane顺序；新候选绑定。|
|正确性2|F02/F03事务裁决|防坏帧发布；pending verdict可能延长slot持有，需与T06容量/所有权审查衔接。|最后ROI行CRC/短长后缀/坏或缺FE/重复FS/恢复；只OR晚abort不足以撤销已发布帧。|
|可观测性|F04/F09|capture/admission/export ID、epoch、ROI/CFA有明确来源；增加元数据与版本兼容成本。|准入拒绝/丢帧/reset/retry/回绕、CFA标靶及方向比对。|
|工程与系统门槛|F05/F06/F07|明确本域复位、PHY适用范围及曝光同步；需未来真实设备/时序/CDC验证。|停clk_cam reset、PHY重锁、I2C清理/晚响应、真实曝光与稳定性。|
|低优先冗余候选|F08|先清理入口说明；无综合网表差分不能估资源收益。|实例/消费者/约束/网表证明后才考虑删自动扫描或文件引用。|

建议不实施优化、不修改生产源，不接入b17/另一1080p30 run。父T02及整链路仍保留后续包与硬件门槛；本包未展开新调度任务。

## 既有证据与G层资格

|对象|G0/G1|G2|G3/G4/G5边界|
|---|---|---|---|
|本审查|本地输入哈希/语义/算术见证已完成，独立综合测试尚待执行。|本轮新执行not_applicable：规划已冻结纯只读，无新RTL/IP/约束/bit。|本轮新执行均not_applicable，理由同dev-plan：不交新候选/不签核硬件。|
|b15旧诊断|原result报告模型/构建通过；仅其原输入范围。|reported pass with caveat：SWNS+0.012ns诊断薄余量，原routed报告未由本包重跑。完整CDC/输入依赖bit绑定not_run/证据缺口。|G3旧记录SRAM下载/150s采集reported pass for observation；G4整帧编码/导出blocked H4_UNRESOLVED，enc/exported=0；G5生产稳定性/吞吐not_run。读根因、确定第1239字和L_max=1均不签核。|
|T08隔离同步|冻结delivery-index记离线G0/G1 PASS；源码/README显示真实I2C/checked CSI和writer，仅明确环境stub。此包未重跑原矩阵或复用它为b15通过。|原交付G2 not_run。|原离线G3/G4/G5 not_applicable；当前生产迁入、真实曝光和板级恢复仍not_run。|
|双路local closure|冻结delivery-index记独立离线PASS，两套独立实现；本包仅作为资格索引引用。|真实生产G2 not_run in this audit。|当前板级曝光、双路A+生产闭环与稳定性not_run。|

G0在本工作流指接口层；性能讨论另称P1080。77.760/155.520MB/s是目标packed payload预算，非本包实测；u16长度4,147,200B和DDR存储129600×32B也不当作packed payload2,592,000B。此处只固定输入语义，详细搬运/吞吐在T06/T11。

## 执行、风险和回退

全部读/复制通过自有PowerShell Job的60秒deadline，见证Python进程WaitForExit(60000)，超时仅Kill本进程树；yield不作为timeout。探索中遇到.al内UsedInP&R未转义导致XML解析失败，改为精确File Path正则读取；一次Select-String未转义方括号失败，改为SimpleMatch。它们没有修改任何生产文件，也没有被当作成功验证。初次角色根技能读取为短直接Get-Content，未套本合同deadline；其余命令均落实deadline，该执行记录限制保留。

DeepSeek未用于本包：可分离的文本整理工作不足以抵消额外上下文发送/审查开销；复杂接口判断及最终核验均在本角色完成，没有声称代理审查。硬件/TD/bitgen/Flash/COM/JTAG/RK/网络下载/删除/commit/push均0。未动其他活动run、docs junction、workflow/tasks.json或baseline。源目录存在不代表本审查取得写权。

回退为保留现有方案与全部旧候选；本轮无生产改动。若综合测试发现文档/见证错误，续同任务开发并新冻轮次，保留当前输入和证据。下一位综合测试者在其允许目录复核manifest所有SHA、全部高风险发现、其余检查点引用和完整覆盖，至少一个不同于本开发的独立判据；不得将审查PASS解释为被审查DUT或四包整链路PASS。
''')
save('lessons.md','''# T02 可复用经验

- 根因类型：同为40bit不能证明格式兼容。触发：checked unpack输出4×10bit，而A+按五字节packed读。修正方向：唯一边界显式格式适配；验证入口witness/check_input_contract.py及真实跨模块源像素oracle。只用全0/全1图样会漏掉这个问题。
- 事务错误：计数凑齐ROI不等于源帧通过CRC/FE。触发：crop先置done，晚到good/abort未接。修正方向：持有pending帧直到采用的判定点，不能用晚abort挽回已发布帧。验证：最后ROI行CRC/后缀短长、缺FE与后续恢复。
- 证据边界：编译列表/源码样本/旧bit是三种身份。统一baseline缺依赖可包内补冻，但缺旧依赖SHA时不能给历史bit背书；同名upstream配置器不能替换b15依赖。
- .al不是通用规范XML：UsedInP&R含未转义&，严格XML parser失败。只提取精确File Path可读入口，不能据此声称TD格式有错。正则搜索cam_pix[须转义或用SimpleMatch；原失败留执行记录。
- 序号边界：成功准入计数不同于全源capture_seq；SOF mailbox到达时间差不同于曝光同步；两者均需元数据与真实设备证据，不能用离线PASS覆盖。
- 本轮仅审查；修复和硬件证据仍须原规划在未来授权范围排期。所有保护文件原样保留。
''')
js('commands.json',{'task_id':'T02.chain-input-review','cwd':str(ROOT),'executed':[
    {'operation':'role/input/source reconnaissance','command_family':'Get-Content -LiteralPath; Select-String; Get-FileHash; git status --short','deadline_seconds':60,'control':'Start-Job / Wait-Job -Timeout 60 / Stop-Job on own job; initial short root-skill read lacked wrapper','exit_code':0,'notes':'source ranges in source-map and checkpoints; existing dirty paths protected; output truncation prompted bounded targeted reads'},
    {'operation':'supplement capture first attempt','command_family':'[xml] Get-Content 0155.al; foreach File[@Path]','deadline_seconds':60,'exit_code':0,'semantic_status':'failed_metadata_parse','evidence':'UsedInP&R attribute contains unescaped ampersand; 0 supplement entries on that attempt; no source change'},
    {'operation':'supplement capture corrected once','command_family':'[regex]::Matches(.al, <File Path=...); Copy-Item exact selected files; SHA before/after/copied','deadline_seconds':60,'exit_code':0,'semantic_status':'13 snapshots captured','artifact':'supplemental-sources.json'},
    {'operation':'source search nonfatal error','command_family':'Select-String patterns including unescaped cam_pix[','deadline_seconds':60,'exit_code':0,'semantic_status':'pattern failed; later SimpleMatch corrected once','notes':'error not used as evidence'},
    {'operation':'arithmetic/static witness','command':'"C:/Program Files/Python311/python.exe" -B -X utf8 witness/check_input_contract.py --out witness/run-r0','cwd':str(OUT),'deadline_seconds':60,'control':'own Start-Process; WaitForExit(60000); Kill(true) only on timeout','exit_code':0,'marker':witness['marker'],'artifacts':['witness/run-r0/result.json','witness/stdout-r0.txt','witness/stderr-r0.txt']},
    {'operation':'artifact assembly and baseline verification','command':'"C:/Program Files/Python311/python.exe" -B -X utf8 build_review.py','cwd':str(OUT),'deadline_seconds':60,'control':'own Start-Process; WaitForExit(60000); Kill(true) only on timeout','exit_code':0,'marker':'T02_REVIEW_ARTIFACTS_WRITTEN','artifact':'baseline-verification-r0.json'}],
    'not_executed':['TD synthesis/P&R/bitgen','RTL/ModelSim full or micro simulation','hardware/COM/JTAG/Flash/RK','network download','DeepSeek delegation','deletion/commit/push'],
    'commands_are_not_DUT_signoff':True})
js('coverage-r0.json',{'five_steps':[
    {'step':1,'checkpoints':['C01','C02','C26'],'artifact':'source-map.json'},
    {'step':2,'checkpoints':[f'C{i:02d}' for i in range(3,16)],'artifact':'checkpoints.csv'},
    {'step':3,'checkpoints':[f'C{i:02d}' for i in range(16,26)]+['C27'],'artifact':'checkpoints.csv'},
    {'step':4,'checkpoints':['C28'],'artifact':'findings.json; witness/run-r0/result.json'},
    {'step':5,'checkpoints':[],'artifact':'review.md/checkpoints.csv/findings.json/source-map.json/witness/commands.json/lessons.md; manifest follows after activity stop'}],
    'checkpoints':len(rows),'unreviewed_or_blank_rows':0,'known_defects_preserved':True,
    'local_check_status':'completed; independent integrated acceptance pending','production_changes':0,'hardware_actions':0})
print('T02_REVIEW_ARTIFACTS_WRITTEN checkpoints='+str(len(rows))+' findings='+str(len(findings))+' baseline_files='+str(len(baseline_checks)))
