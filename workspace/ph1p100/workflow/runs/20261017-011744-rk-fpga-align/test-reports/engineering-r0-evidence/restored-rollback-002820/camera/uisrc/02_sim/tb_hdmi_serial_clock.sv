`timescale 1ps/1fs
// Uses the real PH1P_LOGIC_HR_OSERDES library; no behavioral replacement.
module tb_hdmi_serial_clock;
    parameter integer PHASE_PS=0;
    reg pclk=0,sclk=0,rst=1;
    always #1000 sclk=~sclk;
    initial begin
        #(PHASE_PS);
        forever #5000 pclk=~pclk;
    end
    wire q;
    lane_lvds_10_1 #(.DEVICE("PH1P")) dut
        (.I_pixel_clk(pclk),.I_serial_clk(sclk),.I_rst(rst),
         .I_data_in(10'b0000011111),.O_serial_out(q));
    reg [9:0] samples,reference,first_word;
    reg found;
    integer restart,n,k,r,checks=0;
    task fail(input [255:0] why);
        begin
            $display("SERIAL_FAIL phase=%0d restart=%0d n=%0d bits=%b %0s",PHASE_PS,restart,n,samples,why);
            $finish;
        end
    endtask
    initial begin
        for(restart=0;restart<2;restart=restart+1) begin
            rst=1; #40750; rst=0;
            repeat(12) @(posedge pclk);
            // First sample is the middle of a serial half-cycle, then 1ns apart.
            @(posedge sclk); #500;
            for(n=0;n<32;n=n+1) begin
                for(k=0;k<10;k=k+1) begin
                    if(q!==0 && q!==1) fail("unknown serial output");
                    samples[k]=q;
                    #1000;
                end
                found=0;
                reference=10'b0000011111;
                for(r=0;r<10;r=r+1) begin
                    if(samples===reference) found=1;
                    reference={reference[8:0],reference[9]};
                end
                if(!found) fail("not a five-low five-high clock");
                if(n==0) first_word=samples;
                else if(samples!==first_word) fail("clock word phase changed between periods");
                checks=checks+1;
            end
        end
        $display("SERIAL_PASS phase=%0d words=%0d restarts=2",PHASE_PS,checks);
        $finish;
    end
    initial begin #2000000; fail("timeout");end
endmodule
