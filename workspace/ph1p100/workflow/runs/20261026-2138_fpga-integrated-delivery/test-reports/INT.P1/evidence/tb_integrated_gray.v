`timescale 1ns/1ps
module tb_integrated_gray;
  reg clk=0,rst_n=0;
  reg cfg_valid=0; wire cfg_ready;
  reg [11:0] cfg_width=0,cfg_height=0;
  reg [1:0] cfg_phase=0;
  reg [2:0] cfg_mode=0;
  wire cfg_error;
  reg s_valid=0; wire s_ready;
  reg [39:0] s_data=0;
  reg s_sof=0,s_eol=0,s_eof=0,s_abort=0;
  reg m_ready=1;
  wire m_valid; wire [2:0] m_mode; wire m_is_raw; wire [39:0] m_raw_data; wire [31:0] m_proc_data;
  wire m_sof,m_eol,m_eof,m_abort;
  reg pk_ready=1;
  wire pk_valid; wire [39:0] pk_data; wire pk_sof,pk_eol,pk_eof,pk_abort;
  wire [15:0] st_frames_good,st_frames_abort;
  integrated_input_processing_top #(.MAX_WORDS(512),.WIDTH(16),.HEIGHT(12)) dut(.clk(clk),.rst_n(rst_n),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_width(cfg_width),.cfg_height(cfg_height),.cfg_phase(cfg_phase),.cfg_mode(cfg_mode),.cfg_error(cfg_error),.s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),.s_abort(s_abort),.m_ready(m_ready),.m_valid(m_valid),.m_mode(m_mode),.m_is_raw(m_is_raw),.m_raw_data(m_raw_data),.m_proc_data(m_proc_data),.m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof),.m_abort(m_abort),.pk_ready(pk_ready),.pk_valid(pk_valid),.pk_data(pk_data),.pk_sof(pk_sof),.pk_eol(pk_eol),.pk_eof(pk_eof),.pk_abort(pk_abort),.st_frames_good(st_frames_good),.st_frames_abort(st_frames_abort));
  always #5 clk=~clk;
  integer errors=0, beat=0, seen=0, mvcount=0;
  reg [31:0] first_proc=0;
  initial begin
    rst_n=0; #20; rst_n=1;
    cfg_width=16; cfg_height=12; cfg_phase=3; cfg_mode=1; cfg_valid=1;
    #10; cfg_valid=0;
    $display("AFTER CFG cfg_ready=%b cfg_error=%b", cfg_ready, cfg_error);
    // wait a few cycles
    #20;
    @(posedge clk); s_data=40'h0240600c00; s_valid=1; s_sof=1; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0541203c0c; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0841e06c18; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0b42a09c24; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0400d02807; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0701905813; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0a0250881f; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0d0310b82b; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h05c140440e; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h08c200741a; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0bc2c0a426; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0ec380d432; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0781b06015; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0a82709021; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0d8330c02d; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1083f0f039; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0942207c1c; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0c42e0ac28; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0f43a0dc34; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1244610c40; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0b02909823; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0e0350c82f; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h110410f83b; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1404d12847; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0cc300b42a; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0fc3c0e436; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h12c4811442; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h15c541444e; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h0e8370d031; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h118431003d; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1484f13049; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1785b16055; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1043e0ec38; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1344a11c44; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1645614c50; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1946217c5c; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h120451083f; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h150511384b; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1805d16857; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1b06919863; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h13c4c12446; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h16c5815452; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h19c641845e; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1cc701b46a; s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h158531404d; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1885f17059; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1b86b1a065; s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0;
    @(posedge clk); s_data=40'h1e8771d071; s_valid=1; s_sof=0; s_eol=1; s_eof=1; s_abort=0;
    @(posedge clk); s_valid=0; s_sof=0; s_eol=0; s_eof=0;
    // run to drain
    repeat(2000) @(posedge clk);
    $display("GRAY first_proc=%h seen=%0d m_valid_count=%0d", first_proc, seen, mvcount);
    if (first_proc !== 32'h03020100) begin $display("GRAY FIRST MISMATCH"); errors=errors+1; end
    if (errors==0) $display("TB_INTEGRATED_GRAY PASS");
    else $display("TB_INTEGRATED_GRAY FAIL errors=%0d", errors);
    $finish;
  end
  always @(posedge clk) begin
    if (m_valid) mvcount <= mvcount + 1;
    if (m_valid && !seen) begin first_proc <= m_proc_data; seen <= 1; end
  end
endmodule