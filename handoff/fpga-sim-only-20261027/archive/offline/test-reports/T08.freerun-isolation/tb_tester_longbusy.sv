`timescale 1ns/1ps
// New free-running source + external consumer; frozen checked CSI/writers/arbiter/mailboxes remain real RTL.
module tb_freerun;
 reg clk=0,ca=0,cb=0;always #10 clk=~clk;
 always #7 ca=~ca;initial begin #3;forever #9 cb=~cb;end
 reg por=0,va=0,vb=0,da=0,db=0;reg [31:0] wa=0,wb=0;
 tri1 sda_a,sda_b;wire scl_a,scl_b;
 integer case_id=0,events,frames=12,period_a=50000,period_b=50000,phase_b=0;
 integer source_a=0,source_b=0,checked_a=0,checked_b=0,fid_a=0,fid_b=0;
 integer pub_a=0,pub_b=0,releases_a=0,releases_b=0,peak=0;
 localparam integer T0=20000;
 integer busy_end=420000;
 reg ready_a=1,ready_b=1,consume=1,done_a=0,done_b=0;
 wire av,bv,ac,bc,asl,bsl;wire [31:0] ae,be,ass,bss,aq,bq,ab,bb,al,bl,araw,braw;
 wire [15:0] aw,ah,bw,bh;wire [1:0] aph,bph;
 reg rv=0,rc=0,rs=0;reg [31:0] re=7,rse=0,rq=0;reg [2:0] rst=0;
 wire rr;reg xv=0,xrr=1;reg [28:0] xa=0;wire xr,xrv,xlast;wire [255:0] xd;wire [3:0] xid;wire [1:0] xresp;
 reg [3:0] pending=0;reg [31:0] seqs[0:3],sess[0:3],epochs[0:3],bases[0:3];
 reg old_va=0,old_vb=0,stall_a=0,stall_b=0;reg [230:0] stable_a,stable_b;
 wire [230:0] identity_a={ac,asl,ae,ass,aq,ab,al,araw,aw,ah,aph};
 wire [230:0] identity_b={bc,bsl,be,bss,bq,bb,bl,braw,bw,bh,bph};

 ph1p_pcie_ep_top #(.DBG_CTRL_DEFAULT_EN(1),.SYNC_ENABLE(0),.DUAL_LOCAL_EN(1),.CONSUMER_MODE(2),.LOCAL_TIMEOUT(1000000),
   .CAM_I2C_DIV(14),.CAM_POWER_CYCLES(32),.CAM_CSI_RELEASE_CYCLES(8),
   .CAMDDR_W(8),.CAMDDR_H(2),.CAMDDR_X0(0),.CAMDDR_Y0(0),.CAMDDR_SKIP_ROWS(0)) dut(
   .consumer_epoch(32'd7),.consumer_mode(2'd2),.local_abort(1'b0),.sync_start(1'b0),.sync_abort(1'b0),
   .rel_valid(rv),.rel_ready(rr),.rel_camera_id(rc),.rel_slot_id(rs),.rel_epoch(re),.rel_session(rse),.rel_capture_seq(rq),.rel_status(rst),
   .a_desc_valid(av),.a_desc_ready(ready_a),.a_desc_camera_id(ac),.a_desc_slot_id(asl),.a_desc_epoch(ae),.a_desc_session(ass),.a_desc_capture_seq(aq),.a_desc_base(ab),.a_desc_dma_bytes(al),.a_desc_raw_bytes(araw),.a_desc_width(aw),.a_desc_height(ah),.a_desc_bayer_phase(aph),
   .b_desc_valid(bv),.b_desc_ready(ready_b),.b_desc_camera_id(bc),.b_desc_slot_id(bsl),.b_desc_epoch(be),.b_desc_session(bss),.b_desc_capture_seq(bq),.b_desc_base(bb),.b_desc_dma_bytes(bl),.b_desc_raw_bytes(braw),.b_desc_width(bw),.b_desc_height(bh),.b_desc_bayer_phase(bph),
   .ext_arvalid(xv),.ext_arready(xr),.ext_arid(4'd0),.ext_araddr(xa),.ext_arlen(8'd127),.ext_arsize(3'd5),.ext_arburst(2'd1),
   .ext_rready(xrr),.ext_rvalid(xrv),.ext_rdata(xd),.ext_rid(xid),.ext_rresp(xresp),.ext_rlast(xlast),
   .sim_clk_a(ca),.sim_clk_b(cb),.sim_valid_a(va),.sim_valid_b(vb),.sim_done_a(da),.sim_done_b(db),.sim_data_a(wa),.sim_data_b(wb),
   .sys_clk(clk),.pcie_power_on_rst(por),.pcie_mperst(por),.ref_pad_clk_p(clk),.ref_pad_clk_n(~clk),
   .pcie_rx_p(2'b0),.pcie_rx_n(2'b0),.user_int_trigger(1'b0),
   .mipi_a_clk_hs_p(ca),.mipi_a_clk_hs_n(~ca),.mipi_b_clk_hs_p(cb),.mipi_b_clk_hs_n(~cb),
   .mipi_a_data_hs_p(4'b0),.mipi_a_data_hs_n(4'b0),.mipi_b_data_hs_p(4'b0),.mipi_b_data_hs_n(4'b0),
   .cam_a_scl(scl_a),.cam_a_sda(sda_a),.cam_b_scl(scl_b),.cam_b_sda(sda_b));

 task check(input bit ok,input string why);
  if(!ok)begin $display("FREERUN_FAIL case=%0d time=%0d %s held=%h pubs=%0d/%0d",case_id,$time,why,dut.local_held,pub_a,pub_b);$fatal(1);end
 endtask
 task tick;@(negedge dut.w_ddr_dhi_clk);endtask
 function automatic [7:0] ecc(input [23:0] d);
  reg [7:0] e;begin e=0;
   e[0]=d[0]^d[1]^d[2]^d[4]^d[5]^d[7]^d[10]^d[11]^d[13]^d[16]^d[20]^d[21]^d[22]^d[23];
   e[1]=d[0]^d[1]^d[3]^d[4]^d[6]^d[8]^d[10]^d[12]^d[14]^d[17]^d[20]^d[21]^d[22]^d[23];
   e[2]=d[0]^d[2]^d[3]^d[5]^d[6]^d[9]^d[11]^d[12]^d[15]^d[18]^d[20]^d[21]^d[22];
   e[3]=d[1]^d[2]^d[3]^d[7]^d[8]^d[9]^d[13]^d[14]^d[15]^d[19]^d[20]^d[21]^d[23];
   e[4]=d[4]^d[5]^d[6]^d[7]^d[8]^d[9]^d[16]^d[17]^d[18]^d[19]^d[20]^d[22]^d[23];
   e[5]=d[10]^d[11]^d[12]^d[13]^d[14]^d[15]^d[16]^d[17]^d[18]^d[19]^d[21]^d[22]^d[23];ecc=e;end
 endfunction
 function automatic [15:0] crc16_byte(input [15:0] c,input [7:0] b);
  reg [15:0] r;integer k;begin r=c;for(k=0;k<8;k=k+1)if(r[0]^b[k])r=(r>>1)^16'h8408;else r=r>>1;crc16_byte=r;end
 endfunction
 task automatic put(input integer cam,input [31:0] data);
  if(cam==0)begin @(negedge ca);va=1;wa=data;@(negedge ca);va=0;end
  else begin @(negedge cb);vb=1;wb=data;@(negedge cb);vb=0;end
 endtask
 task automatic gap(input integer cam);
  if(cam==0)repeat(8)@(negedge ca);else repeat(8)@(negedge cb);
 endtask
 task automatic short_packet(input integer cam,dt,id);
  reg [23:0] h;begin h={id[15:0],dt[7:0]};put(cam,{ecc(h),h});gap(cam);end
 endtask
 task automatic line_packet(input integer cam,fid,row);
  reg [7:0] data[0:11];reg [15:0] c;reg [23:0] h;integer k;
  begin c=16'hffff;for(k=0;k<10;k=k+1)begin data[k]=(cam*97+fid*13+row*23+k*7)&255;c=crc16_byte(c,data[k]);end
   data[10]=c[7:0];data[11]=c[15:8];h={16'd10,8'h2b};put(cam,{ecc(h),h});
   for(k=0;k<12;k=k+4)put(cam,{data[k+3],data[k+2],data[k+1],data[k]});gap(cam);end
 endtask
 // The source waits only for its predeclared absolute simulator times and byte clock edges.
 // No descriptor ready, mailbox occupancy or consumer progress is an input here.
 task automatic source(input integer cam,period,phase);
  integer n,target,fid;
  begin for(n=0;n<12;n=n+1)begin
   target=T0+phase+n*period;if($time<target)#(target-$time);
   if($test$plusargs("GATE_SOURCE")&&cam==0&&n==3)wait(ready_a);
   check($time==target,"source schedule overrun");fid=100+n;
   $fdisplay(events,"SSOF %0d %0d %0d %0d",cam,fid,target,$time);
   if(cam==0)begin fid_a=fid;source_a=source_a+1;end else begin fid_b=fid;source_b=source_b+1;end
   short_packet(cam,0,fid);line_packet(cam,fid,0);line_packet(cam,fid,1);short_packet(cam,1,fid);
   $fdisplay(events,"SEOF %0d %0d %0d",cam,fid,$time);
  end if(cam==0)done_a=1;else done_b=1;end
 endtask
 task snapshot(input integer cam,input string label);
  integer f,j,start;reg [1023:0] name;
  begin $sformat(name,"snapshot_%0d_%s.hex",cam,label);f=$fopen(name,"w");start=cam*8192;
   for(j=0;j<8192;j=j+1)$fdisplay(f,"%02x",dut.u_ddr3_mc_0.mem[start+j]);$fclose(f);
   $fdisplay(events,"SNAP %0d %s %0d %h",cam,label,$time,dut.local_held);end
 endtask
 task bad_release(input integer kind);
  reg [3:0] before_held;reg [31:0] rejects;
  begin tick();before_held=dut.local_held;rejects=dut.local_reject_count;
   rc=0;rs=0;re=epochs[0];rse=sess[0];rq=seqs[0];rst=0;
   case(kind)0:re=epochs[0]-1;1:rse=sess[0]^1;2:begin rc=1;rq=seqs[0]+500;end 3:rq=seqs[0]+1;endcase
   rv=1;tick();rv=0;repeat(3)tick();
   check(dut.local_held==before_held&&dut.cl_release==0&&dut.b_cl_release==0&&dut.local_reject_count==rejects+1,"stale/mismatched release changed ownership");
   $fdisplay(events,"BADREL %0d %0d %h %h %0d",kind,$time,before_held,dut.local_held,dut.local_reject_count);
  end
 endtask
 // External consumer model uses legal descriptor, native-read and complete-identity release ports.
 initial begin:consumer
  integer idx,n,fd,j;reg [1023:0] name;
  wait(por);forever begin tick();idx=-1;
   if(consume)for(n=3;n>=0;n=n-1)if(pending[n])idx=n;
   if(idx>=0)begin
    xa=bases[idx][28:0];xv=1;do @(posedge dut.w_ddr_dhi_clk);while(!xr);tick();xv=0;
    $fdisplay(events,"READBEGIN %0d %0d %0d %0d",idx/2,idx%2,seqs[idx],$time);
    $sformat(name,"read_%0d_%0d.hex",idx/2,seqs[idx]);fd=$fopen(name,"w");n=0;
    while(n<128)begin @(posedge dut.w_ddr_dhi_clk);if(xrv&&xrr)begin
     check(xid==0&&xresp==0&&xlast==(n==127),"native read response identity/length");
     for(j=0;j<32;j=j+1)$fdisplay(fd,"%02x",xd[j*8+:8]);n=n+1;end end
    $fclose(fd);repeat(3)tick();
    check(dut.g_dual_local.u_local.outstanding==0&&!dut.g_dual_local.u_local.ar_pending,"read drained before release");
    rc=idx/2;rs=idx%2;re=epochs[idx];rse=sess[idx];rq=seqs[idx];rst=0;rv=1;
    $fdisplay(events,"RELEASE %0d %0d %0d %0d %0d %0d",rc,rs,re,rse,rq,$time);
    tick();rv=0;pending[idx]=0;repeat(3)tick();check(!dut.local_held[idx],"exact status0 release did not clear target");
   end
  end
 end
 always @(posedge dut.w_ddr_dhi_clk)if(por)begin:observations
  integer i,cnt;
  if(stall_a)check(av&&identity_a===stable_a,"A descriptor changed while stalled");
  if(stall_b)check(bv&&identity_b===stable_b,"B descriptor changed while stalled");
  stall_a=av&&!ready_a;stall_b=bv&&!ready_b;stable_a=identity_a;stable_b=identity_b;
  if(av&&ready_a)begin
   check(ac==0&&ae==7&&al==4096&&araw==20&&aw==8&&ah==2&&aph==0,"A thin interface fields");
   check(!pending[asl],"A duplicate descriptor");pending[asl]=1;seqs[asl]=aq;sess[asl]=ass;epochs[asl]=ae;bases[asl]=ab;
   $fdisplay(events,"DESC 0 %0d %0d %0d %0d %08x %0d",asl,ae,ass,aq,ab,$time);
  end
  if(bv&&ready_b)begin
   check(bc==1&&be==7&&bl==4096&&braw==20&&bw==8&&bh==2&&bph==0,"B thin interface fields");
   check(!pending[2+bsl],"B duplicate descriptor");pending[2+bsl]=1;seqs[2+bsl]=bq;sess[2+bsl]=bss;epochs[2+bsl]=be;bases[2+bsl]=bb;
   $fdisplay(events,"DESC 1 %0d %0d %0d %0d %08x %0d",bsl,be,bss,bq,bb,$time);
  end
  if(dut.cl_pub_valid)begin
   pub_a=pub_a+1;dut.u_ddr3_mc_0.dump_frame(0,dut.cl_pub_seq,dut.cl_pub_base);
   $fdisplay(events,"PUB 0 %0d %08x %0d %0d %0d",dut.cl_pub_seq,dut.cl_pub_base,dut.cl_pub_session,fid_a,$time);
  end
  if(dut.b_cl_pub_valid)begin
   pub_b=pub_b+1;dut.u_ddr3_mc_0.dump_frame(1,dut.b_cl_pub_seq,dut.b_cl_pub_base);
   $fdisplay(events,"PUB 1 %0d %08x %0d %0d %0d",dut.b_cl_pub_seq,dut.b_cl_pub_base,dut.b_cl_pub_session,fid_b,$time);
  end
  if(dut.cl_release!=0)begin releases_a=releases_a+1;$fdisplay(events,"RELWIRE 0 %0d %0d",dut.cl_release,$time);end
  if(dut.b_cl_release!=0)begin releases_b=releases_b+1;$fdisplay(events,"RELWIRE 1 %0d %0d",dut.b_cl_release,$time);end
  if(dut.w_ddr_awvalid&&dut.w_ddr_awready)for(i=0;i<4;i=i+1)if(dut.local_held[i])
   check(!(dut.w_ddr_awaddr>=dut.g_dual_local.u_local.q_base[i]&&dut.w_ddr_awaddr<dut.g_dual_local.u_local.q_base[i]+4096),"write touched held slot");
  cnt=0;for(i=0;i<4;i=i+1)cnt=cnt+dut.local_held[i];if(cnt>peak)begin peak=cnt;$fdisplay(events,"PEAK %0d %0d",peak,$time);end
  check(dut.local_fault==0,"local ownership fault");
 end
 always @(posedge ca)if(por)begin
  if(dut.w_a_vsync&&!old_va)begin checked_a=checked_a+1;$fdisplay(events,"CSOF 0 %0d %0d",fid_a,$time);end old_va<=dut.w_a_vsync;
 end
 always @(posedge cb)if(por)begin
  if(dut.w_b_vsync&&!old_vb)begin checked_b=checked_b+1;$fdisplay(events,"CSOF 1 %0d %0d",fid_b,$time);end old_vb<=dut.w_b_vsync;
 end
 initial begin
  events=$fopen("events.log","w");if(!$value$plusargs("CASE=%d",case_id))case_id=0;
  if(case_id==2)begin period_b=52000;phase_b=3000;end
  if(case_id==1)ready_a=0;
  if(case_id==2)ready_b=0;
  if(case_id==3)dut.u_ddr3_mc_0.block_ar=1;
  if(case_id==4)begin ready_a=0;ready_b=0;end
  if(case_id==5)consume=0;
  $fdisplay(events,"CONFIG %0d %0d %0d %0d %0d %0d",case_id,T0,period_a,period_b,phase_b,busy_end);
  #240;por=1;
  #19000;check(dut.w_cam_ddr_want&&dut.w_a_rst_out&&dut.w_b_rst_out,"DUT not initialized before fixed source start");
  fork source(0,period_a,0);source(1,period_b,phase_b);join_none
  if(case_id!=0)begin
   #(150000-$time);
   if(case_id==1)snapshot(0,"start");else if(case_id==2)snapshot(1,"start");
   else begin check(dut.local_held==15,"four slots were not full before continuing SOFs");snapshot(0,"start");snapshot(1,"start");end
   if(case_id==5)for(integer k=0;k<4;k=k+1)bad_release(k);
   #(busy_end-1000-$time);
   if(case_id==1)snapshot(0,"end");else if(case_id==2)snapshot(1,"end");else begin snapshot(0,"end");snapshot(1,"end");end
   #(busy_end-$time);ready_a=1;ready_b=1;consume=1;dut.u_ddr3_mc_0.block_ar=0;
   $fdisplay(events,"RECOVER %0d",$time);
  end
  wait(done_a&&done_b);#70000;
  check(source_a==12&&source_b==12&&checked_a==12&&checked_b==12,"fixed free-running SOF count");
  check(dut.local_held==0&&pending==0&&releases_a==pub_a&&releases_b==pub_b,"consumer did not drain all published frames");
  check(pub_a>=4&&pub_b>=4,"insufficient complete recovery frames");
  if(case_id!=0)check(dut.cl_writer_bad>0||dut.b_cl_bad>0,"busy/full did not drop frames");
  $fdisplay(events,"SUMMARY %0d %0d %0d %0d %0d %0d %0d %0d",pub_a,pub_b,releases_a,releases_b,dut.cl_writer_bad,dut.b_cl_bad,peak,dut.local_reject_count);
  $display("FREERUN_PASS case=%0d sources=%0d/%0d pubs=%0d/%0d releases=%0d/%0d peak=%0d",case_id,source_a,source_b,pub_a,pub_b,releases_a,releases_b,peak);
  $fclose(events);$finish;
 end
 initial begin #1500000;$fatal(1,"free-run simulator watchdog");end
endmodule
