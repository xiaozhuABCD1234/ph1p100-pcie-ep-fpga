from pathlib import Path
H=Path(__file__).resolve().parent
OLD=Path(r'D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery\T08.sync-production-sim')
env=(OLD/'vendor_env.sv').read_text(encoding='utf-8')
env=env.replace("    assign axi_arready=1'b0;assign axi_rvalid=1'b0;assign axi_rdata=0;\n    assign axi_rlast=0;assign axi_rresp=0;assign axi_rid=0;",'''    reg read_active=0,read_valid=0,block_ar=0,drop_reads=0,corrupt_payload=0;
    reg [28:0] read_addr=0;reg [8:0] read_left=0;reg [3:0] read_id=0;
    reg [255:0] read_data=0;reg read_last=0;integer read_delay=0,delay_q=0;
    integer ar_count=0,r_count=0,read_log;
    assign axi_arready=sys_rst_n&&!read_active&&!block_ar&&(cycle%5!=1);
    assign axi_rvalid=read_valid;assign axi_rdata=read_data;
    assign axi_rlast=read_last;assign axi_rresp=0;assign axi_rid=read_id;
    initial begin read_log=$fopen("read_beats.log","w");end
    always @(posedge clock_r or negedge sys_rst_n) begin
      if(!sys_rst_n) begin read_active<=0;read_valid<=0;read_left<=0;read_addr<=0;read_id<=0;ar_count<=0;r_count<=0;delay_q<=0;end
      else begin
        if(axi_arvalid&&axi_arready) begin
          if(axi_arsize!=5||axi_arburst!=1||axi_arlen>127||axi_araddr[4:0]!=0 ||
             {1'b0,axi_araddr[11:0]}+(({5'd0,axi_arlen}+1)<<5)>4096) $fatal(1,"DDR AR boundary/format");
          if(read_active) $fatal(1,"second outstanding AR");
          read_active<=1;read_addr<=axi_araddr;read_left<={1'b0,axi_arlen}+1;read_id<=axi_arid;
          delay_q<=read_delay;ar_count<=ar_count+1;
        end
        if(read_active&&!read_valid&&!drop_reads) begin
          if(delay_q>0) delay_q<=delay_q-1;
          else if(cycle%7!=3) begin
            for(integer z=0;z<32;z=z+1) begin
              read_data[z*8+:8]<=mem[map_byte(read_addr+z)] ^
                ((corrupt_payload && read_addr[11:0]==128 && z==0)?8'h01:8'h00);
            end
            read_last<=read_left==1;read_valid<=1;
          end
        end
        if(axi_rvalid&&axi_rready) begin
          $fdisplay(read_log,"R %0t %08x %064x",$time,read_addr,read_data);
          r_count<=r_count+1;read_valid<=0;read_addr<=read_addr+32;read_left<=read_left-1;
          if(read_left==1) read_active<=0;
        end
      end
    end''')
(H/'vendor_env.sv').write_text(env,encoding='utf-8')

sensor='''`timescale 1ns/1ps
// Pin-only sensor register memory. No access to DUT expectations or hierarchy.
module sensor_i2c #(parameter CAMERA=0)(
 input wire rst_n,scl,inout wire sda,input integer nack_at,
 input wire [7:0] read_xor,input wire [15:0] read_xor_addr,
 output integer transactions,output integer reads);
 reg drive_low=0,active=0,reading=0;integer bits=0,bytes=0;
 reg [7:0] shift=0,tx_data=0;reg [15:0] address=0;
 reg [31:0] word_q=0;reg [3:0] ack_q=0;reg [7:0] regs[0:65535];integer fd,z;
 assign sda=drive_low ? 1'b0 : 1'bz;
 initial begin transactions=0;reads=0;
   for(z=0;z<65536;z=z+1) regs[z]=0;
   if(CAMERA==0) fd=$fopen("i2c_a.log","w");else fd=$fopen("i2c_b.log","w");
   if(!fd) $fatal(1,"I2C trace open");end
 always @(negedge rst_n) begin
   active=0;drive_low=0;reading=0;bits=0;bytes=0;transactions=0;reads=0;word_q=0;ack_q=0;
   $fdisplay(fd,"RESET %0t",$time);
 end
 always @(negedge sda) if(rst_n && scl===1'b1 && !drive_low) begin
   if(active && bytes==3) $fdisplay(fd,"ADDR %0t %04x",$time,address);
   active=1;reading=0;bits=0;bytes=0;word_q=0;ack_q=0;shift=0;
 end
 always @(posedge scl) if(rst_n && active) begin
   if(reading) begin
     if(bits<8) bits=bits+1;
     else begin
       if(sda!==1'b1) $fatal(1,"master must NACK final read byte");
       $fdisplay(fd,"READ %0t %04x %02x",$time,address,tx_data);
       reads=reads+1;reading=0;active=0;drive_low=0;
     end
   end else if(bits<8) begin shift={shift[6:0],sda};bits=bits+1;end
   else begin
     if(bytes<4) begin word_q={word_q[23:0],shift};ack_q[bytes]=(sda===1'b0);end
     if(bytes==1) address[15:8]=shift;
     if(bytes==2) address[7:0]=shift;
     if(bytes==3 && sda===1'b0) regs[address]=shift;
     if(bytes==0 && shift==8'h35) begin
       tx_data=regs[address] ^ ((address==read_xor_addr)?read_xor:8'h00);reading=1;
     end
     bytes=bytes+1;bits=0;
   end
 end
 always @(negedge scl) if(active) begin
   if(reading) drive_low=bits<8 ? !tx_data[7-bits] : 0;
   else drive_low=(bits==8) && !(transactions==nack_at && bytes==3);
 end else drive_low=0;
 always @(posedge sda) if(rst_n && scl===1'b1 && active && !drive_low) begin
   if(bytes==4) begin
     $fdisplay(fd,"TX %0t %0d %08x %01x",$time,transactions,word_q,ack_q);transactions=transactions+1;
   end
   active=0;drive_low=0;
 end
endmodule
'''
(H/'sensor_i2c.sv').write_text(sensor,encoding='ascii')

# Extend the proven packet generator; no stub replaces checked CSI or writers.
tb=(OLD/'tb_production_sync.sv').read_text(encoding='utf-8')
tb=tb.replace('integer fid_a=', 'reg [7:0] read_xor=0;integer reads_a,reads_b;reg local_abort=0;reg [1:0] mode=1;\n reg rel_valid=0,rel_camera=0,rel_slot=0;reg [31:0] rel_epoch=0,rel_session=0,rel_seq=0;\n integer releases_a=0,releases_b=0;reg [31:0] prev_pass=0,prev_fail=0;\n integer fid_a=')
tb=tb.replace('.SYNC_ENABLE(1),','.SYNC_ENABLE(1),.DUAL_LOCAL_EN(1),.LOCAL_TIMEOUT(2000),')
tb=tb.replace('.sync_start(start)', ".consumer_epoch(epoch),.consumer_mode(mode),.local_abort(local_abort),\n  .rel_valid(rel_valid),.rel_camera_id(rel_camera),.rel_slot_id(rel_slot),.rel_epoch(rel_epoch),.rel_session(rel_session),.rel_capture_seq(rel_seq),.rel_status(3'd2),\n  .a_desc_ready(1'b0),.b_desc_ready(1'b0),.ext_arvalid(1'b0),.ext_arid(4'd0),.ext_araddr(29'd0),.ext_arlen(8'd0),.ext_arsize(3'd5),.ext_arburst(2'd1),.ext_rready(1'b0),\n  .sync_start(start)")
tb=tb.replace('nack_a,txa);','nack_a,read_xor,16\'h3000,txa,reads_a);').replace('nack_b,txb);','nack_b,read_xor,16\'h3000,txb,reads_b);')
tb=tb.replace('ticks(200);check(txa==201', 'check(reads_a>40 && reads_a==reads_b,"masked random reads completed on pins");\n  $fdisplay(events,"READBACK_HIT %0d %0d",reads_a,reads_b);\n  ticks(200);check(txa==201')
tb=tb.replace('ticks(12);epoch=', 'local_abort=0;\n  dut.u_ddr3_mc_0.block_ar=0;dut.u_ddr3_mc_0.drop_reads=0;dut.u_ddr3_mc_0.read_delay=0;dut.u_ddr3_mc_0.corrupt_payload=0;\n  ticks(12);epoch=')
tb=tb.replace('task three_good;','task three_good;').replace('k<=12','k<=15').replace('three consecutive','six consecutive')
# Every admitted pair completes consumption before the next default pair.
tb=tb.replace('ticks(5000);','ticks(6000);')
tb=tb.replace('check(pubs_a==a+k-9 && pubs_b==b+k-9,"one exact A/B publication per accepted frame");','check(pubs_a==a+k-9 && pubs_b==b+k-9,"one exact A/B publication per accepted frame");\n    check(dut.local_pass_count>=2*(k-9),"both complete DDR reads and releases before next frame");')
start=tb.index(' initial begin\n  events=$fopen')
end=tb.index(' initial begin #40000000',start)
body=''' initial begin
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
'''
tb=tb[:start]+body+tb[end:]
tb=tb.replace('2000000','3000000').replace('#40000000','#60000000')
monitor='''
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
'''
tb=tb.replace('endmodule',monitor+'endmodule')
(H/'tb_production_sync.sv').write_text(tb,encoding='utf-8')
runner=(OLD/'run_t08.py').read_text(encoding='utf-8')
legacy=(OLD/'tb_production_sync.sv').read_text(encoding='utf-8').replace('module tb_production_sync;','module tb_production_sync_legacy;')
legacy=legacy.replace('integer fid_a=','integer reads_a,reads_b;integer fid_a=')
legacy=legacy.replace('nack_a,txa);',"nack_a,8'd0,16'h3000,txa,reads_a);").replace('nack_b,txb);',"nack_b,8'd0,16'h3000,txb,reads_b);")
(H/'tb_production_sync_legacy.sv').write_text(legacy,encoding='utf-8')
runner=runner.replace("H/'sync_i2c_config.v',", "H/'tb_dual_contract.sv',H/'tb_production_sync_legacy.sv',H/'dual_local_closure.v',H/'sync_i2c_config.v',")
runner=runner.replace("'-voptargs=+acc',", "")
(H/'run_t08.py').write_text(runner,encoding='utf-8')
print('ENVIRONMENT_GENERATED')
