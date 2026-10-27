`timescale 1ns/1ps
module tb_csi_preview_integrity #(parameter LINE_BYTES=80);
 localparam SW=LINE_BYTES/5,SH=4,SOURCE_LINES=SH*4,FRAME_BYTES=SW*SH,WORDS=FRAME_BYTES/32+1;
 reg clk=0,usr_clk=0,rst_n=0,en=1,valid=0;reg[31:0] data=0;reg[23:0] hdr=0;
 wire[7:0] ecc;wire[31:0] payload;wire pv,done,waitsync,vs,inf,inl;wire[3:0] keep;
 wire fe,fg,abort_frame;wire[31:0] crc_errors,header_errors,packet_timeouts,frame_timeouts,good_frames,bad_frames;wire[15:0] last_wc,last_lines;wire[39:0] pixels;wire pixels_valid;
 wire[257:0] token_in,token;wire tv,space,rv,take;wire[31:0] drops;
 wire gs,gv,gl;wire[7:0] gd;wire[23:0] preview_rgb;wire preview_de,preview_alive;reg corrupt_payload=0;integer gray_bytes=0,gray_lasts=0;
 wire[31:0] published_count,error_count,drop_count,read_frame_id;wire frame_begin_ready,s_ready,frame_switch_ready,frame_valid,rd_req_ready,rd_valid;
 wire[255:0] rd_data;wire[26:0] paxi_awaddr,paxi_araddr;wire[255:0] paxi_wdata;wire[31:0] paxi_wstrb;
 wire paxi_awvalid,paxi_wvalid,paxi_wlast,paxi_arvalid,paxi_rready;
 reg[255:0] paxi_rdata=0;reg paxi_rvalid=0,pending=0;reg[255:0] pending_data;
 integer uc=0,latency=0,pubs=0,aborts=0,footers=0,frames=0,i,j,k,latest_base=0;
 wire paxi_awready=rst_n&&(uc%3!=0),paxi_arready=rst_n&&(uc%5!=0),paxi_wready=rst_n&&(uc%7!=0);
 reg[255:0] memory[0:WORDS*3-1];reg[31:0] golden_crc[0:0];reg[7:0] expected;
 always #5 clk=~clk;always #2.5 usr_clk=~usr_clk;
 csi_rx_hdr_ecc e(.data(hdr),.ecc(ecc));
 csi_rx_packet_integrity #(.EXPECTED_LINES(SOURCE_LINES),.CHECK_FRAME_ID(1),.FRAME_TIMEOUT_CYCLES(16777216)) packet(
 .I_clock(clk),.I_reset_n(rst_n),.I_enable(en),.I_data(data),.I_data_valid(valid),.O_packet_done(done),.O_sync_wait(waitsync),.O_payload_out(payload),.O_payload_valid(pv),.O_payload_keep(keep),.O_vsync_out(vs),.O_in_frame(inf),.O_in_line(inl),.O_frame_end(fe),.O_frame_good(fg),.O_frame_abort(abort_frame),.O_crc_errors(crc_errors),.O_header_errors(header_errors),.O_packet_timeouts(packet_timeouts),.O_frame_timeouts(frame_timeouts),.O_good_frames(good_frames),.O_bad_frames(bad_frames),.O_last_wc(last_wc),.O_last_lines(last_lines));
 csi_rx_10bit_unpack_checked unpack(.I_clock(clk),.I_reset_n(rst_n),.I_enable(en),.I_line_in(inl),.I_data_in(payload),.I_keep(keep),.I_din_valid(pv),.O_data_out(pixels),.O_dout_valid(pixels_valid));
 cam_preview_capture #(.SW(SW),.SH(SH),.H_ACT(SW*2),.V_ACT(SH*2),.DEC_LINE(4),.DEC_CYC(1)) preview(
 .I_bc_clk(clk),.I_bc_rst_n(rst_n),.I_pix_data(pixels),.I_pix_valid(pixels_valid),.I_line(inl),.I_frame(inf),
 .I_pclk(usr_clk),.I_pclk_rst_n(rst_n),.I_de(1'b0),.I_vs(1'b0),.O_rgb(preview_rgb),.O_de(preview_de),.O_cam_alive(preview_alive),
 .O_gray_sof(gs),.O_gray_valid(gv),.O_gray_last(gl),.O_gray_data(gd));
 always @(posedge clk)if(rst_n&&gv)begin gray_bytes++;if(gl)gray_lasts++;end
 gray_frame_pack_guarded #(.FRAME_BYTES(FRAME_BYTES)) pack(.clk(clk),.rst_n(rst_n),.sof(gs),.pixel_valid(gv),.pixel_last(gl),.pixel(gd),.frame_end(fe),.frame_good(fg),.frame_abort(abort_frame),.out_data(token_in),.out_valid(tv),.out_ready(space),.dropped_frames(drops));
 capture_async_fifo #(.WIDTH(258),.ADDR_BITS(3)) fifo(.rst_n(rst_n),.wclk(clk),.w_valid(tv),.w_data(token_in),.w_ready(space),.rclk(usr_clk),.r_valid(rv),.r_data(token),.r_ready(take));
 wire[1:0] tag=token[257:256];reg in_frame=0;
 wire begin_frame=rv&&tag==1&&!in_frame;
 wire abort_store=rv&&(tag==3||(tag==1&&in_frame));
 wire data_valid=rv&&(tag==0||tag==2)&&in_frame;
 assign take=(tag==1)?(!in_frame&&frame_begin_ready):(tag==3)?1'b1:(!in_frame||s_ready);
 always @(posedge usr_clk)if(!rst_n)in_frame<=0;else if(abort_store)in_frame<=0;else if(begin_frame&&frame_begin_ready)in_frame<=1;else if(data_valid&&s_ready&&tag==2)in_frame<=0;
 ddr_frame_store #(.FRAME_WORDS(WORDS)) store(.clk(usr_clk),.rst_n(rst_n),.ddr_ready(rst_n),.frame_begin(begin_frame),.frame_id(token[31:0]),.frame_begin_ready(frame_begin_ready),.s_data(token[255:0]),.s_valid(data_valid),.s_last(tag==2),.s_abort(abort_store),.s_ready(s_ready),.frame_switch(1'b0),.frame_switch_ready(frame_switch_ready),.frame_valid(frame_valid),.read_frame_id(read_frame_id),.rd_req(1'b0),.rd_offset(16'd0),.rd_req_ready(rd_req_ready),.rd_data(rd_data),.rd_valid(rd_valid),.rd_take(1'b1),.published_count(published_count),.error_count(error_count),.drop_count(drop_count),.paxi_awaddr(paxi_awaddr),.paxi_awvalid(paxi_awvalid),.paxi_awready(paxi_awready),.paxi_wdata(paxi_wdata),.paxi_wstrb(paxi_wstrb),.paxi_wvalid(paxi_wvalid),.paxi_wlast(paxi_wlast),.paxi_wready(paxi_wready),.paxi_araddr(paxi_araddr),.paxi_arvalid(paxi_arvalid),.paxi_arready(paxi_arready),.paxi_rdata(paxi_rdata),.paxi_rvalid(paxi_rvalid),.paxi_rlast(1'b1),.paxi_rready(paxi_rready));
 task fail(input string why);begin $display("INTEGRITY_FAIL preview %s pub=%0d footers=%0d aborts=%0d",why,published_count,footers,aborts);$finish;end endtask
 always @(posedge clk)if(rst_n&&tv&&space)begin if(token_in[257:256]==2)footers++;if(token_in[257:256]==3)aborts++;end
 always @(posedge usr_clk)begin
  uc<=uc+1;
  if(!rst_n)begin pending<=0;paxi_rvalid<=0;end else begin
   paxi_rvalid<=0;
   if(paxi_awvalid)begin
    if(!paxi_wvalid||!paxi_awready||!paxi_wready||paxi_wstrb!=0||!paxi_wlast||paxi_awaddr>=WORDS*24)fail("native write");
    memory[paxi_awaddr>>3]<=paxi_wdata;if((paxi_awaddr>>3)%WORDS==0)latest_base=(paxi_awaddr>>3);end
   if(pending)begin if(latency!=0)latency<=latency-1;else begin paxi_rvalid<=1;paxi_rdata<=pending_data;pending<=0;end end
   if(paxi_arvalid)begin if(pending||paxi_rvalid||!paxi_arready)fail("fence overlap");pending<=1;pending_data<=memory[paxi_araddr>>3];latency<=uc%5+3;end
   #1;if(published_count!=pubs)begin
    if(published_count!=pubs+1)fail("publish jump");pubs=published_count;
    for(integer q=0;q<FRAME_BYTES;q++)begin expected=gray(q%SW);if(memory[latest_base+q/32][q%32*8+:8]!==expected)fail("all-byte payload or RAW10 mapping");end
    if(memory[latest_base+WORDS-1][95:64]!==golden_crc[0])fail("Python golden CRC32");
   end
  end
 end
 // Independent MSB-first 0x1021 reference, with explicit input/output reversal.
 function[7:0] rev8(input[7:0] v);begin for(integer b=0;b<8;b++)rev8[b]=v[7-b];end endfunction
 function[15:0] reverse16(input[15:0] v);begin for(integer b=0;b<16;b++)reverse16[b]=v[15-b];end endfunction
 function[7:0] value(input integer n);value=(n*37+(n>>8)*13+7)&255;endfunction
 function[7:0] gray(input integer col);
 integer off,p0,p1;reg[7:0] low;begin off=col*5;low=value(off+4);p0=value(off)*4+(low&3);p1=value(off+1)*4+((low>>2)&3);gray=(p0+p1)>>3;end endfunction
 function[15:0] checksum(input integer wc);
 reg[15:0] c;reg[7:0] b;begin c=16'hffff;for(integer n=0;n<wc;n++)begin b=rev8(value(n));c=c^{b,8'd0};for(integer z=0;z<8;z++)c=(c<<1)^(c[15]?16'h1021:0);end checksum=reverse16(c);end endfunction
 task beat(input[31:0] v);begin @(negedge clk);data=v;valid=1;end endtask
 task idle(input integer n);begin @(negedge clk);valid=0;repeat(n)@(negedge clk);end endtask
 task shortpkt(input[7:0] di,input[15:0] num,input bit bad_ecc);begin hdr={num,di};#1;beat({ecc^(bad_ecc?8'h01:8'h00),hdr});idle(6);end endtask
 task linepkt(input[7:0] di,input integer wc,input bit bad_crc,input bit gaps);
 reg[15:0] c;reg[31:0] w;integer offset;begin
 hdr={wc[15:0],di};#1;beat({ecc,hdr});c=checksum(wc)^(bad_crc?16'h0001:0);
 for(integer n=0;n<(wc+5)/4;n++)begin
  w=32'hd00dd00d;for(integer b=0;b<4;b++)begin offset=n*4+b;if(offset<wc)w[b*8+:8]=value(offset);else if(offset==wc)w[b*8+:8]=c[7:0];else if(offset==wc+1)w[b*8+:8]=c[15:8];end
  if(corrupt_payload&&n==0)w[0]=~w[0];if(gaps&&n%7==1)idle(1);beat(w);
 end idle(8);
 end endtask
 task source(input bit crc_bad);integer old_lasts;begin
 old_lasts=gray_lasts;shortpkt(0,7,0);
 for(integer row=0;row<SOURCE_LINES;row++)begin
  // Final output row completes at source row 13, before rows 14/15 and FE.
  if(crc_bad&&row==SOURCE_LINES-1&&gray_lasts==old_lasts)fail("late CRC was not after preview last");
  linepkt(8'h2b,LINE_BYTES,crc_bad&&row==SOURCE_LINES-1,row%3==0);
 end frames++;end endtask
 task drain;begin idle(20);repeat(200)@(negedge usr_clk);end endtask
 task expect_pub(input integer n);begin drain();if(published_count!=n||footers!=n||error_count!=0)fail("publication count / protocol");end endtask
 initial begin
  $readmemh("golden_crc.txt",golden_crc);repeat(4)@(negedge clk);rst_n=1;idle(8);
  source(0);expect_pub(0);idle(100);expect_pub(0);shortpkt(1,7,0);expect_pub(1);
  source(1);shortpkt(1,7,0);expect_pub(1);
  source(0);expect_pub(1);linepkt(8'h12,3,1,0);shortpkt(1,7,0);expect_pub(1);
  source(0);expect_pub(1);shortpkt(1,7,1);expect_pub(1);
  source(0);expect_pub(1);shortpkt(1,8,0);expect_pub(1);
  source(0);expect_pub(1); // missing FE must reject old and arriving SOF frame
  source(0);shortpkt(1,7,0);expect_pub(1);
  source(0);shortpkt(1,7,0);expect_pub(2);
  shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);shortpkt(1,7,0);expect_pub(2);
  source(0);shortpkt(1,7,0);expect_pub(3);
  // Disable mid-body then re-enable: no partial publication, recover next FS.
  shortpkt(0,7,0);hdr={LINE_BYTES[15:0],8'h2b};#1;beat({ecc,hdr});beat(32'h12345678);en=0;idle(8);en=1;idle(8);expect_pub(3);
  source(0);shortpkt(1,7,0);expect_pub(4);
  if(aborts<6||drops<6||crc_errors!=2||header_errors!=1)fail("abort diagnostics");
  $display("INTEGRITY_PASS preview wc=%0d bytes=%0d frames=%0d pub=%0d aborts=%0d drops=%0d",LINE_BYTES,FRAME_BYTES,frames,published_count,aborts,drops);
  $display("PREVIEW_TAP_DIAG gray_bytes=%0d last_pulses=%0d",gray_bytes,gray_lasts);$finish;
 end
 initial begin #10000000;fail("watchdog");end
endmodule
