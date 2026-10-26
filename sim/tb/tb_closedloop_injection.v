`timescale 1ns/1ps
module tb_closedloop_injection;
    reg clk=0;always #2.666 clk=~clk;
    reg rst_n=0,vs=0;reg [31:0] good=0;
    integer pulses=0,errors=0;
    ph1p_pcie_ep_top #(.DBG_CTRL_DEFAULT_EN(1),.CLOSEDLOOP_EN(1)) dut();
    initial begin
        force dut.w_a_byte_clk=clk;force dut.w_a_rst_out=rst_n;force dut.w_a_vsync=vs;
        force dut.w_a_good_frm=good;force dut.w_a_frame_abort=0;force dut.w_a_frame_end=0;
    end
    always @(posedge clk)if(rst_n&&dut.cl_inject_abort)begin
        pulses=pulses+1;
        if(!dut.u_cam_r10f_writer.cam_frame_abort||!dut.g_closedloop.u_algo.cam_abort)errors=errors+1;
    end
    task sof;begin @(negedge clk);vs=1;@(negedge clk);vs=0;repeat(5)@(negedge clk);end endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;sof();good=1;sof();
        if(pulses!=0)errors=errors+1;good=2;sof();
        if(pulses!=1||dut.g_closedloop.source_injected!=1)errors=errors+1;
        good=3;sof();good=4;sof();if(pulses!=1)errors=errors+1;
        if(errors==0)$display("INJECTION_PASS pulses=%0d source_injected=%0d",pulses,dut.g_closedloop.source_injected);else $display("INJECTION_FAIL errors=%0d",errors);
        $finish;
    end
endmodule
