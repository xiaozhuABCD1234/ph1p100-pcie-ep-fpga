import random,json
rng=random.Random(999)
lines=[]
lines.append('`timescale 1ns/1ps')
lines.append('module tb_raw10_packer_strong;')
lines.append('  reg clk=0,rst_n=0;')
lines.append('  reg s_valid=0; wire s_ready;')
lines.append('  reg [39:0] s_data=0;')
lines.append('  reg s_sof=0,s_eol=0,s_eof=0,s_abort=0;')
lines.append('  reg m_ready=1;')
lines.append('  wire m_valid; wire [39:0] m_data;')
lines.append('  wire m_sof,m_eol,m_eof,m_abort;')
lines.append('  raw10_sample_vector_to_packed dut(.clk(clk),.rst_n(rst_n),.s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),.s_abort(s_abort),.m_ready(m_ready),.m_valid(m_valid),.m_data(m_data),.m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof),.m_abort(m_abort));')
lines.append('  always #5 clk=~clk;')
lines.append('  integer errors=0,i;')
lines.append('  initial begin')
lines.append('    rst_n=0; #20; rst_n=1;')
vecs=[]
for t in range(200):
    s=[rng.randrange(1024) for _ in range(4)]
    p0,p1,p2,p3=s
    b0=(p0>>2)&0xff; b1=(p1>>2)&0xff; b2=(p2>>2)&0xff; b3=(p3>>2)&0xff
    b4=(p0&3)|((p1&3)<<2)|((p2&3)<<4)|((p3&3)<<6)
    exp=b0|(b1<<8)|(b2<<16)|(b3<<24)|(b4<<32)
    vecs.append((s,exp))
    # apply
    lines.append(f'    s_data = {{10\'d{p3},10\'d{p2},10\'d{p1},10\'d{p0}}};')
    lines.append(f'    s_valid=1; s_sof={(1 if t==0 else 0)}; s_eol={(1 if t%7==0 else 0)}; s_eof={(1 if t==199 else 0)}; s_abort=0; #10;')
    lines.append(f'    if (m_data !== 40\'h{exp:010x}) begin $display("DATA MISMATCH t={t} got=%h exp={exp:x}", m_data); errors=errors+1; end')
    lines.append(f'    if (m_sof !== {(1 if t==0 else 0)}) begin $display("SOF MISMATCH t={t}"); errors=errors+1; end')
    lines.append(f'    if (m_eol !== {(1 if t%7==0 else 0)}) begin $display("EOL MISMATCH t={t}"); errors=errors+1; end')
    lines.append(f'    if (m_eof !== {(1 if t==199 else 0)}) begin $display("EOF MISMATCH t={t}"); errors=errors+1; end')
    lines.append('    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end')
lines.append('    s_valid=0; s_sof=0; s_eol=0; s_eof=0;')
lines.append('    #20;')
lines.append('    if (errors==0) $display("TB_RAW10_PACK_STRONG PASS");')
lines.append('    else $display("TB_RAW10_PACK_STRONG FAIL errors=%0d", errors);')
lines.append('    $finish;')
lines.append('  end')
lines.append('endmodule')
out=r'D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\test-reports\INT.P1\evidence\tb_raw10_packer_strong.v'
open(out,'w').write('\n'.join(lines))
print('generated', out)