`timescale 1ns/1ps
module tb_integrated_top_smoke;
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
  integrated_input_processing_top #(.MAX_WORDS(512),.WIDTH(16),.HEIGHT(12)) dut(
    .clk(clk),.rst_n(rst_n),.cfg_valid(cfg_valid),.cfg_ready(cfg_ready),.cfg_width(cfg_width),.cfg_height(cfg_height),.cfg_phase(cfg_phase),.cfg_mode(cfg_mode),.cfg_error(cfg_error),
    .s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),.s_abort(s_abort),
    .m_ready(m_ready),.m_valid(m_valid),.m_mode(m_mode),.m_is_raw(m_is_raw),.m_raw_data(m_raw_data),.m_proc_data(m_proc_data),.m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof),.m_abort(m_abort),
    .pk_ready(pk_ready),.pk_valid(pk_valid),.pk_data(pk_data),.pk_sof(pk_sof),.pk_eol(pk_eol),.pk_eof(pk_eof),.pk_abort(pk_abort),
    .st_frames_good(st_frames_good),.st_frames_abort(st_frames_abort)
  );
  always #5 clk=~clk;
  integer errors=0;
  initial begin
    rst_n=0; #20; rst_n=1;
    // configure raw mode
    cfg_width=16; cfg_height=12; cfg_phase=3; cfg_mode=0; cfg_valid=1;
    #10; cfg_valid=0;
    if(cfg_error) begin $display("CFG ERROR"); errors=errors+1; end
    // send one beat
    s_data={10'd4,10'd3,10'd2,10'd1};
    s_valid=1; s_sof=1; s_eol=0; s_eof=0; s_abort=0;
    #10; s_valid=0; s_sof=0;
    if(!m_valid) begin $display("M_VALID FAIL"); errors=errors+1; end
    if(!m_is_raw) begin $display("M_IS_RAW FAIL"); errors=errors+1; end
    if(m_raw_data !== s_data) begin $display("M_RAW_DATA FAIL"); errors=errors+1; end
    if(!pk_valid) begin $display("PK_VALID FAIL"); errors=errors+1; end
    // expected packed
    if(pk_data !== 40'h3901000000) begin $display("PK_DATA FAIL got=%h", pk_data); errors=errors+1; end
    if(errors==0) $display("TB_INTEGRATED_TOP_SMOKE PASS");
    else $display("TB_INTEGRATED_TOP_SMOKE FAIL errors=%0d", errors);
    $finish;
  end
endmodule