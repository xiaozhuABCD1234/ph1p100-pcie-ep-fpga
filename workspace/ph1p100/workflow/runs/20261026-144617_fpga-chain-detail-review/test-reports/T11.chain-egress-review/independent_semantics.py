import json,re,hashlib,itertools,csv
from pathlib import Path
from fractions import Fraction
RUN=Path(r'D:\fpga\ph1p100\workflow\runs\20261026-144617_fpga-chain-detail-review'); P=RUN/'T11.chain-egress-review'; O=RUN/'test-reports'/'T11.chain-egress-review'
def read(p): return p.read_text(encoding='utf-8-sig')
src=read(RUN/'baseline/snapshot/0148.v'); body=re.search(r'E_OPEN:\s*(begin.*?)\n\s*E_HDR:',src,re.S).group(1)
# Parse the actual frozen E_OPEN source into a tiny statement AST. No developer
# model or witness code is imported. This parser only accepts the shown subset.
def parse(s):
    s=re.sub(r'//[^\n]*','',s); toks=re.findall(r"\d+'[bdhBDH][0-9a-fA-F_]+|\w+|<=|!=|==|&&|\|\||[();+!]|.",s)
    toks=[x for x in toks if not x.isspace()]; pos=0
    def stmt():
        nonlocal pos
        t=toks[pos]; pos+=1
        if t=='begin':
            a=[]
            while toks[pos]!='end': a.append(stmt())
            pos+=1; return ('block',a)
        if t=='if':
            assert toks[pos]=='('; pos+=1; depth=1; cond=[]
            while depth:
                x=toks[pos]; pos+=1
                if x=='(': depth+=1
                elif x==')': depth-=1
                if depth: cond.append(x)
            return ('if',cond,stmt())
        assert toks[pos]=='<=',(t,toks[pos]); pos+=1; rhs=[]
        while toks[pos]!=';': rhs.append(toks[pos]); pos+=1
        pos+=1; return ('assign',t,rhs)
    result=stmt(); assert pos==len(toks),(pos,toks[pos:]); return result
def guards(ast,name,value,path=()):
    if ast[0]=='block': return sum([guards(x,name,value,path) for x in ast[1]],[])
    if ast[0]=='if': return guards(ast[2],name,value,path+(' '.join(ast[1]),))
    return [list(path)] if ast[1]==name and ''.join(ast[2])==value else []
def ev(tokens,env):
    s=' '.join(tokens); s=s.replace('&&',' and ').replace('||',' or ')
    s=re.sub(r"(\d+)'([bdhBDH])([0-9a-fA-F_]+)",lambda m:str(int(m[3].replace('_',''),{'b':2,'d':10,'h':16}[m[2].lower()])),s)
    assert not re.search(r'[^\w\s()=!+<>-]',s),s
    assert all(t in env or t in ('and','or') for t in re.findall(r'\b[A-Za-z_]\w*\b',s)),s
    return eval(s,{'__builtins__':{}},env)
def execute(ast,env,out):
    if ast[0]=='block':
        for x in ast[1]: execute(x,env,out)
    elif ast[0]=='if':
        if ev(ast[1],env): execute(ast[2],env,out)
    else: out[ast[1]]=ev(ast[2],env)
ast=parse(body); header_paths=guards(ast,'estate','E_HDR'); open_paths=guards(ast,'cmp_open',"1'b1")
assert header_paths==[['cmp_open_ready']] and open_paths==[['cmp_open_ready']]
mut=body.replace('if (cmp_open_ready)','if (cmp_open_ready && (cmp_id == w_frame_id) && (cmp_len == w_stream_len))')
(O/'E_OPEN_original.vfrag').write_text(body,encoding='utf-8'); (O/'E_OPEN_guard_control.vfrag').write_text(mut,encoding='utf-8')
mut_ast=parse(mut); cases=[]
for ready,idok,lenok in itertools.product((False,True),repeat=3):
    env={'cmp_open_ready':ready,'cmp_id':7 if idok else 8,'w_frame_id':7,'cmp_len':33 if lenok else 1,'w_stream_len':33,'st_err':0,'E_HDR':4,'P_PAY':1}; actual={}; control={}; execute(ast,env,actual); execute(mut_ast,env,control)
    expected=ready and idok and lenok; cases.append({'ready':ready,'id_match':idok,'len_match':lenok,'contract_accept':expected,'actual_header':actual.get('estate')==4,'control_header':control.get('estate')==4,'actual_open':actual.get('cmp_open',0)})
assert sum(c['actual_header']!=c['contract_accept'] for c in cases)==3
assert all(c['control_header']==c['contract_accept'] for c in cases)
assert cases[-1]['actual_header'] and cases[-1]['control_header']
f01={'method':'parse frozen HDL statement AST; inspect transition control dependence; isolated guard mutation','header_control_paths':header_paths,'cmp_open_control_paths':open_paths,'cases':cases,'counterexamples':3,'limitation':'source-level transition analysis only; no HDL simulator or full-size reachability claim'}
(O/'independent-export-control.json').write_text(json.dumps(f01,indent=2),encoding='utf-8')
# A wide-integer capacity oracle is intentionally phrased as a remaining-space
# test, avoiding the DUT and developer wrap-based range expression.
capacity=0x10000000; length=4096; address_cases=[]
for base in (0,0x1000,0x08000000,capacity-length,capacity,0xfffff000):
    oracle=base!=0 and base%4096==0 and base<capacity and length<=capacity-base
    actual=base!=0 and base%4096==0 and ((base+length)&0xffffffff)<=capacity
    address_cases.append({'base':hex(base),'remaining_capacity_oracle':oracle,'RTL_32bit_expression':actual,'AR29':hex(base&((1<<29)-1))})
assert address_cases[-1]['remaining_capacity_oracle']==False and address_cases[-1]['RTL_32bit_expression']==True
page_cases=[{'offset':off,'last_byte_page':(off+127)//4096} for off in range(0,4096,128)]
assert all(x['last_byte_page']==0 for x in page_cases)
data={}; raw=1920*1080*10//8; upper=raw+5*(1080//2)+6; dma=((raw+128+4095)//4096)*4096; count=dma//128; wire=dma+count*16+20; raw_alloc=1920//4*1080//4*32; cmp_alloc=((upper+31)//32)*32; ddr=2*(raw_alloc+cmp_alloc)
data.update(raw_payload_B=raw,raw_single_MBps=raw*30/1e6,raw_dual_MBps=raw*60/1e6,aplus_ideal_zlib_upper_B=upper,aplus_single_MBps=upper*30/1e6,aplus_dual_MBps=upper*60/1e6,aplus_outer_A1U1_B=upper+44,aplus_outer_single_MBps=(upper+44)*30/1e6,r10f_header_B=128,r10f_content_B=raw+128,r10f_DMA_B=dma,r10f_padding_B=dma-raw-128,r10f_TLP_count=count,r10f_TLP_header_B=16,doorbell_TLP_B=20,r10f_TLP_total_B=wire,r10f_TLP_single_MBps=wire*30/1e6,r10f_TLP_dual_MBps=wire*60/1e6,raw_store_B=raw_alloc,cmp_alloc32_B=cmp_alloc,cmp_slot_margin_B=cmp_alloc-upper,ddr_four_pass_B_per_frame=ddr,ddr_single_MBps=ddr*30/1e6,ddr_dual_MBps=ddr*60/1e6,uart_115200_8N1_seconds_aplus_outer=(upper+44)*10/115200)
budget=list(csv.DictReader(read(P/'budget.csv').splitlines())); compared=[]
for row in budget:
    if row['quantity']=='note': continue
    q=row['quantity']; expected=data[q]; actual=float(row['value']); assert abs(expected-actual)<1e-8,(q,expected,actual); compared.append(q)
result={'method':'independent remaining-capacity range oracle, last-byte page oracle and integer allocation/TLP arithmetic','source_address_cases':address_cases,'page_cases':page_cases,'budget':data,'budget_fields_checked':len(compared),'Aplus_upper_qualification':'conditional true bit-offset cost from already accepted T10; no claim that RTL offset equivalence or actual bound is proven','limitation':'no IP, DDR or hardware service measurement'}
(O/'independent-address-budget.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('T11_INDEPENDENT_SEMANTICS_COMPLETE: AST counterexamples=3, guard-control=8, address/page/budget checks complete')
