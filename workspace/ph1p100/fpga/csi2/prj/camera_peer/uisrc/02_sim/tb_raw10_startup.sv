`timescale 1ns/1ps
module tb_raw10_startup;
    parameter CASE_ID=0;
    reg clk=0,mclk=0,locked=0;
    always #10 clk=~clk;
    always #18.5185 mclk=~mclk;
    wire xclr,camclk,cfg;
    camera_startup #(.POWER_WAIT_CYCLES(16),.MCLK_WAIT_CYCLES(50),.CFG_WAIT_CYCLES(1000)) dut
       (.I_clk(clk),.I_pll_locked(locked),.I_mclk(mclk),
        .O_xclr_n(xclr),.O_mclk(camclk),.O_cfg_rst_n(cfg));
    time released,first_clock;
    integer pulses=0;
    always @(posedge camclk) begin
        pulses=pulses+1;
        if(!xclr || $time-released<1000) begin $display("STABLE_FAIL MCLK early");$finish;end
        if(pulses==1) first_clock=$time;
    end
    initial begin
        repeat(12) @(negedge clk);
        if({xclr,camclk,cfg}!==0) begin $display("STABLE_FAIL startup unlocked");$finish;end
        locked=1;wait(xclr);released=$time;
        wait(cfg);
        if($time-released<20000 || pulses==0) begin $display("STABLE_FAIL config early");$finish;end
        @(negedge clk);locked=0;#1;
        if(xclr || cfg) begin $display("STABLE_FAIL lock loss reset");$finish;end
        repeat(6) @(negedge mclk);
        if(camclk) begin $display("STABLE_FAIL lock loss clock gate");$finish;end
        pulses=0;
        locked=1;wait(xclr);released=$time;wait(cfg);
        $display("STABLE_PASS STARTUP pulses=%0d",pulses);$finish;
    end
    initial begin #100000;$display("STABLE_FAIL startup timeout");$finish;end
endmodule
