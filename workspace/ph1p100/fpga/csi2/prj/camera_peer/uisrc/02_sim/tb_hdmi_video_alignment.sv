`timescale 1ns/1ps
// Test the plaintext RGB/control wrapper boundary; encrypted TMDS core is a stub.
module tb_hdmi_video_alignment;
  reg clk=0,rst=1,de=0,hs=0,vs=0;
  reg [23:0] data=0,previous_data=0;
  reg previous_de=0,previous_hs=0,previous_vs=0;
  wire hdmi_clk;
  wire [2:0] hdmi;
  integer i,checks=0;
  always #5 clk=~clk;
  ui_HDMI_TX #(.DEVICE("PH1P")) dut(clk,clk,rst,data,de,vs,hs,hdmi_clk,hdmi);
  always @(posedge clk) begin
    if(!dut.pixel_rst) begin
      if(dut.u_hdmi_tx_controller_wrapper.I_video_in_data !== previous_data ||
         dut.u_hdmi_tx_controller_wrapper.I_video_in_de !== previous_de ||
         dut.u_hdmi_tx_controller_wrapper.I_video_in_hs !== previous_hs ||
         dut.u_hdmi_tx_controller_wrapper.I_video_in_vs !== previous_vs)
        $fatal(1,"HDMI_ALIGNMENT_FAIL RGB/control sampled from different cycles at %0t",$time);
      checks=checks+1;
    end
    previous_data=dut.pixel_rst?0:data; previous_de=dut.pixel_rst?0:de;
    previous_hs=dut.pixel_rst?0:hs; previous_vs=dut.pixel_rst?0:vs;
  end
  initial begin
    repeat(3) @(negedge clk);rst=0;
    for(i=0;i<41;i=i+1) begin
      data=24'h901234+i*137;de=(i%7<4);hs=(i%7==6);vs=(i%19==0);
      @(negedge clk);
    end
    $display("HDMI_ALIGNMENT_PASS checks=%0d",checks);$finish;
  end
endmodule

module hdmi_tx_controller_wrapper(
 input I_pixel_clk,I_rst,input [23:0] I_video_in_data,
 input I_video_in_vs,I_video_in_hs,I_video_in_de,
 output [9:0] O_ch0_tmds_code_data,O_ch1_tmds_code_data,O_ch2_tmds_code_data,O_clk_tmds_code_data);
 assign O_ch0_tmds_code_data=0;assign O_ch1_tmds_code_data=0;
 assign O_ch2_tmds_code_data=0;assign O_clk_tmds_code_data=0;
endmodule
module hdmi_tx_phy_wrapper #(parameter DEVICE="PH1P")(
 input I_pixel_clk,I_serial_clk,I_rst,input [9:0] I_tmds_channel_0,I_tmds_channel_1,I_tmds_channel_2,I_tmds_channel_clk,
 output O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p);
 assign {O_tmds_ch0_p,O_tmds_ch1_p,O_tmds_ch2_p,O_tmds_clk_p}=0;
endmodule
