import random
# source ramp 16x12
W,H=16,12
raw=[(y*7+x*3)&0x3FF for y in range(H) for x in range(W)]
# pack 4 samples per beat: s_data P3..P0? integrated input s_data[9:0]=P0,...[39:30]=P3
beats=[]
for i in range(0,len(raw),4):
    p0,p1,p2,p3=raw[i:i+4]
    val=p0|(p1<<10)|(p2<<20)|(p3<<30)
    beats.append(val)
lines=[]
lines.append('`timescale 1ns/1ps')
lines.append('module tb_integrated_gray;')
lines.append('  reg clk=0,rst_n=0;')
lines.append('  reg cfg_valid=0; wire cfg_ready;')
lines.append('  reg [11:0] cfg_width=0,cfg_height=0;')
lines.append('  reg [1:0] cfg_phase=0;')
lines.append('  reg [2:0] cfg_mode=0;')
lines.append('  wire cfg_error;')
lines.append('  reg s_valid=0; wire s_ready;')
lines.append('  reg [39:0] s_data=0;')
lines.append('  reg s_sof=0,s_eol=0,s_eof=0,s_abort=0;')
lines.append('  reg m_ready=1;')
lines.append('  wire m_valid; wire [2:0] m_mode; wire m_is_raw; wire [39:0] m_raw_data; wire [31:0] m_proc_data;')
lines.append('  wire m_sof,m_eol,m_eof,m_abort;')
lines.append('  reg pk_ready=1;')
lines.append('  wire pk_valid; wire [39:0] pk_data; wire pk_sof,pk_eol,pk_eof,pk_abort;')
lines.append('  wire [15:0] st_frames_good,st_frames_abort;')
lines.append('  integrated_input_processing_top #(.MAX_WORDS(512),.WIDTH(16),.HEIGHT(12)) dut(.clk(clk),.rst_n(rst_n),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_width(cfg_width),.cfg_height(cfg_height),.cfg_phase(cfg_phase),.cfg_mode(cfg_mode),.cfg_error(cfg_error),.s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),.s_abort(s_abort),.m_ready(m_ready),.m_valid(m_valid),.m_mode(m_mode),.m_is_raw(m_is_raw),.m_raw_data(m_raw_data),.m_proc_data(m_proc_data),.m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof),.m_abort(m_abort),.pk_ready(pk_ready),.pk_valid(pk_valid),.pk_data(pk_data),.pk_sof(pk_sof),.pk_eol(pk_eol),.pk_eof(pk_eof),.pk_abort(pk_abort),.st_frames_good(st_frames_good),.st_frames_abort(st_frames_abort));')
lines.append('  always #5 clk=~clk;')
lines.append('  integer errors=0, beat=0, seen=0;')
lines.append('  reg [31:0] first_proc=0;')
lines.append('  initial begin')
lines.append('    rst_n=0; #20; rst_n=1;')
lines.append('    cfg_width=16; cfg_height=12; cfg_phase=3; cfg_mode=1; cfg_valid=1;')
lines.append('    #10; cfg_valid=0;')
lines.append('    // wait a few cycles')
lines.append('    #20;')
for idx,val in enumerate(beats):
    sof = 1 if idx==0 else 0
    eol = 1 if (idx+1)%4==0 else 0  # 4 beats per row? 16 px/beat=4 beats/row? Actually 16/4=4 beats per row, so eol on 4th beat
    eof = 1 if idx==len(beats)-1 else 0
    lines.append(f'    @(posedge clk); s_data=40\'h{val:010x}; s_valid=1; s_sof={sof}; s_eol={eol}; s_eof={eof}; s_abort=0;')
lines.append('    @(posedge clk); s_valid=0; s_sof=0; s_eol=0; s_eof=0;')
lines.append('    // run to drain')
lines.append('    repeat(200) @(posedge clk);')
lines.append('    $display("GRAY first_proc=%h seen=%0d", first_proc, seen);')
lines.append('    if (first_proc !== 32\'h03020100) begin $display("GRAY FIRST MISMATCH"); errors=errors+1; end')
lines.append('    if (errors==0) $display("TB_INTEGRATED_GRAY PASS");')
lines.append('    else $display("TB_INTEGRATED_GRAY FAIL errors=%0d", errors);')
lines.append('    $finish;')
lines.append('  end')
lines.append('  always @(posedge clk) begin')
lines.append('    if (m_valid && !seen) begin first_proc <= m_proc_data; seen <= 1; end')
lines.append('  end')
lines.append('endmodule')
out=r'D:\fpga\ph1p100\workflow\runs\20261026-2138_fpga-integrated-delivery\test-reports\INT.P1\evidence\tb_integrated_gray.v'
open(out,'w').write('\n'.join(lines))
print('generated', out, 'beats', len(beats))