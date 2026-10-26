`timescale 1ns/1ps
// Exercise production byte-align, word-align and gearbox feedback with
// byte-aligned D-PHY data. No device I/O primitives/electrical margin model.
module tb_csi_frontend_drain;
 reg clk=0,rst_n=0; always #5 clk=~clk;
 reg[31:0] lanes=0; reg[3:0] lv=0;
 wire[31:0] aw,data; wire av,valid,done,ws;
 wire[31:0] ba;wire[3:0] bv;
 wire[31:0] headers,good,bad,crc_errors; reg[23:0] h=0;wire[7:0] ecc;
 csi_rx_hdr_ecc e(.data(h),.ecc(ecc));
 genvar g;generate for(g=0;g<4;g=g+1)begin: bytes
 csi_rx_byte_align byte_align(.I_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_lan_data_in(lanes[g*8+:8]),.I_wait_for_sync(ws),.I_packet_done(done),.O_data_out_vaild(bv[g]),.O_data_out(ba[g*8+:8]));
 end endgenerate
 csi_rx_word_align #(.MIPI_LAN(4)) align(.I_word_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_packet_done(done),.I_wait_for_sync(ws),.I_word_in(ba),.I_valid_in(bv),.O_word_out(aw),.O_valid_out(av),.O_packet_done_out());
 csi_rx_word_gear_box #(.MIPI_LAN(4)) gear(.I_word_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_lane_data(aw),.I_lane_data_valid(av),.O_word_out(data),.O_valid_out(valid));
 csi_rx_packet_integrity #(.FRAME_TIMEOUT_CYCLES(4096)) d(.I_clock(clk),.I_reset_n(rst_n),.I_enable(1'b1),.I_data(data),.I_data_valid(valid),.O_packet_done(done),.O_sync_wait(ws),.O_header_errors(headers),.O_good_frames(good),.O_bad_frames(bad),.O_crc_errors(crc_errors));
 always @(posedge clk)begin
  if(rst_n&&valid)$display("FRONTEND t=%0t state=%0d data=%08x done=%b wait=%b",$time,d.state,data,done,ws);
 end
 initial begin
  repeat(5)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
  h={16'd7,8'h00};#1;
  // Word align acquires on the sync-valid beat; the following beat is header.
  @(negedge clk);lv=15;lanes=32'hb8b8b8b8;
  @(negedge clk);lanes={ecc,h};
  @(negedge clk);lanes=32'hdeadbeef;
  wait(done);@(negedge clk);lv=0;lanes=0;
  repeat(24)@(negedge clk);
  if(headers!=0||bad!=0)begin $display("INTEGRITY_FAIL frontend: clean FS followed by pipeline tail causes headers=%0d bad=%0d",headers,bad);$finish;end
  if(!d.frame_open)begin $display("INTEGRITY_FAIL frontend: FS not received");$finish;end
  $display("INTEGRITY_PASS frontend clean FS tail drained headers=%0d bad=%0d",headers,bad);$finish;
 end
 initial begin #10000;$display("INTEGRITY_FAIL frontend watchdog");$finish;end
endmodule
