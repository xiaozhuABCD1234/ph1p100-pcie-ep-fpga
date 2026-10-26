`timescale 1ns/1ps
// Real exporter; the store side serves independent, pre-generated zlib fixtures.
module tb_descriptor;
 reg clk=0,rst_n=0,desc_push=0,open_gate=0;
 always #5 clk=~clk;
 reg [255:0] descs[0:19],payloads[0:19];
 integer drive_index=0,active_index=0,mode=2,epoch=0;
 wire cmp_open,cmp_close,rd_take,dbg_valid,txd,busy;
 wire [7:0] dbg_byte;
 wire [31:0] exported,nbytes,errors;
 wire [255:0] descriptor=descs[drive_index];
 a1_uart_export #(.W(8),.H(2),.UART_DIV(4),.HB_DIV(0)) dut(
  .clk(clk),.rst_n(rst_n),.desc_push(desc_push),
  .d_frame_id(descriptor[31:0]),.d_raw_len(descriptor[63:32]),
  .d_xform_len(descriptor[95:64]),.d_stream_len(descriptor[127:96]),
  .d_raw_crc(descriptor[159:128]),.d_xform_crc(descriptor[191:160]),
  .d_stream_crc(descriptor[223:192]),.d_profile(descriptor[225:224]),
  .cmp_open(cmp_open),.cmp_open_ready(open_gate),
  .cmp_len(descs[active_index][127:96]),.cmp_id(descs[active_index][31:0]),
  .cmp_close(cmp_close),.rd_data(payloads[active_index]),.rd_valid(1'b1),
  .rd_take(rd_take),.dbg_byte(dbg_byte),.dbg_byte_valid(dbg_valid),
  .uart_clk(clk),.uart_txd(txd),.st_exported(exported),
  .st_bytes(nbytes),.st_err(errors),.st_busy(busy));
 integer q[0:127],head=0,tail=0,qcount=0;
 integer cycles=0,accepted=0,rejected=0,popped=0,resets=0;
 integer cov[0:11],a,p,old_count,expected_id,k;
 integer fd,ft,fs;
 reg [2047:0] fixture_path,payload_path,out_path,trace_path,stat_path;
 // This scoreboard uses offered descriptors and consumer idle state. It never
 // obtains expected descriptor contents from the DUT's queue or working regs.
 always @(posedge clk) begin
  cycles=cycles+1;
  if(cycles>500000) $fatal(1,"DESCRIPTOR_WATCHDOG");
  if(!rst_n) begin
   head=0;tail=0;qcount=0;active_index=0;
  end else begin
   old_count=qcount;
   a=desc_push && old_count<2;
   p=(dut.estate==0) && old_count>0;
   cov[old_count*4+desc_push*2+p]=cov[old_count*4+desc_push*2+p]+1;
   if(p) begin
    active_index=q[head];head=head+1;popped=popped+1;
    expected_id=descs[active_index][31:0];
   end
   if(a) begin q[tail]=drive_index;tail=tail+1;accepted=accepted+1;end
   if(desc_push && !a) rejected=rejected+1;
   qcount=old_count+a-p;
   if(desc_push || p) $fwrite(ft,"EVENT cycle=%0d epoch=%0d count=%0d request=%0d accepted_push=%0d pop=%0d next_count=%0d offered_index=%0d active_index=%0d\n",cycles,epoch,old_count,desc_push,a,p,qcount,drive_index,active_index);
   #0.001;
   if(dut.dq_cnt !== qcount[1:0]) $fatal(1,"QUEUE_COUNT_MISMATCH old=%0d push=%0d pop=%0d expected=%0d actual=%0d",old_count,a,p,qcount,dut.dq_cnt);
   if(p && dut.w_frame_id !== expected_id[31:0]) $fatal(1,"DESCRIPTOR_ORDER_OR_X pop=%0d expected_id=%0d actual_id=%h",popped,expected_id,dut.w_frame_id);
  end
 end
 always @(negedge clk) if(rst_n && dbg_valid) $fwrite(fd,"%0d %0d\n",epoch,dbg_byte);
 task offer;
  input integer idx;
  begin @(negedge clk);drive_index=idx;desc_push=1;@(posedge clk);#0.002;desc_push=0;end
 endtask
 task wait_exports;
  input integer n;
  integer t;
  begin
   t=0;while((exported<n || busy || dut.uart_busy) && t<100000) begin @(negedge clk);t=t+1;end
   if(t==100000 || exported!=n) $fatal(1,"EXPORT_COMPLETION expected=%0d actual=%0d",n,exported);
   repeat(50) @(negedge clk);
  end
 endtask
 task queued_reset;
  begin
   open_gate=0;offer(14);offer(15);offer(16);
   @(negedge clk);
   if(qcount!=2 || dut.estate!=1) $fatal(1,"QUEUED_RESET_NOT_HIT");
   $fwrite(ft,"QUEUED_RESET epoch=%0d queued=%0d active_index=%0d\n",epoch,qcount,active_index);
   rst_n=0;desc_push=0;epoch=epoch+1;resets=resets+1;
   repeat(4) @(negedge clk);
   if(dut.dq_wr!==0 || dut.dq_rd!==0 || dut.dq_cnt!==0 || exported!==0 || errors!==0 || busy!==0 || dbg_valid!==0) $fatal(1,"QUEUED_RESET_CLEAR");
   rst_n=1;open_gate=1;repeat(2) @(negedge clk);
   offer(12);wait_exports(1);offer(13);wait_exports(2);
  end
 endtask
 integer i,t;
 initial begin
  for(i=0;i<12;i=i+1) cov[i]=0;
  if(!$value$plusargs("MODE=%d",mode)) mode=2;
  if(!$value$plusargs("DESCS=%s",fixture_path)) $fatal(1,"DESCS_PATH");
  if(!$value$plusargs("PAYLOADS=%s",payload_path)) $fatal(1,"PAYLOADS_PATH");
  if(!$value$plusargs("OUT=%s",out_path)) $fatal(1,"OUT_PATH");
  if(!$value$plusargs("TRACE=%s",trace_path)) $fatal(1,"TRACE_PATH");
  if(!$value$plusargs("STAT=%s",stat_path)) $fatal(1,"STAT_PATH");
  $readmemh(fixture_path,descs);$readmemh(payload_path,payloads);
  fd=$fopen(out_path,"w");ft=$fopen(trace_path,"w");fs=$fopen(stat_path,"w");
  if(!fd||!ft||!fs) $fatal(1,"FILE_OPEN");
  repeat(4) @(negedge clk);rst_n=1;repeat(3) @(negedge clk);
  if(mode==2) begin
   open_gate=1;
   for(i=0;i<12;i=i+1) begin offer(i);wait_exports(i+1);end
  end else begin
   // Empty push, then one-item simultaneous push/pop, then fill and reject.
   open_gate=0;offer(0);offer(1);offer(2);offer(3);
   if(qcount!=2 || errors!=1) $fatal(1,"FULL_REJECT_PRECONDITION");
   open_gate=1;t=0;
   while(dut.estate!=0 && t<100000) begin @(negedge clk);t=t+1;end
   if(t==100000 || qcount!=2) $fatal(1,"FULL_POP_PRECONDITION");
   // Full+pop rejects this request, matching the frozen admission policy.
   drive_index=4;desc_push=1;@(negedge clk);desc_push=0;
   if(qcount!=1 || errors!=2) $fatal(1,"FULL_POP_REJECT_POLICY");
   offer(5); // Refill while busy; next full pop has no offered push.
   wait_exports(4);
   if(errors!=2 || rejected!=2) $fatal(1,"REJECTION_ACCOUNTING");
   // All physically legal count/request/pop combinations must be observed.
   for(k=0;k<12;k=k+1) begin
    if(k!=1 && k!=3 && cov[k]==0) $fatal(1,"QUEUE_TRANSITION_MISSING bin=%0d",k);
   end
  end
  queued_reset;
  $fwrite(fs,"STAT mode=%0d accepted=%0d rejected=%0d popped=%0d resets=%0d epoch=%0d final_exported=%0d final_errors=%0d queued=%0d cycles=%0d\n",mode,accepted,rejected,popped,resets,epoch,exported,errors,qcount,cycles);
  for(k=0;k<12;k=k+1) $fwrite(fs,"COV bin=%0d hits=%0d\n",k,cov[k]);
  $fclose(fd);$fclose(ft);$fclose(fs);
  $display("DESCRIPTOR_PASS mode=%0d mismatch=0",mode);$finish;
 end
endmodule
