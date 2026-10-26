// Isolated G0/G1 candidate. One shared DHI clock, one AXI beat outstanding.
// RAW ownership is held until rel handshake; a missing R locks until DDR reset.
module dual_aplus_scheduler #(
 parameter integer W=1920,H=1080,CMP_CAP=8388608,TIMEOUT=20000
)(
 input wire clk,rst_n,input wire [31:0] current_epoch,
 input wire prep_en,pred_en,abort,input wire sink_enable,
 input wire a_desc_valid,output wire a_desc_ready,
 input wire a_desc_camera_id,a_desc_slot_id,
 input wire [31:0] a_desc_epoch,a_desc_session,a_desc_capture_seq,
 input wire [31:0] a_desc_base,a_desc_dma_bytes,a_desc_raw_bytes,
 input wire [15:0] a_desc_width,a_desc_height,input wire [1:0] a_desc_bayer_phase,
 input wire b_desc_valid,output wire b_desc_ready,
 input wire b_desc_camera_id,b_desc_slot_id,
 input wire [31:0] b_desc_epoch,b_desc_session,b_desc_capture_seq,
 input wire [31:0] b_desc_base,b_desc_dma_bytes,b_desc_raw_bytes,
 input wire [15:0] b_desc_width,b_desc_height,input wire [1:0] b_desc_bayer_phase,
 output reg rel_valid,input wire rel_ready,
 output reg rel_camera_id,rel_slot_id,
 output reg [31:0] rel_epoch,rel_session,rel_capture_seq,output reg [2:0] rel_status,
 output reg arvalid,input wire arready,output reg [28:0] araddr,
 output wire [3:0] arid,output wire [7:0] arlen,output wire [2:0] arsize,output wire [1:0] arburst,
 input wire rvalid,output wire rready,input wire [255:0] rdata,
 input wire [3:0] rid,input wire [1:0] rresp,input wire rlast,
 output wire cmp_valid,input wire cmp_ready,output wire cmp_slot,
 output wire cmp_camera_id,cmp_source_slot_id,output wire [31:0] cmp_epoch,cmp_session,cmp_capture_seq,
 output wire [31:0] cmp_raw_len,cmp_xform_len,cmp_stream_len,cmp_raw_crc,cmp_xform_crc,cmp_stream_crc,
 output wire cmp_prep,cmp_pred,input wire cmp_read_slot,input wire [31:0] cmp_read_addr,output wire [7:0] cmp_read_data,
 input wire ack_valid,ack_slot,ack_camera_id,ack_source_slot_id,
 input wire [31:0] ack_epoch,ack_session,ack_capture_seq,
 output reg locked,output reg [31:0] reject_acks,accepted,completed,failed,ar_words,groups,cycles,queue_peak,
 output reg select_valid,output reg select_camera,output reg [31:0] select_seq
);
 localparam integer RAW=W*H*5/4,DMA=((128+RAW+4095)/4096)*4096;
 localparam integer WORST=RAW+5*((H+1)/2)+6;
 localparam [3:0] IDLE=0,HAR=1,HR=2,HCHECK=3,DATA=4,RELEASE=5,LOCK=6;
 reg [3:0] state;
 reg [3:0] owned,queued;
 reg qcam[0:3];reg qslot[0:3];reg [31:0] qe[0:3],qs[0:3],qq[0:3],qb[0:3],qd[0:3],qr[0:3];
 reg [15:0] qw[0:3],qh[0:3];reg [1:0] qp[0:3];
 reg rr;reg [1:0] active;reg active_cmp,mode_prep,mode_pred;
 reg [1:0] cs[0:1]; // FREE, WRITING, READY, READING
 reg mc[0:1],mslot[0:1],mprep[0:1],mpred[0:1];
 reg [31:0] me[0:1],ms[0:1],mq[0:1],mraw[0:1],mxf[0:1],mlen[0:1],mrc[0:1],mxc[0:1],msc[0:1];
 reg [7:0] cmp0[0:CMP_CAP-1],cmp1[0:CMP_CAP-1];
 reg [31:0] sink_count,sink_crc;
 reg cmp_offer_valid,cmp_offer_slot;
 wire cmp_sel=cmp_offer_slot;
 assign cmp_valid=cmp_offer_valid;assign cmp_slot=cmp_sel;
 assign cmp_camera_id=mc[cmp_sel];assign cmp_source_slot_id=mslot[cmp_sel];
 assign cmp_epoch=me[cmp_sel];assign cmp_session=ms[cmp_sel];assign cmp_capture_seq=mq[cmp_sel];
 assign cmp_raw_len=mraw[cmp_sel];assign cmp_xform_len=mxf[cmp_sel];assign cmp_stream_len=mlen[cmp_sel];
 assign cmp_raw_crc=mrc[cmp_sel];assign cmp_xform_crc=mxc[cmp_sel];assign cmp_stream_crc=msc[cmp_sel];
 assign cmp_prep=mprep[cmp_sel];assign cmp_pred=mpred[cmp_sel];
 assign cmp_read_data=(cmp_read_addr<CMP_CAP)?(cmp_read_slot?cmp1[cmp_read_addr]:cmp0[cmp_read_addr]):8'd0;
 wire [1:0] ai={1'b0,a_desc_slot_id},bi={1'b1,b_desc_slot_id};
 assign a_desc_ready=!owned[ai]&&!locked;assign b_desc_ready=!owned[bi]&&!locked;
 reg [7:0] hdr[0:127];reg [2:0] hword;reg [31:0] hcrc,pcrc,expected_crc;
 reg [511:0] fifo;reg [6:0] fcount;
 reg [31:0] offset,issued_offset,group_count,wait_cycles;
 reg outstanding,bad,read_done,core_abort,codec_reset;
 wire [39:0] in_pix=fifo[39:0];
 wire in_valid=(state==DATA)&&!bad&&(fcount>=5)&&(group_count<RAW/5);
 wire in_sof=(group_count==0);wire in_ready;
 wire [31:0] out_data,st_raw_len,st_xform_len,st_stream_len,st_raw_crc,st_xform_crc,st_stream_crc;
 wire [3:0] out_keep;wire out_valid,out_last,frame_commit,frame_abort,core_busy;
 wire out_ready=sink_enable&&!bad&&(state==DATA)&&(!out_last||read_done);
 a1_frame_top #(.W(W),.H(H)) codec(.clk(clk),.rst_n(rst_n&&!codec_reset),.in_pix(in_pix),.in_valid(in_valid),.in_ready(in_ready),.in_sof(in_sof),
 .prep_en(mode_prep),.pred_en(mode_pred),.abort(core_abort),.out_data(out_data),.out_valid(out_valid),.out_ready(out_ready),.out_keep(out_keep),.out_last(out_last),
 .frame_commit(frame_commit),.frame_abort(frame_abort),.st_raw_len(st_raw_len),.st_xform_len(st_xform_len),.st_stream_len(st_stream_len),
 .st_raw_crc(st_raw_crc),.st_xform_crc(st_xform_crc),.st_stream_crc(st_stream_crc),.st_blocks(),.st_stall_cycles(),.st_busy(core_busy));
 assign arid=4'd3;assign arlen=0;assign arsize=5;assign arburst=1;
 assign rready=outstanding&&(state!=LOCK);
 function [31:0] crcbyte(input [31:0] c,input [7:0] d);
 integer n;reg [31:0] x;begin x=c^d;for(n=0;n<8;n=n+1)x=x[0]?((x>>1)^32'hedb88320):(x>>1);crcbyte=x;end endfunction
 function [31:0] h32(input integer p);begin h32={hdr[p+3],hdr[p+2],hdr[p+1],hdr[p]};end endfunction
 function [31:0] baseof(input c,input s);begin baseof=32'h00100000+(c?32'h01000000:0)+(s?32'h00800000:0);end endfunction
 integer i,k,n,chosen,ca,cb,np;reg [511:0] tf;reg [6:0] tc;reg [31:0] cr,sc,nb;reg hb;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 cmp_offer_valid<=0;cmp_offer_slot<=0;state<=IDLE;owned<=0;queued<=0;rr<=0;active<=0;active_cmp<=0;mode_prep<=0;mode_pred<=0;
 rel_valid<=0;rel_camera_id<=0;rel_slot_id<=0;rel_epoch<=0;rel_session<=0;rel_capture_seq<=0;rel_status<=0;
 arvalid<=0;araddr<=0;outstanding<=0;offset<=0;issued_offset<=0;hword<=0;hcrc<=32'hffffffff;pcrc<=32'hffffffff;expected_crc<=0;
 fifo<=0;fcount<=0;group_count<=0;wait_cycles<=0;bad<=0;read_done<=0;core_abort<=0;codec_reset<=1;sink_count<=0;sink_crc<=32'hffffffff;
 locked<=0;reject_acks<=0;accepted<=0;completed<=0;failed<=0;ar_words<=0;groups<=0;cycles<=0;queue_peak<=0;select_valid<=0;select_camera<=0;select_seq<=0;
 for(i=0;i<2;i=i+1)begin cs[i]<=0;mc[i]<=0;mslot[i]<=0;me[i]<=0;ms[i]<=0;mq[i]<=0;mraw[i]<=0;mxf[i]<=0;mlen[i]<=0;mrc[i]<=0;mxc[i]<=0;msc[i]<=0;mprep[i]<=0;mpred[i]<=0;end
 end else begin
 cycles<=cycles+1;core_abort<=0;codec_reset<=0;select_valid<=0;
 np=0;for(i=0;i<4;i=i+1)np=np+queued[i];if(np>queue_peak)queue_peak<=np;
 if(a_desc_valid&&a_desc_ready)begin owned[ai]<=1;queued[ai]<=1;qcam[ai]<=a_desc_camera_id;qslot[ai]<=a_desc_slot_id;qe[ai]<=a_desc_epoch;qs[ai]<=a_desc_session;qq[ai]<=a_desc_capture_seq;qb[ai]<=a_desc_base;qd[ai]<=a_desc_dma_bytes;qr[ai]<=a_desc_raw_bytes;qw[ai]<=a_desc_width;qh[ai]<=a_desc_height;qp[ai]<=a_desc_bayer_phase;end
 if(b_desc_valid&&b_desc_ready)begin owned[bi]<=1;queued[bi]<=1;qcam[bi]<=b_desc_camera_id;qslot[bi]<=b_desc_slot_id;qe[bi]<=b_desc_epoch;qs[bi]<=b_desc_session;qq[bi]<=b_desc_capture_seq;qb[bi]<=b_desc_base;qd[bi]<=b_desc_dma_bytes;qr[bi]<=b_desc_raw_bytes;qw[bi]<=b_desc_width;qh[bi]<=b_desc_height;qp[bi]<=b_desc_bayer_phase;end
 // An offer is a reservation: its slot and metadata stay fixed until take.
 if(cmp_valid&&cmp_ready)cs[cmp_sel]<=3;
 if(!cmp_offer_valid||cmp_ready)begin
   if(cs[0]==2&&!(cmp_offer_valid&&cmp_ready&&cmp_offer_slot==0))begin
     cmp_offer_valid<=1;cmp_offer_slot<=0;
   end else if(cs[1]==2&&!(cmp_offer_valid&&cmp_ready&&cmp_offer_slot==1))begin
     cmp_offer_valid<=1;cmp_offer_slot<=1;
   end else cmp_offer_valid<=0;
 end
 if(ack_valid)begin
 if(cs[ack_slot]==3&&mc[ack_slot]==ack_camera_id&&mslot[ack_slot]==ack_source_slot_id&&me[ack_slot]==ack_epoch&&ms[ack_slot]==ack_session&&mq[ack_slot]==ack_capture_seq)cs[ack_slot]<=0;
 else reject_acks<=reject_acks+1;
 end
 case(state)
 IDLE:begin
 ca=queued[0]?0:(queued[1]?1:-1);cb=queued[2]?2:(queued[3]?3:-1);chosen=-1;
 if(ca>=0&&cb>=0)chosen=rr?cb:ca;else if(ca>=0)chosen=ca;else if(cb>=0)chosen=cb;
 if(chosen>=0&&(cs[0]==0||cs[1]==0)&&!core_busy&&!codec_reset)begin
 active<=chosen;active_cmp<=(cs[0]!=0);cs[(cs[0]!=0)]<=1;queued[chosen]<=0;rr<=!chosen[1];
 mode_prep<=prep_en;mode_pred<=pred_en;bad<=0;read_done<=0;fifo<=0;fcount<=0;group_count<=0;sink_count<=0;sink_crc<=32'hffffffff;
 hword<=0;hcrc<=32'hffffffff;pcrc<=32'hffffffff;offset<=0;wait_cycles<=0;state<=HAR;accepted<=accepted+1;
 select_valid<=1;select_camera<=chosen[1];select_seq<=qq[chosen];
 rel_camera_id<=qcam[chosen];rel_slot_id<=qslot[chosen];rel_epoch<=qe[chosen];rel_session<=qs[chosen];rel_capture_seq<=qq[chosen];
 if(qcam[chosen]!=chosen[1]||qe[chosen]!=current_epoch||qb[chosen]!=baseof(chosen[1],qslot[chosen])||qb[chosen][31:29]!=0||
 {1'b0,qb[chosen]}+qd[chosen]>33'h020000000||qd[chosen]!=DMA||qd[chosen]>8388608||qr[chosen]!=RAW||qw[chosen]!=W||qh[chosen]!=H||
 W<4||W%4!=0||H<2||2*(W*5/4)>4800||WORST>CMP_CAP||(prep_en&&qp[chosen]!=0)||(pred_en&&!prep_en))begin
 rel_status<=2;state<=RELEASE;end
 end end
 HAR:begin
 if(!arvalid)begin arvalid<=1;araddr<=qb[active][28:0]+hword*32;end
 if(arvalid&&arready)begin arvalid<=0;outstanding<=1;state<=HR;wait_cycles<=0;ar_words<=ar_words+1;end
 else if(wait_cycles>=TIMEOUT)begin state<=LOCK;locked<=1;end else wait_cycles<=wait_cycles+1;
 if(abort)bad<=1;
 end
 HR:begin
 if(rvalid&&rready)begin
 outstanding<=0;wait_cycles<=0;cr=hcrc;
 for(k=0;k<32;k=k+1)begin hdr[hword*32+k]<=rdata[k*8+:8];cr=crcbyte(cr,((hword*32+k>=88)&&(hword*32+k<92))?8'd0:rdata[k*8+:8]);end
 hcrc<=cr;
 if(!rlast||rid!=3)begin state<=LOCK;locked<=1;end
 else if(rresp!=0||bad||abort)begin rel_status<=1;state<=RELEASE;end
 else if(hword==3)state<=HCHECK;else begin hword<=hword+1;state<=HAR;end
 end else if(wait_cycles>=TIMEOUT)begin state<=LOCK;locked<=1;end else wait_cycles<=wait_cycles+1;
 if(abort)bad<=1;
 end
 HCHECK:begin
 hb=0;for(k=92;k<128;k=k+1)if(hdr[k]!=0)hb=1;
 if(h32(0)!=32'h46303152||h32(4)!=1||{hdr[9],hdr[8]}!=128||hdr[10]!=qcam[active]||hdr[11]!=0||h32(12)!=0||
 h32(16)!=qs[active]||h32(20)!=qq[active]||{hdr[29],hdr[28]}!=W||{hdr[31],hdr[30]}!=H||h32(32)!=W*5/4||
 hdr[40]!={6'd0,qp[active]}||hdr[41]!=0||hdr[42]!=10||hdr[43]!=0||h32(44)!=RAW||h32(48)!=RAW||h32(52)==0||
 h32(76)&32'hfffffffd||h32(80)!=h32(84)||h32(88)!=~hcrc||hb||abort||bad)begin rel_status<=1;state<=RELEASE;end
 else begin expected_crc<=h32(80);offset<=128;state<=DATA;end
 end
 DATA:begin
 tf=fifo;tc=fcount;sc=sink_crc;nb=sink_count;
 if(in_valid&&in_ready)begin tf=tf>>40;tc=tc-5;group_count<=group_count+1;groups<=groups+1;end
 if(!arvalid&&!outstanding&&!bad&&!abort&&!(frame_abort&&group_count!=0)&&offset<DMA&&tc<=32)begin arvalid<=1;araddr<=qb[active][28:0]+offset;issued_offset<=offset;end
 if(arvalid&&arready)begin arvalid<=0;outstanding<=1;offset<=offset+32;wait_cycles<=0;ar_words<=ar_words+1;end
 if(rvalid&&rready)begin
 outstanding<=0;wait_cycles<=0;cr=pcrc;hb=0;
 for(k=0;k<32;k=k+1)begin
 if(issued_offset+k<128+RAW)begin
 if(!bad&&!abort)begin tf[tc*8+:8]=rdata[k*8+:8];tc=tc+1;end
 cr=crcbyte(cr,rdata[k*8+:8]);
 end else if(rdata[k*8+:8]!=0)hb=1;
 end
 pcrc<=cr;
 if(!rlast||rid!=3)begin state<=LOCK;locked<=1;core_abort<=1;end
 if(rresp!=0||hb)bad<=1;
 end
 if((arvalid&&!arready)||(outstanding&&!rvalid))begin
 if(wait_cycles>=TIMEOUT)begin state<=LOCK;locked<=1;core_abort<=1;end else wait_cycles<=wait_cycles+1;
 end
 if(offset==DMA&&!outstanding&&!arvalid&&!bad)begin
 if(~pcrc!=expected_crc)bad<=1;else read_done<=1;
 end
 if(out_valid&&out_ready)begin
 for(k=0;k<4;k=k+1)if(out_keep[k])begin
 if(nb<CMP_CAP)begin if(active_cmp)cmp1[nb]<=out_data[k*8+:8];else cmp0[nb]<=out_data[k*8+:8];end
 else bad<=1;
 nb=nb+1;sc=crcbyte(sc,out_data[k*8+:8]);
 end
 sink_count<=nb;sink_crc<=sc;
 end
 if(abort||(frame_abort&&group_count!=0))bad<=1;
 if(bad||abort||(frame_abort&&group_count!=0))begin
 core_abort<=1;tf=0;tc=0;
 if(!arvalid&&!outstanding)begin rel_status<=1;state<=RELEASE;end
 end
 if(frame_commit&&!bad&&!abort)begin
 if(!read_done||group_count!=RAW/5||st_raw_len!=RAW||st_raw_crc!=expected_crc||st_stream_len!=nb||st_stream_crc!=~sc)begin rel_status<=1;end
 else begin
 cs[active_cmp]<=2;mc[active_cmp]<=qcam[active];mslot[active_cmp]<=qslot[active];me[active_cmp]<=qe[active];ms[active_cmp]<=qs[active];mq[active_cmp]<=qq[active];
 mraw[active_cmp]<=st_raw_len;mxf[active_cmp]<=st_xform_len;mlen[active_cmp]<=st_stream_len;mrc[active_cmp]<=st_raw_crc;mxc[active_cmp]<=st_xform_crc;msc[active_cmp]<=st_stream_crc;mprep[active_cmp]<=mode_prep;mpred[active_cmp]<=mode_pred;rel_status<=0;
 end
 state<=RELEASE;
 end
 fifo<=tf;fcount<=tc;
 end
 RELEASE:begin
 if(rel_status!=0)codec_reset<=1;
 rel_valid<=1;
 if(rel_valid&&rel_ready)begin
 owned[active]<=0;rel_valid<=0;
 if(rel_status!=0)begin cs[active_cmp]<=0;failed<=failed+1;core_abort<=1;end else completed<=completed+1;
 state<=IDLE;
 end
 end
 LOCK:begin locked<=1;core_abort<=1;codec_reset<=1;end
 default:begin state<=LOCK;locked<=1;end
 endcase
 end end
endmodule
