module cam_algo_diagnostics #(
    parameter integer W=1920,H=1080,X0=960,Y0=540,SKIP_ROWS=37,FIFO_AW=10,
    parameter [1:0] PHASE=3
)(
    input wire clk,rst_n,cam_vsync,cam_in_frame,cam_in_line,
    input wire [39:0] cam_pix,
    input wire cam_pix_valid,cam_good,cam_abort,
    input wire [2:0] sink_ready
);
    wire sv,sr,ss,sl,se,sa,cr,ce;
    wire [39:0] sd;
    reg configured;
    wire [2:0] ov,os,ol,oe,oa,terminal;
    wire [31:0] od0,od1,od2;
    wire [31:0] crc0,crc1,crc2,complete0,complete1,complete2,reject0,reject1,reject2,beats0,beats1,beats2;
    wire [31:0] accepted,rejected,overflow,inbeats;
    wire busy;
    reg [2:0] done_seen;
    wire all_done=&(done_seen|terminal);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin configured<=0;done_seen<=0;end
        else begin
            if(cr) configured<=1;
            if(all_done) done_seen<=0;else done_seen<=done_seen|terminal;
        end
    end
    csi_algo_roi_adapter #(.W(W),.H(H),.X0(X0),.Y0(Y0),.SKIP_ROWS(SKIP_ROWS),.FIFO_AW(FIFO_AW)) u_adapter (
        .clk(clk),.rst_n(rst_n),.cam_vsync(cam_vsync),.cam_in_frame(cam_in_frame),.cam_in_line(cam_in_line),
        .cam_pix(cam_pix),.cam_pix_valid(cam_pix_valid),.cam_good(cam_good),.cam_abort(cam_abort),
        .configured(configured&&!ce),.outputs_done(all_done),
        .s_valid(sv),.s_ready(sr),.s_data(sd),.s_sof(ss),.s_eol(sl),.s_eof(se),.s_abort(sa),
        .accepted_frames(accepted),.rejected_frames(rejected),.overflow_frames(overflow),.accepted_beats(inbeats),.busy(busy)
    );
    img_algo_parallel_top #(.MAX_WORDS(512)) u_algorithms (
        .clk(clk),.rst_n(rst_n),.cfg_valid(cr),.cfg_ready(cr),.cfg_width(W[11:0]),.cfg_height(H[11:0]),.cfg_phase(PHASE),.cfg_error(ce),
        .s_valid(sv),.s_ready(sr),.s_data(sd),.s_sof(ss),.s_eol(sl),.s_eof(se),.s_abort(sa),
        .y8_valid(ov[0]),.y8_ready(sink_ready[0]),.y8_data(od0),.y8_sof(os[0]),.y8_eol(ol[0]),.y8_eof(oe[0]),.y8_abort(oa[0]),
        .gau_valid(ov[1]),.gau_ready(sink_ready[1]),.gau_data(od1),.gau_sof(os[1]),.gau_eol(ol[1]),.gau_eof(oe[1]),.gau_abort(oa[1]),
        .he_valid(ov[2]),.he_ready(sink_ready[2]),.he_data(od2),.he_sof(os[2]),.he_eol(ol[2]),.he_eof(oe[2]),.he_abort(oa[2]),
        .st_frames_good(),.st_frames_abort(),.st_he_published(),.st_he_rejected(),.st_gau_abort(),.he_lut_addr(8'd0),.he_lut_data()
    );
    algo_diagnostic_sink u_y8(.clk(clk),.rst_n(rst_n),.valid(ov[0]&&sink_ready[0]),.data(od0),.sof(os[0]),.eol(ol[0]),.eof(oe[0]),.abort(oa[0]),.terminal(terminal[0]),.completed(complete0),.rejected(reject0),.last_crc(crc0),.last_beats(beats0));
    algo_diagnostic_sink u_gau(.clk(clk),.rst_n(rst_n),.valid(ov[1]&&sink_ready[1]),.data(od1),.sof(os[1]),.eol(ol[1]),.eof(oe[1]),.abort(oa[1]),.terminal(terminal[1]),.completed(complete1),.rejected(reject1),.last_crc(crc1),.last_beats(beats1));
    algo_diagnostic_sink u_he(.clk(clk),.rst_n(rst_n),.valid(ov[2]&&sink_ready[2]),.data(od2),.sof(os[2]),.eol(ol[2]),.eof(oe[2]),.abort(oa[2]),.terminal(terminal[2]),.completed(complete2),.rejected(reject2),.last_crc(crc2),.last_beats(beats2));
    (* MARK_DEBUG="true" *) reg [31:0] algo_identity,algo_y8_crc,algo_gau_crc,algo_he_crc;
    (* MARK_DEBUG="true" *) reg [31:0] algo_y8_complete,algo_gau_complete,algo_he_complete;
    (* MARK_DEBUG="true" *) reg [31:0] algo_rejected,algo_overflow,algo_inbeats;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            algo_identity<=32'h414c0101;algo_y8_crc<=0;algo_gau_crc<=0;algo_he_crc<=0;
            algo_y8_complete<=0;algo_gau_complete<=0;algo_he_complete<=0;
            algo_rejected<=0;algo_overflow<=0;algo_inbeats<=0;
        end else if(all_done||!busy) begin
            algo_y8_crc<=crc0;algo_gau_crc<=crc1;algo_he_crc<=crc2;
            algo_y8_complete<=complete0;algo_gau_complete<=complete1;algo_he_complete<=complete2;
            algo_rejected<=rejected;algo_overflow<=overflow;algo_inbeats<=inbeats;
        end
    end
endmodule
