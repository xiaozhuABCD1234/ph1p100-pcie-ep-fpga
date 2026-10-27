`timescale 1ns/1ps
`include "fixture-config.vh"
module tb_byte_replay;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0;
 reg wr_begin=0, wr_valid=0, wr_last=0, rd_open=0, rd_close=0;
 reg [39:0] wr_data=0; reg [3:0] wr_keep=0;
 wire wr_begin_ready, wr_ready, rd_open_ready, rd_valid;
 wire [31:0] rd_id, rd_len, awaddr, araddr, pubs, errs, reads;
 wire awvalid,wvalid,arvalid,rready; wire [255:0] wdata,rdata;
 reg [255:0] mem[0:255]; reg [255:0] rdata_r=0; reg rvalid=0;
 assign rdata=rdata_r;
 a1_ddr_slot_store #(.MODE(1),.SLOT_WORDS(128),.AWB(8)) store(
  .clk(clk),.rst_n(rst_n),.ddr_ready(1'b1),.wr_begin(wr_begin),.wr_begin_ready(wr_begin_ready),
  .wr_id(32'd123),.wr_data(wr_data),.wr_keep(wr_keep),.wr_valid(wr_valid),.wr_last(wr_last),
  .wr_ready(wr_ready),.wr_abort(1'b0),.rd_open(rd_open),.rd_open_ready(rd_open_ready),
  .rd_id(rd_id),.rd_len_bytes(rd_len),.rd_close(rd_close),.rd_data(),.rd_valid(rd_valid),.rd_take(1'b1),
  .ddr_awaddr(awaddr),.ddr_awvalid(awvalid),.ddr_awready(1'b1),.ddr_wdata(wdata),
  .ddr_wvalid(wvalid),.ddr_wready(1'b1),.ddr_araddr(araddr),.ddr_arvalid(arvalid),
  .ddr_arready(1'b1),.ddr_rdata(rdata),.ddr_rvalid(rvalid),.ddr_rready(rready),
  .st_published(pubs),.st_dropped(),.st_errors(errs),.st_last_bytes(),.st_read_words(reads),.st_dup_words());
 always @(posedge clk) begin
  if (awvalid && wvalid) mem[awaddr] <= wdata;
  rvalid <= 0;
  if (arvalid) begin rdata_r <= mem[araddr]; rvalid <= 1; end
 end
 reg slot_ready=0; reg [31:0] slot_len=0, cap=4194304;
 reg done=0,ack=0;reg [31:0] ack_seq=0,ack_sess=0;
 wire arm,release_slot;wire [31:0] out_len,out_frame,out_cap,out_session,out_base;
 wire cam,src;wire [7:0] st_err;
 aplus_pcie_egress_adapter #(.SLOT_BYTES(3000000)) p2(
  .clk(clk),.rst_n(rst_n),.push_en(1'b1),.cap_bytes(cap),.session_id(32'd7),
  .dst_base(64'h100000),.db_addr(64'h800000),.mps_code(3'd3),.link_up(1'b1),
  .slot_ready(slot_ready),.slot_id(32'd123),.slot_stream_len(slot_len),.slot_base_word(32'd0),
  .pcie_busy(1'b0),.pcie_held(1'b0),.pcie_done(done),.pcie_err(1'b0),
  .pcie_held_seq(32'd123),.pcie_held_sess(32'd7),.ack_pulse(ack),.ack_seq(ack_seq),
  .ack_session(ack_sess),.cancel_pulse(1'b0),.arm_pulse(arm),.o_cap_bytes(out_cap),
  .o_session_id(out_session),.o_dst_base(),.o_db_addr(),.o_frame_bytes(out_frame),
  .o_stream_len(out_len),.o_slot_base_word(out_base),.o_src_sel(src),.o_cam_sel(cam),
  .slot_release(release_slot),.st_exported(),.st_bytes(),.st_err(st_err),.st_busy(),.st_held());
 integer errors=0, desc, actual, padded, i,j,k,count=0;
 reg [7:0] stimulus[0:`STREAM_N-1];
 always @(posedge clk) if(rst_n && rd_valid) begin
  for(k=0;k<32;k=k+1) begin
   $fwrite(padded,"%c",store.rd_data[k*8+:8]);
   if(count<`STREAM_N) $fwrite(actual,"%c",store.rd_data[k*8+:8]);
   count=count+1;
  end
 end
 task descriptor;
  input integer n, capacity, kind;
  integer expected;
  begin
   @(negedge clk);slot_len=n;cap=capacity;slot_ready=1;
   @(negedge clk);slot_ready=0;expected=((n+4095)/4096)*4096;
   if(!arm || out_len!=n || out_frame!=expected || out_cap!=capacity || out_session!=7 || cam!=0 || src!=0) errors=errors+1;
   $fwrite(desc,"{\"kind\":%0d,\"zlib_bytes\":%0d,\"frame_bytes\":%0d,\"cap_bytes\":%0d,\"session\":%0d,\"cam_sel\":%0d,\"slot_base_word\":%0d,\"arm\":%0d}\n",kind,out_len,out_frame,out_cap,out_session,cam,out_base,arm);
   @(negedge clk);done=1;@(negedge clk);done=0;
   repeat(2) @(negedge clk);
   ack=1;ack_seq=123;ack_sess=999;@(negedge clk);ack=0;
   if(release_slot || st_err==0) errors=errors+1;
   @(negedge clk);ack=1;ack_sess=7;@(negedge clk);ack=0;
   if(!release_slot) errors=errors+1;
   repeat(2) @(negedge clk);
  end
 endtask
 initial begin
  desc=$fopen("p2-descriptors.jsonl","w");actual=$fopen("rtl-slot-read.bin","wb");padded=$fopen("rtl-slot-word-padding.bin","wb");
  $readmemh("stream.mem",stimulus);
  repeat(4) @(negedge clk);rst_n=1;
  @(negedge clk);wr_begin=1;@(negedge clk);wr_begin=0;
  for(i=0;i<`STREAM_N;i=i+4) begin
   wr_data=0;wr_keep=0;
   for(j=0;j<4;j=j+1) if(i+j<`STREAM_N) begin wr_data[j*8+:8]=stimulus[i+j];wr_keep[j]=1;end
   wr_last=(i+4>=`STREAM_N);wr_valid=1;
   @(posedge clk);while(!wr_ready) @(posedge clk);
   @(negedge clk);
  end
  wr_valid=0;wr_last=0;
  if(pubs!=1 || errs!=0 || rd_len!=`STREAM_N || rd_id!=123) errors=errors+1;
  $display("REAL_STORE published=%0d errors=%0d exact_len=%0d first_word=%h",pubs,errs,rd_len,mem[0]);
  descriptor(rd_len,4194304,0);
  rd_open=1;@(negedge clk);rd_open=0;
  wait(count>=`STREAM_N);@(negedge clk);rd_close=1;@(negedge clk);rd_close=0;
  $fclose(actual);$fclose(padded);
  for(i=4052;i<=4096;i=i+1) descriptor(i,4194304,1);
  descriptor(2594706,4194304,2);
  descriptor(4096,1,3); // adapter lacks capacity-vs-frame check; backend must reject.
  $fclose(desc);
  if(errors==0) $display("BYTE_REPLAY_RTL PASS descriptors=48 slot_bytes=%0d",`STREAM_N);
  else $display("BYTE_REPLAY_RTL FAIL errors=%0d",errors);
  $finish;
 end
 initial begin #10000000;$display("BYTE_REPLAY_RTL FAIL watchdog");$finish;end
endmodule
