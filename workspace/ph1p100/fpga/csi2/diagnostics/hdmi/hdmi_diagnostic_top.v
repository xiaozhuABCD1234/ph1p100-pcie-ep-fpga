`timescale 1ns/1ps
// Isolated display probe: 0=1080p30, 1=1080p60, 2=720p60.
// No camera, DDR, PCIe or runtime source switch participates in this build.
module hdmi_diagnostic_top #(
    parameter DISPLAY_MODE=2,
    parameter POWER_BITS=16
)(input sys_clk50m,output O_hdmi_clk_p,output [2:0] O_hdmi_tx_p);
    reg [POWER_BITS-1:0] power_count=0;
    always @(posedge sys_clk50m)
        if(!(&power_count)) power_count<=power_count+1'b1;
    wire pclk,sclk,locked;
    hdmi_diagnostic_clocks #(.FULL_RATE(DISPLAY_MODE==1)) X_ui_pll
        (.refclk(sys_clk50m),.reset(!(&power_count)),.lock(locked),
         .clk0_out(pclk),.clk1_out(sclk));
    reg [2:0] reset_pipe=0;
    always @(posedge pclk or negedge locked)
        if(!locked) reset_pipe<=0;else reset_pipe<={reset_pipe[1:0],1'b1};
    wire rstn=reset_pipe[2];
    localparam SMALL=(DISPLAY_MODE==2);
    wire hs,vs,de;
    uivtc #(.H_ActiveSize(SMALL?1280:1920),.H_FrameSize(SMALL?1650:2200),
        .H_SyncStart(SMALL?1390:2008),.H_SyncEnd(SMALL?1430:2052),
        .V_ActiveSize(SMALL?720:1080),.V_FrameSize(SMALL?750:1125),
        .V_SyncStart(SMALL?725:1084),.V_SyncEnd(SMALL?730:1089)) vtc
        (.I_vtc_clk(pclk),.I_vtc_rstn(rstn),.O_vtc_hs(hs),.O_vtc_vs(vs),
         .O_vtc_de_valid(de),.O_vtc_user(),.O_vtc_last());
    reg [10:0] x=0;
    reg [23:0] rgb=0;
    reg hs_d=0,vs_d=0,de_d=0;
    always @(posedge pclk) begin
        if(!rstn) begin x<=0;rgb<=0;hs_d<=0;vs_d<=0;de_d<=0;end
        else begin
            x<=de ? x+1'b1 : 11'd0;
            rgb<=x[7] ? 24'hFF0000 : 24'h00FFFF;
            hs_d<=hs;vs_d<=vs;de_d<=de;
        end
    end
    ui_HDMI_TX #(.DEVICE("PH1P")) tx
        (.I_pixel_clk(pclk),.I_serial_clk(sclk),.I_rst(!locked),
         .I_video_in_data(rgb),.I_video_in_de(de_d),.I_video_in_vs(vs_d),.I_video_in_hs(hs_d),
         .O_hdmi_clk_p(O_hdmi_clk_p),.O_hdmi_tx_p(O_hdmi_tx_p));
endmodule
