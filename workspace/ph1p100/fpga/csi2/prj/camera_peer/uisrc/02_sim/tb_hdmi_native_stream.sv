`timescale 1ps/1fs
// Real vendor IO model; require one continuous MSB-first stream, no word skips.
module tb_hdmi_native_stream;
parameter integer PHASE_PS=0;
reg pclk=0,sclk=0,rst=1;
always #1000 sclk=~sclk;
initial begin #(PHASE_PS); forever #5000 pclk=~pclk; end
function [9:0] pattern(input integer n);
    pattern=(n*73)^(n>>2)^10'h2d3;
endfunction
integer word_index=0;
reg [9:0] data=10'h2d3;
always @(negedge pclk) begin
    if(rst) begin word_index=0;data=pattern(0);end
    else begin word_index=word_index+1;data=pattern(word_index);end
end
wire q;
`ifdef PRODUCTION_LANE
lane_lvds_10_1 #(.DEVICE("PH1P")) dut(
`else
lane_lvds_native_x5 dut(
`endif
.I_pixel_clk(pclk),.I_serial_clk(sclk),.I_rst(rst),.I_data_in(data),.O_serial_out(q));
reg actual[0:1799];
reg [9:0] expected;
integer restart,i,j,start,found,bad,checks=0;
initial begin
    for(restart=0;restart<2;restart=restart+1) begin
        rst=1; #40750;rst=0;
        @(posedge sclk);#500;
        for(i=0;i<1800;i=i+1) begin actual[i]=q;#1000;end
        found=-1;
        // Ignore reset fill; find word 8 with a single fixed stream alignment.
        for(start=0;start<300;start=start+1) begin
            bad=0;
            for(j=0;j<1200;j=j+1) begin
                expected=pattern(8+j/10);
                if(actual[start+j]!==expected[9-j%10]) bad=1;
            end
            if(!bad) found=start;
        end
        if(found<0) begin $display("NATIVE_FAIL phase=%0d restart=%0d no continuous MSB-first stream",PHASE_PS,restart);$finish;end
        checks=checks+1200;
    end
    $display("NATIVE_PASS phase=%0d bits=%0d restarts=2",PHASE_PS,checks);$finish;
end
initial begin #5000000;$display("NATIVE_FAIL timeout");$finish;end
endmodule
