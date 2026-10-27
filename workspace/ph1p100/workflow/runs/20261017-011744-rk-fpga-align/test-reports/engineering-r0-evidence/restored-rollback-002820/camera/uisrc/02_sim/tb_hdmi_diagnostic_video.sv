`timescale 1ns/1ps
module tb_hdmi_diagnostic_video;
    parameter DISPLAY_MODE=2;
    localparam MODE_720P60=(DISPLAY_MODE==2);
    localparam HT=MODE_720P60 ? 1650 : 2200, VT=MODE_720P60 ? 750 : 1125;
    localparam HA=MODE_720P60 ? 1280 : 1920, VA=MODE_720P60 ? 720 : 1080;
    localparam HS=MODE_720P60 ? 1390 : 2008, HE=MODE_720P60 ? 1430 : 2052;
    localparam VS=MODE_720P60 ? 725 : 1084, VE=MODE_720P60 ? 730 : 1089;
    reg sys_clk50m=0;
    always #10 sys_clk50m=~sys_clk50m;
    wire clkout;
    wire [2:0] pins;
    hdmi_diagnostic_top #(.DISPLAY_MODE(DISPLAY_MODE),.POWER_BITS(4)) dut
        (.sys_clk50m(sys_clk50m),.O_hdmi_clk_p(clkout),.O_hdmi_tx_p(pins));
    integer x,y,n,active=0,nonblack=0;
    initial begin
        wait(pins[1]===1);wait(pins[1]===0);wait(pins[0]===1);@(negedge dut.pclk);
        x=0;y=0;
        for(n=0;n<HT*VT;n=n+1) begin
            if(pins !== { (x>=HS && x<HE),(y>=VS && y<VE),(x<HA && y<VA)}) begin
                $display("DIAG_FAIL mode=%0d x=%0d y=%0d controls=%b",DISPLAY_MODE,x,y,pins);$finish;
            end
            if(pins[0]) begin
                active=active+1;
                if(dut.tx.I_video_in_data!==24'hFF0000 && dut.tx.I_video_in_data!==24'h00FFFF) begin
                    $display("DIAG_FAIL active color=%h",dut.tx.I_video_in_data);$finish;
                end
                nonblack=nonblack+1;
            end
            if(x==HT-1) begin x=0;y=y+1;end else x=x+1;
            @(negedge dut.pclk);
        end
        if(active!=HA*VA || nonblack!=active) begin $display("DIAG_FAIL totals");$finish;end
        $display("DIAG_PASS mode=%0d cycles=%0d active=%0d nonblack=%0d",DISPLAY_MODE,HT*VT,active,nonblack);
        $finish;
    end
    initial begin #60000000;$display("DIAG_FAIL timeout");$finish;end
endmodule
// These stubs validate top-level VTC/RGB/control alignment only.
// Real output primitive is tested separately by tb_hdmi_serial_clock.
module hdmi_diagnostic_clocks #(parameter FULL_RATE=0)
    (input refclk,reset,output reg clk0_out=0,clk1_out=0,output lock);
    assign lock=!reset;
    always #5 clk0_out=~clk0_out;
    always #1 clk1_out=~clk1_out;
endmodule
module ui_HDMI_TX #(parameter DEVICE="PH1P")
    (input I_pixel_clk,I_serial_clk,I_rst,input [23:0] I_video_in_data,
     input I_video_in_de,I_video_in_vs,I_video_in_hs,output O_hdmi_clk_p,output [2:0] O_hdmi_tx_p);
    assign O_hdmi_clk_p=I_pixel_clk;
    assign O_hdmi_tx_p={I_video_in_hs,I_video_in_vs,I_video_in_de};
endmodule
