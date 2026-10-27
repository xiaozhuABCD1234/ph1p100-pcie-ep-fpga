`timescale 1ns/1ps
module tb_production_sync_legacy;
 reg clk=0,ca=0,cb=0;always #10 clk=~clk;
 always #7 ca=~ca;initial begin #3;forever #9 cb=~cb;end
 reg por=0,start=0,abort_req=0;
 reg va=0,vb=0,da=0,db=0;reg [31:0] wa=0,wb=0;
 tri1 sda_a,sda_b;wire scl_a,scl_b;
 integer nack_a=-1,nack_b=-1,txa,txb,case_id=0,cycles=0,epoch=0;
 integer reads_a,reads_b;integer fid_a=0,fid_b=0,pubs_a=0,pubs_b=0,events;
 reg [31:0] old_seq_a=0,old_seq_b=0;reg [24:0] held;reg stalled=0;
 integer accepts=0,responses=0;
 ph1p_pcie_ep_top #(.DBG_CTRL_DEFAULT_EN(1),.SYNC_ENABLE(1),
  .CAM_I2C_DIV(14),.CAM_POWER_CYCLES(32),.CAM_CSI_RELEASE_CYCLES(8),
  .SYNC_WAIT_CYCLES(120),.SYNC_FRAME_TIMEOUT(30000),.SYNC_PAIR_WINDOW(64),
  .SYNC_I2C_TIMEOUT(5000),.CAMDDR_W(8),.CAMDDR_H(2),
  .CAMDDR_X0(0),.CAMDDR_Y0(0),.CAMDDR_SKIP_ROWS(0)) dut(
  .sync_start(start),.sync_abort(abort_req),.sim_clk_a(ca),.sim_clk_b(cb),
  .sim_valid_a(va),.sim_valid_b(vb),.sim_done_a(da),.sim_done_b(db),.sim_data_a(wa),.sim_data_b(wb),
  .sys_clk(clk),.pcie_power_on_rst(por),.pcie_mperst(por),.ref_pad_clk_p(clk),.ref_pad_clk_n(~clk),
  .pcie_rx_p(2'b0),.pcie_rx_n(2'b0),.user_int_trigger(1'b0),
  .mipi_a_clk_hs_p(ca),.mipi_a_clk_hs_n(~ca),.mipi_b_clk_hs_p(cb),.mipi_b_clk_hs_n(~cb),
  .mipi_a_data_hs_p(4'b0),.mipi_a_data_hs_n(4'b0),.mipi_b_data_hs_p(4'b0),.mipi_b_data_hs_n(4'b0),
  .cam_a_scl(scl_a),.cam_a_sda(sda_a),.cam_b_scl(scl_b),.cam_b_sda(sda_b));
 sensor_i2c #(.CAMERA(0)) sa(por,scl_a,sda_a,nack_a,8'd0,16'h3000,txa,reads_a);
 sensor_i2c #(.CAMERA(1)) sb(por,scl_b,sda_b,nack_b,8'd0,16'h3000,txb,reads_b);
 task check(input bit ok,input string why);
  if(!ok) begin $display("T08_FAIL case=%0d epoch=%0d cycle=%0d %s",case_id,epoch,cycles,why);$fatal(1);end
 endtask
 task ticks(input integer n);repeat(n) @(negedge clk);endtask
 task reset_all;
  por=0;start=0;abort_req=0;va=0;vb=0;da=0;db=0;nack_a=-1;nack_b=-1;
  ticks(12);epoch=epoch+1;$fdisplay(events,"EPOCH %0d %0t",epoch,$time);por=1;ticks(20);
 endtask
 task configured;
  wait(dut.w_a_cfg_done && dut.w_b_cfg_done);ticks(4);
  check(txa==201 && txb==201,"complete pin-level initialization before ownership transfer");
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
  ticks(5000);
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
   for(k=10;k<=12;k=k+1) begin pair_frame(k);
    check(pubs_a==a+k-9 && pubs_b==b+k-9,"one exact A/B publication per accepted frame");end
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
  if(cycles>2000000) $fatal(1,"cycle watchdog");
 end
 initial begin
  events=$fopen("events.log","w");if(!$value$plusargs("CASE=%d",case_id)) case_id=0;
  reset_all();configured();
  if(case_id==5) begin
   start=1;ticks(1);start=0;
   wait(accepts==1 && dut.u_cfg_a.g_sync.transport.core_busy);ticks(2);
   check(accepts==1 && responses==0,"accepted I2C pending before reset");
   $fdisplay(events,"PENDING_RESET_HIT %0d %0t accepts=%0d responses=%0d",epoch,$time,accepts,responses);
   reset_all();configured();
   check(accepts==0 && responses==0,"old pending response absent after full reinitialization");
  end
  if(case_id==1) begin
   nack_b=txb+3;start=1;ticks(1);start=0;wait(dut.sync_stopped);ticks(20);
   check(!dut.sync_ready && dut.sync_error==2 && pubs_a==0 && pubs_b==0,"last-byte NACK latched and safe cleanup");
   $fdisplay(events,"NACK_HIT %0t",$time);nack_b=-1;
  end
  start_it();warmup();check(pubs_a==0 && pubs_b==0,"ninth frame never admitted in its middle");
  if(case_id==2 || case_id==3) begin
   fid_a=77;short_packet(0,0,77);line_packet(0,77,0);
   if(case_id==2) begin
    wait(dut.sync_stopped);ticks(6000);
    check(!dut.sync_ready && pubs_a==0 && pubs_b==0,"missing B revokes and rejects half frame");
    $fdisplay(events,"MISSING_HIT %0t",$time);
    short_packet(0,1,77);ticks(200);start_it();warmup();
   end else begin
    wait(dut.u_ddr3_mc_0.w_count>0);
    $fdisplay(events,"RESET_HIT %0t aw=%0d w=%0d",$time,dut.u_ddr3_mc_0.aw_count,dut.u_ddr3_mc_0.w_count);
    reset_all();configured();start_it();warmup();
   end
  end
  three_good();
  if(case_id==4) begin
   abort_req=1;ticks(1);abort_req=0;wait(dut.sync_stopped);ticks(20);
   check(!dut.sync_ready,"explicit stop");start_it();
   begin integer a,b;a=pubs_a;b=pubs_b;warmup();check(pubs_a==a && pubs_b==b,"restart repeats full warmup");end
   three_good();
  end
  ticks(200);check(accepts==responses,"all accepted I2C requests receive one response");
  $display("T08_PASS case=%0d mismatch=0 A=%0d B=%0d accepts=%0d responses=%0d",case_id,pubs_a,pubs_b,accepts,responses);
  $fclose(events);$finish;
 end
 initial begin #40000000;$fatal(1,"simulation time watchdog");end
 // A real command-path mutation: transport and pin slave remain unmodified.
 // The independent pin checker must reject this correctly compiled run.
 initial if($test$plusargs("MUTATE_ROLE")) begin
  wait(dut.sync_req_valid && !dut.sync_camera && dut.sync_addr==16'h30c1);
  force dut.g_sync_ctrl.u_sync.control.reg_data=8'h0e;
  wait(dut.sync_req_valid && dut.sync_req_ready);ticks(2);
  release dut.g_sync_ctrl.u_sync.control.reg_data;
 end
endmodule
