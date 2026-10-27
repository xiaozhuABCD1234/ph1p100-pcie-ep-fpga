`timescale 1ns/1ps
// Exercise production byte-align, word-align and gearbox feedback with
// byte-aligned D-PHY data. No device I/O primitives/electrical margin model.
module tb_csi_frontend_drain;
 reg clk=0,rst_n=0; always #5 clk=~clk;
 reg[31:0] lanes=0;
 wire[31:0] aw,data; wire av,valid,done,ws;
 wire[31:0] ba;wire[3:0] bv;
 wire[31:0] headers,good,bad,crc_errors; reg[23:0] h=0;wire[7:0] ecc;
 csi_rx_hdr_ecc e(.data(h),.ecc(ecc));
 genvar g;generate for(g=0;g<4;g=g+1)begin: bytes
 csi_rx_byte_align byte_align(.I_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_lan_data_in(lanes[g*8+:8]),.I_wait_for_sync(ws),.I_packet_done(done),.O_data_out_vaild(bv[g]),.O_data_out(ba[g*8+:8]));
 end endgenerate
 csi_rx_word_align #(.MIPI_LAN(4)) align(.I_word_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_packet_done(done),.I_wait_for_sync(ws),.I_word_in(ba),.I_valid_in(bv),.O_word_out(aw),.O_valid_out(av),.O_packet_done_out());
 csi_rx_word_gear_box #(.MIPI_LAN(4)) gear(.I_word_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_lane_data(aw),.I_lane_data_valid(av),.O_word_out(data),.O_valid_out(valid));
 csi_rx_packet_integrity #(.EXPECTED_LINES(2),.CHECK_FRAME_ID(1),.FRAME_TIMEOUT_CYCLES(4096)) d(.I_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_data(data),.I_data_valid(valid),.O_packet_done(done),.O_sync_wait(ws),.O_header_errors(headers),.O_good_frames(good),.O_bad_frames(bad),.O_crc_errors(crc_errors),.O_payload_out(),.O_payload_valid(),.O_payload_keep(),.O_vsync_out(),.O_in_frame(),.O_in_line(),.O_frame_end(),.O_frame_good(),.O_frame_abort(),.O_packet_timeouts(),.O_frame_timeouts(),.O_last_wc(),.O_last_lines());
 always @(posedge clk)begin
  if(rst_n&&valid)$display("FRONTEND t=%0t state=%0d data=%08x done=%b wait=%b",$time,d.state,data,done,ws);
 end
 task fail(input string why);begin $display("INTEGRITY_FAIL frontend %s headers=%0d good=%0d bad=%0d crc=%0d",why,headers,good,bad,crc_errors);$finish;end endtask
 task beat(input[31:0] word);begin @(negedge clk);lanes=word;end endtask
 task tail;begin
  beat(32'hdeadbeef);wait(done);beat(0);repeat(24)@(negedge clk);
 end endtask
 task header(input[7:0] di,input[15:0] wc,input bit corrupt);begin
  wait(ws);h={wc,di};#1;beat(32'hb8b8b8b8);beat({ecc^(corrupt?8'h01:8'h00),h});
 end endtask
 task shortpkt(input[7:0] di,input bit corrupt);begin header(di,7,corrupt);tail();end endtask
 function[7:0] rev8(input[7:0] v);begin for(integer n=0;n<8;n++)rev8[n]=v[7-n];end endfunction
 function[15:0] checksum;
 reg[15:0] c;reg[7:0] b;begin c=16'hffff;
  for(integer n=0;n<20;n++)begin b=rev8(n*13+7);c=c^{b,8'd0};for(integer j=0;j<8;j++)c=(c<<1)^(c[15]?16'h1021:0);end
  for(integer n=0;n<16;n++)checksum[n]=c[15-n];
 end endfunction
 task linepkt(input bit corrupt);reg[15:0] c;reg[31:0] w;begin
  header(8'h2b,20,0);c=checksum()^(corrupt?16'h0001:0);
  for(integer n=0;n<5;n++)begin for(integer j=0;j<4;j++)w[j*8+:8]=(n*4+j)*13+7;beat(w);end
  beat({16'hdead,c});tail();
 end endtask
 task frame(input bit corrupt);begin shortpkt(0,0);linepkt(0);linepkt(corrupt);shortpkt(1,0);end endtask
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
  shortpkt(0,0);
  if(headers!=0||bad!=0)fail("clean FS tail treated as header");
  if(!d.frame_open)fail("FS not received");
  linepkt(0);linepkt(0);shortpkt(1,0);
  if(good!=1||headers!=0||bad!=0||crc_errors!=0)fail("valid complete frame");
  frame(1);if(good!=1||crc_errors!=1||bad!=1||headers!=0)fail("CRC rejection");
  frame(0);if(good!=2||bad!=1||headers!=0)fail("CRC recovery");
  shortpkt(0,0);shortpkt(1,1);if(headers!=1||bad!=2)fail("ECC rejection");
  frame(0);if(good!=3||bad!=2||headers!=1||crc_errors!=1)fail("ECC recovery");
  shortpkt(0,0);linepkt(0);linepkt(0);repeat(4100)@(negedge clk);
  if(good!=3||bad!=3||d.O_frame_timeouts!=1||d.frame_open)fail("missing FE timeout drain");
  frame(0);if(good!=4||bad!=3||headers!=1||crc_errors!=1||d.O_frame_timeouts!=1)fail("timeout recovery");
  $display("INTEGRITY_PASS frontend complete frames=%0d bad=%0d header=%0d crc=%0d",good,bad,headers,crc_errors);$finish;
 end
 initial begin #100000;fail("watchdog");end
endmodule
