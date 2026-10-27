`timescale 1ns/1ps
module tb_production_sync;
 reg clk=0,ca=0,cb=0;always #10 clk=~clk;
 always #7 ca=~ca;initial begin #3;forever #9 cb=~cb;end
 reg por=0,start=0,abort_req=0;
 reg va=0,vb=0,da=0,db=0;reg [31:0] wa=0,wb=0;
 tri1 sda_a,sda_b;wire scl_a,scl_b;
 integer nack_a=-1,nack_b=-1,txa,txb,case_id=0,cycles=0,epoch=0;
 reg [7:0] read_xor=0;integer reads_a,reads_b;reg local_abort=0;reg [1:0] mode=1;
 reg rel_valid=0,rel_camera=0,rel_slot=0;reg [31:0] rel_epoch=0,rel_session=0,rel_seq=0;
 integer releases_a=0,releases_b=0;reg [31:0] prev_pass=0,prev_fail=0;
 integer fid_a=0,fid_b=0,pubs_a=0,pubs_b=0,events;
 reg [31:0] old_seq_a=0,old_seq_b=0;reg [24:0] held;reg stalled=0;
 integer accepts=0,responses=0;
 ph1p_pcie_ep_top #(.DBG_CTRL_DEFAULT_EN(1),.SYNC_ENABLE(1),.DUAL_LOCAL_EN(1),.LOCAL_TIMEOUT(2000),
  .CAM_I2C_DIV(14),.CAM_POWER_CYCLES(32),.CAM_CSI_RELEASE_CYCLES(8),
  .SYNC_WAIT_CYCLES(120),.SYNC_FRAME_TIMEOUT(30000),.SYNC_PAIR_WINDOW(64),
  .SYNC_I2C_TIMEOUT(5000),.CAMDDR_W(8),.CAMDDR_H(2),
  .CAMDDR_X0(0),.CAMDDR_Y0(0),.CAMDDR_SKIP_ROWS(0)) dut(
  .consumer_epoch(epoch),.consumer_mode(mode),.local_abort(local_abort),
  .rel_valid(rel_valid),.rel_camera_id(rel_camera),.rel_slot_id(rel_slot),.rel_epoch(rel_epoch),.rel_session(rel_session),.rel_capture_seq(rel_seq),.rel_status(3'd2),
  .a_desc_ready(1'b0),.b_desc_ready(1'b0),.ext_arvalid(1'b0),.ext_arid(4'd0),.ext_araddr(29'd0),.ext_arlen(8'd0),.ext_arsize(3'd5),.ext_arburst(2'd1),.ext_rready(1'b0),
  .sync_start(start),.sync_abort(abort_req),.sim_clk_a(ca),.sim_clk_b(cb),
  .sim_valid_a(va),.sim_valid_b(vb),.sim_done_a(da),.sim_done_b(db),.sim_data_a(wa),.sim_data_b(wb),
  .sys_clk(clk),.pcie_power_on_rst(por),.pcie_mperst(por),.ref_pad_clk_p(clk),.ref_pad_clk_n(~clk),
  .pcie_rx_p(2'b0),.pcie_rx_n(2'b0),.user_int_trigger(1'b0),
  .mipi_a_clk_hs_p(ca),.mipi_a_clk_hs_n(~ca),.mipi_b_clk_hs_p(cb),.mipi_b_clk_hs_n(~cb),
  .mipi_a_data_hs_p(4'b0),.mipi_a_data_hs_n(4'b0),.mipi_b_data_hs_p(4'b0),.mipi_b_data_hs_n(4'b0),
  .cam_a_scl(scl_a),.cam_a_sda(sda_a),.cam_b_scl(scl_b),.cam_b_sda(sda_b));
 sensor_i2c #(.CAMERA(0)) sa(por,scl_a,sda_a,nack_a,read_xor,16'h3000,txa,reads_a);
 sensor_i2c #(.CAMERA(1)) sb(por,scl_b,sda_b,nack_b,read_xor,16'h3000,txb,reads_b);
 task check(input bit ok,input string why);
  if(!ok) begin $display("T08_FAIL case=%0d epoch=%0d cycle=%0d %s",case_id,epoch,cycles,why);$fatal(1);end
 endtask
 task ticks(input integer n);repeat(n) @(negedge clk);endtask
 task reset_all;
  por=0;start=0;abort_req=0;va=0;vb=0;da=0;db=0;nack_a=-1;nack_b=-1;
  local_abort=0;
  dut.u_ddr3_mc_0.block_ar=0;dut.u_ddr3_mc_0.drop_reads=0;dut.u_ddr3_mc_0.read_delay=0;dut.u_ddr3_mc_0.corrupt_payload=0;
  ticks(12);epoch=epoch+1;$fdisplay(events,"EPOCH %0d %0t",epoch,$time);por=1;ticks(20);
 endtask
 task configured;
  wait(dut.w_a_cfg_done && dut.w_b_cfg_done);ticks(4);
  check(txa==201 && txb==201,"complete pin-level initialization before ownership transfer");
  check(reads_a>40 && reads_a==reads_b,"masked random reads completed on pins");
  $fdisplay(events,"READBACK_HIT %0d %0d",reads_a,reads_b);
  ticks(200);check(txa==201 && txb==201,"no automatic or periodic sensor start");
 endtask
 task start_it;
  $fdisplay(events,"START %0d %0t %0d %0d",epoch,$time,txa,txb);
  start=1;ticks(1);start=0;
  wait(dut.g_sync_ctrl.u_sync.control.measurement_enable);ticks(8);
  check(!dut.sync_ready,"no ready before warmup");
 endtask
 function automatic [7:0] ecc(input [23:0] d);
  reg [7:0] e;
  begin e=0;
   e[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
   e[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[22]^d[23];
   e[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
   e[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
   e[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
   e[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];
   ecc=e;end
 endfunction
 function automatic [15:0] crc16_byte(input [15:0] c,input [7:0] b);
  integer k;reg [15:0] r;
  begin r=c;for(k=0;k<8;k=k+1) begin
   if(r[0]^b[k]) r=(r>>1)^16'h8408;else r=r>>1;end crc16_byte=r;end
 endfunction
 task automatic put(input integer cam,input [31:0] data);
  if(cam==0) begin @(negedge ca);va=1;wa=data;@(negedge ca);va=0;end
  else begin @(negedge cb);vb=1;wb=data;@(negedge cb);vb=0;end
 endtask
 task automatic gap(input integer cam);
  if(cam==0) repeat(8) @(negedge ca);else repeat(8) @(negedge cb);
 endtask
 task automatic short_packet(input integer cam,dt,id);
  reg [23:0] h;
  begin h={id[15:0],dt[7:0]};put(cam,{ecc(h),h});gap(cam);end
 endtask
 task automatic line_packet(input integer cam,fid,row);
  reg [7:0] data[0:11];reg [15:0] c;reg [23:0] h;integer k;
  begin c=16'hffff;for(k=0;k<10;k=k+1) begin
   data[k]=(cam*97+fid*13+row*23+k*7)&255;c=crc16_byte(c,data[k]);end
   data[10]=c[7:0];data[11]=c[15:8];h={16'd10,8'h2b};put(cam,{ecc(h),h});
   for(k=0;k<12;k=k+4) put(cam,{data[k+3],data[k+2],data[k+1],data[k]});gap(cam);
  end
 endtask
 task automatic frame(input integer cam,fid);
  if(cam==0) fid_a=fid;else fid_b=fid;
  short_packet(cam,0,fid);line_packet(cam,fid,0);line_packet(cam,fid,1);short_packet(cam,1,fid);
 endtask
 task pair_frame(input integer fid);
  fork frame(0,fid);frame(1,fid);join
  ticks(6000);
 endtask
 task warmup;
  integer k;
  begin
   for(k=1;k<=8;k=k+1) begin pair_frame(k);check(!dut.sync_ready,"first eight pairs not ready");end
   check(dut.sync_warmup==8,"eight actual SOF pairs warmup");pair_frame(9);
   check(dut.sync_ready && dut.sync_locked,"ninth pair ready");
  end
 endtask
 task three_good;
  integer a,b,k;
  begin a=pubs_a;b=pubs_b;
   for(k=10;k<=15;k=k+1) begin pair_frame(k);
    check(pubs_a==a+k-9 && pubs_b==b+k-9,"one exact A/B publication per accepted frame");
    check(dut.local_pass_count>=2*(k-9),"both complete DDR reads and releases before next frame");end
  end
 endtask
 always @(posedge clk) begin
  cycles=cycles+1;
  if(!por) begin old_seq_a=0;old_seq_b=0;pubs_a=0;pubs_b=0;accepts=0;responses=0;stalled=0;end
  else begin
   if(stalled) check(dut.sync_req_valid && {dut.sync_camera,dut.sync_addr,dut.sync_data}===held,"stable stalled request");
   stalled=dut.sync_req_valid&&!dut.sync_req_ready;held={dut.sync_camera,dut.sync_addr,dut.sync_data};
   if(dut.sync_req_valid && dut.sync_req_ready) begin
    check(accepts==responses,"one outstanding owner");accepts=accepts+1;
    $fdisplay(events,"REQ %0d %0t %0d %04x %02x",epoch,$time,dut.sync_camera,dut.sync_addr,dut.sync_data);
   end
   if(dut.sync_a_rsp || dut.sync_b_rsp) begin
    check(!(dut.sync_a_rsp && dut.sync_b_rsp),"exclusive response camera");responses=responses+1;
    check(responses<=accepts,"no duplicate or pre-reset response");
    $fdisplay(events,"RSP %0d %0t %0d %0d",epoch,$time,dut.sync_b_rsp,
      (dut.sync_a_rsp&&dut.sync_a_ok)||(dut.sync_b_rsp&&dut.sync_b_ok));
   end
   if(dut.w_camddr_seq!=old_seq_a) begin
    check(dut.w_camddr_seq==old_seq_a+1,"A publication monotonic single");
    pubs_a=pubs_a+1;old_seq_a=dut.w_camddr_seq;
    dut.u_ddr3_mc_0.dump_frame(0,old_seq_a,dut.w_camddr_base);
    $fdisplay(events,"PUB %0d %0t 0 %0d %08x %0d %0d",epoch,$time,old_seq_a,dut.w_camddr_base,dut.w_camddr_len,fid_a);
   end
   if(dut.w_camddr_b_seq!=old_seq_b) begin
    check(dut.w_camddr_b_seq==old_seq_b+1,"B publication monotonic single");
    pubs_b=pubs_b+1;old_seq_b=dut.w_camddr_b_seq;
    dut.u_ddr3_mc_0.dump_frame(1,old_seq_b,dut.w_camddr_b_base);
    $fdisplay(events,"PUB %0d %0t 1 %0d %08x %0d %0d",epoch,$time,old_seq_b,dut.w_camddr_b_base,dut.w_camddr_b_len,fid_b);
   end
  end
  if(cycles>3000000) $fatal(1,"cycle watchdog");
 end
 initial begin
  events=$fopen("events.log","w");if(!$value$plusargs("CASE=%d",case_id)) case_id=0;
  if(case_id==7) read_xor=2; // non-mask bit variation must be accepted
  if(case_id==6) read_xor=1; // checked standby bit must be rejected
  reset_all();
  if(case_id==6) begin
   wait(dut.w_a_bus_err);ticks(20);check(!dut.w_a_cfg_done&&!dut.sync_ready&&pubs_a==0,"masked bit mismatch rejects config");
   $fdisplay(events,"MASK_REJECT_HIT");read_xor=0;reset_all();
  end
  if(case_id==8 || case_id==9) begin
   wait(dut.u_cfg_a.g_sync.transport.state==1);
   if(case_id==8) force dut.u_cfg_a.g_sync.transport.core_busy=0;
   else begin wait(dut.u_cfg_a.g_sync.transport.core_busy);force dut.u_cfg_a.g_sync.transport.core_busy=1;end
   wait(dut.w_a_bus_err);ticks(20);check(!dut.w_a_cfg_done&&!dut.sync_ready,"transaction timeout safe");
   $fdisplay(events,"I2C_TIMEOUT_HIT %0d",case_id);
   release dut.u_cfg_a.g_sync.transport.core_busy;reset_all();
  end
  configured();
  if(case_id==5) begin
   start=1;ticks(1);start=0;wait(accepts==1 && dut.u_cfg_a.g_sync.transport.core_busy);ticks(2);
   check(accepts==1 && responses==0,"accepted I2C pending before reset");
   $fdisplay(events,"PENDING_RESET_HIT %0d %0t",epoch,$time);reset_all();configured();
  end
  if(case_id==1) begin
   nack_b=txb+3;start=1;ticks(1);start=0;wait(dut.sync_stopped);ticks(20);
   check(!dut.sync_ready && dut.sync_error==2 && pubs_a==0 && pubs_b==0,"last-byte NACK latched and safe cleanup");
   $fdisplay(events,"NACK_HIT %0t",$time);nack_b=-1;
  end
  start_it();warmup();check(pubs_a==0 && pubs_b==0,"ninth frame never admitted in its middle");
  if(case_id==14) begin
   mode=0;ticks(10);check(dut.local_active_mode==0,"idle mode can disable reader");
   pair_frame(60);pair_frame(61);check(dut.local_held==15,"four independent mailboxes hold both slots per camera");
   begin integer a,b;a=pubs_a;b=pubs_b;pair_frame(62);pair_frame(63);
    check(pubs_a==a && pubs_b==b,"full held slots drop complete frames without publication");
    check(dut.cl_writer_bad>0 && dut.b_cl_bad>0,"both protected-slot drop counters increment");end
   mode=2;ticks(10);check(dut.local_active_mode==0 && dut.local_reject_count>0,"active mode change rejected");
   $fdisplay(events,"SATURATION_HIT held=%0d rejects=%0d",dut.local_held,dut.local_reject_count);
   reset_all();mode=1;configured();start_it();warmup();
  end
  if(case_id==15) begin
   mode=2;ticks(10);rel_valid=1;rel_epoch=epoch-1;rel_seq=1;ticks(2);rel_valid=0;ticks(10);
   check(dut.local_held==0 && dut.local_reject_count>0,"old epoch release rejected");
   $fdisplay(events,"STALE_REL_HIT");mode=1;ticks(10);
  end
  if(case_id==2 || case_id==3) begin
   fid_a=77;short_packet(0,0,77);line_packet(0,77,0);
   if(case_id==2) begin
    wait(dut.sync_stopped);ticks(6000);check(!dut.sync_ready && pubs_a==0 && pubs_b==0,"missing B rejects half frame");
    $fdisplay(events,"MISSING_HIT");short_packet(0,1,77);ticks(200);start_it();warmup();
   end else begin wait(dut.u_ddr3_mc_0.w_count>0);$fdisplay(events,"RESET_HIT");reset_all();configured();start_it();warmup();end
  end
  if(case_id>=10 && case_id<=13) begin
   if(case_id==10) dut.u_ddr3_mc_0.corrupt_payload=1;
   if(case_id==11) dut.u_ddr3_mc_0.block_ar=1;
   if(case_id==12) dut.u_ddr3_mc_0.read_delay=100;
   if(case_id==13) dut.u_ddr3_mc_0.drop_reads=1;
   fork
    pair_frame(70);
    begin
     wait(dut.w_ddr_arvalid);
     if(case_id==11) begin ticks(20);local_abort=1;ticks(2);local_abort=0;ticks(50);
       check(dut.local_held!=0 && dut.w_ddr_arvalid,"pending AR retained on abort");dut.u_ddr3_mc_0.block_ar=0;end
     if(case_id==12) begin wait(dut.u_ddr3_mc_0.ar_count>0);ticks(5);local_abort=1;ticks(2);local_abort=0;end
    end
   join
   if(case_id==13) begin
    wait(dut.local_fault!=0);ticks(20);check(dut.local_held!=0 && releases_a==0 && releases_b==0,"missing R locks held ownership");
    $fdisplay(events,"LOCK_HIT");reset_all();configured();start_it();warmup();
   end else begin
    wait(dut.local_held==0);check(dut.local_fail_count>0,"fault safely drains and fails");
    $fdisplay(events,"DRAIN_HIT %0d pass=%0d fail=%0d",case_id,dut.local_pass_count,dut.local_fail_count);
    dut.u_ddr3_mc_0.corrupt_payload=0;dut.u_ddr3_mc_0.read_delay=0;
   end
  end
  three_good();
  if(case_id==4) begin
   abort_req=1;ticks(1);abort_req=0;wait(dut.sync_stopped);ticks(20);check(!dut.sync_ready,"explicit stop");start_it();
   begin integer a,b;a=pubs_a;b=pubs_b;warmup();check(pubs_a==a && pubs_b==b,"restart repeats full warmup");end
   three_good();
  end
  ticks(200);check(accepts==responses,"all accepted I2C requests receive one response");
  check(dut.local_held==0 && dut.local_fault==0,"all published slots safely released");
  check(releases_a>=6 && releases_b>=6,"six complete frames per camera consumed and slots reused");
  $display("T08_PASS case=%0d mismatch=0 A=%0d B=%0d releaseA=%0d releaseB=%0d pass=%0d fail=%0d",case_id,pubs_a,pubs_b,releases_a,releases_b,dut.local_pass_count,dut.local_fail_count);
  $fclose(events);$finish;
 end
 initial begin #60000000;$fatal(1,"simulation time watchdog");end
 // A real command-path mutation: transport and pin slave remain unmodified.
 // The independent pin checker must reject this correctly compiled run.
 initial if($test$plusargs("MUTATE_ROLE")) begin
  wait(dut.sync_req_valid && !dut.sync_camera && dut.sync_addr==16'h30c1);
  force dut.g_sync_ctrl.u_sync.control.reg_data=8'h0e;
  wait(dut.sync_req_valid && dut.sync_req_ready);ticks(2);
  release dut.g_sync_ctrl.u_sync.control.reg_data;
 end

 reg [28:0] ar_held;reg [7:0] arlen_held;reg ar_stall=0;
 always @(posedge dut.w_ddr_dhi_clk) begin
  if(!por) begin releases_a=0;releases_b=0;prev_pass=0;prev_fail=0;ar_stall=0;end
  else begin
   if(ar_stall) check(dut.w_ddr_arvalid && dut.w_ddr_araddr==ar_held && dut.w_ddr_arlen==arlen_held,"AR stable under stall including abort");
   ar_stall=dut.w_ddr_arvalid&&!dut.w_ddr_arready;ar_held=dut.w_ddr_araddr;arlen_held=dut.w_ddr_arlen;
   if(dut.cl_pub_valid) $fdisplay(events,"CLPUB %0d %0t 0 %0d %08x %0d %0d",epoch,$time,dut.cl_pub_seq,dut.cl_pub_base,dut.cl_pub_len,fid_a);
   if(dut.b_cl_pub_valid) $fdisplay(events,"CLPUB %0d %0t 1 %0d %08x %0d %0d",epoch,$time,dut.b_cl_pub_seq,dut.b_cl_pub_base,dut.b_cl_pub_len,fid_b);
   if(dut.cl_release!=0 || dut.b_cl_release!=0) begin
    check(dut.g_dual_local.u_local.outstanding==0 && !dut.g_dual_local.u_local.ar_pending,"no release before all reads drained");
    if(dut.cl_release!=0) releases_a=releases_a+1;
    if(dut.b_cl_release!=0) releases_b=releases_b+1;
    $fdisplay(events,"REL %0d %0t %0d %0d %0d %0d",epoch,$time,dut.cl_release,dut.b_cl_release,dut.local_pass_count,dut.local_fail_count);
   end
   if(dut.g_dual_local.u_local.state==2 && dut.g_dual_local.u_local.c_done && !dut.g_dual_local.u_local.c_busy)
    $fdisplay(events,"CHECK %0t %0d %0d %0d %0d %0d %0d",$time,dut.g_dual_local.u_local.current,
    dut.g_dual_local.u_local.c_error,dut.g_dual_local.u_local.u_checker.identity_bad,dut.g_dual_local.u_local.u_checker.tail_bad,
    dut.g_dual_local.u_local.u_checker.rd_header_crc32,dut.g_dual_local.u_local.u_checker.rd_payload_crc32);
   if(dut.w_ddr_awvalid&&dut.w_ddr_awready) begin
    for(integer i=0;i<4;i=i+1) if(dut.local_held[i])
     check(!(dut.w_ddr_awaddr>=dut.g_dual_local.u_local.q_base[i] && dut.w_ddr_awaddr<dut.g_dual_local.u_local.q_base[i]+4096),"protected complete RAW slot cannot be overwritten");
   end
  end
 end
endmodule
