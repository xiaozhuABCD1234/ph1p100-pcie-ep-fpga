`timescale 1ns/1ps
// Bounded normal-interface loss test. Camera stimulus follows frozen
// tb_p1_chain.v / recovery/tb_recovery.sv. No force, no DUT mutations.
module tb_r1_sof;
 localparam W=32,H=2,CAM_W=40,CAM_H=8,ROI_X=4,ROI_Y=2,CG=10;
 localparam FIFO_AW=2,UART_DIV=4;
 reg clk_cam=0,clk_a1=0,rst_n=0;
 // Slow enough that the depth-four FIFO control does not itself overflow.
 always #20 clk_cam=~clk_cam;
 initial begin #1.7;forever #2.6665 clk_a1=~clk_a1;end
 wire clk_uart=clk_a1;
 reg [39:0] pix=0;reg pv=0,il=0,inf=0,vs=0;
 wire [31:0] awaddr,araddr;wire awvalid,awready,wvalid,wready,arvalid,arready,rvalid,rready;
 wire [255:0] wdata,rdata;wire [7:0] byte_data;wire byte_valid,txd;
 wire [31:0] cap,enc,exp,expbytes,rawpub,rawdrop,cmpdrop,geom,err,reads,dups;
 camera_a1_uart_top #(.CAM_W(CAM_W),.CAM_H(CAM_H),.ROI_X(ROI_X),.ROI_Y(ROI_Y),
  .W(W),.H(H),.UART_DIV(UART_DIV),.FIFO_AW(FIFO_AW),.STS_DIV(0)) dut(
  .clk_cam(clk_cam),.clk_a1(clk_a1),.clk_uart(clk_uart),.rst_n(rst_n),
  .i_a_pixel(pix),.i_a_pixel_valid(pv),.i_a_in_line(il),.i_a_in_frame(inf),.i_a_vsync(vs),
  .i_ddr_rdy(1'b1),.i_dbg_tap(6'd0),.i_dbg_delay_done(1'b0),.i_dbg_rst_out(1'b0),
  .i_dbg_sync_wait(1'b0),.i_dbg_pkt_tgl(1'b0),.i_dbg_vs_tgl(1'b0),.i_dbg_clk_tgl(1'b0),.i_dbg_sys(64'd0),
  .o_ddr_awaddr(awaddr),.o_ddr_awvalid(awvalid),.o_ddr_awready(awready),
  .o_ddr_wdata(wdata),.o_ddr_wvalid(wvalid),.o_ddr_wready(wready),
  .o_ddr_araddr(araddr),.o_ddr_arvalid(arvalid),.o_ddr_arready(arready),
  .i_ddr_rdata(rdata),.i_ddr_rvalid(rvalid),.o_ddr_rready(rready),
  .o_uart_txd(txd),.o_dbg_byte(byte_data),.o_dbg_byte_valid(byte_valid),
  .o_st_cap_frames(cap),.o_st_enc_frames(enc),.o_st_exported(exp),.o_st_export_bytes(expbytes),
  .o_st_raw_pub(rawpub),.o_st_raw_drop(rawdrop),.o_st_cmp_drop(cmpdrop),
  .o_st_geom_err(geom),.o_st_errors(err),.o_st_read_words(reads),.o_st_dup_words(dups),.o_st_raw_sts());
 reg stall_write=0;
 wire pending;wire [31:0] response_epoch,aw_count,w_count,ar_count,r_count,old_r_count;
 ddr_recovery_model mem(.clk(clk_a1),.dut_rst_n(rst_n),.stall_write(stall_write),.read_delay(32'd5),
  .epoch(32'd0),.awaddr(awaddr),.awvalid(awvalid),.awready(awready),.wdata(wdata),.wvalid(wvalid),.wready(wready),
  .araddr(araddr),.arvalid(arvalid),.arready(arready),.rdata(rdata),.rvalid(rvalid),.rready(rready),
  .pending(pending),.response_epoch(response_epoch),.aw_count(aw_count),.w_count(w_count),
  .ar_count(ar_count),.r_count(r_count),.old_r_count(old_r_count));
 integer fd,fu,ft,fs,cycles=0,bytes_count=0,uart_bytes=0,case_id=0,active_seed=0;
 integer sof_accept=0,writer_begin=0,last_reject=0,full_cycles=0,rejects=0,aborts=0;
 integer fault_crop=0,fault_sof_accept=0,fault_writer_begin=0,fault_last_reject=0;
 integer fault_full=0,fault_rejects=0,fault_aborts=0,fault_pub_base=0,clean_done=0;
 integer fault_slot=-1,recovery_inputs=0,result_fail=0,post_release_writer=0;
 // T10.b12-r1-last T7: SOF beats rejected by the full CDC FIFO (head-of-line
 // deadlock probe).  Counted at the real FIFO write port, no force.
 integer sof_reject=0,t7_drain_cycles=0;
 reg fault_active=0;reg [2047:0] out_path,uart_path,trace_path,stat_path;
 task state_log;input [255:0] tag;
 begin
  $fwrite(ft,"EVENT tag=%0s cycle=%0d seed=%0d stall=%0d cap=%0d rawpub=%0d enc=%0d exp=%0d rawdrop=%0d cmpdrop=%0d geom=%0d err=%0d raw_active=%0d writer=%0d wcnt=%0d nbytes=%0d skid=%0d skidlast=%0d skip=%0d begin_pend=%0d slot0=%0d slot1=%0d fifo_valid=%0d fifo_ready=%0d fifo_sof=%0d fifo_last=%0d fifo_abort=%0d full=%0d abort_hold=%0d raw_abort_cnt=%0d begin_ok=%0d begin_deny=%0d aw=%0d w=%0d\n",
   tag,cycles,active_seed,stall_write,cap,rawpub,enc,exp,rawdrop,cmpdrop,geom,err,dut.raw_active,
   dut.u_raw_store.wr_active,dut.u_raw_store.wcnt,dut.u_raw_store.nbytes,dut.skid_valid,dut.skid_last,
   dut.skip_frame,dut.begin_pend,dut.u_raw_store.slot_st[0],dut.u_raw_store.slot_st[1],dut.fifo_valid,
   dut.fifo_ready,dut.e_sof,dut.e_last,dut.e_abort,dut.u_cam_fifo.full,dut.abort_hold,dut.raw_abort_cnt,
   dut.raw_begin_ok,dut.raw_begin_deny,aw_count,w_count);
 end endtask
 always @(posedge clk_cam) if(rst_n) begin
  if(dut.u_cam_fifo.full) begin full_cycles=full_cycles+1;if(fault_active)fault_full=fault_full+1;end
  if(dut.crop_valid) begin
   if(fault_active)fault_crop=fault_crop+1;
   $fwrite(ft,"CROP cycle=%0d seed=%0d sof=%0d last=%0d valid=%0d ready=%0d full=%0d raw_active=%0d writer=%0d\n",
    cycles,active_seed,dut.crop_sof,dut.crop_last,dut.u_cam_fifo.w_valid,dut.u_cam_fifo.w_ready,dut.u_cam_fifo.full,dut.raw_active,dut.u_raw_store.wr_active);
   if(dut.crop_sof&&dut.u_cam_fifo.w_valid&&dut.u_cam_fifo.w_ready) begin
    sof_accept=sof_accept+1;if(fault_active)fault_sof_accept=fault_sof_accept+1;
   end
   if(dut.u_cam_fifo.w_valid&&!dut.u_cam_fifo.w_ready) begin
    rejects=rejects+1;if(fault_active)fault_rejects=fault_rejects+1;
    if(dut.crop_last) begin
     last_reject=last_reject+1;
     if(fault_active) begin
      fault_last_reject=fault_last_reject+1;
      if(fault_sof_accept!=1||fault_writer_begin!=1||!dut.u_raw_store.wr_active||!dut.u_cam_fifo.full)
       $fatal(1,"LAST_REJECT_PRECONDITION_MISSING");
      state_log("last_rejected");
     end
    end
   end
  end
  if(dut.crop_abort) begin aborts=aborts+1;if(fault_active)fault_aborts=fault_aborts+1;end
  if(dut.crop_sof&&dut.u_cam_fifo.w_valid&&!dut.u_cam_fifo.w_ready) begin
   sof_reject=sof_reject+1;
   $fwrite(ft,"SOF_REJECT cycle=%0d seed=%0d full=%0d\n",cycles,active_seed,dut.u_cam_fifo.full);
  end
 end
 always @(posedge clk_a1) begin
  cycles=cycles+1;
  if(cycles>400000) begin state_log("watchdog");$fatal(1,"TB_WATCHDOG");end
  if(rst_n) begin
   if(dut.begin_hs) begin
    writer_begin=writer_begin+1;
    if(fault_active) begin fault_writer_begin=fault_writer_begin+1;fault_slot=dut.u_raw_store.free_slot;end
    $fwrite(ft,"WRITER_BEGIN cycle=%0d seed=%0d slot=%0d fault=%0d\n",cycles,active_seed,dut.u_raw_store.free_slot,fault_active);
   end
   if(dut.raw_abort) $fwrite(ft,"RAW_ABORT cycle=%0d seed=%0d writer=%0d\n",cycles,active_seed,dut.u_raw_store.wr_active);
   if(awvalid&&awready&&wvalid&&wready) $fwrite(ft,"DDR_WRITE cycle=%0d seed=%0d addr=%0d rawpub=%0d\n",cycles,active_seed,awaddr,rawpub);
   if(byte_valid) begin $fwrite(fd,"%0d\n",byte_data);bytes_count=bytes_count+1;end
  end
 end
 // Decode actual 8N1 wire as independent accounting of debug capture.
 integer ub;reg [7:0] serial_data;
 initial forever begin
  @(negedge txd);
  if(rst_n) begin
   repeat(2) @(negedge clk_uart);
   if(txd!==1'b0)$fatal(1,"UART_BAD_START");
   for(ub=0;ub<8;ub=ub+1)begin repeat(UART_DIV)@(negedge clk_uart);serial_data[ub]=txd;end
   repeat(UART_DIV)@(negedge clk_uart);
   if(txd!==1'b1)$fatal(1,"UART_BAD_STOP");
   $fwrite(fu,"%0d\n",serial_data);uart_bytes=uart_bytes+1;
  end
 end
 task drive_frame;input integer seed;
  integer y,g;reg [31:0] st;reg [9:0] q[0:3];
  begin
   active_seed=seed;$fwrite(ft,"SOURCE seed=%0d cycle=%0d\n",seed,cycles);
   @(negedge clk_cam);inf=1;vs=1;st=32'h12345678^seed;
   for(y=0;y<ROI_Y+H;y=y+1)begin
    @(negedge clk_cam);il=1;pv=0;
    for(g=0;g<CG;g=g+1)begin
     st=st^(st<<13);st=st^(st>>17);st=st^(st<<5);
     q[0]=st[9:0];q[1]=st[19:10];q[2]=st[29:20];q[3]=st[31:22];
     pix={q[3][1:0],q[2][1:0],q[1][1:0],q[0][1:0],q[3][9:2],q[2][9:2],q[1][9:2],q[0][9:2]};
     pv=1;@(negedge clk_cam);
    end
    pv=0;il=0;repeat(12)@(negedge clk_cam);
   end
   inf=0;vs=0;repeat(16)@(negedge clk_cam);
   $fwrite(ft,"SOURCE_END seed=%0d cycle=%0d\n",seed,cycles);
  end
 endtask
 task settle_uart;begin repeat(100)@(negedge clk_a1);while(dut.u_export.uart_busy)@(negedge clk_a1);repeat(20)@(negedge clk_a1);end endtask
 task finish_case;
 begin
  settle_uart;state_log("final");
  $fwrite(fs,"STAT case=%0d w=%0d h=%0d cap=%0d rawpub=%0d enc=%0d exp=%0d rawdrop=%0d cmpdrop=%0d geom=%0d err=%0d reads=%0d dups=%0d bytes=%0d uart_bytes=%0d sof_accept=%0d writer_begin=%0d last_reject=%0d full_cycles=%0d rejects=%0d aborts=%0d clean_done=%0d fault_crop=%0d fault_sof_accept=%0d fault_writer_begin=%0d fault_last_reject=%0d fault_full=%0d fault_rejects=%0d fault_aborts=%0d fault_slot=%0d fault_pub_base=%0d post_release_writer=%0d recovery_inputs=%0d writer_final=%0d slot0=%0d slot1=%0d raw_abort_cnt=%0d begin_deny=%0d result_fail=%0d cycles=%0d sof_reject=%0d t7_drain=%0d\n",
   case_id,W,H,cap,rawpub,enc,exp,rawdrop,cmpdrop,geom,err,reads,dups,bytes_count,uart_bytes,sof_accept,writer_begin,last_reject,full_cycles,rejects,aborts,clean_done,fault_crop,fault_sof_accept,fault_writer_begin,fault_last_reject,fault_full,fault_rejects,fault_aborts,fault_slot,fault_pub_base,post_release_writer,recovery_inputs,dut.u_raw_store.wr_active,dut.u_raw_store.slot_st[0],dut.u_raw_store.slot_st[1],dut.raw_abort_cnt,dut.raw_begin_deny,result_fail,cycles,sof_reject,t7_drain_cycles);
  $fclose(fd);$fclose(fu);$fclose(ft);$fclose(fs);
  $display("CASE_RESULT case=%0d fail=%0d clean=%0d last_rejected=%0d rawpub=%0d exported=%0d writer=%0d",case_id,result_fail,clean_done,fault_last_reject,rawpub,exp,dut.u_raw_store.wr_active);$finish;
 end endtask
 integer t,i;
 initial begin
  if(!$value$plusargs("CASE=%d",case_id))case_id=0;
  if(!$value$plusargs("OUT=%s",out_path))out_path="capture.dec";
  if(!$value$plusargs("UART=%s",uart_path))uart_path="uart.dec";
  if(!$value$plusargs("TRACE=%s",trace_path))trace_path="trace.txt";
  if(!$value$plusargs("STAT=%s",stat_path))stat_path="stats.txt";
  fd=$fopen(out_path,"w");fu=$fopen(uart_path,"w");ft=$fopen(trace_path,"w");fs=$fopen(stat_path,"w");
  if(!fd||!fu||!ft||!fs)$fatal(1,"OPEN_FAIL");
  repeat(24)@(negedge clk_a1);rst_n=1;repeat(50)@(negedge clk_a1);state_log("start");
  drive_frame(11);
  t=0;while(exp<1&&t<100000)begin @(negedge clk_a1);t=t+1;end
  settle_uart;
  if(exp!=1||rawpub!=1||enc!=1||cap!=1||geom!=0||err!=0||rejects!=0||aborts!=0||bytes_count==0||bytes_count!=uart_bytes)
   $fatal(1,"CLEAN_CONTROL_FAILED");
  clean_done=1;state_log("clean_valid");
  if(case_id==0)finish_case;
  if(case_id==2)begin
   // T10.b12-r1-last T7: the CDC FIFO is already full when the next frame
   // starts, so the SOF beat itself is rejected.  The frame's data beats and
   // the sticky loss-abort beat must drain in order without a head-of-line
   // deadlock and the following good frames must publish.
   stall_write=1;fault_active=1;state_log("t7_stall_on");
   drive_frame(100);fault_active=0;
   drive_frame(101);
   if(sof_reject<1)$fatal(1,"T7_NO_SOF_REJECT");
   if(rawpub!=1)$fatal(1,"T7_DAMAGED_FRAME_PUBLISHED");
   state_log("t7_sof_rejected");
   stall_write=0;
   t=0;while(dut.u_raw_store.wr_active&&t<20000)begin @(negedge clk_a1);t=t+1;end
   t7_drain_cycles=t;repeat(2000)@(negedge clk_a1);state_log("t7_drained");
   if(dut.u_raw_store.wr_active)$fatal(1,"T7_STORE_STILL_WRITING");
   for(i=0;i<2;i=i+1)begin drive_frame(1000+i);recovery_inputs=recovery_inputs+1;repeat(20000)@(negedge clk_a1);end
   t=0;while(exp<3&&t<120000)begin @(negedge clk_a1);t=t+1;end
   if(exp!=3||rawpub!=3||geom!=0||dut.u_raw_store.wr_active)begin
    result_fail=1;state_log("T7_FAIL");
   end
   finish_case;
  end
  if(case_id!=1)$fatal(1,"BAD_CASE");
  fault_pub_base=rawpub;stall_write=1;fault_active=1;
  drive_frame(100);fault_active=0;state_log("fault_stalled");
  if(fault_crop!=W*H/4||fault_sof_accept!=1||fault_writer_begin!=1||fault_last_reject!=1||fault_full==0||fault_aborts!=0||geom!=0)
   $fatal(1,"FAULT_PRECONDITIONS_MISSING");
  stall_write=0;repeat(2000)@(negedge clk_a1);post_release_writer=dut.u_raw_store.wr_active;state_log("released_drained");
  if(rawpub!=fault_pub_base)$fatal(1,"DAMAGED_FRAME_PUBLISHED");
  for(i=0;i<2;i=i+1)begin drive_frame(1000+i);recovery_inputs=recovery_inputs+1;repeat(10000)@(negedge clk_a1);end
  // Bound is 120,000 A1 cycles after the final known-good frame. Independent
  // positive preconditions above prevent an empty/timeout stimulus false fail.
  t=0;while(exp<3&&t<120000)begin @(negedge clk_a1);t=t+1;end
  if(exp<3||dut.u_raw_store.wr_active||rawpub!=3)begin
   result_fail=1;state_log("DUT_FAIL_ORPHAN_AFTER_LOST_LAST");
  end
  finish_case;
 end
endmodule
