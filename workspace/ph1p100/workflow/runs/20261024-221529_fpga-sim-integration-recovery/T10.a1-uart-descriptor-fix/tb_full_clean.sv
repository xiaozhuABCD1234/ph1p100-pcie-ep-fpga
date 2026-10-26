`timescale 1ns/1ps
module tb_full_clean # (parameter integer W=8, H=2, MAX_CYCLES=1500000);
 localparam CAM_W=W+8, CAM_H=8, ROI_X=4, ROI_Y=2, CG=CAM_W/4;
 reg clk_cam=0, clk_a1=0, rst_n=0;
 always #2.6665 clk_cam=~clk_cam;
 initial begin #1.7; forever #2.6665 clk_a1=~clk_a1; end
 wire clk_uart=clk_a1; // r5 exporter UART has a same-clock contract.
 reg [39:0] pix=0;
 reg pv=0, il=0, inf=0, vs=0;
 wire [31:0] awaddr, araddr;
 wire awvalid,awready,wvalid,wready,arvalid,arready,rvalid,rready;
 wire [255:0] wdata,rdata;
 wire [7:0] byte_data; wire byte_valid,txd;
 wire [31:0] cap,enc,exp,expbytes,rawpub,rawdrop,cmpdrop,geom,err,reads,dups;
 camera_a1_uart_top #(.CAM_W(CAM_W),.CAM_H(CAM_H),.ROI_X(ROI_X),.ROI_Y(ROI_Y),
  .W(W),.H(H),.UART_DIV(4),.FIFO_AW(2)) dut(
  .clk_cam(clk_cam),.clk_a1(clk_a1),.clk_uart(clk_uart),.rst_n(rst_n),
  .i_a_pixel(pix),.i_a_pixel_valid(pv),.i_a_in_line(il),.i_a_in_frame(inf),.i_a_vsync(vs),
  .o_ddr_awaddr(awaddr),.o_ddr_awvalid(awvalid),.o_ddr_awready(awready),
  .o_ddr_wdata(wdata),.o_ddr_wvalid(wvalid),.o_ddr_wready(wready),
  .o_ddr_araddr(araddr),.o_ddr_arvalid(arvalid),.o_ddr_arready(arready),
  .i_ddr_rdata(rdata),.i_ddr_rvalid(rvalid),.o_ddr_rready(rready),
  .o_uart_txd(txd),.o_dbg_byte(byte_data),.o_dbg_byte_valid(byte_valid),
  .o_st_cap_frames(cap),.o_st_enc_frames(enc),.o_st_exported(exp),.o_st_export_bytes(expbytes),
  .o_st_raw_pub(rawpub),.o_st_raw_drop(rawdrop),.o_st_cmp_drop(cmpdrop),
  .o_st_geom_err(geom),.o_st_errors(err),.o_st_read_words(reads),.o_st_dup_words(dups));
 reg stall_write=0; reg [31:0] epoch=0,read_delay=5;
 wire pending; wire [31:0] response_epoch,aw_count,w_count,ar_count,r_count,old_r_count;
 ddr_recovery_model mem(.clk(clk_a1),.dut_rst_n(rst_n),.stall_write(stall_write),.read_delay(read_delay),
  .epoch(epoch),.awaddr(awaddr),.awvalid(awvalid),.awready(awready),.wdata(wdata),.wvalid(wvalid),.wready(wready),
  .araddr(araddr),.arvalid(arvalid),.arready(arready),.rdata(rdata),.rvalid(rvalid),.rready(rready),
  .pending(pending),.response_epoch(response_epoch),.aw_count(aw_count),.w_count(w_count),
  .ar_count(ar_count),.r_count(r_count),.old_r_count(old_r_count));
 integer fd,ft,fs,cycles=0,bytes_count=0,raw_ingress=0,cmp_ingress=0;
 integer raw_aw=0,cmp_aw=0,full_cycles=0,fifo_rejected=0,abort_seen=0;
 integer case_id=0,inject_hit=0,post_reset_zero=0,good_sent=0,last_fe=0;
 integer geom_before=0,rawdrop_before=0,cmpdrop_before=0,err_before=0;
 integer fault_geom=0,fault_rawdrop=0,fault_cmpdrop=0,fault_err=0;
 integer recovered=0,recovery_elapsed=0,active_seed=0;
 reg [2047:0] out_path,trace_path,stat_path;
 task state_log; input [255:0] tag;
 begin
  $fwrite(ft,"EVENT tag=%0s cycles=%0d epoch=%0d seed=%0d raw_ingress=%0d cmp_ingress=%0d raw_aw=%0d cmp_aw=%0d aw=%0d w=%0d raw_active=%0d raw_wcnt=%0d cmp_active=%0d cmp_wcnt=%0d rawpub=%0d enc=%0d exp=%0d geom=%0d rawdrop=%0d cmpdrop=%0d err=%0d fifo_full=%0d rejected=%0d slots0=%0d slots1=%0d fstate=%0d pending=%0d rvalid=%0d response_epoch=%0d\n",
   tag,cycles,epoch,active_seed,raw_ingress,cmp_ingress,raw_aw,cmp_aw,aw_count,w_count,
   dut.u_raw_store.wr_active,dut.u_raw_store.wcnt,dut.u_cmp_store.wr_active,dut.u_cmp_store.wcnt,
   rawpub,enc,exp,geom,rawdrop,cmpdrop,err,full_cycles,fifo_rejected,
   dut.u_raw_store.slot_st[0],dut.u_raw_store.slot_st[1],dut.fstate,pending,rvalid,response_epoch);
 end endtask
 always @(posedge clk_cam) if(rst_n) begin
  if(dut.u_cam_fifo.full) full_cycles=full_cycles+1;
  if(dut.crop_valid&&!dut.u_cam_fifo.w_ready) fifo_rejected=fifo_rejected+1;
  if(dut.crop_abort) abort_seen=abort_seen+1;
 end
 always @(posedge clk_a1) begin
  cycles=cycles+1;
  if(rst_n) begin
   if(dut.skid_valid&&dut.raw_wr_ready) raw_ingress=raw_ingress+1;
   if(dut.a1_out_valid&&dut.a1_out_ready) cmp_ingress=cmp_ingress+1;
   if(dut.raw_awvalid&&dut.raw_awready&&dut.raw_wvalid&&dut.raw_wready) raw_aw=raw_aw+1;
   if(dut.cmp_awvalid&&dut.cmp_awready&&dut.cmp_wvalid&&dut.cmp_wready) cmp_aw=cmp_aw+1;
   if(byte_valid) begin $fwrite(fd,"%0d\n",byte_data); bytes_count=bytes_count+1; end
   if(rvalid&&rready&&response_epoch!=epoch) $fwrite(ft,"OLD_RESPONSE cycles=%0d response_epoch=%0d epoch=%0d\n",cycles,response_epoch,epoch);
  end
  if(cycles>MAX_CYCLES) begin state_log("watchdog"); $fatal(1,"CYCLE_WATCHDOG"); end
 end
 task drive_frame;
  input integer seed; input integer bad;
  integer y,g,j,rej0; reg [31:0] st; reg [9:0] q[0:3];
  begin
   active_seed=seed; rej0=fifo_rejected;
   $fwrite(ft,"SOURCE seed=%0d epoch=%0d bad=%0d cycles=%0d\n",seed,epoch,bad,cycles);
   @(negedge clk_cam); inf=1; vs=1; st=32'h12345678 ^ seed;
   for(y=0;y<ROI_Y+H;y=y+1) begin
    @(negedge clk_cam); il=1; pv=0;
    for(g=0;g<CG;g=g+1) begin
     st=st^(st<<13); st=st^(st>>17); st=st^(st<<5);
     q[0]=st[9:0];q[1]=st[19:10];q[2]=st[29:20];q[3]=st[31:22];
     pix={q[3][1:0],q[2][1:0],q[1][1:0],q[0][1:0],q[3][9:2],q[2][9:2],q[1][9:2],q[0][9:2]};
     pv=!(bad && y==ROI_Y && g==CG-1);
     @(negedge clk_cam);
    end
    pv=0;il=0; repeat(12) @(negedge clk_cam);
   end
   inf=0;vs=0; last_fe=cycles;
   repeat(16) @(negedge clk_cam);
   $fwrite(ft,"SOURCE_END seed=%0d epoch=%0d bad=%0d rejected_delta=%0d cycles=%0d\n",seed,epoch,bad,fifo_rejected-rej0,cycles);
  end
 endtask
 task snapshot_fault;
 begin
  fault_geom=geom-geom_before;fault_rawdrop=rawdrop-rawdrop_before;
  fault_cmpdrop=cmpdrop-cmpdrop_before;fault_err=err-err_before;
  state_log("fault_observed");
 end endtask
 task reset_now;
  input integer which;
  begin
   state_log("reset_hit");
   if(which==1 && !(raw_aw>0 && rawpub==0 && dut.u_raw_store.wr_active)) $fatal(1,"RAW_RESET_NOT_MIDWRITE");
   if(which==2 && !(cmp_aw>0 && enc==0 && dut.u_cmp_store.wr_active)) $fatal(1,"ENC_RESET_NOT_MIDWRITE");
   inject_hit=1; rst_n=0; epoch=epoch+1;
   repeat(24) @(negedge clk_a1);
   if(rawpub!=0||enc!=0||exp!=0||geom!=0||rawdrop!=0||cmpdrop!=0||err!=0) $fatal(1,"RESET_COUNTERS_NOT_ZERO");
   if(dut.u_raw_store.slot_st[0]!=0||dut.u_raw_store.slot_st[1]!=0||dut.u_cmp_store.slot_st[0]!=0||dut.u_cmp_store.slot_st[1]!=0) $fatal(1,"RESET_OWNERSHIP");
   post_reset_zero=1; state_log("reset_asserted");
   rst_n=1;repeat(50) @(negedge clk_a1);state_log("reset_released");
  end
 endtask
 integer i,t,start_exp;
 initial begin
  if(!$value$plusargs("CASE=%d",case_id)) case_id=0;
  if(!$value$plusargs("OUT=%s",out_path)) out_path="capture.dec";
  if(!$value$plusargs("TRACE=%s",trace_path)) trace_path="trace.txt";
  if(!$value$plusargs("STAT=%s",stat_path)) stat_path="stats.txt";
  fd=$fopen(out_path,"w");ft=$fopen(trace_path,"w");fs=$fopen(stat_path,"w");
  if(!fd||!ft||!fs) $fatal(1,"OPEN_FAIL");
  repeat(24) @(negedge clk_a1);rst_n=1;repeat(50) @(negedge clk_a1);
  state_log("start");
  if(case_id==1) begin
   fork
    drive_frame(11,0);
    begin
     t=0;while(!(raw_aw>0 && rawpub==0 && dut.u_raw_store.wr_active) && t<100000) begin @(negedge clk_a1);t=t+1;end
     if(t==100000) $fatal(1,"RAW_INJECTION_MISS"); reset_now(1);
    end
   join
  end else if(case_id==2) begin
   drive_frame(12,0);
   t=0;while(!(cmp_aw>0 && enc==0 && dut.u_cmp_store.wr_active) && t<100000) begin @(negedge clk_a1);t=t+1;end
   if(t==100000) $fatal(1,"ENC_INJECTION_MISS");reset_now(2);
  end else if(case_id==3) begin
   geom_before=geom;rawdrop_before=rawdrop;cmpdrop_before=cmpdrop;err_before=err;
   drive_frame(13,1);repeat(500) @(negedge clk_a1);snapshot_fault;
   if(geom<=geom_before||abort_seen==0||rawpub!=0||exp!=0) $fatal(1,"BAD_FRAME_INJECTION_MISS");
   inject_hit=1;
  end else if(case_id==4) begin
   geom_before=geom;rawdrop_before=rawdrop;cmpdrop_before=cmpdrop;err_before=err;
   stall_write=1;
   for(i=0;i<8;i=i+1) drive_frame(100+i,0);
   state_log("overflow_stalled");
   if(full_cycles==0||fifo_rejected==0) $fatal(1,"OVERFLOW_INJECTION_MISS");
   inject_hit=1; stall_write=0;repeat(10000) @(negedge clk_a1);snapshot_fault;
   state_log("overflow_released");
  end
  // At most four GOOD recovery inputs. Each has a unique epoch/seed and a
  // generous bounded interval; after the final FE the hard limit is 1e6.
  start_exp=exp;
  for(i=0;i<4;i=i+1) begin
   drive_frame(1000+epoch*100+i,0);good_sent=good_sent+1;
   repeat(10000) @(negedge clk_a1);
  end
  t=cycles-last_fe;
  while((exp-start_exp<4)&&t<1000000) begin @(negedge clk_a1);t=cycles-last_fe;end
  recovered=exp-start_exp;recovery_elapsed=cycles-last_fe;
  repeat(20000) @(negedge clk_a1);state_log("final");
  $fwrite(fs,"STAT case=%0d w=%0d h=%0d epoch=%0d inject_hit=%0d post_reset_zero=%0d good_sent=%0d recovered=%0d recovery_elapsed=%0d cap=%0d enc=%0d exported=%0d raw_pub=%0d raw_drop=%0d cmp_drop=%0d geom=%0d err=%0d read_words=%0d dup_words=%0d old_r_count=%0d bytes=%0d aw=%0d wbeats=%0d raw_aw=%0d cmp_aw=%0d raw_ingress=%0d cmp_ingress=%0d fifo_full=%0d fifo_rejected=%0d abort_seen=%0d fault_geom=%0d fault_rawdrop=%0d fault_cmpdrop=%0d fault_err=%0d cycles=%0d\n",
   case_id,W,H,epoch,inject_hit,post_reset_zero,good_sent,recovered,recovery_elapsed,cap,enc,exp,rawpub,rawdrop,cmpdrop,geom,err,reads,dups,old_r_count,bytes_count,aw_count,w_count,raw_aw,cmp_aw,raw_ingress,cmp_ingress,full_cycles,fifo_rejected,abort_seen,fault_geom,fault_rawdrop,fault_cmpdrop,fault_err,cycles);
  $fclose(fd);$fclose(ft);$fclose(fs);
  if(case_id!=0) $fatal(1,"ONLY_CLEAN_AUTHORIZED_IN_THIS_PACKAGE");
  if(case_id!=0 && inject_hit!=1) $fatal(1,"INJECTION_NOT_HIT");
  if(recovered!=4||recovery_elapsed>1000000) $fatal(1,"RECOVERY_BOUND_FAIL");
  if(case_id==4 && fault_rawdrop+fault_cmpdrop+fault_err==0) $fatal(1,"OVERFLOW_COUNTER_MISSING");
  if(dups!=0||old_r_count!=0) $fatal(1,"DUPLICATE_OR_OLD_EPOCH_RESPONSE");
  $display("CASE_PASS case=%0d recovered=%0d",case_id,recovered);$finish;
 end
endmodule
