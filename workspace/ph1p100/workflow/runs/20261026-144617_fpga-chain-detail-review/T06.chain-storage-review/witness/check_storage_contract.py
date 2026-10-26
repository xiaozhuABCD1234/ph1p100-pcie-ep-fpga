"""Source-anchored arithmetic/state witnesses; no RTL/MC simulation."""
from pathlib import Path
import json, re, sys
HERE=Path(__file__).resolve().parent
RUN=HERE.parent.parent
BM=json.loads((RUN/'baseline/source-manifest.json').read_text(encoding='utf-8-sig'))
files={Path(f['snapshot_path']).name:Path(f['snapshot_path']) for f in BM['files']}
def source(name):return files[name].read_text(encoding='utf-8-sig')
store=source('0144.v'); bridge=source('0153.v'); top=source('0150.v'); exporter=source('0148.v')
anchors={
 'begin_advances_seq': 'slot_seq[free_slot] <= pub_tgl;' in store and 'pub_tgl   <= ~pub_tgl;' in store,
 'oldest_slot0_first': bool(re.search(r'slot_st\[0\] == S_READY\) && \(slot_seq\[0\] == rd_expect\)\) \? 2\x27d0',store)),
 'abort_leaves_seq_toggle': 'else if (abort_now) begin\n                slot_st[wr_slot] <= S_FREE;' in store,
 'native_reference_step8': "{wr_addr[APP_ADDR_WIDTH-3-1 : 0], 3'b000}" in source('0166.v'),
 'bridge_raw_address': 'assign paxi_araddr  = af_rdata;' in bridge and 'assign paxi_awaddr  = wf_rdata[282:256];' in bridge,
 'mask_all_ones': "assign paxi_wstrb   = 32'hFFFF_FFFF;" in bridge,
 'reference_mask_zero': "assign wmask_phase[p*DX_NUM+n] = 1'b0;" in source('0167.v'),
 'publish_on_store_accept': 'if (wr_ready) begin' in store and 'slot_st[wr_slot] <= S_READY;' in store,
 'no_shared_write_fence_in_ar_gate': 'assign paxi_arvalid = af_rvalid && !ar_busy && rf_path_empty &&' in bridge,
 'tagless_rf_push': 'rf_push     = paxi_rvalid && paxi_rready && ar_busy_win;' in bridge,
 'watchdog_close': 'raw_rd_close_r <= 1\'b1;' in top[top.index('else if (fwait_cycles >= WD_LIMIT)'):],
 'close_only_hold': store.count('if (rd_close)')==1 and 'if (rd_close)' in store[store.index('R_HOLD: begin'):],
 'export_mismatch_counts_then_continues': "if (cmp_id != w_frame_id) st_err <= st_err + 32'd1;" in exporter and 'estate     <= E_HDR;' in exporter,
}
assert all(anchors.values()),anchors

# Two distinguishable 256bit words; declared conditional address/mask semantics.
patterns=[int.from_bytes(bytes(range(32)),'little'),int.from_bytes(bytes(range(32,64)),'little')]
def memory_case(native_addr=False,active_mask=False,adapt=False):
    mem={}
    for idx,data in enumerate(patterns):
        addr=idx*8 if adapt else idx;mask=0 if adapt else (2**32-1)
        target=addr>>3 if native_addr else addr
        if not(active_mask and mask==2**32-1):mem[target]=data
    got=[]
    for idx in range(2):
        addr=idx*8 if adapt else idx;target=addr>>3 if native_addr else addr
        got.append(mem.get(target,0))
    return {'mismatch_count':sum(a!=b for a,b in zip(patterns,got)),'read_words_hex':['%064x'%x for x in got]}
cases={'permissive_word_index':memory_case(),'native_address_only':memory_case(True),'mask_only':memory_case(False,True),'native_address_and_mask':memory_case(True,True),'external_adapter_control':memory_case(True,True,True)}
assert [v['mismatch_count'] for v in cases.values()]==[0,1,2,2,0]

# Follow legal slot ownership events and compare to a publication FIFO oracle.
states=['FREE','FREE'];seq=[0,0];ids=[None,None];pub=0;expect=0;selected=None;trace=[];oracle=[]
def snap(event):trace.append({'event':event,'states':states.copy(),'seq':seq.copy(),'ids':ids.copy(),'pub_tgl':pub,'rd_expect':expect,'publication_fifo':oracle.copy()})
def begin(name):
    global pub,selected
    selected=states.index('FREE');states[selected]='WRITING';ids[selected]=name;seq[selected]=pub;pub^=1;snap('begin '+name)
def publish():
    states[selected]='READY';oracle.append(ids[selected]);snap('publish '+str(ids[selected]))
def open_slot():
    global expect
    s=next((i for i in [0,1] if states[i]=='READY' and seq[i]==expect),next(i for i in [0,1] if states[i]=='READY'))
    expected=oracle.pop(0);actual=ids[s];states[s]='READING';expect^=1;snap('open '+str(actual)+' expected '+str(expected));return s,expected,actual
begin('A');publish();a,_,_=open_slot()
begin('B');publish();states[a]='FREE';snap('close A')
begin('C');states[selected]='FREE';snap('abort C')
begin('D');publish();chosen,expected,actual=open_slot()
assert (expected,actual,chosen)==('B','D',0)

pixels=1920*1080;payload=pixels*10//8;groups=pixels//4;rawwords=(groups+3)//4;cmpwords=81085
assert rawwords==129600 and payload==2592000
rawddr=rawwords*32;cmpcapacity=cmpwords*32;fps=30
budget={'pixels_per_frame':pixels,'raw_payload_bytes':payload,'raw_groups':groups,'raw_slot_words':rawwords,'raw_ddr_bytes_per_direction':rawddr,'raw_transport_factor':rawddr/payload,'cmp_capacity_words':cmpwords,'cmp_capacity_bytes':cmpcapacity,'cmp_observed_example_bytes':2594706,'example_word_padding_bytes':cmpcapacity-2594706,'raw_ranges':[[0,rawwords-1],[rawwords,2*rawwords-1]],'cmp_ranges':[[262144,262144+cmpwords-1],[262144+cmpwords,262144+2*cmpwords-1]],'gap_words':262144-2*rawwords,'raw_payload_MBps_single':payload*fps/1e6,'raw_payload_MBps_dual':payload*fps*2/1e6,'raw_ddr_MBps_per_direction_single':rawddr*fps/1e6,'four_move_bytes_per_frame':2*rawddr+2*cmpcapacity,'four_move_MBps_single':(2*rawddr+2*cmpcapacity)*fps/1e6,'four_move_MBps_dual':(2*rawddr+2*cmpcapacity)*fps*2/1e6,'reference25_MBps_single':(2*rawddr+2*cmpcapacity)*fps*1.25/1e6,'reference25_MBps_dual':(2*rawddr+2*cmpcapacity)*fps*2.5/1e6,'word_moves_per_frame':2*(rawwords+cmpwords),'word_moves_per_second_single':2*(rawwords+cmpwords)*fps,'word_moves_per_second_dual':4*(rawwords+cmpwords)*fps,'mean_200MHz_cycles_per_move_single':200e6/(2*(rawwords+cmpwords)*fps),'mean_200MHz_cycles_per_move_dual':200e6/(4*(rawwords+cmpwords)*fps),'scope':'CMP capacity budget only, not proven expansion bound; excludes protocol/refresh/fence/retry overhead; slots are depth, not throughput.'}
assert budget['gap_words']==2944 and budget['four_move_bytes_per_frame']==13483840

# Explicit allowed bridge trace; absence of a fence, not observed MC behavior.
visibility=[{'event':'final RAW word accepted to WF','slot':'READY','native_write_complete':False},{'event':'consumer opens slot; AR queued to AF','slot':'READING','native_write_complete':False},{'event':'AF visible, ar_busy=0, rf_path_empty=1, ddr_rdy=1, rd_hold=0, ARready=1','native_AR_accepted':True,'native_AWready':False,'native_Wready':False},{'event':'native response sampled before blocked write','read_value':'OLD','expected_value':'NEW','qualification':'conditional responsive MC model; no real MC claim'}]
watchdog={'precondition':'R_AR, ddr_arready=0 throughout WD_LIMIT; top F_WAIT','top_after_watchdog':'F_IDLE; a1_abort=1;cmp_abort=1;raw_rd_close=1','store_transition_on_close':'R_AR -> R_AR (no matching rd_close branch)','rd_timeout':False,'rd_open_ready':False,'watchdog_cycles':16777216,'watchdog_ms_at_187_5MHz':16777216/187500,'qualification':'source-state trace, not RTL simulation'}
late={'old_response_after_guard':True,'new_ar_busy':True,'paxi_rvalid':True,'paxi_rready':True,'rf_push_old_as_new':True,'reason':'rf_push only tests ar_busy, no response transaction tag/epoch','qualification':'unbounded-delay conditional trace; actual MC lifetime/flush not proven'}
result={'marker':'STORAGE_WITNESS_COMPLETE','type':'source-anchored Python arithmetic/state witnesses; no RTL or hardware','source_anchors':anchors,'conditional_memory_cases':cases,'order_counterexample':{'trace':trace,'descriptor_expected':expected,'store_actual':actual,'mismatch':True},'publication_visibility_trace':visibility,'watchdog_state_trace':watchdog,'late_response_predicate':late,'service_budget':budget}
if '--stdout' in sys.argv: print(json.dumps(result,ensure_ascii=False,indent=2))
else:
    (HERE/'result-r0.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('STORAGE_WITNESS_COMPLETE cases=5 order_expected=B actual=D single_MBps=404.5152 dual_MBps=809.0304')
