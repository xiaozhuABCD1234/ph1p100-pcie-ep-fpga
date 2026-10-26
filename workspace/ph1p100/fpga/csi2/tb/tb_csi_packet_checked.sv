`timescale 1ns/1ps
module tb_csi_packet_checked #(parameter LINE_BYTES=20);
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,en=1,valid=0; reg[31:0] data=0;reg[23:0] hdr=0;
 wire[7:0] ecc;wire[31:0] payload;wire pv,done,waitsync,vs,inf,inl;wire[3:0] keep;
 integer seen=0,lines=0,dones=0,starts=0,i,expected,tests=0;
 csi_rx_hdr_ecc e(.data(hdr),.ecc(ecc));
`ifdef LEGACY
 csi_rx_packet_handler d(
`else
 csi_rx_packet_handler_checked #(.IMAGE_WC(LINE_BYTES)) d(.O_payload_keep(keep),
`endif
 .I_clock(clk),.I_reset_n(rst_n),.I_enable(en),.I_data(data),.I_data_valid(valid),
 .O_packet_done(done),.O_sync_wait(waitsync),.O_payload_out(payload),.O_payload_valid(pv),
 .O_vsync_out(vs),.O_in_frame(inf),.O_in_line(inl));
 function[31:0] value(input integer n);value=32'h40201000+n*32'h01010101;endfunction
 task fail(input string why);begin $display("CSI_PACKET_FAIL %s seen=%0d expected=%0d",why,seen,expected);$finish;end endtask
 always @(posedge clk)begin
  if(vs)starts=starts+1;
  #1;
  if(pv)begin if(payload!==value(seen))fail("payload value/footer leak");seen=seen+1;end
  if(inl)lines=lines+1;
  if(done)dones=dones+1;
 end
 task beat(input[31:0] v);begin @(negedge clk);data=v;valid=1;end endtask
 task idle(input integer n);begin @(negedge clk);valid=0;repeat(n)@(negedge clk);end endtask
 task reset_dut;begin
  @(negedge clk);rst_n=0;valid=0;repeat(3)@(negedge clk);rst_n=1;idle(4);
  seen=0;lines=0;dones=0;starts=0;
 end endtask
 task packet(input[7:0] di,input integer wc,input integer gaps,input integer wanted);
 begin
  seen=0;lines=0;dones=0;expected=wanted;
  hdr={wc[15:0],di};#1;beat({ecc,hdr});
  // Header is followed by ceil((WC+CRC16)/4) 32-bit transport beats.
  for(i=0;i<(wc+5)/4;i=i+1)begin
   if(gaps && i%3==1)idle(2);
   if(i<wc/4)beat(value(i));else beat(32'hd00dbeef);
  end
  idle(6);
  if(seen!=wanted)fail("payload count");
  if(lines!=(wanted!=0))fail("line qualification");
  if(dones!=1)fail("packet completion");
  tests=tests+1;
 end endtask
 initial begin
  reset_dut();packet(8'h2b,LINE_BYTES,0,LINE_BYTES/4);
  packet(8'h2b,LINE_BYTES,1,LINE_BYTES/4);
  packet(8'h12,LINE_BYTES,0,0);packet(8'h2c,LINE_BYTES,0,0);
  packet(8'h6b,LINE_BYTES,0,0); // RAW10 on VC1 is consumed, never unpacked.
  packet(8'h12,1,0,0);packet(8'h12,2,0,0);packet(8'h12,3,0,0);
  packet(8'h12,5,0,0);packet(8'h12,0,0,0);
  packet(8'h2b,5,0,0);packet(8'h2b,LINE_BYTES+20,0,0);
  packet(8'h2b,LINE_BYTES,0,LINE_BYTES/4); // Recover after skipped packets.
  hdr={16'd1,8'h00};#1;beat({ecc,hdr});idle(6);
  if(!inf||starts!=1)fail("selected FS");
  hdr={16'd1,8'h41};#1;beat({ecc,hdr});idle(6);
  if(!inf)fail("foreign VC FE");
  hdr={16'd1,8'h01};#1;beat({ecc,hdr});idle(6);if(inf)fail("selected FE");
  // Bad ECC must not open a line; reset also discards a partial payload.
  hdr={LINE_BYTES[15:0],8'h2b};#1;beat({ecc^8'h01,hdr});idle(6);
  if(lines!=1)fail("ECC opened line");
  reset_dut();hdr={LINE_BYTES[15:0],8'h2b};#1;beat({ecc,hdr});beat(value(0));
  reset_dut();packet(8'h2b,LINE_BYTES,0,LINE_BYTES/4);
  // Truncated payload times out, then a complete packet can recover.
  hdr={LINE_BYTES[15:0],8'h2b};#1;beat({ecc,hdr});idle(40);
  if(!waitsync)fail("timeout recovery");
  packet(8'h2b,LINE_BYTES,0,LINE_BYTES/4);
  $display("CSI_PACKET_PASS wc=%0d tests=%0d",LINE_BYTES,tests);$finish;
 end
 initial begin #2000000;fail("watchdog");end
endmodule
