`timescale 1ns/1ps
module tb_raw10_packer;
    reg s_valid = 0; wire s_ready;
    reg [39:0] s_data = 0;
    reg s_sof = 0, s_eol = 0, s_eof = 0, s_abort = 0;
    reg m_ready = 1;
    wire m_valid; wire [39:0] m_data;
    wire m_sof, m_eol, m_eof, m_abort;

    raw10_sample_vector_to_packed dut(
        .clk(1'b0), .rst_n(1'b1),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .m_ready(m_ready), .m_valid(m_valid), .m_data(m_data),
        .m_sof(m_sof), .m_eol(m_eol), .m_eof(m_eof), .m_abort(m_abort)
    );

    integer errors = 0;
    initial begin
        // case 1
        s_data = {10'd4,10'd3,10'd2,10'd1}; // P3=4,P2=3,P1=2,P0=1
        s_valid = 1; s_sof = 1; s_eol = 0; s_eof = 0; s_abort = 0;
        #1;
        if (m_data !== 40'h3901000000) begin $display("DATA FAIL got=%h", m_data); errors = errors + 1; end
        if (m_sof !== 1) begin $display("SOF FAIL"); errors = errors + 1; end
        if (m_valid !== 1) begin $display("VALID FAIL"); errors = errors + 1; end
        s_valid = 0; s_sof = 0;
        #10;
        if (errors == 0) $display("TB_RAW10_PACK PASS");
        else $display("TB_RAW10_PACK FAIL errors=%0d", errors);
        $finish;
    end
endmodule