`timescale 1ns/1ps
module tb_dual_old #(parameter integer W=64,H=8,CASE=0,PREP=0,MUT=0,CAP=W*H*5/4+5*((H+1)/2)+134);
localparam integer RAW=W*H*5/4,DMA=((RAW+128+4095)/4096)*4096;
reg clk=0;always #5 clk=~clk;
reg rst_n=0;reg [31:0] current_epoch=1;reg prep_en=PREP,pred_en=PREP,abort=0,sink_enable=1;
reg a_desc_valid=0;wire a_desc_ready;reg a_desc_camera_id=0,a_desc_slot_id=0;
reg [31:0] a_desc_epoch=0;
reg [31:0] a_desc_session=0;
reg [31:0] a_desc_capture_seq=0;
reg [31:0] a_desc_base=0;
reg [31:0] a_desc_dma_bytes=0;
reg [31:0] a_desc_raw_bytes=0;
wire [15:0] a_desc_width=W,a_desc_height=H;reg [1:0] a_desc_bayer_phase=3;
reg b_desc_valid=0;wire b_desc_ready;reg b_desc_camera_id=1,b_desc_slot_id=0;
reg [31:0] b_desc_epoch=0;
reg [31:0] b_desc_session=0;
reg [31:0] b_desc_capture_seq=0;
reg [31:0] b_desc_base=0;
reg [31:0] b_desc_dma_bytes=0;
reg [31:0] b_desc_raw_bytes=0;
wire [15:0] b_desc_width=W,b_desc_height=H;reg [1:0] b_desc_bayer_phase=3;
wire rel_valid,rel_camera_id,rel_slot_id;reg rel_ready=1;wire [31:0] rel_epoch,rel_session,rel_capture_seq;wire [2:0] rel_status;
wire arvalid;wire [28:0] araddr;wire [3:0] arid;wire [7:0] arlen;wire [2:0] arsize;wire [1:0] arburst;wire arready;
reg rvalid=0;wire rready;reg [255:0] rdata=0;reg [3:0] rid=3;reg [1:0] rresp=0;reg rlast=1;
wire cmp_valid,cmp_slot,cmp_camera_id,cmp_source_slot_id,cmp_prep,cmp_pred;reg cmp_ready=1;
wire [31:0] cmp_epoch,cmp_session,cmp_capture_seq,cmp_raw_len,cmp_xform_len,cmp_stream_len,cmp_raw_crc,cmp_xform_crc,cmp_stream_crc;
reg cmp_read_slot=0;reg [31:0] cmp_read_addr=0;wire [7:0] cmp_read_data;
reg ack_valid=0,ack_slot=0,ack_camera_id=0,ack_source_slot_id=0;reg [31:0] ack_epoch=0,ack_session=0,ack_capture_seq=0;
wire locked;wire [31:0] reject_acks,accepted,completed,failed,ar_words,groups,cycles,queue_peak;
wire select_valid,select_camera;wire [31:0] select_seq;
dual_aplus_scheduler_old #(.W(W),.H(H),.CMP_CAP(CAP),.TIMEOUT(200)) dut(.clk(clk),.rst_n(rst_n),.current_epoch(current_epoch),.prep_en(prep_en),.pred_en(pred_en),.abort(abort),.sink_enable(sink_enable),.a_desc_valid(a_desc_valid),.a_desc_ready(a_desc_ready),.a_desc_camera_id(a_desc_camera_id),.a_desc_slot_id(a_desc_slot_id),.a_desc_epoch(a_desc_epoch),.a_desc_session(a_desc_session),.a_desc_capture_seq(a_desc_capture_seq),.a_desc_base(a_desc_base),.a_desc_dma_bytes(a_desc_dma_bytes),.a_desc_raw_bytes(a_desc_raw_bytes),.a_desc_width(a_desc_width),.a_desc_height(a_desc_height),.a_desc_bayer_phase(a_desc_bayer_phase),.b_desc_valid(b_desc_valid),.b_desc_ready(b_desc_ready),.b_desc_camera_id(b_desc_camera_id),.b_desc_slot_id(b_desc_slot_id),.b_desc_epoch(b_desc_epoch),.b_desc_session(b_desc_session),.b_desc_capture_seq(b_desc_capture_seq),.b_desc_base(b_desc_base),.b_desc_dma_bytes(b_desc_dma_bytes),.b_desc_raw_bytes(b_desc_raw_bytes),.b_desc_width(b_desc_width),.b_desc_height(b_desc_height),.b_desc_bayer_phase(b_desc_bayer_phase),.rel_valid(rel_valid),.rel_ready(rel_ready),.rel_camera_id(rel_camera_id),.rel_slot_id(rel_slot_id),.rel_epoch(rel_epoch),.rel_session(rel_session),.rel_capture_seq(rel_capture_seq),.rel_status(rel_status),.arvalid(arvalid),.arready(arready),.araddr(araddr),.arid(arid),.arlen(arlen),.arsize(arsize),.arburst(arburst),.rvalid(rvalid),.rready(rready),.rdata(rdata),.rid(rid),.rresp(rresp),.rlast(rlast),.cmp_valid(cmp_valid),.cmp_ready(cmp_ready),.cmp_slot(cmp_slot),.cmp_camera_id(cmp_camera_id),.cmp_source_slot_id(cmp_source_slot_id),.cmp_epoch(cmp_epoch),.cmp_session(cmp_session),.cmp_capture_seq(cmp_capture_seq),.cmp_raw_len(cmp_raw_len),.cmp_xform_len(cmp_xform_len),.cmp_stream_len(cmp_stream_len),.cmp_raw_crc(cmp_raw_crc),.cmp_xform_crc(cmp_xform_crc),.cmp_stream_crc(cmp_stream_crc),.cmp_prep(cmp_prep),.cmp_pred(cmp_pred),.cmp_read_slot(cmp_read_slot),.cmp_read_addr(cmp_read_addr),.cmp_read_data(cmp_read_data),.ack_valid(ack_valid),.ack_slot(ack_slot),.ack_camera_id(ack_camera_id),.ack_source_slot_id(ack_source_slot_id),.ack_epoch(ack_epoch),.ack_session(ack_session),.ack_capture_seq(ack_capture_seq),.locked(locked),.reject_acks(reject_acks),.accepted(accepted),.completed(completed),.failed(failed),.ar_words(ar_words),.groups(groups),.cycles(cycles),.queue_peak(queue_peak),.select_valid(select_valid),.select_camera(select_camera),.select_seq(select_seq));
reg [7:0] headers[0:8191];integer srcseq[0:3],srcfault[0:3];reg [3:0] raw_owned=0;
reg pending=0,holdar=0,holdr=0;integer latency=0,idx=0,off=0,rcount=0,ccount=0,selcount=0;
integer i,j,fd,mf,tf,logfd,seqno,relfails=0,safe0=0,seen[0:127];
integer acam[0:1],aslot[0:1],ae[0:1],ase[0:1],aq[0:1];reg [1:0] ackpending=0;reg ackenable=1;
string outdir,hpath,fpath;integer tick=0;reg [31:0] seed=32'h12345678;
integer startcycle=0,startwords=0,startgroups=0,badacks=0;
reg oldcmpstall=0,last_cmp_take=0;reg [292:0] oldcmp;
wire [292:0] cmp_bundle={cmp_slot,cmp_camera_id,cmp_source_slot_id,cmp_epoch,cmp_session,cmp_capture_seq,cmp_raw_len,cmp_xform_len,cmp_stream_len,cmp_raw_crc,cmp_xform_crc,cmp_stream_crc,cmp_prep,cmp_pred};
integer hit_take_commit=0,hit_ack_commit=0,hit_take_refill=0;
always @(posedge clk)begin
 if(rst_n&&oldcmpstall&&(!cmp_valid||cmp_bundle!==oldcmp))die("CMP descriptor changed under stall");
 oldcmpstall<=rst_n&&cmp_valid&&!cmp_ready;oldcmp<=cmp_bundle;
 if(rst_n&&cmp_valid&&cmp_ready&&dut.frame_commit)hit_take_commit=1;
 if(rst_n&&ack_valid&&dut.frame_commit&&dut.cs[ack_slot]==3)hit_ack_commit=1;
 if(rst_n&&cmp_valid&&cmp_ready&&last_cmp_take)hit_take_refill=1;
 last_cmp_take<=rst_n&&cmp_valid&&cmp_ready;
end
task automatic ack_one(input integer sl,badkind);begin
 @(negedge clk);ack_slot=sl;ack_camera_id=acam[sl];ack_source_slot_id=aslot[sl];ack_epoch=ae[sl];ack_session=ase[sl];ack_capture_seq=aq[sl];
 if(badkind==1)ack_camera_id=!acam[sl];if(badkind==2)ack_epoch=ae[sl]-1;if(badkind==3)ack_capture_seq=aq[sl]+1;
 ack_valid=1;@(negedge clk);ack_valid=0;if(badkind==0)ackpending[sl]=0;repeat(2)@(negedge clk);
end endtask
wire [39:0] corrupted_group=((dut.group_count*5)%32>=28)?{dut.fifo[39:8],(dut.fifo[7:0]^8'h01)}:dut.fifo[39:0];
initial if(MUT==1)force dut.in_pix=corrupted_group;
assign arready=!pending&&!rvalid&&!holdar&&(tick%7!=1);
function integer sam(input integer cam,sq,x,y);begin sam=(cam*211+sq*73+x*3+y*17+((x^y)&7)*29)&1023;end endfunction
function [7:0] byte_at(input integer ix,ofs);
integer n,g,x,y,k,v,b;begin
 if(ofs<128)byte_at=headers[((ix/2)*32+srcseq[ix])*128+ofs];
 else if(ofs<RAW+128)begin
 n=ofs-128;g=n/5;x=(g%(W/4))*4;y=g/(W/4);k=n%5;
 if(k<4)byte_at=sam(ix/2,srcseq[ix],x+k,y)>>2;
 else begin b=0;for(v=0;v<4;v=v+1)b=b|((sam(ix/2,srcseq[ix],x+v,y)&3)<<(2*v));byte_at=b;end
 end else byte_at=0;
 if(srcfault[ix]==1&&ofs==0)byte_at=byte_at^1;
 if(srcfault[ix]==2&&ofs==128+RAW-1)byte_at=byte_at^1;
 if(srcfault[ix]==3&&ofs==10)byte_at=byte_at^1;
end endfunction
task die(input [1023:0] why);begin $display("ASSERT_FAIL %0s t=%0t state=%0d",why,$time,dut.state);$fatal(1);end endtask
task reset_all;begin
 @(negedge clk);rst_n=0;a_desc_valid=0;b_desc_valid=0;abort=0;holdar=0;holdr=0;ack_valid=0;
 repeat(5)@(negedge clk);current_epoch=current_epoch+1;rst_n=1;repeat(5)@(negedge clk);
end endtask
task automatic send(input integer cam,sl,sq,fl);
integer q;begin
 q=cam*2+sl;if(raw_owned[q])die("TB attempted RAW overwrite");
 srcseq[q]=sq;srcfault[q]=fl;
 @(negedge clk);
 if(cam==0)begin a_desc_slot_id=sl;a_desc_epoch=(fl==12)?current_epoch-1:current_epoch;a_desc_session=32'h20261025;a_desc_capture_seq=sq;a_desc_base=32'h100000+sl*32'h800000;a_desc_dma_bytes=(fl==5)?DMA-32:DMA;a_desc_raw_bytes=RAW;a_desc_bayer_phase=PREP?0:3;a_desc_valid=1;if(fl==4)a_desc_base=32'h21100000;if(fl==13)a_desc_bayer_phase=2;end
 else begin b_desc_slot_id=sl;b_desc_epoch=current_epoch;b_desc_session=32'h20261025;b_desc_capture_seq=sq;b_desc_base=32'h1100000+sl*32'h800000;b_desc_dma_bytes=DMA;b_desc_raw_bytes=RAW;b_desc_bayer_phase=PREP?0:3;b_desc_valid=1;end
 if(cam==0)begin do @(posedge clk);while(!a_desc_ready);end else begin do @(posedge clk);while(!b_desc_ready);end
 raw_owned[q]=1;@(negedge clk);if(cam==0)a_desc_valid=0;else b_desc_valid=0;
end endtask
task automatic pair(input integer sl,sq);begin fork send(0,sl,sq,0);send(1,sl,sq,0);join end endtask
task wait_rel(input integer target);begin wait(rcount>=target);repeat(12)@(negedge clk);end endtask
always @(posedge clk)begin
 tick<=tick+1;
 if(!rst_n)begin pending<=0;rvalid<=0;raw_owned<=0;ackpending<=0;ack_valid<=0;end
 else begin
 seed<=seed^(seed<<13)^(seed>>17)^(seed<<5);sink_enable<=((tick%11)!=3)&&((tick%11)!=4);rel_ready<=((tick%9)!=4);
 if(arvalid&&arready)begin
 if(arid!=3||arlen!=0||arsize!=5||arburst!=1||araddr[4:0]!=0)die("AXI fields");
 if(araddr>=29'h1900000)begin idx=3;off=araddr-29'h1900000;end
 else if(araddr>=29'h1100000)begin idx=2;off=araddr-29'h1100000;end
 else if(araddr>=29'h0900000)begin idx=1;off=araddr-29'h0900000;end
 else begin idx=0;off=araddr-29'h0100000;end
 if(off<0||off+32>DMA||!raw_owned[idx])die("out-of-bounds or unowned AR");
 pending<=1;latency<=2+(tick%3);for(j=0;j<32;j=j+1)rdata[j*8+:8]<=byte_at(idx,off+j);
 rresp<=(srcfault[idx]==6)?2:0;rid<=(srcfault[idx]==14)?4:3;rlast<=(srcfault[idx]==15)?0:1;
 end
 if(pending&&!rvalid&&!holdr)begin if(latency==0)rvalid<=1;else latency<=latency-1;end
 if(rvalid&&rready)begin rvalid<=0;pending<=0;end
 if(rel_valid&&rel_ready)begin
 i=rel_camera_id*2+rel_slot_id;
 if(!raw_owned[i]||rel_epoch!=((srcfault[i]==12)?current_epoch-1:current_epoch)||rel_session!=32'h20261025||rel_capture_seq!=srcseq[i])die("wrong/duplicate RAW release");
 if(pending||dut.outstanding||arvalid)die("premature release");
 if(srcfault[i]==0&&rel_status!=0)die("good RAW release status");
 if(srcfault[i]!=0&&rel_status==0)die("fault committed RAW");
 if(rel_status!=0)relfails=relfails+1;raw_owned[i]=0;rcount=rcount+1;
 $fdisplay(logfd,"REL %0d %0d %0d %0d",rel_camera_id,rel_slot_id,rel_capture_seq,rel_status);
 $fdisplay(logfd,"FRAME cam=%0d seq=%0d status=%0d cycles=%0d words=%0d groups=%0d",rel_camera_id,rel_capture_seq,rel_status,cycles-startcycle,ar_words-startwords,groups-startgroups);
 end
 if(select_valid)begin
 $fdisplay(logfd,"SELECT %0d %0d %0d",selcount,select_camera,select_seq);
 if(CASE==0&&selcount<8&&select_camera!=selcount%2)die("round robin starvation");
 selcount=selcount+1;startcycle=cycles;startwords=ar_words;startgroups=groups;
 end
 if(cmp_valid&&cmp_ready)begin
 if(seen[cmp_camera_id*32+cmp_capture_seq]!=0)die("duplicate CMP identity");seen[cmp_camera_id*32+cmp_capture_seq]=1;
 if(cmp_epoch!=current_epoch||cmp_session!=32'h20261025)die("CMP source identity");
 fpath=$sformatf("%0s/c%0d_q%0d.zlib",outdir,cmp_camera_id,cmp_capture_seq);fd=$fopen(fpath,"wb");
 if(!fd)die("CMP open failed");
 for(i=0;i<cmp_stream_len;i=i+1)begin if(cmp_slot)$fwrite(fd,"%c",dut.cmp1[i]);else $fwrite(fd,"%c",dut.cmp0[i]);end
 $fclose(fd);
 $fdisplay(mf,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cmp_camera_id,cmp_source_slot_id,cmp_epoch,cmp_session,cmp_capture_seq,cmp_raw_len,cmp_xform_len,cmp_stream_len,cmp_raw_crc,cmp_xform_crc,cmp_stream_crc,cmp_prep,cmp_pred);
 acam[cmp_slot]=cmp_camera_id;aslot[cmp_slot]=cmp_source_slot_id;ae[cmp_slot]=cmp_epoch;ase[cmp_slot]=cmp_session;aq[cmp_slot]=cmp_capture_seq;ackpending[cmp_slot]=1;ccount=ccount+1;
 end
 if(ack_valid)begin ack_valid<=0;end
 else if(ackenable&&ackpending!=0)begin
 i=ackpending[0]?0:1;ack_slot<=i;ack_camera_id<=acam[i];ack_source_slot_id<=aslot[i];ack_epoch<=ae[i];ack_session<=ase[i];ack_capture_seq<=aq[i];ack_valid<=1;ackpending[i]=0;
 end
 end
end
reg oldar=0,oldin=0,oldout=0;reg [28:0] oldaddr;reg [39:0] oldpix;reg oldsof;reg [36:0] olddata;
always @(posedge clk)begin
 if(rst_n)begin
 if(oldar&&(araddr!==oldaddr||!arvalid))die("AR stall changed");
 if(oldin&&!abort&&!dut.core_abort&&(dut.in_pix!==oldpix||dut.in_sof!==oldsof||!dut.in_valid))die("input stall changed");
 if(oldout&&!abort&&!dut.core_abort&&({dut.out_data,dut.out_keep,dut.out_last}!==olddata||!dut.out_valid))die("output stall changed");
 end
 oldar<=rst_n&&arvalid&&!arready;oldaddr<=araddr;
 oldin<=rst_n&&dut.in_valid&&!dut.in_ready&&!dut.bad&&!abort;oldpix<=dut.in_pix;oldsof<=dut.in_sof;
 oldout<=rst_n&&dut.out_valid&&!dut.out_ready&&!dut.bad&&!abort;olddata<={dut.out_data,dut.out_keep,dut.out_last};
end
initial begin
 if(!$value$plusargs("OUT=%s",outdir)||!$value$plusargs("HDR=%s",hpath))die("missing paths");
 fd=$fopen(hpath,"r");if(!fd)die("header open failed");$fclose(fd);
 $readmemh(hpath,headers);fpath={outdir,"/metadata.csv"};mf=$fopen(fpath,"w");if(!mf)die("metadata open failed");fpath={outdir,"/events.log"};logfd=$fopen(fpath,"w");if(!logfd)die("events open failed");
 for(i=0;i<128;i=i+1)seen[i]=0;for(i=0;i<4;i=i+1)begin srcseq[i]=0;srcfault[i]=0;end
 reset_all();
 if(CASE==0)begin
 ackenable=0;pair(0,1);pair(1,2);wait_rel(2);repeat(100)@(negedge clk);if(selcount!=2||ccount!=2||dut.owned==0)die("CMP hold overwritten or RAW admitted");$display("HIT CMP_FULL_RAW_HELD");
 // Wrong identity ACKs while both slots really are held; preserve pending correct ACKs.
 for(badacks=0;badacks<3;badacks=badacks+1)begin
 @(negedge clk);ack_slot=0;ack_camera_id=acam[0];ack_source_slot_id=aslot[0];ack_epoch=ae[0];ack_session=ase[0];ack_capture_seq=aq[0];
 if(badacks==0)ack_camera_id=!acam[0];if(badacks==1)ack_epoch=ae[0]-1;if(badacks==2)ack_capture_seq=aq[0]+1;
 ack_valid=1;@(negedge clk);ack_valid=0;repeat(2)@(negedge clk);
 if(dut.cs[0]!=3)die("held CMP freed by wrong ACK");
 end
 if(reject_acks!=3)die("wrong ACK count");$display("HIT HELD_WRONG_CAMERA_OLD_EPOCH_WRONG_SEQ_ACK");
 ackenable=1;wait_rel(4);pair(0,3);pair(1,4);wait_rel(8);$display("HIT ALTERNATE8 SIMULTANEOUS_AB");
 send(0,0,5,0);send(0,1,6,0);wait_rel(10);send(1,0,5,0);send(1,1,6,0);wait_rel(12);pair(0,7);wait_rel(14);
 if(ccount!=14||relfails!=0)die("normal totals");$display("HIT ONLY_A_ONLY_B_REJOIN CROSS_WORD ODD_TAIL");
 end else if(CASE==1)begin
 for(seqno=1;seqno<=10;seqno=seqno+1)begin
 safe0=rcount;
 if(seqno==7)holdar=1;
 if(seqno==8||seqno==9)holdr=1;
 send(0,0,seqno,seqno);
 if(seqno==7)begin wait(arvalid);@(negedge clk);abort=1;repeat(3)@(negedge clk);abort=0;holdar=0;end
 if(seqno==8)begin wait(pending);@(negedge clk);abort=1;repeat(8)@(negedge clk);abort=0;holdr=0;end
 if(seqno==9)begin wait(locked);if(!raw_owned[0]||rcount!=safe0)die("missing R released");$display("HIT PERMANENT_R_LOCK");reset_all();end
 else begin
 if(seqno==10)begin wait(dut.group_count>=2);@(negedge clk);abort=1;repeat(2)@(negedge clk);abort=0;end
 wait_rel(safe0+1);
 end
 $display("HIT FAULT_%0d",seqno);
 end
 for(seqno=14;seqno<=15;seqno=seqno+1)begin
 safe0=rcount;send(0,0,seqno,seqno);wait(locked);if(!raw_owned[0]||rcount!=safe0)die("RID/RLAST invalid release");
 $display("HIT PROTOCOL_LOCK_%0d",seqno);reset_all();
 end
 send(0,0,12,12);wait_rel(rcount+1);$display("HIT OLD_EPOCH_REJECT");
 pair(0,20);wait_rel(rcount+2);pair(1,21);wait_rel(rcount+2);if(ccount!=4)die("recovery CMP total");
 // Deliberate duplicate/old/wrong-source ACKs after successful free.
 ackenable=0;repeat(20)@(negedge clk);ack_slot=0;ack_camera_id=1;ack_source_slot_id=0;ack_epoch=current_epoch-1;ack_session=0;ack_capture_seq=0;ack_valid=1;@(negedge clk);ack_valid=0;repeat(3)@(negedge clk);if(reject_acks==0)die("bad ACK accepted");$display("HIT STALE_DUPLICATE_ACK_REJECT RECOVERY_GOOD4");
 end else if(CASE==2)begin pair(0,1);wait_rel(2);if(ccount!=2)die("full totals");$display("HIT FULL1920X1080_AB");end
 else if(CASE==3)begin send(0,0,1,11);wait_rel(1);if(ar_words!=0||ccount!=0)die("capacity rejection read");$display("HIT CMP_CAPACITY_REJECT");end
 else if(CASE==4)begin send(0,0,1,13);wait_rel(1);if(ar_words!=0||ccount!=0)die("phase rejection read");$display("HIT PHASE_REJECT");end
 else if(CASE==5)begin
 ackenable=0;send(0,0,1,0);wait_rel(1);wait(ccount==1);
 @(negedge clk);cmp_ready=0;send(1,0,1,0);wait_rel(2);wait(cmp_valid);if(cmp_slot!=1)die("matrix expected stalled slot1");
 ack_one(0,1);ack_one(0,2);ack_one(0,3);if(reject_acks!=3||dut.cs[0]!=3)die("matrix wrong ACK accepted");
 ack_one(0,0);send(0,1,2,0);wait_rel(3);if(!cmp_valid||cmp_slot!=1)die("slot1 changed after slot0 recommit");
 $display("HIT SLOT1_STALL_SLOT0_ACK_RECOMMIT");
 pair(0,3);repeat(100)@(negedge clk);if(selcount!=3||dut.owned==0)die("held CMP allowed RAW overwrite");$display("HIT CMP_TWO_HELD_RAW_BACKPRESSURE");
 @(negedge clk);cmp_ready=1;wait(ccount==3);ack_one(1,0);ack_one(0,0);wait_rel(5);wait(ccount==5);
 @(negedge clk);cmp_ready=0;ack_one(0,0);send(0,1,4,0);wait_rel(6);wait(cmp_valid);if(cmp_slot!=0)die("matrix expected stalled slot0");
 ack_one(1,0);send(1,1,4,0);wait(dut.frame_commit);@(negedge clk);
 cmp_ready=1;ack_slot=cmp_slot;ack_camera_id=cmp_camera_id;ack_source_slot_id=cmp_source_slot_id;ack_epoch=cmp_epoch;ack_session=cmp_session;ack_capture_seq=cmp_capture_seq;ack_valid=1;
 @(negedge clk);ack_valid=0;wait_rel(7);wait(ccount==7);if(reject_acks!=4)die("same-take premature ACK not rejected");
 $display("HIT REVERSE_STALL_TAKE_COMMIT_PREMATURE_ACK");
 ack_one(0,0);send(0,0,5,0);wait(dut.frame_commit);@(negedge clk);
 ack_slot=1;ack_camera_id=acam[1];ack_source_slot_id=aslot[1];ack_epoch=ae[1];ack_session=ase[1];ack_capture_seq=aq[1];ack_valid=1;
 @(negedge clk);ack_valid=0;ackpending[1]=0;wait_rel(8);wait(ccount==8);ack_one(0,0);
 if(ccount!=8||relfails!=0||hit_take_commit==0||hit_ack_commit==0||hit_take_refill==0)die("CMP matrix hit totals");
 $display("HIT CMP_TAKE_REFILL_ACK_COMMIT_REAL_CORE GOOD8");
 end
 repeat(30)@(negedge clk);
 $fdisplay(logfd,"STATS cycles=%0d ar_words=%0d groups=%0d peak=%0d completed=%0d failed=%0d",cycles,ar_words,groups,queue_peak,completed,failed);
 $fclose(mf);$fclose(logfd);$display("TB_DONE case=%0d W=%0d H=%0d cmp=%0d rel=%0d",CASE,W,H,ccount,rcount);$finish;
end
initial begin repeat(90000000)@(posedge clk);die("cycle watchdog");end
endmodule
