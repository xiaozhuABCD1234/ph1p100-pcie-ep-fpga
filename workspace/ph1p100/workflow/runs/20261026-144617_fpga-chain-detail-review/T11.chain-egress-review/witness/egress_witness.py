"""Reproducible source-anchored arithmetic/event witness, not RTL or hardware simulation."""
from pathlib import Path
import argparse, csv, hashlib, json, re, sys, datetime

TASK=Path(__file__).resolve().parents[1]
RUN=TASK.parent
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def text(n): return (RUN/'baseline/snapshot'/n).read_text(encoding='utf-8-sig')
def ceil(n,a): return (n+a-1)//a*a

def run(out):
    out=Path(out).resolve(); out.mkdir(parents=True,exist_ok=True)
    pusher=text('0101.v'); exporter=text('0148.v'); top=text('0123.v'); writer=text('0098.v')
    assert '((ddr_base + frame_bytes) <= ddr_cap_eff)' in pusher
    assert 'base_s2[28:0] + a_bcnt * BURST_STEP' in pusher
    assert re.search(r'input\s+wire\s+\[31:0\]\s+ddr_base',pusher)
    assert re.search(r'input\s+wire\s+\[31:0\]\s+frame_bytes',pusher)
    assert re.search(r'wire\s+\[31:0\]\s+ddr_cap_eff',pusher)
    eopen=exporter.split('E_OPEN: begin',1)[1].split('E_HDR: begin',1)[0]
    assert 'if (cmp_open_ready)' in eopen and 'cmp_id != w_frame_id' in eopen
    assert 'cmp_len != w_stream_len' in eopen and "estate     <= E_HDR;" in eopen
    assert eopen.count('if (')==3, 'Unexpected E_OPEN source changes require rereview'
    assert '.PAY_DW      (32' in top and '.BURST_BEATS (128' in top
    assert '((PAY_BYTES + HDR_BYTES + 4095) / 4096) * 4096' in writer
    # Wide integer oracle rejects out-of-range while exact 32-bit source expression wraps.
    cap=0x10000000; length=4096
    boundary=[]
    for base in [0x00100000,cap-length,cap,0xffffe000,0xfffff000]:
        rtl_sum=(base+length)&0xffffffff
        rtl=(base&4095)==0 and base!=0 and rtl_sum<=cap
        oracle=(base&4095)==0 and base!=0 and base<cap and base+length<=cap
        boundary.append(dict(base=hex(base),bytes=length,capacity=cap,wide_end=hex(base+length),source_32bit_end=hex(rtl_sum),source_claim=rtl,wide_oracle=oracle,first_AR29=hex(base&0x1fffffff)))
    assert boundary[0]['source_claim']==boundary[0]['wide_oracle']==True
    assert boundary[1]['source_claim']==boundary[1]['wide_oracle']==True
    assert boundary[2]['source_claim']==boundary[2]['wide_oracle']==False
    assert boundary[-1]['source_claim'] and not boundary[-1]['wide_oracle']
    # E_OPEN executable event projection. Counterexample is interface fault injection only.
    desc=[]
    for ready in [False,True]:
        for same_id in [False,True]:
            for same_len in [False,True]:
                desc.append(dict(ready=ready,id_match=same_id,length_match=same_len,source_opens=ready,source_next_state='E_HDR' if ready else 'E_OPEN',fail_closed_oracle_opens=ready and same_id and same_len))
    bad=[x for x in desc if x['source_opens']!=x['fail_closed_oracle_opens']]
    assert len(bad)==3
    # Exact packet/header arithmetic; no hypothetical A+ payload inserted into RAW codec0.
    raw=1920*1080*5//4; aplus=raw+540*5+6; a1u1=aplus+44
    r10f_content=raw+128; dma=ceil(r10f_content,4096); n= dma//128
    tlp_bytes=dma+n*16+20
    rawstore=129600*32; cmpalloc=ceil(aplus,32); ddr=2*(rawstore+cmpalloc)
    budget=dict(raw_payload_B=raw,raw_single_MBps=raw*30/1e6,raw_dual_MBps=raw*60/1e6,
        aplus_ideal_zlib_upper_B=aplus,aplus_single_MBps=aplus*30/1e6,aplus_dual_MBps=aplus*60/1e6,
        aplus_outer_A1U1_B=a1u1,aplus_outer_single_MBps=a1u1*30/1e6,
        r10f_header_B=128,r10f_content_B=r10f_content,r10f_DMA_B=dma,r10f_padding_B=dma-r10f_content,
        r10f_TLP_count=n,r10f_TLP_header_B=16,doorbell_TLP_B=20,r10f_TLP_total_B=tlp_bytes,
        r10f_TLP_single_MBps=tlp_bytes*30/1e6,r10f_TLP_dual_MBps=tlp_bytes*60/1e6,
        raw_store_B=rawstore,cmp_alloc32_B=cmpalloc,cmp_slot_margin_B=cmpalloc-aplus,
        ddr_four_pass_B_per_frame=ddr,ddr_single_MBps=ddr*30/1e6,ddr_dual_MBps=ddr*60/1e6,
        uart_115200_8N1_seconds_aplus_outer=a1u1*10/115200,
        note='Pure budgets; A+ upper conditional on true bit-offset cost; TLP excludes DLL/PHY; DDR excludes control/refresh/stalls; UART115200 illustrative not measured board baud.')
    assert (raw,aplus,a1u1,dma,n,tlp_bytes)==(2592000,2594706,2594750,2592768,20256,2916884)
    assert budget['r10f_padding_B']==640 and budget['ddr_dual_MBps']==809.0304
    page=[dict(offset=o,end=o+128,within_page=o+128<=4096) for o in range(0,4096,128)]
    assert len(page)==32 and all(x['within_page'] for x in page)
    mps=[dict(code=c,bytes=128<<c,default_payload_fits=128<=128<<c) for c in range(6)]
    assert all(x['default_payload_fits'] for x in mps)
    facts=dict(data_header_valid='F0 four DW',data_valid='FF eight DW',doorbell_valid='F8 five DW',
        data_first_BE=15,data_last_BE=15,doorbell_first_BE=15,doorbell_last_BE=0,
        ack_event='G_HELD and equal nonzero session and equal seq; local done is not host read completion')
    assert "4'hf, 4'hf" in pusher and "4'h0, 4'hf" in pusher
    result=dict(task_id='T11.chain-egress-review',status='local_witness_pass',method='source-anchored arithmetic and event projection; not RTL/DUT/board simulation',
        source_hashes={n:sha(RUN/'baseline/snapshot'/n) for n in ['0101.v','0148.v','0123.v','0098.v']},
        source_wrap_cases=boundary,export_E_OPEN_cases=desc,export_mismatch_cases=bad,
        long_descriptor_example=dict(desc_len=33,slot_exact_len=1,slot_alloc_word_B=32,reason='After32 copied bytes no next word exists; pending word33 cannot be satisfied in this isolated fault input.'),
        default_page_cases=page,legal_MPS_cases=mps,TL_local_facts=facts,budget=budget,
        limitations=['No cycle-accurate RTL','Descriptor mismatch full-size default reachability unproven','Source wrap outside frozen fixed low writer bases','No host/IP/DDR service or hardware acceptance claim'])
    (out/'result-r0.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    with (out/'budget.csv').open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.writer(f);w.writerow(['quantity','value','qualification'])
        for k,v in budget.items(): w.writerow([k,v,budget['note']])
    print(json.dumps({'status':result['status'],'descriptor_counterexamples':len(bad),'source_wrap_counterexamples':sum(x['source_claim']!=x['wide_oracle'] for x in boundary),'budget':budget},ensure_ascii=False))

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--out',required=True);run(ap.parse_args().out)
