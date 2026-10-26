`timescale 1ps/1fs
module tb_raw10_pll_dynamic;
    reg refclk=0,rst=1;
    always #10000 refclk=~refclk;
    wire c0,c1,c2,locked;
    raw10_clocks dut(.refclk(refclk),.reset(rst),.lock(locked),
        .clk0_out(c0),.clk1_out(c1),.clk2_out(c2));
    real start0,start1,start2,p0,p1,p2;
    initial begin
        #200000;rst=0;
        wait(locked===1);
        #200000;
        fork
            begin @(posedge c0);start0=$realtime;repeat(100) @(posedge c0);p0=($realtime-start0)/100.0;end
            begin @(posedge c1);start1=$realtime;repeat(500) @(posedge c1);p1=($realtime-start1)/500.0;end
            begin @(posedge c2);start2=$realtime;repeat(100) @(posedge c2);p2=($realtime-start2)/100.0;end
        join
        $display("PLL_MEASURE periods_ps=%0.6f,%0.6f,%0.6f MHz=%0.6f,%0.6f,%0.6f",p0,p1,p2,1e6/p0,1e6/p1,1e6/p2);
        if(p0<13466 || p0>13470 || p1<2692 || p1>2695 || p2<37034 || p2>37040)
            $display("PLL_FAIL output frequency");
        else $display("PLL_PASS dynamic vendor model");
        $finish;
    end
    initial begin #100000000; $display("PLL_FAIL lock or clock timeout");$finish;end
endmodule
