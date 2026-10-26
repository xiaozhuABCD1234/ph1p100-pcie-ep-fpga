`timescale 1ns/1ps
module tb_csi_unpack_checked;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,valid=0;reg[31:0] data=0;reg[23:0] hdr=0;
 wire[7:0] ecc;wire[31:0] payload;wire[3:0] keep;
 wire pv,done,waitsync,vs,inf,inl;wire[39:0] pixels;wire pixel_valid;
 integer byte_seen=0,groups=0,lines=0,dones=0,tests=0,active_wc=0,expected_wc=0,i,k;
 reg[31:0] next_word;reg[39:0] reference;reg[7:0] lowbits;
 csi_rx_hdr_ecc e(.data(hdr),.ecc(ecc));
 csi_rx_packet_handler_checked d(.I_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_data(data),.I_data_valid(valid),
  .O_packet_done(done),.O_sync_wait(waitsync),.O_payload_out(payload),.O_payload_valid(pv),.O_payload_keep(keep),
  .O_vsync_out(vs),.O_in_frame(inf),.O_in_line(inl));
 csi_rx_10bit_unpack_checked u(.I_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_line_in(inl),
  .I_data_in(payload),.I_keep(keep),.I_din_valid(pv),.O_data_out(pixels),.O_dout_valid(pixel_valid));
 function[7:0] b(input integer n);b=(n*37+(n>>8)*13+7)&255;endfunction
 task fail(input string why);begin $display("CSI_PACKET_FAIL unpack %s wc=%0d bytes=%0d groups=%0d",why,active_wc,byte_seen,groups);$finish;end endtask
 always @(posedge clk)begin #1;
  if(inl)lines=lines+1;
  if(done)dones=dones+1;
  if(pv)begin
   if(expected_wc==0)fail("unexpected payload");
   for(integer n=0;n<4;n=n+1)begin
    if(keep[n] !== (byte_seen<expected_wc))fail("keep boundary");
    if(keep[n])begin if(payload[n*8+:8]!==b(byte_seen))fail("payload byte");byte_seen=byte_seen+1;end
    else if(payload[n*8+:8]!==0)fail("masked tail");
   end
  end
  if(pixel_valid)begin
   lowbits=b(groups*5+4);
   for(integer n=0;n<4;n=n+1)reference[n*10+:10]={b(groups*5+n),lowbits[n*2+:2]};
   if(pixels!==reference)fail("pixel bits/order");groups=groups+1;
  end
 end
 task beat(input[31:0] v);begin @(negedge clk);data=v;valid=1;end endtask
 task idle(input integer n);begin @(negedge clk);valid=0;repeat(n)@(negedge clk);end endtask
 task packet(input[7:0] di,input integer wc,input integer gaps);
 begin
  active_wc=wc;expected_wc=(di==8'h2b)?wc:0;byte_seen=0;groups=0;lines=0;dones=0;
  hdr={wc[15:0],di};#1;beat({ecc,hdr});
  for(i=0;i<(wc+5)/4;i=i+1)begin
   next_word=32'hbeefbeef;
   for(k=0;k<4;k=k+1)if(i*4+k<wc)next_word[k*8+:8]=b(i*4+k);
   if(gaps&&i%7==2)idle(2);beat(next_word);
  end
  idle(8);
  if(byte_seen!=expected_wc||groups!=expected_wc/5)fail("counts");
  if(lines!=(expected_wc!=0)||dones!=1)fail("line/done");tests=tests+1;
 end endtask
 initial begin
  repeat(3)@(negedge clk);rst_n=1;idle(4);
  packet(8'h2b,5,0);packet(8'h2b,10,1);packet(8'h2b,15,0);packet(8'h2b,20,1);
  packet(8'h2b,25,0);packet(8'h2b,30,1);packet(8'h2b,35,0);packet(8'h2b,40,1);
  packet(8'h12,5,0);packet(8'h6b,10,0);packet(8'h2c,15,0);
  packet(8'h2b,4800,0);packet(8'h2b,4830,1);
  $display("CSI_PACKET_PASS unpack tests=%0d",tests);$finish;
 end
 initial begin #2000000;fail("watchdog");end
endmodule
