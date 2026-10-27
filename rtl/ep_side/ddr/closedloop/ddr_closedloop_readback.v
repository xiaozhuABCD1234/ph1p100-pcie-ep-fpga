// Debug-only exclusive DHI reader. Writer protects both slots at publication.
// The production pusher remains the only owner when CLOSEDLOOP_EN=0 at top.
// An aborted/timed-out accepted burst is drained before release/restart. If
// that drain cannot finish, retain the slot and lock until the DDR reset.
module ddr_closedloop_readback #(
    parameter [31:0] BASE0=32'h00100000, BASE1=32'h00900000,
    parameter [31:0] TIMEOUT_CYCLES=32'h00200000
)(
    input wire clk, rst,
    input wire pub_valid,
    input wire [31:0] pub_seq, pub_base, pub_len, pub_session,
    input wire [31:0] writer_good, writer_bad,
    input wire abort,
    output reg [1:0] release_slot,
    output wire [3:0] arid,
    output wire [28:0] araddr,
    output wire [7:0] arlen,
    output wire [2:0] arsize,
    output wire [1:0] arburst,
    output wire arvalid, input wire arready,
    input wire [3:0] rid,
    input wire [255:0] rdata,
    input wire [1:0] rresp,
    input wire rlast, rvalid, output wire rready
);
    localparam WAIT=0, START=1, RUN=2, DRAIN=3, LOCK=4;
    reg [2:0] state;
    reg [1:0] pending;
    reg [31:0] seq0,seq1,len0,len1,session0,session1;
    reg current_slot;
    reg [1:0] recovery_slot;
    reg current_recovery,recovery_pending;
    reg [31:0] writer_bad_seen;
    reg [31:0] current_seq,current_base,current_len,current_session;
    reg [8:0] outstanding;
    reg [31:0] drain_wait;
    wire c_busy,c_done,c_magic,c_header,c_payload,c_length,c_arvalid,c_rready;
    wire [7:0] c_error;
    wire [31:0] c_hcrc,c_pcrc,c_words;
    wire [28:0] c_araddr;
    wire [7:0] c_arlen;
    wire c_arready;
    reg ar_pending;
    reg [28:0] araddr_q;
    reg [7:0] arlen_q;
    wire active = (state==START)||(state==RUN);
    // Accept the checker request into an owned skid register. Once offered to
    // DDR it remains valid/stable through timeout/abort until ARREADY or reset.
    assign c_arready=active&&!ar_pending&&(outstanding==0);
    assign arvalid=ar_pending;
    assign araddr=araddr_q;assign arlen=arlen_q;
    assign arid=4'd0;assign arsize=3'd5;assign arburst=2'b01;
    assign rready = active ? c_rready : ((state==DRAIN)&&(outstanding!=0));
    wire ar_fire=arvalid&&arready, r_fire=rvalid&&rready;

    (* MARK_DEBUG="true" *) reg [31:0] cl_identity;
    (* MARK_DEBUG="true" *) reg [31:0] cl_seq,cl_base,cl_len,cl_session;
    (* MARK_DEBUG="true" *) reg [31:0] cl_flags,cl_words,cl_header_crc,cl_payload_crc;
    (* MARK_DEBUG="true" *) reg [31:0] cl_pass_count,cl_fail_count,cl_recovery_count;
    (* MARK_DEBUG="true" *) reg [31:0] cl_writer_good,cl_writer_bad,cl_fault;

    ddr_frame_readback_checker #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) u_checker (
        .clk_dhi(clk),.rst_dhi(rst),.start(state==START),
        .base({32'd0,current_base}),.frame_bytes(current_len),.abort(abort),
        .busy(c_busy),.done(c_done),.magic_ok(c_magic),.hdr_crc_ok(c_header),
        .payload_crc_ok(c_payload),.length_ok(c_length),.err_code(c_error),
        .rd_header_crc32(c_hcrc),.rd_payload_crc32(c_pcrc),.words_read(c_words),
        .smp0(),.smp1(),.smp2(),.smp3(),.smp4(),.smp5(),
        .m_axi_arid(),.m_axi_araddr(c_araddr),.m_axi_arlen(c_arlen),
        .m_axi_arsize(),.m_axi_arburst(),.m_axi_arvalid(c_arvalid),
        .m_axi_arready(c_arready),
        .m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(rresp),
        .m_axi_rlast(rlast),.m_axi_rvalid(rvalid&&active&&(outstanding!=0)),.m_axi_rready(c_rready)
    );
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=WAIT; pending<=0; release_slot<=0; current_slot<=0;
            recovery_slot<=0;current_recovery<=0;recovery_pending<=0;writer_bad_seen<=0;cl_recovery_count<=0;
            seq0<=0;seq1<=0;len0<=0;len1<=0;session0<=0;session1<=0;
            current_seq<=0;current_base<=0;current_len<=0;current_session<=0;
            outstanding<=0;drain_wait<=0;
            ar_pending<=0;araddr_q<=0;arlen_q<=0;
            cl_identity<=32'h434c0101;cl_seq<=0;cl_base<=0;cl_len<=0;cl_session<=0;
            cl_flags<=0;cl_words<=0;cl_header_crc<=0;cl_payload_crc<=0;
            cl_pass_count<=0;cl_fail_count<=0;cl_writer_good<=0;cl_writer_bad<=0;cl_fault<=0;
        end else begin
            release_slot<=0;
            // Tag the first good publication after one or more writer rejections.
            // Count recovery only after that exact tuple passes full DDR checking.
            writer_bad_seen<=writer_bad;
            if(writer_bad!=writer_bad_seen) recovery_pending<=1;
            if(c_arvalid&&c_arready) begin ar_pending<=1;araddr_q<=c_araddr;arlen_q<=c_arlen;end
            else if(ar_fire) ar_pending<=0;
            if(ar_fire) outstanding<={1'b0,arlen}+9'd1;
            else if(r_fire && outstanding!=0) outstanding<=outstanding-1'b1;
            if(pub_valid) begin
                if(pub_base==BASE0 && !pending[0]) begin
                    pending[0]<=1;seq0<=pub_seq;len0<=pub_len;session0<=pub_session;
                    recovery_slot[0]<=recovery_pending||(writer_bad!=writer_bad_seen);recovery_pending<=0;
                end else if(pub_base==BASE1 && !pending[1]) begin
                    pending[1]<=1;seq1<=pub_seq;len1<=pub_len;session1<=pub_session;
                    recovery_slot[1]<=recovery_pending||(writer_bad!=writer_bad_seen);recovery_pending<=0;
                end else begin cl_fault<=32'd2;state<=LOCK; end
            end
            case(state)
                WAIT: if(pending!=0) begin
                    current_slot<=!pending[0];
                    current_recovery<=pending[0]?recovery_slot[0]:recovery_slot[1];
                    current_seq<=pending[0]?seq0:seq1;
                    current_base<=pending[0]?BASE0:BASE1;
                    current_len<=pending[0]?len0:len1;
                    current_session<=pending[0]?session0:session1;
                    state<=START;
                end
                START: state<=RUN;
                RUN: if(c_done && !c_busy) begin
                    cl_seq<=current_seq;cl_base<=current_base;cl_len<=current_len;cl_session<=current_session;
                    cl_flags<={1'b1,15'd0,c_error,4'd0,c_length,c_payload,c_header,c_magic};
                    cl_words<=c_words;cl_header_crc<=c_hcrc;cl_payload_crc<=c_pcrc;
                    cl_writer_good<=writer_good;cl_writer_bad<=writer_bad;
                    if(c_error==0 && c_magic&&c_header&&c_payload&&c_length) begin
                        cl_pass_count<=cl_pass_count+1'b1;
                        if(current_recovery) cl_recovery_count<=cl_recovery_count+1'b1;
                    end else begin
                        cl_fail_count<=cl_fail_count+1'b1;
                        if(current_recovery) recovery_pending<=1;
                    end
                    drain_wait<=0;state<=DRAIN;
                end
                DRAIN: if(outstanding==0 && !ar_pending) begin
                    release_slot<=current_slot?2'b10:2'b01;
                    pending[current_slot]<=0;recovery_slot[current_slot]<=0;state<=WAIT;
                end else if(r_fire||ar_fire) drain_wait<=0;
                else if(drain_wait>=TIMEOUT_CYCLES) begin cl_fault<=1;state<=LOCK; end
                else drain_wait<=drain_wait+1'b1;
                LOCK: begin end
                default: state<=LOCK;
            endcase
            if(pub_valid && !((pub_base==BASE0&&!pending[0])||(pub_base==BASE1&&!pending[1]))) begin
                cl_fault<=32'd2;state<=LOCK;
            end
        end
    end
endmodule
