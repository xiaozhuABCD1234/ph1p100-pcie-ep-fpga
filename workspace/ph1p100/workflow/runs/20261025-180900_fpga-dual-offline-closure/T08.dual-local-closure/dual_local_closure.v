// Four pulse mailboxes and one exclusive native AXI reader. DHI clock only.
module dual_local_closure #(
 parameter integer W=1920,H=1080,PHASE=0,DEFAULT_MODE=1,
 parameter [31:0] TIMEOUT_CYCLES=2097152
)(input wire clk,rst,input wire [31:0] epoch,input wire [1:0] requested_mode,
 input wire abort,
 input wire a_pub_valid,input wire [31:0] a_pub_seq,a_pub_base,a_pub_len,a_pub_session,
 input wire b_pub_valid,input wire [31:0] b_pub_seq,b_pub_base,b_pub_len,b_pub_session,
 output reg [1:0] a_release,b_release,
 output wire a_desc_valid,input wire a_desc_ready,
 output wire a_desc_camera_id,
 output wire a_desc_slot_id,
 output wire [31:0] a_desc_epoch,
 output wire [31:0] a_desc_session,
 output wire [31:0] a_desc_capture_seq,
 output wire [31:0] a_desc_base,
 output wire [31:0] a_desc_dma_bytes,
 output wire [31:0] a_desc_raw_bytes,
 output wire [15:0] a_desc_width,
 output wire [15:0] a_desc_height,
 output wire [1:0] a_desc_bayer_phase,
 output wire b_desc_valid,input wire b_desc_ready,
 output wire b_desc_camera_id,
 output wire b_desc_slot_id,
 output wire [31:0] b_desc_epoch,
 output wire [31:0] b_desc_session,
 output wire [31:0] b_desc_capture_seq,
 output wire [31:0] b_desc_base,
 output wire [31:0] b_desc_dma_bytes,
 output wire [31:0] b_desc_raw_bytes,
 output wire [15:0] b_desc_width,
 output wire [15:0] b_desc_height,
 output wire [1:0] b_desc_bayer_phase,
 input wire rel_valid,output wire rel_ready,input wire rel_camera_id,rel_slot_id,
 input wire [31:0] rel_epoch,rel_session,rel_capture_seq,input wire [2:0] rel_status,
 output reg [31:0] pass_count,fail_count,fault,reject_count,
 output reg [3:0] held,output reg [1:0] active_mode,
 output wire [3:0] arid,output wire [28:0] araddr,output wire [7:0] arlen,
 output wire [2:0] arsize,output wire [1:0] arburst,output wire arvalid,input wire arready,
 input wire [3:0] rid,input wire [255:0] rdata,input wire [1:0] rresp,
 input wire rlast,rvalid,output wire rready,
 input wire [3:0] ext_arid,input wire [28:0] ext_araddr,input wire [7:0] ext_arlen,
 input wire [2:0] ext_arsize,input wire [1:0] ext_arburst,input wire ext_arvalid,output wire ext_arready,
 output wire [3:0] ext_rid,output wire [255:0] ext_rdata,output wire [1:0] ext_rresp,
 output wire ext_rlast,ext_rvalid,input wire ext_rready);
 localparam [31:0] RAW_BYTES=W*H*5/4,DMA_BYTES=((128+W*H*5/4+4095)/4096)*4096;
 localparam [15:0] WIDTH=W,HEIGHT=H;localparam [1:0] BAYER_PHASE=PHASE;
 localparam WAIT=0,START=1,RUN=2,DRAIN=3,LOCK=4;
 reg [2:0] state;reg [3:0] sent;reg last_camera;
 reg [31:0] q_seq[0:3],q_sess[0:3],q_epoch[0:3],q_base[0:3],q_len[0:3],ext_bytes[0:3];
 reg [1:0] current;reg [2:0] current_status;
 reg ar_pending;reg [28:0] araddr_q;reg [7:0] arlen_q;reg [3:0] arid_q;
 reg [8:0] outstanding;reg [31:0] drain_wait;reg protocol_bad;reg [1:0] mode_seen;
 reg [1:0] ext_owner;
 wire active=(state==START)||(state==RUN);
 wire c_busy,c_done,c_magic,c_header,c_payload,c_length,c_arvalid,c_rready;
 wire [7:0] c_error,c_arlen;wire [31:0] c_hcrc,c_pcrc,c_words;wire [28:0] c_araddr;
 wire c_arready=active&&!ar_pending&&(outstanding==0);
 assign arvalid=ar_pending;assign araddr=araddr_q;assign arlen=arlen_q;assign arid=arid_q;
 assign arsize=3'd5;assign arburst=2'b01;
 assign rready=active_mode==2 ? ((outstanding!=0)&&ext_rready&&!fault) :
               active ? c_rready : ((state==DRAIN)&&(outstanding!=0));
 wire ar_fire=arvalid&&arready,r_fire=rvalid&&rready;
 wire [3:0] available=held & ~sent;
 wire have_a=|available[1:0],have_b=|available[3:2];
 wire select_camera=have_a&&have_b ? !last_camera : have_b;
 wire [1:0] selected=select_camera ? (available[2]?2'd2:2'd3) : (available[0]?2'd0:2'd1);
 wire [1:0] release_index={rel_camera_id,rel_slot_id};
 assign rel_ready=active_mode==2;
 wire [1:0] ai=held[0]&&!sent[0]?2'd0:2'd1;
assign a_desc_valid=active_mode==2 && !fault && ((held[0]&&!sent[0])||(held[1]&&!sent[1]));
assign a_desc_camera_id=1'b0;
assign a_desc_slot_id=ai[0];
assign a_desc_epoch=q_epoch[ai];
assign a_desc_session=q_sess[ai];
assign a_desc_capture_seq=q_seq[ai];
assign a_desc_base=q_base[ai];
assign a_desc_dma_bytes=q_len[ai];
assign a_desc_raw_bytes=RAW_BYTES;
assign a_desc_width=WIDTH;
assign a_desc_height=HEIGHT;
assign a_desc_bayer_phase=BAYER_PHASE;
wire [1:0] bi=held[2]&&!sent[2]?2'd2:2'd3;
assign b_desc_valid=active_mode==2 && !fault && ((held[2]&&!sent[2])||(held[3]&&!sent[3]));
assign b_desc_camera_id=1'b1;
assign b_desc_slot_id=bi[0];
assign b_desc_epoch=q_epoch[bi];
assign b_desc_session=q_sess[bi];
assign b_desc_capture_seq=q_seq[bi];
assign b_desc_base=q_base[bi];
assign b_desc_dma_bytes=q_len[bi];
assign b_desc_raw_bytes=RAW_BYTES;
assign b_desc_width=WIDTH;
assign b_desc_height=HEIGHT;
assign b_desc_bayer_phase=BAYER_PHASE;

 wire [32:0] ext_end={4'd0,ext_araddr}+(({25'd0,ext_arlen}+1)<<5);
 reg ext_valid_range;reg [1:0] ext_index;integer k;
 always @* begin
  ext_valid_range=0;ext_index=0;
  for(integer n=0;n<4;n=n+1)
   if(held[n]&&sent[n]&&ext_araddr>=q_base[n]&&ext_end<={1'b0,q_base[n]}+q_len[n]) begin ext_valid_range=1;ext_index=n;end
 end
 assign ext_arready=active_mode==2&&!fault&&!ar_pending&&outstanding==0&&ext_valid_range&&
   ext_arid==0&&ext_arsize==5&&ext_arburst==1&&ext_arlen<128&&ext_araddr[4:0]==0&&
   ({1'b0,ext_araddr[11:0]}+(({5'd0,ext_arlen}+1)<<5)<=4096);
 assign ext_rid=rid;assign ext_rdata=rdata;assign ext_rresp=rresp;assign ext_rlast=rlast;
 assign ext_rvalid=active_mode==2&&!fault&&outstanding!=0&&rvalid;
 ddr_frame_readback_checker #(.TIMEOUT_CYCLES(TIMEOUT_CYCLES),.MAX_FRAME_BYTES(8388608)) u_checker(
 .clk_dhi(clk),.rst_dhi(rst),.start(state==START),.base({32'd0,q_base[current]}),.frame_bytes(q_len[current]),.abort(abort),
 .expected_check(1'b1),.expected_camera(current[1]),.expected_session(q_sess[current]),.expected_seq(q_seq[current]),
 .expected_raw(RAW_BYTES),.expected_width(WIDTH),.expected_height(HEIGHT),.expected_phase(BAYER_PHASE),
 .busy(c_busy),.done(c_done),.magic_ok(c_magic),.hdr_crc_ok(c_header),.payload_crc_ok(c_payload),.length_ok(c_length),
 .err_code(c_error),.rd_header_crc32(c_hcrc),.rd_payload_crc32(c_pcrc),.words_read(c_words),
 .smp0(),.smp1(),.smp2(),.smp3(),.smp4(),.smp5(),
 .m_axi_arid(),.m_axi_araddr(c_araddr),.m_axi_arlen(c_arlen),.m_axi_arsize(),.m_axi_arburst(),
 .m_axi_arvalid(c_arvalid),.m_axi_arready(c_arready),.m_axi_rid(rid),.m_axi_rdata(rdata),.m_axi_rresp(rresp),
 .m_axi_rlast(rlast),.m_axi_rvalid(rvalid&&active&&(outstanding!=0)),.m_axi_rready(c_rready));
 function [31:0] slot_base(input [1:0] index);
  case(index) 0:slot_base=32'h00100000;1:slot_base=32'h00900000;2:slot_base=32'h01100000;3:slot_base=32'h01900000;endcase
 endfunction
 task capture(input bit camera,input [31:0] seq,base,len,session);
  reg [1:0] idx;
  begin
   idx={camera,(base==slot_base({camera,1'b1}))};
   if((base!=slot_base({camera,1'b0})&&base!=slot_base({camera,1'b1})) || held[idx] ||
      len!=DMA_BYTES || len>8388608 || base[31:29]!=0 || {1'b0,base}+len>33'h020000000) begin fault<=2;state<=LOCK;end
   else begin held[idx]<=1;sent[idx]<=0;q_seq[idx]<=seq;q_sess[idx]<=session;q_epoch[idx]<=epoch;q_base[idx]<=base;q_len[idx]<=len;ext_bytes[idx]<=0;end
  end
 endtask
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   state<=WAIT;held<=0;sent<=0;last_camera<=1;current<=0;current_status<=0;ar_pending<=0;
   araddr_q<=0;arlen_q<=0;arid_q<=0;outstanding<=0;drain_wait<=0;protocol_bad<=0;
   active_mode<=DEFAULT_MODE;mode_seen<=DEFAULT_MODE;ext_owner<=0;a_release<=0;b_release<=0;
   pass_count<=0;fail_count<=0;fault<=0;reject_count<=0;
   for(k=0;k<4;k=k+1) begin q_seq[k]<=0;q_sess[k]<=0;q_epoch[k]<=0;q_base[k]<=0;q_len[k]<=0;ext_bytes[k]<=0;end
  end else begin
   a_release<=0;b_release<=0;
   if(requested_mode!==mode_seen && (^requested_mode)!==1'bx) begin
    mode_seen<=requested_mode;
    if(held==0 && !ar_pending && outstanding==0 && state==WAIT) active_mode<=requested_mode;
    else reject_count<=reject_count+1;
   end
   if(a_pub_valid) capture(0,a_pub_seq,a_pub_base,a_pub_len,a_pub_session);
   if(b_pub_valid) capture(1,b_pub_seq,b_pub_base,b_pub_len,b_pub_session);
   if(c_arvalid&&c_arready) begin ar_pending<=1;araddr_q<=c_araddr;arlen_q<=c_arlen;arid_q<=0;end
   else if(ext_arvalid&&ext_arready) begin ar_pending<=1;araddr_q<=ext_araddr;arlen_q<=ext_arlen;arid_q<=ext_arid;ext_owner<=ext_index;end
   else if(ar_fire) ar_pending<=0;
   if(ar_fire) outstanding<={1'b0,arlen}+1'b1;
   else if(r_fire&&outstanding!=0) outstanding<=outstanding-1'b1;
   if(r_fire && (rid!=arid_q || rresp!=0 || rlast!=(outstanding==1))) protocol_bad<=1;
   if(active_mode==2) begin
    if(a_desc_valid&&a_desc_ready) sent[ai]<=1;
    if(b_desc_valid&&b_desc_ready) sent[bi]<=1;
    if(r_fire) ext_bytes[ext_owner]<=ext_bytes[ext_owner]+32;
    if(rel_valid&&rel_ready) begin
     if(held[release_index]&&sent[release_index]&&rel_epoch==q_epoch[release_index]&&
        rel_session==q_sess[release_index]&&rel_capture_seq==q_seq[release_index]&&rel_status<=2&&
        !ar_pending&&outstanding==0&&
        ((rel_status==0&&ext_bytes[release_index]==q_len[release_index]&&!protocol_bad)||
         (rel_status==1)||(rel_status==2&&ext_bytes[release_index]==0))) begin
      held[release_index]<=0;sent[release_index]<=0;
      if(rel_camera_id) b_release<=rel_slot_id?2:1;else a_release<=rel_slot_id?2:1;
     end else reject_count<=reject_count+1;
    end
    if((ar_pending||outstanding!=0) && !(ar_fire||r_fire)) begin
     if(drain_wait>=TIMEOUT_CYCLES) begin fault<=1;state<=LOCK;end else drain_wait<=drain_wait+1;
    end else drain_wait<=0;
   end else if(active_mode==1) case(state)
    WAIT: if(available!=0 && !fault) begin
     current<=selected;sent[selected]<=1;last_camera<=select_camera;protocol_bad<=0;state<=START;
    end
    START: state<=RUN;
    RUN: if(c_done&&!c_busy) begin
     current_status<=(c_error==0 && c_magic&&c_header&&c_payload&&c_length&&!protocol_bad)?0:1;
     drain_wait<=0;state<=DRAIN;
    end
    DRAIN: if(outstanding==0&&!ar_pending) begin
     held[current]<=0;sent[current]<=0;
     if(current[1]) b_release<=current[0]?2:1;else a_release<=current[0]?2:1;
     if(current_status==0) pass_count<=pass_count+1;else fail_count<=fail_count+1;
     state<=WAIT;
    end else if(ar_fire||r_fire) drain_wait<=0;
    else if(drain_wait>=TIMEOUT_CYCLES) begin fault<=1;state<=LOCK;end
    else drain_wait<=drain_wait+1;
    LOCK: begin end
    default: begin fault<=3;state<=LOCK;end
   endcase
   // Invalid mode is fail closed: writers retain every complete frame.
  end
 end
 initial begin
  if(W<4 || W%4!=0 || H<2 || DMA_BYTES>8388608) $error("invalid dual local geometry/capacity");
 end
endmodule

