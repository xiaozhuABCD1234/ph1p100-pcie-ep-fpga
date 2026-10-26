`timescale 1ns/1ps
module tb_raw10_lane_reset;
    parameter CASE_ID=0;
    reg pclk=0,sclk=0,rst=1;
    always #50 pclk=~pclk;
    always #10 sclk=~sclk;
    wire observed_reset;
    lane_lvds_10_1 #(.DEVICE("PH1P")) dut
        (.I_pixel_clk(pclk),.I_serial_clk(sclk),.I_rst(rst),.I_data_in(10'b0),.O_serial_out(observed_reset));
    initial begin
        repeat(5) @(negedge sclk);
        #3;rst=0;#1;
        if(observed_reset!==1) begin $display("STABLE_FAIL PIXEL asynchronous reset release");$finish;end
        repeat(2) begin
            @(posedge pclk);#1;
            if(observed_reset!==1) begin $display("STABLE_FAIL PIXEL missing reset synchronizer");$finish;end
        end
        @(posedge pclk);#1;
        if(observed_reset!==0) begin $display("STABLE_FAIL PIXEL reset not released");$finish;end
        #3;rst=1;#1;
        if(observed_reset!==1) begin $display("STABLE_FAIL PIXEL reset assertion");$finish;end
        $display("STABLE_PASS PIXEL reset deassertion synchronized");$finish;
    end
endmodule
// This stub observes only the OSERDES reset input, not serialization/electrical behavior.
module PH1P_LOGIC_HR_OSERDES #(parameter ODDRMODE="DDRX1")
    (input sclk,pclk,rst,input [9:0] idata,output odata);
    assign odata=rst;
endmodule
